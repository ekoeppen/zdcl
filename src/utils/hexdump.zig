const std = @import("std");

pub fn debug(data: []const u8) void {
    var offset: u16 = 0;
    for (data) |byte| {
        if (offset % 16 == 0) std.debug.print("{x:0>4}: ", .{offset});
        std.debug.print("{x:0>2} ", .{byte});
        offset += 1;
        if (offset % 16 == 0) std.debug.print("\n", .{});
    }
    if (offset % 16 != 0) std.debug.print("\n", .{});
}

pub fn toWriter(data: []const u8, writer: anytype) !void {
    var offset: u16 = 0;
    for (data) |byte| {
        if (offset % 16 == 0) try std.fmt.format(writer, "{x:0>4}: ", .{offset});
        try std.fmt.format(writer, "{x:0>2} ", .{byte});
        offset += 1;
        if (offset % 16 == 0) try writer.writeByte(10);
    }
    if (offset % 16 != 0) try writer.writeByte(10);
}
