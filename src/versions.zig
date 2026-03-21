// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const uuid_mod = @import("uuid.zig");
const gen_mod = @import("generator.zig");
const UUID = uuid_mod.UUID;
const Error = uuid_mod.Error;
const Timestamp = @import("timestamp.zig").Timestamp;

pub fn newV1() Error!UUID {
    return gen_mod.default_generator.newV1();
}

pub fn newV1AtTime(ts: Timestamp) Error!UUID {
    return gen_mod.default_generator.newV1AtTime(ts);
}

pub fn newV3(ns: UUID, name: []const u8) UUID {
    return gen_mod.default_generator.newV3(ns, name);
}

pub fn newV4() Error!UUID {
    return gen_mod.default_generator.newV4();
}

pub fn newV5(ns: UUID, name: []const u8) UUID {
    return gen_mod.default_generator.newV5(ns, name);
}

pub fn newV6() Error!UUID {
    return gen_mod.default_generator.newV6();
}

pub fn newV6AtTime(ts: Timestamp) Error!UUID {
    return gen_mod.default_generator.newV6AtTime(ts);
}

pub fn newV7() Error!UUID {
    return gen_mod.default_generator.newV7();
}

pub fn newV7AtTime(ts: i64) Error!UUID {
    return gen_mod.default_generator.newV7AtTime(ts);
}

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
