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

    // Unit tests
    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "json", .module = json_module },
            },
        }),
    });
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

    // Check step (fast syntax validation)
    const check_step = b.step("check", "Check for compilation errors");
    const check = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "json", .module = json_module },
            },
        }),
    });
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

    // Cross-compile check step — all five target triples are compiled unconditionally.
    // Each invocation of `zig build check-cross` compiles all five targets,
    // so `make cross-compile-required` (which calls this once) checks everything.
    const cross_step = b.step("check-cross", "Cross-compile check for the active -Dtarget");
    const cross_targets = [_][]const u8{
        "x86_64-linux",
        "aarch64-linux",
        "x86_64-macos",
        "aarch64-macos",
        "x86_64-windows",
    };
    for (cross_targets) |triple| {
        const cross_target = b.resolveTargetQuery(
            std.Target.Query.parse(.{ .arch_os_abi = triple }) catch unreachable,
        );
        const cross_check = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = cross_target,
                .optimize = .Debug,
                .imports = &.{
                    .{ .name = "json", .module = json_module },
                },
            }),
        });
        cross_step.dependOn(&cross_check.step);
    }
}
