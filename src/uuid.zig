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

    pub fn fromBytes(b: []const u8) Error!UUID {
        if (b.len != 16) return Error.IncorrectByteLength;
        var u: UUID = undefined;
        @memcpy(&u.bytes, b);
        return u;
    }

    pub fn fromString(s: []const u8) Error!UUID {
        // Detect and strip URN prefix
        var rest = s;
        if (std.mem.startsWith(u8, rest, "urn:uuid:")) {
            rest = rest[9..];
        } else if (rest.len > 4 and std.mem.startsWith(u8, rest, "urn:")) {
            return Error.InvalidURNPrefix;
        }

        // Detect and strip braces
        if (rest.len > 0 and rest[0] == '{') {
            if (rest[rest.len - 1] != '}') return Error.InvalidBraces;
            rest = rest[1 .. rest.len - 1];
        }

        return switch (rest.len) {
            36 => parseCanonical(rest), // with dashes
            32 => parseHash(rest), // no dashes
            else => Error.InvalidLength,
        };
    }

    pub fn toString(self: UUID, buf: *[36]u8) []u8 {
        const hex = "0123456789abcdef";
        const groups = [_]struct { start: usize, len: usize }{
            .{ .start = 0, .len = 4 },
            .{ .start = 4, .len = 2 },
            .{ .start = 6, .len = 2 },
            .{ .start = 8, .len = 2 },
            .{ .start = 10, .len = 6 },
        };
        var pos: usize = 0;
        for (groups, 0..) |g, gi| {
            if (gi > 0) {
                buf[pos] = '-';
                pos += 1;
            }
            for (self.bytes[g.start .. g.start + g.len]) |byte| {
                buf[pos] = hex[byte >> 4];
                buf[pos + 1] = hex[byte & 0x0F];
                pos += 2;
            }
        }
        return buf[0..36];
    }

    pub fn toStringAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        var buf: [36]u8 = undefined;
        return alloc.dupe(u8, self.toString(&buf));
    }

    pub fn format(self: UUID, w: anytype) !void {
        var buf: [36]u8 = undefined;
        try w.writeAll(self.toString(&buf));
    }
};

fn parseCanonical(s: []const u8) Error!UUID {
    // Validate dash positions: 8-4-4-4-12
    if (s[8] != '-' or s[13] != '-' or s[18] != '-' or s[23] != '-')
        return Error.InvalidDashes;
    var u: UUID = undefined;
    var out: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '-') continue;
        const hi = std.fmt.charToDigit(s[i], 16) catch return Error.InvalidFormat;
        i += 1;
        const lo = std.fmt.charToDigit(s[i], 16) catch return Error.InvalidFormat;
        u.bytes[out] = (hi << 4) | lo;
        out += 1;
    }
    if (out != 16) return Error.InvalidFormat;
    return u;
}

fn parseHash(s: []const u8) Error!UUID {
    var u: UUID = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const hi = std.fmt.charToDigit(s[i * 2], 16) catch return Error.InvalidFormat;
        const lo = std.fmt.charToDigit(s[i * 2 + 1], 16) catch return Error.InvalidFormat;
        u.bytes[i] = (hi << 4) | lo;
    }
    return u;
}

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

test "fromString: canonical format" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xc8), u.bytes[15]);
}

test "fromString: braced canonical" {
    const u = try UUID.fromString("{6ba7b810-9dad-11d1-80b4-00c04fd430c8}");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: hash (no dashes)" {
    const u = try UUID.fromString("6ba7b8109dad11d180b400c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: braced hash" {
    const u = try UUID.fromString("{6ba7b8109dad11d180b400c04fd430c8}");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: URN canonical" {
    const u = try UUID.fromString("urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: URN hash" {
    const u = try UUID.fromString("urn:uuid:6ba7b8109dad11d180b400c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: nil UUID" {
    const u = try UUID.fromString("00000000-0000-0000-0000-000000000000");
    try std.testing.expect(u.isNil());
}

test "fromString: error on bad format" {
    // 35-char string (malformed mix): hits InvalidLength
    try std.testing.expectError(Error.InvalidLength, UUID.fromString("6ba7b8109dad-11d1-80b4-00c04fd430c8"));
    // Short string: InvalidLength
    try std.testing.expectError(Error.InvalidLength, UUID.fromString("6ba7b810-9dad-11d1-80b4"));
    // Invalid URN namespace: InvalidURNPrefix
    try std.testing.expectError(Error.InvalidURNPrefix, UUID.fromString("urn:bad:6ba7b8109dad11d180b400c04fd430c8"));
}

test "fromBytes: 16-byte slice" {
    const b = [_]u8{ 0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8 };
    const u = try UUID.fromBytes(&b);
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
    try std.testing.expectError(Error.IncorrectByteLength, UUID.fromBytes(b[0..8]));
}

test "toString: canonical format" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", s);
}

test "toString round-trip" {
    const input = "6ba7b810-9dad-11d1-80b4-00c04fd430c8";
    const u = try UUID.fromString(input);
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(input, u.toString(&buf));
}

test "toStringAlloc" {
    const alloc = std.testing.allocator;
    const u = UUID.nil;
    const s = try u.toStringAlloc(alloc);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", s);
}

test "format via std.fmt" {
    const u = UUID.nil;
    const s = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{u});
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", s);
}
