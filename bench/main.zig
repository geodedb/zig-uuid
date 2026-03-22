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
    try benchV3();
    try benchV5();
    try benchToString();
    try benchToStringUpper();
    try benchToStringAlloc();
    try benchToHexUpper();
    try benchToHexAlloc();
    try benchV7AtTime();
    try benchFromString();
    try benchFromStringHex();
    try benchFromStringURN();
    try benchEql();
    try benchTimingSafeEql();
}

fn benchV4() !void {
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV4();
        sink ^= u.bytes[0];
    }
    report("newV4", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchV7() !void {
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV7();
        sink ^= u.bytes[0];
    }
    report("newV7", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchV1() !void {
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV1();
        sink ^= u.bytes[0];
    }
    report("newV1", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchV6() !void {
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV6();
        sink ^= u.bytes[0];
    }
    report("newV6", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchV3() !void {
    // QC-34: MD5 name-based UUID throughput.
    // Pre-compute a varied name pool so the compiler cannot hoist the hash call.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var names: [pool_size][8]u8 = undefined;
    for (&names, 0..) |*n, i| {
        std.mem.writeInt(u64, n, @as(u64, i), .little);
    }
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = gen.newV3(uuid.namespace_dns, &names[i % pool_size]);
        sink ^= u.bytes[0];
    }
    report("newV3", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchV5() !void {
    // QC-34: SHA-1 name-based UUID throughput.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var names: [pool_size][8]u8 = undefined;
    for (&names, 0..) |*n, i| {
        std.mem.writeInt(u64, n, @as(u64, i), .little);
    }
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = gen.newV5(uuid.namespace_dns, &names[i % pool_size]);
        sink ^= u.bytes[0];
    }
    report("newV5", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
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

fn benchToStringUpper() !void {
    // PERF-18: Uppercase string variant benchmark.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();

    var buf: [36]u8 = undefined;
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = pool[i % pool_size].toStringUpper(&buf);
        sink ^= s[0];
    }
    report("toStringUpper", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchToStringAlloc() !void {
    // PERF-16: Allocating string variant benchmark (page_allocator).
    // Expected ~1800 ns/op — ~300× slower than the stack variant.
    const alloc = std.heap.page_allocator;
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();

    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = try pool[i % pool_size].toStringAlloc(alloc);
        defer alloc.free(s);
        sink ^= s[0];
    }
    report("toStringAlloc", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchToHexUpper() !void {
    // PERF-18: Uppercase hex variant benchmark.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();

    var buf: [32]u8 = undefined;
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = pool[i % pool_size].toHexUpper(&buf);
        sink ^= s[0];
    }
    report("toHexUpper", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchToHexAlloc() !void {
    // PERF-16: Allocating hex variant benchmark (page_allocator).
    // Expected ~1800 ns/op — ~300× slower than the stack variant.
    const alloc = std.heap.page_allocator;
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();

    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = try pool[i % pool_size].toHexAlloc(alloc);
        defer alloc.free(s);
        sink ^= s[0];
    }
    report("toHexAlloc", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchV7AtTime() !void {
    // PERF-17: V7 base generation cost without ceiling/spin-wait.
    // Increments ms by 1 per call to bypass the mono_seq overflow path.
    // Expected ~20-25 ns/op (true V7 encoding cost).
    var gen = uuid.Generator.init();
    var ms: i64 = 1_700_000_000_000;
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV7AtTime(ms);
        sink ^= u.bytes[0];
        ms += 1;
    }
    report("newV7AtTime", start);
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

fn benchFromStringHex() !void {
    // QC-45: benchmark fromString with 32-char hex (no-dashes) input.
    var gen = uuid.Generator.init();
    const u = try gen.newV4();
    var hex_buf: [32]u8 = undefined;
    const s = u.toHex(&hex_buf);

    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(s);
        sink ^= parsed.bytes[0];
    }
    report("fromStr/hex", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchFromStringURN() !void {
    // QC-45: benchmark fromString with urn:uuid: prefixed canonical input.
    var gen = uuid.Generator.init();
    const u = try gen.newV4();
    var urn_buf: [45]u8 = undefined;
    const s = u.toURN(&urn_buf);

    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(s);
        sink ^= parsed.bytes[0];
    }
    report("fromStr/urn", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchEql() !void {
    // QC-73: benchmark UUID.eql() — non-constant-time byte comparison.
    var gen = uuid.Generator.init();
    const a = try gen.newV4();
    const b = try gen.newV4();
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const result = a.eql(b);
        sink ^= if (result) @as(u8, 1) else @as(u8, 0);
    }
    report("eql", start);
    if (sink == 0xff) std.debug.print("  (sink={d})\n", .{sink});
}

fn benchTimingSafeEql() !void {
    // QC-73: benchmark UUID.timingSafeEql() — constant-time comparison via
    // std.crypto.timing_safe.eql. Measures the overhead vs eql() so callers
    // can make informed decisions about where timing safety is needed.
    var gen = uuid.Generator.init();
    const a = try gen.newV4();
    const b = try gen.newV4();
    var sink: u8 = 0;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const result = a.timingSafeEql(b);
        sink ^= if (result) @as(u8, 1) else @as(u8, 0);
    }
    report("timingSafeEql", start);
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
