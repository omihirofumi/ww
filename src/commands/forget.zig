const std = @import("std");
const jj = @import("../jj.zig");
const config = @import("../config.zig");

pub const Parsed = struct {
    name: ?[]const u8,
};

pub fn parse(it: *std.process.ArgIterator) !Parsed {
    const name = it.next() orelse null;
    if (it.next() != null) return error.InvalidArgs;
    return .{ .name = name };
}

pub fn run(allocator: std.mem.Allocator, parsed: Parsed) !void {
    var buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &stderr_writer.interface;

    // Get workspace info before forgetting (for hook)
    const default_root = jj.defaultRoot(allocator) catch |err| {
        try stderr.print("Error: failed to get repository root ({s})\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(default_root);

    // Determine workspace name to forget
    const workspace_name: []const u8 = if (parsed.name) |name|
        name
    else
        jj.currentWorkspaceNamePublic(allocator) catch |err| {
            try stderr.print("Error: failed to get current workspace name ({s})\n", .{@errorName(err)});
            return;
        };
    defer if (parsed.name == null) allocator.free(workspace_name);

    // Build workspace path for hook
    const cfg = config.Config.load(allocator, default_root) catch config.Config{};
    const workspace_path = jj.buildWorkspacePath(allocator, default_root, workspace_name, cfg.workspace_location) catch |err| {
        try stderr.print("Error: failed to build workspace path ({s})\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(workspace_path);

    jj.forgetWorkspace(allocator, parsed.name) catch |err| {
        switch (err) {
            error.CannotForgetCurrentDefault => {
                try stderr.print("Error: cannot forget default while it is the current workspace\n", .{});
            },
            else => {
                try stderr.print("Error: failed to forget workspace ({s})\n", .{@errorName(err)});
            },
        }
        return;
    };

    // Run post-workspace-forget hook if it exists
    jj.runPostWorkspaceForgetHook(allocator, default_root, workspace_path, workspace_name);
}
