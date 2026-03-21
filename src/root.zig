// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # uuid
//!
//! A fully RFC-9562-compliant UUID library for Zig.
//!
//! Supports UUID versions V1, V3, V4, V5, V6, V7, V8 with:
//! - Injectable generator (clock, random, hardware address)
//! - Cross-platform MAC resolution (Linux, macOS, Windows)
//! - Multiple parse formats (canonical, braced, hash, URN)
//! - JSON serialization via gitlab.com/devnw/zig/json
//!
//! ## Quick Start
//!
//! ```zig
//! const uuid = @import("uuid");
//!
//! const u = try uuid.newV7();          // k-sortable timestamp UUID
//! const u4 = try uuid.newV4();         // random UUID
//! const v3 = uuid.newV3(uuid.namespace_dns, "example.com");
//!
//! var buf: [36]u8 = undefined;
//! std.debug.print("{s}\n", .{u.toString(&buf)});
//! ```

const builtin = @import("builtin");

// Core types
pub const UUID = @import("uuid.zig").UUID;
pub const Version = @import("uuid.zig").Version;
pub const Variant = @import("uuid.zig").Variant;
pub const Error = @import("uuid.zig").Error;
pub const NullUUID = @import("null_uuid.zig").NullUUID;

// Timestamp
pub const Timestamp = @import("timestamp.zig").Timestamp;
pub const timestampFromV1 = @import("timestamp.zig").timestampFromV1;
pub const timestampFromV6 = @import("timestamp.zig").timestampFromV6;
pub const timestampFromV7 = @import("timestamp.zig").timestampFromV7;

// Namespace constants
pub const nil = @import("namespace.zig").nil;
pub const max = @import("namespace.zig").max;
pub const namespace_dns = @import("namespace.zig").namespace_dns;
pub const namespace_url = @import("namespace.zig").namespace_url;
pub const namespace_oid = @import("namespace.zig").namespace_oid;
pub const namespace_x500 = @import("namespace.zig").namespace_x500;

// Generator
pub const Generator = @import("generator.zig").Generator;
pub const GeneratorInterface = @import("generator.zig").GeneratorInterface;
pub const default_generator = @import("generator.zig").default_generator;

// Package-level convenience functions
pub const newV1 = @import("versions.zig").newV1;
pub const newV1AtTime = @import("versions.zig").newV1AtTime;
pub const newV3 = @import("versions.zig").newV3;
pub const newV4 = @import("versions.zig").newV4;
pub const newV5 = @import("versions.zig").newV5;
pub const newV6 = @import("versions.zig").newV6;
pub const newV6AtTime = @import("versions.zig").newV6AtTime;
pub const newV7 = @import("versions.zig").newV7;
pub const newV7AtTime = @import("versions.zig").newV7AtTime;
pub const newV8 = @import("versions.zig").newV8;

// Windows GUID interop (only available on Windows builds)
pub const guidToUUID = if (builtin.os.tag == .windows)
    @import("hwaddr/hwaddr.zig").guidToUUID
else
    @compileError("guidToUUID is only available on Windows");

pub const uuidToGUID = if (builtin.os.tag == .windows)
    @import("hwaddr/hwaddr.zig").uuidToGUID
else
    @compileError("uuidToGUID is only available on Windows");

pub const version = "0.1.0";

test {
    _ = @import("uuid.zig");
    _ = @import("namespace.zig");
    _ = @import("timestamp.zig");
    _ = @import("generator.zig");
    _ = @import("versions.zig");
    _ = @import("null_uuid.zig");
    _ = @import("hwaddr/hwaddr.zig");
}
