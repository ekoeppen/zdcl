const std = @import("std");
const fsm = @import("../utils/fsm.zig");
const queue = @import("../utils/queue.zig");
const event_queue = @import("./event_queue.zig");

const State = enum {
    idle,
    data_phase,
};

const Action = enum {
    handle_link_request,
    handle_link_acknowledgement,
    handle_link_transfer,
    close_connection,
};

const LR: u8 = 0x01;
const LD: u8 = 0x02;
const LT: u8 = 0x04;
const LA: u8 = 0x05;

var peer_receive_sequence_number: u8 = 0;
var receive_credit_number: u8 = 0;
var peer_send_sequence_number: u8 = 0;
var local_send_sequence_number: u8 = 1;

var framing_mode: u8 = undefined;
var max_outstanding_packets: u8 = undefined;
var max_info_field: u16 = undefined;
var data_phase_opt: u8 = undefined;

var backlog: queue.Queue(event_queue.SerialPacket) = undefined;

var mnp_fsm: fsm.Fsm(u8, State, Action) = .{
    .state = .idle,
    .transitions = &.{
        .{
            .state = .idle,
            .actions = &.{
                .{ .event = LR, .action = .handle_link_request, .new_state = .idle },
                .{ .event = LA, .new_state = .data_phase },
                .{ .event = LD, .new_state = .idle },
                .{ .event = LT, .new_state = .idle },
            },
        },
        .{
            .state = .data_phase,
            .actions = &.{
                .{ .event = LR, .new_state = .idle },
                .{ .event = LA, .action = .handle_link_acknowledgement, .new_state = .data_phase },
                .{ .event = LD, .action = .close_connection, .new_state = .idle },
                .{ .event = LT, .action = .handle_link_transfer, .new_state = .data_phase },
            },
        },
    },
};

fn handleLinkRequest(packet: event_queue.SerialPacket, allocator: std.mem.Allocator) !void {
    framing_mode = packet.data[13];
    max_outstanding_packets = packet.data[16];
    receive_credit_number = max_outstanding_packets;
    max_info_field = @intCast(u16, packet.data[19]) * 256 + packet.data[20];
    data_phase_opt = packet.data[23];
    var response: event_queue.SerialPacket = .{ .direction = .out, .length = 24 };
    response.data = try allocator.alloc(u8, response.length);
    std.mem.copy(u8, response.data, &.{
        23, LR, 2, 1, 6, 1, 0, 0, 0,  0, 255, //
        2,  1,  2, 3, 1, 8, 4, 2, 64, 0, 8,
        1,  3,
    });
    try event_queue.enqueue(.{ .serial = response });
    backlog = .{ .allocator = allocator };
}

fn sendLinkAcknowledgement(sequence_number: u8, credit: u8, allocator: std.mem.Allocator) !void {
    var response: event_queue.SerialPacket = .{ .direction = .out, .length = 4 };
    response.data = try allocator.alloc(u8, response.length);
    std.mem.copy(u8, response.data, &.{ 3, LA, sequence_number, credit });
    try event_queue.enqueue(.{ .serial = response });
}

fn handleLinkTransfer(packet: event_queue.SerialPacket, allocator: std.mem.Allocator) !void {
    var mnp_packet: event_queue.MnpPacket = .{ .direction = .in, .length = packet.length - 3 };
    mnp_packet.data = try allocator.alloc(u8, mnp_packet.length);
    peer_send_sequence_number = packet.data[2];
    try sendLinkAcknowledgement(peer_send_sequence_number, 8, allocator);
    std.mem.copy(u8, mnp_packet.data, packet.data[3..packet.length]);
    try event_queue.enqueue(.{ .mnp = mnp_packet });
}

fn handleLinkAcknowledgement(packet: event_queue.SerialPacket) !void {
    peer_receive_sequence_number = packet.data[2];
    receive_credit_number += packet.data[3];
    if (receive_credit_number > 8) receive_credit_number = 8;
    send_backlog: while (receive_credit_number > 0) {
        if (backlog.dequeue()) |serial_packet| {
            try event_queue.enqueue(.{ .serial = serial_packet });
            receive_credit_number -|= 1;
        } else {
            break :send_backlog;
        }
    }
}

fn processSerial(packet: event_queue.SerialPacket, allocator: std.mem.Allocator) !void {
    if (mnp_fsm.input(packet.data[1])) |action| {
        switch (action) {
            .handle_link_request => try handleLinkRequest(packet, allocator),
            .handle_link_transfer => try handleLinkTransfer(packet, allocator),
            .handle_link_acknowledgement => try handleLinkAcknowledgement(packet),
            .close_connection => std.os.exit(0),
        }
    }
}

fn sendLinkTransfer(data: []const u8, allocator: std.mem.Allocator) !void {
    var serial_packet: event_queue.SerialPacket = .{
        .direction = .out,
        .length = @truncate(u16, data.len + 3),
    };
    serial_packet.data = try allocator.alloc(u8, serial_packet.length);
    std.mem.copy(u8, serial_packet.data[0..3], &.{ 2, LT, local_send_sequence_number });
    std.mem.copy(u8, serial_packet.data[3..serial_packet.length], data);
    local_send_sequence_number +%= 1;
    if (receive_credit_number > 0) {
        try event_queue.enqueue(.{ .serial = serial_packet });
        receive_credit_number -|= 1;
    } else {
        try backlog.enqueue(serial_packet);
    }
}

fn processMnp(packet: event_queue.MnpPacket, allocator: std.mem.Allocator) !void {
    var offset: usize = 0;
    var remaining: usize = packet.length;
    while (remaining > 0) {
        var length = if (remaining > max_info_field) max_info_field else remaining;
        try sendLinkTransfer(packet.data[offset .. offset + length], allocator);
        offset += length;
        remaining -|= length;
    }
}

pub fn processEvent(event: event_queue.StackEvent, allocator: std.mem.Allocator) !void {
    switch (event) {
        .serial => |serial| if (serial.direction == .in) try processSerial(serial, allocator),
        .mnp => |mnp| if (mnp.direction == .out) try processMnp(mnp, allocator),
        else => {},
    }
}
