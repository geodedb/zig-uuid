// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Micro-benchmark: fromString latency distribution.  10M iterations per
// scenario; every iteration's wall time is recorded so the p99 is anchored
// on 100k samples (10M iters / sample-every-100).

const std = @import("std");
const uuid = @import("uuid");
const common = @import("common");

const total_iters: u64 = 10_000_000;
const sample_every: u64 = 100; // record 1-in-100 latency samples
const pool_size: usize = 256;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try common.parseOutputArg(allocator, init.minimal.args);

    const specs = [_]common.ScenarioSpec{
        .{ .name = "parse_canonical_latency", .expected_iterations = total_iters, .runFn = runCanonical },
        .{ .name = "parse_urn_latency", .expected_iterations = total_iters, .runFn = runURN },
        .{ .name = "parse_hash_latency", .expected_iterations = total_iters, .runFn = runHash },
        .{ .name = "parse_invalid_reject", .expected_iterations = total_iters, .runFn = runInvalid },
    };
    try common.runScenarios(allocator, init.io, &specs, output);
}

fn buildPool(
    allocator: std.mem.Allocator,
    comptime L: usize,
    comptime formatter: fn (uuid.UUID, *[L]u8) []u8,
) ![pool_size][]const u8 {
    var gen = uuid.Generator.init();
    const storage = try allocator.alloc([L]u8, pool_size);
    var slices: [pool_size][]const u8 = undefined;
    for (storage, 0..) |*buf, j| {
        const u = try gen.newV4();
        slices[j] = formatter(u, buf);
    }
    return slices;
}

fn runCanonical(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    const slices = try buildPool(allocator, 36, uuid.UUID.toString);
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(total_iters / sample_every)));
    return parseLoop(slices, latencies);
}

fn runURN(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    const slices = try buildPool(allocator, 45, uuid.UUID.toURN);
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(total_iters / sample_every)));
    return parseLoop(slices, latencies);
}

fn runHash(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    const slices = try buildPool(allocator, 32, uuid.UUID.toHex);
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(total_iters / sample_every)));
    return parseLoop(slices, latencies);
}

fn runInvalid(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    // Pool of malformed inputs: half wrong-length (InvalidLength), half
    // non-hex (InvalidFormat).  The parser has to reach the full length
    // check before InvalidFormat can be surfaced, so both branches are
    // exercised.
    const short = "abcdef0123456789abcdef"; // 22 chars — InvalidLength
    const nonhex = "12345678-1234-1234-1234-ZZZZZZZZZZZZ"; // 36 chars — InvalidFormat
    const slices = try allocator.alloc([]const u8, pool_size);
    for (slices, 0..) |*s, j| {
        s.* = if (j % 2 == 0) short else nonhex;
    }
    const latencies = try allocator.alloc(u64, @as(usize, @intCast(total_iters / sample_every)));

    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < total_iters) : (i += 1) {
        const t0 = common.nowNs();
        const res = uuid.UUID.fromString(slices[@as(usize, @intCast(i % pool_size))]);
        const t1 = common.nowNs();
        if (res) |u| sink ^= u.bytes[0] else |_| sink +%= 1;
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

fn parseLoop(slices: [pool_size][]const u8, latencies: []u64) common.RunResult {
    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = common.processCpuTimeNs() catch 0;
    var i: u64 = 0;
    var lat_idx: usize = 0;
    while (i < total_iters) : (i += 1) {
        const t0 = common.nowNs();
        const parsed = uuid.UUID.fromString(slices[@as(usize, @intCast(i % pool_size))]) catch unreachable;
        const t1 = common.nowNs();
        sink ^= parsed.bytes[0];
        if (i % sample_every == 0 and lat_idx < latencies.len) {
            latencies[lat_idx] = t1 - t0;
            lat_idx += 1;
        }
    }
    const cpu_end = common.processCpuTimeNs() catch 0;
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);
    return common.timedResult(total_iters, start, end, cpu_start, cpu_end, latencies);
}
