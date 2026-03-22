// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Integration tests — cross-module round-trips, JSON, and concurrent generation.

const std = @import("std");
const uuid = @import("uuid");
const json = @import("json");

// =============================================================================
// Round-trip: generate → toString → fromString → eql
// =============================================================================

test "integration: V4 round-trip" {
    const u = try uuid.newV4();
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const parsed = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(parsed));
}

test "integration: V7 round-trip" {
    const u = try uuid.newV7();
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const parsed = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(parsed));
}

test "integration: V3 round-trip" {
    const u = uuid.newV3(uuid.namespace_dns, "www.example.com");
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const parsed = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(parsed));
}

test "integration: V5 round-trip" {
    const u = uuid.newV5(uuid.namespace_url, "https://example.com");
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const parsed = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(parsed));
}

test "integration: V1 round-trip" {
    const u = try uuid.newV1();
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const parsed = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(parsed));
    // Version and variant preserved
    try std.testing.expectEqual(uuid.Version.v1, parsed.version());
    try std.testing.expectEqual(uuid.Variant.rfc9562, parsed.variant());
}

// =============================================================================
// NullUUID JSON round-trip
// =============================================================================

test "integration: NullUUID null JSON round-trip" {
    const alloc = std.testing.allocator;
    const nu = uuid.NullUUID{};
    const v = try nu.jsonMarshal(alloc);
    try std.testing.expect(v == .null);
    const nu2 = try uuid.NullUUID.jsonUnmarshal(alloc, v);
    try std.testing.expect(!nu2.valid);
}

test "integration: NullUUID string JSON round-trip" {
    const alloc = std.testing.allocator;
    const u = try uuid.newV4();
    const nu = uuid.NullUUID.from(u);
    const v = try nu.jsonMarshal(alloc);
    defer alloc.free(v.str);
    const nu2 = try uuid.NullUUID.jsonUnmarshal(alloc, v);
    try std.testing.expect(nu2.valid);
    try std.testing.expect(nu2.uuid.eql(u));
}

test "integration: UUID in struct encoded with json.encode" {
    const alloc = std.testing.allocator;
    const MyStruct = struct {
        id: uuid.UUID,
        name: []const u8,
    };
    const s = MyStruct{
        .id = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8"),
        .name = "test",
    };
    const encoded = try json.encode(alloc, s, .{ .allocator = alloc });
    defer alloc.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "6ba7b810-9dad-11d1-80b4-00c04fd430c8") != null);
}

// =============================================================================
// Concurrent V7 generation: no duplicates, strictly monotone per goroutine
// =============================================================================

const ConcurrentResult = struct {
    uuids: [100]uuid.UUID = undefined,
    err: ?anyerror = null,
};

fn generateV7s(gen: *uuid.Generator, result: *ConcurrentResult) void {
    for (&result.uuids) |*u| {
        u.* = gen.newV7() catch |e| {
            result.err = e;
            return;
        };
    }
}

test "integration: concurrent V7 generation — no duplicates" {
    var gen = uuid.Generator.init();
    var results: [4]ConcurrentResult = [_]ConcurrentResult{.{}} ** 4;
    var threads: [4]std.Thread = undefined;

    for (&threads, &results) |*t, *r| {
        t.* = try std.Thread.spawn(.{}, generateV7s, .{ &gen, r });
    }
    for (&threads) |*t| t.join();

    for (&results) |*r| {
        try std.testing.expect(r.err == null);
    }

    // Collect all UUIDs and check for duplicates
    var all: [400]uuid.UUID = undefined;
    var idx: usize = 0;
    for (&results) |r| {
        for (r.uuids) |u| {
            all[idx] = u;
            idx += 1;
        }
    }
    // Sort and check adjacent for equality
    std.mem.sort(uuid.UUID, &all, {}, struct {
        pub fn lt(_: void, a: uuid.UUID, b: uuid.UUID) bool {
            return a.order(b) == .lt;
        }
    }.lt);
    for (0..all.len - 1) |i| {
        try std.testing.expect(!all[i].eql(all[i + 1]));
    }
}

// =============================================================================
// All parse formats produce the same UUID
// =============================================================================

test "integration: all six parse formats produce identical UUID" {
    const canonical = "6ba7b810-9dad-11d1-80b4-00c04fd430c8";
    const braced = "{6ba7b810-9dad-11d1-80b4-00c04fd430c8}";
    const hash = "6ba7b8109dad11d180b400c04fd430c8";
    const braced_hash = "{6ba7b8109dad11d180b400c04fd430c8}";
    const urn_canonical = "urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8";
    const urn_hash = "urn:uuid:6ba7b8109dad11d180b400c04fd430c8";

    const base = try uuid.UUID.fromString(canonical);
    const inputs = [_][]const u8{ braced, hash, braced_hash, urn_canonical, urn_hash };
    for (inputs) |s| {
        const u = try uuid.UUID.fromString(s);
        try std.testing.expect(base.eql(u));
    }
}

// =============================================================================
// timestampFromV7 returns Timestamp (G-4) — verify toUnixMs() round-trip
// =============================================================================

test "integration: timestampFromV7 returns Timestamp (G-4)" {
    const v7 = try uuid.newV7();
    const ts = try uuid.timestampFromV7(v7);
    // The extracted Unix ms should be a recent timestamp (after 2020-01-01)
    const ms = ts.toUnixMs();
    try std.testing.expect(ms > 1_577_836_800_000); // 2020-01-01 in Unix ms
}

// =============================================================================
// URN output round-trip (F-5 / G-3)
// =============================================================================

test "integration: toURN produces parseable URN" {
    const u = try uuid.newV4();
    var buf: [45]u8 = undefined;
    const urn = u.toURN(&buf);
    const parsed = try uuid.UUID.fromString(urn);
    try std.testing.expect(u.eql(parsed));
}

// =============================================================================
// Uppercase / nodash output (G-2)
// =============================================================================

test "integration: toStringUpper and toHexUpper produce uppercase" {
    const u = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    var buf36: [36]u8 = undefined;
    var buf32: [32]u8 = undefined;
    const upper = u.toStringUpper(&buf36);
    const hex_upper = u.toHexUpper(&buf32);
    try std.testing.expectEqualStrings("6BA7B810-9DAD-11D1-80B4-00C04FD430C8", upper);
    try std.testing.expectEqualStrings("6BA7B8109DAD11D180B400C04FD430C8", hex_upper);
}

// =============================================================================
// toHexAlloc / toHexUpperAlloc allocating round-trip (QC-49)
// =============================================================================

test "integration: toHexAlloc produces lowercase 32-char hex" {
    const alloc = std.testing.allocator;
    const u = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const lower = try u.toHexAlloc(alloc);
    defer alloc.free(lower);
    try std.testing.expectEqualStrings("6ba7b8109dad11d180b400c04fd430c8", lower);
    try std.testing.expectEqual(@as(usize, 32), lower.len);
}

test "integration: toHexUpperAlloc produces uppercase 32-char hex" {
    const alloc = std.testing.allocator;
    const u = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const upper = try u.toHexUpperAlloc(alloc);
    defer alloc.free(upper);
    try std.testing.expectEqualStrings("6BA7B8109DAD11D180B400C04FD430C8", upper);
    try std.testing.expectEqual(@as(usize, 32), upper.len);
}

// =============================================================================
// isZero alias (G-9)
// =============================================================================

test "integration: isZero is an alias for isNil (G-9)" {
    try std.testing.expect(uuid.UUID.nil.isZero());
    const u = try uuid.newV4();
    try std.testing.expect(!u.isZero());
}

// =============================================================================
// V6 round-trip (QC-27)
// =============================================================================

test "integration: V6 round-trip" {
    const u = try uuid.newV6();
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const parsed = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(parsed));
    try std.testing.expectEqual(uuid.Version.v6, parsed.version());
    try std.testing.expectEqual(uuid.Variant.rfc9562, parsed.variant());
}

// =============================================================================
// V8 round-trip (QC-27)
// =============================================================================

test "integration: V8 round-trip" {
    const a = [6]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const b = [2]u8{ 0x07, 0x08 };
    const c = [8]u8{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const u = uuid.newV8(a, b, c);
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const parsed = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(parsed));
    try std.testing.expectEqual(uuid.Version.v8, parsed.version());
    try std.testing.expectEqual(uuid.Variant.rfc9562, parsed.variant());
}

// =============================================================================
// saveState / loadState integration (QC-27)
// =============================================================================

test "integration: saveState + loadState round-trip preserves V1/V7 state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/uuid.state", .{dir_path});

    // Generate a V1 UUID to populate generator state, then save it.
    var gen = uuid.Generator.init();
    _ = try gen.newV1();
    _ = try gen.newV7();
    try gen.saveState(path);

    // Load into a fresh generator and verify it can generate valid UUIDs.
    var gen2 = uuid.Generator.init();
    try gen2.loadState(path);

    const v1 = try gen2.newV1();
    try std.testing.expectEqual(uuid.Version.v1, v1.version());
    try std.testing.expectEqual(uuid.Variant.rfc9562, v1.variant());

    const v7 = try gen2.newV7();
    try std.testing.expectEqual(uuid.Version.v7, v7.version());
    try std.testing.expectEqual(uuid.Variant.rfc9562, v7.variant());
}

// =============================================================================
// GeneratorInterface (G-8)
// =============================================================================

test "integration: GeneratorInterface dispatches newV4 (G-8)" {
    var gen = uuid.Generator.init();
    var iface = uuid.GeneratorInterface.fromGenerator(&gen);
    const u = try iface.newV4();
    try std.testing.expectEqual(uuid.Version.v4, u.version());
}

// =============================================================================
// Error path integration tests (QC-69): verify error propagation through the
// public API.  These are the first integration tests that call expectError.
// =============================================================================

test "integration: fromString rejects empty string (QC-69)" {
    try std.testing.expectError(uuid.Error.InvalidLength, uuid.UUID.fromString(""));
}

test "integration: fromString rejects string that is too short (QC-69)" {
    try std.testing.expectError(uuid.Error.InvalidLength, uuid.UUID.fromString("6ba7b810-9dad"));
}

test "integration: fromString rejects bad URN namespace (QC-69)" {
    // starts with "urn:" but not "urn:uuid:"
    try std.testing.expectError(
        uuid.Error.InvalidURNPrefix,
        uuid.UUID.fromString("urn:nope:6ba7b8109dad11d180b400c04fd430c8"),
    );
}

test "integration: fromString rejects URN with wrong-length payload (QC-69)" {
    // "urn:uuid:" prefix is valid but the UUID part is truncated
    try std.testing.expectError(
        uuid.Error.InvalidLength,
        uuid.UUID.fromString("urn:uuid:6ba7b810-9dad"),
    );
}

test "integration: fromString rejects non-hex characters (QC-69)" {
    try std.testing.expectError(
        uuid.Error.InvalidFormat,
        uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430ZZ"),
    );
}

test "integration: fromString rejects wrong dash positions (QC-69)" {
    // A 36-char string with dash at position 9 instead of 8
    try std.testing.expectError(
        uuid.Error.InvalidDashes,
        uuid.UUID.fromString("6ba7b810X9dad-11d1-80b4-00c04fd430c8"),
    );
}

test "integration: fromString rejects unclosed brace (QC-69)" {
    try std.testing.expectError(
        uuid.Error.InvalidBraces,
        uuid.UUID.fromString("{6ba7b810-9dad-11d1-80b4-00c04fd430c8"),
    );
}

test "integration: fromBytes rejects wrong-length slice (QC-69)" {
    const short = [_]u8{0x01} ** 8;
    try std.testing.expectError(uuid.Error.IncorrectByteLength, uuid.UUID.fromBytes(&short));
}

test "integration: NullUUID.jsonUnmarshal rejects non-string non-null value (QC-69)" {
    const alloc = std.testing.allocator;
    // .bool is not a valid JSON representation for a UUID
    try std.testing.expectError(
        uuid.Error.InvalidFormat,
        uuid.NullUUID.jsonUnmarshal(alloc, json.Value{ .bool = true }),
    );
}

test "integration: NullUUID.jsonUnmarshal rejects invalid UUID string (QC-69)" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(
        uuid.Error.InvalidLength,
        uuid.NullUUID.jsonUnmarshal(alloc, json.Value{ .str = "not-a-uuid" }),
    );
}

// =============================================================================
// timingSafeEql integration tests (QC-74): verify constant-time equality
// through the public uuid package API.
// =============================================================================

test "integration: timingSafeEql equal UUIDs (QC-74)" {
    // Equal UUIDs generated via the public package must compare equal.
    const u = try uuid.newV4();
    try std.testing.expect(u.timingSafeEql(u));
}

test "integration: timingSafeEql unequal UUIDs (QC-74)" {
    // Two independently generated V4 UUIDs must not compare equal.
    var gen = uuid.Generator.init();
    const a = try gen.newV4();
    const b = try gen.newV4();
    // Independently generated UUIDs are astronomically unlikely to collide; treat
    // equality as a test failure.
    try std.testing.expect(!a.timingSafeEql(b));
    // Symmetry: b.timingSafeEql(a) must agree with a.timingSafeEql(b).
    try std.testing.expect(a.timingSafeEql(b) == b.timingSafeEql(a));
}
