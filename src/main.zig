const std = @import("std");
const Io = std.Io;
const t = std.testing;

test {
    t.refAllDecls(@This());
}

const Card = enum(u8) {
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

    PlusTwo = 16,
    PlusFour = 17,
    PlusSix = 18,
    PlusEight = 19,
    PlusTen = 20,

    TimesTwo = 21,

    SecondChance = 13,
    Freeze = 14,
    FlipThree = 15,

    pub fn isNumber(self: Card) bool {
        return @intFromEnum(self) <= @intFromEnum(Card.Twelve);
    }
};

const Deck = struct {
    cards: std.ArrayList(Card),
    prng: std.Random,

    pub fn init(allocator: std.mem.Allocator, prng: std.Random) !Deck {
        const cards = try std.ArrayList(Card).initCapacity(allocator, 94);
        var deck = Deck{ .cards = cards, .prng = prng };
        try deck.refill(allocator);
        return deck;
    }

    pub fn deinit(self: *Deck, allocator: std.mem.Allocator) void {
        self.cards.deinit(allocator);
    }

    pub fn shuffle(self: *Deck) void {
        std.Random.shuffle(self.prng, Card, self.cards.items);
    }

    pub fn refill(self: *Deck, allocator: std.mem.Allocator) !void {
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

const DrawStrategy = union(enum) {
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

    const Context = struct {
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

const Player = struct {
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
                return self.hand.items.len < max_cards;
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

const GameSimulation = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    prng: std.Random,
    deck: *Deck,
    players: []Player,
    player_selection_buffer: []*Player,
    cards_played: u32 = 0,

    start_time: ?std.Io.Timestamp = null,
    current_player_index: u32 = 0,

    result_: ?GameResult = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, prng: std.Random, deck: *Deck, players: []Player) !GameSimulation {
        return GameSimulation{
            .allocator = allocator,
            .io = io,
            .prng = prng,
            .deck = deck,
            .players = players,
            .player_selection_buffer = try allocator.alloc(*Player, players.len),
        };
    }

    pub fn deinit(self: *GameSimulation, allocator: std.mem.Allocator) void {
        allocator.free(self.player_selection_buffer);
    }

    pub fn step(self: *GameSimulation) !bool {
        if (self.start_time == null) {
            // first call to step -> initializing
            self.start_time = std.Io.Clock.now(.real, self.io);

            self.deck.shuffle();
            self.current_player_index = @intCast(self.players.len);
        }

        if (self.result_ != null) {
            // game simulation is already finished
            return false;
        }

        var winning_player: ?Player = null;
        for (self.players) |player| {
            if (player.score >= 200) {
                winning_player = player;
                break;
            }
        }
        if (winning_player) |player| {
            const end_time = std.Io.Clock.now(.real, self.io);
            const runtime = self.start_time.?.durationTo(end_time);
            self.result_ = GameResult{
                .winning_strategy = player.strategy,
                .cards_played = self.cards_played,
                .runtime = runtime,
            };
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
        }

        self.current_player_index += 1;
        if (self.current_player_index >= self.players.len) {
            self.current_player_index = 0;
        }

        if (self.deck.cards.items.len == 0) {
            try self.deck.refill(self.allocator);
            self.deck.shuffle();
        }

        var player = &self.players[self.current_player_index];
        if (!player.is_still_in_game) {
            return true;
        }

        if (!player.decideTakeCard(self.deck)) {
            player.endRound();
        }

        const card = self.deck.cards.pop().?;
        self.cards_played += 1;
        switch (card) {
            .Freeze => {
                self.handleFreeze(player);
                return true;
            },
            .FlipThree => {
                try self.handleFlipThree(player);
                return true;
            },
            .SecondChance => {
                try self.handleSecondChance(player, card);
                return true;
            },
            else => {
                if (player.takeCard(card)) {
                    for (self.players) |*p| {
                        p.nextRound();
                    }
                }
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
    }

    fn handleFreeze(self: *GameSimulation, player: *Player) void {
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
            return;
        }

        const random_index = self.prng.intRangeLessThan(usize, 0, available_players.items.len);
        var freeze_target = &self.players[random_index];
        freeze_target.endRound();
    }

    fn drawThreeCards(self: *GameSimulation, player: *Player) error{OutOfMemory}!void {
        var freeze_count: u8 = 0;
        var flip_three_count: u8 = 0;
        var should_resolve_action_cards = true;
        for (0..3) |_| {
            if (self.deck.cards.items.len == 0) {
                try self.deck.refill(self.allocator);
                self.deck.shuffle();
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
                self.handleFreeze(player);
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

        var simulation = try GameSimulation.init(allocator, t.io, prng, &deck, &players);
        defer simulation.deinit(allocator);

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

        var simulation = try GameSimulation.init(allocator, t.io, prng, &deck, &players);
        defer simulation.deinit(allocator);

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

        var simulation = try GameSimulation.init(allocator, t.io, prng, &deck, &players);
        defer simulation.deinit(allocator);

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

        var simulation = try GameSimulation.init(allocator, t.io, prng, &deck, &players);
        defer simulation.deinit(allocator);

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

        var simulation = try GameSimulation.init(allocator, t.io, prng, &deck, &players);
        defer simulation.deinit(allocator);

        const drawing_player = &players[0];
        try simulation.handleFlipThree(drawing_player);

        const other_player = &players[1];
        try t.expectEqual(false, other_player.is_still_in_game);
        try t.expectEqual(1, other_player.hand.items.len);
        try t.expectEqual(.One, other_player.hand.items[0]);

        try t.expectEqual(false, drawing_player.is_still_in_game);
    }
};

const GameResult = struct {
    winning_strategy: DrawStrategy,
    cards_played: u64,
    runtime: std.Io.Duration,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const games_to_run = 100_000;

    const SharedResults = struct {
        mutex: std.Io.Mutex = .init,
        total_cards_played: u64 = 0,
        total_runtime: std.Io.Duration = std.Io.Duration.fromSeconds(0),
        draw_strategy_wins: std.HashMap(DrawStrategy, u32, DrawStrategy.Context, std.hash_map.default_max_load_percentage),
    };
    var shared = SharedResults{
        .draw_strategy_wins = std.HashMap(DrawStrategy, u32, DrawStrategy.Context, std.hash_map.default_max_load_percentage).init(allocator),
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
            var local_wins = std.HashMap(DrawStrategy, u32, DrawStrategy.Context, std.hash_map.default_max_load_percentage).init(ctx.allocator);
            defer local_wins.deinit();

            std.debug.print("Simulating {d} games\n", .{ctx.games});

            for (0..ctx.games) |_| {
                const result = try runGame(ctx.allocator, ctx.io, ctx.prng.random());
                local_cards_played += result.cards_played;
                local_runtime = .fromNanoseconds(local_runtime.nanoseconds + result.runtime.nanoseconds);
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

        fn runGame(task_allocator: std.mem.Allocator, io: std.Io, prng: std.Random) !GameResult {
            var arena = std.heap.ArenaAllocator.init(task_allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            var deck = try Deck.init(arena_allocator, prng);
            defer deck.deinit(arena_allocator);

            var players = [_]Player{
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

            var simulation = try GameSimulation.init(arena_allocator, io, prng, &deck, &players);
            defer simulation.deinit(arena_allocator);

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
    const Entry = struct { strategy: DrawStrategy, wins: u32 };
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
