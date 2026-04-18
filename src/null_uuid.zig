// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const Error = @import("uuid.zig").Error;

/// A nullable UUID wrapper with JSON marshaling support.
/// Serializes to null JSON or "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".
pub const NullUUID = struct {
    uuid: UUID = UUID.nil,
    valid: bool = false,

    /// Wrap an existing UUID as a valid NullUUID.
    pub fn from(u: UUID) NullUUID {
        return .{ .uuid = u, .valid = true };
    }

    /// Return null if not valid, or the UUID value.
    pub fn value(self: NullUUID) ?UUID {
        return if (self.valid) self.uuid else null;
    }

    /// Format for use with `{f}` in std.fmt.
    /// Emits "null" when invalid, or the canonical UUID string when valid.
    pub fn format(self: NullUUID, w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (!self.valid) {
            try w.writeAll("null");
        } else {
            try self.uuid.format(w);
        }
    }

    // json adapters moved to src/uuid_json.zig (opt-in submodule).
};

test "NullUUID.from and value()" {
    const u = UUID.nil;
    const nu = NullUUID.from(u);
    try std.testing.expect(nu.valid);
    try std.testing.expect((nu.value() orelse unreachable).eql(u));
}

test "NullUUID zero value is invalid" {
    const nu = NullUUID{};
    try std.testing.expect(!nu.valid);
    try std.testing.expect(nu.value() == null);
}

// Json adapter tests live in tests/integration.zig (via the uuid_json
// submodule) so the core module stays dep-free.

test "NullUUID.format valid UUID produces canonical output (QC-55)" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const nu = NullUUID.from(u);
    const s = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{nu});
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", s);
}

test "NullUUID.format null produces 'null' (QC-55)" {
    const nu = NullUUID{};
    const s = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{nu});
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("null", s);
}
