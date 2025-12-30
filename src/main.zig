const std = @import("std");
const ww = @import("ww");

var writer_buf: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&writer_buf);
const stdout = &stdout_writer.interface;

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

pub fn main() !void {
    // read args
    var args_iter = std.process.args();
    if (args_iter.inner.count != 3) {
        try stderr.print("usage: ", .{});
        try stderr.flush();
        return;
    }
    while (args_iter.next()) |val| {
        try stdout.print("args: {s}", .{val});
    }
    try stdout.flush();
}
