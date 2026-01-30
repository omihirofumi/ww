const std = @import("std");

pub const Parsed = struct {
    topic: ?[]const u8,
};

pub fn parse(it: *std.process.ArgIterator) !Parsed {
    const topic = it.next();
    if (it.next() != null) return error.InvalidArgs;
    return .{ .topic = topic };
}

pub fn run(parsed: Parsed) !void {
    var out_buf: [2048]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;

    if (parsed.topic == null) {
        try stdout.print(
            "ww - workspace helper for jj\n" ++
                "\n" ++
                "USAGE:\n" ++
                "  ww <command> [options] [args]\n" ++
                "\n" ++
                "COMMANDS:\n" ++
                "  new         Create workspace\n" ++
                "  go          Go to workspace (optionally create)\n" ++
                "  list        List workspaces\n" ++
                "  default     Go to default workspace\n" ++
                "  init        Print shell init\n" ++
                "  completion  Print completion script\n" ++
                "  help        Show help for a command\n" ++
                "\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  -h, --help  Show help\n" ++
                "\n" ++
                "CONFIGURATION:\n" ++
                "  Global:    ~/.config/ww/config.toml\n" ++
                "  Per-repo:  <repo>/.jj/ww.toml (overrides global)\n" ++
                "\n" ++
                "  workspace_location = sibling   # <repo>__<name> (default)\n" ++
                "  workspace_location = internal  # <repo>/.workspaces/<name>\n" ++
                "\n" ++
                "Run 'ww help <command>' for details on a command.\n",
            .{},
        );
        try stdout.flush();
        return;
    }

    const topic = parsed.topic.?;
    if (std.mem.eql(u8, topic, "new")) {
        try stdout.print(
            "USAGE:\n" ++
                "  ww new [options] <name>\n" ++
                "\n" ++
                "OPTIONS:\n" ++
                "  -r, --revision <revision>  Revision to use when creating\n" ++
                "  -h, --help                 Show help\n" ++
                "\n" ++
                "EXAMPLES:\n" ++
                "  ww new -r @- myws\n",
            .{},
        );
    } else if (std.mem.eql(u8, topic, "go")) {
        try stdout.print(
            "USAGE:\n" ++
                "  ww go [options] <name>\n" ++
                "\n" ++
                "OPTIONS:\n" ++
                "  -c, --create               Create workspace if missing\n" ++
                "  -r, --revision <revision>  Revision to use when creating\n" ++
                "  -h, --help                 Show help\n" ++
                "\n" ++
                "EXAMPLES:\n" ++
                "  ww go -c -r @- myws\n",
            .{},
        );
    } else if (std.mem.eql(u8, topic, "list")) {
        try stdout.print(
            "USAGE:\n" ++
                "  ww list\n",
            .{},
        );
    } else if (std.mem.eql(u8, topic, "default")) {
        try stdout.print(
            "USAGE:\n" ++
                "  ww default\n",
            .{},
        );
    } else if (std.mem.eql(u8, topic, "init")) {
        try stdout.print(
            "USAGE:\n" ++
                "  ww init <shell>\n" ++
                "\n" ++
                "ARGS:\n" ++
                "  shell  zsh\n",
            .{},
        );
    } else if (std.mem.eql(u8, topic, "completion")) {
        try stdout.print(
            "USAGE:\n" ++
                "  ww completion <shell>\n" ++
                "\n" ++
                "ARGS:\n" ++
                "  shell  zsh\n",
            .{},
        );
    } else if (std.mem.eql(u8, topic, "help")) {
        try stdout.print(
            "USAGE:\n" ++
                "  ww help [command]\n",
            .{},
        );
    } else {
        try stdout.print("unknown command: {s}\n", .{topic});
    }

    try stdout.flush();
}
