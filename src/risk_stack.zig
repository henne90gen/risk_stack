const std = @import("std");
const Io = std.Io;
const t = std.testing;

test {
    t.refAllDecls(@This());
}

pub const Card = enum(u8) {
    Zero = 0,
    One = 1,
    Two = 2,
    Three = 3,
    Four = 4,
    Five = 5,
    Six = 6,
    Seven = 7,
    Eight = 8,
    Nine = 9,
    Ten = 10,
    Eleven = 11,
    Twelve = 12,

    SecondChance = 13,
    Freeze = 14,
    FlipThree = 15,

    PlusTwo = 16,
    PlusFour = 17,
    PlusSix = 18,
    PlusEight = 19,
    PlusTen = 20,

    TimesTwo = 21,

    pub fn isNumber(self: Card) bool {
        return @intFromEnum(self) <= @intFromEnum(Card.Twelve);
    }
};

pub const Deck = struct {
    prng: std.Random,
    cards: std.ArrayList(Card),
    discarded: std.ArrayList(Card),

    pub fn init(allocator: std.mem.Allocator, prng: std.Random) !Deck {
        var deck = Deck{
            .prng = prng,
            .cards = try std.ArrayList(Card).initCapacity(allocator, 94),
            .discarded = try std.ArrayList(Card).initCapacity(allocator, 94),
        };
        try deck.refill(allocator);
        deck.shuffle();
        return deck;
    }

    pub fn deinit(self: *Deck, allocator: std.mem.Allocator) void {
        self.cards.deinit(allocator);
        self.discarded.deinit(allocator);
    }

    pub fn shuffle(self: *Deck) void {
        // u32 indices: `shuffle` uses usize, which draws differently on wasm32.
        std.Random.shuffleWithIndex(self.prng, Card, self.cards.items, u32);
    }

    pub fn refill(self: *Deck, allocator: std.mem.Allocator) !void {
        self.discarded.clearRetainingCapacity();
        self.cards.clearRetainingCapacity();

        try self.cards.append(allocator, Card.Zero);
        try self.cards.append(allocator, Card.One);
        try self.cards.append(allocator, Card.Two);
        try self.cards.append(allocator, Card.Two);
        for (0..3) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Three);
        }
        for (0..4) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Four);
        }
        for (0..5) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Five);
        }
        for (0..6) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Six);
        }
        for (0..7) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Seven);
        }
        for (0..8) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Eight);
        }
        for (0..9) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Nine);
        }
        for (0..10) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Ten);
        }
        for (0..11) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Eleven);
        }
        for (0..12) |i| {
            _ = i;
            try self.cards.append(allocator, Card.Twelve);
        }

        try self.cards.append(allocator, Card.SecondChance);
        try self.cards.append(allocator, Card.SecondChance);
        try self.cards.append(allocator, Card.SecondChance);
        try self.cards.append(allocator, Card.Freeze);
        try self.cards.append(allocator, Card.Freeze);
        try self.cards.append(allocator, Card.Freeze);
        try self.cards.append(allocator, Card.FlipThree);
        try self.cards.append(allocator, Card.FlipThree);
        try self.cards.append(allocator, Card.FlipThree);

        try self.cards.append(allocator, Card.PlusTwo);
        try self.cards.append(allocator, Card.PlusFour);
        try self.cards.append(allocator, Card.PlusSix);
        try self.cards.append(allocator, Card.PlusEight);
        try self.cards.append(allocator, Card.PlusTen);
        try self.cards.append(allocator, Card.TimesTwo);
    }

    pub fn discard(self: *Deck, allocator: std.mem.Allocator, card: Card) !void {
        try self.discarded.append(allocator, card);
    }

    /// Shuffles the discard pile into the draw pile. Cards still held by
    /// players stay out of the deck, like in the physical game.
    pub fn reshuffleDiscarded(self: *Deck, allocator: std.mem.Allocator) !void {
        try self.cards.appendSlice(allocator, self.discarded.items);
        self.discarded.clearRetainingCapacity();
        self.shuffle();
    }

    pub fn removeCard(self: *Deck, card: Card) !void {
        for (self.cards.items, 0..) |c, i| {
            if (c == card) {
                _ = self.cards.orderedRemove(i);
                return;
            }
        }
        return error.CardNotFound;
    }

    pub fn probabilityOfDrawingCard(self: *Deck, card: Card) f64 {
        var remaining_cards: u32 = 0;
        for (self.cards.items) |dc| {
            if (dc == card) {
                remaining_cards += 1;
            }
        }

        const remaining_cards_f64: f64 = @floatFromInt(remaining_cards);
        const total_cards_f64: f64 = @floatFromInt(self.cards.items.len);
        return remaining_cards_f64 / total_cards_f64;
    }

    test "probabilityOfDrawingCard" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        try t.expectApproxEqAbs(0.07446808510638298, deck.probabilityOfDrawingCard(.Seven), 0.000001);
        try t.expectApproxEqAbs(0.1276595744680851, deck.probabilityOfDrawingCard(.Twelve), 0.000001);
        try t.expectApproxEqAbs(0.0851063829787234, deck.probabilityOfDrawingCard(.Eight), 0.000001);

        try deck.removeCard(.Seven);
        try deck.removeCard(.Seven);
        try deck.removeCard(.Twelve);
        try deck.removeCard(.Twelve);

        try t.expectApproxEqAbs(0.05555555555555555, deck.probabilityOfDrawingCard(.Seven), 0.000001);
        try t.expectApproxEqAbs(0.1111111111111111, deck.probabilityOfDrawingCard(.Twelve), 0.000001);
        try t.expectApproxEqAbs(0.08888888888888889, deck.probabilityOfDrawingCard(.Eight), 0.000001);
    }
};

pub const DrawStrategy = union(enum) {
    MinPoints: u8,
    MaxCards: u8,
    MinPointsMaxCards: struct {
        min_points: u8,
        max_cards: u8,
    },
    Always7,
    Random,
    RandomMinCards: u8,
    ChanceOfFailureBelow: f32,

    pub const Context = struct {
        pub fn hash(_: Context, s: DrawStrategy) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&std.meta.activeTag(s)));
            switch (s) {
                .MinPoints => |v| hasher.update(std.mem.asBytes(&v)),
                .MaxCards => |v| hasher.update(std.mem.asBytes(&v)),
                .MinPointsMaxCards => |v| {
                    hasher.update(std.mem.asBytes(&v.min_points));
                    hasher.update(std.mem.asBytes(&v.max_cards));
                },
                .RandomMinCards => |v| hasher.update(std.mem.asBytes(&v)),
                .ChanceOfFailureBelow => |v| hasher.update(std.mem.asBytes(&@as(u32, @bitCast(v)))),
                .Always7, .Random => {},
            }
            return hasher.final();
        }
        pub fn eql(_: Context, a: DrawStrategy, b: DrawStrategy) bool {
            if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
            return switch (a) {
                .MinPoints => |va| va == b.MinPoints,
                .MaxCards => |va| va == b.MaxCards,
                .MinPointsMaxCards => |va| va.min_points == b.MinPointsMaxCards.min_points and va.max_cards == b.MinPointsMaxCards.max_cards,
                .RandomMinCards => |va| va == b.RandomMinCards,
                .ChanceOfFailureBelow => |va| @as(u32, @bitCast(va)) == @as(u32, @bitCast(b.ChanceOfFailureBelow)),
                .Always7, .Random => true,
            };
        }
    };
};

/// Points `hand` is worth if banked now.
pub fn scoreHand(hand: []const Card) u32 {
    var number_sum: u32 = 0;
    var modifier_sum: u32 = 0;
    var number_cards: u32 = 0;
    var multiply_by_2: bool = false;

    for (hand) |c| {
        switch (c) {
            .Zero, .One, .Two, .Three, .Four, .Five, .Six, .Seven, .Eight, .Nine, .Ten, .Eleven, .Twelve => {
                number_sum += @intFromEnum(c);
                number_cards += 1;
            },
            .PlusTwo, .PlusFour, .PlusSix, .PlusEight, .PlusTen => {
                const modifier = (@intFromEnum(c) - @intFromEnum(Card.PlusTwo) + 1) * 2;
                modifier_sum += modifier;
            },
            .TimesTwo => {
                multiply_by_2 = true;
            },
            .SecondChance => {},
            .Freeze, .FlipThree => {
                @panic("special cards Freeze and FlipThree are not supposed to be held by players");
            },
        }
    }

    // x2 doubles only the number cards, not the +N cards or the Flip 7 bonus.
    if (multiply_by_2) {
        number_sum *= 2;
    }

    var score = number_sum + modifier_sum;
    if (number_cards == 7) {
        score += 15;
    }

    return score;
}

pub const PlayerState = enum {
    InGame,
    Frozen,
    Eliminated,
    RoundEnded,
};

pub const Player = struct {
    prng: std.Random,
    strategy: DrawStrategy,
    hand: std.ArrayList(Card),
    score: u32 = 0,
    state: PlayerState = .InGame,

    pub fn init(allocator: std.mem.Allocator, prng: std.Random, strategy: DrawStrategy) !Player {
        return Player{ .prng = prng, .strategy = strategy, .hand = try std.ArrayList(Card).initCapacity(allocator, 20) };
    }

    pub fn deinit(self: *Player, allocator: std.mem.Allocator) void {
        self.hand.deinit(allocator);
    }

    pub fn handScore(self: *const Player) u32 {
        return scoreHand(self.hand.items);
    }

    pub fn numberCardCount(self: *const Player) u32 {
        var count: u32 = 0;
        for (self.hand.items) |c| {
            if (c.isNumber()) count += 1;
        }
        return count;
    }

    test "handScore" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        try player.hand.append(allocator, .Twelve);
        try t.expectEqual(12, player.handScore());

        try player.hand.append(allocator, .Eleven);
        try t.expectEqual(23, player.handScore());

        try player.hand.append(allocator, .Ten);
        try t.expectEqual(33, player.handScore());

        try player.hand.append(allocator, .Nine);
        try t.expectEqual(42, player.handScore());

        try player.hand.append(allocator, .Eight);
        try t.expectEqual(50, player.handScore());

        try player.hand.append(allocator, .Seven);
        try t.expectEqual(57, player.handScore());

        try player.hand.append(allocator, .Six);
        try t.expectEqual(63 + 15, player.handScore());

        try player.hand.append(allocator, .PlusTwo);
        try t.expectEqual(65 + 15, player.handScore());

        try player.hand.append(allocator, .PlusFour);
        try t.expectEqual(69 + 15, player.handScore());

        try player.hand.append(allocator, .PlusSix);
        try t.expectEqual(75 + 15, player.handScore());

        try player.hand.append(allocator, .PlusEight);
        try t.expectEqual(83 + 15, player.handScore());

        try player.hand.append(allocator, .PlusTen);
        try t.expectEqual(93 + 15, player.handScore());

        try player.hand.append(allocator, .TimesTwo);
        try t.expectEqual(63 * 2 + 30 + 15, player.handScore());
    }

    test "handScore TimesTwo does not double modifiers" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        var player = try Player.init(allocator, r.random(), DrawStrategy.Always7);
        defer player.deinit(allocator);

        try player.hand.appendSlice(allocator, &.{ .Five, .PlusFour, .TimesTwo });
        try t.expectEqual(5 * 2 + 4, player.handScore());
    }

    pub fn decideTakeCard(self: *Player, deck: *Deck) bool {
        // Every round starts with a dealt card, so an empty hand always draws.
        if (self.hand.items.len == 0) {
            return true;
        }

        switch (self.strategy) {
            .MinPoints => |min_points| {
                return self.handScore() < min_points;
            },
            .MaxCards => |max_cards| {
                return self.numberCardCount() < max_cards;
            },
            .MinPointsMaxCards => |data| {
                if (self.handScore() < data.min_points) {
                    return true;
                }
                return self.numberCardCount() < data.max_cards;
            },
            .Always7 => {
                return self.numberCardCount() < 7;
            },
            .Random => {
                return self.prng.boolean();
            },
            .RandomMinCards => |min_cards| {
                if (self.hand.items.len < min_cards) {
                    return true;
                }
                return self.prng.boolean();
            },
            .ChanceOfFailureBelow => |f| {
                // A held SecondChance absorbs the next duplicate.
                if (self.hasCard(.SecondChance)) {
                    return true;
                }
                var p_total: f64 = 0.0;
                for (self.hand.items) |c| {
                    if (!c.isNumber()) {
                        continue;
                    }
                    p_total += deck.probabilityOfDrawingCard(c);
                }
                return p_total < f;
            },
        }
    }

    test "decideTakeCard MinPoints = 30 takes cards until hand score 30 is reached" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        var player = try Player.init(allocator, prng, DrawStrategy{ .MinPoints = 30 });
        defer player.deinit(allocator);

        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.Twelve);
        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.Eleven);
        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.Ten);

        try t.expect(!player.decideTakeCard(&deck));
    }

    test "decideTakeCard MaxCards = 3 takes cards until hand contains 3 cards" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        var player = try Player.init(allocator, prng, DrawStrategy{ .MaxCards = 3 });
        defer player.deinit(allocator);

        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.Twelve);
        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.Eleven);
        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.Ten);

        try t.expect(!player.decideTakeCard(&deck));

        player.hand.clearRetainingCapacity();

        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.Zero);
        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.One);
        try t.expect(player.decideTakeCard(&deck));
        _ = player.takeCard(.Two);

        try t.expect(!player.decideTakeCard(&deck));
    }

    test "decideTakeCard ChancesOfFailureBelow10Percent" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        var player = try Player.init(allocator, prng, DrawStrategy{ .ChanceOfFailureBelow = 0.1 });
        defer player.deinit(allocator);

        try deck.removeCard(.Seven);
        try deck.removeCard(.Seven);
        try deck.removeCard(.Twelve);
        try deck.removeCard(.Twelve);

        try t.expect(player.decideTakeCard(&deck));
    }

    pub const TakeCardResult = enum {
        /// The card was added to the hand.
        Taken,
        /// The card was a duplicate; it and the SecondChance left the hand.
        SecondChanceUsed,
        /// The card was a duplicate and the player is eliminated.
        Busted,
        /// The card was the 7th unique number card. The round ends for everyone.
        Flip7,
    };

    /// Adds `card` to the hand. Does not bank points; the caller ends the
    /// round on `.Flip7`.
    pub fn takeCard(self: *Player, card: Card) TakeCardResult {
        std.debug.assert(card != .Freeze and card != .FlipThree);
        for (self.hand.items) |held| {
            if (held != card) continue;
            // SecondChance saves the player: discard it together with the duplicate.
            if (self.removeCard(.SecondChance)) {
                return .SecondChanceUsed;
            }
            self.hand.appendAssumeCapacity(card);
            self.state = .Eliminated;
            return .Busted;
        }

        self.hand.appendAssumeCapacity(card);
        if (card.isNumber() and self.numberCardCount() == 7) {
            return .Flip7;
        }
        return .Taken;
    }

    test "takeCard fails on duplicate card" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        try t.expectEqual(.Taken, player.takeCard(.Twelve));
        try t.expect(player.is_still_in_game());
        try t.expectEqual(.Busted, player.takeCard(.Twelve));
        try t.expect(!player.is_still_in_game());
    }

    test "takeCard with SecondChance survives duplicate" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        try t.expectEqual(.Taken, player.takeCard(.SecondChance));
        try t.expectEqual(.Taken, player.takeCard(.Twelve));
        // duplicate Twelve: SecondChance is consumed, player survives
        try t.expectEqual(.SecondChanceUsed, player.takeCard(.Twelve));
        try t.expect(player.is_still_in_game());
        try t.expect(!player.hasCard(.SecondChance));
        try t.expectEqual(1, player.hand.items.len); // only the first Twelve remains
        // now a second duplicate eliminates the player (no SecondChance left)
        try t.expectEqual(.Busted, player.takeCard(.Twelve));
        try t.expect(!player.is_still_in_game());
    }

    test "takeCard SecondChance itself cannot be duplicated" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        try t.expectEqual(.Taken, player.takeCard(.SecondChance));
        // Drawing a second SecondChance triggers the duplicate check; the existing
        // SecondChance in hand is consumed to save the player.
        try t.expectEqual(.SecondChanceUsed, player.takeCard(.SecondChance));
        try t.expect(player.is_still_in_game());
        try t.expect(!player.hasCard(.SecondChance));
    }

    test "takeCard reports Flip7 on the 7th number card without banking points" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        for ([_]Card{ .Zero, .One, .Two, .Three, .Four, .Five }) |c| {
            try t.expectEqual(.Taken, player.takeCard(c));
        }
        try t.expectEqual(.Flip7, player.takeCard(.Six));
        try t.expectEqual(0, player.score);
    }

    test "takeCard does not end round if 7th card is a not a number card" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        for ([_]Card{ .Zero, .One, .Two, .Three, .Four, .Five, .PlusTwo, .PlusFour, .PlusSix, .PlusEight, .PlusTen, .SecondChance }) |c| {
            try t.expectEqual(.Taken, player.takeCard(c));
        }
    }

    pub fn hasCard(self: *Player, card: Card) bool {
        for (self.hand.items) |c| {
            if (c == card) {
                return true;
            }
        }
        return false;
    }

    /// Removes the first occurrence of `card` from the player's hand.
    /// Returns true if the card was found and removed, false otherwise.
    pub fn removeCard(self: *Player, card: Card) bool {
        for (self.hand.items, 0..) |c, i| {
            if (c == card) {
                _ = self.hand.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn endRound(self: *Player) void {
        self.score += self.handScore();
        self.state = .RoundEnded;
    }

    pub fn freeze(self: *Player) void {
        self.score += self.handScore();
        self.state = .Frozen;
    }

    pub fn nextRound(self: *Player) void {
        self.hand.clearRetainingCapacity();
        self.state = .InGame;
    }

    pub fn is_still_in_game(self: *const Player) bool {
        return self.state == .InGame;
    }
};

pub const GameEvent = union(enum) {
    PlayerFrozen: struct {
        freezing_player: *Player,
        frozen_player: *Player,
        score: u32,
    },
    PlayerEliminated: struct {
        player: *Player,
    },
    PlayerEndRound: struct {
        player: *Player,
        score: u32,
    },
    PlayerWon: struct {
        player: *Player,
        score: u32,
    },
    DeckShuffle: struct {},
    DrawCard: struct {
        player: *Player,
        card: Card,
    },
    NewRoundStarted: struct {},
    FlipThreeStarted: struct {
        player: *Player,
        target: *Player,
    },
    FlipThreeEnded: struct {
        player: *Player,
        target: *Player,
    },
    /// `player` got 7 unique number cards. Everyone still in the round
    /// banks their points next (see `PlayerEndRound`).
    Flip7: struct {
        player: *Player,
        score: u32,
    },
    /// `player` drew `card` as a duplicate; it and their SecondChance are discarded.
    SecondChanceUsed: struct {
        player: *Player,
        card: Card,
    },
    /// `from` drew a SecondChance while holding one and passed it on. A
    /// `DrawCard` for `to` follows.
    SecondChancePassed: struct {
        from: *Player,
        to: *Player,
    },
    /// A drawn card was discarded without effect: a SecondChance nobody can
    /// take, or a Freeze/FlipThree whose holder left the round first.
    CardDiscarded: struct {
        player: *Player,
        card: Card,
    },
    /// The draw pile and discard pile are both empty; the round ends for
    /// everyone still in it.
    DeckExhausted: struct {},
    /// No player is left in the round. Followed by `PlayerWon` or `NewRoundStarted`.
    RoundEnded: struct {},
};

pub const GameResult = struct {
    winning_strategy: DrawStrategy,
    cards_played: u64,
};

pub const Settings = struct {
    logging_enabled: bool = false,
    events_enabled: bool = false,
};

pub const GameSimulation = struct {
    allocator: std.mem.Allocator,
    rng: *std.Random.DefaultPrng,
    prng: std.Random,
    settings: Settings,

    deck: Deck,
    players: []Player,
    player_selection_buffer: []*Player,
    current_player_index: u32,
    /// Who takes the first turn this round; moves one seat each round.
    round_starting_player_index: u32 = 0,
    cards_played: u32 = 0,

    events: std.ArrayList(GameEvent) = undefined,

    result_: ?GameResult = null,

    pub fn init(allocator: std.mem.Allocator, rng: *std.Random.DefaultPrng, players_init: []const DrawStrategy) !GameSimulation {
        const prng = rng.random();
        const players = try allocator.alloc(Player, players_init.len);
        for (players, 0..) |*player, i| {
            player.* = try Player.init(allocator, prng, players_init[i]);
        }
        return GameSimulation{
            .allocator = allocator,
            .rng = rng,
            .prng = prng,
            .settings = .{},
            .deck = try Deck.init(allocator, prng),
            .players = players,
            .player_selection_buffer = try allocator.alloc(*Player, players.len),
            .current_player_index = 0,
            .events = try std.ArrayList(GameEvent).initCapacity(allocator, 100),
        };
    }

    pub fn deinit(self: *GameSimulation) void {
        for (self.players) |*player| player.deinit(self.allocator);
        self.allocator.free(self.players);
        self.allocator.free(self.player_selection_buffer);
        self.events.deinit(self.allocator);
        self.deck.deinit(self.allocator);
    }

    pub fn step(self: *GameSimulation) !bool {
        self.log("Step: current_player_index = {}, cards_played = {}, deck_size = {}", .{ self.current_player_index, self.cards_played, self.deck.cards.items.len });

        if (self.result_ != null) {
            self.log("Game simulation is already finished", .{});
            return false;
        }

        if (!self.anyPlayerInGame()) {
            try self.addEvent(.{ .RoundEnded = .{} });
            // The game only ends at the end of a round.
            if (self.findWinner()) |player| {
                self.result_ = GameResult{
                    .winning_strategy = player.strategy,
                    .cards_played = self.cards_played,
                };
                try self.addEvent(.{ .PlayerWon = .{ .player = player, .score = player.score } });
                self.log("Game simulation finished: player with strategy {} won with score {}", .{ player.strategy, player.score });
                return false;
            }
            try self.startNewRound();
            return true;
        }

        if (self.deck.cards.items.len == 0) {
            try self.reshuffleOrEndRound();
            return true;
        }

        const starting_player_index = self.current_player_index;
        var player = &self.players[self.current_player_index];
        while (!player.is_still_in_game()) {
            self.current_player_index += 1;
            if (self.current_player_index >= self.players.len) {
                self.current_player_index = 0;
            }
            player = &self.players[self.current_player_index];

            if (self.current_player_index == starting_player_index) {
                // unreachable: anyPlayerInGame() was checked above
                self.log("All players are eliminated, starting a new round", .{});
                return true;
            }
        }

        self.current_player_index += 1;
        if (self.current_player_index >= self.players.len) {
            self.current_player_index = 0;
        }

        if (!player.decideTakeCard(&self.deck)) {
            player.endRound();
            try self.addEvent(.{ .PlayerEndRound = .{ .player = player, .score = player.score } });
            return true;
        }

        // The draw pile is not empty, checked above.
        const card = (try self.drawCard()).?;
        switch (card) {
            .Freeze => {
                try self.addEvent(.{ .DrawCard = .{ .player = player, .card = card } });
                try self.handleFreeze(player);
            },
            .FlipThree => {
                try self.addEvent(.{ .DrawCard = .{ .player = player, .card = card } });
                try self.handleFlipThree(player);
            },
            .SecondChance => try self.handleSecondChance(player),
            else => try self.giveCard(player, card),
        }

        return true;
    }

    pub fn result(self: *GameSimulation) GameResult {
        return self.result_.?;
    }

    fn anyPlayerInGame(self: *const GameSimulation) bool {
        for (self.players) |*p| {
            if (p.is_still_in_game()) return true;
        }
        return false;
    }

    /// The player with the highest score, once someone has 200 or more.
    /// A tie for the highest score plays another round.
    fn findWinner(self: *GameSimulation) ?*Player {
        var best: ?*Player = null;
        var tied = false;
        for (self.players) |*p| {
            if (best == null or p.score > best.?.score) {
                best = p;
                tied = false;
            } else if (p.score == best.?.score) {
                tied = true;
            }
        }
        const winner = best orelse return null;
        if (winner.score < 200 or tied) return null;
        return winner;
    }

    fn startNewRound(self: *GameSimulation) error{OutOfMemory}!void {
        for (self.players) |*p| {
            try self.deck.discarded.appendSlice(self.allocator, p.hand.items);
            p.nextRound();
        }
        self.round_starting_player_index = (self.round_starting_player_index + 1) % @as(u32, @intCast(self.players.len));
        self.current_player_index = self.round_starting_player_index;
        try self.addEvent(.{ .NewRoundStarted = .{} });
    }

    /// Draws the top card, shuffling the discard pile in when the draw pile
    /// is empty. Returns null when both are empty; the round has ended then.
    fn drawCard(self: *GameSimulation) error{OutOfMemory}!?Card {
        if (self.deck.cards.items.len == 0) {
            try self.reshuffleOrEndRound();
            if (self.deck.cards.items.len == 0) return null;
        }
        self.cards_played += 1;
        return self.deck.cards.pop().?;
    }

    fn reshuffleOrEndRound(self: *GameSimulation) error{OutOfMemory}!void {
        if (self.deck.discarded.items.len == 0) {
            // Every card is in someone's hand (only possible with many players).
            try self.addEvent(.{ .DeckExhausted = .{} });
            try self.endRoundForAll();
            return;
        }
        try self.deck.reshuffleDiscarded(self.allocator);
        try self.addEvent(.{ .DeckShuffle = .{} });
    }

    /// Everyone still in the round banks their points.
    fn endRoundForAll(self: *GameSimulation) error{OutOfMemory}!void {
        for (self.players) |*p| {
            if (!p.is_still_in_game()) continue;
            p.endRound();
            try self.addEvent(.{ .PlayerEndRound = .{ .player = p, .score = p.score } });
        }
    }

    /// Puts a number, modifier or SecondChance card into `player`'s hand and
    /// resolves the outcome.
    fn giveCard(self: *GameSimulation, player: *Player, card: Card) error{OutOfMemory}!void {
        const outcome = player.takeCard(card);
        try self.addEvent(.{ .DrawCard = .{ .player = player, .card = card } });
        switch (outcome) {
            .Taken => {},
            .SecondChanceUsed => {
                try self.deck.discard(self.allocator, .SecondChance);
                try self.deck.discard(self.allocator, card);
                try self.addEvent(.{ .SecondChanceUsed = .{ .player = player, .card = card } });
            },
            .Busted => try self.addEvent(.{ .PlayerEliminated = .{ .player = player } }),
            .Flip7 => {
                player.endRound();
                try self.addEvent(.{ .Flip7 = .{ .player = player, .score = player.score } });
                try self.endRoundForAll();
            },
        }
    }

    fn handleSecondChance(self: *GameSimulation, player: *Player) error{OutOfMemory}!void {
        if (!player.hasCard(.SecondChance)) {
            try self.giveCard(player, .SecondChance);
            return;
        }

        // Player already has a SecondChance: give it to a random other eligible player.
        var available_players = std.ArrayList(*Player).initBuffer(self.player_selection_buffer);
        for (self.players) |*other_player| {
            if (other_player == player) continue;
            if (!other_player.is_still_in_game()) continue;
            if (other_player.hasCard(.SecondChance)) continue;
            available_players.appendAssumeCapacity(other_player);
        }

        if (available_players.items.len == 0) {
            try self.deck.discard(self.allocator, .SecondChance);
            try self.addEvent(.{ .CardDiscarded = .{ .player = player, .card = .SecondChance } });
            return;
        }

        const random_index = self.prng.intRangeLessThan(u32, 0, @intCast(available_players.items.len));
        const recipient = available_players.items[random_index];
        try self.addEvent(.{ .SecondChancePassed = .{ .from = player, .to = recipient } });
        try self.giveCard(recipient, .SecondChance);
    }

    test "handleSecondChance simple case" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();

        const player = &tf.simulation.players[0];
        try tf.simulation.handleSecondChance(player);

        try t.expectEqual(true, player.hand.items.len == 1);
        try t.expectEqual(true, player.hand.items[0] == .SecondChance);
    }

    test "handleSecondChance player already has a second chance on hand" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();

        const player = &tf.simulation.players[0];
        try player.hand.append(tf.allocator, .SecondChance);
        try tf.simulation.handleSecondChance(player);

        const other_player = &tf.simulation.players[1];
        try t.expectEqual(true, player.hand.items.len == 1);
        try t.expectEqual(true, player.hand.items[0] == .SecondChance);
        try t.expectEqual(true, other_player.hand.items.len == 1);
        try t.expectEqual(true, other_player.hand.items[0] == .SecondChance);
    }

    fn handleFreeze(self: *GameSimulation, player: *Player) error{OutOfMemory}!void {
        try self.deck.discard(self.allocator, .Freeze);
        if (!player.is_still_in_game()) {
            // The holder left the round (bust, Flip 7) before resolving it.
            try self.addEvent(.{ .CardDiscarded = .{ .player = player, .card = .Freeze } });
            return;
        }

        // TODO make this a configurable strategy, doing it randomly for now
        var available_players = std.ArrayList(*Player).initBuffer(self.player_selection_buffer);
        for (self.players) |*p| {
            if (p == player) {
                continue;
            }
            if (!p.is_still_in_game()) {
                continue;
            }
            available_players.appendAssumeCapacity(p);
        }

        if (available_players.items.len == 0) {
            player.freeze();
            try self.addEvent(.{ .PlayerFrozen = .{ .freezing_player = player, .frozen_player = player, .score = player.score } });
            return;
        }

        const random_index = self.prng.intRangeLessThan(u32, 0, @intCast(available_players.items.len));
        var freeze_target = available_players.items[random_index];
        std.debug.assert(freeze_target != player);
        freeze_target.freeze();
        try self.addEvent(.{ .PlayerFrozen = .{ .freezing_player = player, .frozen_player = freeze_target, .score = freeze_target.score } });
    }

    test "handleFreeze simple case" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();

        const freezing_player = &tf.simulation.players[0];
        try tf.simulation.handleFreeze(freezing_player);

        const frozen_player = &tf.simulation.players[1];
        try t.expectEqual(true, frozen_player.state == .Frozen);
    }

    test "handleFreeze other player is already frozen" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();
        const frozen_player = &tf.simulation.players[1];
        frozen_player.freeze();

        const freezing_player = &tf.simulation.players[0];
        try tf.simulation.handleFreeze(freezing_player);

        try t.expectEqual(true, frozen_player.state == .Frozen);
        try t.expectEqual(true, freezing_player.state == .Frozen);
    }

    fn drawThreeCards(self: *GameSimulation, player: *Player, target: *Player) error{OutOfMemory}!void {
        try self.addEvent(.{ .FlipThreeStarted = .{ .player = player, .target = target } });

        // Freeze and FlipThree are resolved after the three cards. Their
        // handlers discard them if the target left the round by then.
        var freeze_count: u8 = 0;
        var flip_three_count: u8 = 0;
        for (0..3) |_| {
            if (!target.is_still_in_game()) break;
            const drawn = (try self.drawCard()) orelse break;
            switch (drawn) {
                .Freeze, .FlipThree => {
                    try self.addEvent(.{ .DrawCard = .{ .player = target, .card = drawn } });
                    if (drawn == .Freeze) freeze_count += 1 else flip_three_count += 1;
                },
                .SecondChance => try self.handleSecondChance(target),
                else => try self.giveCard(target, drawn),
            }
        }

        for (0..flip_three_count) |_| {
            try self.handleFlipThree(target);
        }
        for (0..freeze_count) |_| {
            try self.handleFreeze(target);
        }

        try self.addEvent(.{ .FlipThreeEnded = .{ .player = player, .target = target } });
    }

    fn handleFlipThree(self: *GameSimulation, player: *Player) error{OutOfMemory}!void {
        if (!player.is_still_in_game()) {
            // The holder left the round (bust, Flip 7) before resolving it.
            try self.deck.discard(self.allocator, .FlipThree);
            try self.addEvent(.{ .CardDiscarded = .{ .player = player, .card = .FlipThree } });
            return;
        }

        // TODO make this a configurable strategy, doing it randomly for now
        var available_players = std.ArrayList(*Player).initBuffer(self.player_selection_buffer);
        for (self.players) |*p| {
            if (p == player) {
                continue;
            }
            if (!p.is_still_in_game()) {
                continue;
            }
            available_players.appendAssumeCapacity(p);
        }

        // No targets: the player who drew FlipThree must draw 3 cards themselves.
        const flip_three_target = if (available_players.items.len == 0)
            player
        else
            available_players.items[self.prng.intRangeLessThan(u32, 0, @intCast(available_players.items.len))];
        try self.drawThreeCards(player, flip_three_target);
        // Discarded only now so a reshuffle during the draws can't bring it back.
        try self.deck.discard(self.allocator, .FlipThree);
    }

    test "FlipThree deals every card only to the target" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{ .Six, .Freeze, .Five });
        defer tf.deinit();
        tf.simulation.settings.events_enabled = true;
        const drawing_player = &tf.simulation.players[0];
        const target = &tf.simulation.players[1];

        try tf.simulation.drawThreeCards(drawing_player, target);

        var dealt: std.ArrayList(Card) = .empty;
        defer dealt.deinit(t.allocator);
        for (tf.simulation.events.items) |event| switch (event) {
            .DrawCard => |d| {
                try t.expect(d.player == target);
                try dealt.append(t.allocator, d.card);
            },
            else => {},
        };
        try t.expectEqualSlices(Card, &.{ .Five, .Freeze, .Six }, dealt.items);
    }

    test "handleFlipThree simple case" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{ .One, .Two, .Three });
        defer tf.deinit();

        const drawing_player = &tf.simulation.players[0];
        try tf.simulation.handleFlipThree(drawing_player);

        const other_player = &tf.simulation.players[1];
        try t.expectEqual(true, other_player.is_still_in_game());
        try t.expectEqual(3, other_player.hand.items.len);
        try t.expectEqual(.Three, other_player.hand.items[0]);
        try t.expectEqual(.Two, other_player.hand.items[1]);
        try t.expectEqual(.One, other_player.hand.items[2]);
    }

    test "handleFlipThree flip three as last drawn card" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{ .One, .Two, .Three, .FlipThree, .Four, .Five });
        defer tf.deinit();

        const drawing_player = &tf.simulation.players[0];
        try tf.simulation.handleFlipThree(drawing_player);

        const other_player = &tf.simulation.players[1];
        try t.expectEqual(true, other_player.is_still_in_game());
        try t.expectEqual(2, other_player.hand.items.len);
        try t.expectEqual(.Five, other_player.hand.items[0]);
        try t.expectEqual(.Four, other_player.hand.items[1]);

        try t.expectEqual(true, drawing_player.is_still_in_game());
        try t.expectEqual(3, drawing_player.hand.items.len);
        try t.expectEqual(.Three, drawing_player.hand.items[0]);
        try t.expectEqual(.Two, drawing_player.hand.items[1]);
        try t.expectEqual(.One, drawing_player.hand.items[2]);
    }

    test "handleFlipThree flip three as first and second drawn card" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{
            .One,
            .Two,
            .Three,
            .Four,
            .Five,
            .Six,
            .Seven,
            .FlipThree,
            .FlipThree,
        });
        defer tf.deinit();

        const drawing_player = &tf.simulation.players[0];
        try tf.simulation.handleFlipThree(drawing_player);

        const other_player = &tf.simulation.players[1];
        try t.expectEqual(true, other_player.is_still_in_game());
        try t.expectEqual(1, other_player.hand.items.len);
        try t.expectEqual(.Seven, other_player.hand.items[0]);

        try t.expectEqual(true, drawing_player.is_still_in_game());
        try t.expectEqual(6, drawing_player.hand.items.len);
        try t.expectEqual(.Six, drawing_player.hand.items[0]);
        try t.expectEqual(.Five, drawing_player.hand.items[1]);
        try t.expectEqual(.Four, drawing_player.hand.items[2]);
        try t.expectEqual(.Three, drawing_player.hand.items[3]);
        try t.expectEqual(.Two, drawing_player.hand.items[4]);
        try t.expectEqual(.One, drawing_player.hand.items[5]);
    }

    test "handleFlipThree freeze as last card" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{
            .Freeze,
            .One,
            .Two,
        });
        defer tf.deinit();

        const drawing_player = &tf.simulation.players[0];
        try tf.simulation.handleFlipThree(drawing_player);

        const other_player = &tf.simulation.players[1];
        try t.expectEqual(true, other_player.is_still_in_game());
        try t.expectEqual(2, other_player.hand.items.len);
        try t.expectEqual(.Two, other_player.hand.items[0]);
        try t.expectEqual(.One, other_player.hand.items[1]);

        try t.expectEqual(false, drawing_player.is_still_in_game());
    }

    test "handleFlipThree freeze as first and second card" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{
            .One,
            .Freeze,
            .Freeze,
        });
        defer tf.deinit();

        const drawing_player = &tf.simulation.players[0];
        try tf.simulation.handleFlipThree(drawing_player);

        const other_player = &tf.simulation.players[1];
        try t.expectEqual(false, other_player.is_still_in_game());
        try t.expectEqual(1, other_player.hand.items.len);
        try t.expectEqual(.One, other_player.hand.items[0]);

        try t.expectEqual(false, drawing_player.is_still_in_game());
    }

    test "Flip 7 ends the round for everyone and banks the points once" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{.Six});
        defer tf.deinit();
        const sim = &tf.simulation;
        const flipper = &sim.players[0];
        const other = &sim.players[1];
        flipper.strategy = .Always7;
        try flipper.hand.appendSlice(t.allocator, &.{ .Zero, .One, .Two, .Three, .Four, .Five });
        try other.hand.append(t.allocator, .Ten);

        try t.expect(try sim.step());
        try t.expectEqual(PlayerState.RoundEnded, flipper.state);
        try t.expectEqual(PlayerState.RoundEnded, other.state);
        try t.expectEqual(21 + 15, flipper.score);
        try t.expectEqual(10, other.score);

        // Next step starts a new round without banking anything again.
        try t.expect(try sim.step());
        try t.expectEqual(21 + 15, flipper.score);
        try t.expectEqual(10, other.score);
        try t.expectEqual(PlayerState.InGame, flipper.state);
        try t.expectEqual(0, flipper.hand.items.len);
    }

    test "game ends only at the end of a round, won by the highest score" {
        var tf = try TestFixture.init(t.allocator, 3, &[_]Card{});
        defer tf.deinit();
        const sim = &tf.simulation;
        sim.settings.events_enabled = true;
        sim.players[0].score = 205;
        sim.players[0].state = .RoundEnded;
        sim.players[1].score = 150;
        sim.players[2].score = 230;
        sim.players[2].state = .Frozen;

        // Player 1 is still in the round.
        try t.expect(try sim.step());
        try t.expectEqual(null, sim.result_);

        sim.players[1].state = .Eliminated;
        try t.expect(!try sim.step());
        const won = sim.events.items[sim.events.items.len - 1].PlayerWon;
        try t.expectEqual(&sim.players[2], won.player);
    }

    test "a tie for the highest score plays another round" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();
        const sim = &tf.simulation;
        for (sim.players) |*p| {
            p.score = 210;
            p.state = .RoundEnded;
        }
        try t.expect(try sim.step());
        try t.expectEqual(null, sim.result_);
        try t.expect(sim.players[0].is_still_in_game());
    }

    test "the starting player moves one seat each round" {
        var tf = try TestFixture.init(t.allocator, 3, &[_]Card{});
        defer tf.deinit();
        const sim = &tf.simulation;
        for (sim.players) |*p| p.state = .RoundEnded;
        try t.expect(try sim.step());
        try t.expectEqual(1, sim.current_player_index);
        for (sim.players) |*p| p.state = .RoundEnded;
        try t.expect(try sim.step());
        try t.expectEqual(2, sim.current_player_index);
    }

    test "reshuffling uses the discard pile, not cards held by players" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();
        const sim = &tf.simulation;
        sim.deck.cards.clearRetainingCapacity();
        sim.deck.discarded.clearRetainingCapacity();
        try sim.deck.discarded.append(t.allocator, .Three);
        try sim.players[0].hand.append(t.allocator, .Twelve);

        try t.expect(try sim.step());
        try t.expectEqualSlices(Card, &.{.Three}, sim.deck.cards.items);
        try t.expectEqual(0, sim.deck.discarded.items.len);
    }

    test "a busted player does not resolve a pending Freeze" {
        // The FlipThree targets the drawer (nobody else is in the round) and
        // draws FlipThree, Freeze, One. The nested FlipThree draws a duplicate Five.
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{ .Five, .One, .Freeze, .FlipThree });
        defer tf.deinit();
        const sim = &tf.simulation;
        const player = &sim.players[0];
        sim.players[1].state = .RoundEnded;
        try player.hand.append(t.allocator, .Five);

        try sim.handleFlipThree(player);
        try t.expectEqual(PlayerState.Eliminated, player.state);
        try t.expectEqual(0, player.score);
    }

    test "a passed SecondChance is reported for its recipient" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();
        const sim = &tf.simulation;
        sim.settings.events_enabled = true;
        const from = &sim.players[0];
        const to = &sim.players[1];
        try from.hand.append(t.allocator, .SecondChance);

        try sim.handleSecondChance(from);
        try t.expectEqual(2, sim.events.items.len);
        const passed = sim.events.items[0].SecondChancePassed;
        try t.expectEqual(from, passed.from);
        try t.expectEqual(to, passed.to);
        try t.expectEqual(to, sim.events.items[1].DrawCard.player);
    }

    test "a used SecondChance and the duplicate go to the discard pile" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();
        const sim = &tf.simulation;
        const player = &sim.players[0];
        try player.hand.appendSlice(t.allocator, &.{ .Seven, .SecondChance });
        try sim.giveCard(player, .Seven);
        try t.expectEqualSlices(Card, &.{.Seven}, player.hand.items);
        try t.expectEqualSlices(Card, &.{ .SecondChance, .Seven }, sim.deck.discarded.items);
    }

    test "Always7 and MinPointsMaxCards count only number cards" {
        var tf = try TestFixture.init(t.allocator, 1, &[_]Card{});
        defer tf.deinit();
        const player = &tf.simulation.players[0];
        try player.hand.appendSlice(t.allocator, &.{ .One, .Two, .Three, .Four, .Five, .Six, .PlusTwo });
        player.strategy = .Always7;
        try t.expect(player.decideTakeCard(&tf.simulation.deck));
        player.strategy = .{ .MinPointsMaxCards = .{ .min_points = 0, .max_cards = 7 } };
        try t.expect(player.decideTakeCard(&tf.simulation.deck));
    }

    fn expectAllCardsAccountedFor(sim: *GameSimulation) !void {
        var total = sim.deck.cards.items.len + sim.deck.discarded.items.len;
        for (sim.players) |p| total += p.hand.items.len;
        try t.expectEqual(94, total);
    }

    test "whole games keep all 94 cards and terminate" {
        // Greedy players reach Flip 7, and 22 of them run the deck dry (DeckExhausted).
        for ([_]u32{ 2, 4, 22 }) |num_players| {
            var tf = try TestFixture.init(t.allocator, num_players, &[_]Card{});
            defer tf.deinit();
            const sim = &tf.simulation;
            sim.settings.events_enabled = true;
            for (sim.players) |*p| p.strategy = .Always7;
            var steps: u32 = 0;
            while (try sim.step()) : (steps += 1) {
                try expectAllCardsAccountedFor(sim);
                for (sim.players) |p| try t.expect(p.numberCardCount() <= 7);
                try t.expect(steps < 100_000);
            }
            var best: u32 = 0;
            for (sim.players) |p| best = @max(best, p.score);
            try t.expect(best >= 200);

            var exhausted = false;
            for (sim.events.items) |e| exhausted = exhausted or e == .DeckExhausted;
            try t.expectEqual(num_players == 22, exhausted);
        }
    }

    const SavedPlayer = struct {
        hand: []const Card,
        score: u32,
        state: PlayerState,
        strategy: DrawStrategy,
    };
    const Saved = struct {
        deck: []const Card,
        discarded: []const Card = &.{},
        players: []const SavedPlayer,
        current_player_index: u32 = 0,
        round_starting_player_index: u32 = 0,
        cards_played: u32 = 0,
        /// Exact generator state from `save`, see `encodePrngState`. Takes precedence over `seed`.
        prng_state: ?[]const u8 = null,
        /// Seeds the generator, for hand-written scenarios. Note that JavaScript rounds integers above 2^53.
        seed: ?u64 = null,
    };

    /// The four Xoshiro256 words as 64 hex digits. JSON numbers can't hold
    /// them reliably: JavaScript rounds integers above 2^53.
    fn encodePrngState(rng: *const std.Random.DefaultPrng) [64]u8 {
        var out: [64]u8 = undefined;
        for (rng.s, 0..) |word, i| {
            _ = std.fmt.bufPrint(out[i * 16 ..][0..16], "{x:0>16}", .{word}) catch unreachable;
        }
        return out;
    }

    fn decodePrngState(text: []const u8) ![4]u64 {
        if (text.len != 64) return error.InvalidPrngState;
        var words: [4]u64 = undefined;
        for (&words, 0..) |*word, i| {
            word.* = std.fmt.parseInt(u64, text[i * 16 ..][0..16], 16) catch return error.InvalidPrngState;
        }
        // An all-zero state makes Xoshiro256 return zeros forever.
        if (std.mem.allEqual(u64, &words, 0)) return error.InvalidPrngState;
        return words;
    }

    /// Serializes the simulation state, including the generator state, to
    /// JSON. Loading it continues the game exactly as this one would.
    pub fn save(self: *GameSimulation, allocator: std.mem.Allocator) ![]const u8 {
        const players = try allocator.alloc(SavedPlayer, self.players.len);
        defer allocator.free(players);
        for (players, self.players) |*saved, *player| {
            saved.* = .{
                .hand = player.hand.items,
                .score = player.score,
                .state = player.state,
                .strategy = player.strategy,
            };
        }
        const prng_state = encodePrngState(self.rng);
        const saved = Saved{
            .deck = self.deck.cards.items,
            .discarded = self.deck.discarded.items,
            .players = players,
            .current_player_index = self.current_player_index,
            .round_starting_player_index = self.round_starting_player_index,
            .cards_played = self.cards_played,
            .prng_state = &prng_state,
        };
        return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(saved, .{ .emit_null_optional_fields = false })});
    }

    test "save" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();

        const s = try tf.simulation.save(tf.allocator);
        defer tf.allocator.free(s);
        try t.expectEqualStrings(
            \\{"deck":["Seven","Twelve","FlipThree","Seven","Eleven","Eight","Nine","Eight","Six","One","Five","FlipThree","Eight","Six","Twelve","Freeze","SecondChance","Eight","PlusTwo","Three","Nine","Six","Seven","Nine","Six","Ten","Eleven","Ten","SecondChance","Freeze","Twelve","Three","Eight","Ten","Zero","Twelve","Twelve","Nine","Eleven","Twelve","Twelve","Eleven","Nine","Nine","Four","FlipThree","Three","Eleven","Five","Freeze","Ten","Twelve","Eleven","Eleven","Ten","PlusFour","Two","Two","SecondChance","Four","Nine","Four","PlusEight","Ten","Ten","Five","Eight","Five","Seven","Twelve","Nine","Eleven","PlusTen","Five","Twelve","Six","Eleven","Eight","TimesTwo","Six","Twelve","Eight","Nine","Twelve","Seven","Four","Ten","Eleven","Eleven","Ten","Seven","PlusSix","Seven","Ten"],"discarded":[],"players":[{"hand":[],"score":0,"state":"InGame","strategy":{"Random":{}}},{"hand":[],"score":0,"state":"InGame","strategy":{"Random":{}}}],"current_player_index":0,"round_starting_player_index":0,"cards_played":0,"prng_state":"cb266253fc824a6f7b5c030fb46a88ff6f9d8afede5704d0b5c55d5a9cb43353"}
        , s);
    }

    /// Replaces the simulation state with a state produced by `save`. On
    /// error the simulation is left unchanged. Pending events are dropped.
    pub fn load(self: *GameSimulation, input: []const u8) !void {
        const parsed = try std.json.parseFromSlice(Saved, self.allocator, input, .{});
        defer parsed.deinit();
        const saved = parsed.value;
        if (saved.players.len == 0) return error.NoPlayers;
        if (saved.current_player_index >= saved.players.len) return error.InvalidCurrentPlayerIndex;
        if (saved.round_starting_player_index >= saved.players.len) return error.InvalidCurrentPlayerIndex;
        for (saved.players) |saved_player| {
            // Freeze and FlipThree are resolved on the spot, never held.
            for (saved_player.hand) |card| {
                if (card == .Freeze or card == .FlipThree) return error.InvalidHand;
            }
        }
        const prng_state: ?[4]u64 = if (saved.prng_state) |text| try decodePrngState(text) else null;

        // Build everything that can fail before touching `self`.
        const players = try self.allocator.alloc(Player, saved.players.len);
        var initialized: usize = 0;
        errdefer {
            for (players[0..initialized]) |*player| player.deinit(self.allocator);
            self.allocator.free(players);
        }
        for (players, saved.players) |*player, saved_player| {
            player.* = try Player.init(self.allocator, self.prng, saved_player.strategy);
            initialized += 1;
            // takeCard appends without allocating, keep room for one more card.
            try player.hand.ensureTotalCapacity(self.allocator, saved_player.hand.len + 1);
            player.hand.appendSliceAssumeCapacity(saved_player.hand);
            player.score = saved_player.score;
            player.state = saved_player.state;
        }
        const player_selection_buffer = try self.allocator.alloc(*Player, players.len);
        errdefer self.allocator.free(player_selection_buffer);
        try self.deck.cards.ensureTotalCapacity(self.allocator, saved.deck.len);
        try self.deck.discarded.ensureTotalCapacity(self.allocator, saved.discarded.len);

        // Nothing below can fail.
        for (self.players) |*player| player.deinit(self.allocator);
        self.allocator.free(self.players);
        self.allocator.free(self.player_selection_buffer);
        self.players = players;
        self.player_selection_buffer = player_selection_buffer;

        self.deck.cards.clearRetainingCapacity();
        self.deck.cards.appendSliceAssumeCapacity(saved.deck);
        self.deck.discarded.clearRetainingCapacity();
        self.deck.discarded.appendSliceAssumeCapacity(saved.discarded);

        self.current_player_index = saved.current_player_index;
        self.round_starting_player_index = saved.round_starting_player_index;
        self.cards_played = saved.cards_played;
        self.result_ = null;
        self.events.clearRetainingCapacity();

        // Deck and players hold interfaces to `rng`, so update it in place.
        if (prng_state) |state| {
            self.rng.s = state;
        } else if (saved.seed) |seed| {
            self.rng.* = .init(seed);
        }
    }

    test "save and load round-trip" {
        var original = try TestFixture.init(t.allocator, 3, &[_]Card{ .Freeze, .Seven });
        defer original.deinit();
        original.simulation.players[1].score = 42;
        original.simulation.players[1].state = .Frozen;
        try original.simulation.players[2].hand.append(t.allocator, .PlusFour);
        original.simulation.players[0].strategy = .{ .MinPoints = 25 };
        original.simulation.current_player_index = 2;
        original.simulation.cards_played = 7;

        const saved = try original.simulation.save(t.allocator);
        defer t.allocator.free(saved);

        // Different player count: load has to replace the players.
        var loaded = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer loaded.deinit();
        try loaded.simulation.load(saved);

        const a = &original.simulation;
        const b = &loaded.simulation;
        try t.expectEqualSlices(Card, a.deck.cards.items, b.deck.cards.items);
        try t.expectEqual(@as(usize, 3), b.players.len);
        try t.expectEqual(@as(usize, 3), b.player_selection_buffer.len);
        for (a.players, b.players) |pa, pb| {
            try t.expectEqualSlices(Card, pa.hand.items, pb.hand.items);
            try t.expectEqual(pa.score, pb.score);
            try t.expectEqual(pa.state, pb.state);
            try t.expectEqual(pa.strategy, pb.strategy);
        }
        try t.expectEqual(@as(u32, 2), b.current_player_index);
        try t.expectEqual(@as(u32, 7), b.cards_played);
    }

    test "a loaded game continues exactly like the saved one" {
        var original = try TestFixture.init(t.allocator, 3, &[_]Card{});
        defer original.deinit();
        for (0..10) |_| _ = try original.simulation.step();

        const saved = try original.simulation.save(t.allocator);
        defer t.allocator.free(saved);

        var copy = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer copy.deinit();
        copy.r = .init(12345); // must not matter, the state comes from the file
        try copy.simulation.load(saved);

        for (0..40) |_| {
            const a = try original.simulation.step();
            const b = try copy.simulation.step();
            try t.expectEqual(a, b);
        }
        const end_a = try original.simulation.save(t.allocator);
        defer t.allocator.free(end_a);
        const end_b = try copy.simulation.save(t.allocator);
        defer t.allocator.free(end_b);
        try t.expectEqualStrings(end_a, end_b);
    }

    test "load seeds the generator from seed" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();
        try tf.simulation.load(
            \\{"deck":[],"players":[{"hand":[],"score":0,"state":"InGame","strategy":{"Random":{}}}],"seed":42}
        );
        try t.expectEqual(std.Random.DefaultPrng.init(42).s, tf.r.s);
    }

    test "load rejects a malformed prng_state" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();
        const before = tf.r.s;
        try t.expectError(error.InvalidPrngState, tf.simulation.load(
            \\{"deck":[],"players":[{"hand":[],"score":0,"state":"InGame","strategy":{"Random":{}}}],"prng_state":"1234"}
        ));
        try t.expectError(error.InvalidPrngState, tf.simulation.load(
            \\{"deck":[],"players":[{"hand":[],"score":0,"state":"InGame","strategy":{"Random":{}}}],"prng_state":"0000000000000000000000000000000000000000000000000000000000000000"}
        ));
        try t.expectEqual(before, tf.r.s);
        try t.expectEqual(@as(usize, 2), tf.simulation.players.len);
    }

    test "seeded games play out identically on every target" {
        // Golden value: the same on 64-bit desktop and wasm32. If this changes,
        // either the rules changed or a draw depends on the target again
        // (e.g. a usize in a random call).
        var tf = try TestFixture.init(t.allocator, 4, &[_]Card{});
        defer tf.deinit();
        for (0..40) |_| _ = try tf.simulation.step();
        const saved = try tf.simulation.save(t.allocator);
        defer t.allocator.free(saved);
        try t.expectEqual(@as(u64, 2039900527274424167), std.hash.Wyhash.hash(0, saved));
    }

    test "load requires state and strategy for every player" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{});
        defer tf.deinit();
        try t.expectError(error.MissingField, tf.simulation.load(
            \\{"deck":[],"players":[{"hand":[],"score":0,"strategy":{"Random":{}}}]}
        ));
        try t.expectError(error.MissingField, tf.simulation.load(
            \\{"deck":[],"players":[{"hand":[],"score":0,"state":"InGame"}]}
        ));
        try t.expectEqual(@as(usize, 2), tf.simulation.players.len);
    }

    test "load rejects invalid input and keeps the state" {
        var tf = try TestFixture.init(t.allocator, 2, &[_]Card{.Seven});
        defer tf.deinit();
        const deck_len = tf.simulation.deck.cards.items.len;

        try t.expectError(error.NoPlayers, tf.simulation.load(
            \\{"deck":[],"players":[]}
        ));
        try t.expectError(error.InvalidCurrentPlayerIndex, tf.simulation.load(
            \\{"deck":[],"players":[{"hand":[],"score":0,"state":"InGame","strategy":{"Random":{}}}],"current_player_index":1}
        ));
        try t.expect(std.meta.isError(tf.simulation.load("not json")));

        try t.expectEqual(deck_len, tf.simulation.deck.cards.items.len);
        try t.expectEqual(@as(usize, 2), tf.simulation.players.len);
    }

    fn addEvent(self: *GameSimulation, event: GameEvent) !void {
        if (!self.settings.events_enabled) {
            return;
        }
        try self.events.append(self.allocator, event);
    }

    fn log(self: *GameSimulation, comptime fmt: []const u8, args: anytype) void {
        if (!self.settings.logging_enabled) {
            return;
        }
        const is_wasm = @import("builtin").target.cpu.arch == .wasm32;
        if (!is_wasm) {
            std.debug.print(fmt ++ "\n", args);
        }
    }
};

const TestFixture = struct {
    allocator: std.mem.Allocator = undefined,
    r: std.Random.Xoshiro256 = undefined,
    simulation: GameSimulation = undefined,

    pub fn init(
        allocator: std.mem.Allocator,
        num_players: u32,
        top_cards: []const Card,
    ) !*TestFixture {
        var result_ = try allocator.create(TestFixture);
        result_.allocator = allocator;

        result_.r = std.Random.DefaultPrng.init(0);

        const draw_strategies = try allocator.alloc(DrawStrategy, num_players);
        defer allocator.free(draw_strategies);
        for (draw_strategies) |*strat| {
            strat.* = .Random;
        }

        result_.simulation = try GameSimulation.init(allocator, &result_.r, draw_strategies);

        for (top_cards) |card| {
            try result_.simulation.deck.cards.append(allocator, card);
        }

        return result_;
    }

    pub fn deinit(self: *TestFixture) void {
        self.simulation.deinit();
        self.allocator.destroy(self);
    }
};
