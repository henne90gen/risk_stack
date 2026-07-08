// platform_sdl.zig — native SDL3 backend.  Never imported on wasm builds.

const std = @import("std");
const gl = @import("gl.zig");
const keys = @import("keys.zig");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_opengl.h");
});

// ---------------------------------------------------------------------------
// SDL scancode → JS keyCode translation
// ---------------------------------------------------------------------------

const ScanEntry = struct { sdl: c_uint, js: c_uint };

const scancode_map = [_]ScanEntry{
    .{ .sdl = 80, .js = keys.KEY_LEFT },
    .{ .sdl = 79, .js = keys.KEY_RIGHT },
    .{ .sdl = 82, .js = keys.KEY_UP },
    .{ .sdl = 81, .js = keys.KEY_DOWN },
    .{ .sdl = 44, .js = keys.KEY_SPACE },
    .{ .sdl = 40, .js = keys.KEY_ENTER },
    .{ .sdl = 41, .js = keys.KEY_ESCAPE },
    .{ .sdl = 4, .js = keys.KEY_A },
    .{ .sdl = 7, .js = keys.KEY_D },
    .{ .sdl = 22, .js = keys.KEY_S },
    .{ .sdl = 26, .js = keys.KEY_W },
};

fn sdlScancodeToJs(scancode: c_uint) ?c_uint {
    for (scancode_map) |entry| {
        if (entry.sdl == scancode) return entry.js;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

pub fn run(comptime App: type) void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("SDL_Init failed: {s}", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_Quit();

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);

    const window = c.SDL_CreateWindow(
        "flip7",
        1280,
        720,
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        std.log.err("SDL_CreateWindow failed: {s}", .{c.SDL_GetError()});
        return;
    };
    defer c.SDL_DestroyWindow(window);

    const gl_ctx = c.SDL_GL_CreateContext(window) orelse {
        std.log.err("SDL_GL_CreateContext failed: {s}", .{c.SDL_GetError()});
        return;
    };
    defer _ = c.SDL_GL_DestroyContext(gl_ctx);

    _ = c.SDL_GL_MakeCurrent(window, gl_ctx);
    _ = c.SDL_GL_SetSwapInterval(1);

    gl.loadProcs();

    App.onInit();

    {
        var pw: c_int = 0;
        var ph: c_int = 0;
        _ = c.SDL_GetWindowSizeInPixels(window, &pw, &ph);
        var lw: c_int = 0;
        var lh: c_int = 0;
        _ = c.SDL_GetWindowSize(window, &lw, &lh);
        const scale: f32 = if (lw > 0) @as(f32, @floatFromInt(pw)) / @as(f32, @floatFromInt(lw)) else 1.0;
        App.onResize(@intCast(pw), @intCast(ph), scale);
    }

    var event: c.SDL_Event = undefined;
    main: while (true) {
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => break :main,

                c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                    const we = event.window;
                    var lw: c_int = 0;
                    var _lh: c_int = 0;
                    _ = c.SDL_GetWindowSize(window, &lw, &_lh);
                    const scale: f32 = if (lw > 0)
                        @as(f32, @floatFromInt(we.data1)) / @as(f32, @floatFromInt(lw))
                    else
                        1.0;
                    App.onResize(@intCast(we.data1), @intCast(we.data2), scale);
                },

                c.SDL_EVENT_KEY_DOWN => {
                    const scancode: c_uint = @intCast(event.key.scancode);
                    if (sdlScancodeToJs(scancode)) |js_key| {
                        App.onKeyDown(js_key);
                    }
                },

                else => {},
            }
        }

        App.onAnimationFrame();
        _ = c.SDL_GL_SwapWindow(window);
    }
}
