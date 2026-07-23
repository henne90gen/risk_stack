const std = @import("std");
const t = std.testing;

const m = @import("main.zig");

test {
    t.refAllDecls(@This());
}

pub fn main() !void {
    if (comptime @import("builtin").target.cpu.arch != .wasm32) {
        m.p.run(m.Flip7App);
    }
}
