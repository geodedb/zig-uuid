// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// CI-safe single-thread benchmark suite for the uuid library.
//
// Each scenario runs at ReleaseFast for 1M iterations (100M for sub-ns ops).
// The harness wraps every scenario in a 7-run / median-of-6 / stddev pattern
// so compare.zig can gate on measured per-row noise in addition to the 15%
// hard regression threshold (PERF-26).
//
// Run with:
//   zig build bench -Doptimize=ReleaseFast
//   zig build bench -- --output benchmarks/results/latest.json
//
// Target runtime <= 60s wall clock.

const std = @import("std");
const uuid = @import("uuid");
const common = @import("common");

const iters: u64 = 1_000_000;
const fast_iters: u64 = 100_000_000;
const pool_size: usize = 256;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try common.parseOutputArg(allocator, init.minimal.args);

    // Scenarios are declared in execution order.  The harness will re-run
    // each spec 7 times and pick the median throughput.  All scenarios here
    // are single-thread so `thread_count = 1`.
    const specs = [_]common.ScenarioSpec{
        .{ .name = "v4_random_default", .runFn = scenarioV4 },
        .{ .name = "v7_random_mutex", .variant = "mutex", .runFn = scenarioV7Mutex },
        .{ .name = "v7_random_lockfree", .variant = "lockfree", .runFn = scenarioV7Lockfree },
        .{ .name = "v1_random_default", .runFn = scenarioV1 },
        .{ .name = "v6_random_default", .runFn = scenarioV6 },
        .{ .name = "v3_dns_short", .runFn = scenarioV3Short },
        .{ .name = "v5_dns_short", .runFn = scenarioV5Short },
        .{ .name = "v3_dns_prehashed", .variant = "prehashed", .runFn = scenarioV3Prehashed },
        .{ .name = "v5_dns_prehashed", .variant = "prehashed", .runFn = scenarioV5Prehashed },
        .{ .name = "v8_custom", .runFn = scenarioV8 },
        .{ .name = "fromString_canonical", .runFn = scenarioFromStringCanonical },
        .{ .name = "fromString_braced", .runFn = scenarioFromStringBraced },
        .{ .name = "fromString_urn", .runFn = scenarioFromStringURN },
        .{ .name = "fromString_hash_32", .runFn = scenarioFromStringHash },
        .{ .name = "toString_lower", .runFn = scenarioToString },
        .{ .name = "toString_upper", .runFn = scenarioToStringUpper },
        .{ .name = "toHex_lower", .runFn = scenarioToHex },
        .{ .name = "toURN", .runFn = scenarioToURN },
        .{ .name = "toStringAlloc_page", .allocator_kind = "page", .runFn = scenarioToStringAllocPage },
        .{ .name = "toStringAlloc_arena", .allocator_kind = "arena", .runFn = scenarioToStringAllocArena },
        .{ .name = "eql", .expected_iterations = fast_iters, .runFn = scenarioEql },
        .{ .name = "timingSafeEql", .expected_iterations = fast_iters, .runFn = scenarioTimingSafeEql },
        .{ .name = "eql_differ_first_byte", .expected_iterations = fast_iters, .runFn = scenarioEqlDifferFirstByte },
    };

    try common.runScenarios(allocator, init.io, &specs, output);
}

// --------------------------------------------------------------------------
// Scenario impls.  Each returns a RunResult with `iterations` set and (for
// non-fast scenarios) an allocator-owned latency buffer; the harness frees
// the buffer after computing the summary.
// --------------------------------------------------------------------------

fn scenarioV4(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV4();
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioV7Mutex(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV7();
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioV7Lockfree(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.initOptions(.{ .v7_lockfree = true });
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV7();
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    var res = common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
    res.lockfree_fallbacks = gen.v7_lockfree_fallbacks.load(.monotonic);
    return res;
}

fn scenarioV1(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV1();
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioV6(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = try gen.newV6();
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioV3Short(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var names: [pool_size][8]u8 = undefined;
    for (&names, 0..) |*n, idx| std.mem.writeInt(u64, n, @as(u64, idx), .little);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = gen.newV3(uuid.namespace_dns, &names[@as(usize, @intCast(i % pool_size))]);
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioV5Short(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var names: [pool_size][8]u8 = undefined;
    for (&names, 0..) |*n, idx| std.mem.writeInt(u64, n, @as(u64, idx), .little);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = gen.newV5(uuid.namespace_dns, &names[@as(usize, @intCast(i % pool_size))]);
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioV3Prehashed(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    const pre = gen.initV3Namespace(uuid.namespace_dns);
    var names: [pool_size][8]u8 = undefined;
    for (&names, 0..) |*n, idx| std.mem.writeInt(u64, n, @as(u64, idx), .little);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = pre.name(&names[@as(usize, @intCast(i % pool_size))]);
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioV5Prehashed(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    const pre = gen.initV5Namespace(uuid.namespace_dns);
    var names: [pool_size][8]u8 = undefined;
    for (&names, 0..) |*n, idx| std.mem.writeInt(u64, n, @as(u64, idx), .little);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const u = pre.name(&names[@as(usize, @intCast(i % pool_size))]);
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioV8(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var a: [6]u8 = [_]u8{ 1, 2, 3, 4, 5, 6 };
    var b: [2]u8 = [_]u8{ 7, 8 };
    var c: [8]u8 = [_]u8{ 9, 10, 11, 12, 13, 14, 15, 16 };
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        // Vary inputs so the compiler cannot constant-fold the hash result.
        a[0] +%= 1;
        b[0] +%= 1;
        c[0] +%= 1;
        const u = gen.newV8(a, b, c);
        sink ^= u.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    std.mem.doNotOptimizeAway(&a);
    std.mem.doNotOptimizeAway(&b);
    std.mem.doNotOptimizeAway(&c);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

// ---- Parsing scenarios -----------------------------------------------------

fn StringPool(comptime L: usize) type {
    return struct {
        pool: [pool_size][L]u8,
        /// Rebuild the slice table — callers MUST do this after receiving the
        /// value-returned struct because value-returning an array copies the
        /// storage, which invalidates any pointers taken before the copy.
        pub fn rebuildSlices(self: *@This(), slices: *[pool_size][]const u8) void {
            var j: usize = 0;
            while (j < pool_size) : (j += 1) slices[j] = self.pool[j][0..L];
        }
    };
}

fn buildStringPool(comptime L: usize, comptime formatter: fn (uuid.UUID, *[L]u8) []u8) !StringPool(L) {
    var gen = uuid.Generator.init();
    var out: StringPool(L) = undefined;
    for (&out.pool) |*buf| {
        const u = try gen.newV4();
        _ = formatter(u, buf);
    }
    return out;
}

fn scenarioFromStringCanonical(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var pack = try buildStringPool(36, uuid.UUID.toString);
    var slices: [pool_size][]const u8 = undefined;
    pack.rebuildSlices(&slices);
    std.mem.doNotOptimizeAway(&slices);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(slices[@as(usize, @intCast(i % pool_size))]);
        sink ^= parsed.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioFromStringBraced(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var pool: [pool_size][38]u8 = undefined;
    var slices: [pool_size][]const u8 = undefined;
    for (&pool, 0..) |*buf, j| {
        const u = try gen.newV4();
        buf[0] = '{';
        var inner: [36]u8 = undefined;
        _ = u.toString(&inner);
        @memcpy(buf[1..37], &inner);
        buf[37] = '}';
        slices[j] = buf[0..38];
    }
    std.mem.doNotOptimizeAway(&slices);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(slices[@as(usize, @intCast(i % pool_size))]);
        sink ^= parsed.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioFromStringURN(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var pack = try buildStringPool(45, uuid.UUID.toURN);
    var slices: [pool_size][]const u8 = undefined;
    pack.rebuildSlices(&slices);
    std.mem.doNotOptimizeAway(&slices);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(slices[@as(usize, @intCast(i % pool_size))]);
        sink ^= parsed.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioFromStringHash(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var pack = try buildStringPool(32, uuid.UUID.toHex);
    var slices: [pool_size][]const u8 = undefined;
    pack.rebuildSlices(&slices);
    std.mem.doNotOptimizeAway(&slices);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const parsed = try uuid.UUID.fromString(slices[@as(usize, @intCast(i % pool_size))]);
        sink ^= parsed.bytes[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

// ---- Formatting scenarios --------------------------------------------------

fn buildUuidPool() ![pool_size]uuid.UUID {
    var gen = uuid.Generator.init();
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();
    return pool;
}

fn scenarioToString(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    const pool = try buildUuidPool();
    var buf: [36]u8 = undefined;
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const s = pool[@as(usize, @intCast(i % pool_size))].toString(&buf);
        sink ^= s[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioToStringUpper(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    const pool = try buildUuidPool();
    var buf: [36]u8 = undefined;
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const s = pool[@as(usize, @intCast(i % pool_size))].toStringUpper(&buf);
        sink ^= s[0];
        std.mem.doNotOptimizeAway(&buf);
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioToHex(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    const pool = try buildUuidPool();
    var buf: [32]u8 = undefined;
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const s = pool[@as(usize, @intCast(i % pool_size))].toHex(&buf);
        sink ^= s[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioToURN(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    const pool = try buildUuidPool();
    var buf: [45]u8 = undefined;
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const s = pool[@as(usize, @intCast(i % pool_size))].toURN(&buf);
        sink ^= s[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioToStringAllocPage(_: std.mem.Allocator, _: std.Io) !common.RunResult {
    const alloc = std.heap.page_allocator;
    const pool = try buildUuidPool();
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const s = try pool[@as(usize, @intCast(i % pool_size))].toStringAlloc(alloc);
        defer alloc.free(s);
        sink ^= s[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioToStringAllocArena(_: std.mem.Allocator, _: std.Io) !common.RunResult {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const pool = try buildUuidPool();
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        const s = try pool[@as(usize, @intCast(i % pool_size))].toStringAlloc(alloc);
        sink ^= s[0];
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, &.{});
}

// ---- Comparison scenarios --------------------------------------------------

fn scenarioEql(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var pool_a: [pool_size]uuid.UUID = undefined;
    var pool_b: [pool_size]uuid.UUID = undefined;
    for (&pool_a) |*u| u.* = try gen.newV4();
    for (&pool_b) |*u| u.* = try gen.newV4();
    std.mem.doNotOptimizeAway(&pool_a);
    std.mem.doNotOptimizeAway(&pool_b);
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < fast_iters) : (i += 1) {
        var idx: usize = @intCast(i % pool_size);
        std.mem.doNotOptimizeAway(&idx);
        const result = pool_a[idx].eql(pool_b[idx]);
        sink ^= @intFromBool(result);
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(fast_iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioTimingSafeEql(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    _ = allocator;
    var gen = uuid.Generator.init();
    var pool_a: [pool_size]uuid.UUID = undefined;
    var pool_b: [pool_size]uuid.UUID = undefined;
    for (&pool_a) |*u| u.* = try gen.newV4();
    for (&pool_b) |*u| u.* = try gen.newV4();
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < fast_iters) : (i += 1) {
        var idx: usize = @intCast(i % pool_size);
        std.mem.doNotOptimizeAway(&idx);
        const result = pool_a[idx].timingSafeEql(pool_b[idx]);
        sink ^= @intFromBool(result);
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(fast_iters, start, end, cpu_start, cpu_end, &.{});
}

fn scenarioEqlDifferFirstByte(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    // Short-circuit best case: every comparison differs at byte 0 so a
    // byte-wise `eql` can early-return after a single comparison.
    _ = allocator;
    var gen = uuid.Generator.init();
    var pool_a: [pool_size]uuid.UUID = undefined;
    var pool_b: [pool_size]uuid.UUID = undefined;
    for (&pool_a) |*u| u.* = try gen.newV4();
    for (&pool_b, 0..) |*u, idx| {
        u.* = pool_a[idx];
        u.bytes[0] +%= 1;
    }
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    while (i < fast_iters) : (i += 1) {
        var idx: usize = @intCast(i % pool_size);
        std.mem.doNotOptimizeAway(&idx);
        const result = pool_a[idx].eql(pool_b[idx]);
        sink ^= @intFromBool(result);
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(fast_iters, start, end, cpu_start, cpu_end, &.{});
}
