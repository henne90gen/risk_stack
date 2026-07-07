// platform.zig
//
// Bridges the four-callback App interface to the host environment.
//
// On wasm32:
//   `run(App)` at comptime generates the four `export fn` symbols the JS host
//   calls.  `gl.loadProcs()` is a no-op on wasm.
//
// On native (SDL3 / OpenGL 3.3):
//   `run(App)` from `main()` creates a window + GL context, loads procs,
//   fires onInit / onResize, then pumps the SDL event loop.
//
// ── App interface ──────────────────────────────────────────────────────────
//
//   const MyApp = struct {
//       pub fn onInit() void { ... }
//       pub fn onResize(w: c_uint, h: c_uint, scale: f32) void { ... }
//       pub fn onKeyDown(key: c_uint) void { ... }   // key = keys.KEY_*
//       pub fn onAnimationFrame() void { ... }
//   };
//
//   // native entry point:
//   pub fn main() void { platform.run(MyApp); }
//
//   // wasm — generate exports at comptime:
//   comptime { platform.run(MyApp); }

const builtin = @import("builtin");
// gl and keys are available as named modules when this file is used
// as part of a build — no direct import needed here.

pub const is_wasm = builtin.target.cpu.arch == .wasm32;

// ---------------------------------------------------------------------------
// Comptime validation
// ---------------------------------------------------------------------------

fn validateApp(comptime App: type) void {
    const required = .{
        .{ "onInit", fn () void },
        .{ "onResize", fn (c_uint, c_uint, f32) void },
        .{ "onKeyDown", fn (c_uint) void },
        .{ "onAnimationFrame", fn () void },
    };
    inline for (required) |entry| {
        const name = entry[0];
        const Sig = entry[1];
        if (!@hasDecl(App, name))
            @compileError("App must declare `pub fn " ++ name ++ "`");
        const actual = @TypeOf(@field(App, name));
        if (actual != Sig)
            @compileError("App." ++ name ++ " has wrong signature: expected " ++
                @typeName(Sig) ++ ", got " ++ @typeName(actual));
    }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn run(comptime App: type) void {
    validateApp(App);

    if (is_wasm) {
        const Exports = struct {
            export fn onInit() void {
                App.onInit();
            }
            export fn onResize(w: c_uint, h: c_uint, s: f32) void {
                App.onResize(w, h, s);
            }
            export fn onKeyDown(key: c_uint) void {
                App.onKeyDown(key);
            }
            export fn onAnimationFrame() void {
                App.onAnimationFrame();
            }
        };
        _ = Exports;
    } else {
        const sdl = @import("platform_sdl.zig");
        sdl.run(App);
    }
}
