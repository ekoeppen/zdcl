const std = @import("std");
const builtin = @import("builtin");
const framing_layer = @import("./protocol/framing_layer.zig");
const mnp_layer = @import("./protocol/mnp_layer.zig");
const dock_layer = @import("./protocol/dock_layer.zig");
const connect_module = @import("./protocol/connect_module.zig");
const load_package_module = @import("./protocol/load_package_module.zig");
const event_queue = @import("./protocol/event_queue.zig");
const args = @import("./utils/args.zig");

const Command = union(enum) {
    load: struct { file: []const u8, data: []const u8 = undefined },
    info: bool,
    sync: bool,
    soup_export: struct { soup: []const u8, file: []const u8 },
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

const load_cli_command: args.Command = .{
    .name = "load",
    .help = "Load package",
    .args = .{},
};

const info_cli_command: args.Command = .{
    .name = "info",
    .help = "Get Newton information",
    .args = .{},
};

const help_cli_command: args.Command = .{
    .name = "help",
    .help = "Get general help",
    .args = .{},
};

const common_args = .{
    .help = help_arg,
    .port = port_arg,
    .speed = speed_arg,
};

const cli_commands = .{
    .help = help_cli_command,
    .info = info_cli_command,
    .load = load_cli_command,
};

const LogLayer = struct {
    enabled: bool = true,

    fn processEvent(self: *const LogLayer, event: event_queue.StackEvent) void {
        if (!self.enabled) {
            return;
        }
        std.debug.print("=====================================================\n", .{});
        std.debug.print("{s}\n", .{event});
    }
};

const log_layer = LogLayer{};

fn processStackEvents(file: std.os.fd_t, command: Command, allocator: std.mem.Allocator) !void {
    while (event_queue.dequeue()) |event| {
        log_layer.processEvent(event);
        try framing_layer.processEvent(event, file);
        try mnp_layer.processEvent(event, allocator);
        try dock_layer.processEvent(event, allocator);
        try connect_module.processEvent(event, allocator);
        switch (command) {
            .load => |load| try load_package_module.processEvent(event, load.data, allocator),
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

fn openPort(arg: ?args.Arg) !std.os.fd_t {
    var port = if (arg) |a| a.value.string else if (builtin.os.tag == .windows) "COM1" else "/dev/ttyUSB0";
    return try std.os.open(port, std.os.O.RDWR, 0);
}

fn setupCommand(parsed_args: *args.ParsedArgs, allocator: std.mem.Allocator) !Command {
    var command: Command = .{ .info = true };
    if (std.mem.eql(u8, parsed_args.command, help_cli_command.name)) {
        std.log.info("Usage...", .{});
        std.os.exit(0);
    } else if (std.mem.eql(u8, parsed_args.command, info_cli_command.name)) {
        command = .{ .info = true };
        connect_module.session_type = .setting_up;
    } else if (std.mem.eql(u8, parsed_args.command, load_cli_command.name)) {
        const file_name = parsed_args.parameters.items[0];
        const fd = try std.os.open(file_name, std.os.O.RDONLY, 0);
        defer std.os.close(fd);
        const file_stat = try std.os.fstat(fd);
        var package_data = try allocator.alloc(u8, @intCast(u32, (file_stat.size + 3) & 0xfffffffc));
        _ = try std.os.read(fd, package_data);
        command = .{ .load = .{ .file = file_name, .data = package_data } };
        connect_module.session_type = .load_package;
    }
    return command;
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var parsed_args = try args.process(cli_commands, common_args, arena.allocator());

    var command = try setupCommand(&parsed_args, arena.allocator());
    var file = try openPort(parsed_args.args.get("port"));
    defer std.os.close(file);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    event_queue.init(allocator);
    var readerThread = try std.Thread.spawn(.{}, framing_layer.readerLoop, .{ file, allocator });
    var commandThread = try std.Thread.spawn(.{}, commandLoop, .{});
    var stackThread = try std.Thread.spawn(.{}, processStackEvents, .{ file, command, allocator });
    readerThread.detach();
    stackThread.detach();
    commandThread.join();
    _ = gpa.deinit();
    std.log.info("Done.", .{});
    std.os.exit(0);
}
