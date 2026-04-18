// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core `uuid` module is dep-free. The json adapter lives in a separate
    // `uuid_json` module consumers opt into. Keeping json out of the core
    // module avoids diamond errors when uuid is instantiated by multiple
    // sibling build contexts (geode, geode-client-zig, graph-storage) that
    // each reach uuid through different graph chains.
    const module = b.addModule("uuid", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Opt-in json adapter. Depends on `json` and the core uuid module.
    const json_dep = b.dependency("json", .{ .target = target, .optimize = optimize });
    const json_module = json_dep.module("json");
    const uuid_json_module = b.addModule("uuid_json", .{
        .root_source_file = b.path("src/uuid_json.zig"),
        .target = target,
        .optimize = optimize,
    });
    uuid_json_module.addImport("json", json_module);
    uuid_json_module.addImport("uuid", module);

    // Unit tests — reuse the public `module` so src/root.zig isn't rooted by
    // multiple module instances (would trigger "file exists in modules 'json'
    // and 'json0'" when downstream consumers graph-walk multiple instances).
    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{ .root_module = module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests exercise both core and the json adapter.
    const integration_step = b.step("test-integration", "Run integration tests");
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "uuid_json", .module = uuid_json_module },
                .{ .name = "json", .module = json_module },
            },
        }),
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    integration_step.dependOn(&run_integration_tests.step);

    // Unit tests for the json adapter itself.
    const unit_tests_json = b.addTest(.{ .root_module = uuid_json_module });
    const run_unit_tests_json = b.addRunArtifact(unit_tests_json);
    test_step.dependOn(&run_unit_tests_json.step);

    // Check step (fast syntax validation) — reuse public `module` (same
    // dedup reason as unit_tests above).
    const check_step = b.step("check", "Check for compilation errors");
    const check = b.addTest(.{ .root_module = module });
    check_step.dependOn(&check.step);

    // -------------------------------------------------------------------------
    // Benchmark harness (modelled after sibling thread-pool repo).
    //
    // The harness lives under `benchmarks/` and produces JSON result
    // documents. Every bench executable is pinned to ReleaseFast by default
    // so CI and ad-hoc runs are directly comparable. Callers can still
    // build a Debug variant by editing `bench_optimize` below when profiling.
    // -------------------------------------------------------------------------
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;

    const bench_module_common = b.createModule(.{
        .root_source_file = b.path("benchmarks/common.zig"),
        .target = target,
        .optimize = bench_optimize,
        .imports = &.{
            .{ .name = "uuid", .module = module },
        },
    });

    // Unit tests for the harness itself (percentile calc, RSS reader). Hook
    // them into `zig build test` so schema regressions are caught in the
    // normal dev loop.
    const bench_common_tests = b.addTest(.{ .root_module = bench_module_common });
    const run_bench_common_tests = b.addRunArtifact(bench_common_tests);
    test_step.dependOn(&run_bench_common_tests.step);

    const bench_step = b.step("bench", "Run the CI-safe single-thread benchmark suite");
    const bench_exe = b.addExecutable(.{
        .name = "uuid-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/bench.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "common", .module = bench_module_common },
            },
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    if (b.args) |args| run_bench.addArgs(args);
    bench_step.dependOn(&run_bench.step);

    const bench_contention_step = b.step("bench-contention", "Multi-thread V7 contention matrix (mutex vs lockfree)");
    const bench_contention_exe = b.addExecutable(.{
        .name = "uuid-bench-contention",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/bench_contention.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "common", .module = bench_module_common },
            },
        }),
    });
    const run_bench_contention = b.addRunArtifact(bench_contention_exe);
    if (b.args) |args| run_bench_contention.addArgs(args);
    bench_contention_step.dependOn(&run_bench_contention.step);

    const bench_state_step = b.step("bench-state", "saveState/loadState throughput (v2 vs v3 HMAC)");
    const bench_state_exe = b.addExecutable(.{
        .name = "uuid-bench-state",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/bench_state.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "common", .module = bench_module_common },
            },
        }),
    });
    const run_bench_state = b.addRunArtifact(bench_state_exe);
    if (b.args) |args| run_bench_state.addArgs(args);
    bench_state_step.dependOn(&run_bench_state.step);

    const micro_parse_exe = b.addExecutable(.{
        .name = "uuid-bench-micro-parse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/micro/parse.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "common", .module = bench_module_common },
            },
        }),
    });
    const run_micro_parse = b.addRunArtifact(micro_parse_exe);
    if (b.args) |args| run_micro_parse.addArgs(args);
    const micro_parse_step = b.step("bench-micro-parse", "Micro-benchmark: fromString latency distribution");
    micro_parse_step.dependOn(&run_micro_parse.step);

    const micro_format_exe = b.addExecutable(.{
        .name = "uuid-bench-micro-format",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/micro/format.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "common", .module = bench_module_common },
            },
        }),
    });
    const run_micro_format = b.addRunArtifact(micro_format_exe);
    if (b.args) |args| run_micro_format.addArgs(args);
    const micro_format_step = b.step("bench-micro-format", "Micro-benchmark: toString/toHex/toURN throughput");
    micro_format_step.dependOn(&run_micro_format.step);

    const micro_hash_exe = b.addExecutable(.{
        .name = "uuid-bench-micro-hash",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/micro/hash.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "common", .module = bench_module_common },
            },
        }),
    });
    const run_micro_hash = b.addRunArtifact(micro_hash_exe);
    if (b.args) |args| run_micro_hash.addArgs(args);
    const micro_hash_step = b.step("bench-micro-hash", "Micro-benchmark: V3/V5 hash cost + prehashed comparison");
    micro_hash_step.dependOn(&run_micro_hash.step);

    const micro_step = b.step("bench-micro", "Run all micro-benchmarks");
    micro_step.dependOn(&run_micro_parse.step);
    micro_step.dependOn(&run_micro_format.step);
    micro_step.dependOn(&run_micro_hash.step);

    const bench_all_step = b.step("bench-all", "Run every benchmark executable (bench + contention + state + micro)");
    bench_all_step.dependOn(&run_bench.step);
    bench_all_step.dependOn(&run_bench_contention.step);
    bench_all_step.dependOn(&run_bench_state.step);
    bench_all_step.dependOn(&run_micro_parse.step);
    bench_all_step.dependOn(&run_micro_format.step);
    bench_all_step.dependOn(&run_micro_hash.step);

    const compare_exe = b.addExecutable(.{
        .name = "uuid-bench-compare",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/compare.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{
                .{ .name = "common", .module = bench_module_common },
            },
        }),
    });
    const run_compare = b.addRunArtifact(compare_exe);
    if (b.args) |args| run_compare.addArgs(args);
    const compare_step = b.step("bench-compare", "Compare two benchmark result JSONs (regression gate)");
    compare_step.dependOn(&run_compare.step);

    // Compile-only check for every bench executable (PERF-15: used by CI to
    // verify the benchmark sources compile without running them).
    const bench_check_step = b.step("bench-check", "Compile-only check for every benchmark executable");
    bench_check_step.dependOn(&bench_exe.step);
    bench_check_step.dependOn(&bench_contention_exe.step);
    bench_check_step.dependOn(&bench_state_exe.step);
    bench_check_step.dependOn(&micro_parse_exe.step);
    bench_check_step.dependOn(&micro_format_exe.step);
    bench_check_step.dependOn(&micro_hash_exe.step);
    bench_check_step.dependOn(&compare_exe.step);

    // Examples build step (QC-15: ensures examples compile and API drift is caught)
    const examples_step = b.step("examples", "Build examples");
    const example_exe = b.addExecutable(.{
        .name = "basic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
            },
        }),
    });
    examples_step.dependOn(&example_exe.step);

    // Cross-compile check step removed — previously created per-target module
    // copies rooted at src/root.zig, which triggered duplicate-module diamond
    // errors in downstream consumers ("src/uuid.zig: file exists in modules
    // 'json' and 'json0'"). Cross-target builds remain available via explicit
    // `zig build -Dtarget=<triple>` invocations, matching the sibling-repo
    // convention.
    _ = &json_module; // silence unused when only the single public module uses it
}
