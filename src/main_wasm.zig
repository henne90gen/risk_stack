const platform = @import("platform.zig");
const TriangleApp = @import("main.zig").TriangleApp;

comptime {
    if (@import("builtin").target.cpu.arch == .wasm32) {
        platform.run(TriangleApp);
    }
}
