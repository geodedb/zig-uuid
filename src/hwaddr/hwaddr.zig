// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const builtin = @import("builtin");
const Error = @import("../uuid.zig").Error;
const UUID = @import("../uuid.zig").UUID;

/// Get a hardware (MAC) address from the first suitable network interface.
/// Returns Error.NoHWAddressFound if no interface is available.
/// Cross-compiled safely: each platform branch is only evaluated for its target.
pub fn get() Error![6]u8 {
    if (builtin.os.tag == .linux) return @import("linux.zig").getHWAddr();
    if (builtin.os.tag == .macos or builtin.os.tag == .ios) return @import("macos.zig").getHWAddr();
    if (builtin.os.tag == .windows) return @import("windows.zig").getHWAddr();
    return Error.NoHWAddressFound;
}

/// QC-98 (SEC-R6-03): Shared predicate used by every platform backend.
/// Returns `true` iff `mac` is a usable MAC for UUID node-ID purposes:
/// not the all-zero placeholder (tunnel / virtual / uninitialized
/// interfaces) and not the broadcast address FF:FF:FF:FF:FF:FF, both of
/// which RFC 4122 §4.1.6 excludes.
pub fn isUsableMac(mac: *const [6]u8) bool {
    if (std.mem.allEqual(u8, mac, 0)) return false;
    if (std.mem.allEqual(u8, mac, 0xFF)) return false;
    return true;
}

test "isUsableMac: rejects all-zero" {
    const zero: [6]u8 = .{ 0, 0, 0, 0, 0, 0 };
    try std.testing.expect(!isUsableMac(&zero));
}

test "isUsableMac: rejects all-FF" {
    const broadcast: [6]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    try std.testing.expect(!isUsableMac(&broadcast));
}

test "isUsableMac: accepts arbitrary MAC" {
    const normal: [6]u8 = .{ 0x02, 0x42, 0xAC, 0x11, 0x00, 0x02 };
    try std.testing.expect(isUsableMac(&normal));
}

test "isUsableMac: accepts partially-zero MAC" {
    const partial: [6]u8 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 };
    try std.testing.expect(isUsableMac(&partial));
}

// Re-export GUID interop helpers (Windows only — guarded at call site via comptime)
pub const guidToUUID = if (builtin.os.tag == .windows)
    @import("windows.zig").guidToUUID
else
    @compileError("guidToUUID is only available on Windows");

pub const uuidToGUID = if (builtin.os.tag == .windows)
    @import("windows.zig").uuidToGUID
else
    @compileError("uuidToGUID is only available on Windows");

test "hwaddr.get() returns 6-byte array or NoHWAddressFound" {
    const result = get();
    if (result) |mac| {
        try @import("std").testing.expectEqual(@as(usize, 6), mac.len);
    } else |err| {
        try @import("std").testing.expectEqual(Error.NoHWAddressFound, err);
    }
}

// QC-114: pull every per-OS backend into the test graph so the pure
// byte-level parser tests (`parseIfreqHwaddr`, `parseSockaddrDlMac`,
// `findMacInAdapters`) run on every native target. The imported files only
// declare extern OS syscalls; tests never reference those declarations, so
// the link edge is never created and the same Linux host can compile+run
// the macOS/Windows parser tests.
test {
    _ = @import("linux.zig");
    _ = @import("macos.zig");
    _ = @import("windows.zig");
}
