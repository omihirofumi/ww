const std = @import("std");
const jj = @import("../jj.zig");
const args = @import("args.zig");

pub const Options = struct {
    revision: ?[]const u8 = null,
};

pub const Parsed = struct {
    name: []const u8,
    options: Options,
};

pub fn parse(it: *std.process.ArgIterator) !Parsed {
    var options: Options = .{};
    const name = try args.parseOptions(Options, &options, it) orelse return error.InvalidArgs;
    if (it.next() != null) return error.InvalidArgs;
    return .{ .name = name, .options = options };
}

pub fn run(allocator: std.mem.Allocator, parsed: Parsed) !void {
    const default_root = try jj.defaultRoot(allocator);
    defer allocator.free(default_root);

    const workspace_path = try jj.buildWorkspacePath(allocator, default_root, parsed.name);
    defer allocator.free(workspace_path);

    try jj.runJjWorkspaceAdd(allocator, workspace_path, parsed.options.revision, parsed.name);
}
