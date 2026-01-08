const std = @import("std");
const App = @import("App.zig");

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var args = std.process.args();
    _ = args.next();

    var app = App{ .allocator = allocator };

    const cmd = app.parse(&args) catch |err| {
        switch (err) {
            error.UnrecognizedSubcommand => {
                if (app.last_subcommand) |name| {
                    try stderr.print("error: unrecognized subcommand '{s}'\n\n", .{name});
                } else {
                    try stderr.print("error: unrecognized subcommand\n\n", .{});
                }
            },
            else => {
                try stderr.print("error: invalid arguments\n\n", .{});
            },
        }

        try stderr.print(
            "Usage: ww [OPTIONS] <COMMAND>\n\n" ++
                "For more information, try '--help'.\n",
            .{},
        );
        try stderr.flush();
        return;
    };

    try app.run(cmd);
}
