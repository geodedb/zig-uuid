// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const Version = @import("uuid.zig").Version;
const Error = @import("uuid.zig").Error;

/// 100-nanosecond intervals since 1582-10-15 (Gregorian epoch).
/// Used by V1 and V6 natively. V7 Unix-ms timestamps are converted to/from
/// this type via fromUnixMs() / toUnixMs() (G-4, G-5).
pub const Timestamp = struct {
    value: u60,

    /// Offset between Gregorian epoch (1582-10-15) and Unix epoch (1970-01-01)
    /// in 100-ns intervals: 122,192,928 seconds × 10,000,000 intervals/second.
    pub const gregorian_offset: u64 = 122_192_928_000_000_000;

    /// Current time as a Gregorian Timestamp (F-7).
    ///
    /// Returns Error.InvalidTimestamp if the system clock reports a time
    /// before the Unix epoch (1970-01-01). Pre-1970 clocks are rare but would
    /// cause an unchecked @intCast panic without this guard.
    pub fn now() Error!Timestamp {
        const ns: i128 = std.time.nanoTimestamp();
        if (ns < 0) return Error.InvalidTimestamp;
        const intervals_since_unix: u64 = @intCast(@divTrunc(ns, 100));
        return .{ .value = @truncate(intervals_since_unix + gregorian_offset) };
    }

    /// Convert to Unix nanoseconds for interop with std.time.
    pub fn toUnixNano(self: Timestamp) i128 {
        const intervals: i128 = @as(i128, self.value) - gregorian_offset;
        return intervals * 100;
    }

    /// Convert to Unix milliseconds (G-5).
    ///
    /// **Bounds:** The 60-bit Gregorian timestamp space maps to Unix ms values
    /// in the range [-12.2T, +103T], which fits within i64. The @intCast below
    /// cannot panic for any valid u60 Timestamp value. The saturating clamps are
    /// defense-in-depth against future changes to the value field width (SEC-R2-15).
    pub fn toUnixMs(self: Timestamp) i64 {
        const ns = self.toUnixNano();
        // Divide first (i128 → smaller i128) before casting to i64.
        // For any u60 value, the result fits in i64 (see doc comment above).
        const ms128 = @divTrunc(ns, 1_000_000);
        if (ms128 > std.math.maxInt(i64)) return std.math.maxInt(i64);
        if (ms128 < std.math.minInt(i64)) return std.math.minInt(i64);
        return @intCast(ms128);
    }

    /// Convert to Unix seconds (G-5).
    ///
    /// **Bounds:** Same as toUnixMs — all valid Timestamp values fit in i64
    /// after dividing by 1_000_000_000. The saturating clamps are
    /// defense-in-depth against future changes to the value field width (SEC-R2-15).
    pub fn toUnixSec(self: Timestamp) i64 {
        const ns = self.toUnixNano();
        const sec128 = @divTrunc(ns, 1_000_000_000);
        if (sec128 > std.math.maxInt(i64)) return std.math.maxInt(i64);
        if (sec128 < std.math.minInt(i64)) return std.math.minInt(i64);
        return @intCast(sec128);
    }

    /// Create from Unix nanoseconds.
    pub fn fromUnixNano(ns: i128) Error!Timestamp {
        if (ns < 0) return Error.InvalidTimestamp;
        const intervals_since_unix: u64 = @intCast(@divTrunc(ns, 100));
        return .{ .value = @truncate(intervals_since_unix + gregorian_offset) };
    }

    /// Create from Unix milliseconds (G-4 helper for timestampFromV7).
    pub fn fromUnixMs(ms: i64) Error!Timestamp {
        if (ms < 0) return Error.InvalidTimestamp;
        const ns: i128 = @as(i128, ms) * 1_000_000;
        return fromUnixNano(ns);
    }
};

/// Extract Gregorian timestamp from a V1 UUID.
/// V1 layout: time_low(32)|time_mid(16)|ver(4)|time_high(12) in bytes 0-7.
pub fn timestampFromV1(u: UUID) Error!Timestamp {
    if (u.version() != .v1) return Error.InvalidVersion;
    const low: u64 = std.mem.readInt(u32, u.bytes[0..4], .big);
    const mid: u64 = std.mem.readInt(u16, u.bytes[4..6], .big);
    const high: u64 = std.mem.readInt(u16, u.bytes[6..8], .big) & 0x0FFF; // mask version nibble
    const ts: u60 = @truncate((high << 48) | (mid << 32) | low);
    return .{ .value = ts };
}

/// Extract Gregorian timestamp from a V6 UUID.
/// V6 layout: time_high(32)|time_mid(16)|ver(4)|time_low(12) in bytes 0-7.
pub fn timestampFromV6(u: UUID) Error!Timestamp {
    if (u.version() != .v6) return Error.InvalidVersion;
    const hi: u64 = std.mem.readInt(u32, u.bytes[0..4], .big);
    const mid: u64 = std.mem.readInt(u16, u.bytes[4..6], .big);
    const low: u64 = std.mem.readInt(u16, u.bytes[6..8], .big) & 0x0FFF; // mask version nibble
    // Reassemble: V6 stores bits 28-59 in hi, bits 12-27 in mid, bits 0-11 in low
    const ts: u60 = @truncate((hi << 28) | (mid << 12) | low);
    return .{ .value = ts };
}

/// Extract timestamp from a V7 UUID as a Gregorian Timestamp (G-4).
///
/// V7 UUIDs embed a Unix millisecond timestamp. This function converts that
/// value to the same Gregorian Timestamp type returned by timestampFromV1 and
/// timestampFromV6, making the API consistent. Use .toUnixMs() to recover the
/// original millisecond value.
pub fn timestampFromV7(u: UUID) Error!Timestamp {
    if (u.version() != .v7) return Error.InvalidVersion;
    // unix_ts_ms is in bytes 0-5 (48 bits, big-endian)
    const hi: u64 = std.mem.readInt(u32, u.bytes[0..4], .big);
    const lo: u64 = std.mem.readInt(u16, u.bytes[4..6], .big);
    const ms: i64 = @intCast((hi << 16) | lo);
    return Timestamp.fromUnixMs(ms);
}

// =============================================================================
// Tests
// =============================================================================

test "Timestamp now() is after Unix epoch" {
    const ts = try Timestamp.now();
    try std.testing.expect(ts.value > Timestamp.gregorian_offset);
}

test "Timestamp now() pre-1970 guard (F-7)" {
    // We can't easily mock std.time, but we can verify fromUnixNano rejects negative ns.
    const result = Timestamp.fromUnixNano(-1);
    try std.testing.expectError(Error.InvalidTimestamp, result);
}

test "Timestamp fromUnixMs: negative ms returns error (F-7)" {
    try std.testing.expectError(Error.InvalidTimestamp, Timestamp.fromUnixMs(-1));
}

test "Timestamp round-trip through Unix nanoseconds" {
    const ts = try Timestamp.now();
    const ns = ts.toUnixNano();
    const ts2 = try Timestamp.fromUnixNano(ns);
    // Allow 1 interval (100ns) of rounding error
    const diff = if (ts.value > ts2.value) ts.value - ts2.value else ts2.value - ts.value;
    try std.testing.expect(diff <= 1);
}

test "Timestamp.toUnixMs round-trip (G-5)" {
    const ms_in: i64 = 1_700_000_000_000; // 2023-11-14
    const ts = try Timestamp.fromUnixMs(ms_in);
    const ms_out = ts.toUnixMs();
    try std.testing.expectEqual(ms_in, ms_out);
}

test "Timestamp.toUnixSec round-trip (G-5)" {
    const ms_in: i64 = 1_700_000_000_000;
    const ts = try Timestamp.fromUnixMs(ms_in);
    const sec = ts.toUnixSec();
    try std.testing.expectEqual(@as(i64, 1_700_000_000), sec);
}

test "Timestamp.toUnixNano is consistent with toUnixMs (G-5)" {
    const ts = try Timestamp.now();
    const ns = ts.toUnixNano();
    const ms = ts.toUnixMs();
    try std.testing.expectEqual(@divTrunc(ns, 1_000_000), ms);
}

test "timestampFromV1: RFC Appendix B vector" {
    // RFC-9562 Appendix B V1 test vector: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
    // This is the DNS namespace UUID which happens to be a valid V1 UUID
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const ts = try timestampFromV1(u);
    // time_low=0x6ba7b810, time_mid=0x9dad, time_high=0x11d1&0x0FFF=0x1d1
    // ts = (0x1d1 << 48) | (0x9dad << 32) | 0x6ba7b810
    const expected: u60 = (@as(u60, 0x1d1) << 48) | (@as(u60, 0x9dad) << 32) | 0x6ba7b810;
    try std.testing.expectEqual(expected, ts.value);
}

test "timestampFromV6: bit reassembly is correct" {
    // Build a V6 UUID with a known 60-bit Gregorian timestamp value.
    // ts = 0x1d19dad6ba7b810 (same bit pattern as DNS namespace V1 reassembled to V6)
    // Encode it manually: hi=bits28-59, mid=bits12-27, low=bits0-11
    const ts_known: u60 = 0x1d19dad6ba7b810;
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    std.mem.writeInt(u32, u.bytes[0..4], @truncate(ts_known >> 28), .big);
    std.mem.writeInt(u16, u.bytes[4..6], @truncate((ts_known >> 12) & 0xFFFF), .big);
    std.mem.writeInt(u16, u.bytes[6..8], @truncate(ts_known & 0x0FFF), .big);
    u.setVersion(.v6);
    u.setVariant(.rfc9562);
    const ts = try timestampFromV6(u);
    try std.testing.expectEqual(ts_known, ts.value);
}

test "timestampFromV7: returns Timestamp with correct Unix ms (G-4)" {
    // Build a V7 UUID with known timestamp (1000 ms = 0x3E8)
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    const ms: u64 = 1000;
    std.mem.writeInt(u32, u.bytes[0..4], @truncate(ms >> 16), .big);
    std.mem.writeInt(u16, u.bytes[4..6], @truncate(ms), .big);
    u.setVersion(.v7);
    u.setVariant(.rfc9562);
    const ts = try timestampFromV7(u);
    // Recover Unix ms via toUnixMs() and verify
    try std.testing.expectEqual(@as(i64, 1000), ts.toUnixMs());
}

test "timestampFromV7: large real-world timestamp (G-4)" {
    const ms_in: i64 = 1_700_000_000_000; // 2023-11-14
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    const ms_u: u64 = @intCast(ms_in);
    std.mem.writeInt(u32, u.bytes[0..4], @truncate(ms_u >> 16), .big);
    std.mem.writeInt(u16, u.bytes[4..6], @truncate(ms_u), .big);
    u.setVersion(.v7);
    u.setVariant(.rfc9562);
    const ts = try timestampFromV7(u);
    try std.testing.expectEqual(ms_in, ts.toUnixMs());
}

test "timestampFromV1: error on wrong version" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVersion(.v4);
    try std.testing.expectError(Error.InvalidVersion, timestampFromV1(u));
}

test "timestampFromV6: error on wrong version (QC-37)" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVersion(.v4);
    try std.testing.expectError(Error.InvalidVersion, timestampFromV6(u));
}

test "timestampFromV7: error on wrong version (QC-37)" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVersion(.v4);
    try std.testing.expectError(Error.InvalidVersion, timestampFromV7(u));
}

test "Timestamp.toUnixMs: i64 cast is safe at extreme u60 values (SEC-R2-15/#48)" {
    // Max u60 value → far future (year ~5236): fits in i64
    const ts_max = Timestamp{ .value = std.math.maxInt(u60) };
    const ms_max = ts_max.toUnixMs();
    try std.testing.expect(ms_max > 0);
    try std.testing.expect(ms_max < std.math.maxInt(i64));

    // value = 0 (before Gregorian epoch): negative ms, fits in i64
    const ts_zero = Timestamp{ .value = 0 };
    const ms_zero = ts_zero.toUnixMs();
    try std.testing.expect(ms_zero < 0);
    try std.testing.expect(ms_zero > std.math.minInt(i64));
}
