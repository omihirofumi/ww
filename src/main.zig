const std = @import("std");
const ww = @import("ww.zig");

var writer_buf: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&writer_buf);
const stdout = &stdout_writer.interface;

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var args = std.process.args();
    _ = args.next();

    var app = ww.App{ .allocator = allocator };

    const cmd = app.parse(&args) catch {
        try printUsage();
        return;
    };

    try app.run(cmd);
}

fn printUsage() !void {
    try stderr.print("usage: ww new <name>\n", .{});
    try stderr.flush();
}
