const std = @import("std");
const mem = std.mem;

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
