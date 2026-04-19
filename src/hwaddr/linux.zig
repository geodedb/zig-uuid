// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const builtin = @import("builtin");
const Error = @import("../uuid.zig").Error;
const hwaddr = @import("hwaddr.zig");

const linux = std.os.linux;

pub const SIOCGIFCONF = 0x8912;
pub const SIOCGIFHWADDR = 0x8927;
pub const SIOCGIFFLAGS = 0x8913;
pub const IFF_LOOPBACK = 0x8;
pub const ARPHRD_ETHER = 1;

/// QC-114: Maximum number of interfaces the `SIOCGIFCONF` scratch buffer holds.
/// SEC-R2-13 chose 128 because that fits every realistic host without forcing
/// a retry loop; systems with >128 interfaces silently fall back to a random
/// multicast node (the correct privacy-preserving behaviour).
pub const MAX_IFREQ_SLOTS: usize = 128;

pub const ifreq = extern struct {
    ifr_name: [16]u8,
    // union: we read different fields depending on the ioctl
    ifr_data: [24]u8,
};

const ifconf = extern struct {
    ifc_len: c_int,
    ifc_buf: ?[*]ifreq,
};

pub fn getHWAddr() Error![6]u8 {
    const sock_ret = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    // Raw syscall: error codes are encoded as large usize values (>= maxInt(isize)).
    const sock_err = linux.errno(sock_ret);
    if (sock_err != .SUCCESS) return Error.NoHWAddressFound;
    const sock: linux.fd_t = @intCast(sock_ret);
    defer _ = linux.close(sock);

    // Get interface list.
    // SEC-R2-13: Use 128 slots instead of 64; SIOCGIFCONF truncation is not
    // detectable without a retry loop (kernel sets ifc_len to bytes used, which
    // equals buffer size when truncated). For UUID node-ID purposes (we need any
    // one non-loopback Ethernet MAC), this is sufficient for all realistic systems.
    // Systems with >128 interfaces will silently fall back to a random multicast
    // node, which is the correct privacy-preserving behaviour.
    var ifreqs: [128]ifreq = undefined;
    var ifc = ifconf{
        .ifc_len = @intCast(@sizeOf(ifreq) * ifreqs.len),
        .ifc_buf = &ifreqs,
    };
    const initial_len: c_int = ifc.ifc_len;
    const ifc_ret = linux.syscall3(
        .ioctl,
        @as(usize, @intCast(sock)),
        SIOCGIFCONF,
        @intFromPtr(&ifc),
    );
    if (ifc_ret != 0) return Error.NoHWAddressFound;
    // Detect possible truncation (informational; we still search what we got).
    // When ifc_len equals the initial buffer size, the kernel may have filled the
    // buffer completely and truncated additional interfaces.
    if (ifc.ifc_len == initial_len) {
        // PERF-24: Buffer-full truncation is extremely rare in practice
        // (typical hosts have far fewer than 128 interfaces). Mark the block
        // cold so the branch predictor keeps it off the hot path, and demote
        // the message from `warn` (visible by default) to `debug` (silent
        // unless the caller opts in) — it is an informational "you may want
        // to investigate" hint, not an error.
        @branchHint(.cold);
        // SEC-R13-06 (CWE-390): Buffer was completely filled; the kernel may
        // have truncated additional interfaces.  Log an info-level message so
        // operators on hosts with large interface counts (container
        // orchestration, VLAN deployments) who opt in to debug logging are
        // aware the node ID may be selected from an incomplete set.  We
        // continue searching what we received.
        std.log.debug("hwaddr: SIOCGIFCONF buffer full ({d} bytes); interface list may be truncated", .{initial_len});
    }

    // SEC-3 / CWE-190: ifc_len is a signed c_int; a negative value (kernel
    // bug or pathological response) would cause @intCast to panic in safe
    // builds and produce a very large count in ReleaseFast.  Delegate to the
    // QC-114 helper so the guard is unit-tested.
    const count = ifreqSlotCountFromBytes(ifc.ifc_len) orelse
        return Error.NoHWAddressFound;

    for (ifreqs[0..count]) |*ifr| {
        // Get flags to skip loopback
        var flags_req = ifr.*;
        const flags_ret = linux.syscall3(
            .ioctl,
            @as(usize, @intCast(sock)),
            SIOCGIFFLAGS,
            @intFromPtr(&flags_req),
        );
        if (flags_ret != 0) continue;
        const flags = std.mem.readInt(u16, flags_req.ifr_data[0..2], .little);
        if (flags & IFF_LOOPBACK != 0) continue;

        // Get hardware address
        var hw_req = ifr.*;
        const hw_ret = linux.syscall3(
            .ioctl,
            @as(usize, @intCast(sock)),
            SIOCGIFHWADDR,
            @intFromPtr(&hw_req),
        );
        if (hw_ret != 0) continue;

        // QC-114: byte-level parsing lives in `parseIfreqHwaddr` so the
        // validation logic can be unit-tested against synthetic buffers
        // without needing the kernel ioctl path.
        if (parseIfreqHwaddr(&hw_req.ifr_data)) |mac| {
            return mac;
        }
    }
    return Error.NoHWAddressFound;
}

/// QC-114: Pure parser for the 8 leading bytes of `struct ifreq.ifr_hwaddr`.
///
/// Accepts the whole 24-byte `ifr_data` union slot (so callers can hand us
/// the raw buffer the ioctl filled in). Returns the 6-byte MAC when:
///   - the sa_family field equals `ARPHRD_ETHER`, and
///   - the MAC passes `hwaddr.isUsableMac` (rejects all-zero and broadcast).
///
/// Returns `null` for any non-Ethernet family or unusable MAC, letting the
/// caller skip to the next interface without a syscall. Separated out so the
/// parser can be exercised with synthetic byte buffers in tests.
pub fn parseIfreqHwaddr(ifr_data: *const [24]u8) ?[6]u8 {
    const family = std.mem.readInt(u16, ifr_data[0..2], .little);
    if (family != ARPHRD_ETHER) return null;

    const mac: *const [6]u8 = ifr_data[2..8];
    if (!hwaddr.isUsableMac(mac)) return null;

    var result: [6]u8 = undefined;
    @memcpy(&result, mac);
    return result;
}

/// QC-114: Guard for the `ifc.ifc_len` field returned by `SIOCGIFCONF`.
///
/// The kernel writes bytes used; we divide by `@sizeOf(ifreq)` to get the
/// slot count. A negative value (kernel bug) must not propagate because
/// `@intCast(isize -> usize)` would panic in safe builds. Returns `null`
/// when the buffer is unusable; otherwise the clamped slot count.
pub fn ifreqSlotCountFromBytes(ifc_len: c_int) ?usize {
    if (ifc_len < 0) return null;
    const count: usize = @intCast(@divTrunc(ifc_len, @sizeOf(ifreq)));
    // SEC-R2-13 guard: never return a count larger than the scratch buffer.
    if (count > MAX_IFREQ_SLOTS) return MAX_IFREQ_SLOTS;
    return count;
}

// =============================================================================
// QC-114 — byte-level parser tests.
//
// These do not invoke any kernel syscall; they feed synthetic `ifr_data`
// buffers through `parseIfreqHwaddr` / `ifreqSlotCountFromBytes`. Safe to
// compile on every target because they only touch pure byte slices.
// =============================================================================

test "QC-114 linux: parseIfreqHwaddr accepts valid Ethernet MAC" {
    var buf: [24]u8 = @splat(0);
    // family = ARPHRD_ETHER (little-endian)
    std.mem.writeInt(u16, buf[0..2], ARPHRD_ETHER, .little);
    // MAC 02:42:ac:11:00:02 (Docker bridge style)
    buf[2] = 0x02;
    buf[3] = 0x42;
    buf[4] = 0xac;
    buf[5] = 0x11;
    buf[6] = 0x00;
    buf[7] = 0x02;

    const mac = parseIfreqHwaddr(&buf) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x02, 0x42, 0xac, 0x11, 0x00, 0x02 },
        &mac,
    );
    // And the shared predicate accepts it.
    try std.testing.expect(hwaddr.isUsableMac(&mac));
}

test "QC-114 linux: parseIfreqHwaddr rejects all-zero and broadcast MAC" {
    // Non-Ethernet family → skip (rejects non-Ethernet bus types like PPP/IPv6-tunnels).
    var tunnel: [24]u8 = @splat(0);
    std.mem.writeInt(u16, tunnel[0..2], 512, .little); // ARPHRD_PPP
    try std.testing.expectEqual(@as(?[6]u8, null), parseIfreqHwaddr(&tunnel));

    // All-zero MAC (uninitialised virtual iface) → skip.
    var zero_mac: [24]u8 = @splat(0);
    std.mem.writeInt(u16, zero_mac[0..2], ARPHRD_ETHER, .little);
    try std.testing.expectEqual(@as(?[6]u8, null), parseIfreqHwaddr(&zero_mac));

    // Broadcast MAC → skip (RFC 4122 §4.1.6).
    var bcast: [24]u8 = @splat(0);
    std.mem.writeInt(u16, bcast[0..2], ARPHRD_ETHER, .little);
    @memset(bcast[2..8], 0xFF);
    try std.testing.expectEqual(@as(?[6]u8, null), parseIfreqHwaddr(&bcast));
}

test "QC-114 linux: ifreqSlotCountFromBytes guards against negative and oversized counts" {
    // Negative ifc_len (kernel bug) must not panic-cast to usize.
    try std.testing.expectEqual(@as(?usize, null), ifreqSlotCountFromBytes(-1));
    try std.testing.expectEqual(
        @as(?usize, null),
        ifreqSlotCountFromBytes(std.math.minInt(c_int)),
    );

    // Three interfaces reported (3 * sizeof(ifreq)).
    const three_bytes: c_int = @intCast(3 * @sizeOf(ifreq));
    try std.testing.expectEqual(@as(?usize, 3), ifreqSlotCountFromBytes(three_bytes));

    // Buffer-full: the slot count is clamped to MAX_IFREQ_SLOTS even if the
    // kernel reports a byte count that would imply more entries (defence in
    // depth against arithmetic overruns on pathological responses).
    const overflow_bytes: c_int = @intCast(@sizeOf(ifreq) * (MAX_IFREQ_SLOTS + 10));
    try std.testing.expectEqual(
        @as(?usize, MAX_IFREQ_SLOTS),
        ifreqSlotCountFromBytes(overflow_bytes),
    );

    // Zero interfaces (empty system) → count 0, not null.
    try std.testing.expectEqual(@as(?usize, 0), ifreqSlotCountFromBytes(0));

    // Truncated byte count (not a multiple of sizeof(ifreq)) still rounds
    // down via @divTrunc; verifies we don't over-read the scratch buffer.
    const ifreq_size: c_int = @intCast(@sizeOf(ifreq));
    try std.testing.expectEqual(
        @as(?usize, 1),
        ifreqSlotCountFromBytes(ifreq_size + 3),
    );
}
