//! Renders the card artwork with z2d directly into an RGBA texture atlas.
//!
//! All drawing happens in "card units": a 250x350 coordinate space with the
//! origin in the top-left corner and y pointing down. Each card is mapped onto
//! its atlas cell by the canvas transformation, so the artwork is resolution
//! independent.

const std = @import("std");
const z2d = @import("z2d");
const t = std.testing;

const ft = @cImport({
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftoutln.h");
});

test {
    t.refAllDecls(@This());
}

const font_data = @embedFile("LiberationSans-Bold.ttf");

pub const Card = enum(u8) {
    @"0",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"10",
    @"11",
    @"12",
    flip_three,
    freeze,
    plus_2,
    plus_4,
    plus_6,
    plus_8,
    plus_10,
    second_chance,
    x2,
    back,
};

/// Card dimensions in card units.
pub const width = 250;
pub const height = 350;

pub const Atlas = struct {
    /// Premultiplied while drawing, converted to straight alpha once all cards
    /// are rendered.
    buffer: []z2d.pixel.RGBA,
    width: usize,
    height: usize,
    card_width: usize,
    card_height: usize,
    cards_per_row: usize,

    pub fn deinit(self: *Atlas, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
    }

    /// RGBA8 pixels with straight alpha, row-major, top-to-bottom.
    pub fn bytes(self: *const Atlas) []u8 {
        return std.mem.sliceAsBytes(self.buffer);
    }

    /// Pixel position of the top-left corner of the card at `index`.
    pub fn cardOrigin(self: *const Atlas, index: usize) [2]usize {
        return .{
            (index % self.cards_per_row) * self.card_width,
            (index / self.cards_per_row) * self.card_height,
        };
    }
};

/// Renders an atlas one card at a time, so the caller can keep drawing frames
/// (e.g. a loading screen) in between.
pub const AtlasRenderer = struct {
    allocator: std.mem.Allocator,
    faces: []const Card,
    /// Owned until `finish` hands it over.
    atlas: ?Atlas,
    scale: f64,
    font: Font,
    /// Scratch memory, reset after every card.
    arena: std.heap.ArenaAllocator,
    /// Index of the next card to render.
    next: usize = 0,

    /// `faces` must outlive the renderer.
    pub fn init(allocator: std.mem.Allocator, faces: []const Card, cards_per_row: usize, max_width: usize, max_height: usize) !AtlasRenderer {
        const rows = try std.math.divCeil(usize, faces.len, cards_per_row);
        const scale = @min(
            @as(f64, @floatFromInt(max_width)) / @as(f64, @floatFromInt(cards_per_row * width)),
            @as(f64, @floatFromInt(max_height)) / @as(f64, @floatFromInt(rows * height)),
        );
        const card_width: usize = @intFromFloat(@floor(width * scale));
        const card_height: usize = @intFromFloat(@floor(height * scale));

        var atlas = Atlas{
            .buffer = try allocator.alloc(z2d.pixel.RGBA, cards_per_row * card_width * rows * card_height),
            .width = cards_per_row * card_width,
            .height = rows * card_height,
            .card_width = card_width,
            .card_height = card_height,
            .cards_per_row = cards_per_row,
        };
        errdefer atlas.deinit(allocator);
        @memset(atlas.buffer, std.mem.zeroes(z2d.pixel.RGBA));

        return .{
            .allocator = allocator,
            .faces = faces,
            .atlas = atlas,
            .scale = scale,
            .font = try Font.init(),
            .arena = .init(allocator),
        };
    }

    pub fn deinit(self: *AtlasRenderer) void {
        if (self.atlas) |*atlas| atlas.deinit(self.allocator);
        self.font.deinit();
        self.arena.deinit();
    }

    /// Renders the next card. Returns false once every card has been rendered.
    pub fn step(self: *AtlasRenderer) !bool {
        if (self.next >= self.faces.len) return false;
        const atlas = &self.atlas.?;
        defer _ = self.arena.reset(.retain_capacity);

        // Wraps the buffer without clearing it, unlike `Surface.initBuffer`.
        var surface: z2d.Surface = .{ .image_surface_rgba = .{
            .width = @intCast(atlas.width),
            .height = @intCast(atlas.height),
            .buf = atlas.buffer,
        } };

        const origin = atlas.cardOrigin(self.next);
        var canvas = Canvas{
            .alloc = self.arena.allocator(),
            .surface = &surface,
            .font = &self.font,
            .ctm = z2d.Transformation.identity
                .translate(@floatFromInt(origin[0]), @floatFromInt(origin[1]))
                .scale(self.scale, self.scale),
        };
        try drawCard(&canvas, self.faces[self.next], origin, atlas.card_width, atlas.card_height);
        self.next += 1;
        return self.next < self.faces.len;
    }

    /// Number of cards rendered so far, out of `faces.len`.
    pub fn done(self: *const AtlasRenderer) usize {
        return self.next;
    }

    /// Converts the atlas to straight alpha and hands it over to the caller.
    /// Call once `step` has returned false.
    pub fn finish(self: *AtlasRenderer) Atlas {
        std.debug.assert(self.next == self.faces.len);
        const atlas = self.atlas.?;
        self.atlas = null;
        for (atlas.buffer) |*px| px.* = px.demultiply();
        return atlas;
    }
};

// ---------------------------------------------------------------------------
// Card layouts
// ---------------------------------------------------------------------------

const number_colors = [_]u24{
    0x8e44ad, 0xe74c3c, 0xe67e22, 0xf1c40f, 0x2ecc71, 0x1abc9c, 0x3498db,
    0x9b59b6, 0xe84393, 0xd35400, 0x16a085, 0x2980b9, 0xc0392b,
};
const modifier_color = 0xf39c12;
const white = 0xffffff;

const Front = struct {
    color: u24,
    main_text: []const u8,
    corner_text: []const u8,
    main_size: u32,
    sub_text: ?[]const u8 = null,
};

fn front(card: Card) Front {
    return switch (card) {
        .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8", .@"9", .@"10", .@"11", .@"12" => |n| .{
            .color = number_colors[@intFromEnum(n)],
            .main_text = @tagName(n),
            .corner_text = @tagName(n),
            .main_size = if (@intFromEnum(n) < 10) 140 else 120,
        },
        .plus_2 => .{ .color = modifier_color, .main_text = "+2", .corner_text = "+2", .main_size = 110, .sub_text = "BONUS" },
        .plus_4 => .{ .color = modifier_color, .main_text = "+4", .corner_text = "+4", .main_size = 110, .sub_text = "BONUS" },
        .plus_6 => .{ .color = modifier_color, .main_text = "+6", .corner_text = "+6", .main_size = 110, .sub_text = "BONUS" },
        .plus_8 => .{ .color = modifier_color, .main_text = "+8", .corner_text = "+8", .main_size = 110, .sub_text = "BONUS" },
        .plus_10 => .{ .color = modifier_color, .main_text = "+10", .corner_text = "+10", .main_size = 110, .sub_text = "BONUS" },
        .x2 => .{ .color = 0xe67e22, .main_text = "\u{00d7}2", .corner_text = "\u{00d7}2", .main_size = 110, .sub_text = "MULTIPLY" },
        .freeze => .{ .color = 0x5dade2, .main_text = "\u{2744}", .corner_text = "F", .main_size = 130, .sub_text = "FREEZE" },
        .flip_three => .{ .color = 0xaf7ac5, .main_text = "3\u{21bb}", .corner_text = "F3", .main_size = 100, .sub_text = "FLIP THREE" },
        .second_chance => .{ .color = 0xec7063, .main_text = "\u{21ba}", .corner_text = "SC", .main_size = 130, .sub_text = "SECOND CHANCE" },
        .back => unreachable,
    };
}

fn drawCard(canvas: *Canvas, card: Card, origin: [2]usize, card_width: usize, card_height: usize) !void {
    if (card == .back) {
        try drawBack(canvas, origin, card_width, card_height);
    } else {
        try drawFront(canvas, front(card));
    }
}

fn drawFront(canvas: *Canvas, card: Front) !void {
    const outline = try canvas.roundedRect(1, 1, width - 2, height - 2, 18);
    try canvas.fill(&outline, try canvas.linearGradient(.{ .x = 1, .y = 1, .w = width - 2, .h = height - 2 }, .diagonal, &.{
        .{ .offset = 0, .color = card.color },
        .{ .offset = 1, .color = card.color, .alpha = 0.75 },
    }, 1));
    try canvas.stroke(&outline, solid(white, 1), 2);

    try canvas.stroke(&try canvas.roundedRect(12, 12, width - 24, height - 24, 12), solid(white, 0.5), 3);
    try canvas.fill(&try canvas.circle(width / 2, height / 2, 82), solid(white, 0.12));

    const corner_style = TextStyle{ .size = 30 };
    try canvas.fill(&try canvas.text(card.corner_text, 24, 46, corner_style), solid(white, 1));
    {
        const saved = canvas.ctm;
        defer canvas.ctm = saved;
        canvas.rotateAround(std.math.pi, width / 2, height / 2);
        try canvas.fill(&try canvas.text(card.corner_text, 24, 46, corner_style), solid(white, 1));
    }

    const main_y: u32 = if (card.sub_text != null) height / 2 + 15 else height / 2 + card.main_size / 3;
    const main_text = try canvas.text(card.main_text, width / 2, @floatFromInt(main_y), .{
        .size = @floatFromInt(card.main_size),
        .anchor = .middle,
    });
    // paint-order="stroke": the stroke goes underneath the fill.
    try canvas.stroke(&main_text, solid(0x000000, 0x30.0 / 255.0), 3);
    try canvas.fill(&main_text, solid(white, 1));

    if (card.sub_text) |sub_text| {
        // Short labels stay on one line, longer ones get one line per word.
        var lines = std.mem.splitScalar(u8, sub_text, if (sub_text.len <= 8) 0 else ' ');
        var i: f64 = 0;
        while (lines.next()) |line| : (i += 1) {
            try canvas.fill(&try canvas.text(line, width / 2, height / 2 + 60 + i * 38, .{
                .size = 30,
                .anchor = .middle,
                .letter_spacing = 2,
            }), solid(white, 1));
        }
    }
}

fn drawBack(canvas: *Canvas, origin: [2]usize, card_width: usize, card_height: usize) !void {
    const outline = try canvas.roundedRect(1, 1, width - 2, height - 2, 18);
    try canvas.fill(&outline, try canvas.linearGradient(.{ .x = 1, .y = 1, .w = width - 2, .h = height - 2 }, .diagonal, &.{
        .{ .offset = 0, .color = 0x1a1a2e },
        .{ .offset = 1, .color = 0x16213e },
    }, 1));

    { // diamond pattern, clipped to the card outline
        var layer = try canvas.layer(card_width, card_height);
        var diamonds = layer.path();
        var y: f64 = 0;
        while (y < height) : (y += 30) {
            var x: f64 = 0;
            while (x < width) : (x += 30) {
                try diamonds.moveTo(layer.alloc, x + 15, y + 2);
                try diamonds.lineTo(layer.alloc, x + 28, y + 15);
                try diamonds.lineTo(layer.alloc, x + 15, y + 28);
                try diamonds.lineTo(layer.alloc, x + 2, y + 15);
                try diamonds.close(layer.alloc);
            }
        }
        try layer.stroke(&diamonds, solid(white, 0.12), 1);

        var clip = try canvas.layer(card_width, card_height);
        try clip.fill(&try clip.roundedRect(1, 1, width - 2, height - 2, 18), solid(white, 1));
        applyMask(layer.surface.image_surface_rgba.buf, clip.surface.image_surface_rgba.buf);
        canvas.composite(layer.surface, origin);
    }

    try canvas.stroke(&outline, solid(white, 1), 2);
    try canvas.stroke(&try canvas.roundedRect(12, 12, width - 24, height - 24, 12), solid(white, 0.35), 2.5);

    const shimmer = [_]Stop{
        .{ .offset = 0, .color = 0xe040fb },
        .{ .offset = 0.5, .color = 0x7c4dff },
        .{ .offset = 1, .color = 0x40c4ff },
    };
    try canvas.stroke(&try canvas.circle(125, 175, 88), try canvas.linearGradient(.{ .x = 37, .y = 87, .w = 176, .h = 176 }, .diagonal, &shimmer, 0.6), 3);
    try canvas.stroke(&try canvas.circle(125, 175, 72), try canvas.linearGradient(.{ .x = 53, .y = 103, .w = 144, .h = 144 }, .diagonal, &shimmer, 0.35), 1.5);
    try canvas.fill(&try canvas.circle(125, 175, 60), solid(white, 0.04));

    try canvas.fill(&try canvas.roundedRect(62, 148, 126, 54, 12), try canvas.linearGradient(.{ .x = 62, .y = 148, .w = 126, .h = 54 }, .vertical, &.{
        .{ .offset = 0, .color = 0x7c4dff, .alpha = 0.85 },
        .{ .offset = 1, .color = 0xe040fb, .alpha = 0.85 },
    }, 1));

    { // title with a glow: a blurred copy of the text underneath the text itself
        var layer = try canvas.layer(card_width, card_height);
        try drawBackTitle(&layer);
        try blur(layer.alloc, &layer.surface.image_surface_rgba, 3 * layer.ctm.ax);
        canvas.composite(layer.surface, origin);
        try drawBackTitle(canvas);
    }

    const star_style = TextStyle{ .size = 22 };
    try canvas.fill(&try canvas.text("\u{2726}", 24, 44, star_style), solid(white, 0.5));
    {
        const saved = canvas.ctm;
        defer canvas.ctm = saved;
        canvas.rotateAround(std.math.pi, 225, 310);
        try canvas.fill(&try canvas.text("\u{2726}", 226, 314, star_style), solid(white, 0.5));
    }
}

fn drawBackTitle(canvas: *Canvas) !void {
    try canvas.fill(&try canvas.text("RISK", 125, 167, .{ .size = 20, .anchor = .middle, .letter_spacing = 4 }), solid(white, 1));
    try canvas.fill(&try canvas.text("STACK", 125, 193, .{ .size = 26, .anchor = .middle, .letter_spacing = 6 }), solid(white, 1));
}

// ---------------------------------------------------------------------------
// Drawing primitives
// ---------------------------------------------------------------------------

const Rect = struct { x: f64, y: f64, w: f64, h: f64 };

const Stop = struct {
    offset: f32,
    color: u24,
    alpha: f32 = 1,
};

const Anchor = enum { start, middle };

const TextStyle = struct {
    size: f64,
    anchor: Anchor = .start,
    /// Extra space after every glyph, in card units.
    letter_spacing: f64 = 0,
};

fn channels(color: u24) [3]f32 {
    return .{
        @as(f32, @floatFromInt((color >> 16) & 0xff)) / 255,
        @as(f32, @floatFromInt((color >> 8) & 0xff)) / 255,
        @as(f32, @floatFromInt(color & 0xff)) / 255,
    };
}

fn solid(color: u24, alpha: f64) z2d.Pattern {
    const c = channels(color);
    return .{ .opaque_pattern = .{ .pixel = z2d.pixel.RGBA.fromClamped(c[0], c[1], c[2], alpha).asPixel() } };
}

const Canvas = struct {
    /// Scratch memory, reset after every card.
    alloc: std.mem.Allocator,
    surface: *z2d.Surface,
    font: *Font,
    /// Maps card units to device pixels.
    ctm: z2d.Transformation,

    /// Creates an empty, card-sized surface that shares this canvas' scale.
    fn layer(self: *Canvas, card_width: usize, card_height: usize) !Canvas {
        const surface = try self.alloc.create(z2d.Surface);
        surface.* = try z2d.Surface.init(.image_surface_rgba, self.alloc, @intCast(card_width), @intCast(card_height));
        return .{
            .alloc = self.alloc,
            .surface = surface,
            .font = self.font,
            .ctm = z2d.Transformation.identity.scale(self.ctm.ax, self.ctm.dy),
        };
    }

    fn composite(self: *Canvas, src: *const z2d.Surface, origin: [2]usize) void {
        self.surface.composite(src, .src_over, @intCast(origin[0]), @intCast(origin[1]), .{});
    }

    fn rotateAround(self: *Canvas, angle: f64, cx: f64, cy: f64) void {
        self.ctm = self.ctm.translate(cx, cy).rotate(angle).translate(-cx, -cy);
    }

    fn path(self: *const Canvas) z2d.Path {
        var p: z2d.Path = .empty;
        p.transformation = self.ctm;
        return p;
    }

    fn fill(self: *Canvas, p: *const z2d.Path, pattern: z2d.Pattern) !void {
        try z2d.painter.fill(self.alloc, self.surface, &pattern, p.nodes.items, .{});
    }

    fn stroke(self: *Canvas, p: *const z2d.Path, pattern: z2d.Pattern, line_width: f64) !void {
        try z2d.painter.stroke(self.alloc, self.surface, &pattern, p.nodes.items, .{
            .line_width = line_width,
            .transformation = self.ctm,
        });
    }

    /// Linear gradient in objectBoundingBox units of `bbox`, `alpha` scales
    /// the alpha of every stop.
    fn linearGradient(self: *Canvas, bbox: Rect, direction: enum { diagonal, vertical }, stops: []const Stop, alpha: f32) !z2d.Pattern {
        const gradient = try self.alloc.create(z2d.Gradient);
        gradient.* = .init(.{
            .type = .{ .linear = .{
                .x0 = 0,
                .y0 = 0,
                .x1 = if (direction == .diagonal) 1 else 0,
                .y1 = 1,
            } },
            // SVG interpolates the raw sRGB values; passing them as "linear"
            // colors keeps z2d from converting them.
            .method = .linear_rgb,
        });
        for (stops) |stop| {
            const c = channels(stop.color);
            try gradient.addStop(self.alloc, stop.offset, .{ .rgba = .{ c[0], c[1], c[2], stop.alpha * alpha } });
        }
        try gradient.setTransformation(self.ctm.translate(bbox.x, bbox.y).scale(bbox.w, bbox.h));
        return gradient.asPattern();
    }

    fn roundedRect(self: *Canvas, x: f64, y: f64, w: f64, h: f64, r: f64) !z2d.Path {
        const pi = std.math.pi;
        var p = self.path();
        try p.moveTo(self.alloc, x + r, y);
        try p.arc(self.alloc, x + w - r, y + r, r, -pi / 2.0, 0);
        try p.arc(self.alloc, x + w - r, y + h - r, r, 0, pi / 2.0);
        try p.arc(self.alloc, x + r, y + h - r, r, pi / 2.0, pi);
        try p.arc(self.alloc, x + r, y + r, r, pi, 3.0 * pi / 2.0);
        try p.close(self.alloc);
        return p;
    }

    fn circle(self: *Canvas, cx: f64, cy: f64, r: f64) !z2d.Path {
        var p = self.path();
        try p.arc(self.alloc, cx, cy, r, 0, 2 * std.math.pi);
        try p.close(self.alloc);
        return p;
    }

    /// Outline of `str` with its baseline at `y`. The symbols Liberation Sans
    /// lacks are drawn by `Symbol`.
    fn text(self: *Canvas, str: []const u8, x: f64, y: f64, style: TextStyle) !z2d.Path {
        const view = try std.unicode.Utf8View.init(str);

        var total_advance: f64 = 0;
        var it = view.iterator();
        while (it.nextCodepoint()) |cp| {
            total_advance += try self.advance(cp, style.size) + style.letter_spacing;
        }

        var pen = switch (style.anchor) {
            .start => x,
            .middle => x - total_advance / 2,
        };
        var p = self.path();
        it = view.iterator();
        while (it.nextCodepoint()) |cp| {
            if (Symbol.fromCodepoint(cp)) |symbol| {
                try symbol.addTo(&p, self.alloc, pen, y, style.size);
            } else {
                try self.font.addGlyph(&p, self.alloc, cp, pen, y, style.size);
            }
            pen += try self.advance(cp, style.size) + style.letter_spacing;
        }
        return p;
    }

    fn advance(self: *Canvas, cp: u21, size: f64) !f64 {
        if (Symbol.fromCodepoint(cp)) |symbol| return symbol.advance() * size;
        const glyph = try self.font.load(cp);
        return @as(f64, @floatFromInt(glyph.*.metrics.horiAdvance)) * self.font.scale(size);
    }
};

/// Liberation Sans Bold, metric-compatible with the Arial Bold the original
/// SVG artwork asked for. Glyphs are loaded unscaled and converted to z2d
/// paths.
const Font = struct {
    library: ft.FT_Library,
    face: ft.FT_Face,

    fn init() !Font {
        var library: ft.FT_Library = undefined;
        if (ft.FT_Init_FreeType(&library) != 0) return error.FontFreeTypeInitFailed;
        errdefer _ = ft.FT_Done_FreeType(library);

        var face: ft.FT_Face = undefined;
        if (ft.FT_New_Memory_Face(library, font_data.ptr, font_data.len, 0, &face) != 0) return error.FontFaceLoadFailed;
        return .{ .library = library, .face = face };
    }

    fn deinit(self: *Font) void {
        _ = ft.FT_Done_Face(self.face);
        _ = ft.FT_Done_FreeType(self.library);
    }

    /// Font units to card units at font size `size`.
    fn scale(self: *const Font, size: f64) f64 {
        return size / @as(f64, @floatFromInt(self.face.*.units_per_EM));
    }

    fn load(self: *Font, cp: u21) !ft.FT_GlyphSlot {
        const index = ft.FT_Get_Char_Index(self.face, cp);
        if (index == 0) return error.FontMissingGlyph;
        if (ft.FT_Load_Glyph(self.face, index, ft.FT_LOAD_NO_SCALE | ft.FT_LOAD_NO_HINTING | ft.FT_LOAD_NO_BITMAP) != 0) {
            return error.FontLoadGlyphFailed;
        }
        return self.face.*.glyph;
    }

    /// Appends the outline of `cp` with its origin at (`x`, `y`) to `p`.
    fn addGlyph(self: *Font, p: *z2d.Path, alloc: std.mem.Allocator, cp: u21, x: f64, y: f64, size: f64) !void {
        const glyph = try self.load(cp);
        var sink = OutlineSink{ .path = p, .alloc = alloc, .x = x, .y = y, .scale = self.scale(size) };
        const funcs = ft.FT_Outline_Funcs{
            .move_to = OutlineSink.moveTo,
            .line_to = OutlineSink.lineTo,
            .conic_to = OutlineSink.conicTo,
            .cubic_to = OutlineSink.cubicTo,
            .shift = 0,
            .delta = 0,
        };
        const err = ft.FT_Outline_Decompose(&glyph.*.outline, &funcs, &sink);
        if (sink.err) |e| return e;
        if (err != 0) return error.FontDecomposeOutlineFailed;
        if (sink.open) try p.close(alloc);
    }

    /// Receives FreeType outline segments and adds them to a z2d path,
    /// flipping the y axis from font space (up) to card space (down).
    const OutlineSink = struct {
        path: *z2d.Path,
        alloc: std.mem.Allocator,
        x: f64,
        y: f64,
        scale: f64,
        current: [2]f64 = .{ 0, 0 },
        open: bool = false,
        err: ?anyerror = null,

        fn point(self: *const OutlineSink, v: [*c]const ft.FT_Vector) [2]f64 {
            return .{
                self.x + @as(f64, @floatFromInt(v.*.x)) * self.scale,
                self.y - @as(f64, @floatFromInt(v.*.y)) * self.scale,
            };
        }

        fn from(user: ?*anyopaque) *OutlineSink {
            return @ptrCast(@alignCast(user));
        }

        fn result(self: *OutlineSink, r: anyerror!void) c_int {
            r catch |e| {
                self.err = e;
                return 1;
            };
            return 0;
        }

        fn moveTo(to: [*c]const ft.FT_Vector, user: ?*anyopaque) callconv(.c) c_int {
            const self = from(user);
            const p = self.point(to);
            if (self.open) {
                if (self.result(self.path.close(self.alloc)) != 0) return 1;
            }
            self.open = true;
            self.current = p;
            return self.result(self.path.moveTo(self.alloc, p[0], p[1]));
        }

        fn lineTo(to: [*c]const ft.FT_Vector, user: ?*anyopaque) callconv(.c) c_int {
            const self = from(user);
            const p = self.point(to);
            self.current = p;
            return self.result(self.path.lineTo(self.alloc, p[0], p[1]));
        }

        fn conicTo(control: [*c]const ft.FT_Vector, to: [*c]const ft.FT_Vector, user: ?*anyopaque) callconv(.c) c_int {
            const self = from(user);
            const p0 = self.current;
            const c = self.point(control);
            const p3 = self.point(to);
            // Quadratic to cubic: both control points sit 2/3 of the way to
            // the quadratic control point.
            const c1 = .{ p0[0] + 2.0 / 3.0 * (c[0] - p0[0]), p0[1] + 2.0 / 3.0 * (c[1] - p0[1]) };
            const c2 = .{ p3[0] + 2.0 / 3.0 * (c[0] - p3[0]), p3[1] + 2.0 / 3.0 * (c[1] - p3[1]) };
            self.current = p3;
            return self.result(self.path.curveTo(self.alloc, c1[0], c1[1], c2[0], c2[1], p3[0], p3[1]));
        }

        fn cubicTo(control1: [*c]const ft.FT_Vector, control2: [*c]const ft.FT_Vector, to: [*c]const ft.FT_Vector, user: ?*anyopaque) callconv(.c) c_int {
            const self = from(user);
            const c1 = self.point(control1);
            const c2 = self.point(control2);
            const p3 = self.point(to);
            self.current = p3;
            return self.result(self.path.curveTo(self.alloc, c1[0], c1[1], c2[0], c2[1], p3[0], p3[1]));
        }
    };
};

/// Glyphs Liberation Sans doesn't have, drawn as vector shapes. Coordinates
/// are in em units relative to the horizontal center of the glyph on the
/// baseline, y pointing down.
const Symbol = enum {
    snowflake,
    clockwise_arrow,
    counterclockwise_arrow,
    star,

    fn fromCodepoint(cp: u21) ?Symbol {
        return switch (cp) {
            0x2744 => .snowflake,
            0x21bb => .clockwise_arrow,
            0x21ba => .counterclockwise_arrow,
            0x2726 => .star,
            else => null,
        };
    }

    fn advance(self: Symbol) f64 {
        return switch (self) {
            .snowflake => 0.6,
            .clockwise_arrow, .counterclockwise_arrow => 0.94,
            .star => 0.77,
        };
    }

    fn addTo(self: Symbol, p: *z2d.Path, alloc: std.mem.Allocator, pen_x: f64, baseline_y: f64, size: f64) !void {
        const saved = p.transformation;
        defer p.transformation = saved;
        p.transformation = saved.translate(pen_x + self.advance() * size / 2, baseline_y).scale(size, size);

        switch (self) {
            .snowflake => try drawSnowflake(p, alloc),
            .clockwise_arrow => {
                // Mirror image of the counterclockwise arrow.
                p.transformation = p.transformation.scale(-1, 1);
                try drawCircularArrow(p, alloc);
            },
            .counterclockwise_arrow => try drawCircularArrow(p, alloc),
            .star => try drawStar(p, alloc),
        }
    }

    fn drawSnowflake(p: *z2d.Path, alloc: std.mem.Allocator) !void {
        const cy = -0.53;
        const arm = 0.25;
        const half_width = 0.021;
        const branch_at = 0.55 * arm;
        const branch_len = 0.42 * arm;
        for (0..6) |i| {
            const angle = std.math.pi / 2.0 + @as(f64, @floatFromInt(i)) * std.math.pi / 3.0;
            const dx = @cos(angle);
            const dy = @sin(angle);
            try bar(p, alloc, 0, cy, dx * arm, cy + dy * arm, half_width);

            const bx = dx * branch_at;
            const by = cy + dy * branch_at;
            for ([_]f64{ -1, 1 }) |side| {
                const branch_angle = angle + side * std.math.pi / 4.0;
                try bar(p, alloc, bx, by, bx + @cos(branch_angle) * branch_len, by + @sin(branch_angle) * branch_len, half_width);
            }
        }
    }

    /// Rectangle from (x0, y0) to (x1, y1). All bars share the same winding
    /// direction, so overlapping bars merge under the non-zero fill rule.
    fn bar(p: *z2d.Path, alloc: std.mem.Allocator, x0: f64, y0: f64, x1: f64, y1: f64, half_width: f64) !void {
        const len = std.math.hypot(x1 - x0, y1 - y0);
        const nx = -(y1 - y0) / len * half_width;
        const ny = (x1 - x0) / len * half_width;
        try p.moveTo(alloc, x0 + nx, y0 + ny);
        try p.lineTo(alloc, x1 + nx, y1 + ny);
        try p.lineTo(alloc, x1 - nx, y1 - ny);
        try p.lineTo(alloc, x0 - nx, y0 - ny);
        try p.close(alloc);
    }

    /// A ring open between 9 and 12 o'clock with an arrowhead at 12 o'clock
    /// pointing to the left.
    fn drawCircularArrow(p: *z2d.Path, alloc: std.mem.Allocator) !void {
        const pi = std.math.pi;
        const cy = -0.57;
        const outer = 0.36;
        const inner = 0.245;
        const mid = (outer + inner) / 2.0;

        // Explicit move, otherwise the arc connects to the previous glyph.
        try p.moveTo(alloc, 0, cy - outer);
        try p.arc(alloc, 0, cy, outer, -pi / 2.0, pi);
        try p.lineTo(alloc, -inner, cy);
        try p.arcNegative(alloc, 0, cy, inner, pi, -pi / 2.0);
        try p.close(alloc);

        try p.moveTo(alloc, 0, cy - mid - 0.24);
        try p.lineTo(alloc, 0, cy - mid + 0.24);
        try p.lineTo(alloc, -0.22, cy - mid);
        try p.close(alloc);
    }

    /// Four-pointed star with concave sides.
    fn drawStar(p: *z2d.Path, alloc: std.mem.Allocator) !void {
        const cy = -0.34;
        const r = 0.37;
        const c = 0.07;
        try p.moveTo(alloc, 0, cy - r);
        try p.curveTo(alloc, c, cy - c, c, cy - c, r, cy);
        try p.curveTo(alloc, c, cy + c, c, cy + c, 0, cy + r);
        try p.curveTo(alloc, -c, cy + c, -c, cy + c, -r, cy);
        try p.curveTo(alloc, -c, cy - c, -c, cy - c, 0, cy - r);
        try p.close(alloc);
    }
};

/// Scales every pixel by the alpha of the corresponding `mask` pixel. Used for
/// clipping instead of z2d's unbounded operators (e.g. `.dst_in`), which are
/// broken in its multisample rasterizer.
fn applyMask(pixels: []z2d.pixel.RGBA, mask: []const z2d.pixel.RGBA) void {
    for (pixels, mask) |*px, m| {
        const a: u16 = m.a;
        px.* = .{
            .r = @intCast((@as(u16, px.r) * a + 127) / 255),
            .g = @intCast((@as(u16, px.g) * a + 127) / 255),
            .b = @intCast((@as(u16, px.b) * a + 127) / 255),
            .a = @intCast((@as(u16, px.a) * a + 127) / 255),
        };
    }
}

/// Approximates a gaussian blur with standard deviation `std_dev` (in pixels)
/// by three box blurs per axis, as described in the SVG feGaussianBlur spec.
fn blur(alloc: std.mem.Allocator, surface: *z2d.surface.ImageSurface(z2d.pixel.RGBA), std_dev: f64) !void {
    const box: usize = @intFromFloat(@floor(std_dev * 3.0 * @sqrt(2.0 * std.math.pi) / 4.0 + 0.5));
    if (box < 2) return;
    const radius = box / 2;

    const w: usize = @intCast(surface.width);
    const h: usize = @intCast(surface.height);
    const tmp = try alloc.alloc(z2d.pixel.RGBA, surface.buf.len);
    defer alloc.free(tmp);

    var src = surface.buf;
    var dst = tmp;
    for ([_]bool{ true, true, true, false, false, false }) |horizontal| {
        if (horizontal) {
            for (0..h) |row| boxBlurLine(src, dst, row * w, 1, w, radius);
        } else {
            for (0..w) |col| boxBlurLine(src, dst, col, w, h, radius);
        }
        std.mem.swap([]z2d.pixel.RGBA, &src, &dst);
    }
    // An even number of passes leaves the result in the surface buffer.
}

fn boxBlurLine(src: []const z2d.pixel.RGBA, dst: []z2d.pixel.RGBA, start: usize, stride: usize, len: usize, radius: usize) void {
    const window: u32 = @intCast(2 * radius + 1);
    var sum = @Vector(4, u32){ 0, 0, 0, 0 };
    for (0..@min(radius, len)) |i| sum += vec(src[start + i * stride]);
    for (0..len) |i| {
        if (i + radius < len) sum += vec(src[start + (i + radius) * stride]);
        if (i > radius) sum -= vec(src[start + (i - radius - 1) * stride]);
        const avg = (sum + @as(@Vector(4, u32), @splat(window / 2))) / @as(@Vector(4, u32), @splat(window));
        dst[start + i * stride] = .{ .r = @intCast(avg[0]), .g = @intCast(avg[1]), .b = @intCast(avg[2]), .a = @intCast(avg[3]) };
    }
}

fn vec(px: z2d.pixel.RGBA) @Vector(4, u32) {
    return .{ px.r, px.g, px.b, px.a };
}

test "AtlasRenderer renders every card" {
    const faces = std.enums.values(Card);
    var renderer = try AtlasRenderer.init(t.allocator, faces, 8 , 400, 215);
    defer renderer.deinit();
    while (try renderer.step()) {}
    var atlas = renderer.finish();
    defer atlas.deinit(t.allocator);

    try t.expectEqual(@as(usize, 50), atlas.card_width);
    try t.expectEqual(@as(usize, 8 * 50), atlas.width);
    try t.expectEqual(@as(usize, 3 * 70), atlas.height);
    try t.expectEqual(atlas.width * atlas.height * 4, atlas.bytes().len);

    for (0..faces.len) |i| {
        const origin = atlas.cardOrigin(i);
        const corner = atlas.buffer[origin[1] * atlas.width + origin[0]];
        const center = atlas.buffer[(origin[1] + 35) * atlas.width + origin[0] + 25];
        // Rounded corners stay transparent, the card body is (nearly) opaque.
        try t.expectEqual(@as(u8, 0), corner.a);
        try t.expect(center.a > 200);
    }
}
