const std = @import("std");
const jj = @import("../jj.zig");

pub const Parsed = struct {
    name: ?[]const u8,
};

pub fn parse(it: *std.process.ArgIterator) !Parsed {
    const name = it.next() orelse null;
    if (it.next() != null) return error.InvalidArgs;
    return .{ .name = name };
}

pub fn run(allocaltor: std.mem.Allocator, parsed: Parsed) !void {
    var buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &stderr_writer.interface;

    jj.forgetWorkspace(allocaltor, parsed.name) catch |err| {
        switch (err) {
            error.CannotForgetCurrentDefault => {
                try stderr.print("Error: cannot forget default while it is the current workspace\n", .{});
            },
            else => {
                try stderr.print("Error: failed to forget workspace ({s})\n", .{@errorName(err)});
            },
        }
    };
}
