const std = @import("std");
const t = std.testing;

const p = @import("platform.zig");

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

var tri_program: u32 = 0;
var tri_vao: u32 = 0;
var tri_vbo: u32 = 0;
var card_texture: u32 = 0;
var global_allocator: std.mem.Allocator = undefined;

pub const TriangleApp = struct {
    pub fn onInit() void {
        global_allocator = std.heap.page_allocator;

        // --- shader program ------------------------------------------------
        const vert = glInitShader(vert_src, vert_src.len, p.GL_VERTEX_SHADER);
        const frag = glInitShader(frag_src, frag_src.len, p.GL_FRAGMENT_SHADER);
        tri_program = glLinkShaderProgram(vert, frag);

        // --- geometry -------------------------------------------------------
        p.glGenVertexArrays(1, @as([*]u32, @ptrCast(&tri_vao)));
        p.glGenBuffers(1, @as([*]u32, @ptrCast(&tri_vbo)));

        p.glBindVertexArray(tri_vao);
        p.glBindBuffer(p.GL_ARRAY_BUFFER, tri_vbo);
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
        card_texture = loadCardTexture(global_allocator, "cards/0.png") catch std.debug.panic("failed to load card texture", .{});

        // Bind sampler uniform to texture unit 0
        p.glUseProgram(tri_program);
        const loc = p.glGetUniformLocation(tri_program, "uTex\x00");
        p.glUniform1i(loc, 0);
        p.glUseProgram(0);
    }

    pub fn onResize(w: c_uint, h: c_uint, scale: f32) void {
        const w_: u32 = @intFromFloat(@round(scale * @as(f32, @floatFromInt(w))));
        const h_: u32 = @intFromFloat(@round(scale * @as(f32, @floatFromInt(h))));
        p.glViewport(0, 0, w_, h_);
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

        p.glUseProgram(tri_program);

        // Bind the card texture to unit 0
        p.glBindTexture(p.GL_TEXTURE_2D, card_texture);

        p.glBindVertexArray(tri_vao);
        p.glDrawArrays(p.GL_TRIANGLES, 0, 6);
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
