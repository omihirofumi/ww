const App = @This();

const std = @import("std");
const jj = @import("jj.zig");

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

const Command = union(enum) {
    new: []const u8,
    go: []const u8,
};

allocator: std.mem.Allocator,

pub fn parse(self: App, args: *std.process.ArgIterator) !Command {
    _ = self;
    const subcommand = args.next() orelse return error.InvalidArgs;

    if (std.mem.eql(u8, subcommand, "new")) {
        const name = args.next() orelse return error.InvalidArgs;
        return .{ .new = name };
    }

    if (std.mem.eql(u8, subcommand, "go")) {
        const name = args.next() orelse return error.InvalidArgs;
        return .{ .go = name };
    }

    return error.InvalidArgs;
}

pub fn run(self: App, cmd: Command) !void {
    switch (cmd) {
        .new => |name| try self.runNew(name),
        .go => |name| try self.runGo(name),
    }
}

fn runNew(self: App, name: []const u8) !void {
    const repo_root = try jj.jjRoot(self.allocator);
    defer self.allocator.free(repo_root);

    const workspace_path = try jj.buildWorkspacePath(self.allocator, repo_root, name);
    defer self.allocator.free(workspace_path);

    try jj.runJjWorkspaceAdd(self.allocator, workspace_path);
}

fn runGo(self: App, name: []const u8) !void {
    const workspace_list = try jj.listWorkspaces(self.allocator);
    defer {
        for (workspace_list) |workspace| {
            self.allocator.free(workspace);
        }
        self.allocator.free(workspace_list);
    }
    var workspace_exists = false;
    for (workspace_list) |workspace| {
        if (std.mem.eql(u8, workspace, name)) {
            workspace_exists = true;
            break;
        }
    }
    if (!workspace_exists) {
        try stderr.print("{s} does not exist.\n", .{name});
        try stderr.flush();
        return error.WorkspaceNotFound;
    }

    const repo_root = try jj.jjRoot(self.allocator);
    defer self.allocator.free(repo_root);

    const workspace_path = try jj.buildWorkspacePath(self.allocator, repo_root, name);
    defer self.allocator.free(workspace_path);

    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;
    try stdout.print("{s}\n", .{workspace_path});
    try stdout.flush();
}
