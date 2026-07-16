const std = @import("std");

const ft = @cImport({
    @cInclude("freetype/freetype.h");
});

const p = @import("platform.zig");

const font_file = @embedFile("LiberationMono-Regular.ttf");

pub const Font = struct {
    // load the font file
    // render out a texture atlas for the font
    // create a structure that holds all relevant data on how to use the texture atlas
    library: ft.FT_Library = undefined,
    face: ft.FT_Face = undefined,

    pub fn init(allocator: std.mem.Allocator) !Font {
        var library: ft.FT_Library = undefined;
        var err = ft.FT_Init_FreeType(&library);
        if (err != 0) {
            return error.FontFreeTypeInitFailed;
        }

        var face: ft.FT_Face = undefined;
        err = ft.FT_New_Memory_Face(library, font_file.ptr, font_file.len, 0, &face);
        if (err != 0) {
            return error.FontFaceLoadFailed;
        }

        p.logInfo("Face: {}", .{face.*});

        const char_size = 128;
        err = ft.FT_Set_Pixel_Sizes(face, char_size, char_size);
        if (err != 0) {
            return error.FontSetCharSizeFailed;
        }

        const glyph_count = '~' - ' ' + 1;
        const glyphs_per_row = @ceil(std.math.sqrt(@as(f64, @floatFromInt(glyph_count))));
        const glyphs_per_col = glyph_count / glyphs_per_row;
        const buffer_width: usize = @intFromFloat(char_size * glyphs_per_row);
        const buffer_height: usize = @intFromFloat(char_size * glyphs_per_col);
        const buffer = try allocator.alloc(u8, buffer_width * buffer_height);

        p.logInfo("{} x {}", .{ buffer_width, buffer_height });

        var current_row = 0;
        var current_col = 0;
        for (0..glyph_count) |i| {
            const c = i + ' ';
            err = ft.FT_Load_Char(face, c, ft.FT_LOAD_RENDER);
            if (err != 0) {
                return error.FontLoadGlyphFailed;
            }

            // TODO write loaded glyph into texture atlas
            // TODO save glyph data into some global storage (including the position on the texture atlas, maybe even in uv-coordinates)
        }

        return .{ .library = library, .face = face };
    }

    pub fn deinit(self: *Font) void {
        _ = ft.FT_Done_Face(self.face);
        _ = ft.FT_Done_FreeType(self.library);
    }
};
