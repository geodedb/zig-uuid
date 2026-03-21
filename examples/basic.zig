// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Basic usage examples for the uuid library.

const std = @import("std");
const uuid = @import("uuid");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var buf: [36]u8 = undefined;

    try stdout.print("uuid library — RFC-9562 examples\n", .{});
    try stdout.print("=================================\n\n", .{});

    // V4: random
    const v4 = try uuid.newV4();
    try stdout.print("V4 (random):            {s}\n", .{v4.toString(&buf)});

    // V7: Unix-ms timestamp + monotonic counter
    const v7 = try uuid.newV7();
    try stdout.print("V7 (timestamp+random):  {s}\n", .{v7.toString(&buf)});

    // V7 at a historical timestamp (1,700,000,000,000 ms = 2023-11-14)
    const v7_hist = try uuid.newV7AtTime(1_700_000_000_000);
    try stdout.print("V7 (historical ts):     {s}\n", .{v7_hist.toString(&buf)});

    // V3: MD5 namespace hash
    const v3 = uuid.newV3(uuid.namespace_dns, "www.example.com");
    try stdout.print("V3 (MD5/DNS):           {s}\n", .{v3.toString(&buf)});

    // V5: SHA-1 namespace hash
    const v5 = uuid.newV5(uuid.namespace_dns, "www.example.com");
    try stdout.print("V5 (SHA1/DNS):          {s}\n", .{v5.toString(&buf)});

    // V1: time + MAC
    const v1 = uuid.newV1() catch |e| blk: {
        try stdout.print("V1: skipped ({s})\n", .{@errorName(e)});
        break :blk uuid.UUID.nil;
    };
    if (!v1.isNil()) try stdout.print("V1 (time+MAC):          {s}\n", .{v1.toString(&buf)});

    // V6: k-sortable time + MAC
    const v6 = uuid.newV6() catch |e| blk: {
        try stdout.print("V6: skipped ({s})\n", .{@errorName(e)});
        break :blk uuid.UUID.nil;
    };
    if (!v6.isNil()) try stdout.print("V6 (k-sortable time):   {s}\n", .{v6.toString(&buf)});

    // Parse formats
    try stdout.print("\nParse formats (all produce the same UUID):\n", .{});
    const formats = [_][]const u8{
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        "{6ba7b810-9dad-11d1-80b4-00c04fd430c8}",
        "6ba7b8109dad11d180b400c04fd430c8",
        "urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    };
    for (formats) |s| {
        const u = try uuid.UUID.fromString(s);
        try stdout.print("  parse({s})\n         → {s}\n", .{ s, u.toString(&buf) });
    }

    // Timestamp extraction
    const ts = try uuid.timestampFromV7(v7);
    try stdout.print("\nV7 timestamp (Unix ms): {d}\n", .{ts});

    // NullUUID
    const nu_valid = uuid.NullUUID.from(v4);
    const nu_null = uuid.NullUUID{};
    try stdout.print("\nNullUUID valid: {any}\n", .{nu_valid.value()});
    try stdout.print("NullUUID null:  {any}\n", .{nu_null.value()});

    try stdout.print("\nAll examples completed successfully!\n", .{});
}
