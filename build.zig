const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run unit tests");

    { // simulation executable
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/flip7_sim.zig"),
            .target = target,
            .optimize = optimize,
        });
        const exe = b.addExecutable(.{
            .name = "flip7_sim",
            .root_module = exe_mod,
        });
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        const run_step = b.step("run-sim", "Run the simulation");
        run_step.dependOn(&run_cmd.step);

        const run_tests = b.addRunArtifact(b.addTest(.{ .root_module = exe_mod }));
        test_step.dependOn(&run_tests.step);
    }

    // -------------------------------------------------------------------------
    // Native executable (SDL3 / OpenGL 3.3)
    // -------------------------------------------------------------------------

    { // game executable
        const sdl_dep = b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
        });
        const sdl_lib = sdl_dep.artifact("SDL3");

        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/main_native.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.linkLibrary(sdl_lib);

        const exe = b.addExecutable(.{
            .name = "flip7",
            .root_module = exe_mod,
        });
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        const exe_tests = b.addTest(.{ .root_module = exe_mod });
        const run_tests = b.addRunArtifact(exe_tests);
        test_step.dependOn(&run_tests.step);
    }

    // -------------------------------------------------------------------------
    // Wasm build step:  zig build wasm
    //   Produces zig-out/bin/flip7.wasm targeting wasm32-wasi.
    // -------------------------------------------------------------------------

    {
        const wasm_target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        });

        const wasm_mod = b.createModule(.{
            .root_source_file = b.path("src/main_wasm.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });

        const wasm_exe = b.addExecutable(.{
            .name = "flip7",
            .root_module = wasm_mod,
        });
        wasm_exe.entry = .disabled;
        wasm_exe.rdynamic = true;
        const install_wasm = b.addInstallArtifact(wasm_exe, .{});
        const wasm_step = b.step("wasm", "Build WebGL module (wasm32-wasi)");
        wasm_step.dependOn(&install_wasm.step);

        const install_html = b.addInstallBinFile(b.path("static/index.html"), "index.html");
        const install_js = b.addInstallBinFile(b.path("static/webgl.js"), "webgl.js");
        wasm_step.dependOn(&install_html.step);
        wasm_step.dependOn(&install_js.step);

        b.getInstallStep().dependOn(wasm_step);
    }
}
