const std = @import("std");
const protobuf = @import("protobuf/decode.zig");

pub fn buildWorkspacePath(allocator: std.mem.Allocator, repo_root: []const u8, name: []const u8) ![]const u8 {
    return std.mem.concat(allocator, u8, &[_][]const u8{
        repo_root,
        "__",
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

pub fn runJjWorkspaceAdd(allocator: std.mem.Allocator, path: []const u8, revision: ?[]const u8, name: ?[]const u8) !void {
    var args = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    defer args.deinit(allocator);

    try args.append(allocator, "jj");
    try args.append(allocator, "workspace");
    try args.append(allocator, "add");
    if (revision) |rev| {
        try args.append(allocator, "-r");
        try args.append(allocator, rev);
    }
    if (name) |n| {
        try args.append(allocator, "--name");
        try args.append(allocator, n);
    }
    try args.append(allocator, path);

    var child = std.process.Child.init(args.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.RunJjWorkspaceAddFailed,
        else => return error.RunJjWorkspaceAddFailed,
    }
}

pub fn listWorkspaces(allocator: std.mem.Allocator) ![]const []const u8 {
    var child = std.process.Child.init(&.{ "jj", "workspace", "list" }, allocator);
    child.stdin_behavior = .Inherit;
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

    var trimmed = std.mem.splitSequence(u8, out, "\n");
    var workspace_list = try std.ArrayList([]const u8).initCapacity(allocator, 100);
    while (trimmed.next()) |val| {
        const line = std.mem.trimEnd(u8, val, "\r");
        if (line.len == 0) continue;
        var workspace_name_line = std.mem.splitScalar(u8, line, ':');
        const workspace_name = try allocator.dupe(u8, workspace_name_line.first());
        try workspace_list.append(allocator, workspace_name);
    }

    return workspace_list.toOwnedSlice(allocator);
}

const Checkout = struct {
    workspace_name: []const u8 = &.{},
};

// The workspace name is written in protobuf encoded format at .jj/workspace/checkout
fn decodeCheckout(allocator: std.mem.Allocator) !Checkout {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(".jj/working_copy/checkout", .{ .mode = .read_only });
    defer file.close();

    var f_buf: [1024]u8 = undefined;
    var f_reader = file.reader(&f_buf);
    const reader = &f_reader.interface;

    const content = try reader.allocRemaining(allocator, .unlimited);
    var decode_reader = protobuf.Reader.init(content);
    const checkout = try protobuf.decodeCheckout(&decode_reader);
    return checkout;
}
