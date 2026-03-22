// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Fuzz tests for UUID parsing (SEC-R2-11, #52).
//!
//! Run with: zig build test --fuzz  (requires Zig 0.15+)
//!
//! These tests verify that UUID parsing functions never panic on arbitrary
//! input — they may return errors, but must not crash, overflow, or exhibit
//! undefined behaviour.

const std = @import("std");
const UUID = @import("uuid.zig").UUID;

// Known-tricky inputs that parsers often mishandle.
const corpus: []const []const u8 = &.{
    // Empty / too short
    "",
    "a",
    "00000000",
    // Almost-canonical (wrong length)
    "00000000-0000-0000-0000-00000000000",
    "00000000-0000-0000-0000-000000000000x",
    // All bytes
    "ffffffff-ffff-ffff-ffff-ffffffffffff",
    // High bit bytes
    "\xff\xff\xff\xff-\xff\xff\xff-\xff-\xff\xff\xff\xff\xff\xff\xff\xff",
    // Null bytes
    "\x00\x00\x00\x00-\x00\x00\x00-\x00\x00-\x00\x00-\x00\x00\x00\x00\x00\x00",
    // Braced
    "{00000000-0000-0000-0000-000000000000}",
    "{ffffffff-ffff-ffff-ffff-ffffffffffff}",
    // URN
    "urn:uuid:00000000-0000-0000-0000-000000000000",
    "urn:uuid:ffffffff-ffff-ffff-ffff-ffffffffffff",
    // 32-char hex
    "00000000000000000000000000000000",
    "ffffffffffffffffffffffffffffffff",
    // Invalid variants
    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    // Overlong
    "00000000-0000-0000-0000-000000000000-extra",
    // Control characters
    "\t\n\r ",
};

/// Fuzz target: UUID.fromString must not panic on any input.
/// Any result (ok or error) is acceptable; we only verify no panic/crash.
fn fuzzFromString(_: void, input: []const u8) anyerror!void {
    _ = UUID.fromString(input) catch {};
}

test "fuzz: UUID.fromString does not panic on arbitrary input (SEC-R2-11/#52)" {
    // Exercise the corpus in normal test mode.
    for (corpus) |input| {
        try fuzzFromString({}, input);
    }

    // When run with `--fuzz`, this hands control to libFuzzer via std.testing.fuzz.
    // The corpus is passed as initial seeds; libFuzzer extends coverage from there.
    try std.testing.fuzz({}, fuzzFromString, .{ .corpus = corpus });
}
