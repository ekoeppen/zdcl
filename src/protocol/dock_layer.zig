const std = @import("std");
const event_queue = @import("./event_queue.zig");

fn storeInt(dst: *[4]u8, n: u32) void {
    dst[0] = @intCast(u8, (n >> 24) & 0xff);
    dst[1] = @intCast(u8, (n >> 16) & 0xff);
    dst[2] = @intCast(u8, (n >> 8) & 0xff);
    dst[3] = @intCast(u8, n & 0xff);
}

fn fetchInt(src: *const [4]u8) u32 {
    return (@as(u32, src[0]) << 24) +
        (@as(u32, src[1]) << 16) +
        (@as(u32, src[2]) << 8) +
        @as(u32, src[3]);
}

fn handleIncomingPacket(packet: *const event_queue.MnpPacket, allocator: std.mem.Allocator) !void {
    if (packet.source != .mnp) {
        return;
    }
    var command: event_queue.DockPacket = .{
        .source = .dock,
        .length = packet.length - 12,
        .command = @intToEnum(event_queue.DockCommand, fetchInt(packet.data[8..12])),
    };
    std.mem.copy(u8, &command.data, packet.data[12..packet.length]);
    var stack_event = try allocator.create(event_queue.StackEvent);
    stack_event.* = .{ .dock = command };
    try event_queue.events.enqueue(stack_event);
}

pub fn send(packet: *const event_queue.DockPacket, allocator: std.mem.Allocator) !void {
    var payload_length: u16 = packet.length + 16;
    var mnp_packet: event_queue.MnpPacket = .{
        .source = .dock,
        .length = (payload_length + 3) & 0xfffc,
    };
    var c: u32 = @enumToInt(packet.command);
    var l: u32 = packet.length;
    std.mem.copy(u8, mnp_packet.data[0..8], &.{ 0x6e, 0x65, 0x77, 0x74, 0x64, 0x6f, 0x63, 0x6b });
    storeInt(mnp_packet.data[8..12], c);
    storeInt(mnp_packet.data[12..16], l);
    std.mem.copy(u8, mnp_packet.data[16..payload_length], packet.data[0..packet.length]);
    var stack_event = try allocator.create(event_queue.StackEvent);
    stack_event.* = .{ .mnp = mnp_packet };
    try event_queue.events.enqueue(stack_event);
}

pub fn processEvent(event: *event_queue.StackEvent, allocator: std.mem.Allocator) !void {
    switch (event.*) {
        .mnp => |packet| try handleIncomingPacket(&packet, allocator),
        else => {},
    }
}
