// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const Error = @import("../uuid.zig").Error;
const UUID = @import("../uuid.zig").UUID;

const windows = std.os.windows;

// IP_ADAPTER_ADDRESSES (simplified — only fields we use)
const IP_ADAPTER_ADDRESSES = extern struct {
    Length: windows.ULONG,
    IfIndex: windows.DWORD,
    Next: ?*IP_ADAPTER_ADDRESSES,
    AdapterName: [*:0]windows.CHAR,
    FirstUnicastAddress: ?*anyopaque,
    FirstAnycastAddress: ?*anyopaque,
    FirstMulticastAddress: ?*anyopaque,
    FirstDnsServerAddress: ?*anyopaque,
    DnsSuffix: [*:0]windows.WCHAR,
    Description: [*:0]windows.WCHAR,
    FriendlyName: [*:0]windows.WCHAR,
    PhysicalAddress: [8]u8,
    PhysicalAddressLength: windows.DWORD,
    Flags: windows.DWORD,
    Mtu: windows.DWORD,
    IfType: windows.DWORD,
    OperStatus: windows.DWORD,
    // ... additional fields omitted; Length field ensures safe iteration
};

const IF_TYPE_SOFTWARE_LOOPBACK: windows.DWORD = 24;
const GAA_FLAG_NONE: windows.ULONG = 0;
const AF_UNSPEC: windows.ULONG = 0;

extern "iphlpapi" fn GetAdaptersAddresses(
    Family: windows.ULONG,
    Flags: windows.ULONG,
    Reserved: ?*anyopaque,
    AdapterAddresses: ?*IP_ADAPTER_ADDRESSES,
    SizePointer: *windows.ULONG,
) callconv(windows.WINAPI) windows.DWORD;

const ERROR_BUFFER_OVERFLOW: windows.DWORD = 111;
const NO_ERROR: windows.DWORD = 0;

pub fn getHWAddr() Error![6]u8 {
    // Use a stack buffer; 16KB is sufficient for most systems
    var buf: [16384]u8 align(@alignOf(IP_ADAPTER_ADDRESSES)) = undefined;
    var buf_size: windows.ULONG = buf.len;

    const ret = GetAdaptersAddresses(
        AF_UNSPEC,
        GAA_FLAG_NONE,
        null,
        @ptrCast(&buf),
        &buf_size,
    );
    if (ret != NO_ERROR) return Error.NoHWAddressFound;

    var it: ?*IP_ADAPTER_ADDRESSES = @ptrCast(&buf);
    while (it) |adapter| : (it = adapter.Next) {
        // Skip loopback
        if (adapter.IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
        const mac_len = adapter.PhysicalAddressLength;
        if (mac_len != 6) continue;
        const mac = adapter.PhysicalAddress[0..6];
        if (std.mem.allEqual(u8, mac, 0)) continue;
        var result: [6]u8 = undefined;
        @memcpy(&result, mac);
        return result;
    }
    return Error.NoHWAddressFound;
}

// =============================================================================
// Application-level GUID interop helpers
//
// Windows GUID stores Data1/Data2/Data3 in little-endian; RFC UUIDs are
// fully big-endian. These helpers convert at the boundary. UUID.bytes is
// always network byte order internally.
// =============================================================================

pub const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

/// Convert a Windows GUID to an RFC UUID.
/// Handles the Data1/Data2/Data3 little-endian → big-endian conversion.
pub fn guidToUUID(guid: GUID) UUID {
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4], guid.Data1, .big); // LE → BE
    std.mem.writeInt(u16, bytes[4..6], guid.Data2, .big); // LE → BE
    std.mem.writeInt(u16, bytes[6..8], guid.Data3, .big); // LE → BE
    @memcpy(bytes[8..16], &guid.Data4); // already BE
    return UUID{ .bytes = bytes };
}

/// Convert an RFC UUID to a Windows GUID.
/// Handles the big-endian → Data1/Data2/Data3 little-endian conversion.
pub fn uuidToGUID(u: UUID) GUID {
    return .{
        .Data1 = std.mem.readInt(u32, u.bytes[0..4], .big), // BE → LE
        .Data2 = std.mem.readInt(u16, u.bytes[4..6], .big),
        .Data3 = std.mem.readInt(u16, u.bytes[6..8], .big),
        .Data4 = u.bytes[8..16].*,
    };
}

test "guidToUUID and uuidToGUID round-trip" {
    const guid = GUID{
        .Data1 = 0x6ba7b810,
        .Data2 = 0x9dad,
        .Data3 = 0x11d1,
        .Data4 = .{ 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8 },
    };
    const u = guidToUUID(guid);
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        u.toString(&buf),
    );
    const guid2 = uuidToGUID(u);
    try std.testing.expectEqual(guid.Data1, guid2.Data1);
    try std.testing.expectEqual(guid.Data2, guid2.Data2);
    try std.testing.expectEqual(guid.Data3, guid2.Data3);
}
