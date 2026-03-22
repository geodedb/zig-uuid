// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;

/// All-zero UUID (RFC-9562 nil UUID).
/// QC-93: single source of truth is UUID.nil in uuid.zig.
pub const nil = UUID.nil;

/// All-ones UUID (RFC-9562 max UUID).
/// QC-93: single source of truth is UUID.max in uuid.zig.
pub const max = UUID.max;

/// DNS namespace UUID: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
pub const namespace_dns = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// URL namespace UUID: 6ba7b811-9dad-11d1-80b4-00c04fd430c8
pub const namespace_url = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// OID namespace UUID: 6ba7b812-9dad-11d1-80b4-00c04fd430c8
pub const namespace_oid = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x12, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// X.500 namespace UUID: 6ba7b814-9dad-11d1-80b4-00c04fd430c8
pub const namespace_x500 = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x14, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

test "namespace_dns canonical string" {
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        namespace_dns.toString(&buf),
    );
}

test "namespace constants are distinct" {
    try std.testing.expect(!namespace_dns.eql(namespace_url));
    try std.testing.expect(!namespace_dns.eql(namespace_oid));
    try std.testing.expect(!namespace_dns.eql(namespace_x500));
}

test "nil and max are correct" {
    try std.testing.expect(nil.isNil());
    for (max.bytes) |b| try std.testing.expectEqual(@as(u8, 0xFF), b);
}
