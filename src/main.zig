const std = @import("std");
const App = @import("App.zig");

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var args = std.process.args();
    _ = args.next();

    var app = App{ .allocator = allocator };

    const cmd = app.parse(&args) catch {
        try printUsage();
        return;
    };

    try app.run(cmd);
}

fn printUsage() !void {
    try stderr.print("usage: ww new/go <name>\n", .{});
    try stderr.flush();
}
