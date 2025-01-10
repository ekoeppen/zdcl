const std = @import("std");

var termios: std.posix.termios = undefined;

pub fn makeRaw(fd: std.posix.fd_t) !void {
    termios = try std.posix.tcgetattr(fd);
    var raw = termios;
    raw.cflag |= std.c.CLOCAL | std.c.CREAD | std.c.HUPCL;
    raw.cflag &= ~(std.c.IXON | std.c.IXOFF);
    raw.lflag = 0;
    try std.posix.tcsetattr(fd, .NOW, raw);
}

pub fn restore(fd: std.posix.fd_t) void {
    std.posix.tcsetattr(fd, .NOW, termios) catch {};
}

pub fn setSpeed(fd: std.posix.fd_t, _: u32) !void {
    termios = try std.posix.tcgetattr(fd);
    var raw = termios;
    raw.ispeed = std.c.speed_t.B115200; // speed;
    raw.ospeed = std.c.speed_t.B115200; // speed;
    try std.posix.tcsetattr(fd, .NOW, raw);
}
