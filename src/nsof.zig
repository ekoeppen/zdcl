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

const cli_commands = .{
    .help = .{ .name = "help", .help = "Get general help", .args = .{} },
    .encode = .{ .name = "encode", .help = "Encode to NSOF", .args = .{} },
    .decode = .{ .name = "decode", .help = "Decode from NSOF", .args = .{} },
};

fn decode(file: []const u8, allocator: std.mem.Allocator) !void {
    const fd = try std.posix.open(file, .{ .ACCMODE = .RDONLY }, 0);
    defer std.posix.close(fd);
    const file_stat = try std.posix.fstat(fd);
    const nsof_data = try allocator.alloc(u8, @intCast(file_stat.size));
    _ = try std.posix.read(fd, nsof_data);
    hexdump.debug(nsof_data);
    var fbs = std.io.fixedBufferStream(nsof_data);
    var reader = fbs.reader();
    _ = try reader.readByte();
    var objects = NSObjectSet.init(allocator);
    defer objects.deinit(allocator);
    const o = try objects.decode(reader, allocator);
    try o.write(std.io.getStdOut().writer());
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed_args = try args.process(cli_commands, common_args, arena.allocator());
    if (std.mem.eql(u8, parsed_args.command, cli_commands.decode.name)) {
        try decode(parsed_args.parameters.items[0], allocator);
    } else if (std.mem.eql(u8, parsed_args.command, cli_commands.help.name)) {
        try args.usage(common_args, cli_commands, std.io.getStdOut().writer());
    }
}

test {
    std.testing.refAllDecls(@This());
}
