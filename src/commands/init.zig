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
                "ww() {{\n" ++
                    "  local out\n" ++
                    "  out=\"$(command ww \"$@\")\" || return\n" ++
                    "  if [[ \"$1\" == \"go\" || \"$1\" == \"default\" ]]; then\n" ++
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
