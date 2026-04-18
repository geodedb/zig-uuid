// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Regression gate for the uuid benchmark suite.  Reads two JSON result
// documents (baseline + candidate) and fails when any row in the candidate
// has throughput below `baseline * (1 - threshold)`.  The threshold defaults
// to 0.15 (matches PERF-26); pass `--threshold 0.10` to tighten.  Per-row
// stddev is used as a noise floor on top of the hard threshold: if the
// baseline stddev is greater than 5 % of the baseline throughput, the
// effective gate for that row becomes `max(threshold, 3*stddev_pct/100)`.
//
// Rows are matched on (scenario_name, variant, thread_count).

const std = @import("std");
const common = @import("common");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    var baseline_path: ?[]const u8 = null;
    var candidate_path: ?[]const u8 = null;
    var threshold: f64 = 0.15;

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
        }
    }

    if (baseline_path == null or candidate_path == null) {
        const stderr = std.Io.File.stderr();
        try stderr.writeStreamingAll(init.io, "usage: bench-compare --baseline <file> --candidate <file> [--threshold 0.15]\n");
        return error.InvalidArguments;
    }

    const base_doc = try readDocument(allocator, init.io, baseline_path.?);
    const cand_doc = try readDocument(allocator, init.io, candidate_path.?);
    defer base_doc.deinit();
    defer cand_doc.deinit();

    const stderr = std.Io.File.stderr();
    var header_buf: [128]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "bench-compare (hard threshold {d:.2}%)\n", .{threshold * 100.0});
    try stderr.writeStreamingAll(init.io, header);

    var failures: usize = 0;
    var missing: usize = 0;
    for (cand_doc.value.rows) |row| {
        const baseline = findMatch(base_doc.value.rows, row) orelse {
            missing += 1;
            var buf: [256]u8 = undefined;
            const line = try std.fmt.bufPrint(&buf, "  MISSING baseline for {s}/{s}/{d}T\n", .{ row.scenario_name, row.variant, row.thread_count });
            try stderr.writeStreamingAll(init.io, line);
            continue;
        };
        const throughput_change_pct = pctChange(baseline.throughput_ops_per_sec, row.throughput_ops_per_sec);

        // Noise gate: 3× stddev-pct is the classic 99.7% confidence interval.
        // Use max(threshold, 3*stddev_pct) so a noisy row needs a bigger
        // regression to fail the gate, but a quiet row cannot sneak through
        // below the hard floor.
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
        try stderr.writeStreamingAll(init.io, line);

        if (throughput_change_pct < -noise_gate_pct) {
            const fail_line = try std.fmt.bufPrint(
                &buf,
                "    FAIL: regression {d:.2}% exceeds gate {d:.2}%\n",
                .{ -throughput_change_pct, noise_gate_pct },
            );
            try stderr.writeStreamingAll(init.io, fail_line);
            failures += 1;
        }

        // UUID-specific correctness gates.
        if (row.duplicate_uuids != 0) {
            const dup_line = try std.fmt.bufPrint(
                &buf,
                "    FAIL: {d} duplicate UUIDs in contention scenario\n",
                .{row.duplicate_uuids},
            );
            try stderr.writeStreamingAll(init.io, dup_line);
            failures += 1;
        }
    }

    if (missing > 0) {
        var buf: [96]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "WARNING: {d} candidate row(s) had no baseline match\n", .{missing});
        try stderr.writeStreamingAll(init.io, line);
    }

    if (failures != 0) return error.BenchmarkRegression;
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
