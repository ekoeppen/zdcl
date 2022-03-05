const std = @import("std");
const args = @import("./utils/args.zig");
const hexdump = @import("./utils/hexdump.zig");

const help_arg: args.Arg = .{
    .name = "help",
    .short = "-h",
    .long = "--help",
    .help = "Show help",
};

const common_args = .{
    .help = help_arg,
};

const cli_commands = .{ //
    .help = .{
        .name = "help",
        .help = "Get general help",
        .args = .{},
    },
    .encode = .{ .name = "encode", .help = "Encode to NSOF", .args = .{} },
    .decode = .{
        .name = "decode",
        .help = "Decode from NSOF",
        .args = .{},
    },
};

const NSObjectTag = enum(u8) { //
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

const NSObject = union(enum) {
    immediate: i32,
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
                for (o.tags) |_, i| {
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
                    try f(writer, "{c}", .{@truncate(u8, char)});
                }
                try f(writer, "\"", .{});
            },
            .precedent => |o| try f(writer, "prec: {d}", .{o}),
            .nil => try f(writer, "nil", .{}),
            .smallRect => |o| try f(writer, "[{d}]", .{o}),
        }
    }
};

fn decodeXlong(reader: anytype) !i32 {
    var r: i32 = try reader.readByte();
    if (r < 255) {
        return r;
    }
    r = try reader.readIntBig(i32);
    return r;
}

fn encodeXlong(xlong: i32, writer: anytype) !void {
    if (xlong >= 0 and xlong <= 254) {
        try writer.writeByte(@intCast(u8, xlong));
        return;
    }
    try writer.writeByte(255);
    try writer.writeIntBig(i32, xlong);
}

fn decodeObject(reader: anytype, allocator: std.mem.Allocator) anyerror!NSObject {
    switch (@intToEnum(NSObjectTag, try reader.readByte())) {
        .immediate => return NSObject{ .immediate = try decodeXlong(reader) },
        .character => return NSObject{ .character = try reader.readByte() },
        .uniChar => return NSObject{ .uniChar = try reader.readIntBig(u16) },
        .binary => {
            const length = try decodeXlong(reader);
            var class = try allocator.create(NSObject);
            class.* = try decodeObject(reader, allocator);
            var data = try allocator.alloc(u8, @intCast(usize, length));
            _ = try reader.read(data);
            return NSObject{ .binary = .{
                .class = class,
                .data = data,
            } };
        },
        .array => {
            const count = try decodeXlong(reader);
            var class = try allocator.create(NSObject);
            class.* = try decodeObject(reader, allocator);
            var elements = try allocator.alloc(*NSObject, @intCast(usize, count));
            for (elements) |_, i| {
                elements[i] = try allocator.create(NSObject);
                elements[i].* = try decodeObject(reader, allocator);
            }
            return NSObject{ .array = .{ .class = class, .slots = elements } };
        },
        .plainArray => {
            const count = try decodeXlong(reader);
            var elements = try allocator.alloc(*NSObject, @intCast(usize, count));
            for (elements) |_, i| {
                elements[i] = try allocator.create(NSObject);
                elements[i].* = try decodeObject(reader, allocator);
            }
            return NSObject{ .plainArray = elements };
        },
        .frame => {
            const count = try decodeXlong(reader);
            var tags = try allocator.alloc(*NSObject, @intCast(usize, count));
            var slots = try allocator.alloc(*NSObject, @intCast(usize, count));
            for (tags) |_, i| {
                tags[i] = try allocator.create(NSObject);
                tags[i].* = try decodeObject(reader, allocator);
            }
            for (slots) |_, i| {
                slots[i] = try allocator.create(NSObject);
                slots[i].* = try decodeObject(reader, allocator);
            }
            return NSObject{ .frame = .{ .tags = tags, .slots = slots } };
        },
        .symbol => {
            const length = try decodeXlong(reader);
            var symbol = try allocator.alloc(u8, @intCast(usize, length));
            _ = try reader.read(symbol);
            return NSObject{ .symbol = symbol };
        },
        .string => {
            const length = try decodeXlong(reader);
            const string_data: []u16 = try allocator.alloc(u16, @intCast(usize, length) / 2);
            for (string_data) |_, i| {
                string_data[i] = @intCast(u16, try reader.readByte()) * 256 + try reader.readByte();
            }
            return NSObject{ .string = string_data };
        },
        .precedent => return NSObject{ .precedent = try decodeXlong(reader) },
        .nil => return NSObject{ .nil = 0 },
        .smallRect => return NSObject{ .smallRect = .{
            .top = try reader.readByte(),
            .left = try reader.readByte(),
            .right = try reader.readByte(),
            .bottom = try reader.readByte(),
        } },
        else => |tag| {
            std.log.err("Invalid object tag {}", .{tag});
            return error.InvalidArgument;
        },
    }
}

fn encodeObject(object: *const NSObject, writer: anytype) anyerror!void {
    switch (object.*) {
        .immediate => |o| {
            try writer.writeByte(0);
            try encodeXlong(o, writer);
        },
        .character => |o| {
            try writer.writeByte(1);
            try writer.writeByte(o);
        },
        .uniChar => |o| {
            try writer.writeByte(2);
            try writer.writeIntBig(u16, o);
        },
        .binary => |o| {
            try writer.writeByte(3);
            try encodeXlong(@intCast(i32, o.data.len), writer);
            try encodeObject(o.class, writer);
            _ = try writer.write(o.data);
        },
        .array => |o| {
            try writer.writeByte(4);
            try encodeXlong(@intCast(i32, o.slots.len), writer);
            try encodeObject(o.class, writer);
            for (o.slots) |slot| {
                try encodeObject(slot, writer);
            }
        },
        .plainArray => |o| {
            try writer.writeByte(5);
            try encodeXlong(@intCast(i32, o.len), writer);
            for (o) |slot| {
                try encodeObject(slot, writer);
            }
        },
        .frame => |o| {
            try writer.writeByte(6);
            try encodeXlong(@intCast(i32, o.tags.len), writer);
            for (o.tags) |tag| {
                try encodeObject(tag, writer);
            }
            for (o.slots) |slot| {
                try encodeObject(slot, writer);
            }
        },
        .symbol => |o| {
            try writer.writeByte(7);
            try encodeXlong(@intCast(i32, o.len), writer);
            _ = try writer.write(o);
        },
        .string => |o| {
            try writer.writeByte(8);
            try encodeXlong(@intCast(i32, o.len) * 2, writer);
            for (o) |char| {
                try writer.writeIntBig(u16, char);
            }
        },
        .precedent => |o| {
            try writer.writeByte(9);
            try encodeXlong(@intCast(i32, o), writer);
        },
        .nil => {
            try writer.writeByte(10);
        },
        .smallRect => |o| {
            try writer.writeByte(11);
            try writer.writeByte(o.top);
            try writer.writeByte(o.left);
            try writer.writeByte(o.bottom);
            try writer.writeByte(o.right);
        },
    }
}

fn decode(file: []const u8, allocator: std.mem.Allocator) !NSObject {
    const fd = try std.os.open(file, std.os.O.RDONLY, 0);
    defer std.os.close(fd);
    const file_stat = try std.os.fstat(fd);
    var nsof_data = try allocator.alloc(u8, @intCast(u32, file_stat.size));
    _ = try std.os.read(fd, nsof_data);
    hexdump.debug(nsof_data);
    const reader = std.io.fixedBufferStream(nsof_data).reader();
    _ = try reader.readByte();
    return try decodeObject(reader, allocator);
}

test "Decode XLong" {
    const data: []const u8 = &.{ 0, 1, 254, 255, 0, 0, 1, 0 };
    const s = std.io.fixedBufferStream(data).reader();
    const zero = decodeXlong(&s);
    std.debug.print("\n{}\n", .{zero});
    const one = decodeXlong(&s);
    std.debug.print("{}\n", .{one});
    const small = decodeXlong(&s);
    std.debug.print("{}\n", .{small});
    const medium = decodeXlong(&s);
    std.debug.print("{}\n", .{medium});
}

test "Decode simple types" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const data: []const u8 = &.{
        10, 1, 65,   2,   0x10, 0x01, 7,    4,   'n', 'a', 'm', 'e', //
        8,  6, 0x00, 'A', 0x00, 'B',  0x00, 'C',
    };
    const s = std.io.fixedBufferStream(data).reader();

    const nil = decodeObject(&s, arena.allocator());
    std.debug.print("\n{s}\n", .{nil});

    const character = decodeObject(&s, arena.allocator());
    std.debug.print("{s}\n", .{character});

    const uniChar = decodeObject(&s, arena.allocator());
    std.debug.print("{s}\n", .{uniChar});

    const symbol = decodeObject(&s, arena.allocator());
    std.debug.print("{s}\n", .{symbol});

    const string = decodeObject(&s, arena.allocator());
    std.debug.print("{s}\n", .{string});
}

test "Decode compound types" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const data: []const u8 = &.{
        3, 4,   7,  3, 'b', 'i', 'n', '1', '2', '3', '4', //
        5, 3,   7,  3, '1', '2', '3', 8,   4,   0,   'A',
        0, 'B', 10, 4, 3,   7,   3,   'a', 'r', 'r', 0,
        2, 8,   4,  0, 'A', 0,   'B', 10,
    };
    const s = std.io.fixedBufferStream(data).reader();

    const binary = try decodeObject(&s, arena.allocator());
    std.debug.print("\n{}\n", .{binary});

    const plainArray = try decodeObject(&s, arena.allocator());
    std.debug.print("{}\n", .{plainArray});

    const array = try decodeObject(&s, arena.allocator());
    std.debug.print("{}\n", .{array});
}

test "Encode simple types" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var data: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&data);
    const s = fbs.writer();

    var start = try fbs.getPos();
    try encodeObject(&NSObject{ .immediate = 0 }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encodeObject(&NSObject{ .immediate = 256 }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encodeObject(&NSObject{ .character = 'a' }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encodeObject(&NSObject{ .uniChar = 0x1001 }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encodeObject(&NSObject{ .symbol = &.{ 'n', 'a', 'm', 'e' } }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encodeObject(&NSObject{ .string = &.{ 'A', 'B', 'C' } }, s);
    hexdump.debug(data[start..try fbs.getPos()]);
}

test "Encode complex types" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var data: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&data);
    const s = fbs.writer();

    var start = try fbs.getPos();
    try encodeObject(&NSObject{ .binary = .{
        .class = &NSObject{ .symbol = &.{ 'b', 'i', 'n' } },
        .data = &.{ 1, 2, 3, 4, 5, 6, 7, 8 },
    } }, s);
    hexdump.debug(data[start..try fbs.getPos()]);

    start = try fbs.getPos();
    try encodeObject(&NSObject{ .array = .{
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

    var data: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&data);
    const writer = fbs.writer();
    const reader = fbs.reader();

    var start = try fbs.getPos();
    try encodeObject(&NSObject{ .array = .{
        .class = &NSObject{ .symbol = &.{ 'a', 'r', 'r' } },
        .slots = &.{
            &NSObject{ .nil = 0 },
            &NSObject{ .string = &.{ 'a', 'b', 'c', 'd' } },
            &NSObject{ .immediate = 0x1234 },
        },
    } }, writer);
    hexdump.debug(data[start..try fbs.getPos()]);
    fbs.reset();
    const o = try decodeObject(reader, arena.allocator());
    var buffer: [1024]u8 = undefined;
    var fb = std.io.fixedBufferStream(&buffer);
    try o.write(fb.writer());
    std.debug.print("{s}\n", .{buffer[0..try fb.getPos()]});
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();
    _ = allocator;
    var parsed_args = try args.process(cli_commands, common_args, arena.allocator());
    if (std.mem.eql(u8, parsed_args.command, cli_commands.decode.name)) {
        var nsof = try decode(parsed_args.parameters.items[0], allocator);
        try nsof.write(std.io.getStdOut().writer());
    }
}
