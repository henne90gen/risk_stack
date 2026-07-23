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
        std.Random.shuffle(self.prng, Card, self.cards.items);
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

pub const Player = struct {
    prng: std.Random,
    strategy: DrawStrategy,
    hand: std.ArrayList(Card),
    score: u32 = 0,
    is_still_in_game: bool = true,

    pub fn init(allocator: std.mem.Allocator, prng: std.Random, strategy: DrawStrategy) !Player {
        return Player{ .prng = prng, .strategy = strategy, .hand = try std.ArrayList(Card).initCapacity(allocator, 20) };
    }

    pub fn deinit(self: *Player, allocator: std.mem.Allocator) void {
        self.hand.deinit(allocator);
    }

    pub fn handScore(self: *Player) u32 {
        var score: u32 = 0;
        var number_cards: u32 = 0;
        var multiply_by_2: bool = false;

        for (self.hand.items) |c| {
            switch (c) {
                .Zero, .One, .Two, .Three, .Four, .Five, .Six, .Seven, .Eight, .Nine, .Ten, .Eleven, .Twelve => {
                    score += @intFromEnum(c);
                    number_cards += 1;
                },
                .PlusTwo, .PlusFour, .PlusSix, .PlusEight, .PlusTen => {
                    const modifier = (@intFromEnum(c) - @intFromEnum(Card.PlusTwo) + 1) * 2;
                    score += modifier;
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

        if (multiply_by_2) {
            score *= 2;
        }

        if (number_cards == 7) {
            score += 15;
        }

        return score;
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
        try t.expectEqual(186 + 15, player.handScore());
    }

    pub fn decideTakeCard(self: *Player, deck: *Deck) bool {
        switch (self.strategy) {
            .MinPoints => |min_points| {
                return self.handScore() < min_points;
            },
            .MaxCards => |max_cards| {
                var number_card_count: u32 = 0;
                for (self.hand.items) |c| {
                    if (c.isNumber()) {
                        number_card_count += 1;
                    }
                }
                return number_card_count < max_cards;
            },
            .MinPointsMaxCards => |data| {
                if (self.handScore() < data.min_points) {
                    return true;
                }
                return self.hand.items.len < data.max_cards;
            },
            .Always7 => {
                return self.hand.items.len < 7;
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

    pub fn takeCard(self: *Player, card: Card) bool {
        self.hand.appendAssumeCapacity(card);

        // check if any card is duplicated
        for (0..self.hand.items.len - 1) |i| {
            // always comparing to the last card, since that's the one that was just added
            if (self.hand.items[i] == self.hand.items[self.hand.items.len - 1]) {
                // Remove the duplicate card that was just added
                _ = self.hand.pop();
                // SecondChance saves the player: remove the SecondChance instead of eliminating
                if (self.removeCard(.SecondChance)) {
                    return false;
                }
                self.is_still_in_game = false;
                return false;
            }
        }

        var number_card_count: u32 = 0;
        for (self.hand.items) |c| {
            switch (c) {
                .Zero, .One, .Two, .Three, .Four, .Five, .Six, .Seven, .Eight, .Nine, .Ten, .Eleven, .Twelve => {
                    number_card_count += 1;
                },
                else => {},
            }
        }

        if (number_card_count == 7) {
            self.score += self.handScore();
            return true;
        }

        return false;
    }

    test "takeCard fails on duplicate card" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        try t.expect(!player.takeCard(.Twelve));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.takeCard(.Twelve));
        try t.expect(!player.is_still_in_game);
    }

    test "takeCard with SecondChance survives duplicate" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        try t.expect(!player.takeCard(.SecondChance));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.takeCard(.Twelve));
        try t.expect(player.is_still_in_game);
        // duplicate Twelve: SecondChance is consumed, player survives
        try t.expect(!player.takeCard(.Twelve));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.hasCard(.SecondChance));
        try t.expectEqual(1, player.hand.items.len); // only the first Twelve remains
        // now a second duplicate eliminates the player (no SecondChance left)
        try t.expect(!player.takeCard(.Twelve));
        try t.expect(!player.is_still_in_game);
    }

    test "takeCard SecondChance itself cannot be duplicated" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        // Player draws a SecondChance normally
        try t.expect(!player.takeCard(.SecondChance));
        try t.expect(player.is_still_in_game);
        // Drawing a second SecondChance triggers the duplicate check; the existing
        // SecondChance in hand is consumed to save the player.
        try t.expect(!player.takeCard(.SecondChance));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.hasCard(.SecondChance));
    }

    test "takeCard ends round at 7 cards" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        try t.expect(!player.takeCard(.Zero));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.takeCard(.One));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.takeCard(.Two));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.takeCard(.Three));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.takeCard(.Four));
        try t.expect(player.is_still_in_game);
        try t.expect(!player.takeCard(.Five));
        try t.expect(player.is_still_in_game);
        try t.expect(player.takeCard(.Six));
        try t.expect(player.is_still_in_game);
    }

    test "takeCard does not end round if 7th card is a not a number card" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var player = try Player.init(allocator, prng, DrawStrategy.Always7);
        defer player.deinit(allocator);

        try t.expect(!player.takeCard(.Zero));
        try t.expect(!player.takeCard(.One));
        try t.expect(!player.takeCard(.Two));
        try t.expect(!player.takeCard(.Three));
        try t.expect(!player.takeCard(.Four));
        try t.expect(!player.takeCard(.Five));
        try t.expect(!player.takeCard(.PlusTwo));
        try t.expect(!player.takeCard(.PlusFour));
        try t.expect(!player.takeCard(.PlusSix));
        try t.expect(!player.takeCard(.PlusEight));
        try t.expect(!player.takeCard(.PlusTen));
        try t.expect(!player.takeCard(.SecondChance));
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
        self.is_still_in_game = false;
    }

    pub fn nextRound(self: *Player) void {
        self.hand.clearRetainingCapacity();
        self.is_still_in_game = true;
    }
};

pub const GameEvent = union(enum) {
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
};

pub const GameResult = struct {
    winning_strategy: DrawStrategy,
    cards_played: u64,
};

pub const GameSimulation = struct {
    allocator: std.mem.Allocator,
    prng: std.Random,
    deck: *Deck,
    players: []Player,
    player_selection_buffer: []*Player,
    current_player_index: u32,
    cards_played: u32 = 0,

    events: std.ArrayList(GameEvent) = undefined,

    result_: ?GameResult = null,

    pub fn init(allocator: std.mem.Allocator, prng: std.Random, deck: *Deck, players: []Player) !GameSimulation {
        return GameSimulation{
            .allocator = allocator,
            .prng = prng,
            .deck = deck,
            .players = players,
            .player_selection_buffer = try allocator.alloc(*Player, players.len),
            .current_player_index = 0,
            .events = try std.ArrayList(GameEvent).initCapacity(allocator, 100),
        };
    }

    pub fn deinit(self: *GameSimulation) void {
        self.allocator.free(self.player_selection_buffer);
        self.events.deinit(self.allocator);
    }

    pub fn step(self: *GameSimulation) !bool {
        self.log("Step: current_player_index = {}, cards_played = {}, deck_size = {}", .{ self.current_player_index, self.cards_played, self.deck.cards.items.len });

        if (self.result_ != null) {
            // game simulation is already finished
            self.log("Game simulation is already finished", .{});
            return false;
        }

        var winning_player: ?*Player = null;
        for (self.players) |*player| {
            if (player.score >= 200) {
                winning_player = player;
                break;
            }
        }
        if (winning_player) |player| {
            self.result_ = GameResult{
                .winning_strategy = player.strategy,
                .cards_played = self.cards_played,
            };
            try self.addEvent(.{ .PlayerWon = .{ .player = player, .score = player.score } });
            self.log("Game simulation finished: player with strategy {} won with score {}", .{ player.strategy, player.score });
            return false;
        }

        var all_players_eliminated = true;
        for (self.players) |p| {
            if (p.is_still_in_game) {
                all_players_eliminated = false;
                break;
            }
        }
        if (all_players_eliminated) {
            for (self.players) |*p| {
                p.nextRound();
            }
            try self.addEvent(.{ .NewRoundStarted = .{} });
            return true;
        }

        if (self.deck.cards.items.len == 0) {
            try self.deck.refill(self.allocator);
            self.deck.shuffle();
            try self.addEvent(.{ .DeckShuffle = .{} });
            return true;
        }

        const starting_player_index = self.current_player_index;
        var player = &self.players[self.current_player_index];
        while (!player.is_still_in_game) {
            self.current_player_index += 1;
            if (self.current_player_index >= self.players.len) {
                self.current_player_index = 0;
            }
            player = &self.players[self.current_player_index];

            if (self.current_player_index == starting_player_index) {
                // should never happen, but just in case: all players are eliminated, start a new round
                self.log("All players are eliminated, starting a new round", .{});
                return true;
            }
        }

        self.current_player_index += 1;
        if (self.current_player_index >= self.players.len) {
            self.current_player_index = 0;
        }

        if (!player.decideTakeCard(self.deck)) {
            player.endRound();
            try self.addEvent(.{ .PlayerEndRound = .{ .player = player, .score = player.score } });
            return true;
        }

        const card = self.deck.cards.pop().?;
        self.cards_played += 1;
        switch (card) {
            .Freeze => {
                try self.addEvent(.{ .DrawCard = .{ .player = player, .card = card } });
                try self.handleFreeze(player);
                return true;
            },
            .FlipThree => {
                try self.addEvent(.{ .DrawCard = .{ .player = player, .card = card } });
                try self.handleFlipThree(player);
                return true;
            },
            .SecondChance => {
                try self.handleSecondChance(player, card);
                return true;
            },
            else => {
                _ = player.takeCard(card);
                try self.addEvent(.{ .DrawCard = .{ .player = player, .card = card } });
            },
        }

        return true;
    }

    pub fn result(self: *GameSimulation) GameResult {
        return self.result_.?;
    }

    fn handleSecondChance(self: *GameSimulation, player: *Player, card: Card) error{OutOfMemory}!void {
        if (!player.hasCard(card)) {
            _ = player.takeCard(card);
            try self.addEvent(.{ .DrawCard = .{ .player = player, .card = card } });
            return;
        }

        // Player already has a SecondChance: give it to a random other eligible player.
        var available_players = std.ArrayList(*Player).initBuffer(self.player_selection_buffer);
        for (self.players) |*other_player| {
            if (other_player == player) continue;
            if (!other_player.is_still_in_game) continue;
            if (other_player.hasCard(card)) continue;
            available_players.appendAssumeCapacity(other_player);
        }

        if (available_players.items.len == 0) {
            // No eligible recipient: discard.
            return;
        }

        const random_index = self.prng.intRangeLessThan(usize, 0, available_players.items.len);
        _ = available_players.items[random_index].takeCard(card);
        try self.addEvent(.{ .DrawCard = .{ .player = player, .card = card } });
    }

    fn handleFreeze(self: *GameSimulation, player: *Player) !void {
        // TODO make this a configurable strategy, doing it randomly for now
        var available_players = std.ArrayList(*Player).initBuffer(self.player_selection_buffer);
        for (self.players) |*p| {
            if (p == player) {
                continue;
            }
            if (!p.is_still_in_game) {
                continue;
            }
            available_players.appendAssumeCapacity(p);
        }

        if (available_players.items.len == 0) {
            player.endRound();
            try self.addEvent(.{ .PlayerEliminated = .{ .player = player } });
            return;
        }

        const random_index = self.prng.intRangeLessThan(usize, 0, available_players.items.len);
        var freeze_target = &self.players[random_index];
        freeze_target.endRound();
        try self.addEvent(.{ .PlayerEndRound = .{ .player = freeze_target, .score = freeze_target.score } });
    }

    fn drawThreeCards(self: *GameSimulation, player: *Player) error{OutOfMemory}!void {
        var freeze_count: u8 = 0;
        var flip_three_count: u8 = 0;
        var should_resolve_action_cards = true;
        for (0..3) |_| {
            if (self.deck.cards.items.len == 0) {
                try self.deck.refill(self.allocator);
                self.deck.shuffle();
                try self.addEvent(.{ .DeckShuffle = .{} });
            }

            const drawn = self.deck.cards.pop().?;
            self.cards_played += 1;
            if (drawn == .Freeze) {
                freeze_count += 1;
                continue;
            }
            if (drawn == .FlipThree) {
                flip_three_count += 1;
                continue;
            }
            if (drawn == .SecondChance) {
                try self.handleSecondChance(player, drawn);
                continue;
            }

            const round_over = player.takeCard(drawn);
            try self.addEvent(.{ .DrawCard = .{ .player = player, .card = drawn } });
            if (round_over or !player.is_still_in_game) {
                should_resolve_action_cards = false;
                break;
            }
        }

        if (should_resolve_action_cards) {
            for (0..flip_three_count) |_| {
                try self.handleFlipThree(player);
            }
            for (0..freeze_count) |_| {
                try self.handleFreeze(player);
            }
        }
    }

    fn handleFlipThree(self: *GameSimulation, player: *Player) !void {
        // TODO make this a configurable strategy, doing it randomly for now
        var available_players = std.ArrayList(*Player).initBuffer(self.player_selection_buffer);
        for (self.players) |*p| {
            if (p == player) {
                continue;
            }
            if (!p.is_still_in_game) {
                continue;
            }
            available_players.appendAssumeCapacity(p);
        }

        if (available_players.items.len == 0) {
            // No targets: the player who drew FlipThree must draw 3 cards themselves.
            try self.drawThreeCards(player);
            return;
        }

        const random_index = self.prng.intRangeLessThan(usize, 0, available_players.items.len);
        const flip_three_target = available_players.items[random_index];
        try self.drawThreeCards(flip_three_target);
    }

    test "handleFlipThree simple case" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        var players = [_]Player{
            try .init(allocator, prng, .Random),
            try .init(allocator, prng, .Random),
        };
        defer {
            for (&players) |*player| {
                player.deinit(allocator);
            }
        }

        try deck.cards.append(allocator, .One);
        try deck.cards.append(allocator, .Two);
        try deck.cards.append(allocator, .Three);

        var simulation = try GameSimulation.init(allocator, prng, &deck, &players);
        defer simulation.deinit();

        const drawing_player = &players[0];
        try simulation.handleFlipThree(drawing_player);

        const other_player = &players[1];
        try t.expectEqual(true, other_player.is_still_in_game);
        try t.expectEqual(3, other_player.hand.items.len);
        try t.expectEqual(.Three, other_player.hand.items[0]);
        try t.expectEqual(.Two, other_player.hand.items[1]);
        try t.expectEqual(.One, other_player.hand.items[2]);
    }

    test "handleFlipThree flip three as last drawn card" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        var players = [_]Player{
            try .init(allocator, prng, .Random),
            try .init(allocator, prng, .Random),
        };
        defer {
            for (&players) |*player| {
                player.deinit(allocator);
            }
        }

        try deck.cards.append(allocator, .One);
        try deck.cards.append(allocator, .Two);
        try deck.cards.append(allocator, .Three);
        try deck.cards.append(allocator, .FlipThree);
        try deck.cards.append(allocator, .Four);
        try deck.cards.append(allocator, .Five);

        var simulation = try GameSimulation.init(allocator, prng, &deck, &players);
        defer simulation.deinit();

        const drawing_player = &players[0];
        try simulation.handleFlipThree(drawing_player);

        const other_player = &players[1];
        try t.expectEqual(true, other_player.is_still_in_game);
        try t.expectEqual(2, other_player.hand.items.len);
        try t.expectEqual(.Five, other_player.hand.items[0]);
        try t.expectEqual(.Four, other_player.hand.items[1]);

        try t.expectEqual(true, drawing_player.is_still_in_game);
        try t.expectEqual(3, drawing_player.hand.items.len);
        try t.expectEqual(.Three, drawing_player.hand.items[0]);
        try t.expectEqual(.Two, drawing_player.hand.items[1]);
        try t.expectEqual(.One, drawing_player.hand.items[2]);
    }

    test "handleFlipThree flip three as first and second drawn card" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        var players = [_]Player{
            try .init(allocator, prng, .Random),
            try .init(allocator, prng, .Random),
        };
        defer {
            for (&players) |*player| {
                player.deinit(allocator);
            }
        }

        try deck.cards.append(allocator, .One);
        try deck.cards.append(allocator, .Two);
        try deck.cards.append(allocator, .Three);
        try deck.cards.append(allocator, .Four);
        try deck.cards.append(allocator, .Five);
        try deck.cards.append(allocator, .Six);
        try deck.cards.append(allocator, .Seven);
        try deck.cards.append(allocator, .FlipThree);
        try deck.cards.append(allocator, .FlipThree);

        var simulation = try GameSimulation.init(allocator, prng, &deck, &players);
        defer simulation.deinit();

        const drawing_player = &players[0];
        try simulation.handleFlipThree(drawing_player);

        const other_player = &players[1];
        try t.expectEqual(true, other_player.is_still_in_game);
        try t.expectEqual(1, other_player.hand.items.len);
        try t.expectEqual(.Seven, other_player.hand.items[0]);

        try t.expectEqual(true, drawing_player.is_still_in_game);
        try t.expectEqual(6, drawing_player.hand.items.len);
        try t.expectEqual(.Six, drawing_player.hand.items[0]);
        try t.expectEqual(.Five, drawing_player.hand.items[1]);
        try t.expectEqual(.Four, drawing_player.hand.items[2]);
        try t.expectEqual(.Three, drawing_player.hand.items[3]);
        try t.expectEqual(.Two, drawing_player.hand.items[4]);
        try t.expectEqual(.One, drawing_player.hand.items[5]);
    }

    test "handleFlipThree freeze as last card" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        var players = [_]Player{
            try .init(allocator, prng, .Random),
            try .init(allocator, prng, .Random),
        };
        defer {
            for (&players) |*player| {
                player.deinit(allocator);
            }
        }

        try deck.cards.append(allocator, .Freeze);
        try deck.cards.append(allocator, .One);
        try deck.cards.append(allocator, .Two);

        var simulation = try GameSimulation.init(allocator, prng, &deck, &players);
        defer simulation.deinit();

        const drawing_player = &players[0];
        try simulation.handleFlipThree(drawing_player);

        const other_player = &players[1];
        try t.expectEqual(true, other_player.is_still_in_game);
        try t.expectEqual(2, other_player.hand.items.len);
        try t.expectEqual(.Two, other_player.hand.items[0]);
        try t.expectEqual(.One, other_player.hand.items[1]);

        try t.expectEqual(false, drawing_player.is_still_in_game);
    }

    test "handleFlipThree freeze as first and second card" {
        const allocator = t.allocator;
        var r = std.Random.DefaultPrng.init(0);
        const prng = r.random();

        var deck = try Deck.init(allocator, prng);
        defer deck.deinit(allocator);

        var players = [_]Player{
            try .init(allocator, prng, .Random),
            try .init(allocator, prng, .Random),
        };
        defer {
            for (&players) |*player| {
                player.deinit(allocator);
            }
        }

        try deck.cards.append(allocator, .One);
        try deck.cards.append(allocator, .Freeze);
        try deck.cards.append(allocator, .Freeze);

        var simulation = try GameSimulation.init(allocator, prng, &deck, &players);
        defer simulation.deinit();

        const drawing_player = &players[0];
        try simulation.handleFlipThree(drawing_player);

        const other_player = &players[1];
        try t.expectEqual(false, other_player.is_still_in_game);
        try t.expectEqual(1, other_player.hand.items.len);
        try t.expectEqual(.One, other_player.hand.items[0]);

        try t.expectEqual(false, drawing_player.is_still_in_game);
    }

    fn addEvent(self: *GameSimulation, event: GameEvent) !void {
        try self.events.append(self.allocator, event);
    }

    fn log(self: *GameSimulation, comptime fmt: []const u8, args: anytype) void {
        _ = self;
        const is_wasm = @import("builtin").target.cpu.arch == .wasm32;
        if (!is_wasm) {
            std.debug.print(fmt ++ "\n", args);
        }
    }
};
