// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Micro-benchmark: toString / toHex / toURN throughput + latency.  5M
// iterations each (these are sub-30-ns ops, so throughput is the headline
// number).

const std = @import("std");
const uuid = @import("uuid");
const common = @import("common");

const total_iters: u64 = 5_000_000;
const sample_every: u64 = 50;
const pool_size: usize = 256;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try common.parseOutputArg(allocator, init.minimal.args);

    const specs = [_]common.ScenarioSpec{
        .{ .name = "toString_lower_latency", .expected_iterations = total_iters, .runFn = runToString },
        .{ .name = "toHex_latency", .expected_iterations = total_iters, .runFn = runToHex },
        .{ .name = "toURN_latency", .expected_iterations = total_iters, .runFn = runToURN },
    };
    try common.runScenarios(allocator, init.io, &specs, output);
}

fn buildPool() ![pool_size]uuid.UUID {
    var gen = uuid.Generator.init();
    var pool: [pool_size]uuid.UUID = undefined;
    for (&pool) |*u| u.* = try gen.newV4();
    return pool;
}

fn runToString(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    const pool = try buildPool();
    var buf: [36]u8 = undefined;
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(total_iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < total_iters) : (i += 1) {
        const t0 = common.nowNs();
        const s = pool[@as(usize, @intCast(i % pool_size))].toString(&buf);
        const t1 = common.nowNs();
        sink ^= s[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(total_iters, start, end, cpu_start, cpu_end, latencies);
}

fn runToHex(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    const pool = try buildPool();
    var buf: [32]u8 = undefined;
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(total_iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < total_iters) : (i += 1) {
        const t0 = common.nowNs();
        const s = pool[@as(usize, @intCast(i % pool_size))].toHex(&buf);
        const t1 = common.nowNs();
        sink ^= s[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(total_iters, start, end, cpu_start, cpu_end, latencies);
}

fn runToURN(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    const pool = try buildPool();
    var buf: [45]u8 = undefined;
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(total_iters / sample_every)));
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < total_iters) : (i += 1) {
        const t0 = common.nowNs();
        const s = pool[@as(usize, @intCast(i % pool_size))].toURN(&buf);
        const t1 = common.nowNs();
        sink ^= s[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(total_iters, start, end, cpu_start, cpu_end, latencies);
}
