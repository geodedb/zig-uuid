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
// Sub-nanosecond operations need more iterations to get measurable results.
const fast_iters: usize = 100_000_000;


// std.time.nanoTimestamp was removed in Zig 0.16. Use the Io.Clock primitive
// directly with the library's default single-threaded Io.
fn nanoTimestamp() i128 {
    const io = std.Io.Threaded.global_single_threaded.io();
    return std.Io.Clock.Timestamp.now(io, .real).raw.nanoseconds;
}

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
    try benchToHex();
    try benchToHexUpper();
    try benchToHexAlloc();
    try benchV7AtTime();
    try benchFromString();
    try benchFromStringHex();
    try benchFromStringURN();
    try benchEql();
    try benchTimingSafeEql();
    try benchV7Contention();
}

fn benchV4() !void {
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV4();
        sink ^= u.bytes[0];
    }
    report("newV4", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchV7() !void {
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV7();
        sink ^= u.bytes[0];
    }
    report("newV7", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchV1() !void {
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV1();
        sink ^= u.bytes[0];
    }
    report("newV1", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchV6() !void {
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV6();
        sink ^= u.bytes[0];
    }
    report("newV6", start);
    std.mem.doNotOptimizeAway(sink);
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
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = gen.newV3(uuid.namespace_dns, &names[i % pool_size]);
        sink ^= u.bytes[0];
    }
    report("newV3", start);
    std.mem.doNotOptimizeAway(sink);
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
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = gen.newV5(uuid.namespace_dns, &names[i % pool_size]);
        sink ^= u.bytes[0];
    }
    report("newV5", start);
    std.mem.doNotOptimizeAway(sink);
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
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = pool[i % pool_size].toString(&buf);
        sink ^= s[0];
    }
    report("toString", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchToStringUpper() !void {
    // PERF-18: Uppercase string variant benchmark.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();

    var buf: [36]u8 = undefined;
    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = pool[i % pool_size].toStringUpper(&buf);
        sink ^= s[0];
        std.mem.doNotOptimizeAway(&buf);
    }
    report("toStringUpper", start);
    std.mem.doNotOptimizeAway(sink);
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
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = try pool[i % pool_size].toStringAlloc(alloc);
        defer alloc.free(s);
        sink ^= s[0];
    }
    report("toStringAlloc", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchToHex() !void {
    // PERF-20: Lowercase no-alloc hex benchmark — separate compiler
    // instantiation from toHexUpper; regression in lowercase table would
    // otherwise go undetected.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();

    var buf: [32]u8 = undefined;
    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = pool[i % pool_size].toHex(&buf);
        sink ^= s[0];
    }
    report("toHex", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchToHexUpper() !void {
    // PERF-18: Uppercase hex variant benchmark.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();

    var buf: [32]u8 = undefined;
    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = pool[i % pool_size].toHexUpper(&buf);
        sink ^= s[0];
        std.mem.doNotOptimizeAway(&buf);
    }
    report("toHexUpper", start);
    std.mem.doNotOptimizeAway(sink);
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
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const s = try pool[i % pool_size].toHexAlloc(alloc);
        defer alloc.free(s);
        sink ^= s[0];
    }
    report("toHexAlloc", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchV7AtTime() !void {
    // PERF-17: V7 base generation cost without ceiling/spin-wait.
    // Increments ms by 1 per call to bypass the mono_seq overflow path.
    // Expected ~20-25 ns/op (true V7 encoding cost).
    var gen = uuid.Generator.init();
    var ms: i64 = 1_700_000_000_000;
    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV7AtTime(ms);
        sink ^= u.bytes[0];
        ms += 1;
    }
    report("newV7AtTime", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchFromString() !void {
    // PERF-11 / PERF-25: Pre-generate a pool of 256 distinct UUID strings so
    // the parser cannot constant-fold or hoist the result across iterations.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var str_pool: [pool_size][36]u8 = undefined;
    var slices: [pool_size][]const u8 = undefined;
    for (&str_pool, 0..) |*buf, j| {
        const u = try gen.newV4();
        const s = u.toString(buf);
        slices[j] = s;
    }

    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(slices[i % pool_size]);
        sink ^= parsed.bytes[0];
    }
    report("fromString", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchFromStringHex() !void {
    // QC-45 / PERF-25: benchmark fromString with 32-char hex (no-dashes) input.
    // Pre-generate a pool of 256 distinct hex strings to prevent constant folding.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var hex_pool: [pool_size][32]u8 = undefined;
    var slices: [pool_size][]const u8 = undefined;
    for (&hex_pool, 0..) |*buf, j| {
        const u = try gen.newV4();
        const s = u.toHex(buf);
        slices[j] = s;
    }

    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(slices[i % pool_size]);
        sink ^= parsed.bytes[0];
    }
    report("fromStr/hex", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchFromStringURN() !void {
    // QC-45 / PERF-25: benchmark fromString with urn:uuid: prefixed canonical input.
    // Pre-generate a pool of 256 distinct URN strings to prevent constant folding.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var urn_pool: [pool_size][45]u8 = undefined;
    var slices: [pool_size][]const u8 = undefined;
    for (&urn_pool, 0..) |*buf, j| {
        const u = try gen.newV4();
        const s = u.toURN(buf);
        slices[j] = s;
    }

    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(slices[i % pool_size]);
        sink ^= parsed.bytes[0];
    }
    report("fromStr/urn", start);
    std.mem.doNotOptimizeAway(sink);
}

fn benchEql() !void {
    // QC-73 / PERF-22: benchmark UUID.eql() — non-constant-time byte comparison.
    // Uses fast_iters (100M) because 16-byte memcmp is sub-nanosecond at ReleaseFast.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool_a: [pool_size]uuid.UUID = undefined;
    var pool_b: [pool_size]uuid.UUID = undefined;
    for (&pool_a) |*u| u.* = try gen.newV4();
    for (&pool_b) |*u| u.* = try gen.newV4();
    std.mem.doNotOptimizeAway(&pool_a);
    std.mem.doNotOptimizeAway(&pool_b);

    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < fast_iters) : (i += 1) {
        var idx = i % pool_size;
        std.mem.doNotOptimizeAway(&idx);
        const result = pool_a[idx].eql(pool_b[idx]);
        sink ^= @intFromBool(result);
    }
    reportN("eql", start, fast_iters);
    std.mem.doNotOptimizeAway(sink);
}

fn benchTimingSafeEql() !void {
    // QC-73 / PERF-22: benchmark UUID.timingSafeEql() — constant-time comparison
    // via std.crypto.timing_safe.eql.
    // Uses fast_iters (100M) because 16-byte XOR+OR is sub-nanosecond at ReleaseFast.
    var gen = uuid.Generator.init();
    const pool_size = 256;
    var pool_a: [pool_size]uuid.UUID = undefined;
    var pool_b: [pool_size]uuid.UUID = undefined;
    for (&pool_a) |*u| u.* = try gen.newV4();
    for (&pool_b) |*u| u.* = try gen.newV4();

    var sink: u8 = 0;
    const start = nanoTimestamp();
    var i: usize = 0;
    while (i < fast_iters) : (i += 1) {
        var idx = i % pool_size;
        std.mem.doNotOptimizeAway(&idx);
        const result = pool_a[idx].timingSafeEql(pool_b[idx]);
        sink ^= @intFromBool(result);
    }
    reportN("timingSafeEql", start, fast_iters);
    std.mem.doNotOptimizeAway(sink);
}

fn reportN(name: []const u8, start: i128, n: usize) void {
    const elapsed = nanoTimestamp() - start;
    const ns_per_op = @divTrunc(elapsed, @as(i128, n));
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

fn report(name: []const u8, start: i128) void {
    const elapsed = nanoTimestamp() - start;
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

// =============================================================================
// PERF-22: multi-threaded V7 contention benchmark.
//
// Spawns `getCpuCount()` worker threads, each calling `newV7` for a fixed
// iteration count on a SHARED `Generator`.  Measures aggregate throughput
// and wall-clock time so PERF-21 (lock-free CAS V7) has a regression gate
// without needing a dedicated repro harness.
// =============================================================================

const contention_iters_per_thread: usize = 200_000;

const V7ContentionCtx = struct {
    gen: *uuid.Generator,
    iters: usize,
    sink: u8,
    err: ?anyerror = null,
};

fn v7ContentionWorker(ctx: *V7ContentionCtx) void {
    var sink: u8 = 0;
    var i: usize = 0;
    while (i < ctx.iters) : (i += 1) {
        const u = ctx.gen.newV7() catch |e| {
            ctx.err = e;
            return;
        };
        sink ^= u.bytes[0];
    }
    ctx.sink = sink;
}

fn benchV7Contention() !void {
    const thread_count_raw: usize = std.Thread.getCpuCount() catch 8;
    // Clamp to a reasonable upper bound so wildly-large CPU counts (e.g.,
    // 256-core servers) do not produce misleading numbers dominated by
    // scheduler noise; the benchmark is meant to characterise contention,
    // not system saturation.
    const thread_count: usize = if (thread_count_raw > 32) 32 else thread_count_raw;

    var shared_gen = uuid.Generator.init();
    var alloc_buf: [32 * (@sizeOf(V7ContentionCtx) + @sizeOf(std.Thread))]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&alloc_buf);
    const alloc = fba.allocator();

    const ctxs = try alloc.alloc(V7ContentionCtx, thread_count);
    defer alloc.free(ctxs);
    const threads = try alloc.alloc(std.Thread, thread_count);
    defer alloc.free(threads);

    for (ctxs) |*c| {
        c.* = .{
            .gen = &shared_gen,
            .iters = contention_iters_per_thread,
            .sink = 0,
        };
    }

    const start = nanoTimestamp();
    for (threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, v7ContentionWorker, .{&ctxs[i]});
    }
    for (threads) |t| t.join();
    const elapsed = nanoTimestamp() - start;

    // Surface per-worker errors (RandomError, InvalidTimestamp) without
    // masking the headline throughput.
    for (ctxs) |c| if (c.err) |e| return e;

    const total_ops: i128 = @as(i128, @intCast(thread_count)) *
        @as(i128, @intCast(contention_iters_per_thread));
    const ns_per_op = if (total_ops > 0) @divTrunc(elapsed, total_ops) else 0;
    const ops_per_sec = if (elapsed > 0)
        @divTrunc(total_ops * 1_000_000_000, elapsed)
    else
        0;
    const wall_ms = @divTrunc(elapsed, 1_000_000);

    std.debug.print(
        "v7Contend/{d}T  {d:>6} ns/op  {d:>12} ops/s  (wall {d} ms, {d} total ops)\n",
        .{ thread_count, ns_per_op, ops_per_sec, wall_ms, total_ops },
    );

    // Defeat DCE — the workers' sink bytes must be observable.
    var total_sink: u8 = 0;
    for (ctxs) |c| total_sink ^= c.sink;
    std.mem.doNotOptimizeAway(total_sink);
}
