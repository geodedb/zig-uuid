// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const builtin = @import("builtin");
const Error = @import("../uuid.zig").Error;

const linux = std.os.linux;

const SIOCGIFCONF = 0x8912;
const SIOCGIFHWADDR = 0x8927;
const SIOCGIFFLAGS = 0x8913;
const IFF_LOOPBACK = 0x8;
const ARPHRD_ETHER = 1;

const ifreq = extern struct {
    ifr_name: [16]u8,
    // union: we read different fields depending on the ioctl
    ifr_data: [24]u8,
};

const ifconf = extern struct {
    ifc_len: c_int,
    ifc_buf: ?[*]ifreq,
};

pub fn getHWAddr() Error![6]u8 {
    const sock = std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM,
        0,
    ) catch return Error.NoHWAddressFound;
    defer std.posix.close(sock);

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
        // SEC-R13-06 (CWE-390): Buffer was completely filled; the kernel may
        // have truncated additional interfaces.  Log a warning so operators on
        // hosts with large interface counts (container orchestration, VLAN
        // deployments) are aware the node ID may be selected from an incomplete
        // set.  We continue searching what we received.
        std.log.warn("hwaddr: SIOCGIFCONF buffer full ({d} bytes); interface list may be truncated", .{initial_len});
    }

    // SEC-3 / CWE-190: ifc_len is a signed c_int; a negative value (kernel
    // bug or pathological response) would cause @intCast to panic in safe
    // builds and produce a very large count in ReleaseFast.  Guard first.
    if (ifc.ifc_len < 0) return Error.NoHWAddressFound;
    const count: usize = @intCast(@divTrunc(ifc.ifc_len, @sizeOf(ifreq)));

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

        // sa_family is first 2 bytes; MAC is bytes 2-7
        const family = std.mem.readInt(u16, hw_req.ifr_data[0..2], .little);
        if (family != ARPHRD_ETHER) continue;

        const mac = hw_req.ifr_data[2..8];
        // Skip zero MAC
        if (std.mem.allEqual(u8, mac, 0)) continue;
        // SEC-R6-03: Skip broadcast MAC (FF:FF:FF:FF:FF:FF) per RFC 4122 §4.1.6.
        if (std.mem.allEqual(u8, mac, 0xFF)) continue;

        var result: [6]u8 = undefined;
        @memcpy(&result, mac);
        return result;
    }
    return Error.NoHWAddressFound;
}
