const std = @import("std");
const Io = std.Io;
const t = std.testing;
const flip7 = @import("flip7.zig");

const platform = @import("platform");
const gl = @import("gl.zig");

test {
    t.refAllDecls(@This());
}

// ---------------------------------------------------------------------------
// Triangle app — runs on both native (SDL3/OpenGL) and wasm (WebGL).
// GPU state lives at file scope because App callbacks are plain functions.
// ---------------------------------------------------------------------------

const vert_src =
    \\#version 300 es
    \\precision mediump float;
    \\layout (location = 0) in vec2 aPos;
    \\layout (location = 1) in vec3 aColor;
    \\out vec3 vColor;
    \\void main() {
    \\    gl_Position = vec4(aPos, 0.0, 1.0);
    \\    vColor = aColor;
    \\}
;

const frag_src =
    \\#version 300 es
    \\precision mediump float;
    \\in vec3 vColor;
    \\out vec4 fragColor;
    \\void main() {
    \\    fragColor = vec4(vColor, 1.0);
    \\}
;

// interleaved: x, y, r, g, b  (f32)
const triangle_vertices = [_]f32{
    0.0, 0.5, 1.0, 0.0, 0.0, // top        – red
    -0.5, -0.5, 0.0, 1.0, 0.0, // bot-left   – green
    0.5, -0.5, 0.0, 0.0, 1.0, // bot-right  – blue
};

var tri_program: u32 = 0;
var tri_vao: u32 = 0;
var tri_vbo: u32 = 0;

pub const TriangleApp = struct {
    pub fn onInit() void {
        const vert = gl.glInitShader(vert_src, vert_src.len, gl.GL_VERTEX_SHADER);
        const frag = gl.glInitShader(frag_src, frag_src.len, gl.GL_FRAGMENT_SHADER);
        tri_program = gl.glLinkShaderProgram(vert, frag);
        gl.glGenVertexArrays(1, @as([*]u32, @ptrCast(&tri_vao)));
        gl.glGenBuffers(1, @as([*]u32, @ptrCast(&tri_vbo)));

        gl.glBindVertexArray(tri_vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, tri_vbo);

        const byte_size = @sizeOf(@TypeOf(triangle_vertices));
        gl.glBufferData(
            gl.GL_ARRAY_BUFFER,
            byte_size,
            &triangle_vertices,
            gl.GL_STATIC_DRAW,
        );

        const stride: i32 = 5 * @sizeOf(f32);
        gl.glEnableVertexAttribArray(0);
        gl.glVertexAttribPointer(0, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(0));
        gl.glEnableVertexAttribArray(1);
        gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));

        gl.glBindVertexArray(0);
    }

    pub fn onResize(w: c_uint, h: c_uint, scale: f32) void {
        gl.glViewport(0, 0, @intFromFloat(scale * @as(f32, @floatFromInt(w))), @intFromFloat(scale * @as(f32, @floatFromInt(h))));
    }

    pub fn onKeyDown(key: c_uint) void {
        _ = key;
    }

    pub fn onAnimationFrame() void {
        gl.glClearColor(0.1, 0.1, 0.1, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        gl.glUseProgram(tri_program);
        gl.glBindVertexArray(tri_vao);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);
        gl.glBindVertexArray(0);
    }
};
