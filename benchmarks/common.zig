// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Shared benchmark harness for the uuid repo.  Modelled after the sibling
// thread-pool benchmark harness so result JSONs can be compared by the same
// regression tooling.  The schema diverges only where UUID-specific fields
// are needed (e.g. `lockfree_fallbacks`, `duplicate_uuids`).
//
// Conventions:
//
//   * Each scenario runs 7 iterations; the first is discarded as warm-up
//     (cold icache / branch predictor / page faults) and the median of the
//     remaining 6 is recorded with stddev.  `compare.zig` uses the stddev
//     as a per-row noise floor on top of a 15% hard regression threshold.
//
//   * All UUID objects observed by a scenario must be XOR'd into a `sink`
//     byte so LLVM cannot DCE the loop body at ReleaseFast.  Add `keep(x)`
//     wrappers around allocations when a return value is otherwise unused.
//
//   * Latency distributions are collected per-iteration when the spec
//     requests them; for 100M-iter scenarios (`fast_iters`) only aggregate
//     throughput is recorded to keep the histogram memory bounded.

const std = @import("std");
const builtin = @import("builtin");

// --------------------------------------------------------------------------
// Shared result schema — kept in sync with compare.zig and the JSON files in
// benchmarks/results/.
// --------------------------------------------------------------------------

pub const ResultRow = struct {
    // Environment provenance.
    git_sha: []const u8,
    run_timestamp_unix_s: i64,
    zig_version: []const u8,
    os: []const u8,
    arch: []const u8,
    cpu: []const u8,

    // Scenario identity (matched on by compare.zig).
    scenario_name: []const u8,
    variant: []const u8,
    thread_count: usize,
    iteration_count: u64,
    allocator_kind: []const u8,

    // Throughput + stddev (over the 6 non-warmup samples).
    throughput_ops_per_sec: f64,
    throughput_stddev_ops_per_sec: f64 = 0,

    // Per-op latency distribution.  For 100M-iter scenarios these are 0 so
    // the per-iteration record overhead does not swamp the measured cost.
    latency_p50_ns: u64,
    latency_p95_ns: u64,
    latency_p99_ns: u64,
    latency_min_ns: u64,
    latency_max_ns: u64,

    // Wall + CPU time (wall is authoritative for ops/s).
    cpu_time_ns: u64,
    wall_time_ns: u64,

    // Memory (optional — zero for stack-only scenarios).
    alloc_count: u64 = 0,
    alloc_bytes: u64 = 0,
    rss_current_bytes: u64,
    rss_peak_bytes: u64,
    rss_delta_after_warmup_bytes: i64,

    // UUID-specific signals.
    lockfree_fallbacks: u64 = 0,
    duplicate_uuids: u64 = 0,
};

pub const ResultDocument = struct {
    generated_at_unix_s: i64,
    rows: []ResultRow,
};

// --------------------------------------------------------------------------
// Latency summarisation.
// --------------------------------------------------------------------------

pub const LatencySummary = struct {
    count: usize,
    min_ns: u64,
    mean_ns: u64,
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    max_ns: u64,
};

/// Sort the buffer in place (ascending) and return p50/p95/p99/min/max.
pub fn summarizeLatencies(values: []u64) LatencySummary {
    if (values.len == 0) return .{
        .count = 0,
        .min_ns = 0,
        .mean_ns = 0,
        .p50_ns = 0,
        .p95_ns = 0,
        .p99_ns = 0,
        .max_ns = 0,
    };
    std.sort.heap(u64, values, {}, comptime std.sort.asc(u64));
    return .{
        .count = values.len,
        .min_ns = values[0],
        .mean_ns = meanU64(values),
        .p50_ns = percentile(values, 50),
        .p95_ns = percentile(values, 95),
        .p99_ns = percentile(values, 99),
        .max_ns = values[values.len - 1],
    };
}

fn meanU64(values: []const u64) u64 {
    if (values.len == 0) return 0;
    var total: u128 = 0;
    for (values) |v| total += v;
    return @as(u64, @intCast(total / values.len));
}

fn percentile(values: []const u64, pct: u8) u64 {
    if (values.len == 0) return 0;
    const idx = @min((values.len - 1) * pct / 100, values.len - 1);
    return values[idx];
}

// --------------------------------------------------------------------------
// Environment readers.
// --------------------------------------------------------------------------

/// Return the current HEAD SHA, or the string "unknown" on failure. Caller
/// owns the returned memory.
pub fn gitSha(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "git", "rev-parse", "HEAD" },
        .stdout_limit = .limited(128),
        .stderr_limit = .limited(512),
    }) catch return allocator.dupe(u8, "unknown");
    defer allocator.free(result.stderr);
    const exited = switch (result.term) {
        .exited => |code| code,
        else => 1,
    };
    if (exited != 0) {
        allocator.free(result.stdout);
        return allocator.dupe(u8, "unknown");
    }
    defer allocator.free(result.stdout);
    return allocator.dupe(u8, std.mem.trim(u8, result.stdout, " \r\n\t"));
}

/// Return process utime + stime in nanoseconds (Linux-only; other OSes fall
/// back to wall time).
pub fn processCpuTimeNs() !u64 {
    if (builtin.os.tag == .linux) {
        const posix = std.posix;
        const fd = try posix.openat(posix.AT.FDCWD, "/proc/self/stat", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
        defer _ = std.os.linux.close(fd);
        var buffer: [4096]u8 = undefined;
        var total: usize = 0;
        while (total < buffer.len) {
            const n = try posix.read(fd, buffer[total..]);
            if (n == 0) break;
            total += n;
        }
        const contents = buffer[0..total];
        var it = std.mem.tokenizeScalar(u8, contents, ' ');
        var field_index: usize = 1;
        var utime_ticks: u64 = 0;
        var stime_ticks: u64 = 0;
        while (it.next()) |field| : (field_index += 1) {
            if (field_index == 14) utime_ticks = std.fmt.parseInt(u64, field, 10) catch 0;
            if (field_index == 15) {
                stime_ticks = std.fmt.parseInt(u64, field, 10) catch 0;
                break;
            }
        }
        return (utime_ticks + stime_ticks) * (std.time.ns_per_s / 100);
    }
    return nowNs();
}

pub const MemorySnapshot = struct {
    rss_current_bytes: u64,
    rss_peak_bytes: u64,
};

/// Read /proc/self/status and return VmRSS + VmHWM (Linux only; zeroes on
/// other OSes).
pub fn memorySnapshot() MemorySnapshot {
    if (builtin.os.tag != .linux) return .{ .rss_current_bytes = 0, .rss_peak_bytes = 0 };
    const posix = std.posix;
    const fd = posix.openat(posix.AT.FDCWD, "/proc/self/status", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0) catch return .{ .rss_current_bytes = 0, .rss_peak_bytes = 0 };
    defer _ = std.os.linux.close(fd);
    var buffer: [8192]u8 = undefined;
    var total: usize = 0;
    while (total < buffer.len) {
        const n = posix.read(fd, buffer[total..]) catch break;
        if (n == 0) break;
        total += n;
    }
    const contents = buffer[0..total];

    var rss_kb: u64 = 0;
    var hwm_kb: u64 = 0;
    var line_it = std.mem.splitScalar(u8, contents, '\n');
    while (line_it.next()) |line| {
        if (std.mem.startsWith(u8, line, "VmRSS:")) {
            rss_kb = parseKb(line);
        } else if (std.mem.startsWith(u8, line, "VmHWM:")) {
            hwm_kb = parseKb(line);
        }
    }
    return .{
        .rss_current_bytes = rss_kb * 1024,
        .rss_peak_bytes = hwm_kb * 1024,
    };
}

fn parseKb(line: []const u8) u64 {
    // Format: "VmRSS:\t   12345 kB"
    var it = std.mem.tokenizeAny(u8, line, " \t");
    _ = it.next(); // label
    const number = it.next() orelse return 0;
    return std.fmt.parseInt(u64, number, 10) catch 0;
}

/// Monotonic-since-epoch nanoseconds.  Falls back to real time because the
/// uuid repo does not export a dedicated clock shim.
pub fn nowNs() u64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.Timestamp.now(io, .real).raw.nanoseconds;
    return if (ts < 0) 0 else @as(u64, @intCast(ts));
}

// --------------------------------------------------------------------------
// CLI parsing — every bench executable accepts `--output <path>` to write a
// JSON document instead of stdout.
// --------------------------------------------------------------------------

pub fn parseOutputArg(allocator: std.mem.Allocator, args: std.process.Args) !?[]const u8 {
    const argv = try args.toSlice(allocator);
    var idx: usize = 0;
    while (idx + 1 < argv.len) : (idx += 1) {
        if (std.mem.eql(u8, argv[idx], "--output")) {
            return try allocator.dupe(u8, argv[idx + 1]);
        }
    }
    return null;
}

// --------------------------------------------------------------------------
// Scenario harness.  A scenario is a function that returns a RunResult;
// `runScenarios` wraps it in the 7-run / median-of-6 / stddev pattern and
// records memory deltas between the warmup run and the measured run.
// --------------------------------------------------------------------------

pub const RunResult = struct {
    // Wall + CPU timing.
    wall_ns: u64,
    cpu_ns: u64,

    // Iteration count actually executed.
    iterations: u64,

    // Latency buffer — caller owns; `runScenarios` will sort in place and
    // free. Pass an empty slice when only throughput is recorded.
    latencies_ns: []u64 = &.{},

    // UUID-specific signals.
    lockfree_fallbacks: u64 = 0,
    duplicate_uuids: u64 = 0,

    // Optional memory signals (saveState/loadState scenarios fill these).
    alloc_count: u64 = 0,
    alloc_bytes: u64 = 0,
};

pub const ScenarioSpec = struct {
    name: []const u8,
    variant: []const u8 = "default",
    thread_count: usize = 1,
    allocator_kind: []const u8 = "stack",
    /// When non-zero, forces `runScenarios` to record `iteration_count` from
    /// this field rather than from `RunResult.iterations`.
    expected_iterations: u64 = 0,
    runFn: *const fn (std.mem.Allocator, std.Io) anyerror!RunResult,
};

pub fn runScenarios(allocator: std.mem.Allocator, io: std.Io, specs: []const ScenarioSpec, output_path: ?[]const u8) !void {
    var rows: std.ArrayList(ResultRow) = .empty;
    defer {
        for (rows.items) |row| freeRow(allocator, row);
        rows.deinit(allocator);
    }

    for (specs) |spec| {
        const row = try runOneScenario(allocator, io, spec);
        try rows.append(allocator, row);
    }

    const document = ResultDocument{
        .generated_at_unix_s = @as(i64, @intCast(@divTrunc(nowNs(), std.time.ns_per_s))),
        .rows = try rows.toOwnedSlice(allocator),
    };
    defer allocator.free(document.rows);

    try writeDocument(allocator, io, document, output_path);
    for (document.rows) |row| freeRow(allocator, row);
}

/// Expose for external tools (micro benches) that compose a single
/// ResultDocument across several one-off scenarios.
pub fn writeDocument(allocator: std.mem.Allocator, io: std.Io, document: ResultDocument, output_path: ?[]const u8) !void {
    if (output_path) |path| {
        var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
        defer file.close(io);
        const json = try std.json.Stringify.valueAlloc(allocator, document, .{ .whitespace = .indent_2 });
        defer allocator.free(json);
        try file.writeStreamingAll(io, json);
        try file.writeStreamingAll(io, "\n");
    } else {
        const json = try std.json.Stringify.valueAlloc(allocator, document, .{ .whitespace = .indent_2 });
        defer allocator.free(json);
        const stdout = std.Io.File.stdout();
        try stdout.writeStreamingAll(io, json);
        try stdout.writeStreamingAll(io, "\n");
    }
}

fn freeRow(allocator: std.mem.Allocator, row: ResultRow) void {
    allocator.free(row.git_sha);
    allocator.free(row.cpu);
}

fn runOneScenario(allocator: std.mem.Allocator, io: std.Io, spec: ScenarioSpec) !ResultRow {
    const RUN_COUNT: usize = 7;
    const WARMUP_DISCARD: usize = 1;
    const SAMPLE_COUNT: usize = RUN_COUNT - WARMUP_DISCARD;

    var results: [RUN_COUNT]InternalRow = undefined;
    var mem_after_warmup: MemorySnapshot = undefined;

    for (&results, 0..) |*r, run_idx| {
        const res = try spec.runFn(allocator, io);
        if (run_idx == 0) mem_after_warmup = memorySnapshot();
        r.* = .{
            .result = res,
            .throughput = opsPerSec(res.iterations, res.wall_ns),
        };
    }

    // Free discarded warmup run's latency buffer.
    for (results[0..WARMUP_DISCARD]) |r| {
        allocator.free(r.result.latencies_ns);
    }

    // Sort the 6 measured samples by throughput so we can take the median
    // and compute stddev.
    const samples = results[WARMUP_DISCARD..];
    std.sort.heap(InternalRow, samples, {}, struct {
        fn lessThan(_: void, a: InternalRow, b: InternalRow) bool {
            return a.throughput < b.throughput;
        }
    }.lessThan);

    const median = samples[SAMPLE_COUNT / 2];
    const median_throughput = median.throughput;

    var sum_sq: f64 = 0;
    for (samples) |s| {
        const d = s.throughput - median_throughput;
        sum_sq += d * d;
    }
    const stddev = std.math.sqrt(sum_sq / @as(f64, @floatFromInt(SAMPLE_COUNT)));

    // Free every non-median sample's latency buffer; we only summarise the
    // median run's distribution.
    for (samples, 0..) |r, idx| {
        if (idx == SAMPLE_COUNT / 2) continue;
        allocator.free(r.result.latencies_ns);
    }

    const latency_buf = median.result.latencies_ns;
    defer allocator.free(latency_buf);

    const summary = summarizeLatencies(latency_buf);
    const mem_after = memorySnapshot();
    const git = try gitSha(allocator, io);
    const cpu_name = try allocator.dupe(u8, @tagName(builtin.cpu.arch));
    const iter_count = if (spec.expected_iterations != 0) spec.expected_iterations else median.result.iterations;

    return .{
        .git_sha = git,
        .run_timestamp_unix_s = @as(i64, @intCast(@divTrunc(nowNs(), std.time.ns_per_s))),
        .zig_version = builtin.zig_version_string,
        .os = @tagName(builtin.os.tag),
        .arch = @tagName(builtin.cpu.arch),
        .cpu = cpu_name,
        .scenario_name = spec.name,
        .variant = spec.variant,
        .thread_count = spec.thread_count,
        .iteration_count = iter_count,
        .allocator_kind = spec.allocator_kind,
        .throughput_ops_per_sec = median_throughput,
        .throughput_stddev_ops_per_sec = stddev,
        .latency_p50_ns = summary.p50_ns,
        .latency_p95_ns = summary.p95_ns,
        .latency_p99_ns = summary.p99_ns,
        .latency_min_ns = summary.min_ns,
        .latency_max_ns = summary.max_ns,
        .cpu_time_ns = median.result.cpu_ns,
        .wall_time_ns = median.result.wall_ns,
        .alloc_count = median.result.alloc_count,
        .alloc_bytes = median.result.alloc_bytes,
        .rss_current_bytes = mem_after.rss_current_bytes,
        .rss_peak_bytes = mem_after.rss_peak_bytes,
        .rss_delta_after_warmup_bytes = @as(i64, @intCast(mem_after.rss_current_bytes)) - @as(i64, @intCast(mem_after_warmup.rss_current_bytes)),
        .lockfree_fallbacks = median.result.lockfree_fallbacks,
        .duplicate_uuids = median.result.duplicate_uuids,
    };
}

const InternalRow = struct {
    result: RunResult,
    throughput: f64,
};

pub fn opsPerSec(iterations: u64, wall_ns: u64) f64 {
    if (wall_ns == 0) return 0;
    const iters_f = @as(f64, @floatFromInt(iterations));
    const wall_s = @as(f64, @floatFromInt(wall_ns)) / @as(f64, std.time.ns_per_s);
    return iters_f / wall_s;
}

// --------------------------------------------------------------------------
// Utilities reused across bench executables.
// --------------------------------------------------------------------------

/// Return a RunResult built from `start_ns`, `end_ns`, iteration count, and
/// an owned latency buffer.
pub fn timedResult(
    iterations: u64,
    start_ns: u64,
    end_ns: u64,
    cpu_start_ns: u64,
    cpu_end_ns: u64,
    latencies_ns: []u64,
) RunResult {
    const cpu_ns = if (cpu_end_ns > cpu_start_ns) cpu_end_ns - cpu_start_ns else end_ns - start_ns;
    return .{
        .wall_ns = end_ns - start_ns,
        .cpu_ns = cpu_ns,
        .iterations = iterations,
        .latencies_ns = latencies_ns,
    };
}

// --------------------------------------------------------------------------
// Tests.
// --------------------------------------------------------------------------

test "summarizeLatencies returns ordered quantiles" {
    var buf = [_]u64{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 };
    const s = summarizeLatencies(buf[0..]);
    try std.testing.expectEqual(@as(usize, 10), s.count);
    try std.testing.expectEqual(@as(u64, 10), s.min_ns);
    try std.testing.expectEqual(@as(u64, 100), s.max_ns);
    try std.testing.expectEqual(@as(u64, 50), s.p50_ns);
    try std.testing.expectEqual(@as(u64, 90), s.p95_ns);
    try std.testing.expectEqual(@as(u64, 90), s.p99_ns);
    try std.testing.expect(s.mean_ns > 0);
}

test "summarizeLatencies handles empty input" {
    var buf = [_]u64{};
    const s = summarizeLatencies(buf[0..]);
    try std.testing.expectEqual(@as(usize, 0), s.count);
    try std.testing.expectEqual(@as(u64, 0), s.p50_ns);
    try std.testing.expectEqual(@as(u64, 0), s.max_ns);
}

test "summarizeLatencies sorts in place" {
    var buf = [_]u64{ 50, 20, 30, 10, 40 };
    _ = summarizeLatencies(buf[0..]);
    try std.testing.expectEqual(@as(u64, 10), buf[0]);
    try std.testing.expectEqual(@as(u64, 50), buf[4]);
}

test "opsPerSec basic math" {
    try std.testing.expectApproxEqAbs(@as(f64, 1_000_000.0), opsPerSec(1000, 1_000_000), 0.001);
    try std.testing.expectEqual(@as(f64, 0), opsPerSec(1, 0));
}

test "memorySnapshot returns non-negative values" {
    const snap = memorySnapshot();
    if (builtin.os.tag == .linux) {
        try std.testing.expect(snap.rss_current_bytes > 0);
        try std.testing.expect(snap.rss_peak_bytes >= snap.rss_current_bytes);
    }
}

test "nowNs is monotonic under consecutive reads" {
    const a = nowNs();
    const b = nowNs();
    try std.testing.expect(b >= a);
}
