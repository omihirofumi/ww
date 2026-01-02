const App = @This();

const std = @import("std");
const jj = @import("jj.zig");

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

const Command = union(enum) {
    new: []const u8,
    go: []const u8,
    init_shell: []const u8,
    list: void,
};

const Shell = enum { zsh };

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

    if (std.mem.eql(u8, subcommand, "init")) {
        const shell = args.next() orelse return error.InvalidArgs;
        if (!std.mem.eql(u8, shell, "zsh")) return error.ZshOnlySupported;
        return .{ .init_shell = shell };
    }

    if (std.mem.eql(u8, subcommand, "list")) {
        return .{ .list = {} };
    }
    return error.InvalidArgs;
}

pub fn run(self: App, cmd: Command) !void {
    switch (cmd) {
        .new => |name| try self.runNew(name),
        .go => |name| {
            self.runGo(name) catch |err| {
                switch (err) {
                    error.WorkspaceNotFound => {
                        try stderr.print("workspace not found: {s}\n", .{name});
                        try stderr.flush();
                    },
                    // TODO: handling errors
                    else => {
                        try stderr.print("something happened", .{});
                        try stderr.flush();
                    },
                }
            };
        },
        .init_shell => |shell| {
            const tag = std.meta.stringToEnum(Shell, shell) orelse return error.InvalidArgs;
            try self.runInitShell(tag);
        },
        .list => {
            try self.runList();
        },
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
    if (!(try existsWorkspace(self.allocator, name))) {
        return error.WorkspaceNotFound;
    }

    const repo_root = try jj.jjRoot(self.allocator);
    defer self.allocator.free(repo_root);

    const workspace_path = try jj.buildWorkspacePath(self.allocator, repo_root, name);
    defer self.allocator.free(workspace_path);

    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;
    try stdout.print("cd {s}\n", .{workspace_path});
    try stdout.flush();
}

fn runInitShell(self: App, shell: Shell) !void {
    _ = self;

    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;
    switch (shell) {
        .zsh => {
            try stdout.print(
                "ww() {{\n" ++
                    "  local out\n" ++
                    "  out=\"$(command ww \"$@\")\" || return\n" ++
                    "  if [[ \"$1\" == \"go\" ]]; then\n" ++
                    "    eval \"$out\"\n" ++
                    "  else\n" ++
                    "    print -r -- \"$out\"\n" ++
                    "  fi\n" ++
                    "}}\n",
                .{},
            );
            try stdout.flush();
        },
    }
}

fn runList(self: App) !void {
    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;

    const workspace_list = try jj.listWorkspaces(self.allocator);
    defer {
        for (workspace_list) |workspace| {
            self.allocator.free(workspace);
        }
        self.allocator.free(workspace_list);
    }

    for (workspace_list) |workspace| {
        try stdout.print("{s}\n", .{workspace});
    }
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
