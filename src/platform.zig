const builtin = @import("builtin");

pub const is_wasm = builtin.target.cpu.arch == .wasm32;

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
