// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const Error = @import("uuid.zig").Error;

/// 100-nanosecond intervals since 1582-10-15 (Gregorian epoch).
/// Used exclusively by V1 and V6. V7 uses bare i64 Unix milliseconds.
pub const Timestamp = struct {
    value: u60,

    /// Offset between Gregorian epoch (1582-10-15) and Unix epoch (1970-01-01)
    /// in 100-ns intervals.
    pub const gregorian_offset: u64 = 122_192_928_000_000_000;

    /// Current time as a Gregorian Timestamp.
    pub fn now() Timestamp {
        const ns: i128 = std.time.nanoTimestamp();
        const intervals_since_unix: u64 = @intCast(@divTrunc(ns, 100));
        return .{ .value = @truncate(intervals_since_unix + gregorian_offset) };
    }

    /// Convert to Unix nanoseconds for interop with std.time.
    pub fn toUnixNano(self: Timestamp) i128 {
        const intervals: i128 = @as(i128, self.value) - gregorian_offset;
        return intervals * 100;
    }

    /// Create from Unix nanoseconds.
    pub fn fromUnixNano(ns: i128) Timestamp {
        const intervals_since_unix: u64 = @intCast(@divTrunc(ns, 100));
        return .{ .value = @truncate(intervals_since_unix + gregorian_offset) };
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

/// Extract Unix millisecond timestamp from a V7 UUID.
/// Returns i64 (not Timestamp) — V7 uses Unix epoch, not Gregorian epoch.
pub fn timestampFromV7(u: UUID) Error!i64 {
    if (u.version() != .v7) return Error.InvalidVersion;
    // unix_ts_ms is in bytes 0-5 (48 bits, big-endian)
    const hi: u64 = std.mem.readInt(u32, u.bytes[0..4], .big);
    const lo: u64 = std.mem.readInt(u16, u.bytes[4..6], .big);
    return @intCast((hi << 16) | lo);
}

test "Timestamp now() is after Unix epoch" {
    const ts = Timestamp.now();
    try std.testing.expect(ts.value > Timestamp.gregorian_offset);
}

test "Timestamp round-trip through Unix nanoseconds" {
    const ts = Timestamp.now();
    const ns = ts.toUnixNano();
    const ts2 = Timestamp.fromUnixNano(ns);
    // Allow 1 interval (100ns) of rounding error
    const diff = if (ts.value > ts2.value) ts.value - ts2.value else ts2.value - ts.value;
    try std.testing.expect(diff <= 1);
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

test "timestampFromV7: extracts Unix ms" {
    // Build a V7 UUID with known timestamp (1000 ms = 0x3E8)
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    const ms: u64 = 1000;
    std.mem.writeInt(u32, u.bytes[0..4], @truncate(ms >> 16), .big);
    std.mem.writeInt(u16, u.bytes[4..6], @truncate(ms), .big);
    u.setVersion(.v7);
    u.setVariant(.rfc9562);
    const extracted = try timestampFromV7(u);
    try std.testing.expectEqual(@as(i64, 1000), extracted);
}

test "timestampFromV1: error on wrong version" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVersion(.v4);
    try std.testing.expectError(Error.InvalidVersion, timestampFromV1(u));
}
