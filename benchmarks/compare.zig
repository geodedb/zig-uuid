// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Regression gate for the uuid benchmark suite.  Reads one or more JSON
// result documents (baseline + candidate) and fails when any row in the
// candidate has throughput below `baseline * (1 - threshold)`.  The
// threshold defaults to 0.15 (matches PERF-26); pass `--threshold 0.10`
// to tighten.  Per-row stddev is used as a noise floor on top of the
// hard threshold: if the baseline stddev is greater than 5 % of the
// baseline throughput, the effective gate for that row becomes
// `max(threshold, 3*stddev_pct/100)`.
//
// Rows are matched on (scenario_name, variant, thread_count).
//
// Modes:
//   Single-pair mode (CI / dev):
//     bench-compare --baseline <file> --candidate <file> [--threshold 0.15]
//   Walker mode (full suite post-`zig build bench-all`):
//     bench-compare --all [--dir benchmarks/results] [--threshold 0.15]
//     Discovers every `baseline*.json` under --dir, pairs each with its
//     sibling `latest*.json` (same suffix), and runs one compare per pair.
//     Aggregates failures across all pairs — the process exits non-zero
//     if ANY pair regresses, so CI can use one invocation instead of N.

const std = @import("std");
const common = @import("common");

const default_results_dir = "benchmarks/results";

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    var baseline_path: ?[]const u8 = null;
    var candidate_path: ?[]const u8 = null;
    var threshold: f64 = 0.15;
    var walk_all: bool = false;
    var results_dir: []const u8 = default_results_dir;

    var idx: usize = 1;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--baseline") and idx + 1 < args.len) {
            baseline_path = args[idx + 1];
            idx += 1;
        } else if (std.mem.eql(u8, arg, "--candidate") and idx + 1 < args.len) {
            candidate_path = args[idx + 1];
            idx += 1;
        } else if (std.mem.eql(u8, arg, "--threshold") and idx + 1 < args.len) {
            threshold = std.fmt.parseFloat(f64, args[idx + 1]) catch threshold;
            idx += 1;
        } else if (std.mem.startsWith(u8, arg, "--threshold=")) {
            threshold = std.fmt.parseFloat(f64, arg["--threshold=".len..]) catch threshold;
        } else if (std.mem.eql(u8, arg, "--all")) {
            walk_all = true;
        } else if (std.mem.eql(u8, arg, "--dir") and idx + 1 < args.len) {
            results_dir = args[idx + 1];
            idx += 1;
        }
    }

    if (walk_all) {
        try runWalker(allocator, init.io, results_dir, threshold);
        return;
    }

    if (baseline_path == null or candidate_path == null) {
        const stderr = std.Io.File.stderr();
        try stderr.writeStreamingAll(init.io,
            \\usage:
            \\  bench-compare --baseline <file> --candidate <file> [--threshold 0.15]
            \\  bench-compare --all [--dir benchmarks/results] [--threshold 0.15]
            \\
        );
        return error.InvalidArguments;
    }

    var stats = PairStats{};
    try comparePair(allocator, init.io, baseline_path.?, candidate_path.?, threshold, &stats, null);
    if (stats.failures != 0) return error.BenchmarkRegression;
}

const PairStats = struct {
    failures: usize = 0,
    missing: usize = 0,
    rows_compared: usize = 0,
};

fn runWalker(allocator: std.mem.Allocator, io: std.Io, results_dir: []const u8, threshold: f64) !void {
    const stderr = std.Io.File.stderr();
    var header_buf: [160]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "bench-compare --all (dir={s}, hard threshold {d:.2}%)\n",
        .{ results_dir, threshold * 100.0 },
    );
    try stderr.writeStreamingAll(io, header);

    var dir = try std.Io.Dir.cwd().openDir(io, results_dir, .{ .iterate = true });
    defer dir.close(io);

    var baseline_names: std.ArrayList([]const u8) = .empty;
    defer baseline_names.deinit(allocator);

    var walker = dir.iterate();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, "baseline")) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        try baseline_names.append(allocator, try allocator.dupe(u8, entry.name));
    }

    // Deterministic order so output is stable across runs.
    std.sort.heap([]const u8, baseline_names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    if (baseline_names.items.len == 0) {
        var buf: [192]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "  no baseline*.json found under {s}/\n", .{results_dir});
        try stderr.writeStreamingAll(io, line);
        return error.InvalidArguments;
    }

    var total = PairStats{};
    var pairs_ran: usize = 0;
    var pairs_skipped: usize = 0;

    for (baseline_names.items) |base_name| {
        // Derive candidate filename: "baseline...json" -> "latest...json".
        const suffix = base_name["baseline".len..];
        const cand_name = try std.fmt.allocPrint(allocator, "latest{s}", .{suffix});

        const base_path = try std.fs.path.join(allocator, &.{ results_dir, base_name });
        const cand_path = try std.fs.path.join(allocator, &.{ results_dir, cand_name });

        // Skip pairs where the candidate file doesn't exist — that usually
        // means the CI step that produces `latest_foo.json` wasn't run this
        // time, not a regression.
        dir.access(io, cand_name, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                var buf: [256]u8 = undefined;
                const line = try std.fmt.bufPrint(&buf, "  SKIP {s} (no {s})\n", .{ base_name, cand_name });
                try stderr.writeStreamingAll(io, line);
                pairs_skipped += 1;
                continue;
            },
            else => return err,
        };

        var header_line: [256]u8 = undefined;
        const hl = try std.fmt.bufPrint(&header_line, "\n== {s} vs {s} ==\n", .{ base_name, cand_name });
        try stderr.writeStreamingAll(io, hl);

        var pair_stats = PairStats{};
        try comparePair(allocator, io, base_path, cand_path, threshold, &pair_stats, base_name);

        total.failures += pair_stats.failures;
        total.missing += pair_stats.missing;
        total.rows_compared += pair_stats.rows_compared;
        pairs_ran += 1;
    }

    var summary_buf: [256]u8 = undefined;
    const summary = try std.fmt.bufPrint(
        &summary_buf,
        "\nbench-compare --all: {d} pair(s) compared, {d} skipped, {d} row(s), {d} failure(s), {d} missing baseline row(s)\n",
        .{ pairs_ran, pairs_skipped, total.rows_compared, total.failures, total.missing },
    );
    try stderr.writeStreamingAll(io, summary);

    if (total.failures != 0) return error.BenchmarkRegression;
}

fn comparePair(
    allocator: std.mem.Allocator,
    io: std.Io,
    baseline_path: []const u8,
    candidate_path: []const u8,
    threshold: f64,
    stats: *PairStats,
    pair_label: ?[]const u8,
) !void {
    _ = pair_label; // reserved for future per-pair annotation; walker prints its own header

    const base_doc = try readDocument(allocator, io, baseline_path);
    const cand_doc = try readDocument(allocator, io, candidate_path);
    defer base_doc.deinit();
    defer cand_doc.deinit();

    const stderr = std.Io.File.stderr();
    for (cand_doc.value.rows) |row| {
        const baseline = findMatch(base_doc.value.rows, row) orelse {
            stats.missing += 1;
            var buf: [256]u8 = undefined;
            const line = try std.fmt.bufPrint(&buf, "  MISSING baseline for {s}/{s}/{d}T\n", .{ row.scenario_name, row.variant, row.thread_count });
            try stderr.writeStreamingAll(io, line);
            continue;
        };
        stats.rows_compared += 1;

        const throughput_change_pct = pctChange(baseline.throughput_ops_per_sec, row.throughput_ops_per_sec);

        // Noise gate: 3× stddev-pct is the classic 99.7% confidence interval.
        const stddev_pct = if (baseline.throughput_ops_per_sec != 0)
            (baseline.throughput_stddev_ops_per_sec / baseline.throughput_ops_per_sec) * 100.0
        else
            0.0;
        const noise_gate_pct = @max(threshold * 100.0, 3.0 * stddev_pct);

        var buf: [512]u8 = undefined;
        const sign: []const u8 = if (throughput_change_pct < 0) "-" else "+";
        const abs_change = if (throughput_change_pct < 0) -throughput_change_pct else throughput_change_pct;
        const line = try std.fmt.bufPrint(
            &buf,
            "  {s}/{s}/{d}T throughput {s}{d:.2}%  stddev {d:.2}%  gate {d:.2}%\n",
            .{ row.scenario_name, row.variant, row.thread_count, sign, abs_change, stddev_pct, noise_gate_pct },
        );
        try stderr.writeStreamingAll(io, line);

        if (throughput_change_pct < -noise_gate_pct) {
            const fail_line = try std.fmt.bufPrint(
                &buf,
                "    FAIL: regression {d:.2}% exceeds gate {d:.2}%\n",
                .{ -throughput_change_pct, noise_gate_pct },
            );
            try stderr.writeStreamingAll(io, fail_line);
            stats.failures += 1;
        }

        // UUID-specific correctness gates.
        if (row.duplicate_uuids != 0) {
            const dup_line = try std.fmt.bufPrint(
                &buf,
                "    FAIL: {d} duplicate UUIDs in contention scenario\n",
                .{row.duplicate_uuids},
            );
            try stderr.writeStreamingAll(io, dup_line);
            stats.failures += 1;
        }
    }
}

fn readDocument(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !std.json.Parsed(common.ResultDocument) {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024));
    return std.json.parseFromSlice(common.ResultDocument, allocator, bytes, .{ .ignore_unknown_fields = true });
}

fn findMatch(rows: []const common.ResultRow, current: common.ResultRow) ?common.ResultRow {
    for (rows) |row| {
        if (std.mem.eql(u8, row.scenario_name, current.scenario_name) and
            std.mem.eql(u8, row.variant, current.variant) and
            row.thread_count == current.thread_count)
        {
            return row;
        }
    }
    return null;
}

fn pctChange(before: f64, after: f64) f64 {
    if (before == 0) return 0;
    return ((after - before) / before) * 100.0;
}
