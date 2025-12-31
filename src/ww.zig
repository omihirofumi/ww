const std = @import("std");

const Command = union(enum) {
    new: []const u8,
    go: []const u8,
};

pub const App = struct {
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
        const repo_root = try jjRoot(self.allocator);
        defer self.allocator.free(repo_root);

        const workspacePath = try buildWorkspacePath(self.allocator, repo_root, name);
        defer self.allocator.free(workspacePath);

        try runJjWorkspaceAdd(self.allocator, workspacePath);
    }

    fn runGo(self: App, name: []const u8) !void {
        const repo_root = try jjRoot(self.allocator);
        defer self.allocator.free(repo_root);

        const workspacePath = try buildWorkspacePath(self.allocator, repo_root, name);
        defer self.allocator.free(workspacePath);

        var out_buf: [1024]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        const stdout = &out_writer.interface;
        try stdout.print("{s}\n", .{workspacePath});
        try stdout.flush();
    }
};

fn buildWorkspacePath(allocator: std.mem.Allocator, repo_root: []const u8, name: []const u8) ![]const u8 {
    const repo_name = std.fs.path.basename(repo_root);
    const home = std.posix.getenv("HOME") orelse return error.MissingHome;

    return try std.fs.path.join(allocator, &.{
        home,
        ".jj-workspace",
        repo_name,
        name,
    });
}

fn jjRoot(allocator: std.mem.Allocator) ![]const u8 {
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

fn runJjWorkspaceAdd(allocator: std.mem.Allocator, path: []const u8) !void {
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
