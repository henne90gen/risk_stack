const std = @import("std");
const t = std.testing;

pub const p = @import("platform.zig");
const zm = @import("zmath");
const f = @import("flip7.zig");

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

const card_texture_paths = [_][]const u8{
    "/cards/0.png",
    "/cards/1.png",
    "/cards/2.png",
    "/cards/3.png",
    "/cards/4.png",
    "/cards/5.png",
    "/cards/6.png",
    "/cards/7.png",
    "/cards/8.png",
    "/cards/9.png",
    "/cards/10.png",
    "/cards/11.png",
    "/cards/12.png",
    "/cards/second_chance.png",
    "/cards/freeze.png",
    "/cards/flip_three.png",
    "/cards/plus_2.png",
    "/cards/plus_4.png",
    "/cards/plus_6.png",
    "/cards/plus_8.png",
    "/cards/plus_10.png",
    "/cards/x2.png",
    "/cards/back.png",
};
const back_texture_index: usize = card_texture_paths.len - 1;

fn cardTextureIndex(card: f.Card) usize {
    return switch (card) {
        .Zero => 0,
        .One => 1,
        .Two => 2,
        .Three => 3,
        .Four => 4,
        .Five => 5,
        .Six => 6,
        .Seven => 7,
        .Eight => 8,
        .Nine => 9,
        .Ten => 10,
        .Eleven => 11,
        .Twelve => 12,
        .SecondChance => 13,
        .Freeze => 14,
        .FlipThree => 15,
        .PlusTwo => 16,
        .PlusFour => 17,
        .PlusSix => 18,
        .PlusEight => 19,
        .PlusTen => 20,
        .TimesTwo => 21,
    };
}

const ZoomState = struct {
    target: f32 = 1.0,
    current: f32 = 1.0,

    fn update_target(self: *ZoomState, delta: f32) void {
        const factor: f32 = 1.15;
        if (delta > 0) {
            self.target *= std.math.pow(f32, factor, delta);
        } else if (delta < 0) {
            self.target /= std.math.pow(f32, factor, -delta);
        }
        self.target = std.math.clamp(self.target, 0.25, 10.0);
    }

    fn update_current(self: *ZoomState) void {
        // Smooth zoom: exponentially lerp zoom_current toward zoom_target each frame.
        const lerp_speed: f32 = 0.18;
        self.current += (self.target - self.current) * lerp_speed;
    }
};

const OpenGLState = struct {
    tri_program: u32 = 0,
    tri_vao: u32 = 0,
    tri_vbo: u32 = 0,
    instance_vbo: u32 = 0,
    card_textures: [card_texture_paths.len]u32 = [_]u32{0} ** card_texture_paths.len,
    u_loc_texture: i32 = 0,
    u_loc_view: i32 = 0,
    u_loc_projection: i32 = 0,
};

const AnimationState = union(enum) {
    none: struct {},
    deal_card: struct {
        t: f32,
        // deck_pos: [2]f32,
        // player_pos: [2]f32,
        player: *f.Player,
    },
};

const AppState = struct {
    allocator: std.mem.Allocator,
    aspect_ratio: f32 = 1.0,
    gl: OpenGLState = .{},
    zoom: ZoomState = .{},
    animation: AnimationState = .{ .none = .{} },

    prng: std.Random.DefaultPrng,
    players: [3]f.Player,
    deck: f.Deck,
    simulation: f.GameSimulation = undefined,
    should_run_next_step: bool = false,
    next_event_to_process_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !AppState {
        var prng = std.Random.DefaultPrng.init(0);
        return AppState{
            .allocator = allocator,
            .prng = prng,
            .players = [_]f.Player{
                try .init(allocator, prng.random(), f.DrawStrategy{ .MinPoints = 20 }),
                try .init(allocator, prng.random(), f.DrawStrategy{ .MinPoints = 30 }),
                try .init(allocator, prng.random(), f.DrawStrategy{ .MinPoints = 40 }),
            },
            .deck = try f.Deck.init(allocator, prng.random()),
        };
    }

    pub fn resetInputTracking(self: *AppState) void {
        self.should_run_next_step = false;
    }
};

var app_state: AppState = undefined;

pub const TriangleApp = struct {
    pub fn onInit() void {
        app_state = AppState.init(std.heap.page_allocator) catch @panic("failed to initialize app state");
        app_state.simulation = f.GameSimulation.init(app_state.allocator, app_state.prng.random(), &app_state.deck, &app_state.players) catch @panic("failed to initialize game simulation");

        // --- shader program ------------------------------------------------
        const vert = glInitShader(vert_src, vert_src.len, p.GL_VERTEX_SHADER) catch std.debug.panic("vertex shader compilation failed", .{});
        const frag = glInitShader(frag_src, frag_src.len, p.GL_FRAGMENT_SHADER) catch std.debug.panic("fragment shader compilation failed", .{});
        app_state.gl.tri_program = glLinkShaderProgram(vert, frag) catch std.debug.panic("shader program linking failed", .{});

        // --- geometry -------------------------------------------------------
        p.glGenVertexArrays(1, @as([*]u32, @ptrCast(&app_state.gl.tri_vao)));
        p.glGenBuffers(1, @as([*]u32, @ptrCast(&app_state.gl.tri_vbo)));

        p.glBindVertexArray(app_state.gl.tri_vao);
        p.glBindBuffer(p.GL_ARRAY_BUFFER, app_state.gl.tri_vbo);
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

        // --- instance VBO (model matrices, per-instance) --------------------
        p.glGenBuffers(1, @as([*]u32, @ptrCast(&app_state.gl.instance_vbo)));
        p.glBindBuffer(p.GL_ARRAY_BUFFER, app_state.gl.instance_vbo);
        p.glBufferData(p.GL_ARRAY_BUFFER, 0, null, p.GL_DYNAMIC_DRAW);

        // A mat4 takes up 4 consecutive vec4 attribute slots (locations 2–5).
        p.glBindVertexArray(app_state.gl.tri_vao);
        const mat_stride: i32 = @sizeOf(zm.Mat);
        inline for (0..4) |col| {
            const slot: u32 = 2 + col;
            p.glEnableVertexAttribArray(slot);
            p.glVertexAttribPointer(
                slot,
                4,
                p.GL_FLOAT,
                p.GL_FALSE,
                mat_stride,
                @ptrFromInt(col * @sizeOf(zm.Vec)),
            );
            // Advance the attribute once per instance, not per vertex.
            p.glVertexAttribDivisor(slot, 1);
        }
        p.glBindBuffer(p.GL_ARRAY_BUFFER, 0);

        p.glBindVertexArray(0);

        // --- texture -----------------------------------------------------------
        for (card_texture_paths, 0..) |path, i| {
            app_state.gl.card_textures[i] = loadCardTexture(app_state.allocator, path) catch std.debug.panic("failed to load card texture", .{});
        }

        // Bind sampler uniform to texture unit 0, and cache uniform locations
        p.glUseProgram(app_state.gl.tri_program);

        app_state.gl.u_loc_texture = p.glGetUniformLocation(app_state.gl.tri_program, "uTexture");
        p.glUniform1i(app_state.gl.u_loc_texture, 0);

        app_state.gl.u_loc_view = p.glGetUniformLocation(app_state.gl.tri_program, "uView");
        p.glUniformMatrix4fv(app_state.gl.u_loc_view, 1, p.GL_TRUE, zm.arrNPtr(&zm.identity()));

        app_state.gl.u_loc_projection = p.glGetUniformLocation(app_state.gl.tri_program, "uProjection");
        p.glUniformMatrix4fv(app_state.gl.u_loc_projection, 1, p.GL_TRUE, zm.arrNPtr(&zm.identity()));

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
        switch (key) {
            p.Key.Escape => {
                p.logInfo("Escape key pressed, exiting...", .{});
                p.close();
            },
            p.Key.Space => {
                app_state.should_run_next_step = true;
            },
            else => p.logInfo("onKeyDown: {}", .{key}),
        }
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

    pub fn onMouseWheel(delta: f32) void {
        app_state.zoom.update_target(delta);
    }

    pub fn onMouseMove(x: f32, y: f32) void {
        _ = x;
        _ = y;
        // p.logInfo("onMouseMove: {} | {}", .{ x, y });
    }

    pub fn onAnimationFrame() void {
        render() catch |err| p.logErr("render failed: {}", .{err});
    }

    fn render() !void {
        p.glClearColor(0.1, 0.1, 0.1, 1.0);
        p.glClear(p.GL_COLOR_BUFFER_BIT);

        p.glUseProgram(app_state.gl.tri_program);
        p.glBindVertexArray(app_state.gl.tri_vao);

        // Orthographic top-down projection: X covers [-aspect, aspect], Y covers [-1, 1].
        const identity = zm.identity();
        p.glUniformMatrix4fv(app_state.gl.u_loc_view, 1, p.GL_TRUE, zm.arrNPtr(&identity));
        const ar = app_state.aspect_ratio;

        app_state.zoom.update_current();
        const half_w = ar / app_state.zoom.current;
        const half_h = 1.0 / app_state.zoom.current;
        const ortho = zm.orthographicOffCenterRh(-half_w, half_w, -half_h, half_h, -1.0, 1.0);
        p.glUniformMatrix4fv(app_state.gl.u_loc_projection, 1, p.GL_TRUE, zm.arrNPtr(&ortho));

        // Card dimensions in world units.
        const card_w: f32 = 0.12;
        const card_h: f32 = 0.17;
        const card_spacing: f32 = card_h * 1.1;

        // One instance list per texture; we issue a separate draw call per texture.
        var batches: [card_texture_paths.len]std.ArrayListUnmanaged(zm.Mat) = undefined;
        for (&batches) |*b| {
            b.* = .empty;
        }
        defer for (&batches) |*b| b.deinit(app_state.allocator);

        // Build a card transform: position (cx, cy), rotation angle (radians CCW), size (cw x ch).
        // Uses a 2-D TRS embedded in a 4x4 matrix.
        const addCard = struct {
            fn call(
                alloc: std.mem.Allocator,
                bs: *[card_texture_paths.len]std.ArrayListUnmanaged(zm.Mat),
                tex_idx: usize,
                cx: f32,
                cy: f32,
                angle: f32,
                cw: f32,
                ch: f32,
            ) !void {
                const cos_a = @cos(angle);
                const sin_a = @sin(angle);
                const m = zm.Mat{
                    zm.f32x4(cos_a * cw, sin_a * cw, 0, 0),
                    zm.f32x4(-sin_a * ch, cos_a * ch, 0, 0),
                    zm.f32x4(0, 0, 1, 0),
                    zm.f32x4(cx, cy, 0, 1),
                };
                try bs[tex_idx].append(alloc, zm.transpose(m));
            }
        }.call;

        switch (app_state.animation) {
            .deal_card => |*data| {
                data.t += 0.05;
                if (data.t >= 1.0) {
                    app_state.animation = .none;
                }
            },
            .none => {},
        }

        // Deck: single face-down card at the center.
        try addCard(app_state.allocator, &batches, back_texture_index, 0.0, 0.0, 0.0, card_w, card_h);

        // Players arranged in a circle.
        const num_players = app_state.players.len;
        const radius: f32 = 0.72;
        for (&app_state.players, 0..) |*player, pi| {
            // Spread players evenly; first player starts at the bottom.
            const base_angle: f32 = -std.math.pi / 2.0 +
                @as(f32, @floatFromInt(pi)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(num_players)));

            const px: f32 = radius * @cos(base_angle);
            const py: f32 = radius * @sin(base_angle);

            // Cards face inward (toward the center).
            var card_angle: f32 = base_angle + std.math.pi;

            // Perpendicular direction to spread cards in a row.
            const perp_x: f32 = -@sin(base_angle);
            const perp_y: f32 = @cos(base_angle);

            const n = player.hand.items.len;
            if (n == 0) {
                continue;
            }

            const total_width: f32 = @as(f32, @floatFromInt(n - 1)) * card_spacing;
            for (player.hand.items, 0..) |card, ci| {
                const offset: f32 = -total_width / 2.0 + @as(f32, @floatFromInt(ci)) * card_spacing;
                var cx = px + perp_x * offset;
                var cy = py + perp_y * offset;

                switch (app_state.animation) {
                    .deal_card => |data| {
                        if (data.player == player and ci == player.hand.items.len - 1) {
                            const result_pos = zm.lerp(zm.f32x4(0.0, 0.0, 0.0, 0.0), zm.f32x4(cx, cy, 0.0, 0.0), data.t);
                            cx = result_pos[0];
                            cy = result_pos[1];
                            card_angle = std.math.lerp(0.0, card_angle, data.t);
                        }
                    },
                    else => {},
                }

                try addCard(app_state.allocator, &batches, cardTextureIndex(card), cx, cy, card_angle, card_w, card_h);
            }
        }

        // Issue one draw call per texture batch
        for (&batches, 0..) |*batch, ti| {
            if (batch.items.len == 0) {
                continue;
            }

            p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.card_textures[ti]);
            p.glBindBuffer(p.GL_ARRAY_BUFFER, app_state.gl.instance_vbo);
            p.glBufferData(
                p.GL_ARRAY_BUFFER,
                batch.items.len * @sizeOf(zm.Mat),
                batch.items.ptr,
                p.GL_DYNAMIC_DRAW,
            );
            p.glBindBuffer(p.GL_ARRAY_BUFFER, 0);
            p.glDrawArraysInstanced(p.GL_TRIANGLES, 0, 6, @intCast(batch.items.len));
        }

        p.glBindVertexArray(0);
        p.glBindTexture(p.GL_TEXTURE_2D, 0);
        p.glUseProgram(0);

        if (app_state.should_run_next_step) {
            const game_should_continue = try app_state.simulation.step();
            if (!game_should_continue) {
                const game_result = app_state.simulation.result();
                p.logInfo("game finished -> strategy {} won", .{game_result.winning_strategy});
            } else {
                if (app_state.simulation.events.items.len != 0) {
                    const events = app_state.simulation.events.items[app_state.next_event_to_process_index..app_state.simulation.events.items.len];
                    app_state.next_event_to_process_index = app_state.simulation.events.items.len;
                    for (events) |event| {
                        p.logInfo("event: {}", .{event});
                        switch (event) {
                            .DrawCard => |data| {
                                app_state.animation = .{ .deal_card = .{ .player = data.player, .t = 0.0 } };
                                p.logInfo("created animation", .{});
                            },
                            else => {},
                        }
                    }
                }
            }
        }

        app_state.resetInputTracking();
    }
};

fn glInitShader(src: [:0]const u8, len: i32, typ: u32) !u32 {
    const shader = p.glCreateShader(typ);
    p.glShaderSource(shader, src, len);
    p.glCompileShader(shader);
    var status: i32 = 0;
    p.glGetShaderiv(shader, p.GL_COMPILE_STATUS, &status);
    if (status == p.GL_FALSE) {
        var log_buf: [1024]u8 = undefined;
        var log_len: usize = 0;
        p.glGetShaderInfoLog(shader, log_buf[0..], &log_len);
        p.logErr("shader compilation failed:\n{s}", .{log_buf[0..log_len]});
        p.glDeleteShader(shader);
        return error.ShaderCompilationFailed;
    }
    return shader;
}

fn glLinkShaderProgram(vert: u32, frag: u32) !u32 {
    const prog = p.glCreateProgram();
    p.glAttachShader(prog, vert);
    p.glAttachShader(prog, frag);
    p.glLinkProgram(prog);
    p.glDeleteShader(vert);
    p.glDeleteShader(frag);
    var status: i32 = 0;
    p.glGetProgramiv(prog, p.GL_LINK_STATUS, &status);
    if (status == p.GL_FALSE) {
        var log_buf: [1024]u8 = undefined;
        var log_len: usize = 0;
        p.glGetProgramInfoLog(prog, log_buf[0..], &log_len);
        p.logErr("shader program linking failed:\n{s}", .{log_buf[0..log_len]});
        p.glDeleteProgram(prog);
        return error.ShaderLinkFailed;
    }
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
