const std = @import("std");
const builtin = @import("builtin");
const framing_layer = @import("./protocol/framing_layer.zig");
const mnp_layer = @import("./protocol/mnp_layer.zig");
const dock_layer = @import("./protocol/dock_layer.zig");
const connect_module = @import("./protocol/connect_module.zig");
const event_queue = @import("./protocol/event_queue.zig");

const LogLayer = struct {
    enabled: bool = true,

    fn processEvent(self: *LogLayer, event: *event_queue.StackEvent) void {
        if (!self.enabled) {
            return;
        }
        std.debug.print("=====================================================\n", .{});
        std.debug.print("{s}\n", .{event});
    }
};

var log_layer = LogLayer{};
var allocator: std.mem.Allocator = undefined;
var file: std.os.fd_t = undefined;

fn processStackEvents() !void {
    while (event_queue.dequeue()) |event| {
        log_layer.processEvent(event);
        try framing_layer.processEvent(event, file);
        try mnp_layer.processEvent(event, allocator);
        try dock_layer.processEvent(event, allocator);
        try connect_module.processEvent(event, allocator);
        event.deinit(allocator);
        allocator.destroy(event);
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
    if (builtin.os.tag == .windows) {
        file = try std.os.open("COM1:", std.os.O.RDWR, 0);
    } else {
        file = try std.os.open("/tmp/einstein-extr.pty", std.os.O.RDWR, 0o664);
    }
    defer std.os.close(file);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = gpa.allocator();

    event_queue.init(allocator);
    var readerThread = try std.Thread.spawn(.{}, framing_layer.readerLoop, .{ file, allocator });
    var commandThread = try std.Thread.spawn(.{}, commandLoop, .{});
    var stackThread = try std.Thread.spawn(.{}, processStackEvents, .{});
    readerThread.detach();
    stackThread.detach();
    commandThread.join();
    std.log.info("Done.", .{});
    _ = gpa.deinit();
    std.os.exit(0);
}
