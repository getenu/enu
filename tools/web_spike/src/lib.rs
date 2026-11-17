//! A small C interface over Blitz for rendering HTML into an RGBA buffer.
//! Nothing here knows about Godot. Node ids are Blitz `NodeId`s as `u64`;
//! 0 means "none".

mod canvas;
mod guard;
mod hub;

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char};
use std::rc::Rc;

use anyrender::ImageRenderer;
use anyrender_vello_cpu::VelloCpuImageRenderer;
use blitz_dom::{
    BaseDocument, DocumentConfig, LocalName, NodeId, QualName, ns,
};
use blitz_html::HtmlDocument;
use blitz_traits::shell::{ColorScheme, Viewport};

pub struct View {
    doc: BaseDocument,
    renderer: VelloCpuImageRenderer,
    width: u32,
    height: u32,
    scale: f32,
    pixels: Vec<u8>,
    canvases: HashMap<u64, canvas::Handle>,
    text: Rc<RefCell<canvas::Text>>,
    pressed: Option<NodeId>,
    out: CString,
    poisoned: bool,
}

fn viewport(width: u32, height: u32, scale: f32) -> Viewport {
    Viewport::new(width, height, scale, ColorScheme::Light)
}

fn parse(html: &str, width: u32, height: u32, scale: f32) -> BaseDocument {
    let config = DocumentConfig {
        viewport: Some(viewport(width, height, scale)),
        ..Default::default()
    };
    HtmlDocument::from_html(html, config).into_inner()
}

pub(crate) unsafe fn str_arg<'a>(s: *const c_char) -> &'a str {
    assert!(!s.is_null());
    unsafe { CStr::from_ptr(s) }.to_str().expect("utf-8")
}

/// The page behind `v`, refusing pages broken by an earlier panic.
pub(crate) unsafe fn view<'a>(v: *mut View) -> &'a mut View {
    let v = unsafe { view_any(v) };
    if v.poisoned {
        panic!("this page stopped working after an earlier error; set its html again");
    }
    v
}

/// The page behind `v`, even if an earlier panic broke it.
unsafe fn view_any<'a>(v: *mut View) -> &'a mut View {
    assert!(!v.is_null());
    guard::note_view(v);
    unsafe { &mut *v }
}

/// Fails the call (without breaking the page) unless every id is a node.
fn check_nodes(doc: &BaseDocument, ids: &[u64]) {
    for &n in ids {
        if doc.get_node(id(n)).is_none() {
            guard::caller_error(format!(
                "no element {n} on this page (it wasn't found, or was removed)"
            ));
        }
    }
}

fn id(n: u64) -> NodeId {
    NodeId::from_u64(n)
}

fn html_name(tag: &str) -> QualName {
    QualName::new(None, ns!(html), LocalName::from(tag))
}

/// `width` and `height` are physical pixels. `scale` is the hidpi scale, so
/// the CSS viewport is `width / scale` by `height / scale`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_view_new(
    html: *const c_char,
    width: u32,
    height: u32,
    scale: f32,
) -> *mut View {
    crate::guard::guard(move || {
        let html = unsafe { str_arg(html) };
        let mut doc = parse(html, width, height, scale);
        doc.resolve(0.0);
        Box::into_raw(Box::new(View {
            doc,
            renderer: VelloCpuImageRenderer::new(width, height),
            width,
            height,
            scale,
            pixels: Vec::new(),
            canvases: HashMap::new(),
            text: Rc::new(RefCell::new(canvas::Text::new())),
            pressed: None,
            out: CString::default(),
            poisoned: false,
        }))
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_view_free(v: *mut View) {
    crate::guard::guard(move || {
        if !v.is_null() {
            drop(unsafe { Box::from_raw(v) });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_set_html(v: *mut View, html: *const c_char) {
    crate::guard::guard(move || {
        let v = unsafe { view_any(v) };
        let html = unsafe { str_arg(html) };
        v.doc = parse(html, v.width, v.height, v.scale);
        v.canvases.clear();
        v.pressed = None;
        v.poisoned = false;
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_resize(v: *mut View, width: u32, height: u32) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        v.width = width;
        v.height = height;
        v.doc.set_viewport(viewport(width, height, v.scale));
        v.renderer.resize(width, height);
    })
}

/// Lays out the document and draws it. Returns a pointer to `width * height`
/// RGBA8 pixels (premultiplied alpha), valid until the next call on this view.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_render(v: *mut View) -> *const u8 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        v.doc.resolve(0.0);
        let (w, h, scale) = (v.width, v.height, v.scale as f64);
        let doc = &mut v.doc;
        v.pixels.clear();
        v.renderer.render_to_vec(
            |scene| blitz_paint::paint_scene(scene, doc, scale, w, h, 0, 0),
            &mut v.pixels,
        );
        v.pixels.as_ptr()
    })
}

/// Height of the laid-out content in physical pixels, for sizing a sign to
/// fit its text.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_content_height(v: *mut View) -> f32 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        v.doc.resolve(0.0);
        let root = v.doc.root_element();
        let layout = root.final_layout();
        layout.size.height.max(layout.scrollable_overflow_rect.bottom) * v.scale
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_query(v: *mut View, selector: *const c_char) -> u64 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        let selector = unsafe { str_arg(selector) };
        match v.doc.query_selector(selector) {
            Ok(Some(n)) => n.as_u64(),
            _ => 0,
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_create_element(v: *mut View, tag: *const c_char) -> u64 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        let tag = unsafe { str_arg(tag) };
        v.doc.mutate().create_element(html_name(tag), vec![]).as_u64()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_create_text(v: *mut View, text: *const c_char) -> u64 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        let text = unsafe { str_arg(text) };
        v.doc.mutate().create_text_node(text).as_u64()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_set_attribute(
    v: *mut View,
    node: u64,
    name: *const c_char,
    value: *const c_char,
) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        let (name, value) = unsafe { (str_arg(name), str_arg(value)) };
        v.doc
            .mutate()
            .set_attribute(id(node), QualName::new(None, ns!(), LocalName::from(name)), value);
    })
}

/// Removes `node`'s children one at a time. Blitz's
/// `remove_and_drop_all_children` doesn't mark the parent's layout damaged
/// (`remove_and_drop_node` does), so a node emptied that way and not given
/// new children keeps stale layout children, and the next layout panics.
fn clear_children(doc: &mut BaseDocument, node: NodeId) {
    let children = doc.get_node(node).map(|n| n.children.clone()).unwrap_or_default();
    let mut m = doc.mutate();
    for child in children {
        m.remove_and_drop_node(child);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_set_text(v: *mut View, node: u64, text: *const c_char) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        let text = unsafe { str_arg(text) };
        let is_element = v.doc.get_node(id(node)).is_some_and(|n| n.is_element());
        if is_element {
            clear_children(&mut v.doc, id(node));
        }
        let mut m = v.doc.mutate();
        if is_element {
            // Like `textContent =`: replace the children with one text node.
            let t = m.create_text_node(text);
            m.append_children(id(node), &[t]);
        } else {
            m.set_node_text(id(node), text);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_set_inner_html(v: *mut View, node: u64, html: *const c_char) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        let html = unsafe { str_arg(html) };
        clear_children(&mut v.doc, id(node));
        v.doc.mutate().set_inner_html(id(node), html);
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_append(v: *mut View, parent: u64, child: u64) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[parent, child]);
        v.doc.mutate().append_children(id(parent), &[id(child)]);
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_remove(v: *mut View, node: u64) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        v.doc.mutate().remove_and_drop_node(id(node));
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_parent(v: *mut View, node: u64) -> u64 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        v.doc
            .get_node(id(node))
            .and_then(|n| n.parent)
            .map_or(0, |p| p.as_u64())
    })
}

/// The element under a point in physical pixels, or 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_element_at(v: *mut View, x: f32, y: f32) -> u64 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        v.doc.resolve(0.0);
        let s = v.scale;
        v.doc.element_from_point(x / s, y / s).map_or(0, |n| n.as_u64())
    })
}

/// Writes `value` of attribute `name` on `node` into `buf` (NUL-terminated,
/// truncated to `len`). Returns the full length, or -1 if absent.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_get_attribute(
    v: *mut View,
    node: u64,
    name: *const c_char,
    buf: *mut u8,
    len: usize,
) -> i64 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        let name = unsafe { str_arg(name) };
        let Some(el) = v.doc.get_node(id(node)).and_then(|n| n.element_data()) else {
            return -1;
        };
        let Some(value) = el.attr(LocalName::from(name)) else {
            return -1;
        };
        if len > 0 {
            let bytes = value.as_bytes();
            let n = bytes.len().min(len - 1);
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, n);
                *buf.add(n) = 0;
            }
        }
        value.len() as i64
    })
}

/// Writes the last rendered frame to a PNG. For tests and the spike harness.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_write_png(v: *mut View, path: *const c_char) -> bool {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        let path = unsafe { str_arg(path) };
        let mut rgba = v.pixels.clone();
        for px in rgba.chunks_exact_mut(4) {
            let a = px[3] as u32;
            if a != 0 && a != 255 {
                for c in &mut px[..3] {
                    *c = ((*c as u32 * 255 + a / 2) / a).min(255) as u8;
                }
            }
        }
        let Ok(file) = std::fs::File::create(path) else {
            return false;
        };
        let mut enc = png::Encoder::new(std::io::BufWriter::new(file), v.width, v.height);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        enc.write_header()
            .and_then(|mut w| w.write_image_data(&rgba))
            .is_ok()
    })
}

// --- canvas ----------------------------------------------------------------
//
// Colors are 0xRRGGBBAA. Coordinates are CSS px within the canvas element.

/// Makes `node` (normally a `<canvas>`) draw the commands recorded below.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_canvas_attach(v: *mut View, node: u64) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        let state = canvas::Handle::default();
        let widget = canvas::CanvasWidget { state: state.clone(), text: v.text.clone() };
        v.doc.mutate().set_custom_widget(id(node), Box::new(widget));
        v.canvases.insert(node, state);
    })
}

fn canvas<'a>(v: &'a mut View, node: u64) -> std::cell::RefMut<'a, canvas::CanvasState> {
    v.canvases.get(&node).expect("ew_canvas_attach first").borrow_mut()
}

macro_rules! canvas_fn {
    ($name:ident, $method:ident $(, $arg:ident : $ty:ty)*) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(v: *mut View, node: u64 $(, $arg: $ty)*) {
            crate::guard::guard(move || {
                let v = unsafe { view(v) };
                canvas(v, node).$method($($arg),*);
            })
        }
    };
}

canvas_fn!(ew_canvas_clear, clear);
canvas_fn!(ew_canvas_begin_path, begin_path);
canvas_fn!(ew_canvas_move_to, move_to, x: f64, y: f64);
canvas_fn!(ew_canvas_line_to, line_to, x: f64, y: f64);
canvas_fn!(ew_canvas_quad_to, quad_to, cx: f64, cy: f64, x: f64, y: f64);
canvas_fn!(ew_canvas_cubic_to, cubic_to, c1x: f64, c1y: f64, c2x: f64, c2y: f64, x: f64, y: f64);
canvas_fn!(ew_canvas_close_path, close_path);
canvas_fn!(ew_canvas_fill, fill, color: u32);
canvas_fn!(ew_canvas_stroke, stroke, color: u32, width: f64);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_canvas_fill_text(
    v: *mut View,
    node: u64,
    text: *const c_char,
    x: f64,
    y: f64,
    size: f32,
    color: u32,
    bold: bool,
) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        let text = unsafe { str_arg(text) };
        canvas(v, node).fill_text(text, x, y, size, color, bold);
    })
}

/// Advance width of `text` in CSS px, like measureText().width.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_measure_text(
    v: *mut View,
    text: *const c_char,
    size: f32,
    bold: bool,
) -> f32 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        let text = unsafe { str_arg(text) };
        v.text.borrow_mut().measure(text, size, bold)
    })
}

pub const EW_POINTER_MOVE: u32 = 0;
pub const EW_POINTER_DOWN: u32 = 1;
pub const EW_POINTER_UP: u32 = 2;
pub const EW_POINTER_LEAVE: u32 = 3;

fn is_ancestor(doc: &BaseDocument, ancestor: NodeId, mut node: NodeId) -> bool {
    loop {
        if node == ancestor {
            return true;
        }
        match doc.get_node(node).and_then(|n| n.parent) {
            Some(p) => node = p,
            None => return false,
        }
    }
}

/// Feeds a pointer event at (x, y) physical pixels to the page, updating
/// `:hover` and `:active`. Sets `changed` when that needs a redraw. Returns
/// the clicked element when this completes a click (press and release on
/// the same element, or one inside the other), else 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_pointer(
    v: *mut View,
    kind: u32,
    x: f32,
    y: f32,
    changed: *mut bool,
) -> u64 {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        v.doc.resolve(0.0);
        let (x, y) = (x / v.scale, y / v.scale);
        let mut dirty;
        let mut clicked = 0;
        match kind {
            EW_POINTER_MOVE => dirty = v.doc.set_hover_to(x, y),
            EW_POINTER_DOWN => {
                dirty = v.doc.set_hover_to(x, y);
                dirty |= v.doc.active_node();
                v.pressed = v.doc.get_hover_node_id();
            }
            EW_POINTER_UP => {
                dirty = v.doc.set_hover_to(x, y);
                dirty |= v.doc.unactive_node();
                if let (Some(p), Some(h)) = (v.pressed.take(), v.doc.get_hover_node_id()) {
                    if is_ancestor(&v.doc, p, h) {
                        clicked = p.as_u64();
                    } else if is_ancestor(&v.doc, h, p) {
                        clicked = h.as_u64();
                    }
                }
            }
            _ => {
                dirty = v.doc.clear_hover();
                dirty |= v.doc.unactive_node();
                v.pressed = None;
            }
        }
        if !changed.is_null() {
            unsafe { *changed = dirty };
        }
        clicked
    })
}

/// The text inside `node`, like `textContent`. Valid until the next call
/// that returns a string on this view.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_get_text(v: *mut View, node: u64) -> *const c_char {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        let text = v.doc.get_node(id(node)).map(|n| n.text_content()).unwrap_or_default();
        v.out = CString::new(text.replace('\0', "")).unwrap();
        v.out.as_ptr()
    })
}

/// Writes x, y, width, height of `node`'s box in CSS pixels, relative to the
/// page, into `out`. Lays the page out first, so the answer is current.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_rect(v: *mut View, node: u64, out: *mut f32) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        v.doc.resolve(0.0);
        let r = match v.doc.get_node(id(node)) {
            Some(n) => {
                let p = n.absolute_position(0.0, 0.0);
                let size = n.final_layout().size;
                [p.x, p.y, size.width, size.height]
            }
            None => [0.0; 4],
        };
        unsafe { std::ptr::copy_nonoverlapping(r.as_ptr(), out, 4) };
    })
}

/// Inserts `node` just before `anchor`, under the same parent.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_insert_before(v: *mut View, anchor: u64, node: u64) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[anchor, node]);
        v.doc.mutate().insert_nodes_before(id(anchor), &[id(node)]);
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ew_remove_attribute(v: *mut View, node: u64, name: *const c_char) {
    crate::guard::guard(move || {
        let v = unsafe { view(v) };
        check_nodes(&v.doc, &[node]);
        let name = unsafe { str_arg(name) };
        v.doc
            .mutate()
            .clear_attribute(id(node), QualName::new(None, ns!(), LocalName::from(name)));
    })
}
