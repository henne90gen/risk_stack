//! A multi-producer channel of type-erased closures.
//!
//! Worker threads `post` a function together with its arguments; the thread
//! that owns the channel (the main thread, which owns the GL context) calls
//! `drain` once per frame to run everything that has arrived. The channel
//! never learns what kinds of results flow through it.
//!
//! The lock is a spinlock on purpose: the critical sections only touch the
//! list, and on wasm the main thread must never block on an atomic wait.

const std = @import("std");

pub const Message = struct {
    ctx: *anyopaque,
    /// Runs on the draining thread, then frees `ctx`.
    run: *const fn (ctx: *anyopaque, gpa: std.mem.Allocator) void,
    /// Frees `ctx` without running; used for messages that were never drained.
    deinit: *const fn (ctx: *anyopaque, gpa: std.mem.Allocator) void,
};

pub const Channel = struct {
    /// Owns the message contexts. Must be safe to use from every posting thread.
    allocator: std.mem.Allocator,
    queue: std.ArrayList(Message) = .empty,
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(allocator: std.mem.Allocator) Channel {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Channel) void {
        for (self.queue.items) |msg| msg.deinit(msg.ctx, self.allocator);
        self.queue.deinit(self.allocator);
    }

    fn lock(self: *Channel) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
    }

    /// Thread-safe. `args` is copied into a heap allocation owned by the
    /// channel until the message is run.
    pub fn post(self: *Channel, comptime function: anytype, args: std.meta.ArgsTuple(@TypeOf(function))) !void {
        const Args = @TypeOf(args);
        const ctx = try self.allocator.create(Args);
        errdefer self.allocator.destroy(ctx);
        ctx.* = args;
        const Gen = struct {
            fn run(ptr: *anyopaque, a: std.mem.Allocator) void {
                const args_casted: *const Args = @ptrCast(@alignCast(ptr));
                defer a.destroy(args_casted);
                @call(.auto, function, args_casted.*);
            }
            fn deinit(ptr: *anyopaque, a: std.mem.Allocator) void {
                const args_casted: *const Args = @ptrCast(@alignCast(ptr));
                a.destroy(args_casted);
            }
        };

        self.lock();
        defer self.mutex.unlock();
        try self.queue.append(self.allocator, .{ .ctx = ctx, .run = Gen.run, .deinit = Gen.deinit });
    }

    /// Runs every message posted so far, in order. The lock is only held to
    /// take the queue, so handlers run without blocking the posters.
    pub fn drain(self: *Channel) void {
        self.lock();
        var pending = self.queue;
        self.queue = .empty;
        self.mutex.unlock();
        defer pending.deinit(self.allocator);

        for (pending.items) |msg| msg.run(msg.ctx, self.allocator);
    }
};

test "post and drain run messages in order and free their contexts" {
    const Log = struct {
        var items: [3]u32 = undefined;
        var len: usize = 0;
        fn record(v: u32) void {
            items[len] = v;
            len += 1;
        }
    };
    Log.len = 0;

    var ch = Channel.init(std.testing.allocator);
    defer ch.deinit();
    try ch.post(Log.record, .{1});
    try ch.post(Log.record, .{2});
    try ch.post(Log.record, .{3});
    ch.drain();
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3 }, &Log.items);

    ch.drain(); // empty: nothing happens
    try std.testing.expectEqual(@as(usize, 3), Log.len);
}

test "undelivered messages are freed by deinit" {
    const Noop = struct {
        fn f(_: u32) void {}
    };
    var ch = Channel.init(std.testing.allocator);
    try ch.post(Noop.f, .{7});
    ch.deinit(); // testing allocator reports a leak if the context isn't freed
}
