// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Basic usage examples for the uuid library.

const std = @import("std");
const uuid = @import("uuid");

pub fn main() !void {
    var out_buf: [4096]u8 = undefined;
    var out = std.fs.File.writer(std.fs.File.stdout(), &out_buf);
    defer out.interface.flush() catch {};
    const w = &out.interface;

    var buf: [36]u8 = undefined;

    try w.print("uuid library — RFC-9562 examples\n", .{});
    try w.print("=================================\n\n", .{});

    // V4: random
    const v4 = try uuid.newV4();
    try w.print("V4 (random):            {s}\n", .{v4.toString(&buf)});

    // V7: Unix-ms timestamp + monotonic counter
    const v7 = try uuid.newV7();
    try w.print("V7 (timestamp+random):  {s}\n", .{v7.toString(&buf)});

    // V7 at a historical timestamp (1,700,000,000,000 ms = 2023-11-14)
    const v7_hist = try uuid.newV7AtTime(1_700_000_000_000);
    try w.print("V7 (historical ts):     {s}\n", .{v7_hist.toString(&buf)});

    // V3: MD5 namespace hash
    const v3 = uuid.newV3(uuid.namespace_dns, "www.example.com");
    try w.print("V3 (MD5/DNS):           {s}\n", .{v3.toString(&buf)});

    // V5: SHA-1 namespace hash
    const v5 = uuid.newV5(uuid.namespace_dns, "www.example.com");
    try w.print("V5 (SHA1/DNS):          {s}\n", .{v5.toString(&buf)});

    // V1: time + random node (MAC opt-in via withHWAddr)
    const v1 = uuid.newV1() catch |e| blk: {
        try w.print("V1: skipped ({s})\n", .{@errorName(e)});
        break :blk uuid.UUID.nil;
    };
    if (!v1.isNil()) try w.print("V1 (time+node):         {s}\n", .{v1.toString(&buf)});

    // V6: k-sortable time + random node
    const v6 = uuid.newV6() catch |e| blk: {
        try w.print("V6: skipped ({s})\n", .{@errorName(e)});
        break :blk uuid.UUID.nil;
    };
    if (!v6.isNil()) try w.print("V6 (k-sortable time):   {s}\n", .{v6.toString(&buf)});

    // Parse formats
    try w.print("\nParse formats (all produce the same UUID):\n", .{});
    const formats = [_][]const u8{
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        "{6ba7b810-9dad-11d1-80b4-00c04fd430c8}",
        "6ba7b8109dad11d180b400c04fd430c8",
        "urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    };
    for (formats) |s| {
        const u = try uuid.UUID.fromString(s);
        try w.print("  parse({s})\n         → {s}\n", .{ s, u.toString(&buf) });
    }

    // std.fmt {f} specifier (Zig 0.15+, QC-24): no stack buffer needed.
    // Use {f} anywhere you'd pass a UUID to std.fmt.print / std.log / writer.print.
    try w.print("\n{{f}} format specifier (zero-alloc, no stack buffer):\n", .{});
    try w.print("  V4 via {{f}}:          {f}\n", .{v4});
    try w.print("  V7 via {{f}}:          {f}\n", .{v7});

    // Output format variants (G-2)
    try w.print("\nOutput formats:\n", .{});
    var buf36: [36]u8 = undefined;
    var buf32: [32]u8 = undefined;
    var buf45: [45]u8 = undefined;
    try w.print("  lowercase+dashes:   {s}\n", .{v4.toString(&buf36)});
    try w.print("  uppercase+dashes:   {s}\n", .{v4.toStringUpper(&buf36)});
    try w.print("  lowercase hex:      {s}\n", .{v4.toHex(&buf32)});
    try w.print("  uppercase hex:      {s}\n", .{v4.toHexUpper(&buf32)});
    try w.print("  URN:                {s}\n", .{v4.toURN(&buf45)});

    // Allocating hex output (QC-53): heap-allocated, caller must free.
    // Use std.heap.page_allocator for standalone examples; prefer
    // an arena or GPA in production code.
    const page_alloc = std.heap.page_allocator;
    const hex_lower = try v4.toHexAlloc(page_alloc);
    defer page_alloc.free(hex_lower);
    const hex_upper = try v4.toHexUpperAlloc(page_alloc);
    defer page_alloc.free(hex_upper);
    try w.print("\nAllocating hex output:\n", .{});
    try w.print("  toHexAlloc:      {s}\n", .{hex_lower});
    try w.print("  toHexUpperAlloc: {s}\n", .{hex_upper});

    // Timestamp extraction (G-4: timestampFromV7 now returns Timestamp)
    const ts = try uuid.timestampFromV7(v7);
    try w.print("\nV7 timestamp (Unix ms): {d}\n", .{ts.toUnixMs()});
    try w.print("V7 timestamp (Unix s):  {d}\n", .{ts.toUnixSec()});

    // NullUUID
    const nu_valid = uuid.NullUUID.from(v4);
    const nu_null = uuid.NullUUID{};
    try w.print("\nNullUUID valid: {f}\n", .{nu_valid});
    try w.print("NullUUID null:  {f}\n", .{nu_null});

    try w.print("\nAll examples completed successfully!\n", .{});
}
