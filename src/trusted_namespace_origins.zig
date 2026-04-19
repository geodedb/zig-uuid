// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// SEC-P4-04: process-global trusted-namespace-origin allowlist for
// `Namespace.fromConfig`.  Mirrors the CAS-once-init pattern used by
// `UUID.ProcessHashContext` (src/uuid.zig).
//
// The allowlist is append-only — `registerTrustedNamespaceOrigin`
// stores the origin string under an internal mutex, and
// `isTrusted(origin)` scans linearly.  Append-only means a configured
// process never loses trust over time; a reseed/fork-clean pattern is
// explicitly NOT provided, because the allowlist is a startup
// configuration (not a rotating-capability).
//
// Capacity is fixed at `max_trusted_origins` — 16 is enough for any
// realistic config-flag vocabulary (tenant-id, api-key-prefix, etc.)
// and keeps the linear scan cheap.  Registering a 17th origin returns
// `error.TrustedOriginLimitExceeded`.

const std = @import("std");

pub const max_trusted_origins: usize = 16;

pub const RegisterError = error{ TrustedOriginLimitExceeded, OriginTooLong };

const max_origin_bytes: usize = 64;

const Entry = struct {
    len: usize,
    bytes: [max_origin_bytes]u8,
};

/// Zig 0.16 migrated `std.Thread.Mutex` onto `std.Io.Mutex`; the rest
/// of this crate resolves the process-global `std.Io` handle via the
/// single-threaded `Threaded.global_single_threaded.io()` spelling
/// (see `src/generator.zig::gio`).  We mirror that pattern locally so
/// the allowlist picks up the same handle.
inline fn gio() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

var mutex: std.Io.Mutex = std.Io.Mutex.init;
var entries: [max_trusted_origins]Entry = undefined;
var entry_count: usize = 0;

/// Register a caller-trusted origin string.  Idempotent — registering
/// the same string twice is a no-op success.  Appends the string to
/// the process-global allowlist; `isTrusted(origin)` returns true for
/// registered origins.
///
/// Threadsafe: protected by an internal mutex.
pub fn registerTrustedNamespaceOrigin(origin: []const u8) RegisterError!void {
    if (origin.len > max_origin_bytes) return error.OriginTooLong;
    mutex.lockUncancelable(gio());
    defer mutex.unlock(gio());
    // Idempotent on exact match.
    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        if (entries[i].len == origin.len and
            std.mem.eql(u8, entries[i].bytes[0..entries[i].len], origin))
            return;
    }
    if (entry_count >= max_trusted_origins)
        return error.TrustedOriginLimitExceeded;
    entries[entry_count].len = origin.len;
    @memcpy(entries[entry_count].bytes[0..origin.len], origin);
    entry_count += 1;
}

/// Linear scan of the allowlist.  Cheap — max 16 × 64-byte compares.
pub fn isTrusted(origin: []const u8) bool {
    mutex.lockUncancelable(gio());
    defer mutex.unlock(gio());
    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        if (entries[i].len == origin.len and
            std.mem.eql(u8, entries[i].bytes[0..entries[i].len], origin))
            return true;
    }
    return false;
}

/// TEST-ONLY: reset the allowlist between tests.  NOT exposed in the
/// public API — tests import this module directly.
pub fn resetForTest() void {
    mutex.lockUncancelable(gio());
    defer mutex.unlock(gio());
    entry_count = 0;
}
