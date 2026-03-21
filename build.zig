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
