//! Moving pages between threads. A page (`View`) lives on one thread, the
//! one its script runs on. That thread records what the page looks like
//! (`ew_present`) and the render thread turns the recording into pixels. The
//! thread that shows the page (Godot's main thread) picks up finished frames
//! and posts pointer events back, by key. Keys are whatever the caller uses to
//! name a page; Enu uses the sign's id.

use std::collections::HashMap;
use std::ffi::c_char;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Instant;

use anyrender::{ImageRenderer, PaintScene, Scene};
use anyrender_vello_cpu::VelloCpuImageRenderer;
use kurbo::Affine;

use crate::{View, str_arg, view};

pub struct Frame {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
    pub render_ms: f32,
}

#[derive(Default)]
struct Slot {
    frame: Option<Arc<Frame>>,
    version: u64,
    pointer: Vec<[f32; 3]>,
}

static SLOTS: LazyLock<Mutex<HashMap<String, Slot>>> = LazyLock::new(Default::default);

struct Job {
    key: String,
    scene: Scene,
    width: u32,
    height: u32,
}

static JOBS: LazyLock<Mutex<Sender<Job>>> = LazyLock::new(|| {
    let (tx, rx) = channel();
    std::thread::Builder::new()
        .name("enu-web-render".into())
        .spawn(move || render_loop(rx))
        .expect("render thread");
    Mutex::new(tx)
});

fn render_loop(rx: Receiver<Job>) {
    let mut renderer = VelloCpuImageRenderer::new(1, 1);
    while let Ok(job) = rx.recv() {
        // Only the newest recording of each page is worth drawing.
        let mut jobs = vec![job];
        while let Ok(j) = rx.try_recv() {
            match jobs.iter_mut().find(|p| p.key == j.key) {
                Some(p) => *p = j,
                None => jobs.push(j),
            }
        }
        for job in jobs {
            let start = Instant::now();
            renderer.resize(job.width, job.height);
            let mut pixels = Vec::new();
            let scene = job.scene;
            let drawn = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                renderer.render_to_vec(|p| p.append_scene(scene, Affine::IDENTITY), &mut pixels)
            }));
            if drawn.is_ok() {
                crate::unpremultiply(&mut pixels);
            }
            if drawn.is_err() {
                // Skip the frame. The page shows its last good one.
                renderer = VelloCpuImageRenderer::new(1, 1);
                continue;
            }
            let frame = Frame {
                width: job.width,
                height: job.height,
                pixels,
                render_ms: start.elapsed().as_secs_f32() * 1000.0,
            };
            let mut slots = SLOTS.lock().unwrap();
            let slot = slots.entry(job.key).or_default();
            slot.frame = Some(Arc::new(frame));
            slot.version += 1;
        }
    }
}

/// Lays out the page, records it, and queues it for the render thread.
/// Returns the time spent on this thread, in ms.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_present(v: *mut View, key: *const c_char) -> f32 {
    crate::guard::guard(move || {
        let start = Instant::now();
        let v = unsafe { view(v) };
        let key = unsafe { str_arg(key) }.to_owned();
        v.doc.resolve(0.0);
        let mut scene = Scene::new();
        let (w, h) = (v.width, v.height);
        blitz_paint::paint_scene(&mut scene, &mut v.doc, v.scale as f64, w, h, 0, 0);
        let job = Job { key, scene, width: w, height: h };
        JOBS.lock().unwrap().send(job).expect("render thread alive");
        start.elapsed().as_secs_f32() * 1000.0
    })
}

/// The newest finished frame for `key` if it's newer than `since`, else
/// null. Writes its version to `version`. Frames stay in the hub, so a
/// newly created sign can ask again with `since = 0`. Free with
/// `ew_frame_free`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_take_frame(
    key: *const c_char,
    since: u64,
    version: *mut u64,
) -> *const Frame {
    crate::guard::guard(move || {
        let key = unsafe { str_arg(key) };
        let slots = SLOTS.lock().unwrap();
        match slots.get(key) {
            Some(Slot { frame: Some(f), version: v, .. }) if *v > since => {
                unsafe { *version = *v };
                Arc::into_raw(f.clone())
            }
            _ => std::ptr::null(),
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_frame_width(f: *const Frame) -> u32 {
    crate::guard::guard(move || {
        unsafe { &*f }.width
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_frame_height(f: *const Frame) -> u32 {
    crate::guard::guard(move || {
        unsafe { &*f }.height
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_frame_render_ms(f: *const Frame) -> f32 {
    crate::guard::guard(move || {
        unsafe { &*f }.render_ms
    })
}

/// Straight-alpha RGBA8, `width * height * 4` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_frame_pixels(f: *const Frame) -> *const u8 {
    crate::guard::guard(move || {
        unsafe { &*f }.pixels.as_ptr()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_frame_free(f: *const Frame) {
    crate::guard::guard(move || {
        if !f.is_null() {
            drop(unsafe { Arc::from_raw(f) });
        }
    })
}

/// Queues a pointer event for the page named `key`. `u` and `v` run 0..1
/// across and down the page. Kinds are `EW_POINTER_*`. Ignored unless `key`
/// has presented a page. Returns whether it was queued.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_post_pointer(key: *const c_char, kind: u32, u: f32, v: f32) -> bool {
    crate::guard::guard(move || {
        let key = unsafe { str_arg(key) };
        let mut slots = SLOTS.lock().unwrap();
        let Some(slot) = slots.get_mut(key) else { return false };
        // A run of moves only needs the last one.
        if kind == 0 && slot.pointer.last().is_some_and(|p| p[0] == 0.0) {
            slot.pointer.pop();
        }
        slot.pointer.push([kind as f32, u, v]);
        true
    })
}

/// Moves up to `max` queued pointer events into `out` as (kind, u, v)
/// triples. Returns how many.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_take_pointer(key: *const c_char, out: *mut f32, max: usize) -> usize {
    crate::guard::guard(move || {
        let key = unsafe { str_arg(key) };
        let mut slots = SLOTS.lock().unwrap();
        let Some(slot) = slots.get_mut(key) else { return 0 };
        let n = slot.pointer.len().min(max);
        for (i, p) in slot.pointer.drain(..n).enumerate() {
            unsafe { std::ptr::copy_nonoverlapping(p.as_ptr(), out.add(i * 3), 3) };
        }
        n
    })
}

/// Drops anything waiting for `key`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_forget(key: *const c_char) {
    crate::guard::guard(move || {
        let key = unsafe { str_arg(key) };
        SLOTS.lock().unwrap().remove(key);
    })
}

/// Drops the finished frame kept for `key` (a few MB) but keeps the page
/// known, so pointer events still reach it. A sign that needs the picture
/// again asks with `EW_POINTER_WAKE`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_drop_frame(key: *const c_char) {
    crate::guard::guard(move || {
        let key = unsafe { str_arg(key) };
        if let Some(slot) = SLOTS.lock().unwrap().get_mut(key) {
            slot.frame = None;
        }
    })
}
