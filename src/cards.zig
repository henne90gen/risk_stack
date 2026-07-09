/// Embedded card PNG data for the native binary.
///
/// Each variant of `Card` corresponds to a PNG file from static/cards/.
/// Access the raw bytes via `card_data[@intFromEnum(card)]`, `Card.bytes()`,
/// or the path-based `Card.fromPath("/0.png")` used by `platform.texture`.
const std = @import("std");

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

    /// Return the embedded PNG bytes for this card.
    pub fn bytes(self: Card) []const u8 {
        return card_data[@intFromEnum(self)];
    }

    /// Look up a card by its URL path, e.g. "/cards/0.png" or "/cards/flip_three.png".
    /// Returns null when the path does not match any known card.
    pub fn fromPath(path: []const u8) ?Card {
        // Strip leading '/' and optional 'cards/' directory segment.
        var name = path;
        if (name.len > 0 and name[0] == '/') name = name[1..];
        const dir = "cards/";
        if (std.mem.startsWith(u8, name, dir)) name = name[dir.len..];
        // Strip trailing '.png'.
        const ext = ".png";
        if (name.len >= ext.len and std.mem.eql(u8, name[name.len - ext.len ..], ext)) {
            name = name[0 .. name.len - ext.len];
        }
        return std.meta.stringToEnum(Card, name);
    }
};

/// All card PNGs baked into the binary at compile time, indexed by `Card`.
pub const card_data: [std.enums.values(Card).len][]const u8 = .{
    @embedFile("cards/0.png"),
    @embedFile("cards/1.png"),
    @embedFile("cards/2.png"),
    @embedFile("cards/3.png"),
    @embedFile("cards/4.png"),
    @embedFile("cards/5.png"),
    @embedFile("cards/6.png"),
    @embedFile("cards/7.png"),
    @embedFile("cards/8.png"),
    @embedFile("cards/9.png"),
    @embedFile("cards/10.png"),
    @embedFile("cards/11.png"),
    @embedFile("cards/12.png"),
    @embedFile("cards/flip_three.png"),
    @embedFile("cards/freeze.png"),
    @embedFile("cards/plus_2.png"),
    @embedFile("cards/plus_4.png"),
    @embedFile("cards/plus_6.png"),
    @embedFile("cards/plus_8.png"),
    @embedFile("cards/plus_10.png"),
    @embedFile("cards/second_chance.png"),
    @embedFile("cards/x2.png"),
};

test "card_data length matches Card enum" {
    try std.testing.expectEqual(std.enums.values(Card).len, card_data.len);
}

test "card_data entries are non-empty PNG files" {
    const png_sig = "\x89PNG\r\n\x1a\n";
    for (card_data) |data| {
        try std.testing.expect(data.len >= 8);
        try std.testing.expectEqualSlices(u8, png_sig, data[0..8]);
    }
}

test "Card.fromPath round-trips every card" {
    for (std.enums.values(Card)) |card| {
        var buf: [64]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "/cards/{s}.png", .{@tagName(card)}) catch unreachable;
        try std.testing.expectEqual(card, Card.fromPath(path).?);
    }
}

test "Card.fromPath returns null for unknown paths" {
    try std.testing.expect(Card.fromPath("/unknown.png") == null);
    try std.testing.expect(Card.fromPath("/0.jpg") == null);
    try std.testing.expect(Card.fromPath("") == null);
}
