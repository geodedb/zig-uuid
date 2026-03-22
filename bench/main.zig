// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// UUID library benchmarks (PERF-03).
//
// Usage:
//   zig build bench -Doptimize=ReleaseFast
//
// Each benchmark runs `iters` iterations and reports ns/op and ops/sec.
// Run with -Doptimize=ReleaseFast for meaningful results; Debug builds
// include safety checks that skew timings by 10–50×.

const std = @import("std");
const uuid = @import("uuid");

const iters: usize = 1_000_000;

pub fn main() !void {
    std.debug.print("UUID benchmark — {d}M iterations each\n", .{iters / 1_000_000});
    std.debug.print("(Use -Doptimize=ReleaseFast for meaningful numbers)\n\n", .{});

    try benchV4();
    try benchV7();
    try benchV1();
    try benchV6();
    try benchToString();
    try benchFromString();
}

fn benchV4() !void {
    var gen = uuid.Generator.init();
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        _ = try gen.newV4();
    }
    report("newV4", start);
}

fn benchV7() !void {
    var gen = uuid.Generator.init();
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        _ = try gen.newV7();
    }
    report("newV7", start);
}

fn benchV1() !void {
    var gen = uuid.Generator.init();
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        _ = try gen.newV1();
    }
    report("newV1", start);
}

fn benchV6() !void {
    var gen = uuid.Generator.init();
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        _ = try gen.newV6();
    }
    report("newV6", start);
}

fn benchToString() !void {
    // PERF-11: Pre-build a pool of distinct UUIDs so the compiler cannot
    // hoist or constant-fold the toString call.  XOR one result byte into
    // `sink` and conditionally print `sink` after the loop so the
    // computation is observable and LLVM cannot DCE the loop body.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();

    var buf: [36]u8 = undefined;
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = pool[i % pool_size].toString(&buf);
        sink ^= s[0];
    }
    report("toString", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchFromString() !void {
    // PERF-11: Derive the input string at runtime from a freshly-generated
    // UUID so the parser cannot be constant-folded away.  XOR a result byte
    // into `sink` and conditionally print it to prevent DCE of the loop body.
    var gen = uuid.Generator.init();
    const u = try gen.newV4();
    var str_buf: [36]u8 = undefined;
    const s = u.toString(&str_buf);

    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(s);
        sink ^= parsed.bytes[0];
    }
    report("fromString", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn report(name: []const u8, start: i128) void {
    const elapsed = std.time.nanoTimestamp() - start;
    const ns_per_op = @divTrunc(elapsed, @as(i128, iters));
    const ops_per_sec = if (ns_per_op > 0)
        @divTrunc(1_000_000_000, ns_per_op)
    else
        0;
    std.debug.print("{s:<12} {d:>6} ns/op  {d:>12} ops/s\n", .{
        name,
        ns_per_op,
        ops_per_sec,
    });
}
