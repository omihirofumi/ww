const std = @import("std");
const protobuf = @import("protobuf/decode.zig");
const config = @import("config.zig");

const checkout_path = ".jj/working_copy/checkout";
const repo_path = ".jj/repo";

pub const Error = error{ NoStdout, JjRootFailed, RunJjWorkspaceAddFailed,
    // // The current workspace cannot be forgotten.
    CannotForgetCurrentDefault, ForgetWorkspaceFailed, Unknown };

/// Build workspace path using the configured location strategy
/// Delegates to config.buildWorkspacePath
pub fn buildWorkspacePath(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    name: []const u8,
    location: config.WorkspaceLocation,
) ![]const u8 {
    return config.buildWorkspacePath(allocator, repo_root, name, location);
}

pub fn defaultRoot(allocator: std.mem.Allocator) ![]const u8 {
    const root = try jjRoot(allocator);

    // in the default workspace, just retun `jj root`
    if (try isCurrentdefault(allocator)) {
        return root;
    }
    defer allocator.free(root);

    const current_workspace_repo = try std.fs.path.join(allocator, &.{ root, repo_path });
    defer allocator.free(current_workspace_repo);

    const repo = try std.fs.openFileAbsolute(current_workspace_repo, .{ .mode = .read_only });
    defer repo.close();

    var buf: [1024]u8 = undefined;
    var f_reader = repo.reader(&buf);
    const reader = &f_reader.interface;

    var default_root: [1024]u8 = undefined;
    const n = try reader.readSliceShort(&default_root);

    // the content of .jj/repo is here.
    // ----------------
    // <default_workspace>/.jj/repo
    // ------------
    // -> <default_workspace> length = n - repo_path.len
    return try allocator.dupe(u8, default_root[0 .. n - repo_path.len]);
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

pub fn runJjWorkspaceAdd(allocator: std.mem.Allocator, path: []const u8, revision: ?[]const u8, name: ?[]const u8) !void {
    // Ensure parent directory exists (needed for internal workspace location)
    if (std.fs.path.dirname(path)) |parent| {
        std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
            error.PathAlreadyExists => {}, // Already exists, that's fine
            else => return err,
        };
    }

    var args = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    defer args.deinit(allocator);

    try args.append(allocator, "jj");
    try args.append(allocator, "workspace");
    try args.append(allocator, "add");
    if (revision) |rev| {
        try args.append(allocator, "-r");
        try args.append(allocator, rev);
    }
    if (name) |n| {
        try args.append(allocator, "--name");
        try args.append(allocator, n);
    }
    try args.append(allocator, path);

    var child = std.process.Child.init(args.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.RunJjWorkspaceAddFailed,
        else => return error.RunJjWorkspaceAddFailed,
    }
}

/// Run a hook if it exists.
/// Hook location: <repo_root>/.jj/hooks/<hook_name>
/// Environment variables set: WW_WORKSPACE_NAME, WW_WORKSPACE_PATH
/// On failure, prints a warning but does not fail.
fn runHook(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    hook_name: []const u8,
    workspace_path: []const u8,
    workspace_name: []const u8,
) void {
    const hook_path = std.fs.path.join(allocator, &.{ repo_root, ".jj", "hooks", hook_name }) catch return;
    defer allocator.free(hook_path);

    // Check if hook exists
    const hook_file = std.fs.openFileAbsolute(hook_path, .{ .mode = .read_only }) catch return;
    hook_file.close();

    // Run the hook with repo_root as working directory
    var child = std.process.Child.init(&.{hook_path}, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    // Set working directory to repo root
    child.cwd = repo_root;

    // Set environment variables
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();

    // Copy existing environment
    if (std.process.getEnvMap(allocator)) |system_env| {
        var it = system_env.iterator();
        while (it.next()) |entry| {
            env_map.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
        @constCast(&system_env).deinit();
    } else |_| {}

    // Add our variables
    env_map.put("WW_WORKSPACE_NAME", workspace_name) catch {};
    env_map.put("WW_WORKSPACE_PATH", workspace_path) catch {};

    child.env_map = &env_map;

    child.spawn() catch |err| {
        printHookWarning(hook_name, "failed to run: {}", .{err});
        return;
    };

    const term = child.wait() catch |err| {
        printHookWarning(hook_name, "failed to wait: {}", .{err});
        return;
    };

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                printHookWarning(hook_name, "exited with code {d}", .{code});
            }
        },
        else => {
            printHookWarning(hook_name, "terminated abnormally", .{});
        },
    }
}

fn printHookWarning(hook_name: []const u8, comptime fmt: []const u8, args: anytype) void {
    var out_buf: [1024]u8 = undefined;
    var err_writer = std.fs.File.stderr().writer(&out_buf);
    const stderr = &err_writer.interface;
    stderr.print("warning: {s} hook " ++ fmt ++ "\n", .{hook_name} ++ args) catch {};
    stderr.flush() catch {};
}

/// Run the post-workspace-add hook if it exists.
pub fn runPostWorkspaceAddHook(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    workspace_path: []const u8,
    workspace_name: []const u8,
) void {
    runHook(allocator, repo_root, "post-workspace-add", workspace_path, workspace_name);
}

/// Run the post-workspace-forget hook if it exists.
pub fn runPostWorkspaceForgetHook(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    workspace_path: []const u8,
    workspace_name: []const u8,
) void {
    runHook(allocator, repo_root, "post-workspace-forget", workspace_path, workspace_name);
}

pub fn listWorkspaces(allocator: std.mem.Allocator) ![]const []const u8 {
    var child = std.process.Child.init(&.{ "jj", "workspace", "list" }, allocator);
    child.stdin_behavior = .Inherit;
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

    var trimmed = std.mem.splitSequence(u8, out, "\n");
    var workspace_list = try std.ArrayList([]const u8).initCapacity(allocator, 100);
    while (trimmed.next()) |val| {
        const line = std.mem.trimEnd(u8, val, "\r");
        if (line.len == 0) continue;
        var workspace_name_line = std.mem.splitScalar(u8, line, ':');
        const workspace_name = try allocator.dupe(u8, workspace_name_line.first());
        try workspace_list.append(allocator, workspace_name);
    }

    return workspace_list.toOwnedSlice(allocator);
}

pub fn defaultWorkspaceName(allocator: std.mem.Allocator) ![]const u8 {
    const default_root = try defaultRoot(allocator);
    defer allocator.free(default_root);

    const default_workspace_checkout_path = try std.fs.path.join(allocator, &.{ default_root, checkout_path });
    defer allocator.free(default_workspace_checkout_path);

    const file = try std.fs.openFileAbsolute(default_workspace_checkout_path, .{ .mode = .read_only });
    defer file.close();

    return try decodeWorkspaceName(allocator, file);
}

/// Get the current workspace name (public wrapper)
pub fn currentWorkspaceNamePublic(allocator: std.mem.Allocator) ![]const u8 {
    return currentWorkspaceName(allocator);
}

pub fn forgetWorkspace(allocator: std.mem.Allocator, workspace_name: ?[]const u8) Error!void {
    const forget_workspace: []const u8 = value: {
        if (workspace_name) |name| {
            break :value name;
        }

        const is_currrent_default = isCurrentdefault(allocator) catch {
            return Error.Unknown;
        };
        if (is_currrent_default) {
            return Error.CannotForgetCurrentDefault;
        }

        if (currentWorkspaceName(allocator)) |current_workspace_name| {
            break :value current_workspace_name;
        } else |_| {
            return Error.Unknown;
        }
    };

    var child = std.process.Child.init(&.{ "jj", "workspace", "forget", forget_workspace }, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    child.spawn() catch return Error.ForgetWorkspaceFailed;
    const term = child.wait() catch return Error.ForgetWorkspaceFailed;
    switch (term) {
        .Exited => |code| if (code != 0) return Error.ForgetWorkspaceFailed,
        else => return Error.ForgetWorkspaceFailed,
    }
}

fn isCurrentdefault(allocator: std.mem.Allocator) !bool {
    const root = try jjRoot(allocator);
    defer allocator.free(root);

    const current_workspace_repo = try std.fs.path.join(allocator, &.{ root, repo_path });
    defer allocator.free(current_workspace_repo);

    const file = try std.fs.openFileAbsolute(current_workspace_repo, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();
    return if (stat.kind == .directory) true else false;
}

// The workspace name is written in protobuf encoded format at .jj/workspace/checkout
fn currentWorkspaceName(allocator: std.mem.Allocator) ![]const u8 {
    const current_workspace_checkout_path = try currenWorkspaceCheckoutPath(allocator);
    defer allocator.free(current_workspace_checkout_path);

    const file = try std.fs.openFileAbsolute(current_workspace_checkout_path, .{ .mode = .read_only });
    defer file.close();

    return try decodeWorkspaceName(allocator, file);
}

fn currenWorkspaceCheckoutPath(allocator: std.mem.Allocator) ![]const u8 {
    const root = try jjRoot(allocator);
    defer allocator.free(root);

    return try std.fs.path.join(allocator, &.{ root, checkout_path });
}

fn decodeWorkspaceName(allocator: std.mem.Allocator, file: std.fs.File) ![]const u8 {
    var f_buf: [1024]u8 = undefined;
    var f_reader = file.reader(&f_buf);
    const reader = &f_reader.interface;

    const content = try reader.allocRemaining(allocator, .unlimited);
    defer allocator.free(content);

    var decode_reader = protobuf.Reader.init(content);
    const checkout = try protobuf.decodeCheckout(&decode_reader);
    return try allocator.dupe(u8, checkout.workspace_name);
}
