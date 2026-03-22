// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const json = @import("json");
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
    pub fn format(self: NullUUID, w: *std.io.Writer) std.io.Writer.Error!void {
        if (!self.valid) {
            try w.writeAll("null");
        } else {
            try self.uuid.format(w);
        }
    }

    /// json library custom marshaler.
    /// Emits JSON null (invalid) or "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" (valid).
    pub fn jsonMarshal(self: NullUUID, allocator: std.mem.Allocator) !json.Value {
        if (!self.valid) return .null;
        var buf: [36]u8 = undefined;
        return .{ .str = try allocator.dupe(u8, self.uuid.toString(&buf)) };
    }

    /// json library custom unmarshaler.
    /// allocator parameter exists for interface conformance; UUID.fromString is zero-alloc.
    pub fn jsonUnmarshal(allocator: std.mem.Allocator, v: json.Value) !NullUUID {
        _ = allocator;
        return switch (v) {
            .null => .{},
            .str => |s| .{ .uuid = try UUID.fromString(s), .valid = true },
            else => Error.InvalidFormat,
        };
    }
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

test "NullUUID.jsonMarshal: null when invalid" {
    const alloc = std.testing.allocator;
    const nu = NullUUID{};
    const v = try nu.jsonMarshal(alloc);
    try std.testing.expect(v == .null);
}

test "NullUUID.jsonMarshal: string when valid" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const nu = NullUUID.from(u);
    const v = try nu.jsonMarshal(alloc);
    defer alloc.free(v.str);
    try std.testing.expect(v == .str);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", v.str);
}

test "NullUUID.jsonUnmarshal: null input → invalid NullUUID" {
    const nu = try NullUUID.jsonUnmarshal(std.testing.allocator, .null);
    try std.testing.expect(!nu.valid);
}

test "NullUUID.jsonUnmarshal: non-string non-null input → error" {
    const v = json.Value{ .bool = true };
    try std.testing.expectError(Error.InvalidFormat, NullUUID.jsonUnmarshal(std.testing.allocator, v));
}

test "NullUUID.jsonUnmarshal: string input → valid NullUUID" {
    const v = json.Value{ .str = "6ba7b810-9dad-11d1-80b4-00c04fd430c8" };
    const nu = try NullUUID.jsonUnmarshal(std.testing.allocator, v);
    try std.testing.expect(nu.valid);
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        nu.uuid.toString(&buf),
    );
}

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
