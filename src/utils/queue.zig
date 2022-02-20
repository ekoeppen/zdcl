const std = @import("std");

fn Node(comptime T: type) type {
    return struct {
        data: T,
        next: ?*Node(T),
    };
}

pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator = undefined,
        start: ?*Node(T) = null,
        end: ?*Node(T) = null,
        mutex: std.Thread.Mutex = .{},
        available: std.Thread.Semaphore = .{},

        pub fn enqueue(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            const node = try self.allocator.create(Node(T));
            node.* = .{ .data = value, .next = null };
            if (self.end) |end| end.next = node else self.start = node;
            self.end = node;
            self.available.post();
        }

        pub fn dequeue(self: *Self) ?T {
            self.available.wait();
            self.mutex.lock();
            defer self.mutex.unlock();
            const start = self.start orelse return null;
            defer self.allocator.destroy(start);
            if (start.next) |next|
                self.start = next
            else {
                self.start = null;
                self.end = null;
            }
            return start.data;
        }

        pub fn deinit(self: *Self) void {
            var event = self.dequeue();
            while (event) |e| {
                switch (e) {
                    else => {
                        std.log.info("Deallocating node\n", .{});
                    },
                }
                self.allocator.destroy(e);
                event = self.dequeue();
            }
        }

        pub fn print(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            var node = self.start;
            while (node) |n| {
                std.log.info("{s}", .{});
                node = n.next;
            }
        }
    };
}
