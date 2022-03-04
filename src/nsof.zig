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

const NSObject = union(enum) {
    immediate: i32,
    character: u8,
    uniChar: u16,
    binary: struct {
        class: *const NSObject,
        data: []const u8,
    },
    array: struct {
        class: *NSObject,
        slots: []const *NSObject,
    },
    plainArray: []const *NSObject,
    frame: struct {
        tags: []const *NSObject,
        slots: []const *NSObject,
    },
    symbol: []const u8,
    string: []const u16,
    precedent: u32,
    nil: u8,
    smallRect: struct {
        top: i8,
        left: i8,
        bottom: i8,
        right: i8,
    },
};

pub fn format(self: NSObject, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    const fmt = std.fmt.format;
    switch (self) {
        .immediate => |o| fmt(writer, "imm: {d}", .{o}),
        .character => |o| fmt(writer, "{c}", .{o}),
        .uniChar => |o| fmt(writer, "{d}", .{o}),
        .binary => |o| fmt(writer, "bin: {d}", .{o}),
        .array => |o| fmt(writer, "arr: {d}", .{o}),
        .plainArray => |o| fmt(writer, "arr: {d}", .{o}),
        .frame => |o| fmt(writer, "{{}{}}", .{o}),
        .symbol => |o| fmt(writer, "'{}", .{o}),
        .string => |o| fmt(writer, "{s}", .{o}),
        .precedent => |o| fmt(writer, "prec: {d}", .{o}),
        .nil => fmt(writer, "nil", .{}),
        .smallRect => |o| fmt(writer, "[{d}]", .{o}),
    }
}

fn decodeXlong(reader: anytype) !i32 {
    var r: i32 = try reader.readByte();
    if (r < 255) {
        return r;
    }
    r = try reader.readIntBig(i32);
    return r;
}

fn decodeObject(reader: anytype, allocator: std.mem.Allocator) anyerror!NSObject {
    switch (try reader.readByte()) {
        0 => return NSObject{ .immediate = try decodeXlong(reader) },
        1 => return NSObject{ .character = try reader.readByte() },
        2 => return NSObject{ .uniChar = try reader.readIntBig(u16) },
        3 => {
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
        4 => {
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
        5 => {
            const count = try decodeXlong(reader);
            var elements = try allocator.alloc(*NSObject, @intCast(usize, count));
            for (elements) |_, i| {
                elements[i] = try allocator.create(NSObject);
                elements[i].* = try decodeObject(reader, allocator);
            }
            return NSObject{ .plainArray = elements };
        },
        6 => { // frame
            unreachable;
        },
        7 => {
            const length = try decodeXlong(reader);
            var symbol = try allocator.alloc(u8, @intCast(usize, length));
            _ = try reader.read(symbol);
            return NSObject{ .symbol = symbol };
        },
        8 => {
            const length = try decodeXlong(reader);
            const string_data: []u16 = try allocator.alloc(u16, @intCast(usize, length) / 2);
            for (string_data) |_, i| {
                string_data[i] = @intCast(u16, try reader.readByte()) * 256 + try reader.readByte();
            }
            return NSObject{ .string = string_data };
        },
        9 => { // precedent
            unreachable;
        },
        10 => return NSObject{ .nil = 0 },
        11 => { // smallRect
            unreachable;
        },
        else => |tag| {
            std.log.err("Invalid object tag {}", .{tag});
            return error.InvalidArgument;
        },
    }
}

fn decode(file: []const u8, allocator: std.mem.Allocator) !void {
    const fd = try std.os.open(file, std.os.O.RDONLY, 0);
    defer std.os.close(fd);
    const file_stat = try std.os.fstat(fd);
    var nsof_data = try allocator.alloc(u8, @intCast(u32, file_stat.size));
    _ = try std.os.read(fd, nsof_data);
    hexdump.debug(nsof_data);
    const reader = std.io.fixedBufferStream(nsof_data).reader();
    _ = reader.readByte();
    var o = try decodeObject(reader, allocator);
    std.log.info("{s}", .{o});
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

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();
    _ = allocator;
    var parsed_args = try args.process(cli_commands, common_args, arena.allocator());
    if (std.mem.eql(u8, parsed_args.command, cli_commands.decode.name)) {
        try decode(parsed_args.parameters.items[0], allocator);
    }
}
