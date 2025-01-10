const std = @import("std");
const fsm = @import("../utils/fsm.zig");
const queue = @import("../utils/queue.zig");
const event_queue = @import("./event_queue.zig");

const SerialPacket = event_queue.SerialPacket;
const MnpPacket = event_queue.MnpPacket;

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

var backlog: queue.Queue(SerialPacket) = undefined;

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

fn handleLinkRequest(packet: SerialPacket, allocator: std.mem.Allocator) !void {
    framing_mode = packet.data[13];
    max_outstanding_packets = 1;
    receive_credit_number = max_outstanding_packets;
    data_phase_opt = packet.data[23];
    max_info_field = if (data_phase_opt & 1 == 1) 256 else @as(u16, @intCast(packet.data[19])) * 256 + packet.data[20];
    const response = try SerialPacket.init(.out, &.{
        23, LR, 2, 1, 6, 1, 0, 0, 0,  0, 255,
        2,  1,  2, 3, 1, 8, 4, 2, 64, 0, 8,
        1,  3,
    }, allocator);
    try event_queue.enqueue(.{ .serial = response });
    backlog = .{ .allocator = allocator };
}

fn sendLinkAcknowledgement(sequence_number: u8, credit: u8, allocator: std.mem.Allocator) !void {
    const response = try SerialPacket.init(.out, &.{ 3, LA, sequence_number, credit }, allocator);
    try event_queue.enqueue(.{ .serial = response });
}

fn handleLinkTransfer(packet: SerialPacket, allocator: std.mem.Allocator) !void {
    const mnp_packet = try MnpPacket.init(.in, packet.data[3..packet.length], allocator);
    try event_queue.enqueue(.{ .mnp = mnp_packet });
    peer_send_sequence_number = packet.data[2];
    try sendLinkAcknowledgement(peer_send_sequence_number, 8, allocator);
}

fn handleLinkAcknowledgement(packet: SerialPacket) !void {
    peer_receive_sequence_number = packet.data[2];
    receive_credit_number = packet.data[3];
    if (receive_credit_number > max_outstanding_packets) receive_credit_number = max_outstanding_packets;
    send_backlog: while (receive_credit_number > 0) {
        if (backlog.dequeue()) |serial_packet| {
            try event_queue.enqueue(.{ .serial = serial_packet });
            receive_credit_number -|= 1;
        } else {
            break :send_backlog;
        }
    }
}

fn processSerial(packet: SerialPacket, allocator: std.mem.Allocator) !void {
    if (mnp_fsm.input(packet.data[1])) |action| {
        switch (action) {
            .handle_link_request => try handleLinkRequest(packet, allocator),
            .handle_link_transfer => try handleLinkTransfer(packet, allocator),
            .handle_link_acknowledgement => try handleLinkAcknowledgement(packet),
            .close_connection => std.process.exit(0),
        }
    }
}

fn sendLinkTransfer(data: []const u8, allocator: std.mem.Allocator) !void {
    var serial_packet: SerialPacket = .{
        .direction = .out,
        .length = @truncate(data.len + 3),
    };
    serial_packet.data = try allocator.alloc(u8, serial_packet.length);
    std.mem.copyForwards(u8, serial_packet.data[0..3], &.{ 2, LT, local_send_sequence_number });
    std.mem.copyForwards(u8, serial_packet.data[3..serial_packet.length], data);
    local_send_sequence_number +%= 1;
    if (receive_credit_number > 0) {
        try event_queue.enqueue(.{ .serial = serial_packet });
        receive_credit_number -|= 1;
    } else {
        try backlog.enqueue(serial_packet);
    }
}

fn processMnp(packet: MnpPacket, allocator: std.mem.Allocator) !void {
    var offset: usize = 0;
    var remaining: usize = packet.length;
    while (remaining > 0) {
        const length = if (remaining > max_info_field) max_info_field else remaining;
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
