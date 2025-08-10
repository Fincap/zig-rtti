const std = @import("std");

const project_name: []const u8 = "rtti";

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Run unit tests");
    const run_step = b.step("run", "Run the app");
    const check_step = b.step("check", "Check if " ++ project_name ++ " compiles");
    const docs_step = b.step("docs", "Emit documentation");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib_mod = b.addModule("rtti", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = project_name,
        .root_module = lib_mod,
        .use_llvm = true,
    });
    b.installArtifact(lib);

    // Run step (for dev testing)
    const exe = b.addExecutable(.{
        .name = project_name,
        .root_module = lib_mod,
    });
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    // Check step
    const exe_check = b.addExecutable(.{
        .name = project_name,
        .root_module = lib_mod,
    });
    check_step.dependOn(&exe_check.step);

    // Unit testing
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    test_step.dependOn(&run_lib_unit_tests.step);

    // Documentation
    const docs_install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = lib.getEmittedDocs(),
    });
    docs_step.dependOn(&docs_install.step);
}
