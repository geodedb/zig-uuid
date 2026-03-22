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
//!   - UUID.fromString          — string parser (all 6 input formats)
//!   - UUID.fromBytes           — 16-byte slice constructor
//!   - NullUUID.jsonUnmarshal   — JSON string deserializer
//!   - Timestamp.fromUnixMs     — i64 timestamp construction (SEC-R8-02)
//!   - Timestamp.fromUnixNano   — i128 timestamp construction (SEC-R8-02)
//!   - Generator.loadState      — state-file deserialization (SEC-R8-02)

const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const NullUUID = @import("null_uuid.zig").NullUUID;
const json = @import("json");
const Timestamp = @import("timestamp.zig").Timestamp;
const Generator = @import("generator.zig").Generator;

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

// =============================================================================
// SEC-R8-02: Fuzz targets for Timestamp and Generator.loadState
// =============================================================================

/// Fuzz target: Timestamp.fromUnixMs must not panic on any i64 value (SEC-R8-02).
///
/// Interprets the first 8 bytes of input as a little-endian i64 millisecond
/// timestamp.  Any error return (negative, overflow, etc.) is acceptable;
/// only panics and undefined behaviour are disallowed.
fn fuzzTimestampFromUnixMs(_: void, input: []const u8) anyerror!void {
    if (input.len < 8) return; // insufficient bytes to form an i64
    const ms = std.mem.readInt(i64, input[0..8], .little);
    _ = Timestamp.fromUnixMs(ms) catch {};
}

// i64 corpus for fromUnixMs: covers negative, zero, small, large, and extreme values.
const ms_corpus: []const []const u8 = &.{
    // 0 ms
    "\x00\x00\x00\x00\x00\x00\x00\x00",
    // 1 ms
    "\x01\x00\x00\x00\x00\x00\x00\x00",
    // -1 ms (negative)
    "\xff\xff\xff\xff\xff\xff\xff\xff",
    // maxInt(i64): overflows the u64 interval range (SEC-R8-01)
    "\xff\xff\xff\xff\xff\xff\xff\x7f",
    // minInt(i64): negative
    "\x00\x00\x00\x00\x00\x00\x00\x80",
    // 2023-11-14 in ms
    "\x40\x0b\xb4\x79\x8c\x01\x00\x00",
};

/// Fuzz target: Timestamp.fromUnixNano must not panic on any i128 value (SEC-R8-02).
///
/// Interprets the first 16 bytes of input as a little-endian i128 nanosecond
/// timestamp.  Any error return is acceptable; only panics are disallowed.
fn fuzzTimestampFromUnixNano(_: void, input: []const u8) anyerror!void {
    if (input.len < 16) return; // insufficient bytes to form an i128
    const ns = std.mem.readInt(i128, input[0..16], .little);
    _ = Timestamp.fromUnixNano(ns) catch {};
}

// i128 corpus for fromUnixNano: covers boundary conditions (SEC-R8-01 thresholds).
const nano_corpus: []const []const u8 = &.{
    // 0 ns
    "\x00" ** 16,
    // -1 ns (negative)
    "\xff" ** 16,
    // maxInt(i128): far above any valid range
    "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x7f",
    // maxInt(u64) * 100 + 100 (just above the u64 interval upper bound)
    "\x64\x00\x00\x00\x00\x00\x00\x00\xff\xff\xff\xff\xff\xff\xff\x00",
    // maxInt(u64) * 100 - 100 (just below the bound — should succeed)
    "\x9c\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\x00",
    // SEC-R12-02: secondary addition overflow boundary for fromUnixNano.
    // ns = (maxInt(u64) - gregorian_offset + 1) * 100 — the first value
    // where intervals_u64 + gregorian_offset overflows u64.
    "\x00\x00\x83\x61\xf0\x59\x6c\x56\x63\x00\x00\x00\x00\x00\x00\x00",
    // SEC-R12-02: just below the secondary overflow boundary (should succeed)
    "\x9c\xff\x82\x61\xf0\x59\x6c\x56\x63\x00\x00\x00\x00\x00\x00\x00",
    // A real-world timestamp (2023-11-14 in ns)
    "\x00\xb0\x7a\x2c\x5c\x79\x94\x68\x01\x00\x00\x00\x00\x00\x00\x00",
};

/// Fuzz target: Generator.loadState must not panic on arbitrary file content (SEC-R8-02).
///
/// Writes the fuzz input bytes to a temporary file, then calls loadState.
/// Accepts any return value (success or error) — only panics and UB are forbidden.
fn fuzzGeneratorLoadState(_: void, input: []const u8) anyerror!void {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // Write the fuzz bytes as a state file.
    const f = try tmp.dir.createFile("uuid.state", .{});
    try f.writeAll(input);
    f.close();
    // Build an absolute path to the state file.
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/uuid.state", .{dir_path});
    // Attempt loadState — any error return is acceptable, no panic allowed.
    var gen = Generator.init();
    _ = gen.loadState(path) catch {};
}

// Binary corpus for loadState: valid and malformed state files.
const state_corpus: []const []const u8 = &.{
    // Empty file
    "",
    // Too short (3 bytes)
    "UUI",
    // Wrong magic
    "FAKE\x02\x00\x00\x00" ++ "\x00" ** 24,
    // Valid v1 magic, wrong format version
    "UUID\x99\x00\x00\x00" ++ "\x00" ** 14,
    // Valid v1 state file (22 bytes, version=1, no flags)
    "UUID\x01\x00\x00\x00" ++ "\x00" ** 16,
    // Valid v2 state file (32 bytes, version=2, no flags)
    "UUID\x02\x00\x00\x00" ++ "\x00" ** 24,
    // Oversized (33 bytes)
    "UUID\x02\x00\x00\x00" ++ "\x00" ** 25,
    // All 0xFF
    "\xff" ** 32,
};

test "fuzz: Timestamp.fromUnixMs does not panic on arbitrary i64 input (SEC-R8-02)" {
    for (ms_corpus) |input| {
        try fuzzTimestampFromUnixMs({}, input);
    }
    try std.testing.fuzz({}, fuzzTimestampFromUnixMs, .{ .corpus = ms_corpus });
}

test "fuzz: Timestamp.fromUnixNano does not panic on arbitrary i128 input (SEC-R8-02)" {
    for (nano_corpus) |input| {
        try fuzzTimestampFromUnixNano({}, input);
    }
    try std.testing.fuzz({}, fuzzTimestampFromUnixNano, .{ .corpus = nano_corpus });
}

test "fuzz: Generator.loadState does not panic on arbitrary file content (SEC-R8-02)" {
    for (state_corpus) |input| {
        try fuzzGeneratorLoadState({}, input);
    }
    try std.testing.fuzz({}, fuzzGeneratorLoadState, .{ .corpus = state_corpus });
}
