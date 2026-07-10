const std = @import("std");
const t = std.testing;

pub const p = @import("platform.zig");
const zm = @import("zmath");

test {
    t.refAllDecls(@This());
}

// Strip the first line (#version ...) from the embedded shader source and
// replace it with the platform-appropriate version directive at compile time.
fn patchShader(comptime src: [:0]const u8) [:0]const u8 {
    // Find the end of the first line.
    const nl = std.mem.indexOfScalar(u8, src, '\n') orelse
        @compileError("shader has no newline");
    return p.glsl_version ++ src[nl + 1 .. :0];
}

const vert_src: [:0]const u8 = patchShader(@embedFile("shader.vert"));
const frag_src: [:0]const u8 = patchShader(@embedFile("shader.frag"));

// ---------------------------------------------------------------------------
// Quad geometry: two triangles covering NDC [-0.5, 0.5]
// interleaved layout: x, y, u, v  (f32)
// ---------------------------------------------------------------------------

const quad_vertices = [_]f32{
    //  x      y     u    v
    -0.5, -0.5, 0.0, 1.0, // bottom-left
    0.5, -0.5, 1.0, 1.0, // bottom-right
    0.5, 0.5, 1.0, 0.0, // top-right
    -0.5, -0.5, 0.0, 1.0, // bottom-left
    0.5, 0.5, 1.0, 0.0, // top-right
    -0.5, 0.5, 0.0, 0.0, // top-left
};

const AppState = struct {
    allocator: std.mem.Allocator,

    tri_program: u32 = 0,
    tri_vao: u32 = 0,
    tri_vbo: u32 = 0,
    card_texture: u32 = 0,
    u_loc_model: i32 = 0,
    u_loc_view: i32 = 0,
    u_loc_projection: i32 = 0,

    aspect_ratio: f32 = 1.0,
};

var app_state: AppState = undefined;

pub const TriangleApp = struct {
    pub fn onInit() void {
        app_state = AppState{ .allocator = std.heap.page_allocator };

        // --- shader program ------------------------------------------------
        const vert = glInitShader(vert_src, vert_src.len, p.GL_VERTEX_SHADER);
        const frag = glInitShader(frag_src, frag_src.len, p.GL_FRAGMENT_SHADER);
        app_state.tri_program = glLinkShaderProgram(vert, frag);

        // --- geometry -------------------------------------------------------
        p.glGenVertexArrays(1, @as([*]u32, @ptrCast(&app_state.tri_vao)));
        p.glGenBuffers(1, @as([*]u32, @ptrCast(&app_state.tri_vbo)));

        p.glBindVertexArray(app_state.tri_vao);
        p.glBindBuffer(p.GL_ARRAY_BUFFER, app_state.tri_vbo);
        p.glBufferData(
            p.GL_ARRAY_BUFFER,
            @sizeOf(@TypeOf(quad_vertices)),
            &quad_vertices,
            p.GL_STATIC_DRAW,
        );

        const stride: i32 = 4 * @sizeOf(f32);
        // aPos: location 0, 2 floats
        p.glEnableVertexAttribArray(0);
        p.glVertexAttribPointer(0, 2, p.GL_FLOAT, p.GL_FALSE, stride, @ptrFromInt(0));
        // aUV:  location 1, 2 floats
        p.glEnableVertexAttribArray(1);
        p.glVertexAttribPointer(1, 2, p.GL_FLOAT, p.GL_FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));

        p.glBindVertexArray(0);

        // --- texture -----------------------------------------------------------
        app_state.card_texture = loadCardTexture(app_state.allocator, "cards/0.png") catch std.debug.panic("failed to load card texture", .{});

        // Bind sampler uniform to texture unit 0, and cache uniform locations
        p.glUseProgram(app_state.tri_program);

        const loc = p.glGetUniformLocation(app_state.tri_program, "uTex");
        p.glUniform1i(loc, 0);

        app_state.u_loc_model = p.glGetUniformLocation(app_state.tri_program, "uModel");
        p.glUniformMatrix4fv(app_state.u_loc_model, 1, p.GL_TRUE, zm.arrNPtr(&zm.identity()));

        app_state.u_loc_view = p.glGetUniformLocation(app_state.tri_program, "uView");
        p.glUniformMatrix4fv(app_state.u_loc_view, 1, p.GL_TRUE, zm.arrNPtr(&zm.identity()));

        app_state.u_loc_projection = p.glGetUniformLocation(app_state.tri_program, "uProjection");
        p.glUniformMatrix4fv(app_state.u_loc_projection, 1, p.GL_TRUE, zm.arrNPtr(&zm.identity()));

        p.glUseProgram(0);
    }

    // The game is designed for this logical aspect ratio (width / height).
    const game_aspect: f32 = 16.0 / 9.0;

    pub fn onResize(w: c_uint, h: c_uint, scale: f32) void {
        p.logInfo("resizing to new dimensions {}x{} with scale {}", .{ w, h, scale });

        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);

        // Pixel dimensions of the full canvas.
        const pw: f32 = @round(fw * scale);
        const ph: f32 = @round(fh * scale);

        // Largest centered rectangle that fits the canvas at the desired ratio.
        var vw: f32 = pw;
        var vh: f32 = @round(vw / game_aspect);
        if (vh > ph) {
            vh = ph;
            vw = @round(vh * game_aspect);
        }

        // Center it: offset from the bottom-left corner of the canvas.
        const ox: i32 = @intFromFloat(@round((pw - vw) / 2.0));
        const oy: i32 = @intFromFloat(@round((ph - vh) / 2.0));

        p.glViewport(ox, oy, @intFromFloat(vw), @intFromFloat(vh));

        app_state.aspect_ratio = vw / vh;
    }

    pub fn onKeyDown(key: p.Key) void {
        if (key == p.Key.Escape) {
            p.logInfo("Escape key pressed, exiting...", .{});
            p.close();
        }
        p.logInfo("onKeyDown: {}", .{key});
    }

    pub fn onKeyUp(key: p.Key) void {
        p.logInfo("onKeyUp: {}", .{key});
    }

    pub fn onMouseDown(button: p.MouseButton, x: f32, y: f32) void {
        p.logInfo("onMouseDown: {} -> {} | {}", .{ button, x, y });
    }

    pub fn onMouseUp(button: p.MouseButton, x: f32, y: f32) void {
        p.logInfo("onMouseUp: {} -> {} | {}", .{ button, x, y });
    }

    pub fn onMouseMove(x: f32, y: f32) void {
        p.logInfo("onMouseMove: {} | {}", .{ x, y });
    }

    pub fn onAnimationFrame() void {
        p.glClearColor(0.1, 0.1, 0.1, 1.0);
        p.glClear(p.GL_COLOR_BUFFER_BIT);

        p.glUseProgram(app_state.tri_program);
        p.glBindTexture(p.GL_TEXTURE_2D, app_state.card_texture);
        p.glBindVertexArray(app_state.tri_vao);

        const positions = [4][2]f32{
            .{ 0.0, 0.0 },
            .{ 1.0, 0.0 },
            .{ 1.0, 1.0 },
            .{ 0.0, 1.0 },
        };

        const world_to_view = zm.lookAtRh(
            zm.f32x4(3.0, 3.0, 3.0, 1.0), // eye position
            zm.f32x4(0.0, 0.0, 0.0, 1.0), // focus point
            zm.f32x4(0.0, 1.0, 0.0, 0.0), // up direction ('w' coord is zero because this is a vector not a point)
        );
        p.glUniformMatrix4fv(app_state.u_loc_view, 1, p.GL_TRUE, zm.arrNPtr(&world_to_view));

        const view_to_clip = zm.perspectiveFovRhGl(0.25 * std.math.pi, app_state.aspect_ratio, 0.1, 20.0);
        p.glUniformMatrix4fv(app_state.u_loc_projection, 1, p.GL_TRUE, zm.arrNPtr(&view_to_clip));

        for (positions) |pos| {
            const object_to_world = zm.mul(
                zm.translation(pos[0], pos[1], 0.0),
                zm.scaling(0.5, 0.5, 0.5),
            );
            p.glUniformMatrix4fv(app_state.u_loc_model, 1, p.GL_TRUE, zm.arrNPtr(&object_to_world));

            p.glDrawArrays(p.GL_TRIANGLES, 0, 6);
        }

        p.glBindVertexArray(0);
        p.glBindTexture(p.GL_TEXTURE_2D, 0);
        p.glUseProgram(0);
    }
};

fn glInitShader(src: [:0]const u8, len: i32, typ: u32) u32 {
    const shader = p.glCreateShader(typ);
    p.glShaderSource(shader, src, len);
    p.glCompileShader(shader);
    return shader;
}

fn glLinkShaderProgram(vert: u32, frag: u32) u32 {
    const prog = p.glCreateProgram();
    p.glAttachShader(prog, vert);
    p.glAttachShader(prog, frag);
    p.glLinkProgram(prog);
    p.glDeleteShader(vert);
    p.glDeleteShader(frag);
    return prog;
}

/// Decode the image at `path` (e.g. "cards/0.png") via `platform.texture` and
/// upload it as a freshly-generated OpenGL RGBA texture.
/// Returns the GL texture id, or 0 on failure.
fn loadCardTexture(allocator: std.mem.Allocator, path: []const u8) !u32 {
    const td = try p.texture(allocator, path);
    defer allocator.free(td.pixels);

    var tex: u32 = 0;
    p.glGenTextures(1, @as([*]u32, @ptrCast(&tex)));
    p.glBindTexture(p.GL_TEXTURE_2D, tex);

    p.glTexImage2D(
        p.GL_TEXTURE_2D,
        0,
        @intCast(p.GL_RGBA),
        @intCast(td.width),
        @intCast(td.height),
        0,
        p.GL_RGBA,
        p.GL_UNSIGNED_BYTE,
        td.pixels.ptr,
        td.pixels.len,
    );

    p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_MIN_FILTER, @intCast(p.GL_LINEAR_MIPMAP_LINEAR));
    p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_MAG_FILTER, @intCast(p.GL_LINEAR));
    p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_WRAP_S, @intCast(p.GL_CLAMP_TO_EDGE));
    p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_WRAP_T, @intCast(p.GL_CLAMP_TO_EDGE));
    p.glGenerateMipmap(p.GL_TEXTURE_2D);

    p.glBindTexture(p.GL_TEXTURE_2D, 0);
    return tex;
}
