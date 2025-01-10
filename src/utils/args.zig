const std = @import("std");

pub const Arg = struct {
    name: []const u8 = undefined,
    short: ?[]const u8 = null,
    long: ?[]const u8 = null,
    help: ?[]const u8 = null,
    value: union(enum) {
        present: bool,
        number: i32,
        boolean: bool,
        string: []const u8,
    } = .{ .present = false },

    pub fn matches(self: *const Arg, parameter: []const u8) bool {
        if (self.short) |short| {
            if (std.mem.eql(u8, short, parameter)) return true;
        }
        if (self.long) |long| {
            if (std.mem.eql(u8, long, parameter)) return true;
        }
        return false;
    }

    pub fn setFromIter(
        self: *Arg,
        iter: *std.process.ArgIterator,
        allocator: std.mem.Allocator,
    ) !void {
        switch (self.value) {
            .number => {
                const arg = iter.next() orelse {
                    std.log.err("Missing argument for {s}", .{self.name});
                    return error.InvalidArgs;
                };
                defer allocator.free(arg);
                self.value = .{ .number = try std.fmt.parseInt(i32, arg, 10) };
            },
            .string => {
                const arg = iter.next() orelse {
                    std.log.err("Missing argument for {s}", .{self.name});
                    return error.InvalidArgs;
                };
                self.value = .{ .string = arg };
            },
            .boolean => self.value = .{ .boolean = true },
            .present => self.value = .{ .present = true },
        }
    }
};

pub const ParsedArgs = struct {
    command: []const u8 = undefined,
    args: std.StringHashMap(Arg) = undefined,
    parameters: std.ArrayList([]const u8) = undefined,
};

pub fn process(
    comptime commands: anytype,
    comptime common_args: anytype,
    allocator: std.mem.Allocator,
) !ParsedArgs {
    var parsed_args: ParsedArgs = .{};
    parsed_args.args = std.StringHashMap(Arg).init(allocator);
    parsed_args.parameters = std.ArrayList([]const u8).init(allocator);
    var iter = try std.process.argsWithAllocator(allocator);
    _ = iter.skip();
    const cmd = iter.next() orelse {
        std.log.err("No command given", .{});
        return error.InvalidArgument;
    };
    inline for (std.meta.fields(@TypeOf(commands))) |f| {
        const cmd_def = @field(commands, f.name);
        if (std.mem.eql(u8, cmd, cmd_def.name)) {
            parsed_args.command = cmd;
            parse_args: while (true) {
                const arg = iter.next() orelse {
                    break :parse_args;
                };
                const defs = cmd_def.args;
                inline for (@typeInfo(@TypeOf(defs)).Struct.fields) |field| {
                    var arg_definition: Arg = @field(defs, field.name);
                    if (arg_definition.matches(arg)) {
                        try arg_definition.setFromIter(&iter, allocator);
                        try parsed_args.args.put(arg_definition.name, arg_definition);
                        allocator.free(arg);
                        continue :parse_args;
                    }
                }
                inline for (@typeInfo(@TypeOf(common_args)).Struct.fields) |field| {
                    var arg_definition: Arg = @field(common_args, field.name);
                    if (arg_definition.matches(arg)) {
                        try arg_definition.setFromIter(&iter, allocator);
                        try parsed_args.args.put(arg_definition.name, arg_definition);
                        allocator.free(arg);
                        continue :parse_args;
                    }
                }
                try parsed_args.parameters.append(arg);
            }
            return parsed_args;
        }
    } else {
        std.log.err("Unknown command {s}\n", .{cmd});
        //try usage(common_args, commands, std.io.getStdErr().writer());
        std.process.exit(1);
    }
}

fn usageArgs(
    comptime indent: usize,
    comptime args: anytype,
    comptime writer: anytype,
) !void {
    inline for (std.meta.fields(@TypeOf(args))) |a| {
        const arg_def = @field(args, a.name);
        _ = try writer.print("{[0]s: >[1]}, {[2]s}: {[3]s}\n", .{
            arg_def.short orelse "",
            indent + 3,
            arg_def.long orelse "",
            arg_def.help orelse "",
        });
    }
}

pub fn usage(
    comptime common_args: anytype,
    comptime commands: anytype,
    comptime writer: anytype,
) !void {
    _ = try writer.write("Commands:\n");
    inline for (std.meta.fields(@TypeOf(commands))) |f| {
        const cmd_def = @field(commands, f.name);
        _ = try writer.print("   {s}: {s}\n", .{ cmd_def.name, cmd_def.help });
        try usageArgs(6, cmd_def.args, writer);
    }
    _ = try writer.write("\nCommon flags for each command:\n");
    try usageArgs(3, common_args, writer);
}
