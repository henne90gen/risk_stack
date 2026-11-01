const std = @import("std");

const Card = struct {
    file_name: []const u8,
    content: []const u8,
};

fn card_svg(allocator: std.mem.Allocator, background_color: []const u8, main_text: []const u8, corner_text: []const u8, main_size: u32, sub_text: ?[]const u8) ![]const u8 {
    const W = 250;
    const H = 350;
    const R = 18; // corner radius

    const corner =
        try std.fmt.allocPrint(allocator,
            \\<text x="24" y="46" font-family="Arial, sans-serif" font-size="30" font-weight="bold" fill="#ffffff">{s}</text>
            \\<text x="24" y="46" font-family="Arial, sans-serif" font-size="30" font-weight="bold" fill="#ffffff" transform="rotate(180 {} {})">{s}</text>
        , .{ corner_text, W / 2, H / 2, corner_text });
    defer allocator.free(corner);

    // TODO simplify main_y calculation
    var main_y = H / 2 + (if (sub_text != null) 0 else main_size / 3);
    if (sub_text != null) {
        main_y = H / 2 + 15;
    }
    const main_ =
        try std.fmt.allocPrint(allocator,
            \\<text
            \\  x="{}"
            \\  y="{}"
            \\  font-family="Arial, sans-serif"
            \\  font-size="{}"
            \\  font-weight="bold"
            \\  fill="#ffffff"
            \\  text-anchor="middle"
            \\  stroke="#00000030"
            \\  stroke-width="3"
            \\  paint-order="stroke">{s}</text>
        , .{ W / 2, main_y, main_size, main_text });
    defer allocator.free(main_);

    const sub = if (sub_text) |text| blk: {
        var parts = try std.ArrayList(u8).initCapacity(allocator, 0);
        var lines = if (text.len <= 8) std.mem.splitAny(u8, text, "") else std.mem.splitAny(u8, text, " ");
        var i: u32 = 0;
        while (lines.next()) |line| {
            const s = try std.fmt.allocPrint(allocator,
                \\<text
                \\  x="{}"
                \\  y="{}"
                \\  font-family="Arial, sans-serif"
                \\  font-size="30"
                \\  font-weight="bold"
                \\  fill="#ffffff"
                \\  text-anchor="middle"
                \\  letter-spacing="2"
                \\>{s}</text>
            , .{ W / 2, H / 2 + 60 + i * 38, line });
            defer allocator.free(s);
            try parts.appendSlice(allocator, s);
            i += 1;
        }
        break :blk try parts.toOwnedSlice(allocator);
    } else try allocator.alloc(u8, 0);
    defer allocator.free(sub);

    return try std.fmt.allocPrint(allocator,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{}" height="{}" viewBox="0 0 {} {}">
        \\  <defs>
        \\    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
        \\      <stop offset="0" stop-color="{s}"/>
        \\      <stop offset="1" stop-color="{s}" stop-opacity="0.75"/>
        \\    </linearGradient>
        \\  </defs>
        \\  <rect x="1" y="1" width="{}" height="{}" rx="{}" fill="url(#bg)" stroke="#ffffff" stroke-width="2"/>
        \\  <rect x="12" y="12" width="{}" height="{}" rx="{}" fill="none" stroke="#ffffff" stroke-width="3" stroke-opacity="0.5"/>
        \\  <circle cx="{}" cy="{}" r="82" fill="#ffffff" fill-opacity="0.12"/>
        \\  {s}
        \\  {s}
        \\  {s}
        \\</svg>
    , .{
        W,
        H,
        W,
        H,
        background_color,
        background_color,
        W - 2,
        H - 2,
        R,
        W - 24,
        H - 24,
        R - 6,
        W / 2,
        H / 2,
        corner,
        main_,
        sub,
    });
}

// ./gen_cards <folder>
pub fn main(init: std.process.Init) !void {
    var args_itr = try std.process.Args.iterateAllocator(init.minimal.args, init.gpa);
    defer args_itr.deinit();
    _ = args_itr.skip();

    const directory_name_opt = args_itr.next();
    if (directory_name_opt == null) {
        return;
    }

    const directory_name = directory_name_opt.?;
    const directory = try std.Io.Dir.cwd().openDir(init.io, directory_name, .{});
    const stats = try directory.stat(init.io);
    if (stats.kind != .directory) {
        std.log.err("Directory {s} does not exist.", .{directory_name});
        return;
    }

    const path = try directory.realPathFileAlloc(init.io, "", init.gpa);
    defer init.gpa.free(path);
    std.log.info("Generating cards into directory '{s}'", .{path});

    var files = try std.ArrayList(Card).initCapacity(init.gpa, 23);
    defer {
        for (files.items) |f| {
            init.gpa.free(f.file_name);
            init.gpa.free(f.content);
        }
        files.deinit(init.gpa);
    }

    { // number cards
        const NUMBER_COLORS = [_][]const u8{
            "#8e44ad",
            "#e74c3c",
            "#e67e22",
            "#f1c40f",
            "#2ecc71",
            "#1abc9c",
            "#3498db",
            "#9b59b6",
            "#e84393",
            "#d35400",
            "#16a085",
            "#2980b9",
            "#c0392b",
        };

        for (0..13) |n| {
            const size: u32 = if (n < 10) 140 else 120;
            var buf = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
            const num_str = try std.fmt.bufPrint(&buf, "{}", .{n});
            try files.append(init.gpa, .{
                .file_name = try std.fmt.allocPrint(init.gpa, "{}.svg", .{n}),
                .content = try card_svg(init.gpa, NUMBER_COLORS[n], num_str, num_str, size, null),
            });
        }
    }

    { // modifier cards
        const MODIFIER_COLOR = "#f39c12";
        for (1..6) |i| {
            const n = i * 2;
            var buf = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
            const num_str = try std.fmt.bufPrint(&buf, "+{}", .{n});
            const size = 110;
            try files.append(init.gpa, .{
                .file_name = try std.fmt.allocPrint(init.gpa, "plus_{}.svg", .{n}),
                .content = try card_svg(init.gpa, MODIFIER_COLOR, num_str, num_str, size, "BONUS"),
            });
        }
    }

    { // x2.svg
        const X2_COLOR = "#e67e22";
        const text = "\u{00d7}2";
        const size = 110;
        try files.append(init.gpa, .{
            .file_name = try std.fmt.allocPrint(init.gpa, "x2.svg", .{}),
            .content = try card_svg(init.gpa, X2_COLOR, text, text, size, "MULTIPLY"),
        });
    }

    { // freeze.svg
        const FREEZE_COLOR = "#5dade2";
        const main_text = "\u{2744}";
        try files.append(init.gpa, .{
            .file_name = try std.fmt.allocPrint(init.gpa, "freeze.svg", .{}),
            .content = try card_svg(init.gpa, FREEZE_COLOR, main_text, "F", 130, "FREEZE"),
        });
    }

    { // flip_three.svg
        const FLIP_THREE_COLOR = "#af7ac5";
        const main_text = "3\u{21bb}";
        try files.append(init.gpa, .{
            .file_name = try std.fmt.allocPrint(init.gpa, "flip_three.svg", .{}),
            .content = try card_svg(init.gpa, FLIP_THREE_COLOR, main_text, "F3", 100, "FLIP THREE"),
        });
    }

    { // second_chance.svg
        const SECOND_CHANCE_COLOR = "#ec7063";
        const main_text = "\u{21ba}";
        try files.append(init.gpa, .{
            .file_name = try std.fmt.allocPrint(init.gpa, "second_chance.svg", .{}),
            .content = try card_svg(init.gpa, SECOND_CHANCE_COLOR, main_text, "SC", 130, "SECOND CHANCE"),
        });
    }

    { // back.svg
        const content =
            \\<svg xmlns="http://www.w3.org/2000/svg" width="250" height="350" viewBox="0 0 250 350">
            \\  <defs>
            \\    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
            \\      <stop offset="0" stop-color="#1a1a2e"/>
            \\      <stop offset="1" stop-color="#16213e"/>
            \\    </linearGradient>
            \\    <pattern id="diamonds" x="0" y="0" width="30" height="30" patternUnits="userSpaceOnUse">
            \\      <polygon points="15,2 28,15 15,28 2,15" fill="none" stroke="#ffffff" stroke-width="1" stroke-opacity="0.12"/>
            \\    </pattern>
            \\    <linearGradient id="shimmer" x1="0" y1="0" x2="1" y2="1">
            \\      <stop offset="0" stop-color="#e040fb"/>
            \\      <stop offset="0.5" stop-color="#7c4dff"/>
            \\      <stop offset="1" stop-color="#40c4ff"/>
            \\    </linearGradient>
            \\    <linearGradient id="labelBg" x1="0" y1="0" x2="0" y2="1">
            \\      <stop offset="0" stop-color="#7c4dff" stop-opacity="0.85"/>
            \\      <stop offset="1" stop-color="#e040fb" stop-opacity="0.85"/>
            \\    </linearGradient>
            \\    <filter id="glow">
            \\      <feGaussianBlur stdDeviation="3" result="blur"/>
            \\      <feMerge>
            \\        <feMergeNode in="blur"/>
            \\        <feMergeNode in="SourceGraphic"/>
            \\      </feMerge>
            \\    </filter>
            \\  </defs>
            \\  <rect x="1" y="1" width="248" height="348" rx="18" fill="url(#bg)"/>
            \\  <rect x="1" y="1" width="248" height="348" rx="18" fill="url(#diamonds)"/>
            \\  <rect x="1" y="1" width="248" height="348" rx="18" fill="none" stroke="#ffffff" stroke-width="2"/>
            \\  <rect x="12" y="12" width="226" height="326" rx="12" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-opacity="0.35"/>
            \\  <circle cx="125" cy="175" r="88" fill="none" stroke="url(#shimmer)" stroke-width="3" stroke-opacity="0.6"/>
            \\  <circle cx="125" cy="175" r="72" fill="none" stroke="url(#shimmer)" stroke-width="1.5" stroke-opacity="0.35"/>
            \\  <circle cx="125" cy="175" r="60" fill="#ffffff" fill-opacity="0.04"/>
            \\  <rect x="62" y="148" width="126" height="54" rx="12" fill="url(#labelBg)"/>
            \\  <text x="125" y="167" font-family="Arial, sans-serif" font-size="20" font-weight="bold" fill="#ffffff" text-anchor="middle" letter-spacing="4" filter="url(#glow)">RISK</text>
            \\  <text x="125" y="193" font-family="Arial, sans-serif" font-size="26" font-weight="bold" fill="#ffffff" text-anchor="middle" letter-spacing="6" filter="url(#glow)">STACK</text>
            \\  <text x="24" y="44" font-family="Arial, sans-serif" font-size="22" fill="#ffffff" fill-opacity="0.5">&#x2726;</text>
            \\  <text x="226" y="314" font-family="Arial, sans-serif" font-size="22" fill="#ffffff" fill-opacity="0.5" transform="rotate(180 225 310)">&#x2726;</text>
            \\</svg>
        ;
        try files.append(init.gpa, .{
            .file_name = try std.fmt.allocPrint(init.gpa, "back.svg", .{}),
            .content = try std.fmt.allocPrint(init.gpa, "{s}", .{content}),
        });
    }

    for (files.items) |file| {
        const f = try directory.createFile(init.io, file.file_name, .{});
        defer f.close(init.io);

        try f.writeStreamingAll(init.io, file.content);
    }
}
