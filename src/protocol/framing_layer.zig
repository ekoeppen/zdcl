const std = @import("std");
const fsm = @import("../utils/fsm.zig");
const hexdump = @import("../utils/hexdump.zig");
const crc16 = @import("../utils/crc16.zig");
const event_queue = @import("./event_queue.zig");

const STX = 0x02;
const ETX = 0x03;
const DLE = 0x10;
const SYN = 0x16;

const State = enum {
    outside_packet,
    start_syn,
    start_dle,
    inside_packet,
    dle_in_packet,
    end_etx,
    end_crc1,
    packet_end,
};

const Action = enum {
    start_packet,
    add_byte,
    add_dle,
    update_calculated_crc,
    reset_received_crc,
    packet_done,
};

pub var packet: [512]u8 = undefined;
pub var packet_length: u9 = 0;
var received_crc: u16 = 0;
var calculated_crc: u16 = 0;

var unframingFsm: fsm.Fsm(u8, State, Action) = .{
    .state = .outside_packet,
    .transitions = &.{
        .{
            .state = .outside_packet,
            .actions = &.{
                .{ .event = SYN, .new_state = .start_syn },
            },
        },
        .{
            .state = .start_syn,
            .actions = &.{
                .{ .event = DLE, .new_state = .start_dle },
                .{ .new_state = .outside_packet },
            },
        },
        .{
            .state = .start_dle,
            .actions = &.{
                .{ .event = STX, .action = .start_packet, .new_state = .inside_packet },
                .{ .new_state = .outside_packet },
            },
        },
        .{
            .state = .inside_packet,
            .actions = &.{
                .{ .event = DLE, .new_state = .dle_in_packet },
                .{ .action = .add_byte, .new_state = .inside_packet },
            },
        },
        .{
            .state = .dle_in_packet,
            .actions = &.{
                .{ .event = DLE, .action = .add_dle, .new_state = .inside_packet },
                .{ .event = ETX, .action = .update_calculated_crc, .new_state = .end_etx },
                .{ .new_state = .outside_packet },
            },
        },
        .{
            .state = .end_etx,
            .actions = &.{
                .{ .action = .reset_received_crc, .new_state = .end_crc1 },
            },
        },
        .{
            .state = .end_crc1,
            .actions = &.{
                .{ .action = .packet_done, .new_state = .packet_end },
            },
        },
        .{
            .state = .packet_end,
            .actions = &.{
                .{ .event = SYN, .new_state = .start_syn },
                .{ .new_state = .outside_packet },
            },
        },
    },
};

var framingFsm: fsm.Fsm(u8, State, Action) = .{
    .state = .outside_packet,
    .transitions = &.{
        .{
            .state = .outside_packet,
            .actions = &.{
                .{ .action = .start_packet, .new_state = .inside_packet },
            },
        },
        .{
            .state = .inside_packet,
            .actions = &.{
                .{ .event = DLE, .action = .add_dle, .new_state = .inside_packet },
                .{ .action = .add_byte, .new_state = .inside_packet },
            },
        },
    },
};

fn addByte(byte: u8) void {
    packet[packet_length] = byte;
    packet_length += 1;
    calculated_crc = crc16.update(byte, calculated_crc);
}

fn addDle() void {
    packet[packet_length] = DLE;
    packet_length += 1;
}

fn input(byte: u8) bool {
    var packet_received = false;
    if (unframingFsm.input(byte)) |action| {
        switch (action) {
            .start_packet => {
                packet_length = 0;
                calculated_crc = 0;
            },
            .add_byte => addByte(byte),
            .add_dle => addDle(),
            .update_calculated_crc => calculated_crc = crc16.update(byte, calculated_crc),
            .reset_received_crc => received_crc = byte,
            .packet_done => {
                received_crc = received_crc + 256 * @intCast(u16, byte);
                packet_received = true;
            },
        }
    }
    return packet_received;
}

pub fn write(serial_packet: *const event_queue.SerialPacket, file: std.os.fd_t) !void {
    var out = [1]u8{0};
    var crc: u16 = 0;
    framingFsm.state = .outside_packet;
    for (serial_packet.data[0..serial_packet.length]) |byte| {
        if (framingFsm.input(byte)) |action| {
            switch (action) {
                .start_packet => {
                    crc = crc16.update(byte, crc);
                    _ = try std.os.write(file, &.{ SYN, DLE, STX, byte });
                },
                .add_byte => {
                    out[0] = byte;
                    crc = crc16.update(byte, crc);
                    _ = try std.os.write(file, &out);
                },
                .add_dle => {
                    out[0] = DLE;
                    crc = crc16.update(byte, crc);
                    _ = try std.os.write(file, &out);
                    _ = try std.os.write(file, &out);
                },
                .update_calculated_crc => {},
                .reset_received_crc => {},
                .packet_done => {},
            }
        }
    }
    crc = crc16.update(ETX, crc);
    _ = try std.os.write(file, &.{ DLE, ETX, @intCast(u8, crc & 0xff), @intCast(u8, crc >> 8) });
}

pub fn readerLoop(file: std.os.fd_t, allocator: std.mem.Allocator) !void {
    var serial_buffer: [1]u8 = undefined;
    read_loop: while (true) {
        if (std.os.read(file, &serial_buffer)) |num_bytes| {
            if (num_bytes == 0) {
                continue :read_loop;
            }
            if (input(serial_buffer[0])) {
                std.debug.print("\n", .{});
                var stack_event = try allocator.create(event_queue.StackEvent);
                var serial_packet: event_queue.SerialPacket = .{
                    .source = .serial,
                    .length = packet_length,
                };
                std.mem.copy(u8, &serial_packet.data, packet[0..serial_packet.length]);
                stack_event.* = .{ .serial = serial_packet };
                try event_queue.enqueue(stack_event);
            }
        } else |_| {
            break :read_loop;
        }
    }
}

pub fn processEvent(event: *event_queue.StackEvent, file: std.os.fd_t) !void {
    switch (event.*) {
        .serial => |serial| if (serial.source == .mnp) {
            try write(&serial, file);
        },
        else => {},
    }
}
