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

var current_store: *stores.StoreList.Node = undefined;

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
        var fbs = std.io.fixedBufferStream(packet.data[1..]);
        switch (action) {
            .select_store => {
                var objects = NSObjectSet.init(allocator);
                defer objects.deinit(allocator);
                try stores.save(try objects.decode(fbs.reader(), allocator), allocator);
                if (stores.store_list.first) |first_store| {
                    current_store = first_store;
                    try stores.setCurrent(&first_store.data, allocator);
                } else unreachable;
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
                var objects = NSObjectSet.init(allocator);
                defer objects.deinit(allocator);
                const entry = try objects.decode(fbs.reader(), allocator);
                const uniqueId = if (entry.getSlot("_uniqueID")) |slot|
                    (nsof.refToInt(slot.immediate) orelse 0)
                else
                    0;
                std.log.info("Store: {d} Entry {d}", .{ current_store.data.signature, uniqueId });
                var b: [128]u8 = undefined;
                var file = try std.fmt.bufPrint(&b, "entry{d}-{d}.nsof", .{
                    current_store.data.signature, uniqueId,
                });
                const fd = try std.os.open(file, std.os.O.CREAT | std.os.O.WRONLY, 0o664);
                defer std.os.close(fd);
                _ = try std.os.write(fd, packet.data);
            },
            .backup_done => {
                if (current_store.next) |next_store| {
                    current_store = next_store;
                    try stores.setCurrent(&next_store.data, allocator);
                    send_fsm.state = .selecting_store;
                } else {
                    var dock_packet = try DockPacket.init(.disconnect, .out, &.{}, allocator);
                    try event_queue.enqueue(.{ .dock = dock_packet });
                    send_fsm.state = .idle;
                    stores.deinit(allocator);
                }
            },
        }
    }
}

pub fn processEvent(event: event_queue.StackEvent, soup: []const u8, allocator: std.mem.Allocator) !void {
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
