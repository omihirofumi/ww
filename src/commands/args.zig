// This code is heavily based on the following implementation:
// https://github.com/ghostty-org/ghostty/blob/b4a44bc47ef7c64f9fcb714be5002cdb92e79b9a/src/cli/args.zig
//
const std = @import("std");
const mem = std.mem;

const log = std.log.scoped(.cli);

pub const whitespace = " \t";

pub fn parseOptions(
    comptime T: type,
    dst: *T,
    args: *std.process.ArgIterator,
) !?[]const u8 {
    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "--")) {
            return args.next();
        }

        if (mem.startsWith(u8, arg, "--")) {
            var key: []const u8 = arg[2..];
            var value: ?[]const u8 = null;

            if (mem.indexOf(u8, key, "=")) |idx| {
                value = key[idx + 1 ..];
                key = key[0..idx];
            } else {
                if (!isBoolField(T, key)) {
                    value = args.next() orelse return error.InvalidArgs;
                }
            }

            try parseIntoField(T, dst, key, value);
            continue;
        }

        if (mem.startsWith(u8, arg, "-") and arg.len == 2) {
            const short = arg[1..2];
            const long = shortToLong(short) orelse return error.InvalidArgs;

            if (isBoolField(T, long)) {
                try parseIntoField(T, dst, long, "true");
                continue;
            }

            const value = args.next() orelse return error.InvalidArgs;

            try parseIntoField(T, dst, long, value);
            continue;
        }

        return arg;
    }

    return null;
}

fn isBoolField(comptime T: type, key: []const u8) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("isBoolField requires a struct");
    }

    inline for (info.@"struct".fields) |field| {
        if (mem.eql(u8, field.name, key)) {
            const Field = switch (@typeInfo(field.type)) {
                .optional => |opt| opt.child,
                else => field.type,
            };
            return Field == bool;
        }
    }

    return false;
}

fn shortToLong(short: []const u8) ?[]const u8 {
    if (mem.eql(u8, short, "r")) return "revision";
    if (mem.eql(u8, short, "c")) return "create";
    return null;
}

fn parseIntoField(
    comptime T: type,
    dst: *T,
    key: []const u8,
    value: ?[]const u8,
) !void {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("parseIntoField requires a struct");

    inline for (info.@"struct".fields) |field| {
        if (mem.eql(u8, field.name, key)) {
            const Field = switch (@typeInfo(field.type)) {
                .optional => |opt| opt.child,
                else => field.type,
            };
            const field_info = @typeInfo(Field);

            @field(dst, field.name) = switch (Field) {
                []const u8 => value orelse return error.InvalidArgs,
                bool => try parseBool(value orelse "t"),
                i8,
                i16,
                i32,
                i64,
                i128,
                isize,
                u8,
                u16,
                u32,
                u64,
                u128,
                usize,
                => |Int| std.fmt.parseInt(
                    Int,
                    value orelse return error.ValueRequired,
                    10,
                ),
                f16, f32, f64, f80, f128 => |Float| std.fmt.parseFloat(
                    Float,
                    value orelse return error.ValueRequired,
                ),
                else => switch (field_info) {
                    .@"enum" => std.meta.stringToEnum(
                        Field,
                        value orelse return error.ValueRequired,
                    ) orelse return error.InvalidValue,
                    else => return error.InvalidValue,
                },
            };
            return;
        }
    }

    return error.InvalidArgs;
}

fn parseBool(v: []const u8) !bool {
    const t = &[_][]const u8{ "1", "t", "T", "true" };
    const f = &[_][]const u8{ "0", "f", "F", "false" };

    for (t) |tv| if (mem.eql(u8, v, tv)) return true;
    for (f) |fv| if (mem.eql(u8, v, fv)) return false;

    return error.InvalidValue;
}

pub const LineIterator = struct {
    const Self = @This();

    pub const MAX_LINE_SIZE = 4096;

    r: *std.Io.Reader,

    filepath: []const u9 = "",

    line: usize = 0,

    entry: [MAX_LINE_SIZE]u8 = [_]u8{ '-', '-' } ++ ([_]u8{0} ** (MAX_LINE_SIZE - 2)),

    pub fn init(reader: *std.Io.Reader) Self {
        return .{ .r = reader };
    }

    pub fn next(self: *Self) ?[]const u8 {
        if (self.r.bufferedLen() < self.r.buffer.len) {
            self.r.fillMore() catch {};
        }

        var writer: std.Io.Writer = .fixed(self.entry[2..]);

        var entry = while (self.r.seek != self.r.end) {
            writer.end = 0;

            _ = self.r.streamDelimiterEnding(&writer, '\n') catch |e| {
                log.warn("cannot read from \"{s}\": {}", .{ self.filepath, e });
                return null;
            };

            var entry = writer.buffered();
            self.line += 1;

            // trim any whitespace (including CR) around it
            const trim = std.mem.trim(u8, entry, whitespace ++ "\r");
            // trim returns a subslice; copy to front so entry starts at index 0.
            // e.g. "  foo = bar" -> trim points at "foo = bar", we need it at entry[0..].
            if (trim.len != entry.len) {
                std.mem.copyForwards(u8, entry, trim);
                entry = entry[0..trim.len];
            }

            if (entry.len == 0 or entry[0] == '#') continue;
            break entry;
        } else return null;

        if (mem.indexOf(u8, entry, "=")) |idx| {
            const key = std.mem.trim(u8, entry[0..idx], whitespace);
            const value = value: {
                var value = std.mem.trim(u8, entry[idx + 1 ..], whitespace);

                if (value.len >= 2 and
                    value[0] == '"' and
                    value[value.len - 1] == '"')
                {
                    value = value[1 .. value.len - 1];
                }

                break :value value;
            };

            const len = key.len + value.len + 1;
            if (entry.len != len) {
                std.mem.copyForwards(u8, entry, key);
                entry[key.len] = '=';
                std.mem.copyForwards(u8, entry[key.len + 1], value);
                entry = entry[0..len];
            }
        }

        return self.entry[0 .. entry.len + 2];
    }
};
