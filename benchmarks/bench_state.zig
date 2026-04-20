// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// saveState / loadState throughput — v2 (legacy, no HMAC) and v3 (HMAC
// authenticated).  Bounded by disk I/O, so iterations are 10k each.  The
// wrong-key scenario exercises the timing-safe HMAC reject path.

const std = @import("std");
const builtin = @import("builtin");
const uuid = @import("uuid");
const common = @import("common");

const iters: usize = 10_000;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try common.parseOutputArg(allocator, init.minimal.args);
    const runs = try common.parseRunsArg(allocator, init.minimal.args);

    const specs = [_]common.ScenarioSpec{
        .{ .name = "saveState_v2", .variant = "v2", .runFn = runSaveV2 },
        .{ .name = "saveState_v3_hmac", .variant = "v3_hmac", .runFn = runSaveV3 },
        .{ .name = "loadState_v2", .variant = "v2", .runFn = runLoadV2 },
        .{ .name = "loadState_v3_hmac", .variant = "v3_hmac", .runFn = runLoadV3 },
        .{ .name = "loadState_v3_wrong_key", .variant = "v3_hmac", .runFn = runLoadV3WrongKey },
    };
    try common.runScenariosOpts(allocator, init.io, &specs, .{ .output_path = output, .runs = runs });
}

// --------------------------------------------------------------------------
// Helpers.
// --------------------------------------------------------------------------

/// Build a PID-qualified path under `/tmp` (Linux) or `.` (portable fallback).
/// We avoid `std.testing.tmpDir` because it is `@compileError("not testing")`
/// in non-test binaries, and `std.Io.Dir.makeOpenPath` over `tmpDir` needs
/// the absolute path that loadState/saveState require.
fn tmpPath(buf: []u8, tag: []const u8) ![]const u8 {
    const pid: usize = if (builtin.os.tag == .linux)
        @intCast(std.os.linux.getpid())
    else
        0;
    const base = if (builtin.os.tag == .linux) "/tmp" else ".";
    const ns = common.nowNs();
    return std.fmt.bufPrint(buf, "{s}/uuid-bench-{s}-{d}-{d}.bin", .{ base, tag, pid, ns });
}

/// Run one of (save v2, save v3, load v2, load v3, load v3 wrong key) and
/// report throughput.  Each variant uses its own tmpDir so the bench can be
/// run concurrently with other state tests.
fn runStateBench(
    allocator: std.mem.Allocator,
    io: std.Io,
    comptime mode: enum { save_v2, save_v3, load_v2, load_v3, load_v3_wrong_key },
) !common.RunResult {
    var path_buf: [std.fs.max_path_bytes + 32]u8 = undefined;
    const path = try tmpPath(&path_buf, @tagName(mode));
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

    const key_a: [32]u8 = [_]u8{0xA5} ** 32;
    const key_b: [32]u8 = [_]u8{0x5A} ** 32;

    const is_load = switch (mode) {
        .load_v2, .load_v3, .load_v3_wrong_key => true,
        else => false,
    };

    // Seed generator. load* modes need a persisted file before the timed
    // loop starts, so we write one up-front.
    var seed_gen = switch (mode) {
        .save_v2, .load_v2 => uuid.Generator.init(),
        .save_v3, .load_v3, .load_v3_wrong_key => uuid.Generator.initOptions(.{ .state_mac_key = key_a }),
    };
    // Put a V7 in flight so the persisted state has non-default last_ms / mono_seq.
    _ = try seed_gen.newV7();
    if (is_load) try seed_gen.saveState(path);

    const latencies = try allocator.alloc(u64, iters);

    var sink: u8 = 0;
    const start = common.nowNs();
    const cpu_start = try common.processCpuTimeNs();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const t0 = common.nowNs();
        switch (mode) {
            .save_v2 => {
                var gen = uuid.Generator.init();
                _ = try gen.newV7();
                try gen.saveState(path);
            },
            .save_v3 => {
                var gen = uuid.Generator.initOptions(.{ .state_mac_key = key_a });
                _ = try gen.newV7();
                try gen.saveState(path);
            },
            .load_v2 => {
                var gen = uuid.Generator.init();
                try gen.loadState(path);
                // last_v1_ts is u60 — truncating keeps the bench loop observable.
                sink ^= @as(u8, @truncate(gen.v1v6.last_v1_ts));
            },
            .load_v3 => {
                var gen = uuid.Generator.initOptions(.{ .state_mac_key = key_a });
                try gen.loadState(path);
                sink ^= @as(u8, @truncate(gen.v1v6.last_v1_ts));
            },
            .load_v3_wrong_key => {
                var gen = uuid.Generator.initOptions(.{ .state_mac_key = key_b });
                // The timing-safe HMAC comparison runs fully before the
                // Error.StateMacMismatch is returned — that's the cost we
                // want to measure.
                gen.loadState(path) catch |e| {
                    if (e != uuid.Error.StateMacMismatch) return e;
                    sink +%= 1;
                };
            },
        }
        const t1 = common.nowNs();
        latencies[i] = t1 - t0;
    }
    const cpu_end = try common.processCpuTimeNs();
    const end = common.nowNs();
    std.mem.doNotOptimizeAway(sink);

    return .{
        .wall_ns = end - start,
        .cpu_ns = if (cpu_end > cpu_start) cpu_end - cpu_start else end - start,
        .iterations = iters,
        .latencies_ns = latencies,
    };
}

fn runSaveV2(allocator: std.mem.Allocator, io: std.Io) !common.RunResult {
    return runStateBench(allocator, io, .save_v2);
}
fn runSaveV3(allocator: std.mem.Allocator, io: std.Io) !common.RunResult {
    return runStateBench(allocator, io, .save_v3);
}
fn runLoadV2(allocator: std.mem.Allocator, io: std.Io) !common.RunResult {
    return runStateBench(allocator, io, .load_v2);
}
fn runLoadV3(allocator: std.mem.Allocator, io: std.Io) !common.RunResult {
    return runStateBench(allocator, io, .load_v3);
}
fn runLoadV3WrongKey(allocator: std.mem.Allocator, io: std.Io) !common.RunResult {
    return runStateBench(allocator, io, .load_v3_wrong_key);
}
