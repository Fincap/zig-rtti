const std = @import("std");

const project_name: []const u8 = "rtti";

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Run unit tests");
    const run_step = b.step("run", "Run the app");
    const check_step = b.step("check", "Check if " ++ project_name ++ " compiles");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib_mod = b.addModule("rtti", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit testing
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    test_step.dependOn(&run_lib_unit_tests.step);

    // Run step (for dev testing)
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("rtti", lib_mod);
    const exe = b.addExecutable(.{
        .name = project_name,
        .root_module = exe_mod,
    });
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // Check step
    const check = b.addExecutable(.{
        .name = project_name,
        .root_module = exe_mod,
    });
    check_step.dependOn(&check.step);
    check_step.dependOn(&lib_unit_tests.step);
}
