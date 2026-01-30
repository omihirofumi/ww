const std = @import("std");
const jj = @import("jj.zig");

/// Workspace location strategy
pub const WorkspaceLocation = enum {
    /// <repo>__<name> - sibling to repo (default, backward compatible)
    sibling,
    /// <repo>/.workspaces/<name> - nested within repo
    internal,

    pub fn fromString(s: []const u8) ?WorkspaceLocation {
        return std.meta.stringToEnum(WorkspaceLocation, s);
    }
};

/// Configuration for ww
pub const Config = struct {
    workspace_location: WorkspaceLocation = .sibling,

    /// Load config with per-repo overriding global
    pub fn load(allocator: std.mem.Allocator, repo_root: ?[]const u8) !Config {
        var config = Config{};

        // Load global config first
        if (getGlobalConfigPath(allocator)) |global_path| {
            defer allocator.free(global_path);
            if (loadFromFile(allocator, global_path)) |global_config| {
                config = global_config;
            } else |_| {
                // Global config doesn't exist or is invalid, use defaults
            }
        } else |_| {
            // Couldn't determine global config path, use defaults
        }

        // Load per-repo config (overrides global)
        if (repo_root) |root| {
            const repo_config_path = try std.fs.path.join(allocator, &.{ root, ".jj", "ww.toml" });
            defer allocator.free(repo_config_path);

            if (loadFromFile(allocator, repo_config_path)) |repo_config| {
                config = repo_config;
            } else |_| {
                // Per-repo config doesn't exist or is invalid, keep global/defaults
            }
        }

        return config;
    }

    fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
        defer file.close();

        var buf: [4096]u8 = undefined;
        var f_reader = file.reader(&buf);
        const reader = &f_reader.interface;

        const content = try reader.allocRemaining(allocator, .unlimited);
        defer allocator.free(content);

        return parseConfig(content);
    }

    fn parseConfig(content: []const u8) Config {
        var config = Config{};

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Skip empty lines and comments
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Parse key = value
            if (std.mem.indexOf(u8, trimmed, "=")) |eq_idx| {
                const key = std.mem.trim(u8, trimmed[0..eq_idx], " \t");
                var value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");

                // Strip inline comments (# preceded by whitespace)
                if (std.mem.indexOf(u8, value, " #")) |comment_idx| {
                    value = std.mem.trim(u8, value[0..comment_idx], " \t");
                }

                // Remove quotes if present
                if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                    value = value[1 .. value.len - 1];
                }

                if (std.mem.eql(u8, key, "workspace_location")) {
                    if (WorkspaceLocation.fromString(value)) |loc| {
                        config.workspace_location = loc;
                    }
                }
            }
        }

        return config;
    }
};

fn getGlobalConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    // Try XDG_CONFIG_HOME first, then fall back to ~/.config
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg_config| {
        return try std.fs.path.join(allocator, &.{ xdg_config, "ww", "config.toml" });
    }

    if (std.posix.getenv("HOME")) |home| {
        return try std.fs.path.join(allocator, &.{ home, ".config", "ww", "config.toml" });
    }

    return error.NoHomeDirectory;
}

/// Build workspace path based on location strategy
pub fn buildWorkspacePath(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    name: []const u8,
    location: WorkspaceLocation,
) ![]const u8 {
    return switch (location) {
        .sibling => std.mem.concat(allocator, u8, &[_][]const u8{
            repo_root,
            "__",
            name,
        }),
        .internal => std.fs.path.join(allocator, &.{ repo_root, ".workspaces", name }),
    };
}

test "parseConfig with sibling location" {
    const content = "workspace_location = sibling\n";
    const config = Config.parseConfig(content);
    try std.testing.expectEqual(WorkspaceLocation.sibling, config.workspace_location);
}

test "parseConfig with internal location" {
    const content = "workspace_location = internal\n";
    const config = Config.parseConfig(content);
    try std.testing.expectEqual(WorkspaceLocation.internal, config.workspace_location);
}

test "parseConfig with quoted value" {
    const content = "workspace_location = \"internal\"\n";
    const config = Config.parseConfig(content);
    try std.testing.expectEqual(WorkspaceLocation.internal, config.workspace_location);
}

test "parseConfig ignores comments" {
    const content = "# comment\nworkspace_location = internal\n";
    const config = Config.parseConfig(content);
    try std.testing.expectEqual(WorkspaceLocation.internal, config.workspace_location);
}

test "parseConfig defaults to sibling" {
    const content = "# only comments\n";
    const config = Config.parseConfig(content);
    try std.testing.expectEqual(WorkspaceLocation.sibling, config.workspace_location);
}

test "parseConfig strips inline comments" {
    const content = "workspace_location = internal # this is a comment\n";
    const config = Config.parseConfig(content);
    try std.testing.expectEqual(WorkspaceLocation.internal, config.workspace_location);
}

test "parseConfig preserves hash in value without preceding space" {
    const content = "workspace_location = internal#notacomment\n";
    const config = Config.parseConfig(content);
    // This should fail to parse since "internal#notacomment" is not a valid enum value
    // and should fall back to default
    try std.testing.expectEqual(WorkspaceLocation.sibling, config.workspace_location);
}

test "buildWorkspacePath sibling" {
    const allocator = std.testing.allocator;
    const path = try buildWorkspacePath(allocator, "/repo", "feature", .sibling);
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/repo__feature", path);
}

test "buildWorkspacePath internal" {
    const allocator = std.testing.allocator;
    const path = try buildWorkspacePath(allocator, "/repo", "feature", .internal);
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/repo/.workspaces/feature", path);
}
