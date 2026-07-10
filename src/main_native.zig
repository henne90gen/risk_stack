const m = @import("main");

pub fn main() !void {
    if (comptime @import("builtin").target.cpu.arch != .wasm32) {
        m.p.run(m.TriangleApp);
    }
}
