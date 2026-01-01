const std = @import("std");
const jj = @import("jj.zig");

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
        const repo_root = try jj.jjRoot(self.allocator);
        defer self.allocator.free(repo_root);

        const workspacePath = try jj.buildWorkspacePath(self.allocator, repo_root, name);
        defer self.allocator.free(workspacePath);

        try jj.runJjWorkspaceAdd(self.allocator, workspacePath);
    }

    fn runGo(self: App, name: []const u8) !void {
        const repo_root = try jj.jjRoot(self.allocator);
        defer self.allocator.free(repo_root);

        const workspacePath = try jj.buildWorkspacePath(self.allocator, repo_root, name);
        defer self.allocator.free(workspacePath);

        var out_buf: [1024]u8 = undefined;
        var out_writer = std.fs.File.stdout().writer(&out_buf);
        const stdout = &out_writer.interface;
        try stdout.print("{s}\n", .{workspacePath});
        try stdout.flush();
    }
};
