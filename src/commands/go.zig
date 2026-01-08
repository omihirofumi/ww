const std = @import("std");
const jj = @import("../jj.zig");

pub const Parsed = struct {
    name: []const u8,
};

pub fn parse(it: *std.process.ArgIterator) !Parsed {
    const name = it.next() orelse return error.InvalidArgs;
    if (it.next() != null) return error.InvalidArgs;
    return .{ .name = name };
}

pub fn run(allocator: std.mem.Allocator, parsed: Parsed) !void {
    if (!(try existsWorkspace(allocator, parsed.name))) {
        return error.WorkspaceNotFound;
    }

    const repo_root = try jj.jjRoot(allocator);
    defer allocator.free(repo_root);

    const workspace_path = try jj.buildWorkspacePath(allocator, repo_root, parsed.name);
    defer allocator.free(workspace_path);

    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;
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
