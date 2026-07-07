const std = @import("std");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_opengl.h");
});

// ---------------------------------------------------------------------------
// Runtime OpenGL function pointers (core 3.3 — no static GL linkage needed)
// ---------------------------------------------------------------------------

pub const Gl = struct {
    // Clear
    ClearColor: *const fn (c.GLfloat, c.GLfloat, c.GLfloat, c.GLfloat) callconv(.c) void,
    Clear: *const fn (c.GLbitfield) callconv(.c) void,
    // Draw
    DrawArrays: *const fn (c.GLenum, c.GLint, c.GLsizei) callconv(.c) void,
    // Shaders
    CreateShader: *const fn (c.GLenum) callconv(.c) c.GLuint,
    ShaderSource: *const fn (c.GLuint, c.GLsizei, [*c]const [*c]const c.GLchar, [*c]const c.GLint) callconv(.c) void,
    CompileShader: *const fn (c.GLuint) callconv(.c) void,
    GetShaderiv: *const fn (c.GLuint, c.GLenum, [*c]c.GLint) callconv(.c) void,
    GetShaderInfoLog: *const fn (c.GLuint, c.GLsizei, [*c]c.GLsizei, [*c]c.GLchar) callconv(.c) void,
    DeleteShader: *const fn (c.GLuint) callconv(.c) void,
    // Programs
    CreateProgram: *const fn () callconv(.c) c.GLuint,
    AttachShader: *const fn (c.GLuint, c.GLuint) callconv(.c) void,
    LinkProgram: *const fn (c.GLuint) callconv(.c) void,
    GetProgramiv: *const fn (c.GLuint, c.GLenum, [*c]c.GLint) callconv(.c) void,
    GetProgramInfoLog: *const fn (c.GLuint, c.GLsizei, [*c]c.GLsizei, [*c]c.GLchar) callconv(.c) void,
    UseProgram: *const fn (c.GLuint) callconv(.c) void,
    DeleteProgram: *const fn (c.GLuint) callconv(.c) void,
    // VAO / VBO
    GenVertexArrays: *const fn (c.GLsizei, [*c]c.GLuint) callconv(.c) void,
    BindVertexArray: *const fn (c.GLuint) callconv(.c) void,
    DeleteVertexArrays: *const fn (c.GLsizei, [*c]const c.GLuint) callconv(.c) void,
    GenBuffers: *const fn (c.GLsizei, [*c]c.GLuint) callconv(.c) void,
    BindBuffer: *const fn (c.GLenum, c.GLuint) callconv(.c) void,
    BufferData: *const fn (c.GLenum, c.GLsizeiptr, ?*const anyopaque, c.GLenum) callconv(.c) void,
    DeleteBuffers: *const fn (c.GLsizei, [*c]const c.GLuint) callconv(.c) void,
    EnableVertexAttribArray: *const fn (c.GLuint) callconv(.c) void,
    VertexAttribPointer: *const fn (c.GLuint, c.GLint, c.GLenum, c.GLboolean, c.GLsizei, ?*const anyopaque) callconv(.c) void,

    pub fn load() Gl {
        return .{
            .ClearColor = @ptrCast(raw("glClearColor")),
            .Clear = @ptrCast(raw("glClear")),
            .DrawArrays = @ptrCast(raw("glDrawArrays")),
            .CreateShader = @ptrCast(raw("glCreateShader")),
            .ShaderSource = @ptrCast(raw("glShaderSource")),
            .CompileShader = @ptrCast(raw("glCompileShader")),
            .GetShaderiv = @ptrCast(raw("glGetShaderiv")),
            .GetShaderInfoLog = @ptrCast(raw("glGetShaderInfoLog")),
            .DeleteShader = @ptrCast(raw("glDeleteShader")),
            .CreateProgram = @ptrCast(raw("glCreateProgram")),
            .AttachShader = @ptrCast(raw("glAttachShader")),
            .LinkProgram = @ptrCast(raw("glLinkProgram")),
            .GetProgramiv = @ptrCast(raw("glGetProgramiv")),
            .GetProgramInfoLog = @ptrCast(raw("glGetProgramInfoLog")),
            .UseProgram = @ptrCast(raw("glUseProgram")),
            .DeleteProgram = @ptrCast(raw("glDeleteProgram")),
            .GenVertexArrays = @ptrCast(raw("glGenVertexArrays")),
            .BindVertexArray = @ptrCast(raw("glBindVertexArray")),
            .DeleteVertexArrays = @ptrCast(raw("glDeleteVertexArrays")),
            .GenBuffers = @ptrCast(raw("glGenBuffers")),
            .BindBuffer = @ptrCast(raw("glBindBuffer")),
            .BufferData = @ptrCast(raw("glBufferData")),
            .DeleteBuffers = @ptrCast(raw("glDeleteBuffers")),
            .EnableVertexAttribArray = @ptrCast(raw("glEnableVertexAttribArray")),
            .VertexAttribPointer = @ptrCast(raw("glVertexAttribPointer")),
        };
    }

    fn raw(comptime name: [:0]const u8) *const anyopaque {
        return @ptrCast(c.SDL_GL_GetProcAddress(name) orelse
            @panic("failed to load GL proc: " ++ name));
    }
};

// ---------------------------------------------------------------------------
// Shader source
// ---------------------------------------------------------------------------

const vert_src: [*:0]const u8 =
    \\#version 330 core
    \\layout (location = 0) in vec2 aPos;
    \\layout (location = 1) in vec3 aColor;
    \\out vec3 vColor;
    \\void main() {
    \\    gl_Position = vec4(aPos, 0.0, 1.0);
    \\    vColor = aColor;
    \\}
;

const frag_src: [*:0]const u8 =
    \\#version 330 core
    \\in vec3 vColor;
    \\out vec4 fragColor;
    \\void main() {
    \\    fragColor = vec4(vColor, 1.0);
    \\}
;

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

pub const Error = error{
    SdlInit,
    WindowCreate,
    GlContextCreate,
    ShaderCompile,
    ProgramLink,
};

// ---------------------------------------------------------------------------
// Triangle
// ---------------------------------------------------------------------------

/// A GPU-resident coloured triangle.  Create after the GL context is current.
pub const Triangle = struct {
    gl: Gl,
    program: c.GLuint,
    vao: c.GLuint,
    vbo: c.GLuint,

    // interleaved layout: x, y, r, g, b  (f32)
    const vertices = [_]f32{
        //  x      y      r     g     b
        0.0, 0.5, 1.0, 0.0, 0.0, // top – red
        -0.5, -0.5, 0.0, 1.0, 0.0, // bottom-left – green
        0.5, -0.5, 0.0, 0.0, 1.0, // bottom-right – blue
    };

    pub fn init() Error!Triangle {
        const gl = Gl.load();

        const program = try compileProgram(gl);

        var vao: c.GLuint = 0;
        var vbo: c.GLuint = 0;
        gl.GenVertexArrays(1, &vao);
        gl.GenBuffers(1, &vbo);

        gl.BindVertexArray(vao);
        gl.BindBuffer(c.GL_ARRAY_BUFFER, vbo);
        gl.BufferData(
            c.GL_ARRAY_BUFFER,
            @sizeOf(@TypeOf(vertices)),
            &vertices,
            c.GL_STATIC_DRAW,
        );

        const stride: c.GLsizei = 5 * @sizeOf(f32);
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(0));
        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));

        gl.BindVertexArray(0);

        return .{ .gl = gl, .program = program, .vao = vao, .vbo = vbo };
    }

    pub fn deinit(self: *Triangle) void {
        self.gl.DeleteBuffers(1, &self.vbo);
        self.gl.DeleteVertexArrays(1, &self.vao);
        self.gl.DeleteProgram(self.program);
    }

    pub fn draw(self: *const Triangle) void {
        self.gl.UseProgram(self.program);
        self.gl.BindVertexArray(self.vao);
        self.gl.DrawArrays(c.GL_TRIANGLES, 0, 3);
        self.gl.BindVertexArray(0);
    }

    // -- helpers -------------------------------------------------------------

    fn compileShader(gl: Gl, kind: c.GLenum, src: [*:0]const u8) Error!c.GLuint {
        const shader = gl.CreateShader(kind);
        const src_ptr: [*c]const [*c]const c.GLchar = @ptrCast(&src);
        gl.ShaderSource(shader, 1, src_ptr, null);
        gl.CompileShader(shader);

        var ok: c.GLint = 0;
        gl.GetShaderiv(shader, c.GL_COMPILE_STATUS, &ok);
        if (ok == 0) {
            var buf: [512]c.GLchar = undefined;
            gl.GetShaderInfoLog(shader, 512, null, &buf);
            std.log.err("shader compile error: {s}", .{buf});
            gl.DeleteShader(shader);
            return error.ShaderCompile;
        }
        return shader;
    }

    fn compileProgram(gl: Gl) Error!c.GLuint {
        const vs = try compileShader(gl, c.GL_VERTEX_SHADER, vert_src);
        const fs = try compileShader(gl, c.GL_FRAGMENT_SHADER, frag_src);

        const prog = gl.CreateProgram();
        gl.AttachShader(prog, vs);
        gl.AttachShader(prog, fs);
        gl.LinkProgram(prog);

        gl.DeleteShader(vs);
        gl.DeleteShader(fs);

        var ok: c.GLint = 0;
        gl.GetProgramiv(prog, c.GL_LINK_STATUS, &ok);
        if (ok == 0) {
            var buf: [512]c.GLchar = undefined;
            gl.GetProgramInfoLog(prog, 512, null, &buf);
            std.log.err("program link error: {s}", .{buf});
            gl.DeleteProgram(prog);
            return error.ProgramLink;
        }
        return prog;
    }
};

pub const GL_COLOR_BUFFER_BIT: c.GLbitfield = c.GL_COLOR_BUFFER_BIT;

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

pub const Window = struct {
    window: *c.SDL_Window,
    gl_ctx: c.SDL_GLContext,

    pub fn init(title: [*:0]const u8, width: c_int, height: c_int) Error!Window {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            std.log.err("SDL_Init failed: {s}", .{c.SDL_GetError()});
            return error.SdlInit;
        }

        // Request an OpenGL 3.3 core profile context.
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);

        const window = c.SDL_CreateWindow(
            title,
            width,
            height,
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE,
        ) orelse {
            std.log.err("SDL_CreateWindow failed: {s}", .{c.SDL_GetError()});
            return error.WindowCreate;
        };

        const gl_ctx = c.SDL_GL_CreateContext(window) orelse {
            std.log.err("SDL_GL_CreateContext failed: {s}", .{c.SDL_GetError()});
            c.SDL_DestroyWindow(window);
            return error.GlContextCreate;
        };

        _ = c.SDL_GL_MakeCurrent(window, gl_ctx);
        _ = c.SDL_GL_SetSwapInterval(1); // vsync

        return .{ .window = window, .gl_ctx = gl_ctx };
    }

    pub fn deinit(self: Window) void {
        _ = c.SDL_GL_DestroyContext(self.gl_ctx);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    /// Run a simple event loop.  `ctx` is passed to `draw_fn` each frame.
    /// Returns when the user closes the window.
    pub fn run(self: Window, ctx: anytype, draw_fn: fn (@TypeOf(ctx)) void) void {
        var event: c.SDL_Event = undefined;
        main: while (true) {
            while (c.SDL_PollEvent(&event)) {
                if (event.type == c.SDL_EVENT_QUIT) break :main;
            }

            draw_fn(ctx);

            _ = c.SDL_GL_SwapWindow(self.window);
        }
    }
};
