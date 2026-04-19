// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const builtin = @import("builtin");
const Error = @import("../uuid.zig").Error;
const hwaddr = @import("hwaddr.zig");

pub const c = struct {
    pub extern "c" fn getifaddrs(ifap: **ifaddrs) c_int;
    pub extern "c" fn freeifaddrs(ifp: *ifaddrs) void;

    pub const AF_LINK: u8 = 18;
    pub const IFF_LOOPBACK: u32 = 0x8;
    pub const IFF_UP: u32 = 0x1;

    pub const sockaddr = extern struct {
        sa_len: u8,
        sa_family: u8,
        sa_data: [14]u8,
    };

    pub const sockaddr_dl = extern struct {
        sdl_len: u8,
        sdl_family: u8,
        sdl_index: u16,
        sdl_type: u8,
        sdl_nlen: u8,
        sdl_alen: u8,
        sdl_slen: u8,
        // SEC-7 / CWE-131: the Apple SDK header declares sdl_data as [12]u8
        // (the MINSOCKADDRLEN placeholder), but the kernel allocates enough
        // space for the interface name (up to IFNAMSIZ=16 bytes) followed by
        // the MAC address (sdl_alen=6 bytes).  With [12]u8 any interface whose
        // name is longer than 6 characters is silently skipped by the bounds
        // guard below, causing NoHWAddressFound even when a valid MAC exists.
        //
        // We declare sdl_data as [22]u8 (IFNAMSIZ=16 + max sdl_alen=6) which
        // covers all valid names.  We are casting from kernel-allocated memory,
        // so reading within sdl_len is always safe.  The sdl_len-based guard
        // below is the primary safety check.
        sdl_data: [22]u8,
    };

    pub const ifaddrs = extern struct {
        ifa_next: ?*ifaddrs,
        ifa_name: [*:0]const u8,
        ifa_flags: u32,
        ifa_addr: ?*sockaddr,
        ifa_netmask: ?*sockaddr,
        ifa_dstaddr: ?*sockaddr,
        ifa_data: ?*anyopaque,
    };
};

pub fn getHWAddr() Error![6]u8 {
    var ifap: *c.ifaddrs = undefined;
    if (c.getifaddrs(&ifap) != 0) return Error.NoHWAddressFound;
    defer c.freeifaddrs(ifap);

    var it: ?*c.ifaddrs = ifap;
    while (it) |ifa| : (it = ifa.ifa_next) {
        // Skip loopback and down interfaces
        if (ifa.ifa_flags & c.IFF_LOOPBACK != 0) continue;
        if (ifa.ifa_flags & c.IFF_UP == 0) continue;

        const addr = ifa.ifa_addr orelse continue;
        if (addr.sa_family != c.AF_LINK) continue;

        const sdl: *c.sockaddr_dl = @ptrCast(@alignCast(addr));
        if (parseSockaddrDlMac(sdl)) |mac| return mac;
    }
    return Error.NoHWAddressFound;
}

/// QC-114: Pure parser for a `sockaddr_dl` structure (BSD link-layer address).
///
/// Performs the SEC-7 / CWE-131 bounds checks and `isUsableMac` filtering
/// without needing `getifaddrs(3)`. Returns `null` when:
///   - `sdl_alen` is not 6 (non-Ethernet link types like loopback / PPP);
///   - the kernel-reported `sdl_len` is too small to contain the name + MAC;
///   - the MAC lies outside our declared `sdl_data` backing array;
///   - the MAC is all-zero or broadcast (RFC 4122 §4.1.6).
///
/// Only the bytes inside `[0, sdl_len)` are read, matching the kernel
/// allocation contract.
pub fn parseSockaddrDlMac(sdl: *const c.sockaddr_dl) ?[6]u8 {
    if (sdl.sdl_alen != 6) return null;

    // MAC follows the interface name in sdl_data.
    // Primary bounds guard: use sdl_len (the kernel-authoritative total
    // struct size) to confirm that the name + MAC bytes fit within the
    // actual allocation.  The fixed-size header occupies header_size bytes,
    // so the data region is sdl_len - header_size bytes long.
    const mac_offset: usize = sdl.sdl_nlen;
    const header_size: usize = @offsetOf(c.sockaddr_dl, "sdl_data");
    if (@as(usize, sdl.sdl_len) < header_size + mac_offset + 6) return null;
    // Secondary guard against our declared array size (defensive):
    if (mac_offset + 6 > sdl.sdl_data.len) return null;
    const mac = sdl.sdl_data[mac_offset .. mac_offset + 6];
    // QC-98 / SEC-R6-03: skip all-zero and broadcast MACs via the shared
    // predicate in hwaddr.zig (RFC 4122 §4.1.6).
    if (!hwaddr.isUsableMac(mac[0..6])) return null;

    var result: [6]u8 = undefined;
    @memcpy(&result, mac);
    return result;
}

// =============================================================================
// QC-114 — byte-level parser tests.
//
// These synthesize `sockaddr_dl` values in Zig stack memory and run them
// through `parseSockaddrDlMac`. No `getifaddrs` syscall is invoked, so the
// tests work as cross-compile smoke coverage; they also run natively when
// building for macOS or iOS.
// =============================================================================

/// Build a `sockaddr_dl` with a given interface name, MAC, and sdl_len override.
/// `override_sdl_len`: pass `null` to let the helper compute the
/// kernel-authoritative size (header + name + mac); pass a specific value
/// to simulate a short/truncated report.
fn makeSockaddrDl(
    name: []const u8,
    mac: [6]u8,
    sdl_alen: u8,
    override_sdl_len: ?u8,
) c.sockaddr_dl {
    std.debug.assert(name.len <= 16);
    var sdl: c.sockaddr_dl = .{
        .sdl_len = 0,
        .sdl_family = c.AF_LINK,
        .sdl_index = 1,
        .sdl_type = 0,
        .sdl_nlen = @intCast(name.len),
        .sdl_alen = sdl_alen,
        .sdl_slen = 0,
        .sdl_data = @splat(0),
    };
    @memcpy(sdl.sdl_data[0..name.len], name);
    if (sdl_alen == 6) {
        @memcpy(sdl.sdl_data[name.len .. name.len + 6], &mac);
    }
    const header_size = @offsetOf(c.sockaddr_dl, "sdl_data");
    const computed: usize = header_size + name.len + sdl_alen;
    sdl.sdl_len = override_sdl_len orelse @intCast(computed);
    return sdl;
}

test "QC-114 macos: parseSockaddrDlMac extracts MAC after 8-char iface name" {
    // "enp0s20f0" — real-world interface name length > 6 bytes (SEC-7 regression).
    const sdl = makeSockaddrDl(
        "enp0s20f0",
        .{ 0x3c, 0x97, 0x0e, 0x12, 0x34, 0x56 },
        6,
        null,
    );
    const mac = parseSockaddrDlMac(&sdl) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x3c, 0x97, 0x0e, 0x12, 0x34, 0x56 },
        &mac,
    );
    try std.testing.expect(hwaddr.isUsableMac(&mac));
}

test "QC-114 macos: parseSockaddrDlMac rejects non-Ethernet and unusable MACs" {
    // sdl_alen != 6 → non-Ethernet (loopback has alen 0, IPoIB has alen 20).
    const loopback = makeSockaddrDl("lo0", .{ 0, 0, 0, 0, 0, 0 }, 0, null);
    try std.testing.expectEqual(@as(?[6]u8, null), parseSockaddrDlMac(&loopback));

    const ipoib = makeSockaddrDl("ib0", .{ 0, 0, 0, 0, 0, 0 }, 20, null);
    try std.testing.expectEqual(@as(?[6]u8, null), parseSockaddrDlMac(&ipoib));

    // All-zero MAC (inactive tunnel) → skip.
    const zero = makeSockaddrDl("en0", .{ 0, 0, 0, 0, 0, 0 }, 6, null);
    try std.testing.expectEqual(@as(?[6]u8, null), parseSockaddrDlMac(&zero));

    // Broadcast MAC (RFC 4122 §4.1.6) → skip.
    const bcast = makeSockaddrDl("en0", @splat(0xFF), 6, null);
    try std.testing.expectEqual(@as(?[6]u8, null), parseSockaddrDlMac(&bcast));
}

test "QC-114 macos: parseSockaddrDlMac respects sdl_len bounds (CWE-131)" {
    const header_size = @offsetOf(c.sockaddr_dl, "sdl_data");

    // Truncated sdl_len: kernel claims a size that does NOT cover
    // name(9) + mac(6) = 15 bytes of data. We report a size that only
    // covers the header + name (no MAC room). Must reject.
    const short_len: u8 = @intCast(header_size + 9);
    const truncated = makeSockaddrDl(
        "enp0s20f0",
        .{ 0x3c, 0x97, 0x0e, 0x12, 0x34, 0x56 },
        6,
        short_len,
    );
    try std.testing.expectEqual(@as(?[6]u8, null), parseSockaddrDlMac(&truncated));

    // Exactly header_size (no data at all) → reject.
    const header_only = makeSockaddrDl("", .{ 0, 0, 0, 0, 0, 0 }, 6, @intCast(header_size));
    try std.testing.expectEqual(@as(?[6]u8, null), parseSockaddrDlMac(&header_only));

    // Oversized name (would push MAC past sdl_data.len) → reject.
    // sdl_data.len == 22; MAC offset would need ≥17 for this to trip.
    var oversized: c.sockaddr_dl = .{
        .sdl_len = 0,
        .sdl_family = c.AF_LINK,
        .sdl_index = 1,
        .sdl_type = 0,
        .sdl_nlen = 17, // 17 + 6 = 23 > sdl_data.len (22) → must reject
        .sdl_alen = 6,
        .sdl_slen = 0,
        .sdl_data = @splat(0xAB),
    };
    oversized.sdl_len = @intCast(header_size + 17 + 6);
    try std.testing.expectEqual(@as(?[6]u8, null), parseSockaddrDlMac(&oversized));

    // Sanity: a correctly-sized empty-name MAC works (regression for the
    // header_only case above when len is bumped to include the MAC).
    const ok = makeSockaddrDl("", .{ 0x02, 0x00, 0x00, 0x00, 0x00, 0x01 }, 6, null);
    const mac = parseSockaddrDlMac(&ok) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0x02), mac[0]);
}
