const std = @import("std");
const m = @import("main.zig");

comptime {
    if (@import("builtin").target.cpu.arch == .wasm32) {
        m.p.run(m.RiskStackApp);
    }
}

const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/ftsystem.h");
    @cInclude("freetype/fttypes.h");
});

const wa = std.heap.wasm_allocator;

fn ftAlloc(_: ft.FT_Memory, size: c_long) callconv(.c) ?*anyopaque {
    const buf = wa.alloc(u8, @intCast(size)) catch return null;
    return buf.ptr;
}

fn ftRealloc(memory: ft.FT_Memory, cur_size: c_long, new_size: c_long, block: ?*anyopaque) callconv(.c) ?*anyopaque {
    if (block == null) return ftAlloc(memory, new_size);
    if (new_size == 0) return null;
    const new_buf = wa.alloc(u8, @intCast(new_size)) catch return null;
    const old: [*]u8 = @ptrCast(block.?);
    const copy_len: usize = @intCast(@min(cur_size, new_size));
    @memcpy(new_buf[0..copy_len], old[0..copy_len]);
    return new_buf.ptr;
}

fn ftFree(_: ft.FT_Memory, block: ?*anyopaque) callconv(.c) void {
    _ = block; // no-op
}

var ft_memory_rec = ft.FT_MemoryRec_{
    .user = null,
    .alloc = &ftAlloc,
    .free = &ftFree,
    .realloc = &ftRealloc,
};

export fn FT_New_Memory() ft.FT_Memory {
    return &ft_memory_rec;
}

export fn FT_Done_Memory(_: ft.FT_Memory) void {}

export fn qsort(
    base: ?*anyopaque,
    nmemb: usize,
    size: usize,
    compar: *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int,
) void {
    const b: [*]u8 = @ptrCast(base orelse return);
    const Context = struct {
        items: [*]u8,
        item_size: usize,
        cmp: *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int,

        pub fn lessThan(ctx: @This(), a: usize, b_idx: usize) bool {
            return ctx.cmp(
                ctx.items + a * ctx.item_size,
                ctx.items + b_idx * ctx.item_size,
            ) < 0;
        }

        pub fn swap(ctx: @This(), a: usize, b_idx: usize) void {
            const pa = ctx.items + a * ctx.item_size;
            const pb = ctx.items + b_idx * ctx.item_size;
            var k: usize = 0;
            while (k < ctx.item_size) : (k += 1) {
                const tmp = pa[k];
                pa[k] = pb[k];
                pb[k] = tmp;
            }
        }
    };

    std.sort.insertionContext(0, nmemb, Context{ .items = b, .item_size = size, .cmp = compar });
}

export fn strtol(nptr: ?[*:0]const u8, endptr: ?*?[*:0]const u8, base: c_int) c_long {
    const p: [*:0]const u8 = nptr orelse {
        if (endptr) |ep| {
            ep.* = nptr;
        }
        return 0;
    };

    // Skip leading whitespace.
    var start: usize = 0;
    while (p[start] == ' ' or p[start] == '\t' or p[start] == '\n') {
        start += 1;
    }

    // Detect base prefix when base == 0.
    var radix: u8 = if (base == 0) 10 else @intCast(base);
    if ((base == 0 or base == 16) and p[start] == '0' and
        (p[start + 1] == 'x' or p[start + 1] == 'X'))
    {
        radix = 16;
        start += 2;
    } else if (base == 0 and p[start] == '0') {
        radix = 8;
        start += 1;
    }

    // Find the end of the numeric portion.
    const slice = std.mem.sliceTo(p + start, 0);
    var num_len: usize = 0;
    for (slice) |c| {
        const valid = switch (c) {
            '0'...'9' => (c - '0') < radix,
            'a'...'f' => radix > 10,
            'A'...'F' => radix > 10,
            '+', '-' => num_len == 0,
            else => false,
        };

        if (!valid) {
            break;
        }

        num_len += 1;
    }

    const result = std.fmt.parseInt(c_long, slice[0..num_len], radix) catch 0;
    if (endptr) |ep| {
        ep.* = p + start + num_len;
    }
    return result;
}
