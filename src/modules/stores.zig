const std = @import("std");
const event_queue = @import("../protocol/event_queue.zig");
const dock_layer = @import("../protocol/dock_layer.zig");
const nsof = @import("../nsof/nsof.zig");

const DockPacket = event_queue.DockPacket;
const NSObject = nsof.NSObject;

pub const Store = struct {
    name: []u16 = undefined,
    kind: []u16 = undefined,
    signature: i32 = 0,
};

pub var current: usize = undefined;
pub var stores: []Store = undefined;

pub fn save(stores_response: *nsof.NSObject, allocator: std.mem.Allocator) !void {
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
    current = 0;
}

pub fn deinit(allocator: std.mem.Allocator) void {
    for (stores) |store| {
        allocator.free(store.kind);
        allocator.free(store.name);
    }
    allocator.free(stores);
}

pub fn setCurrent(allocator: std.mem.Allocator) !void {
    const store = stores[current];
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
