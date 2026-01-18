const App = @This();

const std = @import("std");
const cmd_completion = @import("commands/completion.zig");
const cmd_go = @import("commands/go.zig");
const cmd_help = @import("commands/help.zig");
const cmd_init = @import("commands/init.zig");
const cmd_list = @import("commands/list.zig");
const cmd_new = @import("commands/new.zig");
const cmd_defalt = @import("commands/go_default.zig");
const cmd_forget = @import("commands/forget.zig");

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

const Command = union(enum) {
    new: cmd_new.Parsed,
    go: cmd_go.Parsed,
    help: cmd_help.Parsed,
    init_shell: cmd_init.Parsed,
    completion: cmd_completion.Parsed,
    list: cmd_list.Parsed,
    // go to default workspaec
    default: void,
    forget: cmd_forget.Parsed,
};

allocator: std.mem.Allocator,
last_subcommand: ?[]const u8 = null,

pub fn parse(self: *App, it: *std.process.ArgIterator) !Command {
    const subcommand = it.next() orelse return error.InvalidArgs;
    self.last_subcommand = subcommand;

    if (std.mem.eql(u8, subcommand, "new")) {
        return .{ .new = try cmd_new.parse(it) };
    }

    if (std.mem.eql(u8, subcommand, "go")) {
        return .{ .go = try cmd_go.parse(it) };
    }

    if (std.mem.eql(u8, subcommand, "help") or
        std.mem.eql(u8, subcommand, "-h") or
        std.mem.eql(u8, subcommand, "--help"))
    {
        return .{ .help = try cmd_help.parse(it) };
    }

    if (std.mem.eql(u8, subcommand, "init")) {
        return .{ .init_shell = try cmd_init.parse(it) };
    }

    if (std.mem.eql(u8, subcommand, "list")) {
        return .{ .list = try cmd_list.parse(it) };
    }

    if (std.mem.eql(u8, subcommand, "completion")) {
        return .{ .completion = try cmd_completion.parse(it) };
    }

    if (std.mem.eql(u8, subcommand, "default")) {
        return .{ .default = {} };
    }

    if (std.mem.eql(u8, subcommand, "forget")) {
        return .{ .forget = try cmd_forget.parse(it) };
    }

    return error.UnrecognizedSubcommand;
}

pub fn run(self: App, cmd: Command) !void {
    switch (cmd) {
        .new => |parsed| try cmd_new.run(self.allocator, parsed),
        .go => |parsed| {
            cmd_go.run(self.allocator, parsed) catch |err| {
                switch (err) {
                    error.WorkspaceNotFound => {
                        try stderr.print("workspace not found: {s}\n", .{parsed.name});
                        try stderr.flush();
                    },
                    // TODO: handling errors
                    else => {
                        try stderr.print("something happened. {}", .{err});
                        try stderr.flush();
                    },
                }
            };
        },
        .help => |parsed| try cmd_help.run(parsed),
        .init_shell => |parsed| try cmd_init.run(parsed),
        .completion => |parsed| try cmd_completion.run(parsed),
        .list => |parsed| try cmd_list.run(self.allocator, parsed),
        .default => try cmd_defalt.run(self.allocator),
        .forget => |parsed| try cmd_forget.run(self.allocator, parsed),
    }
}
