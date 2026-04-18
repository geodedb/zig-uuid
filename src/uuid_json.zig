// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros
//
// Opt-in json adapter for uuid/NullUUID. Split out of uuid.zig / null_uuid.zig
// so the core `uuid` module can be instantiated from multiple consumer build
// contexts without bringing a transitive `json` import. Consumers that want
// the adapter depend on the separate `uuid_json` module exposed by uuid's
// build.zig.

const std = @import("std");
const json = @import("json");
const uuid_pkg = @import("uuid");

pub const UUID = uuid_pkg.UUID;
pub const NullUUID = uuid_pkg.NullUUID;
pub const Error = uuid_pkg.Error;

/// Marshal a UUID to a `json.Value.str` with the canonical lowercase string.
/// The returned `.str` is heap-allocated with `allocator`; caller must free
/// (typically via `json.Value.deinit`).
pub fn uuidJsonMarshal(self: UUID, allocator: std.mem.Allocator) !json.Value {
    var buf: [36]u8 = undefined;
    return .{ .str = try allocator.dupe(u8, self.toString(&buf)) };
}

/// Parse a UUID from a `json.Value.str`. Returns `Error.InvalidFormat` if
/// the value is not a string or cannot be parsed as a UUID.
/// `allocator` is unused (kept for interface conformance).
pub fn uuidJsonUnmarshal(allocator: std.mem.Allocator, v: json.Value) !UUID {
    _ = allocator;
    if (v != .str) return Error.InvalidFormat;
    return UUID.fromString(v.str);
}

/// Marshal a NullUUID. Emits JSON null when invalid, canonical UUID string
/// when valid. String payload is heap-allocated with `allocator`.
pub fn nullUuidJsonMarshal(self: NullUUID, allocator: std.mem.Allocator) !json.Value {
    if (!self.valid) return .null;
    var buf: [36]u8 = undefined;
    return .{ .str = try allocator.dupe(u8, self.uuid.toString(&buf)) };
}

/// Parse a NullUUID. Accepts JSON null or a canonical UUID string.
/// Returns `Error.InvalidFormat` for any other value type.
pub fn nullUuidJsonUnmarshal(allocator: std.mem.Allocator, v: json.Value) !NullUUID {
    _ = allocator;
    return switch (v) {
        .null => .{},
        .str => |s| .{ .uuid = try UUID.fromString(s), .valid = true },
        else => Error.InvalidFormat,
    };
}

test "uuidJsonMarshal produces canonical string" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const v = try uuidJsonMarshal(u, alloc);
    defer alloc.free(v.str);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", v.str);
}

test "uuidJsonUnmarshal parses canonical string" {
    const u = try uuidJsonUnmarshal(std.testing.allocator, json.Value{ .str = "6ba7b810-9dad-11d1-80b4-00c04fd430c8" });
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", u.toString(&buf));
}

test "nullUuidJsonMarshal: null when invalid" {
    const alloc = std.testing.allocator;
    const nu = NullUUID{};
    const v = try nullUuidJsonMarshal(nu, alloc);
    try std.testing.expect(v == .null);
}

test "nullUuidJsonMarshal: string when valid" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const nu = NullUUID.from(u);
    const v = try nullUuidJsonMarshal(nu, alloc);
    defer alloc.free(v.str);
    try std.testing.expect(v == .str);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", v.str);
}

test "nullUuidJsonUnmarshal: null input -> invalid" {
    const nu = try nullUuidJsonUnmarshal(std.testing.allocator, .null);
    try std.testing.expect(!nu.valid);
}

test "nullUuidJsonUnmarshal: string input -> valid" {
    const v = json.Value{ .str = "6ba7b810-9dad-11d1-80b4-00c04fd430c8" };
    const nu = try nullUuidJsonUnmarshal(std.testing.allocator, v);
    try std.testing.expect(nu.valid);
}

test "nullUuidJsonUnmarshal: non-string non-null -> error" {
    const v = json.Value{ .bool = true };
    try std.testing.expectError(Error.InvalidFormat, nullUuidJsonUnmarshal(std.testing.allocator, v));
}
