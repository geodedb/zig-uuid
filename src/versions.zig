// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const uuid_mod = @import("uuid.zig");
const gen_mod = @import("generator.zig");
const UUID = uuid_mod.UUID;
const Error = uuid_mod.Error;
const Timestamp = @import("timestamp.zig").Timestamp;

/// Generate a Version 1 (Gregorian-epoch time + node) UUID using the package-level
/// default generator. Uses a random multicast node ID by default (RFC-9562 §6.10).
pub fn newV1() Error!UUID {
    return gen_mod.default_generator.newV1();
}

/// Generate a Version 1 UUID at the given pre-computed Gregorian Timestamp.
/// Useful for deterministic or historical UUID generation.
pub fn newV1AtTime(ts: Timestamp) Error!UUID {
    return gen_mod.default_generator.newV1AtTime(ts);
}

/// Generate a Version 3 (MD5 name-based) UUID.
/// **Security:** MD5 is broken — prefer `newV5` or V8 with a modern hash.
pub fn newV3(ns: UUID, name: []const u8) UUID {
    return gen_mod.default_generator.newV3(ns, name);
}

/// Generate a Version 4 (random) UUID using the package-level default generator.
pub fn newV4() Error!UUID {
    return gen_mod.default_generator.newV4();
}

/// Generate a Version 5 (SHA-1 name-based) UUID.
/// **Security:** SHA-1 is weakened — consider V8 with SHA-256 for new systems.
pub fn newV5(ns: UUID, name: []const u8) UUID {
    return gen_mod.default_generator.newV5(ns, name);
}

/// Generate a Version 6 (reordered Gregorian timestamp, k-sortable) UUID using the
/// package-level default generator. Lexicographically sortable alternative to V1.
pub fn newV6() Error!UUID {
    return gen_mod.default_generator.newV6();
}

/// Generate a Version 6 UUID at the given pre-computed Gregorian Timestamp.
pub fn newV6AtTime(ts: Timestamp) Error!UUID {
    return gen_mod.default_generator.newV6AtTime(ts);
}

/// Generate a Version 7 (Unix-ms timestamp + monotonic counter) UUID using the
/// package-level default generator. Recommended for new systems requiring sortable UUIDs.
pub fn newV7() Error!UUID {
    return gen_mod.default_generator.newV7();
}

/// Generate a Version 7 UUID at the given Unix millisecond timestamp `ts`.
/// Returns `Error.InvalidTimestamp` if `ts < 0`.
pub fn newV7AtTime(ts: i64) Error!UUID {
    return gen_mod.default_generator.newV7AtTime(ts);
}

/// Generate a Version 8 (custom) UUID with caller-supplied bit fields.
/// `a` fills bytes 0-5, `b` fills bytes 6-7 (high 4 bits become version nibble),
/// `c` fills bytes 8-15 (high 2 bits become variant bits).
///
/// This function is infallible — no clock, random, or I/O is needed.
pub fn newV8(a: [6]u8, b: [2]u8, c: [8]u8) UUID {
    return gen_mod.default_generator.newV8(a, b, c);
}

test "top-level newV4 delegates to default_generator" {
    const u = try newV4();
    try std.testing.expectEqual(uuid_mod.Version.v4, u.version());
}

test "top-level newV7 delegates to default_generator" {
    const u = try newV7();
    try std.testing.expectEqual(uuid_mod.Version.v7, u.version());
}

test "top-level newV3 with DNS namespace" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = newV3(ns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        u.toString(&buf),
    );
}

// QC-30: delegation tests for the 7 previously-untested convenience functions.

test "top-level newV1 delegates to default_generator (QC-30)" {
    const u = try newV1();
    try std.testing.expectEqual(uuid_mod.Version.v1, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
}

test "top-level newV1AtTime delegates to default_generator (QC-30)" {
    const ts_mod = @import("timestamp.zig");
    const greg_ts = ts_mod.Timestamp{ .value = 139_806_912_000_000_000 }; // 2024-01-01 UTC
    const u = try newV1AtTime(greg_ts);
    try std.testing.expectEqual(uuid_mod.Version.v1, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
    // Timestamp round-trip.
    const got = try ts_mod.timestampFromV1(u);
    try std.testing.expectEqual(greg_ts.value, got.value);
}

test "top-level newV5 delegates to default_generator (QC-30)" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = newV5(ns, "www.example.com");
    // RFC-9562 / Python uuid.uuid5() test vector.
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2ed6657d-e927-568b-95e1-2665a8aea6a2",
        u.toString(&buf),
    );
}

test "top-level newV6 delegates to default_generator (QC-30)" {
    const u = try newV6();
    try std.testing.expectEqual(uuid_mod.Version.v6, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
}

test "top-level newV6AtTime delegates to default_generator (QC-30)" {
    const ts_mod = @import("timestamp.zig");
    const greg_ts = ts_mod.Timestamp{ .value = 139_806_912_000_000_000 }; // 2024-01-01 UTC
    const u = try newV6AtTime(greg_ts);
    try std.testing.expectEqual(uuid_mod.Version.v6, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
    const got = try ts_mod.timestampFromV6(u);
    try std.testing.expectEqual(greg_ts.value, got.value);
}

test "top-level newV7AtTime delegates to default_generator (QC-30)" {
    const ts_mod = @import("timestamp.zig");
    const ms: i64 = 1_700_000_000_000; // 2023-11-14 in Unix ms
    const u = try newV7AtTime(ms);
    try std.testing.expectEqual(uuid_mod.Version.v7, u.version());
    const got = try ts_mod.timestampFromV7(u);
    try std.testing.expectEqual(ms, got.toUnixMs());
}

test "top-level newV8 delegates to default_generator (QC-30)" {
    const a = [6]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const b = [2]u8{ 0x07, 0x08 };
    const c = [8]u8{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const u = newV8(a, b, c);
    try std.testing.expectEqual(uuid_mod.Version.v8, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
}
