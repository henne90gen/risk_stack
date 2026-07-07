const platform = @import("platform.zig");
const TriangleApp = @import("main.zig").TriangleApp;

pub fn main() !void {
    if (comptime @import("builtin").target.cpu.arch != .wasm32) {
        platform.run(TriangleApp);
    }
}
