const App = @This();

const std = @import("std");
const jj = @import("jj.zig");
const args = @import("cli/args.zig");

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

const Command = union(enum) {
    new: struct { name: []const u8, revision: ?[]const u8 },
    go: []const u8,
    init_shell: []const u8,
    completion: []const u8,
    list: void,
};

const NewOptions = struct {
    revision: ?[]const u8 = null,
};

fn parseNewArgs(it: *std.process.ArgIterator) !struct {
    name: []const u8,
    opts: NewOptions,
} {
    var opts: NewOptions = .{};
    const name = try args.parseOptions(NewOptions, &opts, it) orelse return error.InvalidArgs;
    if (it.next() != null) return error.InvalidArgs;
    return .{ .name = name, .opts = opts };
}

const Shell = enum { zsh };

allocator: std.mem.Allocator,

pub fn parse(self: App, it: *std.process.ArgIterator) !Command {
    _ = self;
    const subcommand = it.next() orelse return error.InvalidArgs;

    if (std.mem.eql(u8, subcommand, "new")) {
        const parsed = try parseNewArgs(it);
        return .{ .new = .{ .name = parsed.name, .revision = parsed.opts.revision } };
    }

    if (std.mem.eql(u8, subcommand, "go")) {
        const name = it.next() orelse return error.InvalidArgs;
        return .{ .go = name };
    }

    if (std.mem.eql(u8, subcommand, "init")) {
        const shell = it.next() orelse return error.InvalidArgs;
        return .{ .init_shell = shell };
    }

    if (std.mem.eql(u8, subcommand, "list")) {
        return .{ .list = {} };
    }

    if (std.mem.eql(u8, subcommand, "completion")) {
        const shell = it.next() orelse return error.InvalidArgs;
        return .{ .completion = shell };
    }
    return error.InvalidArgs;
}

pub fn run(self: App, cmd: Command) !void {
    switch (cmd) {
        .new => |v| try self.runNew(v.name, .{ .revision = v.revision }),
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
        .completion => |shell| {
            const tag = std.meta.stringToEnum(Shell, shell) orelse return error.InvalidArgs;
            try self.runCompletion(tag);
        },
        .list => {
            try self.runList();
        },
    }
}

fn runNew(self: App, name: []const u8, opts: NewOptions) !void {
    const repo_root = try jj.jjRoot(self.allocator);
    defer self.allocator.free(repo_root);

    const workspace_path = try jj.buildWorkspacePath(self.allocator, repo_root, name);
    defer self.allocator.free(workspace_path);

    try jj.runJjWorkspaceAdd(self.allocator, workspace_path, opts.revision);
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

fn runCompletion(self: App, shell: Shell) !void {
    _ = self;

    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;

    switch (shell) {
        .zsh => {
            try stdout.print(
                "#compdef ww\n" ++
                    "\n" ++
                    "_ww() {{\n" ++
                    "  local -a subcmds\n" ++
                    "  subcmds=(\n" ++
                    "    'new:Create workspace'\n" ++
                    "    'go:Go to workspace'\n" ++
                    "    'list:List workspaces'\n" ++
                    "    'init:Print shell init'\n" ++
                    "    'completion:Print completion script'\n" ++
                    "  )\n" ++
                    "\n" ++
                    "  _arguments -C \\\n" ++
                    "    '1:command:->cmds' \\\n" ++
                    "    '2:arg:->args' && return 0\n" ++
                    "\n" ++
                    "  case $state in\n" ++
                    "    cmds)\n" ++
                    "      _describe -t commands 'ww command' subcmds\n" ++
                    "      ;;\n" ++
                    "    args)\n" ++
                    "      case $words[2] in\n" ++
                    "        go)\n" ++
                    "          compadd -- $(ww list)\n" ++
                    "          ;;\n" ++
                    "        new)\n" ++
                    "          _message 'workspace name'\n" ++
                    "          ;;\n" ++
                    "        init|completion)\n" ++
                    "          compadd zsh\n" ++
                    "          ;;\n" ++
                    "      esac\n" ++
                    "      ;;\n" ++
                    "  esac\n" ++
                    "}}\n" ++
                    "\n" ++
                    "compdef _ww ww\n",
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
