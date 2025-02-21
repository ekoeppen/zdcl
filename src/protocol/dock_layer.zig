const std = @import("std");
const event_queue = @import("./event_queue.zig");

var active_packet: event_queue.DockPacket = .{};

fn handleIncomingPacket(packet: event_queue.MnpPacket, allocator: std.mem.Allocator) !void {
    if (active_packet.length == 0) {
        const length = std.mem.readInt(u32, packet.data[12..16], .big);
        active_packet = try event_queue.DockPacket.init(
            @enumFromInt(std.mem.readInt(u32, packet.data[8..12], .big)),
            .in,
            packet.data[16..packet.length],
            allocator,
        );
        active_packet.length = length;
    } else {
        const current = active_packet.data.len;
        active_packet.data = try allocator.realloc(active_packet.data, active_packet.data.len + packet.data.len);
        std.mem.copyForwards(u8, active_packet.data[current..], packet.data);
    }
    if (active_packet.data.len >= active_packet.length) {
        try event_queue.enqueue(.{ .dock = active_packet });
        active_packet.length = 0;
    }
}

pub fn handleOutgoingPacket(packet: event_queue.DockPacket, allocator: std.mem.Allocator) !void {
    const payload_length: u16 = @truncate(packet.length + 16);
    var mnp_packet: event_queue.MnpPacket = .{
        .direction = .out,
        .length = (payload_length + 3) & 0xfffc,
    };
    mnp_packet.data = try allocator.alloc(u8, mnp_packet.length);
    @memset(mnp_packet.data, 0);
    std.mem.copyForwards(u8, mnp_packet.data[0..8], &.{ 0x6e, 0x65, 0x77, 0x74, 0x64, 0x6f, 0x63, 0x6b });
    std.mem.writeInt(u32, mnp_packet.data[8..12], @intFromEnum(packet.command), .big);
    std.mem.writeInt(u32, mnp_packet.data[12..16], packet.length, .big);
    std.mem.copyForwards(u8, mnp_packet.data[16..payload_length], packet.data[0..packet.length]);
    try event_queue.enqueue(.{ .mnp = mnp_packet });
}

pub fn processEvent(event: event_queue.StackEvent, allocator: std.mem.Allocator) !void {
    switch (event) {
        .mnp => |packet| if (packet.direction == .in) try handleIncomingPacket(packet, allocator),
        .dock => |packet| if (packet.direction == .out) try handleOutgoingPacket(packet, allocator),
        else => {},
    }
}
