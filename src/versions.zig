// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const uuid_mod = @import("uuid.zig");
const gen_mod = @import("generator.zig");
const UUID = uuid_mod.UUID;
const Error = uuid_mod.Error;
const Timestamp = @import("timestamp.zig").Timestamp;

/// Generate a Version 1 (Gregorian-epoch time + node) UUID using the package-level
/// default generator. Uses a random multicast node ID by default (RFC-9562 §6.10).
pub fn newV1() Error!UUID {
    return gen_mod.default_generator.newV1();
}

/// Generate a Version 1 UUID at the given pre-computed Gregorian Timestamp.
/// Useful for deterministic or historical UUID generation.
pub fn newV1AtTime(ts: Timestamp) Error!UUID {
    return gen_mod.default_generator.newV1AtTime(ts);
}

/// Generate a Version 3 (MD5 name-based) UUID.
///
/// **Security:** MD5 is broken — prefer `newV5` or V8 with a modern hash.
///
/// **SEC-P3-05 (CWE-327 / CWE-347) — namespace forgery:** `ns` accepts any
/// `UUID` because RFC-9562 permits it. Callers MUST treat `ns` as a trusted
/// constant (RFC namespace, config literal, or compile-time UUID). An
/// attacker-controlled `ns` enables `(ns, name)` collision crafting under
/// MD5 without needing a full preimage attack. Use `newV3Strict` (closed
/// `Namespace` enum) when the call site would otherwise accept any UUID.
///
/// **SEC-P4-12 (CWE-400) — unbounded hash input:** `name` is hashed in
/// full with no internal length cap. Forwarding an attacker-controlled
/// blob causes MD5 to consume CPU proportional to `name.len` (CPU-
/// amplification / hash-DoS). Validate `name.len` before calling or
/// use `newV3Bounded`, which returns `Error.NameTooLong` above the
/// caller's cap.
pub fn newV3(ns: UUID, name: []const u8) UUID {
    return gen_mod.default_generator.newV3(ns, name);
}

/// SEC-P4-12 (CWE-400): bounded V3 wrapper that rejects `name` inputs
/// longer than `max_len` with `Error.NameTooLong` before hashing.
/// Delegates to `Generator.newV3Bounded` on the process-global
/// `default_generator`; output for accepted inputs is byte-identical
/// to `newV3`.
pub fn newV3Bounded(ns: UUID, name: []const u8, max_len: usize) Error!UUID {
    return gen_mod.default_generator.newV3Bounded(ns, name, max_len);
}

/// SEC-P3-05: strict variant of `newV3` — accepts only the closed
/// `Namespace` enum (dns/url/oid/x500) plus the vetted `.custom` escape
/// hatch, so callers cannot pass an attacker-controlled UUID as the
/// namespace. Semantics are identical to `newV3` for the same bytes.
pub fn newV3Strict(ns: @import("namespace.zig").Namespace, name: []const u8) UUID {
    return gen_mod.default_generator.newV3Strict(ns, name);
}

/// Generate a Version 4 (random) UUID using the package-level default generator.
pub fn newV4() Error!UUID {
    return gen_mod.default_generator.newV4();
}

/// Generate a Version 5 (SHA-1 name-based) UUID.
///
/// **Security:** SHA-1 is weakened — consider V8 with SHA-256 for new systems.
///
/// **SEC-P3-05 (CWE-327 / CWE-347) — namespace forgery:** `ns` accepts any
/// `UUID` because RFC-9562 permits it. Callers MUST treat `ns` as a trusted
/// constant. An attacker-controlled namespace enables the same forgery
/// vector described for `newV3`. Use `newV5Strict` for call sites where the
/// compiler should reject attacker-controlled UUIDs.
///
/// **SEC-P4-12 (CWE-400) — unbounded hash input:** `name` is hashed in
/// full with no internal length cap. Forwarding an attacker-controlled
/// blob causes SHA-1 to consume CPU proportional to `name.len`.
/// Validate `name.len` before calling or use `newV5Bounded`, which
/// returns `Error.NameTooLong` above the caller's cap.
pub fn newV5(ns: UUID, name: []const u8) UUID {
    return gen_mod.default_generator.newV5(ns, name);
}

/// SEC-P4-12 (CWE-400): bounded V5 wrapper that rejects `name` inputs
/// longer than `max_len` with `Error.NameTooLong` before hashing.
/// Delegates to `Generator.newV5Bounded` on the process-global
/// `default_generator`; output for accepted inputs is byte-identical
/// to `newV5`.
pub fn newV5Bounded(ns: UUID, name: []const u8, max_len: usize) Error!UUID {
    return gen_mod.default_generator.newV5Bounded(ns, name, max_len);
}

/// SEC-P3-05: strict variant of `newV5` — see `newV3Strict`.
pub fn newV5Strict(ns: @import("namespace.zig").Namespace, name: []const u8) UUID {
    return gen_mod.default_generator.newV5Strict(ns, name);
}

/// Generate a Version 6 (reordered Gregorian timestamp, k-sortable) UUID using the
/// package-level default generator. Lexicographically sortable alternative to V1.
pub fn newV6() Error!UUID {
    return gen_mod.default_generator.newV6();
}

/// Generate a Version 6 UUID at the given pre-computed Gregorian Timestamp.
pub fn newV6AtTime(ts: Timestamp) Error!UUID {
    return gen_mod.default_generator.newV6AtTime(ts);
}

/// Generate a Version 7 (Unix-ms timestamp + monotonic counter) UUID using the
/// package-level default generator. Recommended for new systems requiring sortable UUIDs.
pub fn newV7() Error!UUID {
    return gen_mod.default_generator.newV7();
}

/// Generate a Version 7 UUID at the given Unix millisecond timestamp `ts`.
/// Returns `Error.InvalidTimestamp` if `ts < 0`.
pub fn newV7AtTime(ts: i64) Error!UUID {
    return gen_mod.default_generator.newV7AtTime(ts);
}

/// Generate a Version 8 (custom) UUID with caller-supplied bit fields.
/// `a` fills bytes 0-5, `b` fills bytes 6-7 (high 4 bits become version nibble),
/// `c` fills bytes 8-15 (high 2 bits become variant bits).
///
/// This function is infallible — no clock, random, or I/O is needed.
pub fn newV8(a: [6]u8, b: [2]u8, c: [8]u8) UUID {
    return gen_mod.default_generator.newV8(a, b, c);
}

// =============================================================================
// QC-100: default_generator parity wrappers.
//
// Every method exposed by `Generator` that makes sense on a process-global
// generator is wrapped below so callers who use the convenience `uuid.newV*`
// family do not need to switch to a local `var gen = Generator.init()` just
// to call `clearNodeCache`, `reseed`, `saveState`, etc.  For callers who
// need direct access to the default generator pointer (e.g. to inspect
// state after loadState), use `defaultGenerator()` below.
//
// Omissions by design:
//   - `Generator.init`, `Generator.withClock`, `Generator.withRand`,
//     `Generator.withHWAddr` are constructors — calling them on the shared
//     default would be meaningless (they construct a new value). Callers
//     that need a custom clock/rand/hwaddr should construct their own
//     `Generator` instance.
// =============================================================================

/// QC-100 / SEC-P3-01: return a pointer to the process-global default
/// `Generator` used by the module-level convenience functions. Callers
/// can use this to invoke state-bearing methods such as `reseed()`
/// (post-fork), `loadState()`, `saveState()`, or to inspect state
/// directly. All concurrent UUID generation through the module-level
/// `newV*` functions continues to be safe because `Generator` locks its
/// own state; mutation of the returned pointer is the caller's
/// responsibility.
pub fn defaultGenerator() *gen_mod.Generator {
    return &gen_mod.default_generator;
}

/// QC-100: module-level wrapper for `Generator.clearNodeCache`, operating
/// on the shared `default_generator`. Forces the next V1/V6 call through
/// the module-level `newV1`/`newV6` convenience functions to re-fetch
/// the node ID.
pub fn clearNodeCache() void {
    gen_mod.default_generator.clearNodeCache();
}

/// QC-100 / SEC-P3-01: module-level wrapper for `Generator.reseed`
/// operating on the shared `default_generator`. Intended for callers
/// who fork() and use the module-level convenience functions — the
/// child process MUST call this before generating UUIDs to avoid
/// colliding with the parent on cached CSPRNG-derived state.
pub fn reseed() void {
    gen_mod.default_generator.reseed();
}

/// QC-100: module-level wrapper for `Generator.saveState` operating on
/// the shared `default_generator`. `path` must be an absolute
/// filesystem path; see `Generator.saveState` for full semantics.
pub fn saveState(path: []const u8) Error!void {
    return gen_mod.default_generator.saveState(path);
}

/// QC-100: module-level wrapper for `Generator.loadState` operating on
/// the shared `default_generator`. `path` must be an absolute filesystem
/// path; see `Generator.loadState` for full semantics including the
/// SEC-P3-02 clock-rollback guard.
pub fn loadState(path: []const u8) Error!void {
    return gen_mod.default_generator.loadState(path);
}

/// SEC-P4-01: module-level wrapper for `Generator.migrateStateToV3`
/// operating on the shared `default_generator`.  See
/// `Generator.migrateStateToV3` for semantics.  Requires
/// `default_generator.state_mac_key` to be set (configure via a one-
/// off local Generator + save, or by mutating
/// `uuid.defaultGenerator().state_mac_key` — see the advanced-API
/// section of README for key-handling patterns).
pub fn migrateStateToV3(path: []const u8) Error!void {
    return gen_mod.default_generator.migrateStateToV3(path);
}

/// O-1 (CWE-320): module-level wrapper for `Generator.rotateStateMacKey`
/// operating on the shared `default_generator`.  See
/// `Generator.rotateStateMacKey` for semantics.  Requires
/// `default_generator.state_mac_key` to already be set; the old key
/// is securely zeroed before `new_key` is installed.
pub fn rotateStateMacKey(path: []const u8, new_key: [32]u8) Error!void {
    return gen_mod.default_generator.rotateStateMacKey(path, new_key);
}

/// QC-100: module-level wrapper for `Generator.secureWipeMacKey` operating
/// on the shared `default_generator`. See `Generator.secureWipeMacKey` for
/// semantics (idempotent volatile zeroization of the HMAC state-file key).
pub fn secureWipeMacKey() void {
    gen_mod.default_generator.secureWipeMacKey();
}

/// QC-100 + PERF-30: module-level wrapper for `Generator.initV3Namespace`
/// that builds a `PrehashedV3` snapshot under the shared `default_generator`.
/// Safe to call concurrently: `initV3Namespace` only reads immutable
/// hasher state.
pub fn initV3Namespace(ns: UUID) gen_mod.Generator.PrehashedV3 {
    return gen_mod.default_generator.initV3Namespace(ns);
}

/// QC-100 + PERF-30: module-level wrapper for `Generator.initV5Namespace`.
pub fn initV5Namespace(ns: UUID) gen_mod.Generator.PrehashedV5 {
    return gen_mod.default_generator.initV5Namespace(ns);
}

test "top-level newV4 delegates to default_generator" {
    const u = try newV4();
    try std.testing.expectEqual(uuid_mod.Version.v4, u.version());
}

test "top-level newV7 delegates to default_generator" {
    const u = try newV7();
    try std.testing.expectEqual(uuid_mod.Version.v7, u.version());
}

test "top-level newV3 with DNS namespace" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = newV3(ns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        u.toString(&buf),
    );
}

// QC-30: delegation tests for the 7 previously-untested convenience functions.

test "top-level newV1 delegates to default_generator (QC-30)" {
    const u = try newV1();
    try std.testing.expectEqual(uuid_mod.Version.v1, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
}

test "top-level newV1AtTime delegates to default_generator (QC-30)" {
    const ts_mod = @import("timestamp.zig");
    const greg_ts = ts_mod.Timestamp{ .value = 139_806_912_000_000_000 }; // 2024-01-01 UTC
    const u = try newV1AtTime(greg_ts);
    try std.testing.expectEqual(uuid_mod.Version.v1, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
    // Timestamp round-trip.
    const got = try ts_mod.timestampFromV1(u);
    try std.testing.expectEqual(greg_ts.value, got.value);
}

test "top-level newV5 delegates to default_generator (QC-30)" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = newV5(ns, "www.example.com");
    // RFC-9562 / Python uuid.uuid5() test vector.
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2ed6657d-e927-568b-95e1-2665a8aea6a2",
        u.toString(&buf),
    );
}

test "top-level newV6 delegates to default_generator (QC-30)" {
    const u = try newV6();
    try std.testing.expectEqual(uuid_mod.Version.v6, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
}

test "top-level newV6AtTime delegates to default_generator (QC-30)" {
    const ts_mod = @import("timestamp.zig");
    const greg_ts = ts_mod.Timestamp{ .value = 139_806_912_000_000_000 }; // 2024-01-01 UTC
    const u = try newV6AtTime(greg_ts);
    try std.testing.expectEqual(uuid_mod.Version.v6, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
    const got = try ts_mod.timestampFromV6(u);
    try std.testing.expectEqual(greg_ts.value, got.value);
}

test "top-level newV7AtTime delegates to default_generator (QC-30)" {
    const ts_mod = @import("timestamp.zig");
    const ms: i64 = 1_700_000_000_000; // 2023-11-14 in Unix ms
    const u = try newV7AtTime(ms);
    try std.testing.expectEqual(uuid_mod.Version.v7, u.version());
    const got = try ts_mod.timestampFromV7(u);
    try std.testing.expectEqual(ms, got.toUnixMs());
}

test "top-level newV8 delegates to default_generator (QC-30)" {
    const a = [6]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const b = [2]u8{ 0x07, 0x08 };
    const c = [8]u8{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const u = newV8(a, b, c);
    try std.testing.expectEqual(uuid_mod.Version.v8, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
}

// SEC-P3-05: strict namespace wrappers.

test "newV3Strict(.dns, \"www.example.com\") matches RFC vector (SEC-P3-05)" {
    const ns_mod = @import("namespace.zig");
    const u = newV3Strict(ns_mod.Namespace.dns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        u.toString(&buf),
    );
    try std.testing.expectEqual(uuid_mod.Version.v3, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
}

test "newV5Strict(.dns, \"www.example.com\") matches RFC vector (SEC-P3-05)" {
    const ns_mod = @import("namespace.zig");
    const u = newV5Strict(ns_mod.Namespace.dns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2ed6657d-e927-568b-95e1-2665a8aea6a2",
        u.toString(&buf),
    );
    try std.testing.expectEqual(uuid_mod.Version.v5, u.version());
    try std.testing.expectEqual(uuid_mod.Variant.rfc9562, u.variant());
}

test "newV3/newV3Strict agree on bytes for the same namespace (SEC-P3-05)" {
    const ns_mod = @import("namespace.zig");
    const strict = newV3Strict(ns_mod.Namespace.dns, "example.com");
    const permissive = newV3(ns_mod.namespace_dns, "example.com");
    try std.testing.expect(strict.eql(permissive));
}

test "newV5Strict(.custom, ...) with enum-carried bytes equals newV5 (SEC-P3-05)" {
    const raw: [16]u8 = .{
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
    };
    const strict = newV5Strict(.{ .custom = raw }, "content-1");
    const permissive = newV5(uuid_mod.UUID{ .bytes = raw }, "content-1");
    try std.testing.expect(strict.eql(permissive));
}

// QC-100: default_generator parity tests.

test "defaultGenerator returns the same pointer across calls (QC-100)" {
    const p1 = defaultGenerator();
    const p2 = defaultGenerator();
    try std.testing.expectEqual(p1, p2);
    // Pointer must equal the generator.zig module's default_generator.
    try std.testing.expectEqual(&gen_mod.default_generator, p1);
}

test "module-level clearNodeCache operates on default_generator (QC-100)" {
    // Warm the cache via the convenience newV1, then clear it via the
    // module-level wrapper, then confirm the default_generator's cache
    // flag reflects the clear.
    _ = try newV1();
    try std.testing.expect(gen_mod.default_generator.node_cache_valid.load(.acquire));
    clearNodeCache();
    try std.testing.expect(!gen_mod.default_generator.node_cache_valid.load(.acquire));
    // Re-warm so we leave no global-state surprise for subsequent tests.
    _ = try newV1();
}

test "module-level reseed zeroes default_generator state (QC-100)" {
    // Pre-populate then call the module-level reseed wrapper.
    gen_mod.default_generator.v1v6.clock_seq = 0x1234;
    gen_mod.default_generator.v1v6.clock_seq_initialized = true;
    gen_mod.default_generator.v7.last_ms = 9_999;
    gen_mod.default_generator.v7.mono_seq = 0x0ABC;
    reseed();
    try std.testing.expectEqual(@as(u14, 0), gen_mod.default_generator.v1v6.clock_seq);
    try std.testing.expect(!gen_mod.default_generator.v1v6.clock_seq_initialized);
    try std.testing.expectEqual(@as(i64, 0), gen_mod.default_generator.v7.last_ms);
    try std.testing.expectEqual(@as(u12, 0), gen_mod.default_generator.v7.mono_seq);
}

test "module-level initV3Namespace matches newV3 for the same namespace (QC-100)" {
    const ns_mod = @import("namespace.zig");
    const prehashed = initV3Namespace(ns_mod.namespace_dns);
    const a = prehashed.name("example.com");
    const b = newV3(ns_mod.namespace_dns, "example.com");
    try std.testing.expect(a.eql(b));
}

test "module-level initV5Namespace matches newV5 for the same namespace (QC-100)" {
    const ns_mod = @import("namespace.zig");
    const prehashed = initV5Namespace(ns_mod.namespace_url);
    const a = prehashed.name("https://example.com");
    const b = newV5(ns_mod.namespace_url, "https://example.com");
    try std.testing.expect(a.eql(b));
}

// QC-147: delegation tests for the 7 wrappers added after QC-30.

test "top-level newV3Bounded delegates and enforces cap (QC-147)" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = try newV3Bounded(ns, "www.example.com", 64);
    const expected = newV3(ns, "www.example.com");
    try std.testing.expectEqual(expected, u);
    try std.testing.expectError(
        uuid_mod.Error.NameTooLong,
        newV3Bounded(ns, "www.example.com", 4),
    );
}

test "top-level newV5Bounded delegates and enforces cap (QC-147)" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = try newV5Bounded(ns, "www.example.com", 64);
    const expected = newV5(ns, "www.example.com");
    try std.testing.expectEqual(expected, u);
    try std.testing.expectError(
        uuid_mod.Error.NameTooLong,
        newV5Bounded(ns, "www.example.com", 4),
    );
}

test "top-level saveState/loadState delegate to default_generator (QC-147)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buf);
    var path_buf: [std.fs.max_path_bytes + 64]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/.zig-cache/tmp/{s}/qc147.state",
        .{ cwd_buf[0..cwd_len], tmp.sub_path[0..] },
    );

    _ = try newV7(); // ensure default_generator has V7 state to persist
    try saveState(path);
    try loadState(path); // round-trip through the module-level wrappers
}

test "top-level migrateStateToV3 delegates to default_generator (QC-147)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buf);
    var path_buf: [std.fs.max_path_bytes + 64]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/.zig-cache/tmp/{s}/qc147-migrate.state",
        .{ cwd_buf[0..cwd_len], tmp.sub_path[0..] },
    );

    // Save a v2 (keyless) file via the module wrapper, then migrate under a key.
    defer secureWipeMacKey(); // restore global key-null state for other tests
    secureWipeMacKey(); // guarantee keyless state before saving v2
    _ = try newV7();
    try saveState(path); // v2 — no key configured
    gen_mod.default_generator.state_mac_key = .{0x42} ** 32;
    try migrateStateToV3(path);
    try loadState(path); // v3 file now loads under the configured key
}

test "top-level rotateStateMacKey + secureWipeMacKey delegate (QC-147)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buf);
    var path_buf: [std.fs.max_path_bytes + 64]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/.zig-cache/tmp/{s}/qc147-rotate.state",
        .{ cwd_buf[0..cwd_len], tmp.sub_path[0..] },
    );

    defer secureWipeMacKey(); // always restore global key-null state
    gen_mod.default_generator.state_mac_key = .{0x11} ** 32;
    _ = try newV7();
    try saveState(path); // v3 under the old key
    try rotateStateMacKey(path, .{0x22} ** 32);
    try loadState(path); // authenticates under the new key

    secureWipeMacKey();
    try std.testing.expect(gen_mod.default_generator.state_mac_key == null);
}
