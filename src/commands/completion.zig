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
                    "_ww_workspaces() {{\n" ++
                    "  local -a ws\n" ++
                    "  ws=(${{(f)\"$(ww list 2>/dev/null | grep -v '^default$')\"}})\n" ++
                    "  compadd -a ws\n" ++
                    "}}\n" ++
                    "\n" ++
                    "_ww() {{\n" ++
                    "  local -a subcmds\n" ++
                    "  subcmds=(\n" ++
                    "    'go:Go to workspace'\n" ++
                    "    'forget:Forget workspace'\n" ++
                    "    'new:Create workspace'\n" ++
                    "    'default:Go to default workspace'\n" ++
                    "    'list:List workspaces'\n" ++
                    "    'help:Show help'\n" ++
                    "  )\n" ++
                    "\n" ++
                    "  _arguments -C \\\n" ++
                    "    '(--version)--version[show version]' \\\n" ++
                    "    '1:command:->cmds' \\\n" ++
                    "    '*::arg:->args'\n" ++
                    "\n" ++
                    "  case $state in\n" ++
                    "    cmds)\n" ++
                    "      _describe -t commands 'ww command' subcmds\n" ++
                    "      ;;\n" ++
                    "    args)\n" ++
                    "      case $words[1] in\n" ++
                    "        go)\n" ++
                    "          _arguments \\\n" ++
                    "            '(-r --revision)-r[revision]:revision:' \\\n" ++
                    "            '(-r --revision)--revision[revision]:revision:' \\\n" ++
                    "            '(-c --create)-c[create if missing]' \\\n" ++
                    "            '(-c --create)--create[create if missing]' \\\n" ++
                    "            '1:workspace name:_ww_workspaces'\n" ++
                    "          ;;\n" ++
                    "        new)\n" ++
                    "          _arguments \\\n" ++
                    "            '(-r --revision)'{{-r,--revision}}'[revision]:revision:' \\\n" ++
                    "            '1:workspace name:'\n" ++
                    "          ;;\n" ++
                    "        forget)\n" ++
                    "          _arguments \\\n" ++
                    "            '1:workspace name:_ww_workspaces'\n" ++
                    "          ;;\n" ++
                    "        help)\n" ++
                    "          compadd go forget new default list help\n" ++
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
