const std = @import("std");
const jj = @import("../jj.zig");

pub const Parsed = struct {
    unused: bool = true,
};

pub fn parse(it: *std.process.ArgIterator) !Parsed {
    if (it.next() != null) return error.InvalidArgs;
    return .{};
}

pub fn run(allocator: std.mem.Allocator, _: Parsed) !void {
    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;

    const workspace_list = try jj.listWorkspaces(allocator);
    defer {
        for (workspace_list) |workspace| {
            allocator.free(workspace);
        }
        allocator.free(workspace_list);
    }

    for (workspace_list) |workspace| {
        try stdout.print("{s}\n", .{workspace});
    }
    try stdout.flush();
}
