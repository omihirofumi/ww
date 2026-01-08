const std = @import("std");
const shell = @import("shell.zig");

pub const Parsed = struct {
    shell: shell.Shell,
};

pub fn parse(it: *std.process.ArgIterator) !Parsed {
    const shell_name = it.next() orelse return error.InvalidArgs;
    const tag = std.meta.stringToEnum(shell.Shell, shell_name) orelse return error.InvalidArgs;
    if (it.next() != null) return error.InvalidArgs;
    return .{ .shell = tag };
}

pub fn run(parsed: Parsed) !void {
    var out_buf: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &out_writer.interface;

    switch (parsed.shell) {
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
                    "    'help:Show help'\n" ++
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
                    "          _arguments -C \\\n" ++
                    "            '(-r --revision)'{{-r,--revision}}'[revision]:revision:' \\\n" ++
                    "            '1:workspace name:'\n" ++
                    "          ;;\n" ++
                    "        init|completion)\n" ++
                    "          compadd zsh\n" ++
                    "          ;;\n" ++
                    "        help)\n" ++
                    "          compadd new go list init completion help\n" ++
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
