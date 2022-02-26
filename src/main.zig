const std = @import("std");
const builtin = @import("builtin");
const framing_layer = @import("./protocol/framing_layer.zig");
const mnp_layer = @import("./protocol/mnp_layer.zig");
const dock_layer = @import("./protocol/dock_layer.zig");
const connect_module = @import("./protocol/connect_module.zig");
const event_queue = @import("./protocol/event_queue.zig");

const Arg = struct {
    short: ?[]const u8 = null,
    long: ?[]const u8 = null,
    help: ?[]const u8 = null,
    value: union(enum) {
        present: bool,
        number: i32,
        boolean: bool,
        string: []u8,
    } = .{ .present = false },

    fn matches(self: *Arg, parameter: []const u8) bool {
        if (self.short) |short| {
            if (std.mem.eql(u8, short, parameter)) return true;
        }
        if (self.long) |long| {
            if (std.mem.eql(u8, long, parameter)) return true;
        }
        return false;
    }

    fn setFromIter(self: *Arg, iter: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
        switch (self.value) {
            .number => {
                var arg = try iter.next(allocator) orelse {
                    std.log.err("Missing argument for {s} {s}", .{ self.short, self.long });
                    return error.InvalidArgs;
                };
                defer allocator.free(arg);
                self.value = .{ .number = try std.fmt.parseInt(i32, arg, 10) };
            },
            .string => {
                var arg = try iter.next(allocator) orelse {
                    std.log.err("Missing argument for {s} {s}", .{ self.short, self.long });
                    return error.InvalidArgs;
                };
                self.value = .{ .string = arg };
            },
            .boolean => self.value = .{ .boolean = true },
            .present => self.value = .{ .present = true },
        }
    }
};

var args: [3]Arg = .{ //
    .{ .short = "-h", .long = "--help-package", .help = "Show help" },
    .{ .short = "-l", .long = "--load-package", .help = "Load package", .value = .{ .string = "" } },
    .{
        .short = "-t",
        .long = "--timeout",
        .help = "Connection timeout in seconds",
        .value = .{ .number = 15 },
    },
};

var named_args = .{
    .help = Arg{ //
        .short = "-h",
        .long = "--help-package",
        .help = "Show help",
    },
    .load_package = Arg{ //
        .short = "-l",
        .long = "--load-package",
        .help = "Load package",
        .value = .{ .string = "" },
    },
    .timeout = Arg{ //
        .short = "-t",
        .long = "--timeout",
        .help = "Connection timeout in seconds",
        .value = .{ .number = 15 },
    },
};

fn processArgs(allocator: std.mem.Allocator) !void {
    var iter = std.process.args();
    parse_args: while (true) {
        var arg = try iter.next(allocator) orelse {
            break :parse_args;
        };
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            if (args[i].matches(arg)) {
                try args[i].setFromIter(&iter, allocator);
                continue :parse_args;
            }
        }
        allocator.free(arg);
    }
}

fn processNamedArgs(allocator: std.mem.Allocator) !void {
    var iter = std.process.args();
    parse_args: while (true) {
        var arg = try iter.next(allocator) orelse {
            break :parse_args;
        };
        inline for (@typeInfo(@TypeOf(named_args)).Struct.fields) |field| {
            var named_arg: *Arg = &@field(named_args, field.name);
            if (named_arg.matches(arg)) {
                try Arg.setFromIter(named_arg, &iter, allocator);
                continue :parse_args;
            }
        }
        allocator.free(arg);
    }
}

const LogLayer = struct {
    enabled: bool = true,

    fn processEvent(self: *LogLayer, event: event_queue.StackEvent) void {
        if (!self.enabled) {
            return;
        }
        std.debug.print("=====================================================\n", .{});
        std.debug.print("{s}\n", .{event});
    }
};

var log_layer = LogLayer{};

fn processStackEvents(file: std.os.fd_t, allocator: std.mem.Allocator) !void {
    while (event_queue.dequeue()) |event| {
        log_layer.processEvent(event);
        try framing_layer.processEvent(event, file);
        try mnp_layer.processEvent(event, allocator);
        try dock_layer.processEvent(event, allocator);
        try connect_module.processEvent(event, allocator);
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

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try processNamedArgs(arena.allocator());
    std.log.info("{s}", .{named_args.load_package.value.string});
    std.log.info("{d}", .{named_args.timeout.value.number});

    var file: std.os.fd_t = undefined;
    if (builtin.os.tag == .windows) {
        file = try std.os.open("COM1:", std.os.O.RDWR, 0);
    } else {
        file = try std.os.open("/tmp/einstein-extr.pty", std.os.O.RDWR, 0o664);
    }
    defer std.os.close(file);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    event_queue.init(allocator);
    var readerThread = try std.Thread.spawn(.{}, framing_layer.readerLoop, .{ file, allocator });
    var commandThread = try std.Thread.spawn(.{}, commandLoop, .{});
    var stackThread = try std.Thread.spawn(.{}, processStackEvents, .{ file, allocator });
    readerThread.detach();
    stackThread.detach();
    commandThread.join();
    std.log.info("Done.", .{});
    _ = gpa.deinit();
    std.os.exit(0);
}
