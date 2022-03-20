const std = @import("std");
const fsm = @import("../utils/fsm.zig");
const event_queue = @import("../protocol/event_queue.zig");
const dock_layer = @import("../protocol/dock_layer.zig");
const nsof = @import("../nsof/nsof.zig");

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

const Store = struct {
    name: []u16 = undefined,
    kind: []u16 = undefined,
    signature: i32 = 0,
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

var current_store: usize = undefined;
var stores: []Store = undefined;

fn saveStores(stores_response: *nsof.NSObject, allocator: std.mem.Allocator) !void {
    stores = try allocator.alloc(Store, stores_response.plainArray.len);
    for (stores_response.plainArray) |s, i| {
        if (s.getSlot("name")) |name| {
            stores[i].name = try allocator.alloc(u16, name.string.len);
            std.mem.copy(u16, stores[i].name, name.string);
        }
        if (s.getSlot("kind")) |kind| {
            stores[i].kind = try allocator.alloc(u16, kind.string.len);
            std.mem.copy(u16, stores[i].kind, kind.string);
        }
        if (s.getSlot("signature")) |signature| {
            stores[i].signature = signature.immediate;
        }
    }
    current_store = 0;
}

fn releaseStores(allocator: std.mem.Allocator) void {
    for (stores) |store| {
        allocator.free(store.kind);
        allocator.free(store.name);
    }
    allocator.free(stores);
}

fn sendStoreSelection(allocator: std.mem.Allocator) !void {
    const store = stores[current_store];
    var data: []u8 = try allocator.alloc(u8, store.name.len + store.kind.len + 128);
    defer allocator.free(data);
    var fbs = std.io.fixedBufferStream(data);
    const writer = fbs.writer();
    const info = &NSObject{ .frame = .{ .tags = &.{
        &NSObject{ .symbol = "name" },
        &NSObject{ .symbol = "kind" },
        &NSObject{ .symbol = "signature" },
    }, .slots = &.{
        &NSObject{ .string = store.name },
        &NSObject{ .string = store.kind },
        &NSObject{ .immediate = store.signature },
    } } };
    try writer.writeByte(2);
    try nsof.encode(info, writer);
    var dock_packet = try DockPacket.init(.set_current_store, .out, data[0..try fbs.getPos()], allocator);
    try event_queue.enqueue(.{ .dock = dock_packet });
}

fn handleDockCommand(packet: DockPacket, allocator: std.mem.Allocator) !void {
    if (info_fsm.input(packet.command)) |action| {
        switch (action) {
            .select_store => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                const stores_response = try nsof.decode(reader, allocator);
                defer stores_response.deinit(allocator);
                try saveStores(stores_response, allocator);
                try sendStoreSelection(allocator);
                current_store += 1;
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
                if (current_store < stores.len) {
                    try sendStoreSelection(allocator);
                    current_store += 1;
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
                releaseStores(allocator);
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
