const std = @import("std");
const fsm = @import("../utils/fsm.zig");
const event_queue = @import("../protocol/event_queue.zig");
const dock_layer = @import("../protocol/dock_layer.zig");
const nsof = @import("../nsof/nsof.zig");
const stores = @import("./stores.zig");

const AppEvent = event_queue.AppEvent;
const DockPacket = event_queue.DockPacket;
const NSObject = nsof.NSObject;

const State = enum {
    idle,
    getting_store_names,
    selecting_store,
    getting_soup_names,
    getting_app_list,
};

const Action = enum {
    select_store,
    get_soup_names,
    show_soup_names,
    show_app_list,
};

var info_fsm: fsm.Fsm(event_queue.DockCommand, State, Action) = .{
    .state = .idle,
    .transitions = &.{
        .{
            .state = .idle,
            .actions = &.{},
        },
        .{
            .state = .getting_store_names,
            .actions = &.{
                .{ .event = .store_names, .action = .select_store, .new_state = .selecting_store },
            },
        },
        .{
            .state = .selecting_store,
            .actions = &.{
                .{ .event = .result, .action = .get_soup_names, .new_state = .getting_soup_names },
            },
        },
        .{
            .state = .getting_soup_names,
            .actions = &.{
                .{ .event = .soup_names, .action = .show_soup_names },
            },
        },
        .{
            .state = .getting_app_list,
            .actions = &.{
                .{ .event = .app_names, .action = .show_app_list, .new_state = .idle },
            },
        },
    },
};

fn handleDockCommand(packet: DockPacket, allocator: std.mem.Allocator) !void {
    if (info_fsm.input(packet.command)) |action| {
        switch (action) {
            .select_store => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                const stores_response = try nsof.decode(reader, allocator);
                defer stores_response.deinit(allocator);
                try stores.save(stores_response, allocator);
                try stores.setCurrent(allocator);
                stores.current += 1;
            },
            .get_soup_names => {
                const dock_packet = try DockPacket.init(.get_soup_names, .out, &.{}, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .show_soup_names => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                const soup_names = try nsof.decode(reader, allocator);
                defer soup_names.deinit(allocator);
                try soup_names.write(std.io.getStdOut().writer());
                if (stores.current < stores.stores.len) {
                    try stores.setCurrent(allocator);
                    stores.current += 1;
                    info_fsm.state = .selecting_store;
                } else {
                    const dock_packet = try DockPacket.init(.get_app_names, .out, &.{ 0, 0, 0, 0 }, allocator);
                    try event_queue.enqueue(.{ .dock = dock_packet });
                    info_fsm.state = .getting_app_list;
                }
            },
            .show_app_list => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                const app_names = try nsof.decode(reader, allocator);
                defer app_names.deinit(allocator);
                try app_names.write(std.io.getStdOut().writer());
                const dock_packet = try DockPacket.init(.disconnect, .out, &.{}, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
                stores.deinit(allocator);
            },
        }
    }
}

pub fn processEvent(event: event_queue.StackEvent, allocator: std.mem.Allocator) !void {
    switch (event) {
        .app => |app| if (app.direction == .in and app.event == .connected) {
            var dock_packet = try DockPacket.init(.get_store_names, .out, &.{}, allocator);
            try event_queue.enqueue(.{ .dock = dock_packet });
            info_fsm.state = .getting_store_names;
        },
        .dock => |packet| if (packet.direction == .in) try handleDockCommand(packet, allocator),
        else => {},
    }
}
