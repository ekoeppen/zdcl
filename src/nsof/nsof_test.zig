const std = @import("std");
const hexdump = @import("./utils/hexdump.zig");

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

