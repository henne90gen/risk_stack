// Platform-neutral key constants.
// Values match JS KeyboardEvent.keyCode so the wasm host can pass raw JS
// keycodes straight through to Zig without any translation layer.

pub const KEY_BACKSPACE: c_uint = 8;
pub const KEY_ENTER: c_uint = 13;
pub const KEY_ESCAPE: c_uint = 27;
pub const KEY_SPACE: c_uint = 32;

pub const KEY_LEFT: c_uint = 37;
pub const KEY_UP: c_uint = 38;
pub const KEY_RIGHT: c_uint = 39;
pub const KEY_DOWN: c_uint = 40;

pub const KEY_A: c_uint = 65;
pub const KEY_D: c_uint = 68;
pub const KEY_S: c_uint = 83;
pub const KEY_W: c_uint = 87;
