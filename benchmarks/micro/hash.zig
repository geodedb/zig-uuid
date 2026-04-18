// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Micro-benchmark: V3 / V5 hash cost.  Compares naive per-call newV3/newV5
// against the prehashed `initV3Namespace().name()` / `initV5Namespace().name()`
// path (PERF-30).  Also covers short (8-byte) vs. long (256-byte) names so
// the constant-time namespace re-hash savings show up distinctly from the
// variable-length name hash.

const std = @import("std");
const uuid = @import("uuid");
const common = @import("common");

const iters: u64 = 1_000_000;
const sample_every: u64 = 100;
const pool_size: usize = 256;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try common.parseOutputArg(allocator, init.minimal.args);

    const specs = [_]common.ScenarioSpec{
        .{ .name = "v3_dns_short_latency", .expected_iterations = iters, .runFn = runV3Short },
        .{ .name = "v3_dns_long_latency", .expected_iterations = iters, .runFn = runV3Long },
        .{ .name = "v5_dns_short_latency", .expected_iterations = iters, .runFn = runV5Short },
        .{ .name = "v5_dns_long_latency", .expected_iterations = iters, .runFn = runV5Long },
        .{ .name = "v3_prehashed_short_latency", .variant = "prehashed", .expected_iterations = iters, .runFn = runV3PrehashedShort },
        .{ .name = "v5_prehashed_short_latency", .variant = "prehashed", .expected_iterations = iters, .runFn = runV5PrehashedShort },
        .{ .name = "v3_prehashed_long_latency", .variant = "prehashed", .expected_iterations = iters, .runFn = runV3PrehashedLong },
        .{ .name = "v5_prehashed_long_latency", .variant = "prehashed", .expected_iterations = iters, .runFn = runV5PrehashedLong },
    };
    try common.runScenarios(allocator, init.io, &specs, output);
}

// --------------------------------------------------------------------------
// Name pools.  The short pool uses 8-byte names; the long pool uses 256
// bytes so the name hash dominates.
// --------------------------------------------------------------------------

fn buildShortNames() [pool_size][8]u8 {
    var out: [pool_size][8]u8 = undefined;
    for (&out, 0..) |*n, i| std.mem.writeInt(u64, n, @as(u64, i), .little);
    return out;
}

fn buildLongNames(allocator: std.mem.Allocator) ![pool_size][]u8 {
    var out: [pool_size][]u8 = undefined;
    for (&out, 0..) |*n, i| {
        const buf = try allocator.alloc(u8, 256);
        @memset(buf, 0);
        std.mem.writeInt(u64, buf[0..8], @as(u64, i), .little);
        // Fill the tail with a varying pattern so hashers cannot shortcut
        // on repeated blocks.
        var j: usize = 8;
        while (j < buf.len) : (j += 1) buf[j] = @as(u8, @truncate(i ^ j));
        n.* = buf;
    }
    return out;
}

// --------------------------------------------------------------------------
// Scenarios.
// --------------------------------------------------------------------------

fn runV3Short(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    var gen = uuid.Generator.init();
    const names = buildShortNames();
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        const u = gen.newV3(uuid.namespace_dns, &names[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        sink ^= u.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, latencies);
}

fn runV5Short(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    var gen = uuid.Generator.init();
    const names = buildShortNames();
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        const u = gen.newV5(uuid.namespace_dns, &names[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        sink ^= u.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, latencies);
}

fn runV3Long(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    var gen = uuid.Generator.init();
    const names = try buildLongNames(allocator);
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        const u = gen.newV3(uuid.namespace_dns, names[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        sink ^= u.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, latencies);
}

fn runV5Long(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    var gen = uuid.Generator.init();
    const names = try buildLongNames(allocator);
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        const u = gen.newV5(uuid.namespace_dns, names[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        sink ^= u.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, latencies);
}

fn runV3PrehashedShort(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    var gen = uuid.Generator.init();
    const pre = gen.initV3Namespace(uuid.namespace_dns);
    const names = buildShortNames();
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        const u = pre.name(&names[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        sink ^= u.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, latencies);
}

fn runV5PrehashedShort(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    var gen = uuid.Generator.init();
    const pre = gen.initV5Namespace(uuid.namespace_dns);
    const names = buildShortNames();
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        const u = pre.name(&names[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        sink ^= u.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, latencies);
}

// Long-name prehashed variants.  The naive long-name path (`runV3Long`)
// re-absorbs the 16-byte namespace on every call; the prehashed path
// amortises it.  With a 256-byte name the hash core dominates, so the
// gap vs naive should be smaller than the short-name case — we report
// both so the "when is prehashed worth it?" decision is data-driven.
fn runV3PrehashedLong(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    var gen = uuid.Generator.init();
    const pre = gen.initV3Namespace(uuid.namespace_dns);
    const names = try buildLongNames(allocator);
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        const u = pre.name(names[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        sink ^= u.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, latencies);
}

fn runV5PrehashedLong(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    var gen = uuid.Generator.init();
    const pre = gen.initV5Namespace(uuid.namespace_dns);
    const names = try buildLongNames(allocator);
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        const u = pre.name(names[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        sink ^= u.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(iters, start, end, cpu_start, cpu_end, latencies);
}
