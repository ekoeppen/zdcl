const std = @import("std");
const fsm = @import("../utils/fsm.zig");
const event_queue = @import("../protocol/event_queue.zig");
const dock_layer = @import("../protocol/dock_layer.zig");
const des = @import("../utils/des.zig");

const DockPacket = event_queue.DockPacket;
const AppEvent = event_queue.AppEvent;

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
    connected,
    disconnect,
};

const SessionType = enum(u8) {
    none = 0,
    setting_up = 1,
    synchronize = 2,
    restore = 3,
    load_package = 4,
    test_comm = 5,
    load_patch = 6,
    updating_stores = 7,
};

pub var session_type: SessionType = .none;

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
                .{ .event = .hello, .action = .connected },
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

fn handleDockCommand(packet: DockPacket, allocator: std.mem.Allocator) !void {
    if (connect_fsm.input(packet.command)) |action| {
        switch (action) {
            .request_to_dock => {
                var dock_packet = try DockPacket.init(.dock, .out, &.{ 0, 0, 0, 1 }, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .desktop_info => {
                var dock_packet = try DockPacket.init(.desktop_info, .out, &.{
                    0, 0, 0, protocol_version, //
                    0, 0, 0, desktop_mac, //
                    0x64, 0x23, 0xef, 0x02, //
                    0xfb, 0xcd, 0xc5, 0xa5, //
                    0, 0, 0, @enumToInt(SessionType.setting_up), //
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
                }, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .which_icons => {
                std.mem.copy(u8, challenge[0..8], packet.data[8..16]);
                var dock_packet = try DockPacket.init(.which_icons, .out, &.{ 0, 0, 0, all_icons }, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .set_timeout => {
                var dock_packet = try DockPacket.init(.set_timeout, .out, &.{ 0, 0, 0, dock_timeout }, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .password => {
                var response: [8]u8 = undefined;
                encrypt(&challenge, &response);
                var dock_packet = try DockPacket.init(.password, .out, response[0..8], allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .connected => {
                var app_event = try AppEvent.init(.connected, .in, &.{}, allocator);
                try event_queue.enqueue(.{ .app = app_event });
            },
            .disconnect => {
                var app_event = try AppEvent.init(.disconnected, .in, &.{}, allocator);
                try event_queue.enqueue(.{ .app = app_event });
            },
        }
    }
}

pub fn processEvent(event: event_queue.StackEvent, allocator: std.mem.Allocator) !void {
    switch (event) {
        .dock => |packet| if (packet.direction == .in) try handleDockCommand(packet, allocator),
        else => {},
    }
}
