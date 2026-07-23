const std = @import("std");
const t = std.testing;

pub const p = @import("platform.zig");
const zm = @import("zmath");
const f = @import("flip7.zig");
const text = @import("text.zig");

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
    -0.5, -0.5, 0.0, 0.0, // bottom-left
    0.5, -0.5, 1.0, 0.0, // bottom-right
    0.5, 0.5, 1.0, 1.0, // top-right
    -0.5, -0.5, 0.0, 0.0, // bottom-left
    0.5, 0.5, 1.0, 1.0, // top-right
    -0.5, 0.5, 0.0, 1.0, // top-left
};

const Instance = extern struct {
    model: zm.Mat align(1),
    uv_rect: zm.Vec align(1),
    color: zm.Vec align(1),
    render_type: i32 align(1),
};

const card_texture_paths = [_][]const u8{
    "cards/0.png",
    "cards/1.png",
    "cards/2.png",
    "cards/3.png",
    "cards/4.png",
    "cards/5.png",
    "cards/6.png",
    "cards/7.png",
    "cards/8.png",
    "cards/9.png",
    "cards/10.png",
    "cards/11.png",
    "cards/12.png",
    "cards/second_chance.png",
    "cards/freeze.png",
    "cards/flip_three.png",
    "cards/plus_2.png",
    "cards/plus_4.png",
    "cards/plus_6.png",
    "cards/plus_8.png",
    "cards/plus_10.png",
    "cards/x2.png",
    "cards/back.png",
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
    card_atlas_texture: u32 = 0,
    font_atlas_texture: u32 = 0,
    u_loc_card_texture: i32 = 0,
    u_loc_font_texture: i32 = 0,
    u_loc_view: i32 = 0,
    u_loc_projection: i32 = 0,
};

const Animation = union(enum) {
    deal_card: struct {
        player: *f.Player,
        card: f.Card,
        t: f32 = 0.0,
    },
    freeze_player: struct {
        freezing_player: *f.Player,
        frozen_player: *f.Player,
        t: f32 = 0.0,
    },
};

const AnimationState = struct {
    queue: std.ArrayList(Animation),

    pub fn init(allocator: std.mem.Allocator) !AnimationState {
        return AnimationState{
            .queue = try std.ArrayList(Animation).initCapacity(allocator, 10),
        };
    }
};

const AppState = struct {
    allocator: std.mem.Allocator,
    aspect_ratio: f32 = 1.0,
    gl: OpenGLState = .{},
    zoom: ZoomState = .{},
    animation: AnimationState,
    font: text.Font = .{},
    cards: CardTextures = .{},

    prng: std.Random,
    players: [3]f.Player,
    deck: f.Deck,
    simulation: f.GameSimulation = undefined,
    should_run_next_step: bool = false,
    next_event_to_process_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator, seed: u64) !AppState {
        var r = std.Random.DefaultPrng.init(seed);
        const prng = r.random();
        const deck = try f.Deck.init(allocator, prng);
        return AppState{
            .allocator = allocator,
            .animation = try AnimationState.init(allocator),
            .prng = prng,
            .players = [_]f.Player{
                try .init(allocator, prng, f.DrawStrategy{ .MinPoints = 20 }),
                try .init(allocator, prng, f.DrawStrategy{ .MinPoints = 30 }),
                try .init(allocator, prng, f.DrawStrategy{ .MinPoints = 40 }),
            },
            .deck = deck,
        };
    }

    pub fn resetInputTracking(self: *AppState) void {
        self.should_run_next_step = false;
    }
};

var app_state: AppState = undefined;

pub const Flip7App = struct {
    pub fn onInit(seed: c_ulong) void {
        app_state = AppState.init(std.heap.page_allocator, seed) catch @panic("failed to initialize app state");
        app_state.simulation = f.GameSimulation.init(app_state.allocator, app_state.prng, &app_state.deck, &app_state.players) catch @panic("failed to initialize game simulation");

        const vert = glInitShader(vert_src, vert_src.len, p.GL_VERTEX_SHADER) catch std.debug.panic("vertex shader compilation failed", .{});
        const frag = glInitShader(frag_src, frag_src.len, p.GL_FRAGMENT_SHADER) catch std.debug.panic("fragment shader compilation failed", .{});
        app_state.gl.tri_program = glLinkShaderProgram(vert, frag) catch std.debug.panic("shader program linking failed", .{});

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

        p.glGenBuffers(1, @as([*]u32, @ptrCast(&app_state.gl.instance_vbo)));
        p.glBindBuffer(p.GL_ARRAY_BUFFER, app_state.gl.instance_vbo);
        p.glBufferData(p.GL_ARRAY_BUFFER, 0, null, p.GL_DYNAMIC_DRAW);

        // aModel: location 2-5, mat4
        p.glBindVertexArray(app_state.gl.tri_vao);
        const instance_stride: i32 = @sizeOf(Instance);
        inline for (0..4) |col| {
            const slot: u32 = 2 + col;
            p.glEnableVertexAttribArray(slot);
            p.glVertexAttribPointer(
                slot,
                4,
                p.GL_FLOAT,
                p.GL_FALSE,
                instance_stride,
                @ptrFromInt(col * @sizeOf(zm.Vec)),
            );
            p.glVertexAttribDivisor(slot, 1);
        }
        // aUVRect: location 6, vec4 (u0, v0, u1, v1), after the mat4.
        p.glEnableVertexAttribArray(6);
        p.glVertexAttribPointer(
            6,
            4,
            p.GL_FLOAT,
            p.GL_FALSE,
            instance_stride,
            @ptrFromInt(@offsetOf(Instance, "uv_rect")),
        );
        p.glVertexAttribDivisor(6, 1);
        // aColor: location 7, vec4
        p.glEnableVertexAttribArray(7);
        p.glVertexAttribPointer(
            7,
            4,
            p.GL_FLOAT,
            p.GL_FALSE,
            instance_stride,
            @ptrFromInt(@offsetOf(Instance, "color")),
        );
        p.glVertexAttribDivisor(7, 1);
        // aRenderType: location 8, int
        p.glEnableVertexAttribArray(8);
        p.glVertexAttribIPointer(
            8,
            1,
            p.GL_INT,
            instance_stride,
            @ptrFromInt(@offsetOf(Instance, "render_type")),
        );
        p.glVertexAttribDivisor(8, 1);
        p.glBindBuffer(p.GL_ARRAY_BUFFER, 0);

        p.glBindVertexArray(0);

        app_state.cards = loadCardTextures(app_state.allocator, &card_texture_paths, 8, 3) catch |err| std.debug.panic("failed to load card textures: {}", .{err});
        p.glGenTextures(1, @as([*]u32, @ptrCast(&app_state.gl.card_atlas_texture)));
        p.glActiveTexture(p.GL_TEXTURE0);
        p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.card_atlas_texture);

        p.glTexImage2D(
            p.GL_TEXTURE_2D,
            0,
            @intCast(p.GL_RGBA8),
            @intCast(app_state.cards.buffer_width),
            @intCast(app_state.cards.buffer_height),
            0,
            p.GL_RGBA,
            p.GL_UNSIGNED_BYTE,
            app_state.cards.texture_buffer.ptr,
            app_state.cards.texture_buffer.len,
        );

        p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_MIN_FILTER, @intCast(p.GL_LINEAR_MIPMAP_LINEAR));
        p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_MAG_FILTER, @intCast(p.GL_LINEAR));
        p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_WRAP_S, @intCast(p.GL_CLAMP_TO_EDGE));
        p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_WRAP_T, @intCast(p.GL_CLAMP_TO_EDGE));
        p.glGenerateMipmap(p.GL_TEXTURE_2D);

        p.glBindTexture(p.GL_TEXTURE_2D, 0);

        // Bind sampler uniform to texture unit 0, and cache uniform locations
        p.glUseProgram(app_state.gl.tri_program);

        app_state.gl.u_loc_card_texture = p.glGetUniformLocation(app_state.gl.tri_program, "uCardTexture");
        p.glUniform1i(app_state.gl.u_loc_card_texture, 0);

        app_state.gl.u_loc_font_texture = p.glGetUniformLocation(app_state.gl.tri_program, "uFontTexture");
        p.glUniform1i(app_state.gl.u_loc_font_texture, 1);

        app_state.gl.u_loc_view = p.glGetUniformLocation(app_state.gl.tri_program, "uView");
        p.glUniformMatrix4fv(app_state.gl.u_loc_view, 1, p.GL_TRUE, zm.arrNPtr(&zm.identity()));

        app_state.gl.u_loc_projection = p.glGetUniformLocation(app_state.gl.tri_program, "uProjection");
        p.glUniformMatrix4fv(app_state.gl.u_loc_projection, 1, p.GL_TRUE, zm.arrNPtr(&zm.identity()));

        p.glUseProgram(0);

        app_state.font = text.Font.init(app_state.allocator) catch |err| std.debug.panic("failed to initialize font: {}", .{err});
        p.logInfo("Loaded font.", .{});

        p.glGenTextures(1, @as([*]u32, @ptrCast(&app_state.gl.font_atlas_texture)));
        p.glActiveTexture(p.GL_TEXTURE1);
        p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.font_atlas_texture);
        p.glTexImage2D(
            p.GL_TEXTURE_2D,
            0,
            @intCast(p.GL_R8),
            @intCast(app_state.font.atlas_width),
            @intCast(app_state.font.atlas_height),
            0,
            p.GL_RED,
            p.GL_UNSIGNED_BYTE,
            app_state.font.texture_atlas_buffer.ptr,
            app_state.font.texture_atlas_buffer.len,
        );
        p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_MIN_FILTER, @intCast(p.GL_LINEAR));
        p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_MAG_FILTER, @intCast(p.GL_LINEAR));
        p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_WRAP_S, @intCast(p.GL_CLAMP_TO_EDGE));
        p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_WRAP_T, @intCast(p.GL_CLAMP_TO_EDGE));
        p.glBindTexture(p.GL_TEXTURE_2D, 0);

        p.glEnable(p.GL_BLEND);
        p.glBlendFunc(p.GL_SRC_ALPHA, p.GL_ONE_MINUS_SRC_ALPHA);
    }

    pub fn onResize(w: c_uint, h: c_uint, scale: f32) void {
        p.logInfo("resizing to new dimensions {}x{} with scale {}", .{ w, h, scale });

        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);

        const pw: f32 = @round(fw * scale);
        const ph: f32 = @round(fh * scale);

        p.glViewport(0, 0, @intFromFloat(pw), @intFromFloat(ph));

        app_state.aspect_ratio = pw / ph;
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
        update() catch |err| p.logErr("update failed: {}", .{err});
        render() catch |err| p.logErr("render failed: {}", .{err});
    }

    fn update() !void {
        for (app_state.animation.queue.items) |*animation| {
            switch (animation.*) {
                .deal_card => |*data| {
                    data.t += 0.05;
                    if (data.t >= 1.0) {
                        _ = app_state.animation.queue.orderedRemove(0);
                    }
                },
                .freeze_player => |*data| {
                    data.t += 0.03;
                    if (data.t >= 1.0) {
                        _ = app_state.animation.queue.orderedRemove(0);
                    }
                },
            }
            return;
        }

        if (!app_state.should_run_next_step) {
            return;
        }
        app_state.resetInputTracking();

        const game_should_continue = try app_state.simulation.step();
        if (!game_should_continue) {
            const game_result = app_state.simulation.result();
            p.logInfo("game finished -> strategy {} won", .{game_result.winning_strategy});
            return;
        }

        if (app_state.simulation.events.items.len == 0) {
            return;
        }

        const events = app_state.simulation.events.items[app_state.next_event_to_process_index..];
        app_state.next_event_to_process_index = app_state.simulation.events.items.len;
        for (events) |event| {
            switch (event) {
                .DrawCard => |d| p.logInfo("{} DrawCard {} {any} {}", .{ app_state.simulation.events.items.len, d.card, d.player.hand.items, d.player.strategy }),
                .PlayerEndRound => |d| p.logInfo("{} PlayerEndRound {any} {}", .{ app_state.simulation.events.items.len, d.player.hand.items, d.player.strategy }),
                else => p.logInfo("{} {}", .{ app_state.simulation.events.items.len, event }),
            }

            switch (event) {
                .DrawCard => |data| {
                    try app_state.animation.queue.append(app_state.allocator, .{ .deal_card = .{ .player = data.player, .card = data.card } });
                },
                .PlayerFrozen => |data| {
                    try app_state.animation.queue.append(app_state.allocator, .{ .freeze_player = .{ .freezing_player = data.freezing_player, .frozen_player = data.frozen_player } });
                },
                else => {},
            }
        }
    }

    fn render() !void {
        var frame_arena = std.heap.ArenaAllocator.init(app_state.allocator);
        defer _ = frame_arena.reset(.retain_capacity);
        const frame_allocator = frame_arena.allocator();

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
        const ortho = zm.orthographicOffCenterRh(-half_w, half_w, half_h, -half_h, -1.0, 1.0);
        p.glUniformMatrix4fv(app_state.gl.u_loc_projection, 1, p.GL_TRUE, zm.arrNPtr(&ortho));

        // Card dimensions in world units.
        const card_w: f32 = 0.12;
        const card_h: f32 = 0.17;
        const card_spacing: f32 = card_w * 1.1;

        var instances: std.ArrayList(Instance) = try .initCapacity(frame_allocator, 20);
        defer instances.deinit(frame_allocator);

        const addCard = struct {
            fn call(
                alloc: std.mem.Allocator,
                inst: *std.ArrayList(Instance),
                cards: *CardTextures,
                card_idx: usize,
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
                const card_atlas_entry = &cards.card_atlas[card_idx];
                const uv_rect = zm.f32x4(
                    card_atlas_entry.top_left_u,
                    card_atlas_entry.top_left_v,
                    card_atlas_entry.bottom_right_u,
                    card_atlas_entry.bottom_right_v,
                );
                try inst.append(alloc, .{
                    .model = zm.transpose(m),
                    .uv_rect = uv_rect,
                    .color = zm.f32x4(0, 0, 0, 0),
                    .render_type = 0,
                });
            }
        }.call;

        const TextParameters = struct {
            x: f32 = 0.0,
            y: f32 = 0.0,
            offset_anchor_x: f32 = 0.0,
            offset_anchor_y: f32 = 0.0,
            angle: f32 = 0.0,
            scale: f32 = 1.0,
        };

        const addText = struct {
            fn call(
                alloc: std.mem.Allocator,
                inst: *std.ArrayList(Instance),
                txt: []const u8,
                text_params: TextParameters,
            ) !void {
                var letter_draw_data = try app_state.font.drawText(alloc, txt, text_params.scale);
                defer letter_draw_data.deinit(alloc);

                const rotation_matrix = zm.rotationZ(text_params.angle);
                const translation_matrix = zm.translation(text_params.x, text_params.y, 0.0);
                for (letter_draw_data.items) |item| {
                    const letter_translation_matrix = zm.translation(item.x + text_params.offset_anchor_x, item.y + text_params.offset_anchor_y, 0.0);
                    const scale_matrix = zm.scaling(item.width, item.height, 1.0);
                    const model_matrix = zm.mul(scale_matrix, zm.mul(zm.mul(letter_translation_matrix, rotation_matrix), translation_matrix));
                    try inst.append(alloc, .{
                        .model = zm.transpose(model_matrix),
                        .uv_rect = item.uv_rect,
                        .color = zm.f32x4(0, 1.0, 1.0, 1.0),
                        .render_type = 1,
                    });
                }
            }
        }.call;

        // Deck: single face-down card at the center.
        try addCard(frame_allocator, &instances, &app_state.cards, back_texture_index, 0.0, 0.0, std.math.pi, card_w, card_h);

        // Players arranged in a circle.
        const num_players = app_state.players.len;
        const radius: f32 = 0.5;
        const text_radius: f32 = 0.7;
        for (&app_state.players, 0..) |*player, pi| {
            // Spread players evenly; first player starts at the bottom.
            const base_angle: f32 = -std.math.pi / 2.0 +
                @as(f32, @floatFromInt(pi)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(num_players)));

            const px: f32 = radius * @cos(base_angle);
            const py: f32 = radius * @sin(base_angle);

            // Cards face inward (toward the center).
            var card_angle: f32 = base_angle + std.math.pi / 2.0;
            if (py < 0.0) {
                card_angle += std.math.pi;
            }

            // Perpendicular direction to spread cards in a row.
            const perp_x: f32 = -@sin(base_angle);
            const perp_y: f32 = @cos(base_angle);

            const score = player.handScore();
            const score_text = try std.fmt.allocPrint(frame_allocator, "{d} ({d})", .{ score, player.score });
            defer frame_allocator.free(score_text);

            const font_scale = 0.05;
            const text_dimensions = app_state.font.textDimensions(score_text, font_scale);
            const text_x: f32 = text_radius * @cos(base_angle);
            const text_y: f32 = text_radius * @sin(base_angle);
            var text_angle = base_angle + std.math.pi / 2.0;
            if (py > 0.0) {
                text_angle += std.math.pi;
            }
            try addText(frame_allocator, &instances, score_text, .{
                .x = text_x,
                .y = text_y,
                .offset_anchor_x = -0.5 * text_dimensions[0],
                .offset_anchor_y = 0.0,
                .angle = text_angle,
                .scale = font_scale,
            });

            const n = player.hand.items.len;
            if (n == 0) {
                continue;
            }

            // Count how many deal_card animations are pending in the queue for this player
            // (excluding special cards). The first matching animation is active; the rest
            // are waiting and their cards should not be rendered yet.
            var pending_deal_count: usize = 0;
            var active_deal_anim: ?Animation = null;
            for (app_state.animation.queue.items) |animation| {
                switch (animation) {
                    .deal_card => |data| {
                        if (data.card == .Freeze or data.card == .FlipThree) continue;
                        if (data.player != player) continue;
                        if (active_deal_anim == null) {
                            active_deal_anim = animation;
                        } else {
                            pending_deal_count += 1;
                        }
                    },
                    else => {},
                }
            }

            // Cards at the tail of the hand that are still waiting in the animation
            // queue should not be rendered until their animation becomes active.
            const visible_card_count = n - pending_deal_count;

            const tapped_spacing: f32 = card_h * 1.1;
            const effective_spacing: f32 = if (player.state == .Eliminated) tapped_spacing else card_spacing;
            const total_width: f32 = @as(f32, @floatFromInt(n - 1)) * effective_spacing;
            for (player.hand.items, 0..) |card, ci| {
                // Skip cards that are still waiting in the animation queue.
                if (ci >= visible_card_count) continue;

                var local_card_angle = card_angle;
                const offset: f32 = -total_width / 2.0 + @as(f32, @floatFromInt(ci)) * effective_spacing;
                var cx = px + perp_x * offset;
                var cy = py + perp_y * offset;

                if (active_deal_anim) |anim| {
                    const data = anim.deal_card;
                    if (ci == visible_card_count - 1) {
                        const result_pos = zm.lerp(zm.f32x4(0.0, 0.0, 0.0, 0.0), zm.f32x4(cx, cy, 0.0, 0.0), data.t);
                        cx = result_pos[0];
                        cy = result_pos[1];

                        var start_angle: f32 = 0.0;
                        if (local_card_angle > std.math.pi) {
                            start_angle = std.math.pi * 2.0;
                        }
                        local_card_angle = std.math.lerp(start_angle, local_card_angle, data.t);
                    }
                }

                if (player.state == .RoundEnded and ci == 0) {
                    local_card_angle += std.math.pi / 2.0;
                    cx -= perp_x * (card_w / 2.0);
                    cy -= perp_y * (card_w / 2.0);
                }

                if (player.state == .Eliminated) {
                    local_card_angle += std.math.pi / 2.0;
                }

                try addCard(frame_allocator, &instances, &app_state.cards, cardTextureIndex(card), cx, cy, local_card_angle, card_w, card_h);
            }

            // render drawing flipthree/freeze card animation
            for (app_state.animation.queue.items) |animation| {
                switch (animation) {
                    .deal_card => |data| {
                        if (data.card != .Freeze and data.card != .FlipThree) continue;
                        if (data.player != player) continue;

                        var local_card_angle = card_angle;
                        // animate to the center of the players hand
                        // const offset: f32 = -total_width / 2.0 + @as(f32, @floatFromInt(0)) * card_spacing;
                        // var cx = px + perp_x * offset;
                        // var cy = py + perp_y * offset;

                        const result_pos = zm.lerp(zm.f32x4(0.0, 0.0, 0.0, 0.0), zm.f32x4(px, py, 0.0, 0.0), data.t);
                        const cx = result_pos[0];
                        const cy = result_pos[1];

                        var start_angle: f32 = 0.0;
                        if (local_card_angle > std.math.pi) {
                            start_angle = std.math.pi * 2.0;
                        }
                        local_card_angle = std.math.lerp(start_angle, local_card_angle, data.t);

                        try addCard(frame_allocator, &instances, &app_state.cards, cardTextureIndex(data.card), cx, cy, local_card_angle, card_w, card_h);
                    },
                    else => {},
                }
                break;
            }

            // render freeze card in front of player if they are frozen
            // but not while a freeze animation targeting this player is still pending
            const freeze_anim_pending = for (app_state.animation.queue.items) |anim| {
                if (anim == .freeze_player and anim.freeze_player.frozen_player == player) break true;
            } else false;
            if (player.state == .Frozen and !freeze_anim_pending) {
                const freeze_card_idx = cardTextureIndex(.Freeze);
                const freeze_card_angle = card_angle + std.math.pi / 2.0;
                const freeze_card_cx = px;
                const freeze_card_cy = py;
                try addCard(frame_allocator, &instances, &app_state.cards, freeze_card_idx, freeze_card_cx, freeze_card_cy, freeze_card_angle, card_w, card_h);
            }
        }

        // Animate the freeze card flying from freezing player to frozen player.
        for (app_state.animation.queue.items) |animation| {
            switch (animation) {
                .freeze_player => |data| {
                    // Helper: compute a player's base_angle and derived card_angle.
                    const playerAngles = struct {
                        fn call(players: []f.Player, target: *f.Player) struct { base: f32, card: f32 } {
                            const np = players.len;
                            for (players, 0..) |*pl, idx| {
                                if (pl == target) {
                                    const base: f32 = -std.math.pi / 2.0 +
                                        @as(f32, @floatFromInt(idx)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(np)));
                                    var card = base + std.math.pi / 2.0;
                                    if (radius * @sin(base) < 0.0) card += std.math.pi;
                                    return .{ .base = base, .card = card };
                                }
                            }
                            return .{ .base = 0.0, .card = 0.0 };
                        }
                    }.call;

                    const freezing_angles = playerAngles(&app_state.players, data.freezing_player);
                    const frozen_angles = playerAngles(&app_state.players, data.frozen_player);

                    const src_x = radius * @cos(freezing_angles.base);
                    const src_y = radius * @sin(freezing_angles.base);
                    const dst_x = radius * @cos(frozen_angles.base);
                    const dst_y = radius * @sin(frozen_angles.base);

                    const cx = std.math.lerp(src_x, dst_x, data.t);
                    const cy = std.math.lerp(src_y, dst_y, data.t);

                    // Source angle: normal card orientation of the freezing player.
                    // Destination angle: tapped (freeze) card orientation of the frozen player.
                    const src_angle = freezing_angles.card;
                    const dst_angle = frozen_angles.card + std.math.pi / 2.0;
                    const freeze_anim_angle = std.math.lerp(src_angle, dst_angle, data.t);

                    try addCard(frame_allocator, &instances, &app_state.cards, cardTextureIndex(.Freeze), cx, cy, freeze_anim_angle, card_w, card_h);
                },
                else => {},
            }
            break;
        }

        p.glActiveTexture(p.GL_TEXTURE0);
        p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.card_atlas_texture);
        p.glActiveTexture(p.GL_TEXTURE1);
        p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.font_atlas_texture);

        p.glBindBuffer(p.GL_ARRAY_BUFFER, app_state.gl.instance_vbo);
        p.glBufferData(
            p.GL_ARRAY_BUFFER,
            instances.items.len * @sizeOf(Instance),
            instances.items.ptr,
            p.GL_DYNAMIC_DRAW,
        );
        p.glBindBuffer(p.GL_ARRAY_BUFFER, 0);
        p.glDrawArraysInstanced(p.GL_TRIANGLES, 0, 6, @intCast(instances.items.len));

        p.glBindVertexArray(0);
        p.glBindTexture(p.GL_TEXTURE_2D, 0);
        p.glUseProgram(0);
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

const CardAtlasEntry = struct {
    top_left_u: f32 = 0.0,
    top_left_v: f32 = 0.0,
    bottom_right_u: f32 = 0.0,
    bottom_right_v: f32 = 0.0,
};

const CardTextures = struct {
    buffer_width: usize = 0,
    buffer_height: usize = 0,
    texture_buffer: []u8 = undefined,
    card_atlas: [card_texture_paths.len]CardAtlasEntry = [_]CardAtlasEntry{.{}} ** card_texture_paths.len,
};

fn loadCardTextures(allocator: std.mem.Allocator, texture_paths: []const []const u8, cards_per_row: u32, cards_per_col: u32) !CardTextures {
    var result = CardTextures{};

    var card_width: usize = 0;
    var card_height: usize = 0;
    for (texture_paths, 0..) |path, i| {
        const td = try p.texture(allocator, path);
        defer allocator.free(td.pixels);

        if (card_width == 0 or card_height == 0) {
            card_width = td.width;
            card_height = td.height;
            result.buffer_width = cards_per_row * card_width;
            result.buffer_height = cards_per_col * card_height;
            result.texture_buffer = try allocator.alloc(u8, result.buffer_width * result.buffer_height * 4);
            p.logInfo("Allocated buffer {}x{}", .{ result.buffer_width, result.buffer_height });
        } else if (card_width != td.width or card_height != td.height) {
            p.logErr("expected dimensions {}x{} don't match dimensions of card '{s}': {}x{}", .{ card_width, card_height, path, td.width, td.height });
            return error.InconsistentCardPixelDimensions;
        }

        p.logInfo("\nAdding card '{s}' ({})", .{ path, i });

        const start_row = (@divTrunc(i, cards_per_row)) * card_height;
        const start_col = (i % cards_per_row) * card_width;
        for (0..card_height) |row| {
            for (0..card_width) |col| {
                const final_row = start_row + row;
                const final_col = start_col + col;
                const buffer_index = (final_row * result.buffer_width + final_col) * 4;
                const pixel_index = (row * card_width + col) * 4;
                result.texture_buffer[buffer_index + 0] = td.pixels[pixel_index + 0];
                result.texture_buffer[buffer_index + 1] = td.pixels[pixel_index + 1];
                result.texture_buffer[buffer_index + 2] = td.pixels[pixel_index + 2];
                result.texture_buffer[buffer_index + 3] = td.pixels[pixel_index + 3];
            }
        }

        const buffer_height_f: f32 = @floatFromInt(result.buffer_height);
        const buffer_width_f: f32 = @floatFromInt(result.buffer_width);
        const start_row_f: f32 = @floatFromInt(start_row);
        const start_col_f: f32 = @floatFromInt(start_col);
        const end_row_f: f32 = @floatFromInt(start_row + td.height);
        const end_col_f: f32 = @floatFromInt(start_col + td.width);
        var card = &result.card_atlas[i];
        card.top_left_u = end_col_f / buffer_width_f;
        card.top_left_v = start_row_f / buffer_height_f;
        card.bottom_right_u = start_col_f / buffer_width_f;
        card.bottom_right_v = end_row_f / buffer_height_f;
        p.logInfo("Pixels: {}x{} - {}x{}", .{ start_col_f, start_row_f, end_col_f, end_row_f });
        p.logInfo("UV: {}x{} - {}x{}", .{ card.top_left_u, card.top_left_v, card.bottom_right_u, card.bottom_right_v });
    }

    p.logInfo("imported all cards into a single texture: {}x{}", .{ result.buffer_width, result.buffer_height });

    return result;
}
