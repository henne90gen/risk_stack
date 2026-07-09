const std = @import("std");
const p = @import("platform.zig");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_opengl.h");
});

const png = @cImport({
    @cInclude("png.h");
});

// ---------------------------------------------------------------------------
// SDL scancode → JS keyCode translation
// ---------------------------------------------------------------------------

const ScanEntry = struct { sdl: c_uint, js: p.Key };

const scancode_map = [_]ScanEntry{
    .{ .sdl = 80, .js = p.Key.Left },
    .{ .sdl = 79, .js = p.Key.Right },
    .{ .sdl = 82, .js = p.Key.Up },
    .{ .sdl = 81, .js = p.Key.Down },
    .{ .sdl = 44, .js = p.Key.Space },
    .{ .sdl = 40, .js = p.Key.Enter },
    .{ .sdl = 41, .js = p.Key.Escape },
    .{ .sdl = 4, .js = p.Key.A },
    .{ .sdl = 7, .js = p.Key.D },
    .{ .sdl = 22, .js = p.Key.S },
    .{ .sdl = 26, .js = p.Key.W },
};

fn sdlScancodeToJs(scancode: c_uint) ?p.Key {
    for (scancode_map) |entry| {
        if (entry.sdl == scancode) return entry.js;
    }
    return null;
}

const MouseButtonEntry = struct { sdl: u8, js: p.MouseButton };

const mouse_button_map = [_]MouseButtonEntry{
    .{ .sdl = c.SDL_BUTTON_LEFT, .js = p.MouseButton.Left },
    .{ .sdl = c.SDL_BUTTON_MIDDLE, .js = p.MouseButton.Middle },
    .{ .sdl = c.SDL_BUTTON_RIGHT, .js = p.MouseButton.Right },
};

fn sdlMouseButtonToJs(button: u8) ?p.MouseButton {
    for (mouse_button_map) |entry| {
        if (entry.sdl == button) return entry.js;
    }
    return null;
}

pub fn close() void {
    global_running = false;
}

const ReadState = struct { data: []const u8, pos: usize };
pub fn loadTexture(allocator: std.mem.Allocator, path: []const u8) !p.TextureData {
    const cards = @import("cards.zig");
    const card = cards.Card.fromPath(path) orelse
        std.debug.panic("texture: unknown path '{s}'", .{path});
    const png_bytes = card.bytes();

    var src = ReadState{ .data = png_bytes, .pos = 0 };

    const png_read = png.png_create_read_struct(
        png.PNG_LIBPNG_VER_STRING,
        null,
        null,
        null,
    ) orelse std.debug.panic("png_create_read_struct failed for '{s}'", .{path});
    defer png.png_destroy_read_struct(@ptrCast(@constCast(&png_read)), null, null);

    const info = png.png_create_info_struct(png_read) orelse
        std.debug.panic("png_create_info_struct failed for '{s}'", .{path});

    if (png.setjmp(@constCast(&png.png_jmpbuf(png_read)[0])) != 0)
        std.debug.panic("libpng error while decoding '{s}'", .{path});

    png.png_set_read_fn(png_read, &src, readCallback);
    png.png_read_info(png_read, info);

    const width = png.png_get_image_width(png_read, info);
    const height = png.png_get_image_height(png_read, info);
    const color_type = png.png_get_color_type(png_read, info);
    const bit_depth = png.png_get_bit_depth(png_read, info);

    if (bit_depth == 16) png.png_set_strip_16(png_read);
    if (color_type == png.PNG_COLOR_TYPE_PALETTE) png.png_set_palette_to_rgb(png_read);
    if (color_type == png.PNG_COLOR_TYPE_GRAY and bit_depth < 8)
        png.png_set_expand_gray_1_2_4_to_8(png_read);
    if (png.png_get_valid(png_read, info, png.PNG_INFO_tRNS) != 0) png.png_set_tRNS_to_alpha(png_read);
    if (color_type == png.PNG_COLOR_TYPE_RGB or
        color_type == png.PNG_COLOR_TYPE_GRAY or
        color_type == png.PNG_COLOR_TYPE_PALETTE)
        png.png_set_filler(png_read, 0xFF, png.PNG_FILLER_AFTER);
    if (color_type == png.PNG_COLOR_TYPE_GRAY or
        color_type == png.PNG_COLOR_TYPE_GRAY_ALPHA)
        png.png_set_gray_to_rgb(png_read);

    png.png_read_update_info(png_read, info);

    const row_bytes = width * 4; // RGBA8
    const pixels = try allocator.alloc(u8, height * row_bytes);

    const rows = try allocator.alloc([*]u8, height);
    defer allocator.free(rows);
    for (0..height) |y| rows[y] = pixels[y * row_bytes ..].ptr;

    png.png_read_image(png_read, @ptrCast(rows.ptr));

    return .{ .pixels = pixels, .width = width, .height = height };
}

fn readCallback(
    png_read: png.png_structp,
    buf: png.png_bytep,
    len: png.png_size_t,
) callconv(.c) void {
    const src: *ReadState = @ptrCast(@alignCast(png.png_get_io_ptr(png_read)));
    const available = src.data.len - src.pos;
    if (len > available) {
        png.png_error(png_read, "unexpected end of PNG data");
        return;
    }
    @memcpy(buf[0..len], src.data[src.pos..][0..len]);
    src.pos += len;
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

var global_running: bool = false;

pub fn run(comptime App: type) void {
    // Prefer X11/XWayland over native Wayland: without server-side decorations
    // (e.g. on GNOME) SDL falls back to libdecor, whose software-rendered
    // decorations make interactive resizing extremely slow on large/HiDPI
    // windows. The SDL_VIDEO_DRIVER env var still overrides this hint.
    _ = c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "x11,wayland");

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        p.logErr("SDL_Init failed: {s}", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_Quit();

    p.logInfo("SDL video driver: {s}", .{c.SDL_GetCurrentVideoDriver() orelse @as([*c]const u8, "?")});

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
    // Prefer adaptive vsync: on a missed deadline it swaps immediately instead
    // of stalling until the next retrace. Fall back to regular vsync.
    if (!c.SDL_GL_SetSwapInterval(-1)) {
        _ = c.SDL_GL_SetSwapInterval(1);
    }

    p.loadProcs();
    logGlInfo();

    App.onInit();

    {
        var lw: c_int = 0;
        var lh: c_int = 0;
        _ = c.SDL_GetWindowSize(window, &lw, &lh);
        App.onResize(@intCast(lw), @intCast(lh), windowScale(window));
    }

    global_running = true;
    var event: c.SDL_Event = undefined;
    main: while (global_running) {
        const t_frame_start = c.SDL_GetPerformanceCounter();

        // Coalesce resize events: only re-query the window size once per frame.
        var pending_resize = false;

        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => break :main,

                c.SDL_EVENT_WINDOW_RESIZED,
                c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
                c.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
                => pending_resize = true,

                c.SDL_EVENT_KEY_DOWN => {
                    const scancode: c_uint = @intCast(event.key.scancode);
                    if (sdlScancodeToJs(scancode)) |js_key| {
                        App.onKeyDown(js_key);
                    } else {
                        p.logWarn("Unmapped SDL scancode: {d}", .{scancode});
                    }
                },

                c.SDL_EVENT_KEY_UP => {
                    const scancode: c_uint = @intCast(event.key.scancode);
                    if (sdlScancodeToJs(scancode)) |js_key| {
                        App.onKeyUp(js_key);
                    } else {
                        p.logWarn("Unmapped SDL scancode: {d}", .{scancode});
                    }
                },

                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    const me = event.button;
                    if (sdlMouseButtonToJs(me.button)) |js_button| {
                        App.onMouseDown(js_button, me.x, me.y);
                    } else {
                        p.logWarn("Unmapped SDL mouse button: {d}", .{me.button});
                    }
                },

                c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    const me = event.button;
                    if (sdlMouseButtonToJs(me.button)) |js_button| {
                        App.onMouseUp(js_button, me.x, me.y);
                    } else {
                        p.logWarn("Unmapped SDL mouse button: {d}", .{me.button});
                    }
                },

                c.SDL_EVENT_MOUSE_MOTION => {
                    const me = event.motion;
                    App.onMouseMove(me.x, me.y);
                },

                else => {},
            }
        }

        const t_events_done = c.SDL_GetPerformanceCounter();

        if (pending_resize) {
            var lw: c_int = 0;
            var lh: c_int = 0;
            _ = c.SDL_GetWindowSize(window, &lw, &lh);
            App.onResize(@intCast(lw), @intCast(lh), windowScale(window));
        }

        App.onAnimationFrame();
        const t_render_done = c.SDL_GetPerformanceCounter();

        _ = c.SDL_GL_SwapWindow(window);
        const t_swap_done = c.SDL_GetPerformanceCounter();

        logSlowFrame(t_frame_start, t_events_done, t_render_done, t_swap_done, pending_resize);
    }
}

/// Log which GL implementation the context landed on, to catch software
/// rendering fallbacks (e.g. llvmpipe) that make fill-rate scale with CPU.
fn logGlInfo() void {
    const GetString = @as(
        ?*const fn (c_uint) callconv(.c) ?[*:0]const u8,
        @ptrCast(c.SDL_GL_GetProcAddress("glGetString")),
    ) orelse {
        p.logWarn("glGetString unavailable; cannot report GL renderer", .{});
        return;
    };
    const vendor = GetString(c.GL_VENDOR) orelse "?";
    const renderer = GetString(c.GL_RENDERER) orelse "?";
    const version = GetString(c.GL_VERSION) orelse "?";
    p.logInfo("GL vendor: {s}, renderer: {s}, version: {s}", .{ vendor, renderer, version });
    var interval: c_int = 0;
    _ = c.SDL_GL_GetSwapInterval(&interval);
    p.logInfo("GL swap interval: {d}", .{interval});
}

/// Ratio of drawable pixels to logical window size (e.g. 2.0 on HiDPI).
fn windowScale(window: *c.SDL_Window) f32 {
    var lw: c_int = 0;
    var lh: c_int = 0;
    var pw: c_int = 0;
    var ph: c_int = 0;
    _ = c.SDL_GetWindowSize(window, &lw, &lh);
    _ = c.SDL_GetWindowSizeInPixels(window, &pw, &ph);
    if (lw <= 0) return 1.0;
    return @as(f32, @floatFromInt(pw)) / @as(f32, @floatFromInt(lw));
}

/// Warn when a frame exceeds this budget, with a breakdown of where time went.
const slow_frame_threshold_ms: f64 = 20.0;

fn logSlowFrame(t_start: u64, t_events: u64, t_render: u64, t_swap: u64, resized: bool) void {
    const freq: f64 = @floatFromInt(c.SDL_GetPerformanceFrequency());
    const to_ms = 1000.0 / freq;
    const total_ms = @as(f64, @floatFromInt(t_swap - t_start)) * to_ms;
    if (total_ms <= slow_frame_threshold_ms) return;
    p.logWarn("slow frame{s}: {d:.2}ms total (events {d:.2}ms, render {d:.2}ms, swap {d:.2}ms)", .{
        if (resized) " [resize]" else "",
        total_ms,
        @as(f64, @floatFromInt(t_events - t_start)) * to_ms,
        @as(f64, @floatFromInt(t_render - t_events)) * to_ms,
        @as(f64, @floatFromInt(t_swap - t_render)) * to_ms,
    });
}
