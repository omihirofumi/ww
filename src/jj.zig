const std = @import("std");

pub fn buildWorkspacePath(allocator: std.mem.Allocator, repo_root: []const u8, name: []const u8) ![]const u8 {
    const repo_name = std.fs.path.basename(repo_root);
    const home = std.posix.getenv("HOME") orelse return error.MissingHome;

    return try std.fs.path.join(allocator, &.{
        home,
        ".jj-workspace",
        repo_name,
        name,
    });
}

pub fn jjRoot(allocator: std.mem.Allocator) ![]const u8 {
    var child = std.process.Child.init(&.{ "jj", "root" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;

    try child.spawn();

    const stdout_file = child.stdout orelse return error.NoStdout;

    var io_buf: [1024]u8 = undefined;
    var file_reader = stdout_file.reader(&io_buf);
    const r = &file_reader.interface;

    const out = try r.allocRemaining(allocator, .unlimited);
    defer allocator.free(out);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.JjRootFailed,
        else => return error.JjRootFailed,
    }

    const trimmed = std.mem.trimEnd(u8, out, "\r\n");

    return try allocator.dupe(u8, trimmed);
}

pub fn runJjWorkspaceAdd(allocator: std.mem.Allocator, path: []const u8) !void {
    var child = std.process.Child.init(&.{ "jj", "workspace", "add", path }, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.runJjWorkspaceAddFailed,
        else => return error.runJjWorkspaceAddFailed,
    }
}

