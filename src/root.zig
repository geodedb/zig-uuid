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
//! std.debug.print("{f}\n", .{u});          // {f} specifier — no stack buffer needed (Zig 0.16+)
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
/// SEC-P3-05: closed-set namespace enum for `newV3Strict` / `newV5Strict`.
pub const Namespace = @import("namespace.zig").Namespace;
/// SEC-P4-04: runtime trusted-origin allowlist for `Namespace.fromConfig`.
pub const registerTrustedNamespaceOrigin = @import("trusted_namespace_origins.zig").registerTrustedNamespaceOrigin;

// Generator
pub const Generator = @import("generator.zig").Generator;
pub const GeneratorInterface = @import("generator.zig").GeneratorInterface;
/// PERF-31: comptime-generic, zero-indirection generator interface.  See
/// `src/generator.zig` for the trade-off vs. the vtable-based
/// `GeneratorInterface`.
pub const GeneratorInterfaceFor = @import("generator.zig").GeneratorInterfaceFor;
// SEC-R5-01 / QC-100: `default_generator` is not re-exported as a value
// (that would create a VALUE COPY — a separate Generator at a different
// address — defeating the shared-state intent).  Instead, the
// `defaultGenerator()` function (re-exported below) returns a pointer to
// the one true `default_generator`, and a set of parity wrappers
// (`clearNodeCache`, `reseed`, `saveState`, `loadState`, `initV3Namespace`,
// `initV5Namespace`) operate on that same instance at the module level.
//
// For callers who need a different clock / rand / hwaddr source or an
// isolated state file, construct their own `Generator` instance:
//
//   const uuid = @import("uuid");
//   var gen = uuid.Generator.init();
//   try gen.loadState("/var/lib/app/uuid.state");
//   const u = try gen.newV7();

// Package-level convenience functions
pub const newV1 = @import("versions.zig").newV1;
pub const newV1AtTime = @import("versions.zig").newV1AtTime;
pub const newV3 = @import("versions.zig").newV3;
pub const newV3Strict = @import("versions.zig").newV3Strict;
/// SEC-P4-12: bounded V3 wrapper (`Error.NameTooLong` above `max_len`).
pub const newV3Bounded = @import("versions.zig").newV3Bounded;
pub const newV4 = @import("versions.zig").newV4;
pub const newV5 = @import("versions.zig").newV5;
pub const newV5Strict = @import("versions.zig").newV5Strict;
/// SEC-P4-12: bounded V5 wrapper (`Error.NameTooLong` above `max_len`).
pub const newV5Bounded = @import("versions.zig").newV5Bounded;
pub const newV6 = @import("versions.zig").newV6;
pub const newV6AtTime = @import("versions.zig").newV6AtTime;
pub const newV7 = @import("versions.zig").newV7;
pub const newV7AtTime = @import("versions.zig").newV7AtTime;
pub const newV8 = @import("versions.zig").newV8;

// QC-100: default_generator state-management parity wrappers.
//
// These expose the state-bearing methods of the process-global
// `default_generator` at the module level, so callers using the
// convenience `uuid.newV*` family can also `uuid.reseed()` after
// fork, `uuid.loadState(path)` on startup, etc. without constructing
// their own Generator instance. Use `uuid.defaultGenerator()` if you
// need a `*Generator` pointer (e.g. for methods not wrapped here).
pub const defaultGenerator = @import("versions.zig").defaultGenerator;
pub const clearNodeCache = @import("versions.zig").clearNodeCache;
pub const reseed = @import("versions.zig").reseed;
pub const saveState = @import("versions.zig").saveState;
pub const loadState = @import("versions.zig").loadState;
pub const secureWipeMacKey = @import("versions.zig").secureWipeMacKey;
pub const migrateStateToV3 = @import("versions.zig").migrateStateToV3;
/// O-1 (CWE-320): rotate the HMAC key authenticating the persisted
/// state file.  Loads under the current key + configured policy,
/// zeroizes the old key slot, installs `new_key`, and writes a fresh
/// v3 file under the new key.  See `Generator.rotateStateMacKey` for
/// the full error surface and SEC-P4-01 no-downgrade invariant.
pub const rotateStateMacKey = @import("versions.zig").rotateStateMacKey;
pub const StateMacPolicy = @import("generator.zig").StateMacPolicy;
pub const initV3Namespace = @import("versions.zig").initV3Namespace;
pub const initV5Namespace = @import("versions.zig").initV5Namespace;

// Windows GUID interop (only available on Windows builds)
pub const guidToUUID = if (builtin.os.tag == .windows)
    @import("hwaddr/hwaddr.zig").guidToUUID
else
    @compileError("guidToUUID is only available on Windows");

pub const uuidToGUID = if (builtin.os.tag == .windows)
    @import("hwaddr/hwaddr.zig").uuidToGUID
else
    @compileError("uuidToGUID is only available on Windows");

pub const version = "0.1.2";

test {
    _ = @import("uuid.zig"); // transitively imports uuid_test.zig (QC-65)
    _ = @import("namespace.zig");
    _ = @import("timestamp.zig");
    _ = @import("generator.zig"); // transitively imports generator_test.zig (QC-4)
    _ = @import("versions.zig");
    _ = @import("null_uuid.zig");
    _ = @import("hwaddr/hwaddr.zig");
    _ = @import("fuzz.zig"); // SEC-R2-11: fuzz tests for UUID parsing
    _ = @import("trusted_namespace_origins.zig"); // SEC-P4-04
    _ = @import("crypto_backend_smoke_test.zig"); // FIPS seam smoke test
}
