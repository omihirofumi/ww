// https://github.com/omihirofumi/zig-protobuf/blob/main/src/decode.zig
const std = @import("std");

const ProtoError = error{
    UnexpectedEof,
    VarintTooLong,
    InvalidWireType,
    InvalidFieldNumber,
    LengthOverflow,
};

pub const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    len = 2,
    fixed32 = 5,
};

pub const Key = struct {
    field_number: u32,
    wire: WireType,
};

pub const Reader = struct {
    buf: []const u8,
    pos: usize = 0,

    pub fn init(buf: []const u8) Reader {
        return .{ .buf = buf, .pos = 0 };
    }

    pub fn eof(self: *Reader) bool {
        return self.pos >= self.buf.len;
    }

    fn require(self: *Reader, n: usize) !void {
        if (self.pos + n > self.buf.len) return ProtoError.UnexpectedEof;
    }

    fn readByte(self: *Reader) !u8 {
        if (self.pos >= self.buf.len) return ProtoError.UnexpectedEof;
        const b = self.buf[self.pos];
        self.pos += 1;
        return b;
    }

    pub fn readVarint(self: *Reader) !u64 {
        var shift: u6 = 0;
        var result: u64 = 0;

        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            const b = try self.readByte();
            const payload: u64 = @as(u64, b & 0x7F);
            result |= payload << shift;

            if ((b & 0x80) == 0) return result;

            shift += 7;
        }
        return ProtoError.VarintTooLong;
    }

    pub fn readKey(self: *Reader) !Key {
        const k = try self.readVarint();

        const wire_type: u3 = @intCast(k & 0x7);

        const field: u32 = @intCast(k >> 3);
        if (field == 0) return ProtoError.InvalidFieldNumber;

        const wire: WireType = switch (wire_type) {
            0 => .varint,
            1 => .fixed64,
            2 => .len,
            5 => .fixed32,
            else => return ProtoError.InvalidWireType,
        };

        return .{ .field_number = field, .wire = wire };
    }

    pub fn readFixed32(self: *Reader) !u32 {
        try self.require(4);
        var result: u32 = 0;
        for (0..4) |i| {
            const byte: u32 = self.buf[self.pos + i];
            result |= byte << @as(u5, @intCast(i * 8));
        }
        self.pos += 4;
        return result;
    }

    pub fn readFixed64(self: *Reader) !u64 {
        try self.require(8);
        var result: u64 = 0;
        for (0..8) |i| {
            const byte: u64 = self.buf[self.pos + i];
            result |= byte << @as(u6, @intCast(i * 8));
        }
        self.pos += 8;
        return result;
    }

    pub fn readLen(self: *Reader) !usize {
        const len = try self.readVarint();
        if (len > std.math.maxInt(usize)) return ProtoError.LengthOverflow;
        return @intCast(len);
    }

    pub fn readBytes(self: *Reader) ![]const u8 {
        const len = try self.readLen();
        try self.require(len);
        const s = self.buf[self.pos .. self.pos + len];
        self.pos += len;
        return s;
    }

    pub fn readSInt(self: *Reader) !i64 {
        const raw = try self.readVarint();
        return zigzagDecode(raw);
    }

    // 後方互換性
    pub fn skipField(self: *Reader, wire: WireType) !void {
        switch (wire) {
            .varint => _ = try self.readVarint(),
            .fixed64 => _ = try self.readFixed64(),
            .len => _ = try self.readBytes(),
            .fixed32 => _ = try self.readFixed32(),
        }
    }
};

fn zigzagDecode(n: u64) i64 {
    const shifted: i64 = @bitCast(n >> 1);
    const mask: i64 = -@as(i64, @intCast(n & 1));
    return shifted ^ mask;
}

// https://github.com/jj-vcs/jj/blob/v0.37.0/lib/src/protos/local_working_copy.proto
// message Checkout {
//   // The operation at which the working copy was updated.
//   bytes operation_id = 2;
//   // An identifier for this workspace. It is used for looking up the current
//   // working-copy commit in the repo view. Currently a human-readable name.
//   // TODO: Is it better to make this a UUID and a have map that to a name in
//   // config? That way users can rename a workspace.
//   string workspace_name = 3;
//   reserved 1;
// }

pub const Checkout = struct {
    workspace_name: []const u8 = &.{},

    pub fn init() Checkout {
        return .{};
    }
};

pub fn decodeCheckout(r: *Reader) !Checkout {
    var checkout: Checkout = .{};

    while (!r.eof()) {
        const key = try r.readKey();

        switch (key.field_number) {
            3 => {
                if (key.wire != .len) return ProtoError.InvalidWireType;
                const value = try r.readBytes();
                checkout.workspace_name = value;
            },
            else => {
                try r.skipField(key.wire);
            },
        }
    }

    return checkout;
}

test "varint decoding" {
    var r1 = Reader{ .buf = &.{0x01} };
    try std.testing.expectEqual(@as(u64, 1), try r1.readVarint());

    // 0x96 -> 10010110
    var r2 = Reader{ .buf = &.{ 0x96, 0x01 } };
    try std.testing.expectEqual(@as(u64, 150), try r2.readVarint());

    // 0xAC -> 10101100
    var r3 = Reader{ .buf = &.{ 0xAC, 0x02 } };
    try std.testing.expectEqual(@as(u64, 300), try r3.readVarint());
}

test "key decoding basics" {
    // field=1, wire=0(varint)
    // key = (1<<3)|0 = 8
    // 0x08 = 0000_1000
    var r1 = Reader{ .buf = &.{0x08} };
    const k1 = try r1.readKey();
    try std.testing.expectEqual(@as(u32, 1), k1.field_number);
    try std.testing.expect(k1.wire == .varint);

    // field=2, wire=2(len)
    // key = (2<<3)|2 = 18
    // 0x12 = 0001_0010
    var r2 = Reader{ .buf = &.{0x12} };
    const k2 = try r2.readKey();
    try std.testing.expectEqual(@as(u32, 2), k2.field_number);
    try std.testing.expect(k2.wire == .len);

    // field=15, wire=5(fixed32)
    // key = (15<<3)|5 = 125
    // 0x7D = 0111_1101
    var r3 = Reader{ .buf = &.{0x7D} };
    const k3 = try r3.readKey();
    try std.testing.expectEqual(@as(u32, 15), k3.field_number);
    try std.testing.expect(k3.wire == .fixed32);
}

test "key errors" {
    // field=0 は不正（protobuf仕様）
    // key = 0x00 = 0000_0000 → field=0, wire=0
    var r1 = Reader{ .buf = &.{0x00} };
    try std.testing.expectError(ProtoError.InvalidFieldNumber, r1.readKey());

    // wire=3(group start) はここでは未対応 → InvalidWireType
    // field=1, wire=3 => (1<<3)|3 = 11
    // 0x0B = 0000_1011
    var r2 = Reader{ .buf = &.{0x0B} };
    try std.testing.expectError(ProtoError.InvalidWireType, r2.readKey());
}

test "zigzag decode" {
    try std.testing.expectEqual(0, zigzagDecode(0));
    try std.testing.expectEqual(-5, zigzagDecode(9));
    try std.testing.expectEqual(5, zigzagDecode(10));
}
