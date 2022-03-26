const std = @import("std");
const args = @import("./utils/args.zig");
const nsof = @import("./nsof/nsof.zig");
const hexdump = @import("./utils/hexdump.zig");

const NSObject = nsof.NSObject;
const NSObjectSet = nsof.NSObjectSet;

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

fn decode(file: []const u8, allocator: std.mem.Allocator) !void {
    const fd = try std.os.open(file, std.os.O.RDONLY, 0);
    defer std.os.close(fd);
    const file_stat = try std.os.fstat(fd);
    var nsof_data = try allocator.alloc(u8, @intCast(u32, file_stat.size));
    _ = try std.os.read(fd, nsof_data);
    hexdump.debug(nsof_data);
    const reader = std.io.fixedBufferStream(nsof_data).reader();
    _ = try reader.readByte();
    var objects = NSObjectSet.init(allocator);
    defer objects.deinit(allocator);
    const o = try nsof.decode(reader, &objects, allocator);
    try o.write(std.io.getStdOut().writer());
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

test {
    std.testing.refAllDecls(@This());
}
