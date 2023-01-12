const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const stderr = std.io.getStdErr().writer();
    const target = b.standardTargetOptions(.{});
    const target_info = try std.zig.system.NativeTargetInfo.detect(target);
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

    const znwt_run_step = b.step("run", "Run znwt");
    znwt_run_step.dependOn(&znwt_run_cmd.step);

    const znwt_tests = b.addTest("src/znwt.zig");
    znwt_tests.setTarget(target);
    znwt_tests.setBuildMode(mode);
    switch (target_info.target.os.tag) {
        .linux => znwt.addPackagePath("serial", "src/utils/serial_linux.zig"),
        .macos => znwt.addPackagePath("serial", "src/utils/serial_macos.zig"),
        else => {
            try stderr.print("\nUnsupported target: {}\n", .{target_info.target.os.tag});
            return error.NotSupported;
        },
    }

    const znwt_test_step = b.step("test", "Run unit tests for znwt");
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

    const nsof_run_step = b.step("nsof", "Run nsof");
    nsof_run_step.dependOn(&nsof_run_cmd.step);

    const nsof_tests = b.addTest("src/nsof.zig");
    nsof_tests.setTarget(target);
    nsof_tests.setBuildMode(mode);

    const nsof_test_step = b.step("nsof-test", "Run nsof unit tests");
    nsof_test_step.dependOn(&nsof_tests.step);
}
