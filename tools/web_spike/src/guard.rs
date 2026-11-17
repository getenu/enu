//! Panics stop at the C interface. Every exported function runs inside
//! `guard`: a panic (a Blitz bug, a bad node id) becomes an error the caller
//! picks up with `ew_take_error`, instead of taking down the host. The page
//! the panic happened in may be half-changed, so it refuses further calls
//! until its HTML is set again.

use std::cell::{Cell, RefCell};
use std::ffi::{CString, c_char};
use std::panic::{self, AssertUnwindSafe};
use std::sync::Once;

use crate::View;

pub trait FfiDefault {
    fn ffi_default() -> Self;
}

impl FfiDefault for () {
    fn ffi_default() {}
}

macro_rules! zero_default {
    ($($t:ty),*) => {
        $(impl FfiDefault for $t {
            fn ffi_default() -> Self {
                Default::default()
            }
        })*
    };
}

zero_default!(bool, u32, u64, usize, i64, f32);

impl<T> FfiDefault for *const T {
    fn ffi_default() -> Self {
        std::ptr::null()
    }
}

impl<T> FfiDefault for *mut T {
    fn ffi_default() -> Self {
        std::ptr::null_mut()
    }
}

thread_local! {
    static PANIC_MESSAGE: RefCell<String> = const { RefCell::new(String::new()) };
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
    static TAKEN_ERROR: RefCell<CString> = RefCell::new(CString::default());
    static CURRENT_VIEW: Cell<*mut View> = const { Cell::new(std::ptr::null_mut()) };
}

fn install_hook() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let previous = panic::take_hook();
        panic::set_hook(Box::new(move |info| {
            PANIC_MESSAGE.with(|m| *m.borrow_mut() = info.to_string());
            previous(info);
        }));
    });
}

/// A mistake by the caller (a node id that doesn't exist) found before
/// anything changed. Reported like a panic, but the page isn't marked broken.
pub struct CallerError(pub String);

/// Fails the current call with `message`, leaving the page usable.
pub fn caller_error(message: String) -> ! {
    std::panic::resume_unwind(Box::new(CallerError(message)))
}

/// Runs `f`, turning a panic into a stored error and a default result.
pub fn guard<R: FfiDefault>(f: impl FnOnce() -> R) -> R {
    install_hook();
    CURRENT_VIEW.set(std::ptr::null_mut());
    match panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(payload) => {
            let message = match payload.downcast::<CallerError>() {
                Ok(e) => e.0,
                Err(_) => {
                    let v = CURRENT_VIEW.get();
                    if !v.is_null() {
                        unsafe { (*v).poisoned = true };
                    }
                    PANIC_MESSAGE.with(|m| m.take())
                }
            };
            let message = CString::new(message.replace('\0', "")).unwrap_or_default();
            LAST_ERROR.with(|e| *e.borrow_mut() = Some(message));
            R::ffi_default()
        }
    }
}

/// Remembers which page the current call is using, so a panic can mark it.
pub(crate) fn note_view(v: *mut View) {
    CURRENT_VIEW.set(v);
}

/// The error from the last call on this thread that panicked, or null.
/// Clears it. Valid until the next call to this function.
#[unsafe(no_mangle)]
pub extern "C" fn ew_take_error() -> *const c_char {
    match LAST_ERROR.with(|e| e.borrow_mut().take()) {
        Some(message) => TAKEN_ERROR.with(|t| {
            *t.borrow_mut() = message;
            t.borrow().as_ptr()
        }),
        None => std::ptr::null(),
    }
}
