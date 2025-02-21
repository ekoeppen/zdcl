const std = @import("std");
const hexdump = @import("../utils/hexdump.zig");

const NSObjectTag = enum(u8) {
    immediate = 0,
    character = 1,
    uniChar = 2,
    binary = 3,
    array = 4,
    plainArray = 5,
    frame = 6,
    symbol = 7,
    string = 8,
    precedent = 9,
    nil = 10,
    smallRect = 11,
    _,
};

pub const NSObject = union(NSObjectTag) {
    immediate: u32,
    character: u8,
    uniChar: u16,
    binary: struct {
        class: *const NSObject,
        data: []const u8,
    },
    array: struct {
        class: *const NSObject,
        slots: []const *const NSObject,
    },
    plainArray: []const *NSObject,
    frame: struct {
        tags: []const *const NSObject,
        slots: []const *const NSObject,
    },
    symbol: []const u8,
    string: []const u16,
    precedent: i32,
    nil: u8,
    smallRect: struct {
        top: u8,
        left: u8,
        bottom: u8,
        right: u8,
    },

    pub fn deinit(self: *const NSObject, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .binary => |o| allocator.free(o.data),
            .array => |o| allocator.free(o.slots),
            .plainArray => |o| allocator.free(o),
            .frame => |o| {
                allocator.free(o.tags);
                allocator.free(o.slots);
            },
            .symbol => |o| allocator.free(o),
            .string => |o| allocator.free(o),
            .precedent => std.log.err("Trying to deallocate precedent", .{}),
            else => {},
        }
        allocator.destroy(self);
    }

    pub fn recursiveDeinit(self: *const NSObject, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .binary => |o| {
                o.class.recursiveDeinit(allocator);
                o.deinit();
            },
            .array => |o| {
                for (o.slots) |slot| slot.recursiveDeinit(allocator);
                o.class.recursiveDeinit(allocator);
                o.deinit();
            },
            .plainArray => |o| {
                for (o) |slot| slot.recursiveDeinit(allocator);
                o.deinit();
            },
            .frame => |o| {
                for (o.tags) |tag| tag.recursiveDeinit(allocator);
                for (o.slots) |slot| slot.recursiveDeinit(allocator);
                o.deinit();
            },
            .symbol => |o| o.deinit(),
            .string => |o| o.deinit(),
            else => {},
        }
        allocator.destroy(self);
    }

    pub fn write(self: *const NSObject, writer: anytype) anyerror!void {
        const f = std.fmt.format;
        switch (self.*) {
            .immediate => |o| try f(writer, "imm: {d}", .{o}),
            .character => |o| try f(writer, "{c}", .{o}),
            .uniChar => |o| try f(writer, "{d}", .{o}),
            .binary => |o| {
                try f(writer, "<", .{});
                try o.class.write(writer);
                try f(writer, " ", .{});
                try f(writer, "{s}", .{o.data});
                try f(writer, ">", .{});
            },
            .array => |o| {
                try f(writer, "[", .{});
                try o.class.write(writer);
                try f(writer, ": ", .{});
                for (o.slots) |slot| {
                    try slot.write(writer);
                    try f(writer, ", ", .{});
                }
                try f(writer, "]", .{});
            },
            .plainArray => |o| {
                try f(writer, "[", .{});
                for (o) |slot| {
                    try slot.write(writer);
                    try f(writer, ", ", .{});
                }
                try f(writer, "]", .{});
            },
            .frame => |o| {
                try f(writer, "{{", .{});
                for (o.tags, 0..) |_, i| {
                    try o.tags[i].write(writer);
                    try f(writer, ": ", .{});
                    try o.slots[i].write(writer);
                    try f(writer, ", ", .{});
                }
                try f(writer, "}}", .{});
            },
            .symbol => |o| try f(writer, "{s}", .{o}),
            .string => |o| {
                try f(writer, "\"", .{});
                for (o) |char| {
                    try f(writer, "{c}", .{@as(u8, @truncate(char))});
                }
                try f(writer, "\"", .{});
            },
            .precedent => |o| try f(writer, "prec: {d}", .{o}),
            .nil => try f(writer, "nil", .{}),
            .smallRect => |o| try f(writer, "[{}]", .{o}),
        }
    }

    pub fn getSlot(self: *const NSObject, slot_name: []const u8) ?*const NSObject {
        switch (self.*) {
            .frame => |frame| {
                const slot = for (frame.tags, 0..) |tag, i| {
                    if (std.mem.eql(u8, slot_name, tag.symbol)) break self.frame.slots[i];
                } else null;
                return slot;
            },
            else => return null,
        }
    }
};

fn decodeXlong(reader: anytype) !u32 {
    var r: u32 = try reader.readByte();
    if (r < 255) {
        return r;
    }
    r = try reader.readInt(u32, .big);
    return r;
}

fn encodeXlong(xlong: u32, writer: anytype) !void {
    if (xlong >= 0 and xlong <= 254) {
        try writer.writeByte(@intCast(xlong));
        return;
    }
    try writer.writeByte(255);
    try writer.writeInt(u32, xlong, .big);
}

pub fn refToInt(ref: u32) ?i32 {
    if (ref & 0x3 != 0) {
        return null;
    }
    const n: i32 = @bitCast((ref >> 2) & 0x1fffffff);
    return if (ref & 0x80000000 == 0) n else -n;
}

pub fn intToRef(n: i32) ?u32 {
    if (n > 536870911 or n < -536870912) return null;
    return if (n > 0) @as(u32, @bitCast(n)) << 2 else @as(u32, @bitCast(-n)) << 2 | 0x80000000;
}

pub fn encode(object: *const NSObject, writer: anytype) anyerror!void {
    try writer.writeByte(@intFromEnum(object.*));
    switch (object.*) {
        .immediate => |o| {
            try encodeXlong(o, writer);
        },
        .character => |o| {
            try writer.writeByte(o);
        },
        .uniChar => |o| {
            try writer.writeInt(u16, o, .big);
        },
        .binary => |o| {
            try encodeXlong(@intCast(o.data.len), writer);
            try encode(o.class, writer);
            _ = try writer.write(o.data);
        },
        .array => |o| {
            try encodeXlong(@intCast(o.slots.len), writer);
            try encode(o.class, writer);
            for (o.slots) |slot| {
                try encode(slot, writer);
            }
        },
        .plainArray => |o| {
            try encodeXlong(@intCast(o.len), writer);
            for (o) |slot| {
                try encode(slot, writer);
            }
        },
        .frame => |o| {
            try encodeXlong(@intCast(o.tags.len), writer);
            for (o.tags) |tag| {
                try encode(tag, writer);
            }
            for (o.slots) |slot| {
                try encode(slot, writer);
            }
        },
        .symbol => |o| {
            try encodeXlong(@intCast(o.len), writer);
            _ = try writer.write(o);
        },
        .string => |o| {
            try encodeXlong(@as(u32, @intCast(o.len)) * 2, writer);
            for (o) |char| {
                try writer.writeInt(u16, char, .big);
            }
        },
        .precedent => |o| {
            try encodeXlong(@intCast(o), writer);
        },
        .nil => {},
        .smallRect => |o| {
            try writer.writeByte(o.top);
            try writer.writeByte(o.left);
            try writer.writeByte(o.bottom);
            try writer.writeByte(o.right);
        },
    }
}

pub const NSObjectSet = struct {
    objects: std.ArrayList(*NSObject) = undefined,

    pub fn init(allocator: std.mem.Allocator) NSObjectSet {
        return NSObjectSet{
            .objects = std.ArrayList(*NSObject).init(allocator),
        };
    }

    pub fn deinit(self: *NSObjectSet, allocator: std.mem.Allocator) void {
        for (self.objects.items) |object| object.deinit(allocator);
        self.objects.deinit();
    }

    pub fn decode(self: *NSObjectSet, reader: anytype, allocator: std.mem.Allocator) anyerror!*NSObject {
        var o: *NSObject = undefined;
        const tag: NSObjectTag = @enumFromInt(try reader.readByte());
        if (tag != .precedent) {
            o = try allocator.create(NSObject);
            try self.objects.append(o);
        }
        switch (tag) {
            .immediate => o.* = NSObject{ .immediate = try decodeXlong(reader) },
            .character => o.* = NSObject{ .character = try reader.readByte() },
            .uniChar => o.* = NSObject{ .uniChar = try reader.readInt(u16, .big) },
            .binary => {
                const length = try decodeXlong(reader);
                const class = try self.decode(reader, allocator);
                const data = try allocator.alloc(u8, @intCast(length));
                _ = try reader.read(data);
                o.* = NSObject{ .binary = .{ .class = class, .data = data } };
            },
            .array => {
                const count = try decodeXlong(reader);
                const class = try self.decode(reader, allocator);
                var elements = try allocator.alloc(*NSObject, @intCast(count));
                for (elements, 0..) |_, i| {
                    elements[i] = try self.decode(reader, allocator);
                }
                o.* = NSObject{ .array = .{ .class = class, .slots = elements } };
            },
            .plainArray => {
                const count = try decodeXlong(reader);
                var elements = try allocator.alloc(*NSObject, @intCast(count));
                for (elements, 0..) |_, i| {
                    elements[i] = try self.decode(reader, allocator);
                }
                o.* = NSObject{ .plainArray = elements };
            },
            .frame => {
                const count = try decodeXlong(reader);
                var tags = try allocator.alloc(*NSObject, @intCast(count));
                var slots = try allocator.alloc(*NSObject, @intCast(count));
                for (tags, 0..) |_, i| {
                    tags[i] = try self.decode(reader, allocator);
                }
                for (slots, 0..) |_, i| {
                    slots[i] = try self.decode(reader, allocator);
                }
                o.* = NSObject{ .frame = .{ .tags = tags, .slots = slots } };
            },
            .symbol => {
                const length = try decodeXlong(reader);
                const symbol = try allocator.alloc(u8, @intCast(length));
                _ = try reader.read(symbol);
                o.* = NSObject{ .symbol = symbol };
            },
            .string => {
                const length = try decodeXlong(reader);
                const string_data: []u16 = try allocator.alloc(u16, @as(usize, @intCast(length)) / 2);
                for (string_data, 0..) |_, i| {
                    string_data[i] = @as(u16, @intCast(try reader.readByte())) * 256 + try reader.readByte();
                }
                o.* = NSObject{ .string = string_data };
            },
            .precedent => o = self.objects.items[@intCast(try decodeXlong(reader))],
            .nil => o.* = NSObject{ .nil = 0 },
            .smallRect => o.* = NSObject{ .smallRect = .{
                .top = try reader.readByte(),
                .left = try reader.readByte(),
                .right = try reader.readByte(),
                .bottom = try reader.readByte(),
            } },
            else => |_| {
                std.log.err("Invalid object tag {}", .{tag});
                return error.InvalidArgument;
            },
        }
        return o;
    }
};

test "Decode XLong" {
    const data: []const u8 = &.{ 0, 1, 254, 255, 0, 0, 1, 0 };
    var fbs = std.io.fixedBufferStream(data);
    const s = fbs.reader();
    const zero = decodeXlong(&s);
    std.debug.print("\n{!}\n", .{zero});
    const one = decodeXlong(&s);
    std.debug.print("{!}\n", .{one});
    const small = decodeXlong(&s);
    std.debug.print("{!}\n", .{small});
    const medium = decodeXlong(&s);
    std.debug.print("{!}\n", .{medium});
}

test "Ref conversions" {
    std.debug.print("\n{?} {?}\n", .{ refToInt(0xddd1bdb8), refToInt(0xed850484) });
    std.debug.print("{?} {?}\n", .{ intToRef(-125071214), intToRef(-56705313) });
    std.debug.print("{?} {?}\n", .{ intToRef(-393506670), intToRef(-459358497) });
    try std.testing.expect(refToInt(1) == null);
    try std.testing.expect(refToInt(2) == null);
    try std.testing.expect(refToInt(3) == null);
    try std.testing.expect(intToRef(536870912) == null);
    try std.testing.expect(intToRef(-536870913) == null);
    const int: i32 = 10;
    const ref: ?u32 = intToRef(int);
    try std.testing.expect(refToInt(ref.?).? == int);
    const neg_int: i32 = -10;
    const neg_ref: ?u32 = intToRef(neg_int);
    try std.testing.expect(refToInt(neg_ref.?).? == neg_int);
}

test "Decode simple types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var objects = NSObjectSet.init(gpa.allocator());

    const data: []const u8 = &.{
        10, 1, 65,   2,   0x10, 0x01, 7,    4,   'n', 'a', 'm', 'e', //
        8,  6, 0x00, 'A', 0x00, 'B',  0x00, 'C', 9,   3,
    };
    var fbs = std.io.fixedBufferStream(data);
    const s = fbs.reader();

    const nil = objects.decode(&s, gpa.allocator());
    std.debug.print("\n{!}\n", .{nil});

    const character = objects.decode(&s, gpa.allocator());
    std.debug.print("{!}\n", .{character});

    const uniChar = objects.decode(&s, gpa.allocator());
    std.debug.print("{!}\n", .{uniChar});

    const symbol = objects.decode(&s, gpa.allocator());
    std.debug.print("{!}\n", .{symbol});

    const string = objects.decode(&s, gpa.allocator());
    std.debug.print("{!}\n", .{string});

    const precendent = objects.decode(&s, gpa.allocator());
    std.debug.print("{!}\n", .{precendent});

    objects.deinit(gpa.allocator());
    _ = gpa.deinit();
}

test "Decode compound types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var objects = NSObjectSet.init(gpa.allocator());
    const data: []const u8 = &.{
        3, 4,   7,  3, 'b', 'i', 'n', '1', '2', '3', '4', //
        5, 3,   7,  3, '1', '2', '3', 8,   4,   0,   'A',
        0, 'B', 10, 4, 3,   7,   3,   'a', 'r', 'r', 0,
        2, 8,   4,  0, 'A', 0,   'B', 10,  9,   2,
    };
    var fbs = std.io.fixedBufferStream(data);
    const s = fbs.reader();

    const binary = try objects.decode(&s, gpa.allocator());
    std.debug.print("\n{!}\n", .{binary});

    const plainArray = try objects.decode(&s, gpa.allocator());
    std.debug.print("{!}\n", .{plainArray});

    const array = try objects.decode(&s, gpa.allocator());
    std.debug.print("{!}\n", .{array});

    const precendent = objects.decode(&s, gpa.allocator());
    std.debug.print("{!}\n", .{precendent});

    objects.deinit(gpa.allocator());
    _ = gpa.deinit();
}

test "Encode simple types" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var data: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&data);
    const s = fbs.writer();

    var start = try fbs.getPos();
    try encode(&NSObject{ .immediate = 0 }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encode(&NSObject{ .immediate = 256 }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encode(&NSObject{ .character = 'a' }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encode(&NSObject{ .uniChar = 0x1001 }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encode(&NSObject{ .symbol = &.{ 'n', 'a', 'm', 'e' } }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encode(&NSObject{ .string = &.{ 'A', 'B', 'C' } }, s);
    hexdump.debug(data[start..try fbs.getPos()]);
}

test "Encode complex types" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var data: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&data);
    const s = fbs.writer();

    var start = try fbs.getPos();
    try encode(&NSObject{ .binary = .{
        .class = &NSObject{ .symbol = &.{ 'b', 'i', 'n' } },
        .data = &.{ 1, 2, 3, 4, 5, 6, 7, 8 },
    } }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encode(&NSObject{ .array = .{
        .class = &NSObject{ .symbol = &.{ 'a', 'r', 'r' } },
        .slots = &.{
            &NSObject{ .nil = 0 },
            &NSObject{ .string = &.{ 'a', 'b', 'c', 'd' } },
            &NSObject{ .immediate = 0x1234 },
        },
    } }, s);
    hexdump.debug(data[start..try fbs.getPos()]);
}

test "Roundtrip encoding/decoding" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var objects = NSObjectSet.init(arena.allocator());

    var data: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&data);
    const writer = fbs.writer();
    const reader = fbs.reader();

    const start = try fbs.getPos();
    try encode(&NSObject{ .array = .{
        .class = &NSObject{ .symbol = &.{ 'a', 'r', 'r' } },
        .slots = &.{
            &NSObject{ .nil = 0 },
            &NSObject{ .string = &.{ 'a', 'b', 'c', 'd' } },
            &NSObject{ .immediate = 0x1234 },
        },
    } }, writer);
    hexdump.debug(data[start..try fbs.getPos()]);
    fbs.reset();
    const o = try objects.decode(reader, arena.allocator());
    var buffer: [1024]u8 = undefined;
    var fb = std.io.fixedBufferStream(&buffer);
    try o.write(fb.writer());
    std.debug.print("{s}\n", .{buffer[0..try fb.getPos()]});
}
