const m = @import("main");

comptime {
    if (@import("builtin").target.cpu.arch == .wasm32) {
        m.p.run(m.TriangleApp);
    }
}
