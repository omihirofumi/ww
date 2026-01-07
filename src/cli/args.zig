const std = @import("std");
const mem = std.mem;

pub fn parseOptions(
    comptime T: type,
    alloc: std.mem.Allocator,
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
                value = args.next() orelse return error.InvalidArgs;
            }

            try parseIntoField(T, alloc, dst, key, value);
            continue;
        }

        if (mem.startsWith(u8, arg, "-") and arg.len == 2) {
            const short = arg[1..2];
            const value = args.next() orelse return error.InvalidArgs;

            const long = shortToLong(short) orelse return error.InvalidArgs;
            try parseIntoField(T, alloc, dst, long, value);
            continue;
        }

        return arg;
    }

    return null;
}

fn shortToLong(short: []const u8) ?[]const u8 {
    if (mem.eql(u8, short, "r")) return "revset";
    return null;
}

fn parseIntoField(
    comptime T: type,
    alloc: std.mem.Allocator,
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
                []const u8 => value: {
                    const slice = value orelse return error.ValueRequired;
                    const buf = try alloc.alloc(u8, slice.len);
                    mem.copyForwards(u8, buf, slice);
                    break :value buf;
                },
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
