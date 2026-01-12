const std = @import("std");
const jj = @import("../jj.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    const default_root = try jj.defaultRoot(allocator);
    defer allocator.free(default_root);

    var buf: [1028]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buf);
    const stdout = &writer.interface;

    try stdout.print("cd {s}\n", .{default_root});
    try stdout.flush();
}
