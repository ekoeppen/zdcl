const std = @import("std");
const fsm = @import("../utils/fsm.zig");
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
var outstanding_packets: u8 = undefined;
var max_info_field: u16 = undefined;
var data_phase_opt: u8 = undefined;

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
    outstanding_packets = packet.data[16];
    max_info_field = @intCast(u16, packet.data[19]) * 256 + packet.data[20];
    data_phase_opt = packet.data[23];
    var response: event_queue.SerialPacket = .{
        .source = .mnp,
        .length = 24,
    };
    std.mem.copy(u8, &response.data, &.{
        23, LR, 2, 1, 6, 1, 0, 0, 0,  0, 255, //
        2,  1,  2, 3, 1, 8, 4, 2, 64, 0, 8,
        1,  3,
    });
    var stack_event = try allocator.create(event_queue.StackEvent);
    stack_event.* = .{ .serial = response };
    try event_queue.events.enqueue(stack_event);
}

fn sendLinkAcknowledgement(sequence_number: u8, credit: u8, allocator: std.mem.Allocator) !void {
    var response: event_queue.SerialPacket = .{
        .source = .mnp,
        .length = 4,
    };
    std.mem.copy(u8, &response.data, &.{ 3, LA, sequence_number, credit });
    var stack_event = try allocator.create(event_queue.StackEvent);
    stack_event.* = .{ .serial = response };
    try event_queue.events.enqueue(stack_event);
}

fn handleLinkTransfer(packet: event_queue.SerialPacket, allocator: std.mem.Allocator) !void {
    var mnp_packet: event_queue.MnpPacket = .{
        .source = .mnp,
        .length = packet.length - 3,
    };
    peer_send_sequence_number = packet.data[2];
    try sendLinkAcknowledgement(peer_send_sequence_number, 8, allocator);
    std.mem.copy(u8, &mnp_packet.data, packet.data[3..packet.length]);
    var stack_event = try allocator.create(event_queue.StackEvent);
    stack_event.* = .{ .mnp = mnp_packet };
    try event_queue.events.enqueue(stack_event);
}

fn processSerial(packet: event_queue.SerialPacket, allocator: std.mem.Allocator) !void {
    if (packet.source != .serial) {
        return;
    }
    if (mnp_fsm.input(packet.data[1])) |action| {
        switch (action) {
            .handle_link_request => try handleLinkRequest(packet, allocator),
            .handle_link_transfer => try handleLinkTransfer(packet, allocator),
            .handle_link_acknowledgement => {
                peer_receive_sequence_number = packet.data[2];
                receive_credit_number = packet.data[3];
            },
            .close_connection => std.os.exit(0),
        }
    }
}

fn processMnp(packet: event_queue.MnpPacket, allocator: std.mem.Allocator) !void {
    if (packet.source != .dock) {
        return;
    }
    if (packet.length + 3 > 65536) {
        return error.Overflow;
    }
    var serial_packet: event_queue.SerialPacket = .{
        .source = .mnp,
        .length = @truncate(u16, packet.length + 3),
    };
    serial_packet.data[0] = 2;
    serial_packet.data[1] = 4;
    serial_packet.data[2] = local_send_sequence_number;
    local_send_sequence_number +%= 1;
    std.mem.copy(u8, serial_packet.data[3..serial_packet.length], packet.data[0..packet.length]);
    var stack_event = try allocator.create(event_queue.StackEvent);
    stack_event.* = .{ .serial = serial_packet };
    try event_queue.events.enqueue(stack_event);
}

pub fn processEvent(event: *event_queue.StackEvent, allocator: std.mem.Allocator) !void {
    switch (event.*) {
        .serial => try processSerial(event.serial, allocator),
        .mnp => try processMnp(event.mnp, allocator),
        else => {},
    }
}
