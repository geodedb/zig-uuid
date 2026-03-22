// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const Error = @import("../uuid.zig").Error;

const c = struct {
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
        if (sdl.sdl_alen != 6) continue;

        // MAC follows the interface name in sdl_data.
        // Primary bounds guard: use sdl_len (the kernel-authoritative total
        // struct size) to confirm that the name + MAC bytes fit within the
        // actual allocation.  The fixed-size header occupies 8 bytes, so the
        // data region is sdl_len - 8 bytes long.
        const mac_offset: usize = sdl.sdl_nlen;
        const header_size: usize = @offsetOf(c.sockaddr_dl, "sdl_data"); // validated by compiler
        if (@as(usize, sdl.sdl_len) < header_size + mac_offset + 6) continue;
        // Secondary guard against our declared array size (defensive):
        if (mac_offset + 6 > sdl.sdl_data.len) continue;
        const mac = sdl.sdl_data[mac_offset .. mac_offset + 6];
        if (std.mem.allEqual(u8, mac, 0)) continue;
        // SEC-R6-03: Skip broadcast MAC (FF:FF:FF:FF:FF:FF) per RFC 4122 §4.1.6.
        if (std.mem.allEqual(u8, mac, 0xFF)) continue;

        var result: [6]u8 = undefined;
        @memcpy(&result, mac);
        return result;
    }
    return Error.NoHWAddressFound;
}
