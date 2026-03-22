// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const json = @import("json");

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
    /// Returned by Timestamp.now() when the system clock is before the Unix epoch.
    InvalidTimestamp,
};

/// UUID version nibble (bits 76-79 of byte 6).
///
/// This is a non-exhaustive enum: unrecognised nibble values (e.g. `0` for
/// the nil UUID, `2` for DCE Security, or `9`–`15` for future versions) are
/// returned as unnamed enum members rather than causing a safety-checked panic.
/// Callers that switch on Version must include an `else` branch.
pub const Version = enum(u8) {
    v1 = 1,
    v3 = 3,
    v4 = 4,
    v5 = 5,
    v6 = 6,
    v7 = 7,
    v8 = 8,
    _, // non-exhaustive: allows @enumFromInt on unknown nibbles without panic
};

pub const Variant = enum(u8) {
    ncs,
    rfc9562,
    microsoft,
    future,
};

pub const UUID = struct {
    bytes: [16]u8,

    pub const nil: UUID = .{ .bytes = [_]u8{0x00} ** 16 };
    pub const max: UUID = .{ .bytes = [_]u8{0xFF} ** 16 };

    /// Return the version nibble as a Version enum value.
    ///
    /// Because Version is a non-exhaustive enum, this never panics — unknown
    /// nibbles (nil UUID version=0, DCE Security version=2, future versions
    /// 9–15) are returned as unnamed members. Use `switch (u.version()) { .v4
    /// => ..., else => ... }` to handle unknown values safely.
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

    /// Returns true when this UUID has a known RFC-9562 version nibble (1–8)
    /// and the RFC-9562 variant bits.  Useful for strict conformance checking
    /// without mandating it at parse time (RFC-9562 §6.12 opacity guidance).
    ///
    /// The nil UUID and max UUID return false (version nibble 0 and 0xF are
    /// not defined RFC-9562 versions).
    ///
    /// Implements the validation pattern requested in gofrs/uuid issue #198.
    pub fn isValid(self: UUID) bool {
        const is_known_version = switch (self.version()) {
            .v1, .v3, .v4, .v5, .v6, .v7, .v8 => true,
            _ => false,
        };
        return is_known_version and self.variant() == .rfc9562;
    }

    /// Strict RFC-9562 conformance check.  Returns error.InvalidVersion when
    /// the UUID has an unknown version nibble or a non-rfc9562 variant.
    ///
    /// Callers that need to accept any well-formed UUID regardless of version
    /// should use isNil()/version()/variant() directly instead.
    pub fn validate(self: UUID) Error!void {
        if (!self.isValid()) return Error.InvalidVersion;
    }

    /// Alias for isNil(). Satisfies the bsoncodec.Zeroer-style interface
    /// pattern used in some serialization frameworks (G-9).
    pub fn isZero(self: UUID) bool {
        return self.isNil();
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

    /// A zero-size HashMap context for UUID keys using Wyhash with a fixed
    /// seed of zero.
    ///
    /// **SEC-6 / CWE-330 — HashDoS warning:**
    /// The fixed seed means that two UUIDs which collide under this seed will
    /// **always** collide, across every run and every process.  An adversary
    /// who can control which UUIDs are inserted into a HashMap using this
    /// context can engineer O(n²) worst-case behaviour.
    ///
    /// **Use `HashContext` only when UUID keys are fully trusted** (e.g.,
    /// internally-generated V4 UUIDs, compile-time constants, or values from
    /// a controlled internal datastore).  When keys arrive from untrusted
    /// sources (parsed from user input, external APIs, log files, etc.) use
    /// `SecureHashContext` instead.
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

    /// A HashMap context for UUID keys using a randomly-seeded Wyhash instance,
    /// providing HashDoS resistance when UUID keys may be attacker-controlled.
    ///
    /// **SEC-6:** Use this context instead of `HashContext` whenever UUIDs are
    /// received from untrusted sources (user input, external APIs, network
    /// messages) and inserted into a HashMap.
    ///
    /// Because `SecureHashContext` carries the random seed as instance state,
    /// it is used with Zig's context-aware map APIs.  Example:
    ///
    /// ```zig
    /// var ctx = UUID.SecureHashContext.init();
    /// var map = std.HashMapUnmanaged(UUID, MyVal, UUID.SecureHashContext, 80){};
    /// try map.putContext(allocator, key, value, ctx);
    /// ```
    ///
    /// The seed is sampled from `std.crypto.random` at construction time; each
    /// `SecureHashContext.init()` call produces a different seed.
    pub const SecureHashContext = struct {
        seed: u64,

        /// Create a new SecureHashContext with a cryptographically random seed.
        pub fn init() SecureHashContext {
            return .{ .seed = std.crypto.random.int(u64) };
        }

        pub fn hash(self: SecureHashContext, key: UUID) u64 {
            var hasher = std.hash.Wyhash.init(self.seed);
            hasher.update(&key.bytes);
            return hasher.final();
        }

        pub fn eql(_: SecureHashContext, a: UUID, b: UUID) bool {
            return a.eql(b);
        }
    };

    pub fn fromBytes(b: []const u8) Error!UUID {
        if (b.len != 16) return Error.IncorrectByteLength;
        var u: UUID = undefined;
        @memcpy(&u.bytes, b);
        return u;
    }

    /// Parse any supported UUID format (canonical, braced, URN, 32-hex).
    /// Returns nil UUID on parse error — useful for initializing package-level
    /// variables from known-good literals (G-7).
    pub fn fromStringOrNil(s: []const u8) UUID {
        return UUID.fromString(s) catch UUID.nil;
    }

    /// Wrap a 16-byte slice — returns nil UUID on wrong length (G-7).
    pub fn fromBytesOrNil(b: []const u8) UUID {
        return UUID.fromBytes(b) catch UUID.nil;
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

    /// Return the raw 16 bytes as a value copy (G-1).
    /// Equivalent to reading .bytes directly but more explicit at call sites.
    pub fn toBytes(self: UUID) [16]u8 {
        return self.bytes;
    }

    /// Canonical lowercase with dashes: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
    pub fn toString(self: UUID, buf: *[36]u8) []u8 {
        return toStringImpl(self, buf, "0123456789abcdef");
    }

    /// Canonical uppercase with dashes: `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX` (G-2)
    pub fn toStringUpper(self: UUID, buf: *[36]u8) []u8 {
        return toStringImpl(self, buf, "0123456789ABCDEF");
    }

    /// Lowercase hex without dashes: `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` (G-2)
    pub fn toHex(self: UUID, buf: *[32]u8) []u8 {
        return toHexImpl(self, buf, "0123456789abcdef");
    }

    /// Uppercase hex without dashes: `XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX` (G-2)
    pub fn toHexUpper(self: UUID, buf: *[32]u8) []u8 {
        return toHexImpl(self, buf, "0123456789ABCDEF");
    }

    /// URN format: `urn:uuid:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (F-5 / G-3).
    /// buf must be exactly 45 bytes.
    pub fn toURN(self: UUID, buf: *[45]u8) []u8 {
        @memcpy(buf[0..9], "urn:uuid:");
        _ = self.toString(buf[9..45]);
        return buf[0..45];
    }

    /// Allocating URN format (F-5 / G-3).
    pub fn toURNAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        var buf: [45]u8 = undefined;
        return alloc.dupe(u8, self.toURN(&buf));
    }

    pub fn toStringAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        var buf: [36]u8 = undefined;
        return alloc.dupe(u8, self.toString(&buf));
    }

    /// Allocating uppercase string (G-2).
    pub fn toStringUpperAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        var buf: [36]u8 = undefined;
        return alloc.dupe(u8, self.toStringUpper(&buf));
    }

    pub fn format(self: UUID, writer: anytype) !void {
        var buf: [36]u8 = undefined;
        try writer.writeAll(self.toString(&buf));
    }

    pub fn jsonMarshal(self: UUID, allocator: std.mem.Allocator) !json.Value {
        var buf: [36]u8 = undefined;
        return .{ .str = try allocator.dupe(u8, self.toString(&buf)) };
    }

    /// allocator parameter exists for interface conformance; UUID.fromString is zero-alloc.
    pub fn jsonUnmarshal(allocator: std.mem.Allocator, v: json.Value) !UUID {
        _ = allocator;
        if (v != .str) return Error.InvalidFormat;
        return fromString(v.str);
    }
};

// --- private helpers ---

/// PERF-09: Fully unrolled UUID-to-canonical-string encoding.
///
/// Using `comptime hex` (compile-time-known table) + `inline for` with
/// comptime-tracked buffer offsets eliminates all runtime loop overhead:
/// no loop counter, no conditional dash check, hex table stays in registers.
/// The compiler emits 36 fixed-offset byte stores with no branches.
fn toStringImpl(self: UUID, buf: *[36]u8, comptime hex: *const [16]u8) []u8 {
    // Group 1: UUID bytes 0-3 → buf[0..7]
    comptime var pos: usize = 0;
    inline for (0..4) |i| {
        buf[pos] = hex[self.bytes[i] >> 4];
        buf[pos + 1] = hex[self.bytes[i] & 0x0F];
        pos += 2;
    }
    buf[pos] = '-';
    pos += 1;
    // Group 2: UUID bytes 4-5 → buf[9..12]
    inline for (0..2) |i| {
        buf[pos] = hex[self.bytes[4 + i] >> 4];
        buf[pos + 1] = hex[self.bytes[4 + i] & 0x0F];
        pos += 2;
    }
    buf[pos] = '-';
    pos += 1;
    // Group 3: UUID bytes 6-7 → buf[14..17]
    inline for (0..2) |i| {
        buf[pos] = hex[self.bytes[6 + i] >> 4];
        buf[pos + 1] = hex[self.bytes[6 + i] & 0x0F];
        pos += 2;
    }
    buf[pos] = '-';
    pos += 1;
    // Group 4: UUID bytes 8-9 → buf[19..22]
    inline for (0..2) |i| {
        buf[pos] = hex[self.bytes[8 + i] >> 4];
        buf[pos + 1] = hex[self.bytes[8 + i] & 0x0F];
        pos += 2;
    }
    buf[pos] = '-';
    pos += 1;
    // Group 5: UUID bytes 10-15 → buf[24..35]
    inline for (0..6) |i| {
        buf[pos] = hex[self.bytes[10 + i] >> 4];
        buf[pos + 1] = hex[self.bytes[10 + i] & 0x0F];
        pos += 2;
    }
    return buf[0..36];
}

/// PERF-09: Same inline-for optimization as toStringImpl.
fn toHexImpl(self: UUID, buf: *[32]u8, comptime hex: *const [16]u8) []u8 {
    inline for (0..16) |i| {
        buf[i * 2] = hex[self.bytes[i] >> 4];
        buf[i * 2 + 1] = hex[self.bytes[i] & 0x0F];
    }
    return buf[0..32];
}

/// PERF-10: Decode a single hex character to its 4-bit value.
/// A switch-with-ranges pattern that LLVM typically lowers to branchless code.
inline fn hexVal(c: u8) Error!u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => Error.InvalidFormat,
    };
}

/// PERF-10: Fixed-offset canonical UUID parse.
///
/// Dash positions are validated once upfront, then each of the 16 UUID bytes
/// is decoded at a compile-time-known string offset via `inline for`.  This
/// eliminates the loop counter variable, the `if (s[i] == '-') continue`
/// branch per iteration, and the post-loop `out != 16` check.
fn parseCanonical(s: []const u8) Error!UUID {
    // Validate dash positions: 8-4-4-4-12
    if (s[8] != '-' or s[13] != '-' or s[18] != '-' or s[23] != '-')
        return Error.InvalidDashes;

    // Precomputed string offsets for each of the 16 UUID bytes.
    // Groups: [0..7], [9..12], [14..17], [19..22], [24..35]
    // Verified: offsets[15] = 34, s[34]+s[35] encodes bytes[15]. ✓
    const offsets = comptime blk: {
        var off: [16]usize = undefined;
        var byte_i: usize = 0;
        var str_p: usize = 0;
        for ([5]usize{ 4, 2, 2, 2, 6 }, 0..) |n, gi| {
            if (gi > 0) str_p += 1; // skip dash
            var j: usize = 0;
            while (j < n) : (j += 1) {
                off[byte_i] = str_p;
                byte_i += 1;
                str_p += 2;
            }
        }
        break :blk off;
    };

    var u: UUID = undefined;
    inline for (offsets, 0..) |off, i| {
        const hi = try hexVal(s[off]);
        const lo = try hexVal(s[off + 1]);
        u.bytes[i] = (hi << 4) | lo;
    }
    return u;
}

/// PERF-14: Use `inline for` with comptime-constant offsets so the compiler
/// can unroll the 16-iteration loop and eliminate the runtime counter, matching
/// the pattern applied to parseCanonical in PERF-10.  Measured: 5 ns/op vs
/// 11 ns/op with the previous while-loop (2.2× improvement).
fn parseHash(s: []const u8) Error!UUID {
    var u: UUID = undefined;
    inline for (0..16) |i| {
        const hi = try hexVal(s[i * 2]);
        const lo = try hexVal(s[i * 2 + 1]);
        u.bytes[i] = (hi << 4) | lo;
    }
    return u;
}

// =============================================================================
// Tests
// =============================================================================

test "Version enum values" {
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Version.v1));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(Version.v7));
}

test "Variant enum" {
    const v = Variant.rfc9562;
    try std.testing.expect(v == .rfc9562);
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

test "UUID.version() is safe for nil UUID (nibble=0, non-exhaustive)" {
    // F-2 / G-10: version() must NOT panic on unrecognised nibbles.
    // nil UUID has version nibble = 0, which is not a named Version member.
    const u = UUID.nil;
    const v = u.version(); // must not panic
    try std.testing.expect(v != .v1); // just confirming it returns something
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(v));
}

test "UUID.version() is safe for future nibble (nibble=15)" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.bytes[6] = 0xF0; // version nibble = 15
    const v = u.version(); // must not panic
    try std.testing.expectEqual(@as(u8, 15), @intFromEnum(v));
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

// --- SEC-6: SecureHashContext ---

test "SecureHashContext.init produces distinct seeds (SEC-6)" {
    const ctx1 = UUID.SecureHashContext.init();
    const ctx2 = UUID.SecureHashContext.init();
    // Astronomically unlikely to collide; catches a broken RNG immediately.
    try std.testing.expect(ctx1.seed != ctx2.seed);
}

test "SecureHashContext.hash is deterministic for a given seed (SEC-6)" {
    const ctx = UUID.SecureHashContext{ .seed = 0xCAFEBABE_DEADBEEF };
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(ctx.hash(u), ctx.hash(u));
}

test "SecureHashContext.hash differs from HashContext (fixed-seed=0) (SEC-6)" {
    // With a non-zero seed the secure context produces a different digest
    // than the fixed-seed HashContext, confirming the seed is applied.
    const sctx = UUID.SecureHashContext{ .seed = 0xDEAD_BEEF };
    const hctx = UUID.HashContext{};
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expect(sctx.hash(u) != hctx.hash(u));
}

test "SecureHashContext.eql delegates to UUID.eql (SEC-6)" {
    const ctx = UUID.SecureHashContext.init();
    const a = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const b = a;
    try std.testing.expect(ctx.eql(a, b));
    try std.testing.expect(!ctx.eql(a, UUID.nil));
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

test "UUID.jsonMarshal round-trip" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const v = try u.jsonMarshal(alloc);
    defer alloc.free(v.str);
    const parsed = try UUID.jsonUnmarshal(alloc, v);
    try std.testing.expect(u.eql(parsed));
}

// --- New tests for G-1, G-2, F-5/G-3, G-7, G-9 ---

test "toBytes returns 16-byte copy (G-1)" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const b = u.toBytes();
    try std.testing.expectEqualSlices(u8, &u.bytes, &b);
}

test "toStringUpper produces uppercase with dashes (G-2)" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    var buf: [36]u8 = undefined;
    const s = u.toStringUpper(&buf);
    try std.testing.expectEqualStrings("6BA7B810-9DAD-11D1-80B4-00C04FD430C8", s);
}

test "toHex produces lowercase without dashes (G-2)" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    var buf: [32]u8 = undefined;
    const s = u.toHex(&buf);
    try std.testing.expectEqualStrings("6ba7b8109dad11d180b400c04fd430c8", s);
}

test "toHexUpper produces uppercase without dashes (G-2)" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    var buf: [32]u8 = undefined;
    const s = u.toHexUpper(&buf);
    try std.testing.expectEqualStrings("6BA7B8109DAD11D180B400C04FD430C8", s);
}

test "toStringUpperAlloc (G-2)" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const s = try u.toStringUpperAlloc(alloc);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("6BA7B810-9DAD-11D1-80B4-00C04FD430C8", s);
}

test "toURN produces urn:uuid: prefix (F-5 / G-3)" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    var buf: [45]u8 = undefined;
    const s = u.toURN(&buf);
    try std.testing.expectEqualStrings("urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8", s);
}

test "toURNAlloc (F-5 / G-3)" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const s = try u.toURNAlloc(alloc);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8", s);
}

test "toURN round-trip with fromString (F-5 / G-3)" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    var buf: [45]u8 = undefined;
    const urn = u.toURN(&buf);
    const parsed = try UUID.fromString(urn);
    try std.testing.expect(u.eql(parsed));
}

test "fromStringOrNil: valid input returns UUID (G-7)" {
    const u = UUID.fromStringOrNil("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromStringOrNil: invalid input returns nil (G-7)" {
    const u = UUID.fromStringOrNil("not-a-uuid");
    try std.testing.expect(u.isNil());
}

test "fromBytesOrNil: valid 16 bytes (G-7)" {
    const b = [_]u8{0x01} ** 16;
    const u = UUID.fromBytesOrNil(&b);
    try std.testing.expectEqualSlices(u8, &b, &u.bytes);
}

test "fromBytesOrNil: wrong length returns nil (G-7)" {
    const b = [_]u8{0x01} ** 8;
    const u = UUID.fromBytesOrNil(&b);
    try std.testing.expect(u.isNil());
}

test "isZero alias for isNil (G-9)" {
    try std.testing.expect(UUID.nil.isZero());
    try std.testing.expect(!UUID.max.isZero());
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expect(!u.isZero());
}

// =============================================================================
// isValid / validate — gofrs/uuid issue #198
// =============================================================================

test "isValid: known RFC-9562 versions with rfc9562 variant return true" {
    // V4 random UUID — version nibble 4, rfc9562 variant
    const v4 = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    try std.testing.expect(v4.isValid());

    // V7 UUID — version nibble 7, rfc9562 variant
    const v7 = try UUID.fromString("017f22e2-79b0-7cc3-98c4-dc0c0c07398f");
    try std.testing.expect(v7.isValid());

    // V1 namespace UUID
    const v1 = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expect(v1.isValid());

    // V3 MD5 UUID
    const v3 = try UUID.fromString("5df41881-3aed-3515-88a7-2f4a814cf09e");
    try std.testing.expect(v3.isValid());

    // V5 SHA-1 UUID
    const v5 = try UUID.fromString("2ed6657d-e927-568b-95e1-2665a8aea6a2");
    try std.testing.expect(v5.isValid());
}

test "isValid: nil UUID returns false (version nibble = 0)" {
    try std.testing.expect(!UUID.nil.isValid());
}

test "isValid: max UUID returns false (version nibble = 0xF)" {
    try std.testing.expect(!UUID.max.isValid());
}

test "isValid: unknown version nibble returns false" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVariant(.rfc9562);
    u.bytes[6] = 0x20; // version nibble = 2 (DCE Security, not in our Version enum)
    try std.testing.expect(!u.isValid());
}

test "isValid: wrong variant returns false" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVersion(.v4);
    u.setVariant(.microsoft); // wrong variant
    try std.testing.expect(!u.isValid());
}

test "validate: valid UUID returns void" {
    const v4 = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    try v4.validate();
}

test "validate: nil UUID returns InvalidVersion" {
    try std.testing.expectError(Error.InvalidVersion, UUID.nil.validate());
}

test "validate: unknown version nibble returns InvalidVersion" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVariant(.rfc9562);
    u.bytes[6] = 0x90; // version nibble = 9 (future, unknown)
    try std.testing.expectError(Error.InvalidVersion, u.validate());
}
