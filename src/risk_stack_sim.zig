const std = @import("std");
const t = std.testing;

const f7 = @import("risk_stack.zig");

test {
    t.refAllDecls(@This());
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const games_to_run = 100_000;

    const SharedResults = struct {
        mutex: std.Io.Mutex = .init,
        total_cards_played: u64 = 0,
        total_runtime: std.Io.Duration = std.Io.Duration.fromSeconds(0),
        draw_strategy_wins: std.HashMap(f7.DrawStrategy, u32, f7.DrawStrategy.Context, std.hash_map.default_max_load_percentage),
    };
    var shared = SharedResults{
        .draw_strategy_wins = std.HashMap(f7.DrawStrategy, u32, f7.DrawStrategy.Context, std.hash_map.default_max_load_percentage).init(allocator),
    };
    defer shared.draw_strategy_wins.deinit();

    const WorkerContext = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        games: u32,
        shared: *SharedResults,
        prng: std.Random.DefaultPrng,

        fn run(ctx: *@This()) void {
            ctx.runAll() catch |err| {
                std.debug.print("Worker error: {}\n", .{err});
            };
        }

        fn runAll(ctx: *@This()) !void {
            var local_cards_played: u64 = 0;
            var local_runtime: std.Io.Duration = .fromSeconds(0);
            var local_wins = std.HashMap(f7.DrawStrategy, u32, f7.DrawStrategy.Context, std.hash_map.default_max_load_percentage).init(ctx.allocator);
            defer local_wins.deinit();

            std.debug.print("Simulating {d} games\n", .{ctx.games});

            for (0..ctx.games) |_| {
                const start_time = std.Io.Clock.now(.real, ctx.io);
                const result = try runGame(ctx.allocator, ctx.prng.random());
                const end_time = std.Io.Clock.now(.real, ctx.io);
                local_cards_played += result.cards_played;
                local_runtime = .fromNanoseconds(local_runtime.nanoseconds + start_time.durationTo(end_time).nanoseconds);
                const current_wins = local_wins.get(result.winning_strategy) orelse 0;
                try local_wins.put(result.winning_strategy, current_wins + 1);
            }

            try ctx.shared.mutex.lock(ctx.io);
            defer ctx.shared.mutex.unlock(ctx.io);

            ctx.shared.total_cards_played += local_cards_played;
            ctx.shared.total_runtime = .fromNanoseconds(ctx.shared.total_runtime.nanoseconds + local_runtime.nanoseconds);
            var it = local_wins.iterator();
            while (it.next()) |entry| {
                const current_wins = ctx.shared.draw_strategy_wins.get(entry.key_ptr.*) orelse 0;
                try ctx.shared.draw_strategy_wins.put(entry.key_ptr.*, current_wins + entry.value_ptr.*);
            }
        }

        fn runGame(task_allocator: std.mem.Allocator, prng: std.Random) !f7.GameResult {
            var arena = std.heap.ArenaAllocator.init(task_allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            var deck = try f7.Deck.init(arena_allocator, prng);
            defer deck.deinit(arena_allocator);

            var players = [_]f7.Player{
                try .init(arena_allocator, prng, .{ .MinPoints = 20 }),
                try .init(arena_allocator, prng, .{ .MinPoints = 30 }),
                try .init(arena_allocator, prng, .{ .MinPoints = 40 }),
                try .init(arena_allocator, prng, .{ .MinPoints = 50 }),
                try .init(arena_allocator, prng, .{ .MaxCards = 3 }),
                try .init(arena_allocator, prng, .{ .MaxCards = 4 }),
                try .init(arena_allocator, prng, .{ .MaxCards = 5 }),
                try .init(arena_allocator, prng, .{ .MinPointsMaxCards = .{ .min_points = 30, .max_cards = 5 } }),
                try .init(arena_allocator, prng, .{ .MinPointsMaxCards = .{ .min_points = 30, .max_cards = 4 } }),
                try .init(arena_allocator, prng, .{ .MinPointsMaxCards = .{ .min_points = 30, .max_cards = 3 } }),
                try .init(arena_allocator, prng, .{ .MinPointsMaxCards = .{ .min_points = 20, .max_cards = 5 } }),
                try .init(arena_allocator, prng, .{ .MinPointsMaxCards = .{ .min_points = 20, .max_cards = 4 } }),
                try .init(arena_allocator, prng, .{ .MinPointsMaxCards = .{ .min_points = 20, .max_cards = 3 } }),
                try .init(arena_allocator, prng, .Always7),
                try .init(arena_allocator, prng, .Random),
                try .init(arena_allocator, prng, .{ .RandomMinCards = 1 }),
                try .init(arena_allocator, prng, .{ .RandomMinCards = 2 }),
                try .init(arena_allocator, prng, .{ .RandomMinCards = 3 }),
                try .init(arena_allocator, prng, .{ .RandomMinCards = 4 }),
                try .init(arena_allocator, prng, .{ .ChanceOfFailureBelow = 0.1 }),
                try .init(arena_allocator, prng, .{ .ChanceOfFailureBelow = 0.2 }),
                try .init(arena_allocator, prng, .{ .ChanceOfFailureBelow = 0.3 }),
                try .init(arena_allocator, prng, .{ .ChanceOfFailureBelow = 0.4 }),
            };
            defer {
                for (&players) |*player| {
                    player.deinit(arena_allocator);
                }
            }

            var simulation = try f7.GameSimulation.init(arena_allocator, prng, &deck, &players);
            defer simulation.deinit();

            while (try simulation.step()) {}
            return simulation.result();
        }
    };

    const cpu_count = try std.Thread.getCpuCount();
    const thread_count = @min(cpu_count, games_to_run);
    const games_per_thread = games_to_run / thread_count;
    const remainder = games_to_run % thread_count;

    const contexts = try allocator.alloc(WorkerContext, thread_count);
    defer allocator.free(contexts);

    var threaded = std.Io.Threaded.init(allocator, .{
        // .async_limit = .nothing,
    });
    const io = threaded.io();
    defer threaded.deinit();

    const start_time = std.Io.Clock.now(.real, io);

    var group: std.Io.Group = .init;
    for (0..thread_count) |i| {
        // Distribute the remainder games across the first few threads.
        const extra: u32 = if (i < remainder) 1 else 0;
        contexts[i] = .{
            .allocator = allocator,
            .io = io,
            .games = @intCast(games_per_thread + extra),
            .shared = &shared,
            .prng = std.Random.DefaultPrng.init(@intCast(std.Io.Clock.now(.real, io).toMilliseconds() +% @as(i64, @intCast(i)))),
        };
        group.async(io, WorkerContext.run, .{&contexts[i]});
    }

    try group.await(io);

    const end_time = std.Io.Clock.now(.real, io);
    const overall_runtime = start_time.durationTo(end_time);

    const total_cards_played = shared.total_cards_played;
    const total_runtime = shared.total_runtime;
    var draw_strategy_wins = shared.draw_strategy_wins;

    std.debug.print("\n", .{});
    std.debug.print("Total cards played:       {d}\n", .{total_cards_played});
    std.debug.print("Total runtime:            {d}ms\n", .{overall_runtime.toMilliseconds()});
    std.debug.print("Average runtime per game: {d}ns\n", .{@divFloor(total_runtime.toNanoseconds(), games_to_run)});
    std.debug.print("\n", .{});

    // Collect entries into a slice so we can sort them.
    const Entry = struct { strategy: f7.DrawStrategy, wins: u32 };
    var entries = try std.ArrayList(Entry).initCapacity(allocator, 8);
    defer entries.deinit(allocator);
    var itr = draw_strategy_wins.iterator();
    while (itr.next()) |entry| {
        try entries.append(allocator, .{ .strategy = entry.key_ptr.*, .wins = entry.value_ptr.* });
    }
    std.mem.sort(Entry, entries.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            return a.wins > b.wins;
        }
    }.lessThan);
    for (entries.items) |entry| {
        const pct = @as(f64, @floatFromInt(entry.wins)) / @as(f64, games_to_run) * 100.0;
        std.debug.print("{d:5} times won ({d:5.2}%) Strategy {}\n", .{ entry.wins, pct, entry.strategy });
    }
}
