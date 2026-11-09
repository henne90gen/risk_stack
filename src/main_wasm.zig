const std = @import("std");
const m = @import("main.zig");
const threads = @import("wasm_threads.zig");

/// Safe to use from the worker threads as well, unlike `std.heap.wasm_allocator`.
pub const wasm_allocator = threads.allocator;

comptime {
    if (@import("builtin").target.cpu.arch == .wasm32) {
        _ = threads.workerEntry; // exported for worker.js
        m.p.run(m.RiskStackApp, wasm_allocator, wasm_io, .{});
    }
}

// ---------------------------------------------------------------------------
// Io implementation backed by browser APIs.
// Everything not overridden here behaves like `std.Io.failing`, except that
// `async` runs the function right away. Groups run on web workers.
// ---------------------------------------------------------------------------

/// `Date.now()`: milliseconds since the Unix epoch.
extern fn dateNow() f64;
/// `performance.now()`: monotonic milliseconds since page load.
extern fn performanceNow() f64;
/// Fills `ptr[0..len]` via `crypto.getRandomValues()`.
extern fn getRandomValues(ptr: [*]u8, len: usize) void;

fn ioNow(_: ?*anyopaque, clock: std.Io.Clock) std.Io.Timestamp {
    const ms = switch (clock) {
        .real => dateNow(),
        .awake, .boot, .cpu_process, .cpu_thread => performanceNow(),
    };
    return .fromNanoseconds(@intFromFloat(ms * std.time.ns_per_ms));
}

fn ioRandom(_: ?*anyopaque, buffer: []u8) void {
    // getRandomValues() accepts at most 65536 bytes per call.
    var rest = buffer;
    while (rest.len > 0) {
        const n = @min(rest.len, 65536);
        getRandomValues(rest.ptr, n);
        rest = rest[n..];
    }
}

fn ioRandomSecure(userdata: ?*anyopaque, buffer: []u8) std.Io.RandomSecureError!void {
    ioRandom(userdata, buffer);
}

const wasm_io_vtable: std.Io.VTable = blk: {
    var vtable = std.Io.failing.vtable.*;
    vtable.now = ioNow;
    vtable.random = ioRandom;
    vtable.randomSecure = ioRandomSecure;
    vtable.groupAsync = threads.groupAsync;
    vtable.groupConcurrent = threads.groupConcurrent;
    vtable.groupAwait = threads.groupAwait;
    vtable.groupCancel = threads.groupCancel;
    break :blk vtable;
};

pub const wasm_io: std.Io = .{ .userdata = null, .vtable = &wasm_io_vtable };

const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/ftsystem.h");
    @cInclude("freetype/fttypes.h");
});

const wa = wasm_allocator;

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
