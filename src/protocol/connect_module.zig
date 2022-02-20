const std = @import("std");
const event_queue = @import("./event_queue.zig");
const fsm = @import("../utils/fsm.zig");
const dock_layer = @import("./dock_layer.zig");
const des = @import("../utils/des.zig");

const State = enum {
    idle,
    initiate,
    desktop_info,
    which_icons,
    set_timeout,
    password,
    up,
};

const Action = enum {
    request_to_dock,
    desktop_info,
    which_icons,
    set_timeout,
    password,
    disconnect,
};

const session_none: u8 = 0;
const session_setting_up: u8 = 1;
const desktop_mac: u8 = 0;
const protocol_version: u8 = 10;
const all_icons: u8 = 63;
const dock_timeout: u8 = 5;

var challenge: [8]u8 = undefined;

var connect_fsm: fsm.Fsm(event_queue.DockCommand, State, Action) = .{
    .state = .idle,
    .transitions = &.{
        .{
            .state = .idle,
            .actions = &.{
                .{ .event = .request_to_dock, .action = .request_to_dock, .new_state = .initiate },
            },
        },
        .{
            .state = .initiate,
            .actions = &.{
                .{ .event = .newton_name, .action = .desktop_info, .new_state = .desktop_info },
            },
        },
        .{
            .state = .desktop_info,
            .actions = &.{
                .{ .event = .newton_info, .action = .which_icons, .new_state = .which_icons },
            },
        },
        .{
            .state = .which_icons,
            .actions = &.{
                .{ .event = .result, .action = .set_timeout, .new_state = .set_timeout },
            },
        },
        .{
            .state = .set_timeout,
            .actions = &.{
                .{ .event = .password, .action = .password, .new_state = .up },
            },
        },
        .{
            .state = .up,
            .actions = &.{
                .{ .event = .disconnect, .action = .disconnect, .new_state = .idle },
            },
        },
        .{
            .actions = &.{
                .{ .event = .disconnect, .action = .disconnect, .new_state = .idle },
            },
        },
    },
};

fn encrypt(in: *[8]u8, out: *[8]u8) void {
    var d: des.DES = des.DES.init(.{ 0xe4, 0x0f, 0x7e, 0x9f, 0x0a, 0x36, 0x2c, 0xfa });
    d.crypt(.Encrypt, out, in);
}

fn handleDockCommand(packet: *const event_queue.DockPacket, allocator: std.mem.Allocator) !void {
    _ = allocator;
    if (packet.source != .dock) {
        return;
    }
    if (connect_fsm.input(packet.command)) |action| {
        switch (action) {
            .request_to_dock => {
                try dock_layer.send(&event_queue.DockPacket{
                    .source = .dock,
                    .command = .dock,
                    .data = [_]u8{ 0, 0, 0, 1 } ++ [_]u8{0} ** 65532,
                    .length = 4,
                }, allocator);
            },
            .desktop_info => {
                try dock_layer.send(&event_queue.DockPacket{
                    .source = .dock,
                    .command = .desktop_info,
                    .data = [110]u8{
                        0, 0, 0, protocol_version, //
                        0, 0, 0, desktop_mac, //
                        0x64, 0x23, 0xef, 0x02, //
                        0xfb, 0xcd, 0xc5, 0xa5, //
                        0, 0, 0, session_setting_up, //
                        0, 0, 0, 1, //
                        0x02, 0x05, 0x01, 0x06, 0x03, 0x07, 0x02, 0x69, //
                        0x64, 0x07, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x07,
                        0x07, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6f, 0x6e,
                        0x00, 0x08, 0x08, 0x38, 0x00, 0x4e, 0x00, 0x65,
                        0x00, 0x77, 0x00, 0x74, 0x00, 0x6f, 0x00, 0x6e,
                        0x00, 0x20, 0x00, 0x43, 0x00, 0x6f, 0x00, 0x6e,
                        0x00, 0x6e, 0x00, 0x65, 0x00, 0x63, 0x00, 0x74,
                        0x00, 0x69, 0x00, 0x6f, 0x00, 0x6e, 0x00, 0x20,
                        0x00, 0x55, 0x00, 0x74, 0x00, 0x69, 0x00, 0x6c,
                        0x00, 0x69, 0x00, 0x74, 0x00, 0x69, 0x00, 0x65,
                        0x00, 0x73, 0x00, 0x00, 0x00, 0x04,
                    } ++ [_]u8{0} ** 65426,
                    .length = 110,
                }, allocator);
            },
            .which_icons => {
                std.mem.copy(u8, challenge[0..8], packet.data[8..16]);
                try dock_layer.send(&event_queue.DockPacket{
                    .source = .dock,
                    .command = .which_icons,
                    .data = [_]u8{ 0, 0, 0, all_icons } ++ [_]u8{0} ** 65532,
                    .length = 4,
                }, allocator);
            },
            .set_timeout => {
                try dock_layer.send(&event_queue.DockPacket{
                    .source = .dock,
                    .command = .set_timeout,
                    .data = [_]u8{ 0, 0, 0, dock_timeout } ++ [_]u8{0} ** 65532,
                    .length = 4,
                }, allocator);
            },
            .password => {
                var response: [8]u8 = undefined;
                encrypt(&challenge, &response);
                var response_packet: event_queue.DockPacket = .{
                    .source = .dock,
                    .command = .password,
                    .length = 8,
                };
                std.mem.copy(u8, response_packet.data[0..8], response[0..8]);
                try dock_layer.send(&response_packet, allocator);
            },
            .disconnect => {},
        }
    }
}

pub fn processEvent(event: *event_queue.StackEvent, allocator: std.mem.Allocator) !void {
    switch (event.*) {
        .dock => |packet| try handleDockCommand(&packet, allocator),
        else => {},
    }
}
