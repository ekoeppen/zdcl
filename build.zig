const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const stderr = std.io.getStdErr().writer();
    const target = b.standardTargetOptions(.{});
    const target_info = try std.zig.system.NativeTargetInfo.detect(target);
    const mode = b.standardOptimizeOption(.{});

    const znwt = b.addExecutable(.{
        .name = "znwt",
        .root_source_file = .{ .path = "src/znwt.zig" },
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(znwt);

    const znwt_run_cmd = b.addRunArtifact(znwt);
    znwt_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        znwt_run_cmd.addArgs(args);
    }

    const znwt_run_step = b.step("run", "Run znwt");
    znwt_run_step.dependOn(&znwt_run_cmd.step);

    const znwt_tests = b.addTest(.{
        .name = "znwt_test",
        .root_source_file = .{ .path = "src/znwt.zig" },
        .target = target,
        .optimize = mode,
    });
    const serial_path = switch (target_info.target.os.tag) {
        .linux => "src/utils/serial_linux.zig",
        .macos => "src/utils/serial_macos.zig",
        else => {
            try stderr.print("\nUnsupported target: {}\n", .{target_info.target.os.tag});
            return error.NotSupported;
        },
    };
    //const serial_module = b.addModule("serial", .{ .source_file = .{ .path = serial_path } });
    znwt.addModule("serial", b.createModule(.{ .source_file = .{ .path = serial_path } }));

    const znwt_test_step = b.step("test", "Run unit tests for znwt");
    znwt_test_step.dependOn(&znwt_tests.step);

    const nsof = b.addExecutable(.{
        .name = "nsof",
        .root_source_file = .{ .path = "src/nsof.zig" },
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(nsof);

    const nsof_run_cmd = b.addRunArtifact(nsof);
    nsof_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        nsof_run_cmd.addArgs(args);
    }

    const nsof_run_step = b.step("nsof", "Run nsof");
    nsof_run_step.dependOn(&nsof_run_cmd.step);

    const nsof_tests = b.addTest(.{
        .name = "nsof_test",
        .root_source_file = .{ .path = "src/nsof.zig" },
        .target = target,
        .optimize = mode,
    });

    const nsof_test_step = b.step("nsof-test", "Run nsof unit tests");
    nsof_test_step.dependOn(&nsof_tests.step);
}
