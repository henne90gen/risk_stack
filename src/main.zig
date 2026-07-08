const std = @import("std");
const Io = std.Io;
const t = std.testing;
const flip7 = @import("flip7.zig");

const p = @import("platform.zig");

test {
    t.refAllDecls(@This());
}

const vert_src = @embedFile("shader.vert");
const frag_src = @embedFile("shader.frag");

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
        const vert = glInitShader(vert_src, vert_src.len, p.GL_VERTEX_SHADER);
        const frag = glInitShader(frag_src, frag_src.len, p.GL_FRAGMENT_SHADER);
        tri_program = glLinkShaderProgram(vert, frag);
        p.glGenVertexArrays(1, @as([*]u32, @ptrCast(&tri_vao)));
        p.glGenBuffers(1, @as([*]u32, @ptrCast(&tri_vbo)));

        p.glBindVertexArray(tri_vao);
        p.glBindBuffer(p.GL_ARRAY_BUFFER, tri_vbo);

        const byte_size = @sizeOf(@TypeOf(triangle_vertices));
        p.glBufferData(
            p.GL_ARRAY_BUFFER,
            byte_size,
            &triangle_vertices,
            p.GL_STATIC_DRAW,
        );

        const stride: i32 = 5 * @sizeOf(f32);
        p.glEnableVertexAttribArray(0);
        p.glVertexAttribPointer(0, 2, p.GL_FLOAT, p.GL_FALSE, stride, @ptrFromInt(0));
        p.glEnableVertexAttribArray(1);
        p.glVertexAttribPointer(1, 3, p.GL_FLOAT, p.GL_FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));

        p.glBindVertexArray(0);
    }

    pub fn onResize(w: c_uint, h: c_uint, scale: f32) void {
        p.glViewport(0, 0, @intFromFloat(scale * @as(f32, @floatFromInt(w))), @intFromFloat(scale * @as(f32, @floatFromInt(h))));
    }

    pub fn onKeyDown(key: c_uint) void {
        p.logInfo("onKeyDown: {}", .{key});
    }

    pub fn onKeyUp(key: c_uint) void {
        p.logInfo("onKeyUp: {}", .{key});
    }

    pub fn onMouseDown(button: c_uint, x: f32, y: f32) void {
        p.logInfo("onMouseDown: {} -> {} | {}", .{ button, x, y });
    }

    pub fn onMouseUp(button: c_uint, x: f32, y: f32) void {
        p.logInfo("onMouseUp: {} -> {} | {}", .{ button, x, y });
    }

    pub fn onMouseMove(x: f32, y: f32) void {
        p.logInfo("onMouseMove: {} | {}", .{ x, y });
    }

    pub fn onAnimationFrame() void {
        p.glClearColor(0.1, 0.1, 0.1, 1.0);
        p.glClear(p.GL_COLOR_BUFFER_BIT);

        p.glUseProgram(tri_program);
        p.glBindVertexArray(tri_vao);
        p.glDrawArrays(p.GL_TRIANGLES, 0, 3);
        p.glBindVertexArray(0);
    }
};

pub fn glInitShader(src: [*:0]const u8, len: usize, typ: u32) u32 {
    const shader = p.glCreateShader(typ);
    p.glShaderSource(shader, src, @intCast(len));
    p.glCompileShader(shader);
    return shader;
}

pub fn glLinkShaderProgram(vert: u32, frag: u32) u32 {
    const prog = p.glCreateProgram();
    p.glAttachShader(prog, vert);
    p.glAttachShader(prog, frag);
    p.glLinkProgram(prog);
    p.glDeleteShader(vert);
    p.glDeleteShader(frag);
    return prog;
}
