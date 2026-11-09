//! Parallelism for the wasm build: a fixed pool of web workers that share the
//! module's memory.
//!
//! Every worker instantiates the same module on the same (shared) memory, so a
//! function pointer and a context pointer mean the same thing on every thread.
//! That is what lets `std.Io.Group.async` stay transparent: the vtable below
//! only ever sees a type-erased `start` function plus the bytes of its
//! arguments, copies them into a task, and a worker calls `start` on them.
//!
//! Constraints that shape this file:
//! * The module is built with `single_threaded = true` (std's wasm allocator
//!   only exists in that mode), so std does no locking for us. Everything that
//!   is shared between threads is guarded here: the allocator, the task queue
//!   and the channel in `channel.zig`.
//! * The browser's main thread must never block on an atomic wait, so every
//!   lock is a spinlock and `groupAwait`/`groupCancel` spin. Workers sleep on
//!   `memory.atomic.wait32` while the queue is empty.
//! * Memory is shared, so the host has to create it (see `static/index.html`);
//!   its size must match `initial_memory`/`max_memory` in `build.zig`.

const std = @import("std");
const Alignment = std.mem.Alignment;
const Group = std.Io.Group;

/// Starts a worker which will call `workerEntry(stack_top)`.
extern fn spawnWorker(stack_top: usize) void;
extern fn hardwareConcurrency() u32;

const max_workers = 4;
const worker_stack_size = 2 * 1024 * 1024;

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

// ---------------------------------------------------------------------------
// Allocator
// ---------------------------------------------------------------------------

/// `std.heap.wasm_allocator` has no locking of its own: serialize access to it.
const backing = std.heap.wasm_allocator;
var heap_mutex: std.atomic.Mutex = .unlocked;

fn heapAlloc(_: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    lock(&heap_mutex);
    defer heap_mutex.unlock();
    return backing.vtable.alloc(backing.ptr, len, alignment, ret_addr);
}

fn heapResize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
    lock(&heap_mutex);
    defer heap_mutex.unlock();
    return backing.vtable.resize(backing.ptr, memory, alignment, new_len, ret_addr);
}

fn heapRemap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    lock(&heap_mutex);
    defer heap_mutex.unlock();
    return backing.vtable.remap(backing.ptr, memory, alignment, new_len, ret_addr);
}

fn heapFree(_: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
    lock(&heap_mutex);
    defer heap_mutex.unlock();
    backing.vtable.free(backing.ptr, memory, alignment, ret_addr);
}

/// Safe to use from the main thread and every worker.
pub const allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &.{
        .alloc = heapAlloc,
        .resize = heapResize,
        .remap = heapRemap,
        .free = heapFree,
    },
};

// ---------------------------------------------------------------------------
// Task queue
// ---------------------------------------------------------------------------

const Task = struct {
    next: ?*Task = null,
    group: *Group,
    start: *const fn (context: *const anyopaque) void,
    context: []u8,
    alignment: Alignment,

    /// Releases the task's memory and tells its group that it is done.
    fn finish(task: *Task) void {
        const group = task.group;
        allocator.rawFree(task.context, task.alignment, @returnAddress());
        allocator.destroy(task);
        // Last: once the count hits zero `groupAwait` may return and the
        // caller may free the group.
        _ = @atomicRmw(usize, &group.state, .Sub, 1, .release);
    }
};

var queue_mutex: std.atomic.Mutex = .unlocked;
var queue_head: ?*Task = null;
var queue_tail: ?*Task = null;
/// Bumped on every push; idle workers sleep on it.
var wake_seq: i32 = 0;

var workers_started = false;
var worker_count: u32 = 0;

/// Sleeps while `*ptr == expected`. Never call this on the main thread.
inline fn wait(ptr: *i32, expected: i32) void {
    _ = asm volatile (
        \\local.get %[ptr]
        \\local.get %[expected]
        \\local.get %[timeout]
        \\memory.atomic.wait32 0
        \\local.set %[ret]
        : [ret] "=r" (-> u32),
        : [ptr] "r" (ptr),
          [expected] "r" (expected),
          [timeout] "r" (@as(i64, -1)),
    );
}

inline fn wake(ptr: *i32, max_waiters: u32) void {
    _ = asm volatile (
        \\local.get %[ptr]
        \\local.get %[waiters]
        \\memory.atomic.notify 0
        \\local.set %[ret]
        : [ret] "=r" (-> u32),
        : [ptr] "r" (ptr),
          [waiters] "r" (max_waiters),
    );
}

fn push(task: *Task) void {
    lock(&queue_mutex);
    if (queue_tail) |tail| tail.next = task else queue_head = task;
    queue_tail = task;
    queue_mutex.unlock();

    _ = @atomicRmw(i32, &wake_seq, .Add, 1, .release);
    wake(&wake_seq, 1);
}

fn pop() ?*Task {
    lock(&queue_mutex);
    defer queue_mutex.unlock();
    const task = queue_head orelse return null;
    queue_head = task.next;
    if (queue_head == null) queue_tail = null;
    return task;
}

/// Spawns the pool on first use. Only the main thread starts tasks first, so
/// no synchronization is needed here.
fn ensureWorkers() void {
    if (workers_started) return;
    workers_started = true;

    const wanted = @max(1, @min(max_workers, hardwareConcurrency() -| 1));
    for (0..wanted) |_| {
        const stack = allocator.alignedAlloc(u8, .@"16", worker_stack_size) catch break;
        spawnWorker(@intFromPtr(stack.ptr) + stack.len);
        worker_count += 1;
    }
}

/// Moves the wasm stack pointer. Every instance has its own copy of the global,
/// but a fresh worker starts with the main thread's stack top.
inline fn setStackPointer(addr: usize) void {
    asm volatile (
        \\ local.get %[ptr]
        \\ global.set __stack_pointer
        :
        : [ptr] "r" (addr),
    );
}

/// Called by `worker.js` once the module is instantiated. Never returns.
pub export fn workerEntry(stack_top: usize) callconv(.c) void {
    setStackPointer(stack_top);
    workerLoop();
}

noinline fn workerLoop() noreturn {
    while (true) {
        const seen = @atomicLoad(i32, &wake_seq, .acquire);
        if (pop()) |task| {
            task.start(task.context.ptr);
            task.finish();
            continue;
        }
        // Returns immediately if a push bumped `wake_seq` after `seen`.
        wait(&wake_seq, seen);
    }
}

// ---------------------------------------------------------------------------
// std.Io vtable entries
// ---------------------------------------------------------------------------

/// `Group.token` only has to be non-null while the group may have pending tasks.
const pending_token: *anyopaque = @ptrFromInt(1);

fn enqueue(group: *Group, context: []const u8, alignment: Alignment, start: *const fn (context: *const anyopaque) void) error{OutOfMemory}!void {
    ensureWorkers();
    if (worker_count == 0) return error.OutOfMemory;

    const copy = allocator.rawAlloc(context.len, alignment, @returnAddress()) orelse return error.OutOfMemory;
    errdefer allocator.rawFree(copy[0..context.len], alignment, @returnAddress());
    @memcpy(copy[0..context.len], context);

    const task = try allocator.create(Task);
    task.* = .{ .group = group, .start = start, .context = copy[0..context.len], .alignment = alignment };

    _ = @atomicRmw(usize, &group.state, .Add, 1, .monotonic);
    group.token.store(pending_token, .release);
    push(task);
}

pub fn groupAsync(_: ?*anyopaque, group: *Group, context: []const u8, alignment: Alignment, start: *const fn (context: *const anyopaque) void) void {
    // Without a worker the only way to make progress is to run the task now.
    enqueue(group, context, alignment, start) catch start(context.ptr);
}

pub fn groupConcurrent(_: ?*anyopaque, group: *Group, context: []const u8, alignment: Alignment, start: *const fn (context: *const anyopaque) void) std.Io.ConcurrentError!void {
    enqueue(group, context, alignment, start) catch return error.ConcurrencyUnavailable;
}

fn waitIdle(group: *Group) void {
    while (@atomicLoad(usize, &group.state, .acquire) != 0) std.atomic.spinLoopHint();
    group.token.store(null, .release);
}

pub fn groupAwait(_: ?*anyopaque, group: *Group, _: *anyopaque) std.Io.Cancelable!void {
    waitIdle(group);
}

/// Drops the group's tasks that have not started yet and waits for the running
/// ones: running tasks cannot be interrupted.
pub fn groupCancel(_: ?*anyopaque, group: *Group, _: *anyopaque) void {
    var dropped: ?*Task = null;
    {
        lock(&queue_mutex);
        defer queue_mutex.unlock();
        var link: *?*Task = &queue_head;
        var prev: ?*Task = null;
        while (link.*) |task| {
            if (task.group == group) {
                link.* = task.next;
                task.next = dropped;
                dropped = task;
            } else {
                prev = task;
                link = &task.next;
            }
        }
        queue_tail = prev;
    }
    while (dropped) |task| {
        dropped = task.next;
        task.finish();
    }
    waitIdle(group);
}
