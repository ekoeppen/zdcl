const std = @import("std");
const fsm = @import("../utils/fsm.zig");
const event_queue = @import("../protocol/event_queue.zig");
const dock_layer = @import("../protocol/dock_layer.zig");

const AppEvent = event_queue.AppEvent;
const DockPacket = event_queue.DockPacket;

const State = enum {
    idle,
    installing,
    sent,
};

const Action = enum {
    send_request,
    send_data,
    ack_cancel,
    install_done,
};

var install_fsm: fsm.Fsm(event_queue.DockCommand, State, Action) = .{
    .state = .idle,
    .transitions = &.{
        .{
            .state = .idle,
            .actions = &.{},
        },
        .{
            .state = .installing,
            .actions = &.{
                .{ .event = .result, .action = .send_data, .new_state = .sent },
            },
        },
        .{
            .state = .sent,
            .actions = &.{
                .{ .event = .result, .action = .install_done, .new_state = .idle },
            },
        },
        .{
            .actions = &.{
                .{ .event = .operation_canceled, .action = .ack_cancel, .new_state = .idle },
                .{ .event = .op_canceled_ack, .action = .ack_cancel, .new_state = .idle },
                .{ .event = .op_canceled_ack_2, .action = .ack_cancel, .new_state = .idle },
            },
        },
    },
};

fn handleDockCommand(packet: DockPacket, data: []const u8, allocator: std.mem.Allocator) !void {
    if (install_fsm.input(packet.command)) |action| {
        switch (action) {
            .send_data => {
                var dock_packet = try DockPacket.init(.load_package, .out, data, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .install_done => {
                var dock_packet = try DockPacket.init(.disconnect, .out, &.{}, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .ack_cancel => {
                var dock_packet = try DockPacket.init(.op_canceled_ack, .out, &.{}, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            else => {},
        }
    }
}

pub fn processEvent(event: event_queue.StackEvent, data: []const u8, allocator: std.mem.Allocator) !void {
    switch (event) {
        .app => |app| if (app.direction == .in and app.event == .connected) {
            var dock_packet = try DockPacket.init(.request_to_install, .out, &.{}, allocator);
            try event_queue.enqueue(.{ .dock = dock_packet });
            install_fsm.state = .installing;
        },
        .dock => |packet| if (packet.direction == .in) try handleDockCommand(packet, data, allocator),
        else => {},
    }
}
