const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const znwt = b.addExecutable("znwt", "src/znwt.zig");
    znwt.setTarget(target);
    znwt.setBuildMode(mode);
    znwt.install();

    const znwt_run_cmd = znwt.run();
    znwt_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        znwt_run_cmd.addArgs(args);
    }

    const znwt_run_step = b.step("run", "Run the app");
    znwt_run_step.dependOn(&znwt_run_cmd.step);

    const znwt_tests = b.addTest("src/znwt.zig");
    znwt_tests.setTarget(target);
    znwt_tests.setBuildMode(mode);

    const znwt_test_step = b.step("test", "Run unit tests");
    znwt_test_step.dependOn(&znwt_tests.step);
    znwt_test_step.dependOn(&znwt_tests.step);

    const nsof = b.addExecutable("nsof", "src/nsof.zig");
    nsof.setTarget(target);
    nsof.setBuildMode(mode);
    nsof.install();

    const nsof_run_cmd = nsof.run();
    nsof_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        nsof_run_cmd.addArgs(args);
    }

    const nsof_run_step = b.step("run", "Run the app");
    nsof_run_step.dependOn(&nsof_run_cmd.step);

    const nsof_tests = b.addTest("src/nsof.zig");
    nsof_tests.setTarget(target);
    nsof_tests.setBuildMode(mode);

    const nsof_test_step = b.step("test", "Run unit tests");
    nsof_test_step.dependOn(&nsof_tests.step);
    nsof_test_step.dependOn(&nsof_tests.step);
}
