const std = @import("std");
const ww = @import("ww");

var writer_buf: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&writer_buf);
const stdout = &stdout_writer.interface;

var error_buf: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&error_buf);
const stderr = &stderr_writer.interface;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var args = std.process.args();
    _ = args.next();

    const subcommand = args.next() orelse {
        try printUsage();
        return;
    };

    if (std.mem.eql(u8, subcommand, "new")) {
        const name = args.next() orelse {
            try printUsage();
            return;
        };

        const repo_root = try jjRoot(allocator);
        defer allocator.free(repo_root);

        const repo_name = std.fs.path.basename(repo_root);
        const home = std.posix.getenv("HOME") orelse return error.MissingHome;

        const target_path = try std.fs.path.join(allocator, &.{
            home,
            ".jj-workspace",
            repo_name,
            name,
        });
        defer allocator.free(target_path);

        try runJjWorkspaceAdd(allocator, target_path);
        return;
    }
    try printUsage();
}

fn printUsage() !void {
    try stderr.print("usage: ww new <name>\n", .{});
    try stderr.flush();
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
