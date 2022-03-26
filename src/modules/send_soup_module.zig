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
    selecting_soup,
    getting_entries,
};

const Action = enum {
    select_store,
    select_soup,
    get_entries,
    save_entry,
    backup_done,
};

var send_fsm: fsm.Fsm(event_queue.DockCommand, State, Action) = .{
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
                .{ .event = .result, .action = .select_soup, .new_state = .getting_entries },
            },
        },
        .{
            .state = .getting_entries,
            .actions = &.{
                .{ .event = .result, .action = .get_entries },
            },
        },
        .{
            .state = .getting_entries,
            .actions = &.{
                .{ .event = .entry, .action = .save_entry },
                .{ .event = .backup_soup_done, .action = .backup_done },
            },
        },
    },
};

fn handleDockCommand(packet: DockPacket, soup: []const u8, allocator: std.mem.Allocator) !void {
    if (send_fsm.input(packet.command)) |action| {
        switch (action) {
            .select_store => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                var objects = NSObjectSet.init(allocator);
                defer objects.deinit(allocator);
                const stores_response = try nsof.decode(reader, &objects, allocator);
                try stores.save(stores_response, allocator);
                try stores.setCurrent(allocator);
                stores.current += 1;
            },
            .select_soup => {
                var soup_name = [_]u8{0} ** 52;
                for (soup) |char, i| {
                    soup_name[i * 2 + 1] = char;
                }
                const dock_packet = try DockPacket.init(.set_current_soup, .out, soup_name[0 .. soup.len * 2 + 2], allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .get_entries => {
                const dock_packet = try DockPacket.init(.send_soup, .out, &.{}, allocator);
                try event_queue.enqueue(.{ .dock = dock_packet });
            },
            .save_entry => {
                const reader = std.io.fixedBufferStream(packet.data[1..]).reader();
                var objects = NSObjectSet.init(allocator);
                defer objects.deinit(allocator);
                const entry = try nsof.decode(reader, &objects, allocator);
                try entry.write(std.io.getStdOut().writer());
            },
            .backup_done => {
                if (stores.current < stores.stores.len) {
                    try stores.setCurrent(allocator);
                    stores.current += 1;
                    send_fsm.state = .selecting_store;
                } else {
                    var dock_packet = try DockPacket.init(.disconnect, .out, &.{}, allocator);
                    try event_queue.enqueue(.{ .dock = dock_packet });
                    send_fsm.state = .idle;
                }
            },
        }
    }
}

pub fn processEvent(event: event_queue.StackEvent, soup: []const u8, allocator: std.mem.Allocator) !void {
    _ = soup;
    switch (event) {
        .app => |app| if (app.direction == .in and app.event == .connected) {
            var dock_packet = try DockPacket.init(.get_store_names, .out, &.{}, allocator);
            try event_queue.enqueue(.{ .dock = dock_packet });
            send_fsm.state = .getting_store_names;
        },
        .dock => |packet| if (packet.direction == .in) try handleDockCommand(packet, soup, allocator),
        else => {},
    }
}
