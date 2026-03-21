// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

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
