// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Fuzz tests for UUID parsing and construction (SEC-R2-11, #52, QC-32).
//!
//! Run with: zig build test --fuzz  (requires Zig 0.15+)
//!
//! These tests verify that UUID functions never panic on arbitrary input —
//! they may return errors, but must not crash, overflow, or exhibit
//! undefined behaviour.
//!
//! Fuzz targets:
//!   - UUID.fromString   — string parser (all 6 input formats)
//!   - UUID.fromBytes    — 16-byte slice constructor
//!   - NullUUID.jsonUnmarshal — JSON string deserializer

const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const NullUUID = @import("null_uuid.zig").NullUUID;
const json = @import("json");

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

// Byte corpus for fromBytes: includes edge-case lengths around 16.
const byte_corpus: []const []const u8 = &.{
    "",
    "\x00",
    "\x00" ** 15,
    "\x00" ** 16,
    "\xff" ** 16,
    "\x00" ** 17,
    "\x00" ** 32,
};

/// Fuzz target: UUID.fromString must not panic on any input.
fn fuzzFromString(_: void, input: []const u8) anyerror!void {
    _ = UUID.fromString(input) catch {};
}

/// Fuzz target: UUID.fromBytes must not panic on any input (QC-32).
/// Only panics/UB are disallowed; error.IncorrectByteLength for non-16-byte
/// input is expected and acceptable.
fn fuzzFromBytes(_: void, input: []const u8) anyerror!void {
    _ = UUID.fromBytes(input) catch {};
}

/// Fuzz target: NullUUID.jsonUnmarshal must not panic on arbitrary input (QC-32, SEC-R5-04).
///
/// Exercises all json.Value variants so that every branch of the else-clause
/// (which maps non-string, non-null values to Error.InvalidFormat) is covered
/// by the fuzzer without panicking or exhibiting undefined behaviour.
///
/// Variants covered:
///   .str   — primary path: arbitrary UUID string (most interesting for parsing)
///   .null  — secondary path: returns NullUUID.nil
///   .bool  — must return Error.InvalidFormat, not panic
///   .num   — must return Error.InvalidFormat, not panic (Number is stack-allocated)
///   .arr   — must return Error.InvalidFormat, not panic (zero-length slice is safe)
///   .obj   — must return Error.InvalidFormat, not panic (zero-length slice is safe)
fn fuzzNullUUIDJsonUnmarshal(_: void, input: []const u8) anyerror!void {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();
    // Exercise the string input path (most interesting for UUID parsing).
    _ = NullUUID.jsonUnmarshal(alloc, json.Value{ .str = input }) catch {};
    // Also exercise the null path to ensure coverage.
    _ = NullUUID.jsonUnmarshal(alloc, .null) catch {};
    // SEC-R5-04: additional variant coverage — all must return an error, never panic.
    _ = NullUUID.jsonUnmarshal(alloc, json.Value{ .bool = input.len % 2 == 0 }) catch {};
    // .num requires a json.Number; use a stack-local with input.len as the lexeme.
    // sign=1, digits=lexeme, exp10=0 is a valid (if synthetic) Number representation.
    const num = json.Number{
        .lexeme = input,
        .sign = 1,
        .digits = input,
        .exp10 = 0,
    };
    _ = NullUUID.jsonUnmarshal(alloc, json.Value{ .num = num }) catch {};
    // .arr and .obj with zero-length slices avoid any heap allocation while
    // still exercising the variant branches.
    _ = NullUUID.jsonUnmarshal(alloc, json.Value{ .arr = &.{} }) catch {};
    _ = NullUUID.jsonUnmarshal(alloc, json.Value{ .obj = &.{} }) catch {};
}

test "fuzz: UUID.fromString does not panic on arbitrary input (SEC-R2-11/#52)" {
    for (corpus) |input| {
        try fuzzFromString({}, input);
    }
    try std.testing.fuzz({}, fuzzFromString, .{ .corpus = corpus });
}

test "fuzz: UUID.fromBytes does not panic on arbitrary input (QC-32)" {
    for (byte_corpus) |input| {
        try fuzzFromBytes({}, input);
    }
    try std.testing.fuzz({}, fuzzFromBytes, .{ .corpus = byte_corpus });
}

test "fuzz: NullUUID.jsonUnmarshal does not panic on arbitrary string input (QC-32)" {
    // Exercise the corpus in normal test mode first.
    for (corpus) |input| {
        try fuzzNullUUIDJsonUnmarshal({}, input);
    }
    try std.testing.fuzz({}, fuzzNullUUIDJsonUnmarshal, .{ .corpus = corpus });
}
