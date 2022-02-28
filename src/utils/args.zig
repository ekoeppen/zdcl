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
        string: []u8,
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

    pub fn setFromIter(self: *Arg, iter: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
        switch (self.value) {
            .number => {
                var arg = try iter.next(allocator) orelse {
                    std.log.err("Missing argument for {s} {s}", .{ self.short, self.long });
                    return error.InvalidArgs;
                };
                defer allocator.free(arg);
                self.value = .{ .number = try std.fmt.parseInt(i32, arg, 10) };
            },
            .string => {
                var arg = try iter.next(allocator) orelse {
                    std.log.err("Missing argument for {s} {s}", .{ self.short, self.long });
                    return error.InvalidArgs;
                };
                self.value = .{ .string = arg };
            },
            .boolean => self.value = .{ .boolean = true },
            .present => self.value = .{ .present = true },
        }
    }
};

pub const Command = struct {
    name: []const u8,
    help: []const u8,
    args: anytype,
};

pub const ParsedArgs = struct {
    command: []u8 = undefined,
    args: std.StringHashMap(Arg) = undefined,
    parameters: std.ArrayList([]u8) = undefined,
};

pub fn process(comptime commands: anytype, comptime common_args: anytype, allocator: std.mem.Allocator) !ParsedArgs {
    var parsed_args: ParsedArgs = .{};
    parsed_args.args = std.StringHashMap(Arg).init(allocator);
    parsed_args.parameters = std.ArrayList([]u8).init(allocator);
    var iter = std.process.args();
    _ = iter.skip();
    var cmd = try iter.next(allocator) orelse {
        std.log.err("No command given", .{});
        return error.InvalidArgument;
    };
    const cmd_def = inline for (@typeInfo(@TypeOf(commands)).Struct.fields) |field| {
        const cmd_definition: *const Command = &@field(commands, field.name);
        if (std.mem.eql(u8, cmd, cmd_definition.name)) {
            break cmd_definition;
        }
    } else {
        std.log.err("Unknown command {s}", .{cmd});
        return error.InvalidArgument;
    };
    parsed_args.command = cmd;
    parse_args: while (true) {
        var arg = try iter.next(allocator) orelse {
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

pub fn process_(comptime T: type, args: *T, allocator: std.mem.Allocator) !void {
    var iter = std.process.args();
    parse_args: while (true) {
        var arg = try iter.next(allocator) orelse {
            break :parse_args;
        };
        inline for (@typeInfo(T).Struct.fields) |field| {
            var arg_definition: *Arg = &@field(args, field.name);
            if (arg_definition.matches(arg)) {
                try Arg.setFromIter(arg_definition, &iter, allocator);
                continue :parse_args;
            }
        }
        allocator.free(arg);
    }
}
