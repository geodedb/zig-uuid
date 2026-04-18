// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const json_dep = b.dependency("json", .{ .target = target, .optimize = optimize });
    const json_module = json_dep.module("json");

    // Main library module
    const module = b.addModule("uuid", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "json", .module = json_module },
        },
    });

    // Unit tests — reuse the public `module` so src/root.zig isn't rooted by
    // multiple module instances (would trigger "file exists in modules 'json'
    // and 'json0'" when downstream consumers graph-walk multiple instances).
    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{ .root_module = module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests
    const integration_step = b.step("test-integration", "Run integration tests");
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "json", .module = json_module },
            },
        }),
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    integration_step.dependOn(&run_integration_tests.step);

    // Check step (fast syntax validation) — reuse public `module` (same
    // dedup reason as unit_tests above).
    const check_step = b.step("check", "Check for compilation errors");
    const check = b.addTest(.{ .root_module = module });
    check_step.dependOn(&check.step);

    // Benchmark binary (PERF-03)
    // Run with: zig build bench -Doptimize=ReleaseFast
    const bench_step = b.step("bench", "Run benchmarks (use -Doptimize=ReleaseFast for accurate results)");
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
            },
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    bench_step.dependOn(&run_bench.step);

    // Compile-only bench check (PERF-15): used by CI to verify bench/main.zig
    // compiles without running the benchmarks (which would execute 6M iterations
    // and discard results, wasting CI minutes).
    const bench_check_step = b.step("bench-check", "Compile-only check for bench/main.zig (used in CI)");
    bench_check_step.dependOn(&bench_exe.step);

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
