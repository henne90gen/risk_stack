const std = @import("std");

pub const p = @import("platform.zig");
const zm = @import("zmath");
const f = @import("risk_stack.zig");
const text = @import("text.zig");
const card_art = @import("cards.zig");

test {
    std.testing.refAllDecls(@This());
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

/// Cards in atlas order, indexed by `cardTextureIndex`.
const atlas_cards = [_]card_art.Card{
    .@"0",
    .@"1",
    .@"2",
    .@"3",
    .@"4",
    .@"5",
    .@"6",
    .@"7",
    .@"8",
    .@"9",
    .@"10",
    .@"11",
    .@"12",
    .second_chance,
    .freeze,
    .flip_three,
    .plus_2,
    .plus_4,
    .plus_6,
    .plus_8,
    .plus_10,
    .x2,
    .back,
};
const back_texture_index: usize = atlas_cards.len - 1;

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

// Table layout in world units, see `render`.
const card_w: f32 = 0.12;
const card_h: f32 = 0.17;
const card_spacing: f32 = card_w * 1.1;
/// Distance of the players' hands from the table center.
const table_radius: f32 = 0.5;
/// Distance from the center for cards placed in front of a player.
const front_distance: f32 = table_radius - card_h * 1.2;
/// Distance from the center of the players' score lines.
const text_radius: f32 = 0.7;
const deck_pos = [2]f32{ -card_w * 0.65, 0.0 };
const discard_pos = [2]f32{ card_w * 0.65, 0.0 };
/// Orientation of the deck and discard pile cards.
const pile_angle: f32 = std.math.pi;

const color_text = zm.f32x4(0.0, 1.0, 1.0, 1.0);
const color_bust = zm.f32x4(1.0, 0.35, 0.35, 1.0);
const color_stay = zm.f32x4(0.45, 1.0, 0.45, 1.0);
const color_flip7 = zm.f32x4(1.0, 0.85, 0.2, 1.0);
const color_frozen = zm.f32x4(0.55, 0.8, 1.0, 1.0);
const color_saved = zm.f32x4(1.0, 0.6, 0.2, 1.0);
const color_info = zm.f32x4(0.9, 0.9, 0.9, 1.0);

/// Short text that lives inside an animation, without an allocation.
const Label = struct {
    buf: [48]u8 = undefined,
    len: usize = 0,

    fn init(comptime fmt: []const u8, args: anytype) Label {
        var label = Label{};
        // Too long texts are cut off.
        label.len = (std.fmt.bufPrint(&label.buf, fmt, args) catch @as([]u8, &label.buf)).len;
        return label;
    }

    fn slice(self: *const Label) []const u8 {
        return self.buf[0..self.len];
    }
};

/// One step of the visualization of a simulation event. The queue plays them
/// one after the other; each updates the shown table when it starts and/or
/// finishes, see `startAnimation` and `finishAnimation`.
const Animation = struct {
    /// Progress from 0 to 1.
    t: f32 = 0.0,
    started: bool = false,
    /// Where the moving card starts, set when the animation starts.
    from: [2]f32 = .{ 0.0, 0.0 },
    from_angle: f32 = pile_angle,
    kind: Kind,

    const Kind = union(enum) {
        /// A card flies from the deck, or from in front of `source`, to
        /// `player`. Number, modifier and SecondChance cards join the hand;
        /// with `to_front` the card lands in front of the player instead,
        /// waiting to be resolved.
        deal_card: struct {
            player: *f.Player,
            card: f.Card,
            source: ?*f.Player = null,
            to_front: bool = false,
        },
        /// The Freeze in front of `freezing_player` flies onto `frozen_player`'s hand.
        freeze_player: struct {
            freezing_player: *f.Player,
            frozen_player: *f.Player,
            score: u32,
        },
        /// The FlipThree in front of `player` flies in front of `target`.
        flip_three_start: struct {
            player: *f.Player,
            target: *f.Player,
        },
        /// The FlipThree in front of `target` goes to the discard pile.
        flip_three_end: struct {
            player: *f.Player,
            target: *f.Player,
        },
        /// Cards from `player`'s hand, or from in front of them, go to the discard pile.
        discard: struct {
            player: *f.Player,
            cards: [2]f.Card,
            len: u8,
            from_hand: bool,
            /// A SecondChance saved the player.
            saved: bool = false,
        },
        /// The player leaves the round: busted, stayed or Flip 7.
        player_result: struct {
            player: *f.Player,
            state: f.PlayerState,
            /// Total score after banking; null keeps the shown score.
            score: ?u32,
            outcome: enum { bust, stay, flip7 },
        },
        /// The discard pile is shuffled into the deck.
        shuffle: struct { cards: usize = 0 },
        /// All hands go to the discard pile for the next round.
        collect_cards,
        /// A message across the table center.
        banner: struct { label: Label, color: zm.Vec },
        won: struct { player: *f.Player, score: u32 },
    };

    /// Progress per frame.
    fn speed(self: *const Animation) f32 {
        return switch (self.kind) {
            .deal_card, .flip_three_end, .discard => 0.05,
            .freeze_player, .flip_three_start, .collect_cards => 0.03,
            .shuffle => 0.025,
            .banner => 0.02,
            .won => 0.012,
            // Shows its outcome as a floating text without holding up the
            // queue, so it finishes within one frame at any frame rate.
            .player_result => std.math.inf(f32),
        };
    }
};

const AnimationState = struct {
    queue: std.ArrayList(Animation),

    pub fn init(allocator: std.mem.Allocator) !AnimationState {
        return AnimationState{
            .queue = try std.ArrayList(Animation).initCapacity(allocator, 10),
        };
    }
};

/// Text that rises above a player and fades out, alongside the queue.
const FloatingText = struct {
    player: *f.Player,
    label: Label,
    color: zm.Vec,
    t: f32 = 0.0,
};

const FlipThreeStackEntry = struct {
    player: *f.Player,
    target: *f.Player,
};

/// A player as currently shown; trails the simulation while animations play.
const ShownPlayer = struct {
    hand: std.ArrayList(f.Card) = .empty,
    /// Drawn Freeze, FlipThree and passed-on SecondChance cards, lying in
    /// front of the player until they are resolved.
    pending: std.ArrayList(f.Card) = .empty,
    state: f.PlayerState = .InGame,
    score: u32 = 0,

    fn deinit(self: *ShownPlayer, allocator: std.mem.Allocator) void {
        self.hand.deinit(allocator);
        self.pending.deinit(allocator);
    }
};

/// The table as currently shown; matches the simulation once the queue is empty.
const ShownTable = struct {
    players: std.ArrayList(ShownPlayer) = .empty,
    deck_count: usize = 0,
    discard_count: usize = 0,
    discard_top: ?f.Card = null,
    /// Set once the PlayerWon animation is done.
    winner: ?struct { index: usize, score: u32 } = null,

    fn deinit(self: *ShownTable, allocator: std.mem.Allocator) void {
        for (self.players.items) |*player| player.deinit(allocator);
        self.players.deinit(allocator);
    }

    fn discard(self: *ShownTable, card: f.Card) void {
        self.discard_count += 1;
        self.discard_top = card;
    }
};

const AppState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    group: std.Io.Group = .init,
    /// Scratch memory for a single frame, reset at the start of every frame.
    frame_arena: std.heap.ArenaAllocator,
    aspect_ratio: f32 = 1.0,
    gl: OpenGLState = .{},
    zoom: ZoomState = .{},
    animation: AnimationState,
    font: text.Font = .{},
    cards: CardTextures = .{},

    cards_loading: bool = true,
    cards_loading_started: std.Io.Timestamp = .zero,
    cards_loaded: u32 = 0,
    cards_total: u32 = 0,

    prng: std.Random.DefaultPrng,
    simulation: f.GameSimulation = undefined,
    flip_three_stack: std.ArrayList(FlipThreeStackEntry),
    shown: ShownTable = .{},
    floating_texts: std.ArrayList(FloatingText) = .empty,
    should_run_next_step: bool = false,
    /// Steps still to run on their own, from `--steps`.
    auto_steps: u32 = 0,
    /// Set by `--steps`: close once the steps and their animations are done.
    close_after_auto_steps: bool = false,
    /// Set by `--scenarios`: plays the listed scenarios one after the other.
    scenario_runner: ?ScenarioRunner = null,
    /// Scenarios from `--scenarios` that failed to load.
    failed_scenarios: u32 = 0,
    /// Where S saves and L loads the simulation state; a file on native, a
    /// localStorage entry in the browser. Set with `--scenario`.
    scenario_path: []const u8 = "scenario.json",
    next_event_to_process_index: usize = 0,
    /// When the previous frame was updated, to advance animations by time.
    last_frame: ?std.Io.Timestamp = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !AppState {
        var buf = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
        io.random(&buf);
        const seed: u64 = @bitCast(buf);
        return AppState{
            .allocator = allocator,
            .io = io,
            .frame_arena = .init(allocator),
            .animation = try AnimationState.init(allocator),
            .prng = .init(seed),
            .flip_three_stack = try std.ArrayList(FlipThreeStackEntry).initCapacity(allocator, 3),
        };
    }

    pub fn deinit(self: *AppState) void {
        self.group.cancel(self.io);
        if (self.scenario_runner) |*runner| runner.deinit(self.allocator);
        self.simulation.deinit();
        self.font.deinit(self.allocator);
        self.flip_three_stack.deinit(self.allocator);
        self.shown.deinit(self.allocator);
        self.floating_texts.deinit(self.allocator);
        self.animation.queue.deinit(self.allocator);
        self.frame_arena.deinit();
    }

    pub fn resetInputTracking(self: *AppState) void {
        self.should_run_next_step = false;
    }
};

var app_state: AppState = undefined;

pub const RiskStackApp = struct {
    pub fn onInit(gpa: std.mem.Allocator, io: std.Io, options: p.Options) void {
        app_state = AppState.init(gpa, io) catch @panic("failed to initialize app state");
        app_state.simulation = f.GameSimulation.init(app_state.allocator, &app_state.prng, &[_]f.DrawStrategy{
            f.DrawStrategy{ .MinPoints = 20 },
            f.DrawStrategy{ .MinPoints = 30 },
            f.DrawStrategy{ .MinPoints = 40 },
        }) catch @panic("failed to initialize game simulation");

        app_state.simulation.settings.logging_enabled = true;
        app_state.simulation.settings.events_enabled = true;

        syncShown() catch @panic("failed to set up the shown table");
        if (options.scenario) |path| {
            app_state.scenario_path = path;
            loadScenario() catch |err| {
                p.logErr("loading scenario '{s}' failed: {}", .{ path, err });
                if (!p.is_wasm) std.process.exit(1);
            };
        }
        app_state.auto_steps = options.steps;
        app_state.close_after_auto_steps = options.steps > 0;

        if (options.scenarios) |manifest_path| {
            app_state.scenario_runner = ScenarioRunner.init(app_state.allocator, app_state.io, manifest_path) catch |err| {
                p.logErr("loading scenario manifest '{s}' failed: {}", .{ manifest_path, err });
                if (!p.is_wasm) std.process.exit(1);
                unreachable;
            };
        }

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

        app_state.cards_loading_started = std.Io.Clock.awake.now(io);
        app_state.cards_total = atlas_cards.len;
        app_state.group.concurrent(app_state.io, asyncRenderCards, .{app_state.allocator}) catch |err| std.debug.panic("asyncRenderCards failed: {}", .{err});

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

    pub fn onDeinit() void {
        app_state.deinit();
    }

    pub fn onResize(w: u32, h: u32, scale: f32) void {
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
            p.Key.S => saveScenario() catch |err| p.logErr("saving scenario failed: {}", .{err}),
            p.Key.L => loadScenario() catch |err| p.logErr("loading scenario failed: {}", .{err}),
            else => p.logInfo("onKeyDown: {}", .{key}),
        }
    }

    pub fn onKeyUp(key: p.Key) void {
        p.logInfo("onKeyUp: {}", .{key});
    }

    pub fn onMouseDown(button: p.MouseButton, x: f32, y: f32) void {
        switch (button) {
            p.MouseButton.Left => {
                app_state.should_run_next_step = true;
            },
            else => {
                p.logInfo("onMouseDown: {} -> {} | {}", .{ button, x, y });
            },
        }
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
        if (app_state.cards_loading) {
            renderLoadingScreen() catch |err| p.logErr("render loading screen failed: {}", .{err});
            return;
        }

        update() catch |err| p.logErr("update failed: {}", .{err});
        render() catch |err| p.logErr("render failed: {}", .{err});
    }

    fn update() !void {
        // Animation speeds are tuned per frame at 60 fps; scale them by the
        // real frame time so they look the same at any frame rate.
        const now = std.Io.Clock.awake.now(app_state.io);
        const frames: f32 = if (app_state.last_frame) |last|
            std.math.clamp(@as(f32, @floatFromInt(last.durationTo(now).nanoseconds)) / (@as(f32, std.time.ns_per_s) / 60.0), 0.0, 6.0)
        else
            1.0;
        app_state.last_frame = now;

        updateFloatingTexts(frames);

        const queue = &app_state.animation.queue;
        if (queue.items.len == 0) try syncShown();
        if (queue.items.len > 0) {
            const animation = &queue.items[0];
            if (!animation.started) {
                animation.started = true;
                try startAnimation(animation);
            }
            animation.t += animation.speed() * frames;
            if (animation.t >= 1.0) {
                try finishAnimation(animation);
                _ = queue.orderedRemove(0);
            }
            return;
        }

        if (app_state.scenario_runner) |*runner| {
            if (app_state.auto_steps == 0) {
                switch (runner.advance(std.Io.Clock.awake.now(app_state.io))) {
                    .wait => {},
                    .play => |scenario| playScenario(scenario),
                    .finished => {
                        if (app_state.failed_scenarios > 0) {
                            p.logErr("{d} of {d} scenarios failed to load", .{ app_state.failed_scenarios, runner.scenarios.len });
                        } else {
                            p.logInfo("played all {d} scenarios, closing", .{runner.scenarios.len});
                        }
                        p.close();
                    },
                }
                return;
            }
        }
        if (app_state.close_after_auto_steps and app_state.auto_steps == 0) {
            p.logInfo("ran the requested --steps, closing", .{});
            app_state.close_after_auto_steps = false;
            p.close();
            return;
        }

        const auto_step = app_state.auto_steps > 0;
        if (auto_step) {
            app_state.auto_steps -= 1;
        } else if (!app_state.should_run_next_step) {
            return;
        }
        app_state.resetInputTracking();

        // Once the winner is shown, the next step starts a new game.
        if (app_state.simulation.result_ != null) {
            try startNewGame();
            return;
        }

        const game_should_continue = try app_state.simulation.step();
        // The last step's events (round over, winner) still need showing.
        try queueEvents();
        if (!game_should_continue) {
            // Nothing left to show; don't wait for steps that can't happen.
            app_state.auto_steps = 0;
            const game_result = app_state.simulation.result();
            p.logInfo("game finished -> strategy {} won", .{game_result.winning_strategy});
        }
    }

    /// Turns the simulation's new events into animations.
    fn queueEvents() !void {
        const all_events = app_state.simulation.events.items;
        const events = all_events[@min(app_state.next_event_to_process_index, all_events.len)..];
        app_state.next_event_to_process_index = all_events.len;

        const queue = &app_state.animation.queue;
        const gpa = app_state.allocator;
        // Set by SecondChancePassed: the following DrawCard comes from this player.
        var pass_source: ?*f.Player = null;
        for (events) |event| {
            switch (event) {
                .DrawCard => |d| p.logInfo("{} DrawCard {} {any} {}", .{ all_events.len, d.card, d.player.hand.items, d.player.strategy }),
                .PlayerEndRound => |d| p.logInfo("{} PlayerEndRound {any} {}", .{ all_events.len, d.player.hand.items, d.player.strategy }),
                else => p.logInfo("{} {}", .{ all_events.len, event }),
            }

            switch (event) {
                .DrawCard => |data| {
                    try queue.append(gpa, .{ .kind = .{ .deal_card = .{
                        .player = data.player,
                        .card = data.card,
                        .source = pass_source,
                        .to_front = data.card == .Freeze or data.card == .FlipThree,
                    } } });
                    pass_source = null;
                },
                .PlayerFrozen => |data| {
                    try queue.append(gpa, .{ .kind = .{ .freeze_player = .{ .freezing_player = data.freezing_player, .frozen_player = data.frozen_player, .score = data.score } } });
                },
                .PlayerEliminated => |data| {
                    try queue.append(gpa, .{ .kind = .{ .player_result = .{ .player = data.player, .state = .Eliminated, .score = null, .outcome = .bust } } });
                },
                .PlayerEndRound => |data| {
                    try queue.append(gpa, .{ .kind = .{ .player_result = .{ .player = data.player, .state = .RoundEnded, .score = data.score, .outcome = .stay } } });
                },
                .Flip7 => |data| {
                    try queue.append(gpa, .{ .kind = .{ .banner = .{ .label = .init("FLIP 7! Player {d}", .{playerIndex(data.player) + 1}), .color = color_flip7 } } });
                    try queue.append(gpa, .{ .kind = .{ .player_result = .{ .player = data.player, .state = .RoundEnded, .score = data.score, .outcome = .flip7 } } });
                },
                .PlayerWon => |data| {
                    try queue.append(gpa, .{ .kind = .{ .won = .{ .player = data.player, .score = data.score } } });
                },
                .DeckShuffle => try queue.append(gpa, .{ .kind = .{ .shuffle = .{} } }),
                .DeckExhausted => {
                    try queue.append(gpa, .{ .kind = .{ .banner = .{ .label = .init("Deck exhausted", .{}), .color = color_info } } });
                },
                .RoundEnded => {
                    try queue.append(gpa, .{ .kind = .{ .banner = .{ .label = .init("Round over", .{}), .color = color_info } } });
                },
                .NewRoundStarted => {
                    try queue.append(gpa, .{ .kind = .collect_cards });
                    try queue.append(gpa, .{ .kind = .{ .banner = .{ .label = .init("New round", .{}), .color = color_info } } });
                },
                .FlipThreeStarted => |data| {
                    try queue.append(gpa, .{ .kind = .{ .flip_three_start = .{ .player = data.player, .target = data.target } } });
                },
                .FlipThreeEnded => |data| {
                    try queue.append(gpa, .{ .kind = .{ .flip_three_end = .{ .player = data.player, .target = data.target } } });
                },
                .SecondChanceUsed => |data| {
                    try queue.append(gpa, .{ .kind = .{ .discard = .{ .player = data.player, .cards = .{ .SecondChance, data.card }, .len = 2, .from_hand = true, .saved = true } } });
                },
                .SecondChancePassed => |data| {
                    // Shown in front of the player who drew it, then handed on
                    // by the DrawCard that follows.
                    try queue.append(gpa, .{ .kind = .{ .deal_card = .{ .player = data.from, .card = .SecondChance, .to_front = true } } });
                    pass_source = data.from;
                },
                .CardDiscarded => |data| {
                    // A SecondChance nobody can take had no DrawCard yet; show it drawn first.
                    if (data.card == .SecondChance) {
                        try queue.append(gpa, .{ .kind = .{ .deal_card = .{ .player = data.player, .card = .SecondChance, .to_front = true } } });
                    }
                    try queue.append(gpa, .{ .kind = .{ .discard = .{ .player = data.player, .cards = .{ data.card, data.card }, .len = 1, .from_hand = false } } });
                },
            }
        }
    }

    fn renderLoadingScreen() !void {
        _ = app_state.frame_arena.reset(.retain_capacity);
        const frame_allocator = app_state.frame_arena.allocator();

        p.glClearColor(0.1, 0.1, 0.1, 1.0);
        p.glClear(p.GL_COLOR_BUFFER_BIT);

        p.glUseProgram(app_state.gl.tri_program);
        p.glBindVertexArray(app_state.gl.tri_vao);

        // Same projection as the game, but unaffected by zoom.
        const identity = zm.identity();
        p.glUniformMatrix4fv(app_state.gl.u_loc_view, 1, p.GL_TRUE, zm.arrNPtr(&identity));
        const ar = app_state.aspect_ratio;
        const ortho = zm.orthographicOffCenterRh(-ar, ar, 1.0, -1.0, -1.0, 1.0);
        p.glUniformMatrix4fv(app_state.gl.u_loc_projection, 1, p.GL_TRUE, zm.arrNPtr(&ortho));

        var instances: std.ArrayList(Instance) = try .initCapacity(frame_allocator, 64);

        const done: f32 = @floatFromInt(app_state.cards_loaded);
        const total: f32 = @floatFromInt(app_state.cards_total);
        const seconds: f32 = @floatCast(@as(f64, @floatFromInt(app_state.cards_loading_started.untilNow(app_state.io, .awake).toNanoseconds())) / std.time.ns_per_s);

        // Spinner: a ring of dots, the brightest one leading, one turn per second.
        const dot_count = 10;
        for (0..dot_count) |i| {
            const fi: f32 = @floatFromInt(i);
            const angle = -seconds * 2.0 * std.math.pi + fi * 2.0 * std.math.pi / dot_count;
            const alpha = 1.0 - fi / dot_count;
            try addQuad(frame_allocator, &instances, 0.12 * @cos(angle), 0.2 + 0.12 * @sin(angle), 0.035, 0.035, angle, zm.f32x4(0.0, 1.0, 1.0, alpha));
        }

        const label = try std.fmt.allocPrint(frame_allocator, "Generating cards {d}/{d}", .{ app_state.cards_loaded, app_state.cards_total });
        const font_scale = 0.06;
        try addText(frame_allocator, &instances, label, .{
            .y = -0.1,
            .offset_anchor_x = -0.5 * app_state.font.textDimensions(label, font_scale)[0],
            .scale = font_scale,
        });

        // Progress bar.
        const bar_w: f32 = 0.8;
        const bar_h: f32 = 0.025;
        const fill_w = bar_w * done / total;
        try addQuad(frame_allocator, &instances, 0.0, -0.22, bar_w, bar_h, 0.0, zm.f32x4(1.0, 1.0, 1.0, 0.15));
        try addQuad(frame_allocator, &instances, (fill_w - bar_w) / 2.0, -0.22, fill_w, bar_h, 0.0, zm.f32x4(0.0, 1.0, 1.0, 1.0));

        p.glActiveTexture(p.GL_TEXTURE1);
        p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.font_atlas_texture);
        drawInstances(instances.items);
    }

    fn render() !void {
        _ = app_state.frame_arena.reset(.retain_capacity);
        const frame_allocator = app_state.frame_arena.allocator();

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

        var instances: std.ArrayList(Instance) = try .initCapacity(frame_allocator, 20);
        defer instances.deinit(frame_allocator);

        if (app_state.scenario_runner) |*runner| if (runner.label()) |position| {
            const label = try std.fmt.allocPrint(frame_allocator, "{d}/{d} {s}", .{ position.number, position.total, position.name });
            try addText(frame_allocator, &instances, label, .{ .x = -half_w + 0.03 / app_state.zoom.current, .y = half_h - 0.07 / app_state.zoom.current, .scale = 0.05 / app_state.zoom.current });
        };

        const shown = &app_state.shown;
        const players = app_state.simulation.players;
        const queue = app_state.animation.queue.items;
        // The animation playing right now.
        const current: ?*const Animation = if (queue.len > 0 and queue[0].started) &queue[0] else null;

        // Deck and discard pile in the center, with their card counts above.
        if (shown.deck_count > 0) {
            try addCard(frame_allocator, &instances, back_texture_index, deck_pos, pile_angle);
        } else {
            try addQuad(frame_allocator, &instances, deck_pos[0], deck_pos[1], card_w, card_h, 0.0, zm.f32x4(1.0, 1.0, 1.0, 0.06));
        }
        if (shown.discard_top) |top| {
            try addCard(frame_allocator, &instances, cardTextureIndex(top), discard_pos, pile_angle);
        } else {
            try addQuad(frame_allocator, &instances, discard_pos[0], discard_pos[1], card_w, card_h, 0.0, zm.f32x4(1.0, 1.0, 1.0, 0.06));
        }
        const count_scale = 0.035;
        for ([_]struct { pos: [2]f32, count: usize }{
            .{ .pos = deck_pos, .count = shown.deck_count },
            .{ .pos = discard_pos, .count = shown.discard_count },
        }) |pile| {
            const label = try std.fmt.allocPrint(frame_allocator, "{d}", .{pile.count});
            try addText(frame_allocator, &instances, label, .{
                .x = pile.pos[0],
                .y = pile.pos[1] + card_h / 2.0 + 0.015,
                .offset_anchor_x = -0.5 * app_state.font.textDimensions(label, count_scale)[0],
                .scale = count_scale,
                .color = color_info,
            });
        }

        // During `collect_cards` everything on the table moves to the discard pile.
        const collect_t: f32 = if (current) |anim| (if (anim.kind == .collect_cards) smoothstep(anim.t) else 0.0) else 0.0;

        // Players arranged in a circle.
        for (players, shown.players.items, 0..) |*player, *sp, pi| {
            const seat = seatOf(players, player);
            const hand_center = seat.handCenter();
            const card_angle = seat.card_angle;
            const perp = seat.perp();

            const score_text = try std.fmt.allocPrint(frame_allocator, "P{d}: {d} ({d})", .{ pi + 1, f.scoreHand(sp.hand.items), sp.score });
            const font_scale = 0.05;
            const text_dimensions = app_state.font.textDimensions(score_text, font_scale);
            var text_angle = seat.base_angle + std.math.pi / 2.0;
            if (@sin(seat.base_angle) > 0.0) {
                text_angle += std.math.pi;
            }
            try addText(frame_allocator, &instances, score_text, .{
                .x = text_radius * @cos(seat.base_angle),
                .y = text_radius * @sin(seat.base_angle),
                .offset_anchor_x = -0.5 * text_dimensions[0],
                .angle = text_angle,
                .scale = font_scale,
                .color = switch (sp.state) {
                    .InGame => color_text,
                    .Frozen => color_frozen,
                    .Eliminated => color_bust,
                    .RoundEnded => color_stay,
                },
            });

            const shown_hand = sp.hand.items;

            // The card being dealt into this player's hand right now, if any.
            // It flies into the slot after the shown cards.
            const incoming: ?f.Card = if (current) |anim| switch (anim.kind) {
                .deal_card => |d| if (d.player == player and !d.to_front) d.card else null,
                else => null,
            } else null;
            const n = shown_hand.len + @intFromBool(incoming != null);

            const tapped_spacing: f32 = card_h * 1.1;
            const effective_spacing: f32 = if (sp.state == .Eliminated) tapped_spacing else card_spacing;
            const total_width: f32 = @as(f32, @floatFromInt(n -| 1)) * effective_spacing;
            for (0..n) |ci| {
                const card = if (ci < shown_hand.len) shown_hand[ci] else incoming.?;

                var angle = card_angle;
                const offset: f32 = -total_width / 2.0 + @as(f32, @floatFromInt(ci)) * effective_spacing;
                var pos = [2]f32{ hand_center[0] + perp[0] * offset, hand_center[1] + perp[1] * offset };

                if (sp.state == .RoundEnded and ci == 0) {
                    angle += std.math.pi / 2.0;
                    pos[0] -= perp[0] * (card_w / 2.0);
                    pos[1] -= perp[1] * (card_w / 2.0);
                }
                if (sp.state == .Eliminated) {
                    angle += std.math.pi / 2.0;
                }

                if (ci == shown_hand.len) {
                    const anim = current.?;
                    const amount = smoothstep(anim.t);
                    pos = lerp2(anim.from, pos, amount);
                    angle = lerpAngle(anim.from_angle, angle, amount);
                }

                try addCard(frame_allocator, &instances, cardTextureIndex(card), lerp2(pos, discard_pos, collect_t), lerpAngle(angle, pile_angle, collect_t));
            }

            // A frozen player's hand is covered by the Freeze card.
            if (sp.state == .Frozen) {
                try addCard(frame_allocator, &instances, cardTextureIndex(.Freeze), lerp2(hand_center, discard_pos, collect_t), lerpAngle(card_angle + std.math.pi / 2.0, pile_angle, collect_t));
            }

            // Drawn action cards waiting in front of the player.
            for (sp.pending.items, 0..) |card, i| {
                try addCard(frame_allocator, &instances, cardTextureIndex(card), seat.pendingSlot(i), card_angle);
            }

            // FlipThree cards targeting this player stay in front of them until FlipThreeEnded.
            var stacked: usize = 0;
            for (app_state.flip_three_stack.items) |entry| {
                if (entry.target != player) continue;
                try addCard(frame_allocator, &instances, cardTextureIndex(.FlipThree), seat.flipThreeSlot(stacked), card_angle);
                stacked += 1;
            }
        }

        // The card(s) moved by the current animation, outside of a hand.
        if (current) |anim| {
            const amount = smoothstep(anim.t);
            switch (anim.kind) {
                .deal_card => |d| if (d.to_front) {
                    const seat = seatOf(players, d.player);
                    const dst = seat.pendingSlot(shownPlayer(d.player).pending.items.len);
                    try addCard(frame_allocator, &instances, cardTextureIndex(d.card), lerp2(anim.from, dst, amount), lerpAngle(anim.from_angle, seat.card_angle, amount));
                },
                .freeze_player => |d| {
                    // Lands tapped on the frozen player's hand.
                    const seat = seatOf(players, d.frozen_player);
                    try addCard(frame_allocator, &instances, cardTextureIndex(.Freeze), lerp2(anim.from, seat.handCenter(), amount), lerpAngle(anim.from_angle, seat.card_angle + std.math.pi / 2.0, amount));
                },
                .flip_three_start => |d| {
                    const seat = seatOf(players, d.target);
                    var stacked: usize = 0;
                    for (app_state.flip_three_stack.items) |entry| stacked += @intFromBool(entry.target == d.target);
                    try addCard(frame_allocator, &instances, cardTextureIndex(.FlipThree), lerp2(anim.from, seat.flipThreeSlot(stacked), amount), lerpAngle(anim.from_angle, seat.card_angle, amount));
                },
                .flip_three_end => {
                    try addCard(frame_allocator, &instances, cardTextureIndex(.FlipThree), lerp2(anim.from, discard_pos, amount), lerpAngle(anim.from_angle, pile_angle, amount));
                },
                .discard => |d| for (d.cards[0..d.len], 0..) |card, i| {
                    const fi: f32 = @floatFromInt(i);
                    const from = [2]f32{ anim.from[0] + fi * card_w * 0.4, anim.from[1] };
                    try addCard(frame_allocator, &instances, cardTextureIndex(card), lerp2(from, discard_pos, amount), lerpAngle(anim.from_angle, pile_angle, amount));
                },
                .shuffle => |d| {
                    // A few face-down cards hop from the discard pile onto the deck.
                    const shown_cards = @min(d.cards, 6);
                    for (0..shown_cards) |i| {
                        const fi: f32 = @floatFromInt(i);
                        const local_t = smoothstep(std.math.clamp(anim.t * 1.6 - fi * 0.12, 0.0, 1.0));
                        var pos = lerp2(discard_pos, deck_pos, local_t);
                        const hop = @sin(std.math.pi * local_t);
                        pos[1] += hop * card_h * 0.6;
                        const wiggle: f32 = if (i % 2 == 0) 0.5 else -0.5;
                        try addCard(frame_allocator, &instances, back_texture_index, pos, pile_angle + hop * wiggle);
                    }
                },
                .banner => |d| try addBanner(frame_allocator, &instances, d.label.slice(), d.color, fadeInOut(anim.t), 0.0, 0.09),
                .won => |d| {
                    const label = Label.init("Player {d} wins!", .{playerIndex(d.player) + 1});
                    try addBanner(frame_allocator, &instances, label.slice(), color_flip7, @min(1.0, anim.t * 4.0), 0.0, 0.09 * (0.6 + 0.4 * smoothstep(@min(1.0, anim.t * 2.0))));
                },
                .player_result, .collect_cards => {},
            }
        }

        // Outcomes rising above the players.
        for (app_state.floating_texts.items) |floating| {
            const center = seatOf(players, floating.player).handCenter();
            const scale = 0.06;
            const label = floating.label.slice();
            var color = floating.color;
            color[3] = 1.0 - floating.t * floating.t;
            try addText(frame_allocator, &instances, label, .{
                .x = center[0],
                .y = center[1] + card_h * 0.6 + 0.1 * floating.t,
                .offset_anchor_x = -0.5 * app_state.font.textDimensions(label, scale)[0],
                .scale = scale,
                .color = color,
            });
        }

        if (shown.winner) |winner| {
            const title = Label.init("Player {d} wins with {d} points!", .{ winner.index + 1, winner.score });
            try addBanner(frame_allocator, &instances, title.slice(), color_flip7, 1.0, 0.0, 0.07);
            const strategy = strategyLabel(players[winner.index].strategy);
            try addBanner(frame_allocator, &instances, strategy.slice(), color_info, 1.0, -0.1, 0.045);
        }

        p.glActiveTexture(p.GL_TEXTURE0);
        p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.card_atlas_texture);
        p.glActiveTexture(p.GL_TEXTURE1);
        p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.font_atlas_texture);

        drawInstances(instances.items);
    }

    fn saveScenario() !void {
        const s = try app_state.simulation.save(app_state.allocator);
        defer app_state.allocator.free(s);
        try p.writeStorage(app_state.io, app_state.scenario_path, s);
        p.logInfo("saved scenario to {s}", .{app_state.scenario_path});
    }

    fn playScenario(scenario: ScenarioRunner.Scenario) void {
        p.logInfo("scenario: {s}", .{scenario.name});
        app_state.scenario_path = scenario.path;
        loadScenario() catch |err| {
            p.logErr("scenario '{s}': loading '{s}' failed: {}", .{ scenario.name, scenario.path, err });
            app_state.failed_scenarios += 1;
            app_state.auto_steps = 0;
            return;
        };
        app_state.auto_steps = scenario.steps;
    }

    fn loadScenario() !void {
        const s = try p.readStorage(app_state.io, app_state.allocator, app_state.scenario_path);
        defer app_state.allocator.free(s);
        try app_state.simulation.load(s);
        try resetShown();
        p.logInfo("loaded scenario from {s}", .{app_state.scenario_path});
    }

    /// Replaces the finished game with a new one: same players and
    /// strategies, scores at zero, a fresh shuffled deck.
    fn startNewGame() !void {
        const old = &app_state.simulation;
        const strategies = try app_state.allocator.alloc(f.DrawStrategy, old.players.len);
        defer app_state.allocator.free(strategies);
        for (strategies, old.players) |*strategy, player| strategy.* = player.strategy;

        // Build the new game before dropping the old one, so a failure keeps it.
        var new_game = try f.GameSimulation.init(app_state.allocator, &app_state.prng, strategies);
        new_game.settings = old.settings;
        old.deinit();
        app_state.simulation = new_game;
        try resetShown();
        p.logInfo("started a new game", .{});
    }

    /// Shows the simulation as it is after it was replaced or reloaded.
    fn resetShown() !void {
        // Pending animations point at the replaced players.
        app_state.animation.queue.clearRetainingCapacity();
        app_state.flip_three_stack.clearRetainingCapacity();
        app_state.floating_texts.clearRetainingCapacity();
        app_state.shown.winner = null;
        try syncShown();
        app_state.next_event_to_process_index = 0;
        app_state.should_run_next_step = false;
    }
};

/// Steps through the scenarios of a manifest. It only decides what comes
/// next; the app loads and runs each scenario it hands out. The manifest is
/// JSON:
///
///     {"scenarios": [{"name": "...", "file": "freeze.json", "steps": 2}]}
///
/// `file` is relative to the manifest.
const ScenarioRunner = struct {
    const Manifest = struct {
        scenarios: []const struct {
            name: []const u8,
            file: []const u8,
            steps: u32,
        },
    };

    pub const Scenario = struct {
        name: []const u8,
        path: []const u8,
        steps: u32,

        fn deinit(self: *Scenario, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.path);
        }
    };

    pub const ScenarioLabel = struct {
        name: []const u8,
        number: usize,
        total: usize,
    };

    pub const Action = union(enum) {
        /// Keep showing the current result.
        wait,
        /// Load and run this scenario.
        play: Scenario,
        /// All scenarios have been played.
        finished,
    };

    const wait_time = std.Io.Duration.fromMilliseconds(1500);

    scenarios: []Scenario,
    index: ?usize = null,
    done_at: ?std.Io.Timestamp = null,

    fn init(allocator: std.mem.Allocator, io: std.Io, manifest_path: []const u8) !ScenarioRunner {
        const json = try p.readStorage(io, allocator, manifest_path);
        defer allocator.free(json);
        const manifest = try std.json.parseFromSlice(Manifest, allocator, json, .{});
        defer manifest.deinit();
        if (manifest.value.scenarios.len == 0) return error.EmptyManifest;

        const dir = std.fs.path.dirname(manifest_path) orelse ".";
        const scenarios = try allocator.alloc(Scenario, manifest.value.scenarios.len);
        var initialized: usize = 0;
        errdefer {
            for (scenarios[0..initialized]) |*scenario| scenario.deinit(allocator);
            allocator.free(scenarios);
        }
        for (scenarios, manifest.value.scenarios) |*scenario, entry| {
            const name = try allocator.dupe(u8, entry.name);
            errdefer allocator.free(name);
            scenario.* = .{
                .name = name,
                .path = try std.fs.path.join(allocator, &.{ dir, entry.file }),
                .steps = entry.steps,
            };
            initialized += 1;
        }
        return .{ .scenarios = scenarios };
    }

    fn deinit(self: *ScenarioRunner, allocator: std.mem.Allocator) void {
        for (self.scenarios) |*scenario| scenario.deinit(allocator);
        allocator.free(self.scenarios);
    }

    fn advance(self: *ScenarioRunner, now: std.Io.Timestamp) Action {
        const index = self.index orelse {
            self.index = 0;
            return .{ .play = self.scenarios[0] };
        };
        const done_at = self.done_at orelse {
            self.done_at = now;
            return .wait;
        };
        if (done_at.durationTo(now).nanoseconds < wait_time.nanoseconds) return .wait;
        self.done_at = null;

        if (index + 1 == self.scenarios.len) return .finished;
        self.index = index + 1;
        return .{ .play = self.scenarios[index + 1] };
    }

    fn label(self: *const ScenarioRunner) ?ScenarioLabel {
        const index = self.index orelse return null;
        return .{ .number = index + 1, .total = self.scenarios.len, .name = self.scenarios[index].name };
    }
};

test "ScenarioRunner.advance holds each scenario, then plays the next" {
    const t = std.testing;

    var scenarios = [_]ScenarioRunner.Scenario{
        .{ .name = "a", .path = "a.json", .steps = 1 },
        .{ .name = "b", .path = "b.json", .steps = 2 },
    };
    var runner = ScenarioRunner{ .scenarios = &scenarios };
    const at = std.Io.Timestamp.fromNanoseconds;
    const ms = std.time.ns_per_ms;

    try t.expectEqual(null, runner.label());
    // The first scenario starts right away, without a hold.
    try t.expectEqualStrings("a.json", runner.advance(at(0)).play.path);
    try t.expectEqual(@as(usize, 1), runner.label().?.number);

    try t.expect(runner.advance(at(0)) == .wait);
    try t.expect(runner.advance(at(1000 * ms)) == .wait);
    const next = runner.advance(at(1500 * ms));
    try t.expectEqualStrings("b.json", next.play.path);
    try t.expectEqual(@as(u32, 2), next.play.steps);
    try t.expectEqual(@as(usize, 2), runner.label().?.number);

    try t.expect(runner.advance(at(2000 * ms)) == .wait);
    try t.expect(runner.advance(at(3500 * ms)) == .finished);
}

/// Index of `player` in `simulation.players`.
fn playerIndex(player: *const f.Player) usize {
    for (app_state.simulation.players, 0..) |*pl, i| {
        if (pl == player) return i;
    }
    unreachable;
}

fn shownPlayer(player: *const f.Player) *ShownPlayer {
    return &app_state.shown.players.items[playerIndex(player)];
}

/// Makes the shown table match the simulation.
fn syncShown() !void {
    const players = app_state.simulation.players;
    const shown = &app_state.shown;
    while (shown.players.items.len > players.len) {
        var sp = shown.players.pop().?;
        sp.deinit(app_state.allocator);
    }
    while (shown.players.items.len < players.len) try shown.players.append(app_state.allocator, .{});
    for (shown.players.items, players) |*sp, player| {
        sp.hand.clearRetainingCapacity();
        try sp.hand.appendSlice(app_state.allocator, player.hand.items);
        sp.pending.clearRetainingCapacity();
        sp.state = player.state;
        sp.score = player.score;
    }
    const deck = &app_state.simulation.deck;
    shown.deck_count = deck.cards.items.len;
    shown.discard_count = deck.discarded.items.len;
    shown.discard_top = if (deck.discarded.items.len > 0) deck.discarded.items[deck.discarded.items.len - 1] else null;
    app_state.flip_three_stack.clearRetainingCapacity();
}

/// Removes the last `card` from `cards` and returns its index.
fn removeLast(cards: *std.ArrayList(f.Card), card: f.Card) ?usize {
    const index = std.mem.lastIndexOfScalar(f.Card, cards.items, card) orelse return null;
    _ = cards.orderedRemove(index);
    return index;
}

/// Takes `card` from in front of `player`; `animation` starts where it lay.
fn takePending(animation: *Animation, player: *const f.Player, card: f.Card) void {
    const seat = seatOf(app_state.simulation.players, player);
    const index = removeLast(&shownPlayer(player).pending, card) orelse 0;
    animation.from = seat.pendingSlot(index);
    animation.from_angle = seat.card_angle;
}

/// Applies what an animation changes on the table when it begins.
fn startAnimation(animation: *Animation) !void {
    const players = app_state.simulation.players;
    const shown = &app_state.shown;
    switch (animation.kind) {
        .deal_card => |d| {
            if (d.source) |source| {
                takePending(animation, source, d.card);
            } else {
                animation.from = deck_pos;
                animation.from_angle = pile_angle;
                shown.deck_count -|= 1;
            }
        },
        .freeze_player => |d| takePending(animation, d.freezing_player, .Freeze),
        .flip_three_start => |d| takePending(animation, d.player, .FlipThree),
        .flip_three_end => |d| {
            // The FlipThree on top of the target's stack leaves.
            var stacked: usize = 0;
            for (app_state.flip_three_stack.items) |entry| stacked += @intFromBool(entry.target == d.target);
            const seat = seatOf(players, d.target);
            animation.from = seat.flipThreeSlot(stacked -| 1);
            animation.from_angle = seat.card_angle;
            _ = app_state.flip_three_stack.pop();
        },
        .discard => |d| {
            const seat = seatOf(players, d.player);
            const sp = shownPlayer(d.player);
            animation.from = seat.handCenter();
            animation.from_angle = seat.card_angle;
            for (d.cards[0..d.len]) |card| {
                if (d.from_hand) {
                    _ = removeLast(&sp.hand, card);
                } else if (removeLast(&sp.pending, card)) |index| {
                    animation.from = seat.pendingSlot(index);
                }
            }
            if (d.saved) try spawnFloatingText(d.player, .init("Saved!", .{}), color_saved);
        },
        .player_result => |d| {
            const sp = shownPlayer(d.player);
            const gain = if (d.score) |score| score -| sp.score else 0;
            sp.state = d.state;
            if (d.score) |score| sp.score = score;
            switch (d.outcome) {
                .bust => try spawnFloatingText(d.player, .init("Bust!", .{}), color_bust),
                .stay => try spawnFloatingText(d.player, .init("Stay +{d}", .{gain}), color_stay),
                .flip7 => try spawnFloatingText(d.player, .init("Flip 7! +{d}", .{gain}), color_flip7),
            }
        },
        .shuffle => |*d| {
            d.cards = shown.discard_count;
            shown.discard_count = 0;
            shown.discard_top = null;
        },
        .collect_cards, .banner, .won => {},
    }
}

/// Applies what an animation changes on the table when it ends.
fn finishAnimation(animation: *const Animation) !void {
    const gpa = app_state.allocator;
    const shown = &app_state.shown;
    switch (animation.kind) {
        .deal_card => |d| {
            const sp = shownPlayer(d.player);
            try (if (d.to_front) &sp.pending else &sp.hand).append(gpa, d.card);
        },
        .freeze_player => |d| {
            const sp = shownPlayer(d.frozen_player);
            const gain = d.score -| sp.score;
            sp.state = .Frozen;
            sp.score = d.score;
            shown.discard(.Freeze);
            try spawnFloatingText(d.frozen_player, .init("Frozen +{d}", .{gain}), color_frozen);
        },
        .flip_three_start => |d| try app_state.flip_three_stack.append(gpa, .{ .player = d.player, .target = d.target }),
        .flip_three_end => shown.discard(.FlipThree),
        .discard => |d| for (d.cards[0..d.len]) |card| shown.discard(card),
        .shuffle => |d| shown.deck_count += d.cards,
        .collect_cards => for (shown.players.items) |*sp| {
            for (sp.hand.items) |card| shown.discard(card);
            sp.hand.clearRetainingCapacity();
            sp.pending.clearRetainingCapacity();
            sp.state = .InGame;
        },
        .won => |d| shown.winner = .{ .index = playerIndex(d.player), .score = d.score },
        .player_result, .banner => {},
    }
}

fn spawnFloatingText(player: *f.Player, label: Label, color: zm.Vec) !void {
    try app_state.floating_texts.append(app_state.allocator, .{ .player = player, .label = label, .color = color });
}

fn updateFloatingTexts(frames: f32) void {
    const texts = &app_state.floating_texts;
    var i: usize = 0;
    while (i < texts.items.len) {
        texts.items[i].t += 0.012 * frames;
        if (texts.items[i].t >= 1.0) {
            _ = texts.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

fn strategyLabel(strategy: f.DrawStrategy) Label {
    return switch (strategy) {
        .MinPoints => |v| .init("Strategy: min {d} points", .{v}),
        .MaxCards => |v| .init("Strategy: max {d} cards", .{v}),
        .MinPointsMaxCards => |v| .init("Strategy: min {d} points, max {d} cards", .{ v.min_points, v.max_cards }),
        .Always7 => .init("Strategy: always 7", .{}),
        .Random => .init("Strategy: random", .{}),
        .RandomMinCards => |v| .init("Strategy: random, min {d} cards", .{v}),
        .ChanceOfFailureBelow => |v| .init("Strategy: risk below {d:.2}", .{v}),
    };
}

/// Where a player sits at the table, matching the layout in `render`.
const Seat = struct {
    /// Angle of the player around the table center.
    base_angle: f32,
    /// Orientation of the player's cards, facing the center.
    card_angle: f32,

    fn handCenter(self: Seat) [2]f32 {
        return frontOf(self, table_radius);
    }

    /// Direction along which the hand is spread.
    fn perp(self: Seat) [2]f32 {
        return .{ -@sin(self.base_angle), @cos(self.base_angle) };
    }

    /// Where the `index`th FlipThree aimed at this player lies.
    fn flipThreeSlot(self: Seat, index: usize) [2]f32 {
        const front = frontOf(self, front_distance);
        const shift = @as(f32, @floatFromInt(index)) * card_w * 0.3;
        const dir = self.perp();
        return .{ front[0] + dir[0] * shift, front[1] + dir[1] * shift };
    }

    /// Where the `index`th unresolved card in front of the player lies,
    /// beside their FlipThree stack.
    fn pendingSlot(self: Seat, index: usize) [2]f32 {
        const front = frontOf(self, front_distance);
        const shift = -@as(f32, @floatFromInt(index + 1)) * card_w * 1.15;
        const dir = self.perp();
        return .{ front[0] + dir[0] * shift, front[1] + dir[1] * shift };
    }
};

fn seatOf(players: []const f.Player, player: *const f.Player) Seat {
    const index = for (players, 0..) |*pl, i| {
        if (pl == player) break i;
    } else unreachable;
    const base_angle: f32 = -std.math.pi / 2.0 +
        @as(f32, @floatFromInt(index)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(players.len)));
    var card_angle = base_angle + std.math.pi / 2.0;
    if (@sin(base_angle) < 0.0) card_angle += std.math.pi;
    return .{ .base_angle = base_angle, .card_angle = card_angle };
}

/// Position at `distance` from the table center towards `seat`.
fn frontOf(seat: Seat, distance: f32) [2]f32 {
    return .{ distance * @cos(seat.base_angle), distance * @sin(seat.base_angle) };
}

/// Interpolates between two angles along the shorter way around.
fn lerpAngle(a: f32, b: f32, t: f32) f32 {
    const diff = @mod(b - a + std.math.pi, 2.0 * std.math.pi) - std.math.pi;
    return a + diff * t;
}

fn lerp2(a: [2]f32, b: [2]f32, t: f32) [2]f32 {
    return .{ std.math.lerp(a[0], b[0], t), std.math.lerp(a[1], b[1], t) };
}

/// Eases `t` in [0, 1] in and out.
fn smoothstep(t: f32) f32 {
    return t * t * (3.0 - 2.0 * t);
}

/// Opacity that fades in at the start of `t` in [0, 1] and out at the end.
fn fadeInOut(t: f32) f32 {
    return std.math.clamp(@min(t, 1.0 - t) * 6.0, 0.0, 1.0);
}

test "lerpAngle takes the shorter way around" {
    const t = std.testing;
    try t.expectApproxEqAbs(@as(f32, 0.0), lerpAngle(0.0, 2.0 * std.math.pi, 0.5), 1e-5);
    try t.expectApproxEqAbs(@as(f32, -0.25), lerpAngle(0.0, -0.5, 0.5), 1e-5);
    // From just above 0 to just below 2π: backwards through 0, not forwards around.
    try t.expectApproxEqAbs(@as(f32, 0.0), lerpAngle(0.1, 2.0 * std.math.pi - 0.1, 0.5), 1e-5);
}

const TextParameters = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    offset_anchor_x: f32 = 0.0,
    offset_anchor_y: f32 = 0.0,
    angle: f32 = 0.0,
    scale: f32 = 1.0,
    /// Alpha fades the text.
    color: zm.Vec = color_text,
};

fn addText(
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
            .color = text_params.color,
            .render_type = 1,
        });
    }
}

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
    card_atlas: [atlas_cards.len]CardAtlasEntry = [_]CardAtlasEntry{.{}} ** atlas_cards.len,
};

fn cardTexturesFromAtlas(atlas: *const card_art.Atlas) CardTextures {
    var result = CardTextures{
        .buffer_width = atlas.width,
        .buffer_height = atlas.height,
    };

    const buffer_width_f: f32 = @floatFromInt(atlas.width);
    const buffer_height_f: f32 = @floatFromInt(atlas.height);
    for (0..atlas_cards.len) |i| {
        const origin = atlas.cardOrigin(i);
        const start_col_f: f32 = @floatFromInt(origin[0]);
        const start_row_f: f32 = @floatFromInt(origin[1]);
        const end_col_f: f32 = @floatFromInt(origin[0] + atlas.card_width);
        const end_row_f: f32 = @floatFromInt(origin[1] + atlas.card_height);
        var card = &result.card_atlas[i];
        card.top_left_u = end_col_f / buffer_width_f;
        card.top_left_v = start_row_f / buffer_height_f;
        card.bottom_right_u = start_col_f / buffer_width_f;
        card.bottom_right_v = end_row_f / buffer_height_f;
    }
    return result;
}

fn uploadCardTextures(atlas: *const card_art.Atlas) void {
    p.glGenTextures(1, @as([*]u32, @ptrCast(&app_state.gl.card_atlas_texture)));
    p.glActiveTexture(p.GL_TEXTURE0);
    p.glBindTexture(p.GL_TEXTURE_2D, app_state.gl.card_atlas_texture);
    p.glTexImage2D(
        p.GL_TEXTURE_2D,
        0,
        @intCast(p.GL_RGBA8),
        @intCast(atlas.width),
        @intCast(atlas.height),
        0,
        p.GL_RGBA,
        p.GL_UNSIGNED_BYTE,
        atlas.bytes().ptr,
        atlas.bytes().len,
    );
    p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_MIN_FILTER, @intCast(p.GL_LINEAR_MIPMAP_LINEAR));
    p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_MAG_FILTER, @intCast(p.GL_LINEAR));
    p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_WRAP_S, @intCast(p.GL_CLAMP_TO_EDGE));
    p.glTexParameteri(p.GL_TEXTURE_2D, p.GL_TEXTURE_WRAP_T, @intCast(p.GL_CLAMP_TO_EDGE));
    p.glGenerateMipmap(p.GL_TEXTURE_2D);
    p.glBindTexture(p.GL_TEXTURE_2D, 0);
}

/// Uploads `instances` and draws them. Expects the program, VAO and textures
/// to be bound.
fn drawInstances(instances: []const Instance) void {
    p.glBindBuffer(p.GL_ARRAY_BUFFER, app_state.gl.instance_vbo);
    p.glBufferData(p.GL_ARRAY_BUFFER, instances.len * @sizeOf(Instance), instances.ptr, p.GL_DYNAMIC_DRAW);
    p.glBindBuffer(p.GL_ARRAY_BUFFER, 0);
    p.glDrawArraysInstanced(p.GL_TRIANGLES, 0, 6, @intCast(instances.len));

    p.glBindVertexArray(0);
    p.glBindTexture(p.GL_TEXTURE_2D, 0);
    p.glUseProgram(0);
}

/// Solid-colored rectangle centered at (`cx`, `cy`).
fn addQuad(alloc: std.mem.Allocator, inst: *std.ArrayList(Instance), cx: f32, cy: f32, w: f32, h: f32, angle: f32, color: zm.Vec) !void {
    const cos_a = @cos(angle);
    const sin_a = @sin(angle);
    const m = zm.Mat{
        zm.f32x4(cos_a * w, sin_a * w, 0, 0),
        zm.f32x4(-sin_a * h, cos_a * h, 0, 0),
        zm.f32x4(0, 0, 1, 0),
        zm.f32x4(cx, cy, 0, 1),
    };
    try inst.append(alloc, .{
        .model = zm.transpose(m),
        .uv_rect = zm.f32x4(0, 0, 0, 0),
        .color = color,
        .render_type = 2,
    });
}

/// Card `card_idx` from the atlas, centered at `pos`.
fn addCard(alloc: std.mem.Allocator, inst: *std.ArrayList(Instance), card_idx: usize, pos: [2]f32, angle: f32) !void {
    const cos_a = @cos(angle);
    const sin_a = @sin(angle);
    const m = zm.Mat{
        zm.f32x4(cos_a * card_w, sin_a * card_w, 0, 0),
        zm.f32x4(-sin_a * card_h, cos_a * card_h, 0, 0),
        zm.f32x4(0, 0, 1, 0),
        zm.f32x4(pos[0], pos[1], 0, 1),
    };
    const entry = &app_state.cards.card_atlas[card_idx];
    try inst.append(alloc, .{
        .model = zm.transpose(m),
        .uv_rect = zm.f32x4(entry.top_left_u, entry.top_left_v, entry.bottom_right_u, entry.bottom_right_v),
        .color = zm.f32x4(0, 0, 0, 0),
        .render_type = 0,
    });
}

/// Text centered horizontally at height `y` on a dark backdrop.
fn addBanner(alloc: std.mem.Allocator, inst: *std.ArrayList(Instance), txt: []const u8, color: zm.Vec, alpha: f32, y: f32, scale: f32) !void {
    const width = app_state.font.textDimensions(txt, scale)[0];
    try addQuad(alloc, inst, 0.0, y, width + scale * 1.2, scale * 1.6, 0.0, zm.f32x4(0.05, 0.05, 0.05, 0.85 * alpha));
    var text_color = color;
    text_color[3] = alpha;
    try addText(alloc, inst, txt, .{
        .y = y,
        .offset_anchor_x = -0.5 * width,
        .offset_anchor_y = -0.35 * scale,
        .scale = scale,
        .color = text_color,
    });
}

fn asyncRenderCards(allocator: std.mem.Allocator) void {
    asyncRenderCardsWrapped(allocator) catch |err| {
        p.logErr("asyncRenderCards failed: {}", .{err});
    };
}

fn asyncRenderCardsWrapped(allocator: std.mem.Allocator) !void {
    var loader = try card_art.AtlasRenderer.init(allocator, &atlas_cards, 8, 1920, 1080);
    defer loader.deinit();

    while (try loader.step()) {
        try p.asyncPostResult(asyncRenderCardDone, .{});
    }

    const atlas = loader.finish();
    errdefer allocator.free(atlas.buffer);
    try p.asyncPostResult(asyncRenderCardsDone, .{atlas});
}

fn asyncRenderCardDone() void {
    app_state.cards_loaded += 1;
    p.logInfo("another card is done loading", .{});
}

fn asyncRenderCardsDone(rendered: card_art.Atlas) void {
    var atlas = rendered;
    defer atlas.deinit(app_state.allocator);

    app_state.cards = cardTexturesFromAtlas(&atlas);
    uploadCardTextures(&atlas);
    app_state.cards_loading = false;

    const elapsed = app_state.cards_loading_started.durationTo(std.Io.Clock.awake.now(app_state.io));
    p.logInfo("rendered all cards into a single texture: {}x{} in {}ms", .{ atlas.width, atlas.height, elapsed.toMilliseconds() });
}
