const std = @import("std");
const event_queue = @import("./event_queue.zig");

fn handleIncomingPacket(packet: event_queue.MnpPacket, allocator: std.mem.Allocator) !void {
    var command: event_queue.DockPacket = .{
        .direction = .in,
        .length = packet.length - 12,
        .command = @intToEnum(event_queue.DockCommand, std.mem.readInt(u32, packet.data[8..12], .Big)),
        .data = try allocator.alloc(u8, packet.length - 12),
    };
    std.mem.copy(u8, command.data, packet.data[12..packet.length]);
    try event_queue.enqueue(.{ .dock = command });
}

pub fn handleOutgoingPacket(packet: event_queue.DockPacket, allocator: std.mem.Allocator) !void {
    var payload_length: u16 = @truncate(u16, packet.length + 16);
    var mnp_packet: event_queue.MnpPacket = .{
        .direction = .out,
        .length = (payload_length + 3) & 0xfffc,
    };
    mnp_packet.data = try allocator.alloc(u8, mnp_packet.length);
    std.mem.copy(u8, mnp_packet.data[0..8], &.{ 0x6e, 0x65, 0x77, 0x74, 0x64, 0x6f, 0x63, 0x6b });
    std.mem.writeInt(u32, mnp_packet.data[8..12], @enumToInt(packet.command), .Big);
    std.mem.writeInt(u32, mnp_packet.data[12..16], packet.length, .Big);
    std.mem.copy(u8, mnp_packet.data[16..payload_length], packet.data[0..packet.length]);
    try event_queue.enqueue(.{ .mnp = mnp_packet });
}

pub fn processEvent(event: event_queue.StackEvent, allocator: std.mem.Allocator) !void {
    switch (event) {
        .mnp => |packet| if (packet.direction == .in) try handleIncomingPacket(packet, allocator),
        .dock => |packet| if (packet.direction == .out) try handleOutgoingPacket(packet, allocator),
        else => {},
    }
}
