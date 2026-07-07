const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -------------------------------------------------------------------------
    // Native executable (SDL3 / OpenGL 3.3)
    // -------------------------------------------------------------------------

    {
        const sdl_dep = b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
        });
        const sdl_lib = sdl_dep.artifact("SDL3");

        const keys_mod = b.createModule(.{
            .root_source_file = b.path("src/keys.zig"),
            .target = target,
            .optimize = optimize,
        });

        const gl_mod = b.createModule(.{
            .root_source_file = b.path("src/gl.zig"),
            .target = target,
            .optimize = optimize,
        });
        gl_mod.linkLibrary(sdl_lib);

        const platform_sdl_mod = b.createModule(.{
            .root_source_file = b.path("src/platform_sdl.zig"),
            .target = target,
            .optimize = optimize,
        });
        platform_sdl_mod.addImport("gl", gl_mod);
        platform_sdl_mod.addImport("keys", keys_mod);
        platform_sdl_mod.linkLibrary(sdl_lib);

        const platform_mod = b.createModule(.{
            .root_source_file = b.path("src/platform.zig"),
            .target = target,
            .optimize = optimize,
        });
        platform_mod.addImport("gl", gl_mod);
        platform_mod.addImport("keys", keys_mod);
        platform_mod.addImport("platform_sdl", platform_sdl_mod);

        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("platform", platform_mod);
        exe_mod.addImport("gl", gl_mod);
        exe_mod.addImport("keys", keys_mod);
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
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&run_tests.step);
    }

    // -------------------------------------------------------------------------
    // Wasm build step:  zig build wasm
    //   Produces zig-out/bin/flip7.wasm targeting wasm32-wasi.
    // -------------------------------------------------------------------------

    {
        const wasm_target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        });

        const keys_mod = b.createModule(.{
            .root_source_file = b.path("src/keys.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });

        const gl_mod = b.createModule(.{
            .root_source_file = b.path("src/gl.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });

        const platform_mod = b.createModule(.{
            .root_source_file = b.path("src/platform.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });
        platform_mod.addImport("gl", gl_mod);
        platform_mod.addImport("keys", keys_mod);

        const wasm_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });
        wasm_mod.addImport("platform", platform_mod);
        wasm_mod.addImport("gl", gl_mod);
        wasm_mod.addImport("keys", keys_mod);

        const wasm_exe = b.addExecutable(.{
            .name = "flip7",
            .root_module = wasm_mod,
        });
        const install_wasm = b.addInstallArtifact(wasm_exe, .{});
        const wasm_step = b.step("wasm", "Build WebGL module (wasm32-wasi)");
        wasm_step.dependOn(&install_wasm.step);
    }
}
