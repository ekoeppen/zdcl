const std = @import("std");
const builtin = @import("builtin");
const framing_layer = @import("./protocol/framing_layer.zig");
const mnp_layer = @import("./protocol/mnp_layer.zig");
const dock_layer = @import("./protocol/dock_layer.zig");
const connect_module = @import("./modules/connect_module.zig");
const load_package_module = @import("./modules/load_package_module.zig");
const info_module = @import("./modules/info_module.zig");
const send_soup_module = @import("./modules/send_soup_module.zig");
const event_queue = @import("./protocol/event_queue.zig");
const args = @import("./utils/args.zig");
const serial = @import("serial");

const Command = union(enum) {
    load: struct { file: []const u8, data: []const u8 = undefined },
    info: bool,
    sync: bool,
    soup_export: []const u8,
};

const verbose_arg: args.Arg = .{
    .name = "verbose",
    .short = "-v",
    .long = "--verbose",
    .help = "Vebose output",
    .value = .{ .boolean = false },
};

const port_arg: args.Arg = .{
    .name = "port",
    .short = "-p",
    .long = "--port",
    .help = "Serial port",
    .value = .{ .string = "" },
};

const speed_arg: args.Arg = .{
    .name = "speed",
    .short = "-s",
    .long = "--speed",
    .help = "Serial speed",
    .value = .{ .number = 115200 },
};

const help_arg: args.Arg = .{
    .name = "help",
    .short = "-h",
    .long = "--help",
    .help = "Show help",
};

const common_args = .{
    .help = help_arg,
    .port = port_arg,
    .speed = speed_arg,
    .verbose = verbose_arg,
};

const cli_commands = .{
    .help = .{
        .name = "help",
        .help = "Get general help",
        .args = .{},
    },
    .info = .{
        .name = "info",
        .help = "Get Newton information",
        .args = .{},
    },
    .load = .{
        .name = "load",
        .help = "Load package",
        .args = .{},
    },
    .soup_export = .{
        .name = "export",
        .help = "Export soup",
        .args = .{
            args.Arg{
                .name = "convert",
                .short = "-c",
                .long = "--convert",
                .help = "Conversion format (only 'json' possible)",
                .value = .{ .string = "json" },
            },
        },
    },
};

const LogLayer = struct {
    enabled: bool = true,

    fn processEvent(self: *const LogLayer, event: event_queue.StackEvent) void {
        if (!self.enabled) {
            return;
        }
        std.debug.print("=====================================================\n", .{});
        std.debug.print("{}\n", .{event});
    }
};

var log_layer = LogLayer{ .enabled = false };

fn processStackEvents(file: std.posix.fd_t, command: Command, allocator: std.mem.Allocator) !void {
    while (event_queue.dequeue()) |event| {
        log_layer.processEvent(event);
        try framing_layer.processEvent(event, file);
        try mnp_layer.processEvent(event, allocator);
        try dock_layer.processEvent(event, allocator);
        try connect_module.processEvent(event, allocator);
        switch (command) {
            .load => |load| try load_package_module.processEvent(event, load.data, allocator),
            .info => try info_module.processEvent(event, allocator),
            .soup_export => |soup| try send_soup_module.processEvent(event, soup, allocator),
            else => {},
        }
        event.deinit(allocator);
    }
}

fn commandLoop() void {
    while (true) {
        var cmd: [80]u8 = undefined;
        std.log.info("Press <Enter> to stop.", .{});
        if (std.io.getStdIn().read(&cmd)) |_| {
            break;
        } else |_| {
            break;
        }
    }
}

fn openPort(port: ?args.Arg, speed: ?args.Arg) !std.posix.fd_t {
    const port_file = if (port) |p| p.value.string else if (builtin.os.tag == .windows) "COM1" else "/dev/ttyUSB0";
    const fd = try std.posix.open(port_file, .{ .ACCMODE = .RDWR}, 0);
    try serial.setSpeed(fd, if (speed) |s| @intCast(s.value.number) else 38400);
    return fd;
}

fn setupCommand(parsed_args: *args.ParsedArgs, allocator: std.mem.Allocator) !Command {
    var command: Command = .{ .info = true };
    if (std.mem.eql(u8, parsed_args.command, cli_commands.help.name)) {
        std.log.info("Usage...", .{});
        std.process.exit(0);
    } else if (std.mem.eql(u8, parsed_args.command, cli_commands.info.name)) {
        command = .{ .info = true };
        connect_module.session_type = .setting_up;
    } else if (std.mem.eql(u8, parsed_args.command, cli_commands.load.name)) {
        const file_name = parsed_args.parameters.items[0];
        const fd = try std.posix.open(file_name, .{ .ACCMODE = .RDONLY }, 0);
        defer std.posix.close(fd);
        const file_stat = try std.posix.fstat(fd);
        const package_data = try allocator.alloc(
            u8,
            @intCast((file_stat.size + 3) & 0xfffffffc),
        );
        _ = try std.posix.read(fd, package_data);
        command = .{ .load = .{ .file = file_name, .data = package_data } };
        connect_module.session_type = .load_package;
    } else if (std.mem.eql(u8, parsed_args.command, cli_commands.soup_export.name)) {
        command = .{ .soup_export = parsed_args.parameters.items[0] };
        connect_module.session_type = .synchronize;
    }
    if (parsed_args.args.get("verbose")) |_| {
        log_layer.enabled = true;
    }
    return command;
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var parsed_args = try args.process(cli_commands, common_args, arena.allocator());

    const command = try setupCommand(&parsed_args, arena.allocator());
    const file = try openPort(parsed_args.args.get("port"), parsed_args.args.get("speed"));
    defer std.posix.close(file);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    event_queue.init(allocator);
    var readerThread = try std.Thread.spawn(.{}, framing_layer.readerLoop, .{ file, allocator });
    var commandThread = try std.Thread.spawn(.{}, commandLoop, .{});
    var stackThread = try std.Thread.spawn(.{}, processStackEvents, .{ file, command, allocator });
    readerThread.detach();
    stackThread.detach();
    commandThread.join();
    _ = gpa.deinit();
    std.log.info("Done.", .{});
    std.posix.exit(0);
}
