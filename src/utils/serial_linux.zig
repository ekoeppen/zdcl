const std = @import("std");

var termios: std.os.termios = undefined;

pub fn makeRaw(fd: std.os.fd_t) !void {
    termios = try std.os.tcgetattr(fd);
    var raw = termios;
    raw.cflag |= std.os.linux.CLOCAL | std.os.linux.CREAD | std.os.linux.HUPCL;
    raw.cflag &= ~(std.os.linux.IXON | std.os.linux.IXOFF);
    raw.lflag = 0;
    try std.os.tcsetattr(fd, .NOW, raw);
}

pub fn restore(fd: std.os.fd_t) void {
    std.os.tcsetattr(fd, .NOW, termios) catch {};
}

pub fn setSpeed(fd: std.os.fd_t, speed: u32) !void {
    termios = try std.os.tcgetattr(fd);
    var raw = termios;
    raw.ispeed = speed;
    raw.ospeed = speed;
    try std.os.tcsetattr(fd, .NOW, raw);
}
