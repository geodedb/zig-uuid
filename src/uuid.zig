// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

pub const Error = error{
    InvalidFormat,
    InvalidLength,
    InvalidBraces,
    InvalidURNPrefix,
    InvalidDashes,
    IncorrectByteLength,
    NoHWAddressFound,
    InvalidVersion,
    V8FieldLength,
    RandomError,
};

pub const Version = enum(u8) {
    v1 = 1,
    v3 = 3,
    v4 = 4,
    v5 = 5,
    v6 = 6,
    v7 = 7,
    v8 = 8,
};

pub const Variant = enum(u8) {
    ncs,
    rfc9562,
    microsoft,
    future,
};

test "Version enum values" {
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Version.v1));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(Version.v7));
}

test "Variant enum" {
    const v = Variant.rfc9562;
    try std.testing.expect(v == .rfc9562);
}

pub const UUID = struct {
    bytes: [16]u8,

    pub const nil: UUID = .{ .bytes = [_]u8{0x00} ** 16 };
    pub const max: UUID = .{ .bytes = [_]u8{0xFF} ** 16 };

    pub fn version(self: UUID) Version {
        return @enumFromInt(self.bytes[6] >> 4);
    }

    pub fn variant(self: UUID) Variant {
        const b = self.bytes[8];
        if (b & 0x80 == 0x00) return .ncs;
        if (b & 0xC0 == 0x80) return .rfc9562;
        if (b & 0xE0 == 0xC0) return .microsoft;
        return .future;
    }

    pub fn isNil(self: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &nil.bytes);
    }

    pub fn setVersion(self: *UUID, v: Version) void {
        self.bytes[6] = (self.bytes[6] & 0x0F) | (@as(u8, @intFromEnum(v)) << 4);
    }

    pub fn setVariant(self: *UUID, v: Variant) void {
        switch (v) {
            .rfc9562 => self.bytes[8] = (self.bytes[8] & 0x3F) | 0x80,
            .ncs => self.bytes[8] = self.bytes[8] & 0x7F,
            .microsoft => self.bytes[8] = (self.bytes[8] & 0x1F) | 0xC0,
            .future => self.bytes[8] = (self.bytes[8] & 0x0F) | 0xE0,
        }
    }

    pub fn eql(self: UUID, other: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn order(self: UUID, other: UUID) std.math.Order {
        return std.mem.order(u8, &self.bytes, &other.bytes);
    }

    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: UUID) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(&key.bytes);
            return hasher.final();
        }
        pub fn eql(_: HashContext, a: UUID, b: UUID) bool {
            return a.eql(b);
        }
    };
};

test "UUID nil sentinel" {
    const u = UUID.nil;
    try std.testing.expect(u.isNil());
    try std.testing.expect(!UUID.max.isNil());
}

test "UUID setVersion and version()" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVersion(.v4);
    try std.testing.expectEqual(Version.v4, u.version());
    u.setVersion(.v7);
    try std.testing.expectEqual(Version.v7, u.version());
}

test "UUID setVariant and variant()" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVariant(.rfc9562);
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "UUID eql and order" {
    const a = UUID.nil;
    const b = UUID.max;
    try std.testing.expect(a.eql(UUID.nil));
    try std.testing.expect(!a.eql(b));
    try std.testing.expectEqual(std.math.Order.lt, a.order(b));
}

test "UUID HashContext" {
    const ctx = UUID.HashContext{};
    const h1 = ctx.hash(UUID.nil);
    const h2 = ctx.hash(UUID.nil);
    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(ctx.hash(UUID.max) != ctx.hash(UUID.nil));
}
