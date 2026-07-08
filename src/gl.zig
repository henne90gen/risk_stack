// Unified OpenGL / WebGL API.
//
// On wasm32 every function is an `extern fn` imported from the JS host.
// On native every function delegates to a runtime proc loaded once via
// `loadProcs()` → SDL_GL_GetProcAddress.
//
// Callers write:  gl.glClearColor(...)  regardless of target.
//
// IMPORTANT: call `loadProcs()` once after the GL context is current on
// native builds.  On wasm the call is a no-op.

const builtin = @import("builtin");
const std = @import("std");
const is_wasm = builtin.target.cpu.arch == .wasm32;

// ---------------------------------------------------------------------------
// GL constants
// ---------------------------------------------------------------------------

pub const GL_DEPTH_TEST: u32 = 0x0B71;
pub const GL_VERTEX_SHADER: u32 = 0x8B31;
pub const GL_FRAGMENT_SHADER: u32 = 0x8B30;
pub const GL_ARRAY_BUFFER: u32 = 0x8892;
pub const GL_STATIC_DRAW: u32 = 0x88E4;
pub const GL_FLOAT: u32 = 0x1406;
pub const GL_FALSE: u32 = 0;
pub const GL_TRUE: u32 = 1;
pub const GL_TRIANGLES: u32 = 0x0004;
pub const GL_COLOR_BUFFER_BIT: u32 = 0x4000;
pub const GL_DEPTH_BUFFER_BIT: u32 = 0x0100;
pub const GL_COMPILE_STATUS: u32 = 0x8B81;
pub const GL_LINK_STATUS: u32 = 0x8B82;

// ---------------------------------------------------------------------------
// WASM path — every symbol is imported from the JS host
// ---------------------------------------------------------------------------

const wasm = if (is_wasm) struct {
    extern fn glEnable(cap: u32) void;
    extern fn glViewport(x: i32, y: i32, w: u32, h: u32) void;
    extern fn glClearColor(r: f32, g: f32, b: f32, a: f32) void;
    extern fn glClear(mask: u32) void;
    extern fn glGetError() u32;
    extern fn glGenBuffers(n: i32, buffers: [*]u32) void;
    extern fn glBindBuffer(target: u32, buffer: u32) void;
    extern fn glBufferData(target: u32, size: usize, data: ?*const anyopaque, usage: u32) void;
    extern fn glDrawArrays(mode: u32, first: i32, count: i32) void;
    extern fn glEnableVertexAttribArray(index: u32) void;
    extern fn glVertexAttribPointer(index: u32, size: i32, typ: u32, normalized: u32, stride: i32, offset: ?*const anyopaque) void;
    extern fn glCreateShader(typ: u32) u32;
    // glShaderSource on wasm: JS host accepts (shader, src_ptr, len).
    extern fn glShaderSource(shader: u32, src: [*]const u8, len: i32) void;
    extern fn glCompileShader(shader: u32) void;
    extern fn glCreateProgram() u32;
    extern fn glAttachShader(program: u32, shader: u32) void;
    extern fn glLinkProgram(program: u32) void;
    extern fn glUseProgram(program: u32) void;
    extern fn glGetUniformLocation(program: u32, name: [*]const u8, len: i32) i32;
    extern fn glUniform4f(loc: i32, x: f32, y: f32, z: f32, w: f32) void;
    extern fn glUniformMatrix4fv(loc: i32, count: i32, transpose: u32, data: [*]const f32) void;
    extern fn glDeleteShader(shader: u32) void;
    extern fn glDeleteProgram(program: u32) void;
    extern fn glDeleteBuffers(n: i32, buffers: [*]const u32) void;

    extern fn glGenVertexArrays(n: i32, arrays: [*]u32) void;
    extern fn glBindVertexArray(array: u32) void;
    extern fn glDeleteVertexArrays(n: i32, arrays: [*]const u32) void;

    // High-level wasm helpers used by the existing wasm entrypoint.
    extern fn glInitShader(src: [*]const u8, len: usize, typ: u32) u32;
    extern fn glLinkShaderProgram(vert: u32, frag: u32) u32;

    // Debug logging — calls console.log on the JS side.
    extern fn jsLog(ptr: [*]const u8, len: usize) void;
} else struct {};

// ---------------------------------------------------------------------------
// NATIVE path — proc-pointer table loaded via SDL_GL_GetProcAddress
// ---------------------------------------------------------------------------

const c = if (!is_wasm) @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_opengl.h");
}) else void;

const GlProcs = if (!is_wasm) struct {
    Enable: *const fn (c.GLenum) callconv(.c) void,
    Viewport: *const fn (c.GLint, c.GLint, c.GLsizei, c.GLsizei) callconv(.c) void,
    ClearColor: *const fn (c.GLfloat, c.GLfloat, c.GLfloat, c.GLfloat) callconv(.c) void,
    Clear: *const fn (c.GLbitfield) callconv(.c) void,
    GetError: *const fn () callconv(.c) c.GLenum,
    GenBuffers: *const fn (c.GLsizei, [*c]c.GLuint) callconv(.c) void,
    BindBuffer: *const fn (c.GLenum, c.GLuint) callconv(.c) void,
    BufferData: *const fn (c.GLenum, c.GLsizeiptr, ?*const anyopaque, c.GLenum) callconv(.c) void,
    DrawArrays: *const fn (c.GLenum, c.GLint, c.GLsizei) callconv(.c) void,
    EnableVertexAttribArray: *const fn (c.GLuint) callconv(.c) void,
    VertexAttribPointer: *const fn (c.GLuint, c.GLint, c.GLenum, c.GLboolean, c.GLsizei, ?*const anyopaque) callconv(.c) void,
    GenVertexArrays: *const fn (c.GLsizei, [*c]c.GLuint) callconv(.c) void,
    BindVertexArray: *const fn (c.GLuint) callconv(.c) void,
    DeleteVertexArrays: *const fn (c.GLsizei, [*c]const c.GLuint) callconv(.c) void,
    CreateShader: *const fn (c.GLenum) callconv(.c) c.GLuint,
    ShaderSource: *const fn (c.GLuint, c.GLsizei, [*c]const [*c]const c.GLchar, [*c]const c.GLint) callconv(.c) void,
    CompileShader: *const fn (c.GLuint) callconv(.c) void,
    CreateProgram: *const fn () callconv(.c) c.GLuint,
    AttachShader: *const fn (c.GLuint, c.GLuint) callconv(.c) void,
    LinkProgram: *const fn (c.GLuint) callconv(.c) void,
    UseProgram: *const fn (c.GLuint) callconv(.c) void,
    GetUniformLocation: *const fn (c.GLuint, [*c]const c.GLchar) callconv(.c) c.GLint,
    Uniform4f: *const fn (c.GLint, c.GLfloat, c.GLfloat, c.GLfloat, c.GLfloat) callconv(.c) void,
    UniformMatrix4fv: *const fn (c.GLint, c.GLsizei, c.GLboolean, [*c]const c.GLfloat) callconv(.c) void,
    DeleteShader: *const fn (c.GLuint) callconv(.c) void,
    DeleteProgram: *const fn (c.GLuint) callconv(.c) void,
    DeleteBuffers: *const fn (c.GLsizei, [*c]const c.GLuint) callconv(.c) void,
} else struct {};

var gl_procs: GlProcs = undefined;

/// Load all GL function pointers.  Must be called once after the GL context
/// is made current.  On wasm this is a no-op.
pub fn loadProcs() void {
    if (is_wasm) return;
    gl_procs = .{
        .Enable = @ptrCast(proc("glEnable")),
        .Viewport = @ptrCast(proc("glViewport")),
        .ClearColor = @ptrCast(proc("glClearColor")),
        .Clear = @ptrCast(proc("glClear")),
        .GetError = @ptrCast(proc("glGetError")),
        .GenBuffers = @ptrCast(proc("glGenBuffers")),
        .BindBuffer = @ptrCast(proc("glBindBuffer")),
        .BufferData = @ptrCast(proc("glBufferData")),
        .DrawArrays = @ptrCast(proc("glDrawArrays")),
        .EnableVertexAttribArray = @ptrCast(proc("glEnableVertexAttribArray")),
        .VertexAttribPointer = @ptrCast(proc("glVertexAttribPointer")),
        .GenVertexArrays = @ptrCast(proc("glGenVertexArrays")),
        .BindVertexArray = @ptrCast(proc("glBindVertexArray")),
        .DeleteVertexArrays = @ptrCast(proc("glDeleteVertexArrays")),
        .CreateShader = @ptrCast(proc("glCreateShader")),
        .ShaderSource = @ptrCast(proc("glShaderSource")),
        .CompileShader = @ptrCast(proc("glCompileShader")),
        .CreateProgram = @ptrCast(proc("glCreateProgram")),
        .AttachShader = @ptrCast(proc("glAttachShader")),
        .LinkProgram = @ptrCast(proc("glLinkProgram")),
        .UseProgram = @ptrCast(proc("glUseProgram")),
        .GetUniformLocation = @ptrCast(proc("glGetUniformLocation")),
        .Uniform4f = @ptrCast(proc("glUniform4f")),
        .UniformMatrix4fv = @ptrCast(proc("glUniformMatrix4fv")),
        .DeleteShader = @ptrCast(proc("glDeleteShader")),
        .DeleteProgram = @ptrCast(proc("glDeleteProgram")),
        .DeleteBuffers = @ptrCast(proc("glDeleteBuffers")),
    };
}

fn proc(comptime name: [:0]const u8) *const anyopaque {
    return @ptrCast(c.SDL_GL_GetProcAddress(name) orelse
        @panic("failed to load GL proc: " ++ name));
}

// ---------------------------------------------------------------------------
// Public free functions — uniform API for both targets
// ---------------------------------------------------------------------------

pub fn glEnable(cap: u32) void {
    if (is_wasm) wasm.glEnable(cap) else gl_procs.Enable(@intCast(cap));
}

pub fn glViewport(x: i32, y: i32, w: u32, h: u32) void {
    if (is_wasm) wasm.glViewport(x, y, w, h) else gl_procs.Viewport(x, y, @intCast(w), @intCast(h));
}

pub fn glClearColor(r: f32, g: f32, b: f32, a: f32) void {
    if (is_wasm) wasm.glClearColor(r, g, b, a) else gl_procs.ClearColor(r, g, b, a);
}

pub fn glClear(mask: u32) void {
    if (is_wasm) wasm.glClear(mask) else gl_procs.Clear(@intCast(mask));
}

pub fn glGetError() u32 {
    if (is_wasm) return wasm.glGetError() else return @intCast(gl_procs.GetError());
}

pub fn glGenBuffers(n: i32, buffers: [*]u32) void {
    if (is_wasm) wasm.glGenBuffers(n, buffers) else gl_procs.GenBuffers(@intCast(n), @ptrCast(buffers));
}

pub fn glBindBuffer(target: u32, buffer: u32) void {
    if (is_wasm) wasm.glBindBuffer(target, buffer) else gl_procs.BindBuffer(@intCast(target), @intCast(buffer));
}

pub fn glBufferData(target: u32, size: usize, data: ?*const anyopaque, usage: u32) void {
    if (is_wasm) wasm.glBufferData(target, size, data, usage) else gl_procs.BufferData(@intCast(target), @intCast(size), data, @intCast(usage));
}

pub fn glDrawArrays(mode: u32, first: i32, count: i32) void {
    if (is_wasm) wasm.glDrawArrays(mode, first, count) else gl_procs.DrawArrays(@intCast(mode), first, count);
}

pub fn glEnableVertexAttribArray(index: u32) void {
    if (is_wasm) wasm.glEnableVertexAttribArray(index) else gl_procs.EnableVertexAttribArray(@intCast(index));
}

pub fn glVertexAttribPointer(index: u32, size: i32, typ: u32, normalized: u32, stride: i32, offset: ?*const anyopaque) void {
    if (is_wasm) {
        wasm.glVertexAttribPointer(index, size, typ, normalized, stride, offset);
    } else {
        gl_procs.VertexAttribPointer(@intCast(index), size, @intCast(typ), @intCast(normalized), stride, offset);
    }
}

pub fn glGenVertexArrays(n: i32, arrays: [*]u32) void {
    if (is_wasm) wasm.glGenVertexArrays(n, arrays) else gl_procs.GenVertexArrays(@intCast(n), @ptrCast(arrays));
}

pub fn glBindVertexArray(array: u32) void {
    if (is_wasm) wasm.glBindVertexArray(array) else gl_procs.BindVertexArray(@intCast(array));
}

pub fn glDeleteVertexArrays(n: i32, arrays: [*]const u32) void {
    if (is_wasm) wasm.glDeleteVertexArrays(n, arrays) else gl_procs.DeleteVertexArrays(@intCast(n), @ptrCast(arrays));
}

pub fn glCreateShader(typ: u32) u32 {
    if (is_wasm) return wasm.glCreateShader(typ) else return @intCast(gl_procs.CreateShader(@intCast(typ)));
}

/// Simplified single-string shader source upload.
/// On native wraps the standard (shader, count, strings, lengths) signature.
/// The caller must ensure `src[0..len]` is the complete source.
pub fn glShaderSource(shader: u32, src: [*:0]const u8, len: i32) void {
    if (is_wasm) {
        wasm.glShaderSource(shader, src, len);
    } else {
        const src_ptr: [*c]const [*c]const c.GLchar = @ptrCast(&src);
        gl_procs.ShaderSource(@intCast(shader), 1, src_ptr, @ptrCast(&len));
    }
}

pub fn glCompileShader(shader: u32) void {
    if (is_wasm) wasm.glCompileShader(shader) else gl_procs.CompileShader(@intCast(shader));
}

pub fn glCreateProgram() u32 {
    if (is_wasm) return wasm.glCreateProgram() else return @intCast(gl_procs.CreateProgram());
}

pub fn glAttachShader(program: u32, shader: u32) void {
    if (is_wasm) wasm.glAttachShader(program, shader) else gl_procs.AttachShader(@intCast(program), @intCast(shader));
}

pub fn glLinkProgram(program: u32) void {
    if (is_wasm) wasm.glLinkProgram(program) else gl_procs.LinkProgram(@intCast(program));
}

pub fn glUseProgram(program: u32) void {
    if (is_wasm) wasm.glUseProgram(program) else gl_procs.UseProgram(@intCast(program));
}

pub fn glGetUniformLocation(program: u32, name: [*:0]const u8) i32 {
    if (is_wasm) {
        return wasm.glGetUniformLocation(program, name, name.len);
    } else {
        return @intCast(gl_procs.GetUniformLocation(@intCast(program), @ptrCast(name)));
    }
}

pub fn glUniform4f(loc: i32, x: f32, y: f32, z: f32, w: f32) void {
    if (is_wasm) wasm.glUniform4f(loc, x, y, z, w) else gl_procs.Uniform4f(loc, x, y, z, w);
}

pub fn glUniformMatrix4fv(loc: i32, count: i32, transpose: u32, data: [*]const f32) void {
    if (is_wasm) {
        wasm.glUniformMatrix4fv(loc, count, transpose, data);
    } else {
        gl_procs.UniformMatrix4fv(loc, count, @intCast(transpose), @ptrCast(data));
    }
}

pub fn glDeleteShader(shader: u32) void {
    if (is_wasm) wasm.glDeleteShader(shader) else gl_procs.DeleteShader(@intCast(shader));
}

pub fn glDeleteProgram(program: u32) void {
    if (is_wasm) wasm.glDeleteProgram(program) else gl_procs.DeleteProgram(@intCast(program));
}

pub fn glDeleteBuffers(n: i32, buffers: [*]const u32) void {
    if (is_wasm) wasm.glDeleteBuffers(n, buffers) else gl_procs.DeleteBuffers(@intCast(n), @ptrCast(buffers));
}

// ---------------------------------------------------------------------------
// Wasm-only helpers (backward compat with existing wasm entrypoint)
// ---------------------------------------------------------------------------

/// Write a string to the browser console (wasm) or stdout (native).
pub fn log(msg: []const u8) void {
    if (is_wasm) {
        wasm.jsLog(msg.ptr, msg.len);
    } else {
        const stdout = std.io.getStdOut().writer();
        stdout.print("{s}\n", .{msg}) catch {};
    }
}

/// Format and log — accepts a comptime format string and args, same as std.fmt.bufPrint.
/// Uses a fixed 512-byte stack buffer; messages longer than that are truncated.
pub fn logFmt(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..];
    log(msg);
}
