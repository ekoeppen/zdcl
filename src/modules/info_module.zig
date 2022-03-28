const std = @import("std");
const fsm = @import("../utils/fsm.zig");
const event_queue = @import("../protocol/event_queue.zig");
const dock_layer = @import("../protocol/dock_layer.zig");
const nsof = @import("../nsof/nsof.zig");
const stores = @import("./stores.zig");

const AppEvent = event_queue.AppEvent;
const DockPacket = event_queue.DockPacket;
const NSObject = nsof.NSObject;
const NSObjectSet = nsof.NSObjectSet;

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

var current_store: *stores.StoreList.Node = undefined;

fn handleDockCommand(packet: DockPacket, allocator: std.mem.Allocator) !void {
    if (info_fsm.input(packet.command)) |action| {
        switch (action) {
            .select_store => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                var objects = NSObjectSet.init(allocator);
                defer objects.deinit(allocator);
                const stores_response = try nsof.decode(reader, &objects, allocator);
                try stores.save(stores_response, allocator);
                if (stores.store_list.first) |first_store| {
                    current_store = first_store;
                    try stores.setCurrent(&first_store.data, allocator);
                } else unreachable;
            },
            .get_soup_names => {
                const dock_packet = try DockPacket.init(.get_soup_names, .out, &.{}, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .show_soup_names => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                var objects = NSObjectSet.init(allocator);
                defer objects.deinit(allocator);
                const soup_names = try nsof.decode(reader, &objects, allocator);
                try soup_names.write(std.io.getStdOut().writer());
                if (current_store.next) |next_store| {
                    current_store = next_store;
                    try stores.setCurrent(&next_store.data, allocator);
                    info_fsm.state = .selecting_store;
                } else {
                    const dock_packet = try DockPacket.init(.get_app_names, .out, &.{ 0, 0, 0, 0 }, allocator);
                    try event_queue.enqueue(.{ .dock = dock_packet });
                    info_fsm.state = .getting_app_list;
                }
            },
            .show_app_list => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                var objects = NSObjectSet.init(allocator);
                defer objects.deinit(allocator);
                const app_names = try nsof.decode(reader, &objects, allocator);
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
