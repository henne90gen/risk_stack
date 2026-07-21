const std = @import("std");
const zm = @import("zmath");

const ft = @cImport({
    @cInclude("freetype/freetype.h");
});

const p = @import("platform.zig");

const font_file = @embedFile("LiberationMono-Regular.ttf");

// TODO this is copied from main.zig and should be consolidated at some point
const Instance = extern struct {
    model: zm.Mat align(1),
    uv_rect: zm.Vec align(1),
    render_type: i32 align(1),
};

const GlState = struct {
    tri_program: u32,
    tri_vao: u32,
    u_loc_view: i32,
    u_loc_projection: i32,
    u_loc_color: i32,
    instance_vbo: u32,
    font_atlas_tex: u32,
};

const glyph_count: usize = '~' - ' ' + 1;
pub const Font = struct {
    // load the font file
    // render out a texture atlas for the font
    // create a structure that holds all relevant data on how to use the texture atlas
    library: ft.FT_Library = undefined,
    face: ft.FT_Face = undefined,
    glyph_atlas: [glyph_count]GlyphAtlasEntry = [_]GlyphAtlasEntry{.{}} ** glyph_count,
    texture_atlas_buffer: []u8 = undefined,
    atlas_width: usize = 0,
    atlas_height: usize = 0,
    glyphs_per_row: usize = 0,
    glyphs_per_col: usize = 0,
    char_size: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Font {
        var result = Font{};

        var err = ft.FT_Init_FreeType(&result.library);
        if (err != 0) {
            return error.FontFreeTypeInitFailed;
        }

        err = ft.FT_New_Memory_Face(result.library, font_file.ptr, font_file.len, 0, &result.face);
        if (err != 0) {
            return error.FontFaceLoadFailed;
        }

        const char_size = 128;
        err = ft.FT_Set_Pixel_Sizes(result.face, char_size, char_size);
        if (err != 0) {
            return error.FontSetCharSizeFailed;
        }

        const glyphs_per_row: usize = @intFromFloat(@ceil(std.math.sqrt(@as(f64, @floatFromInt(glyph_count)))));
        const glyphs_per_col: usize = @divTrunc(glyph_count, glyphs_per_row) + 1;
        const buffer_height: usize = char_size * glyphs_per_col;
        const buffer_width: usize = char_size * glyphs_per_row;
        result.texture_atlas_buffer = try allocator.alloc(u8, buffer_width * buffer_height);
        for (0..result.texture_atlas_buffer.len) |i| {
            result.texture_atlas_buffer[i] = 0;
        }
        result.atlas_width = buffer_width;
        result.atlas_height = buffer_height;
        result.glyphs_per_row = glyphs_per_row;
        result.glyphs_per_col = glyphs_per_col;
        result.char_size = char_size;

        for (0..glyph_count) |i| {
            const c = i + ' ';
            err = ft.FT_Load_Char(result.face, c, ft.FT_LOAD_RENDER);
            if (err != 0) {
                return error.FontLoadGlyphFailed;
            }

            const start_slot_row = @divTrunc(i, glyphs_per_row);
            const start_slot_col = i % glyphs_per_row;
            const start_row = start_slot_row * char_size;
            const start_col = start_slot_col * char_size;
            const bitmap = &result.face.*.glyph.*.bitmap;
            for (0..bitmap.*.rows) |row| {
                for (0..bitmap.*.width) |col| {
                    const final_row = start_row + row;
                    const final_col = start_col + col;
                    result.texture_atlas_buffer[final_row * buffer_width + final_col] = bitmap.*.buffer[row * bitmap.*.width + col];
                }
            }

            var glyph = &result.glyph_atlas[i];
            glyph.width = bitmap.*.width;
            glyph.height = bitmap.*.rows;
            glyph.bearing_x = result.face.*.glyph.*.bitmap_left;
            glyph.bearing_y = result.face.*.glyph.*.bitmap_top;
            glyph.advance = @intCast(result.face.*.glyph.*.advance.x >> 6);

            const buffer_height_f: f32 = @floatFromInt(buffer_height);
            const buffer_width_f: f32 = @floatFromInt(buffer_width);
            const start_row_f: f32 = @floatFromInt(start_row);
            const start_col_f: f32 = @floatFromInt(start_col);
            const end_row_f: f32 = @floatFromInt(start_row + bitmap.*.rows);
            const end_col_f: f32 = @floatFromInt(start_col + bitmap.*.width);
            glyph.top_left_u = start_col_f / buffer_width_f;
            glyph.top_left_v = start_row_f / buffer_height_f;
            glyph.bottom_right_u = end_col_f / buffer_width_f;
            glyph.bottom_right_v = end_row_f / buffer_height_f;
        }

        return result;
    }

    pub fn deinit(self: *Font, allocator: std.mem.Allocator) void {
        allocator.free(self.texture_atlas_buffer);
        _ = ft.FT_Done_Face(self.face);
        _ = ft.FT_Done_FreeType(self.library);
    }

    pub fn drawText(
        self: *Font,
        allocator: std.mem.Allocator,
        text: []const u8,
        x: f32,
        y: f32,
        font_scale: f32,
    ) !std.ArrayList(DrawLetterData) {
        var result = try std.ArrayList(DrawLetterData).initCapacity(allocator, text.len);

        var current_x = x;
        const current_y = y;
        // pixels_to_ndc: convert pixel distances to NDC units.
        // char_size pixels should map to a reasonable on-screen size.
        // We treat char_size px = font_scale NDC units.
        const px2ndc: f32 = font_scale / @as(f32, @floatFromInt(self.char_size));
        for (text) |c| {
            const glyph = &self.glyph_atlas[c - ' '];

            const gw: f32 = @floatFromInt(glyph.width);
            const gh: f32 = @floatFromInt(glyph.height);
            const bx: f32 = @floatFromInt(glyph.bearing_x);
            const by: f32 = @floatFromInt(glyph.bearing_y);
            const adv: f32 = @floatFromInt(glyph.advance);

            // Quad size in NDC.
            const qw = gw * px2ndc;
            const qh = gh * px2ndc;

            // Center of the glyph quad.
            // bearing_x: pixels right from cursor to left edge of bitmap.
            // bearing_y: pixels up from baseline to top edge of bitmap.
            const cx = current_x + (bx + gw / 2.0) * px2ndc;
            const cy = -(current_y + (by - gh / 2.0) * px2ndc);

            result.appendAssumeCapacity(.{
                .x = cx,
                .y = cy,
                .width = qw,
                .height = -qh,
                .uv_rect = zm.f32x4(glyph.top_left_u, glyph.top_left_v, glyph.bottom_right_u, glyph.bottom_right_v),
            });

            current_x += adv * px2ndc;
        }

        return result;
    }
};

pub const GlyphAtlasEntry = struct {
    width: usize = 0,
    height: usize = 0,
    // Offset from the cursor origin to the top-left of the bitmap (pixels).
    bearing_x: i32 = 0,
    bearing_y: i32 = 0,
    // How far to advance the cursor after this glyph (pixels, 26.6 fixed-point >> 6).
    advance: i32 = 0,

    top_left_u: f32 = 0.0,
    top_left_v: f32 = 0.0,
    bottom_right_u: f32 = 0.0,
    bottom_right_v: f32 = 0.0,
};

pub const DrawLetterData = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    uv_rect: zm.F32x4,
};
