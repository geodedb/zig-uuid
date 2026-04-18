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
fn fuzzFromString(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [256]u8 = undefined;
    const len = smith.slice(&buf);
    const input = buf[0..len];
    _ = UUID.fromString(input) catch {};
}

/// Fuzz target: UUID.fromBytes must not panic on any input (QC-32).
/// Only panics/UB are disallowed; error.IncorrectByteLength for non-16-byte
/// input is expected and acceptable.
fn fuzzFromBytes(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [256]u8 = undefined;
    const len = smith.slice(&buf);
    const input = buf[0..len];
    _ = UUID.fromBytes(input) catch {};
}

// NullUUID.jsonUnmarshal fuzz target moved to the uuid_json submodule
// (src/uuid_json.zig) — core fuzz suite no longer needs a `json` import.

test "fuzz: UUID.fromString does not panic on arbitrary input (SEC-R2-11/#52)" {
    try std.testing.fuzz({}, fuzzFromString, .{ .corpus = corpus });
}

test "fuzz: UUID.fromBytes does not panic on arbitrary input (QC-32)" {
    try std.testing.fuzz({}, fuzzFromBytes, .{ .corpus = byte_corpus });
}

// Fuzz coverage for NullUUID JSON unmarshal lives in src/uuid_json.zig.

// =============================================================================
// SEC-R8-02: Fuzz targets for Timestamp and Generator.loadState
// =============================================================================

/// Fuzz target: Timestamp.fromUnixMs must not panic on any i64 value (SEC-R8-02).
///
/// Interprets the first 8 bytes of input as a little-endian i64 millisecond
/// timestamp.  Any error return (negative, overflow, etc.) is acceptable;
/// only panics and undefined behaviour are disallowed.
fn fuzzTimestampFromUnixMs(_: void, smith: *std.testing.Smith) anyerror!void {
    var input: [8]u8 = undefined;
    _ = smith.slice(&input);
    const ms = std.mem.readInt(i64, &input, .little);
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
fn fuzzTimestampFromUnixNano(_: void, smith: *std.testing.Smith) anyerror!void {
    var input: [16]u8 = undefined;
    _ = smith.slice(&input);
    const ns = std.mem.readInt(i128, &input, .little);
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
fn fuzzGeneratorLoadState(_: void, smith: *std.testing.Smith) anyerror!void {
    const linux = if (comptime @import("builtin").os.tag == .linux) std.os.linux else return;
    var input_buf: [256]u8 = undefined;
    const input_len = smith.slice(&input_buf);
    const input = input_buf[0..input_len];
    const io = std.Io.Threaded.global_single_threaded.io();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // Write the fuzz bytes as a state file.
    const f = try tmp.dir.createFile(io, "uuid.state", .{});
    try f.writePositionalAll(io, input, 0);
    f.close(io);
    // Build an absolute path to the state file via /proc/self/fd.
    const fd: linux.fd_t = tmp.dir.handle;
    var link_buf: [64:0]u8 = undefined;
    _ = try std.fmt.bufPrintZ(&link_buf, "/proc/self/fd/{d}", .{fd});
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const rc = linux.readlink(&link_buf, &dir_buf, dir_buf.len);
    const err = linux.errno(rc);
    if (err != .SUCCESS) return;
    const dir_path = dir_buf[0..rc];
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
    try std.testing.fuzz({}, fuzzTimestampFromUnixMs, .{ .corpus = ms_corpus });
}

test "fuzz: Timestamp.fromUnixNano does not panic on arbitrary i128 input (SEC-R8-02)" {
    try std.testing.fuzz({}, fuzzTimestampFromUnixNano, .{ .corpus = nano_corpus });
}

test "fuzz: Generator.loadState does not panic on arbitrary file content (SEC-R8-02)" {
    try std.testing.fuzz({}, fuzzGeneratorLoadState, .{ .corpus = state_corpus });
}
