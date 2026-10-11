// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Multi-thread V7 contention matrix.
//
// For each (thread_count, variant) pair the bench spawns N threads sharing
// one Generator, calls `newV7` 100k times per thread, and reports aggregate
// throughput plus per-thread p50/p95/p99 latency.  The uuids are collected
// into per-thread arrays, merged, sorted by (ms, seq), and scanned for
// duplicates — a correctness witness for PERF-21 (lock-free V7).
//
// Target runtime <= 120s at ReleaseFast.

const std = @import("std");
const uuid = @import("uuid");
const common = @import("common");

const per_thread_iters: usize = 100_000;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try common.parseOutputArg(allocator, init.minimal.args);
    const runs = try common.parseRunsArg(allocator, init.minimal.args);

    // Matrix: (2, 4, 8, 16) × (mutex, lockfree).
    // 16T is the published ceiling; contention on larger hosts is clamped
    // so the bench characterises contention rather than system saturation.
    //
    // INV-01 (docs/PERF_GAP_ANALYSIS.md): contention rows swing >= 20%
    // across independent captures at 2T/4T under the default 7-run /
    // median-of-6 pattern.  Widen to 15 runs / median-of-10 so the sample
    // window covers ~3x the observed per-capture variance.  Cost is ~55s
    // added per full bench-contention invocation (manual / main-gated).
    const contention_runs: usize = 15;
    const specs = [_]common.ScenarioSpec{
        .{ .name = "v7_contention_mutex_2T", .variant = "mutex", .thread_count = 2, .expected_iterations = per_thread_iters * 2, .runFn = runMutex2, .run_count = contention_runs },
        .{ .name = "v7_contention_mutex_4T", .variant = "mutex", .thread_count = 4, .expected_iterations = per_thread_iters * 4, .runFn = runMutex4, .run_count = contention_runs },
        .{ .name = "v7_contention_mutex_8T", .variant = "mutex", .thread_count = 8, .expected_iterations = per_thread_iters * 8, .runFn = runMutex8, .run_count = contention_runs },
        .{ .name = "v7_contention_mutex_16T", .variant = "mutex", .thread_count = 16, .expected_iterations = per_thread_iters * 16, .runFn = runMutex16, .run_count = contention_runs },
        .{ .name = "v7_contention_lockfree_2T", .variant = "lockfree", .thread_count = 2, .expected_iterations = per_thread_iters * 2, .runFn = runLockfree2, .run_count = contention_runs },
        .{ .name = "v7_contention_lockfree_4T", .variant = "lockfree", .thread_count = 4, .expected_iterations = per_thread_iters * 4, .runFn = runLockfree4, .run_count = contention_runs },
        .{ .name = "v7_contention_lockfree_8T", .variant = "lockfree", .thread_count = 8, .expected_iterations = per_thread_iters * 8, .runFn = runLockfree8, .run_count = contention_runs },
        .{ .name = "v7_contention_lockfree_16T", .variant = "lockfree", .thread_count = 16, .expected_iterations = per_thread_iters * 16, .runFn = runLockfree16, .run_count = contention_runs },
    };
    // Scenario buffers go through the general-purpose allocator, not the
    // arena: each 16T run allocates ~77 MiB of UUID/latency buffers that the
    // harness and runContention free, and an arena ignores those frees. With
    // 8 scenarios x 15 runs x `--runs 3` the arena grew past 8 GiB and CI
    // runners OOM-killed the bench. The arena still owns the parsed args.
    try common.runScenariosOpts(std.heap.smp_allocator, init.io, &specs, .{ .output_path = output, .runs = runs });
}

// --------------------------------------------------------------------------
// Thread driver.
// --------------------------------------------------------------------------

const WorkerCtx = struct {
    gen: *uuid.Generator,
    iters: usize,
    // Per-thread owning buffers; caller merges and inspects for duplicates.
    uuids: []uuid.UUID,
    latencies_ns: []u64,
    err: ?anyerror = null,
};

fn worker(ctx: *WorkerCtx) void {
    var i: usize = 0;
    while (i < ctx.iters) : (i += 1) {
        const start = common.nowNs();
        const u = ctx.gen.newV7() catch |e| {
            ctx.err = e;
            return;
        };
        const end = common.nowNs();
        ctx.uuids[i] = u;
        ctx.latencies_ns[i] = end - start;
    }
}

fn runContention(
    allocator: std.mem.Allocator,
    thread_count: usize,
    lockfree: bool,
) !common.RunResult {
    var gen = if (lockfree) uuid.Generator.initOptions(.{ .v7_lockfree = true }) else uuid.Generator.init();

    const per_thread_uuids = try allocator.alloc([]uuid.UUID, thread_count);
    defer allocator.free(per_thread_uuids);
    const per_thread_lat = try allocator.alloc([]u64, thread_count);
    defer allocator.free(per_thread_lat);
    const ctxs = try allocator.alloc(WorkerCtx, thread_count);
    defer allocator.free(ctxs);
    const threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    for (per_thread_uuids) |*p| p.* = try allocator.alloc(uuid.UUID, per_thread_iters);
    for (per_thread_lat) |*p| p.* = try allocator.alloc(u64, per_thread_iters);
    defer for (per_thread_uuids) |p| allocator.free(p);
    defer for (per_thread_lat) |p| allocator.free(p);

    for (ctxs, 0..) |*c, idx| {
        c.* = .{
            .gen = &gen,
            .iters = per_thread_iters,
            .uuids = per_thread_uuids[idx],
            .latencies_ns = per_thread_lat[idx],
        };
    }

    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    for (threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, worker, .{&ctxs[i]});
    }
    for (threads) |t| t.join();
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();

    // Surface per-thread errors (RandomError, InvalidTimestamp) without
    // masking the headline throughput.
    for (ctxs) |c| if (c.err) |e| return e;

    const total_iters = per_thread_iters * thread_count;

    // Merge per-thread latencies into one buffer the harness can summarise.
    const merged_lat = try allocator.alloc(u64, total_iters);
    var offset: usize = 0;
    for (per_thread_lat) |src| {
        @memcpy(merged_lat[offset .. offset + src.len], src);
        offset += src.len;
    }

    // Correctness witness: merge all UUIDs into a flat array, sort, and
    // count duplicates.
    const merged_uuids = try allocator.alloc(uuid.UUID, total_iters);
    defer allocator.free(merged_uuids);
    offset = 0;
    for (per_thread_uuids) |src| {
        @memcpy(merged_uuids[offset .. offset + src.len], src);
        offset += src.len;
    }
    std.sort.heap(uuid.UUID, merged_uuids, {}, struct {
        fn lessThan(_: void, a: uuid.UUID, b: uuid.UUID) bool {
            return std.mem.lessThan(u8, &a.bytes, &b.bytes);
        }
    }.lessThan);
    var duplicates: u64 = 0;
    if (merged_uuids.len > 1) {
        var i: usize = 1;
        while (i < merged_uuids.len) : (i += 1) {
            if (std.mem.eql(u8, &merged_uuids[i].bytes, &merged_uuids[i - 1].bytes)) duplicates += 1;
        }
    }

    return .{
        .wall_ns = end - start,
        .cpu_ns = if (cpu_end > cpu_start) cpu_end - cpu_start else end - start,
        .iterations = total_iters,
        .latencies_ns = merged_lat,
        .lockfree_fallbacks = if (lockfree) gen.lockfreeFallbackCount() else 0,
        .duplicate_uuids = duplicates,
    };
}

// The harness takes bare function pointers so each (thread_count, variant)
// pair is its own entry; closures would require a vtable.  Keep each
// shim tiny so compile-time cost stays negligible.
fn runMutex2(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    return runContention(allocator, 2, false);
}
fn runMutex4(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    return runContention(allocator, 4, false);
}
fn runMutex8(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    return runContention(allocator, 8, false);
}
fn runMutex16(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    return runContention(allocator, 16, false);
}
fn runLockfree2(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    return runContention(allocator, 2, true);
}
fn runLockfree4(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    return runContention(allocator, 4, true);
}
fn runLockfree8(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    return runContention(allocator, 8, true);
}
fn runLockfree16(allocator: std.mem.Allocator, _: std.Io) !common.RunResult {
    return runContention(allocator, 16, true);
}
