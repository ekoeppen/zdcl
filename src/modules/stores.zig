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

pub const StoreList = std.SinglyLinkedList(Store);
pub var store_list: StoreList = .{};

pub fn save(stores_response: *nsof.NSObject, allocator: std.mem.Allocator) !void {
    for (stores_response.plainArray) |s| {
        const node = try allocator.create(StoreList.Node);
        if (s.getSlot("name")) |name| {
            node.data.name = try allocator.alloc(u16, name.string.len);
            std.mem.copy(u16, node.data.name, name.string);
        }
        if (s.getSlot("kind")) |kind| {
            node.data.kind = try allocator.alloc(u16, kind.string.len);
            std.mem.copy(u16, node.data.kind, kind.string);
        }
        if (s.getSlot("signature")) |signature| {
            node.data.signature = nsof.refToInt(signature.immediate).?;
        }
        store_list.prepend(node);
    }
}

pub fn deinit(allocator: std.mem.Allocator) void {
    while (store_list.popFirst()) |node| {
        allocator.free(node.data.name);
        allocator.free(node.data.kind);
        allocator.destroy(node);
    }
}

pub fn setCurrent(store: *Store, allocator: std.mem.Allocator) !void {
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
        &NSObject{ .immediate = nsof.intToRef(store.signature).? },
    } } };
    try writer.writeByte(2);
    try nsof.encode(info, writer);
    var dock_packet = try DockPacket.init(.set_current_store, .out, data[0..try fbs.getPos()], allocator);
    try event_queue.enqueue(.{ .dock = dock_packet });
}
