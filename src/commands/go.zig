const std = @import("std");
const jj = @import("../jj.zig");
const config = @import("../config.zig");
const args = @import("args.zig");

pub const Options = struct {
    create: bool = false,
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

    // Load config (global + per-repo)
    const cfg = try config.Config.load(allocator, default_root);

    if (!(try existsWorkspace(allocator, parsed.name))) {
        if (!parsed.options.create) return error.WorkspaceNotFound;

        const workspace_path = try jj.buildWorkspacePath(allocator, default_root, parsed.name, cfg.workspace_location);
        defer allocator.free(workspace_path);

        try jj.runJjWorkspaceAdd(allocator, workspace_path, parsed.options.revision, parsed.name);

        // Run post-workspace-add hook if it exists
        jj.runPostWorkspaceAddHook(allocator, default_root, workspace_path, parsed.name);
    }

    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;

    // if destination is default, go to root.
    const default_workspace = try jj.defaultWorkspaceName(allocator);
    defer allocator.free(default_workspace);

    if (std.mem.eql(u8, parsed.name, default_workspace)) {
        try stdout.print("cd {s}\n", .{default_root});
        try stdout.flush();
        return;
    }

    const workspace_path = try jj.buildWorkspacePath(allocator, default_root, parsed.name, cfg.workspace_location);
    defer allocator.free(workspace_path);

    try stdout.print("cd {s}\n", .{workspace_path});
    try stdout.flush();
}

fn existsWorkspace(allocator: std.mem.Allocator, name: []const u8) !bool {
    const workspace_list = try jj.listWorkspaces(allocator);
    defer {
        for (workspace_list) |workspace| {
            allocator.free(workspace);
        }
        allocator.free(workspace_list);
    }
    for (workspace_list) |workspace| {
        if (std.mem.eql(u8, workspace, name)) {
            return true;
        }
    }
    return false;
}
