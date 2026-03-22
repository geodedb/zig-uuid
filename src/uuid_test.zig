// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// UUID tests — split from uuid.zig to keep that file under 800 lines (QC-65).
// All test logic is here; uuid.zig imports this file via `test { _ = @import("uuid_test.zig"); }`.

const std = @import("std");
const json = @import("json");
const UUID = @import("uuid.zig").UUID;
const Version = @import("uuid.zig").Version;
const Variant = @import("uuid.zig").Variant;
const Error = @import("uuid.zig").Error;

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

test "setVariant round-trip for all four variants (QC-41)" {
    // .rfc9562 — already tested above; include for completeness.
    {
        var u = UUID{ .bytes = [_]u8{0xFF} ** 16 };
        u.setVariant(.rfc9562);
        try std.testing.expectEqual(Variant.rfc9562, u.variant());
        // byte[8] bit 7 = 1, bit 6 = 0  → (b & 0x80==0x80) and (b & 0xC0==0x80)
        try std.testing.expect(u.bytes[8] & 0xC0 == 0x80);
    }
    // .ncs — MSB of byte[8] must be 0.
    {
        var u = UUID{ .bytes = [_]u8{0xFF} ** 16 };
        u.setVariant(.ncs);
        try std.testing.expectEqual(Variant.ncs, u.variant());
        try std.testing.expect(u.bytes[8] & 0x80 == 0x00);
    }
    // .microsoft — byte[8] bits [7:5] = 0b110.
    {
        var u = UUID{ .bytes = [_]u8{0} ** 16 };
        u.setVariant(.microsoft);
        try std.testing.expectEqual(Variant.microsoft, u.variant());
        try std.testing.expect(u.bytes[8] & 0xE0 == 0xC0);
    }
    // .future — byte[8] bits [7:5] = 0b111.
    {
        var u = UUID{ .bytes = [_]u8{0} ** 16 };
        u.setVariant(.future);
        try std.testing.expectEqual(Variant.future, u.variant());
        try std.testing.expect(u.bytes[8] & 0xE0 == 0xE0);
    }
}

test "UUID eql and order" {
    const a = UUID.nil;
    const b = UUID.max;
    try std.testing.expect(a.eql(UUID.nil));
    try std.testing.expect(!a.eql(b));
    try std.testing.expectEqual(std.math.Order.lt, a.order(b));
}

// --- SEC-R9-01: timingSafeEql ---

test "UUID.timingSafeEql: equal UUIDs return true (SEC-R9-01)" {
    // Identical value — must return true.
    try std.testing.expect(UUID.nil.timingSafeEql(UUID.nil));
    try std.testing.expect(UUID.max.timingSafeEql(UUID.max));

    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expect(u.timingSafeEql(u));
}

test "UUID.timingSafeEql: unequal UUIDs return false (SEC-R9-01)" {
    // nil vs max differ in all 16 bytes.
    try std.testing.expect(!UUID.nil.timingSafeEql(UUID.max));

    // Differ only in the last byte.
    var a = UUID.nil;
    var b = UUID.nil;
    b.bytes[15] = 0x01;
    try std.testing.expect(!a.timingSafeEql(b));

    // Differ only in the first byte.
    a = UUID.nil;
    b = UUID.nil;
    b.bytes[0] = 0xFF;
    try std.testing.expect(!a.timingSafeEql(b));
}

test "UUID.timingSafeEql: agrees with eql on equal inputs (SEC-R9-01)" {
    // timingSafeEql and eql must produce the same boolean for all equal pairs.
    const cases = [_]UUID{ UUID.nil, UUID.max };
    for (cases) |u| {
        try std.testing.expect(u.eql(u) == u.timingSafeEql(u));
    }
    const u = try UUID.fromString("018fca1a-b503-7b7a-b9c0-c5c8fdb4e0e8");
    try std.testing.expect(u.eql(u) == u.timingSafeEql(u));
}

test "UUID.timingSafeEql: agrees with eql on unequal inputs (SEC-R9-01)" {
    // timingSafeEql and eql must produce the same boolean for all unequal pairs.
    const a = UUID.nil;
    const b = UUID.max;
    try std.testing.expect(a.eql(b) == a.timingSafeEql(b));

    // Single-byte difference at every position.
    inline for (0..16) |i| {
        var x = UUID.nil;
        var y = UUID.nil;
        y.bytes[i] = 0x42;
        try std.testing.expect(x.eql(y) == x.timingSafeEql(y));
        try std.testing.expect(!x.timingSafeEql(y));
    }
}

test "UUID.timingSafeEql: symmetric (SEC-R9-01)" {
    const a = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const b = try UUID.fromString("018fca1a-b503-7b7a-b9c0-c5c8fdb4e0e8");
    // a.timingSafeEql(b) == b.timingSafeEql(a)
    try std.testing.expect(a.timingSafeEql(b) == b.timingSafeEql(a));
    try std.testing.expect(a.timingSafeEql(a) == a.timingSafeEql(a));
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

test "fromString: URN off-by-one regression — 'urn:' returns InvalidURNPrefix not InvalidLength (QC-47)" {
    // Before fix, rest.len > 4 was false for len==4, so "urn:" fell through to
    // InvalidLength.  With rest.len >= 4 it correctly returns InvalidURNPrefix.
    try std.testing.expectError(Error.InvalidURNPrefix, UUID.fromString("urn:"));
    // Slightly longer bad URN prefixes must also return InvalidURNPrefix.
    try std.testing.expectError(Error.InvalidURNPrefix, UUID.fromString("urn:foo"));
    try std.testing.expectError(Error.InvalidURNPrefix, UUID.fromString("urn:uui:6ba7b8109dad11d180b400c04fd430c8"));
}

test "fromString: URN prefix case-insensitive (SEC-R8-03)" {
    // RFC 2141 §5: the URN scheme and NID (uuid) are both case-insensitive.
    const expected = try UUID.fromString("urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    // Uppercase
    const r1 = try UUID.fromString("URN:UUID:6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(expected, r1);
    // Mixed case
    const r2 = try UUID.fromString("Urn:Uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(expected, r2);
    // Invalid uppercase URN prefix still returns InvalidURNPrefix
    try std.testing.expectError(Error.InvalidURNPrefix, UUID.fromString("URN:BAD:6ba7b8109dad11d180b400c04fd430c8"));
}

test "parseCanonical: InvalidDashes for wrong dash position (QC-40)" {
    // Position 8 should be '-' but 'X' is substituted — must return InvalidDashes.
    try std.testing.expectError(Error.InvalidDashes, UUID.fromString("6ba7b810X9dad-11d1-80b4-00c04fd430c8"));
    // Position 13 wrong.
    try std.testing.expectError(Error.InvalidDashes, UUID.fromString("6ba7b810-9dadX11d1-80b4-00c04fd430c8"));
    // Position 18 wrong.
    try std.testing.expectError(Error.InvalidDashes, UUID.fromString("6ba7b810-9dad-11d1X80b4-00c04fd430c8"));
    // Position 23 wrong.
    try std.testing.expectError(Error.InvalidDashes, UUID.fromString("6ba7b810-9dad-11d1-80b4X00c04fd430c8"));
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

test "toHexAlloc produces lowercase hex without dashes (QC-42)" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const s = try u.toHexAlloc(alloc);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("6ba7b8109dad11d180b400c04fd430c8", s);
}

test "toHexUpperAlloc produces uppercase hex without dashes (QC-42)" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const s = try u.toHexUpperAlloc(alloc);
    defer alloc.free(s);
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

test "UUID.isMax returns true for max UUID (QC-56)" {
    try std.testing.expect(UUID.max.isMax());
    try std.testing.expect(!UUID.nil.isMax());
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expect(!u.isMax());
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
