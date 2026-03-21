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
pub fn newV8(a: [6]u8, b: [2]u8, c: [8]u8) Error!UUID {
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
