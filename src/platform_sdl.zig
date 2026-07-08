const std = @import("std");
const p = @import("platform.zig");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_opengl.h");
});

// ---------------------------------------------------------------------------
// SDL scancode → JS keyCode translation
// ---------------------------------------------------------------------------

const ScanEntry = struct { sdl: c_uint, js: c_uint };

const scancode_map = [_]ScanEntry{
    .{ .sdl = 80, .js = p.KEY_LEFT },
    .{ .sdl = 79, .js = p.KEY_RIGHT },
    .{ .sdl = 82, .js = p.KEY_UP },
    .{ .sdl = 81, .js = p.KEY_DOWN },
    .{ .sdl = 44, .js = p.KEY_SPACE },
    .{ .sdl = 40, .js = p.KEY_ENTER },
    .{ .sdl = 41, .js = p.KEY_ESCAPE },
    .{ .sdl = 4, .js = p.KEY_A },
    .{ .sdl = 7, .js = p.KEY_D },
    .{ .sdl = 22, .js = p.KEY_S },
    .{ .sdl = 26, .js = p.KEY_W },
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
        p.logErr("SDL_Init failed: {s}", .{c.SDL_GetError()});
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

    p.loadProcs();

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
                    } else {
                        p.logWarn("Unmapped SDL scancode: {d}", .{scancode});
                    }
                },

                else => {},
            }
        }

        App.onAnimationFrame();
        _ = c.SDL_GL_SwapWindow(window);
    }
}
