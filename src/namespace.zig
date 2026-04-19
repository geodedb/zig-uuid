// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;

/// All-zero UUID (RFC-9562 nil UUID).
/// QC-93: single source of truth is UUID.nil in uuid.zig.
pub const nil = UUID.nil;

/// All-ones UUID (RFC-9562 max UUID).
/// QC-93: single source of truth is UUID.max in uuid.zig.
pub const max = UUID.max;

/// DNS namespace UUID: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
pub const namespace_dns = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// URL namespace UUID: 6ba7b811-9dad-11d1-80b4-00c04fd430c8
pub const namespace_url = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// OID namespace UUID: 6ba7b812-9dad-11d1-80b4-00c04fd430c8
pub const namespace_oid = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x12, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// X.500 namespace UUID: 6ba7b814-9dad-11d1-80b4-00c04fd430c8
pub const namespace_x500 = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x14, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// Closed set of RFC-9562 §6.6 namespace constants (`dns`, `url`, `oid`, `x500`)
/// plus a `custom` escape hatch for non-RFC namespaces. Used by
/// `newV3Strict` / `newV5Strict` so callers cannot accidentally pass an
/// attacker-controlled UUID as the namespace argument.
///
/// **CWE-347 (Improper Verification of Cryptographic Signature analog).**
/// V3 (MD5) and V5 (SHA-1) are deterministic hashes over
/// `ns.bytes ++ name`.  If *either* half of that input is attacker-
/// controlled, the attacker chooses half the preimage and can engineer
/// colliding `(ns, name)` pairs trivially — no hash-level collision is
/// required.  Concretely: never derive a `.custom` namespace from an
/// HTTP header, JSON body, query-string parameter, or any runtime input
/// whose bytes you do not fully trust.  Config-file-supplied namespaces
/// are also risky unless the config file itself is protected at the
/// same tier as a signing key (filesystem ACLs, sealed secrets, etc.).
///
/// **Safe patterns:**
///   * `Namespace.dns` / `.url` / `.oid` / `.x500` — the four RFC-9562
///     §6.6 constants; always safe.
///   * `Namespace{ .custom = comptime_known_bytes }` where
///     `comptime_known_bytes` is a constant defined in your source code
///     or embedded build-time.
///
/// **Unsafe patterns (will forge):**
///   * `Namespace{ .custom = request.header("X-Tenant-UUID").bytes }`
///   * `Namespace{ .custom = try uuid.UUID.fromString(user_input).bytes }`
///
/// Locking callers to a closed set of trusted namespaces via
/// `newV3Strict`/`newV5Strict` eliminates the attacker-controlled-input
/// vector; the `.custom` variant remains available for callers who
/// accept responsibility for their bytes being trusted.
pub const Namespace = union(enum) {
    dns,
    url,
    oid,
    x500,
    /// Non-RFC namespace. Caller is responsible for treating `bytes` as a
    /// trusted constant — NEVER populate it from untrusted input.
    custom: [16]u8,

    /// Materialise the `Namespace` as a UUID value (16 raw bytes).
    pub fn asUUID(self: Namespace) UUID {
        return switch (self) {
            .dns => namespace_dns,
            .url => namespace_url,
            .oid => namespace_oid,
            .x500 => namespace_x500,
            .custom => |b| UUID{ .bytes = b },
        };
    }

    /// SEC-P4-04: runtime-driven constructor that consults the process
    /// trusted-origin allowlist.  `origin` is a caller-defined string
    /// tag identifying where the bytes came from (e.g.
    /// "config.namespace", "vault.uuid-ns", "CLI --uuid-ns"); it must
    /// be registered via `registerTrustedNamespaceOrigin` at process
    /// startup before `fromConfig` will accept bytes carrying it.
    ///
    /// Returns `error.UnvettedNamespace` if the origin is not in the
    /// allowlist.  This converts the compile-time-only Namespace
    /// constraint into a startup-configurable runtime gate — callers
    /// who load namespaces from config can still get the CWE-347
    /// protection that `newV3Strict`/`newV5Strict` afford, without
    /// hard-coding the bytes.
    ///
    /// Safe pattern:
    /// ```zig
    /// // Startup:
    /// try uuid.registerTrustedNamespaceOrigin("config.tenant");
    ///
    /// // Later, config-driven:
    /// const ns_bytes = parseConfig(...);
    /// const ns = try Namespace.fromConfig(ns_bytes, "config.tenant");
    /// const id = try uuid.newV3Strict(ns, name);
    /// ```
    pub fn fromConfig(bytes: [16]u8, origin: []const u8) error{UnvettedNamespace}!Namespace {
        const trusted = @import("trusted_namespace_origins.zig");
        if (!trusted.isTrusted(origin)) return error.UnvettedNamespace;
        return Namespace{ .custom = bytes };
    }
};

test "Namespace.asUUID round-trips the four RFC-9562 namespaces (SEC-P3-05)" {
    const ns_dns: Namespace = .dns;
    const ns_url: Namespace = .url;
    const ns_oid: Namespace = .oid;
    const ns_x500: Namespace = .x500;
    try std.testing.expect(ns_dns.asUUID().eql(namespace_dns));
    try std.testing.expect(ns_url.asUUID().eql(namespace_url));
    try std.testing.expect(ns_oid.asUUID().eql(namespace_oid));
    try std.testing.expect(ns_x500.asUUID().eql(namespace_x500));
}

test "Namespace.custom round-trips arbitrary bytes (SEC-P3-05)" {
    const raw: [16]u8 = .{
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
    };
    const ns: Namespace = .{ .custom = raw };
    try std.testing.expectEqualSlices(u8, &raw, &ns.asUUID().bytes);
}

test "namespace_dns canonical string" {
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        namespace_dns.toString(&buf),
    );
}

test "namespace constants are distinct" {
    try std.testing.expect(!namespace_dns.eql(namespace_url));
    try std.testing.expect(!namespace_dns.eql(namespace_oid));
    try std.testing.expect(!namespace_dns.eql(namespace_x500));
}

test "nil and max are correct" {
    try std.testing.expect(nil.isNil());
    for (max.bytes) |b| try std.testing.expectEqual(@as(u8, 0xFF), b);
}

test "SEC-P4-04: Namespace.fromConfig rejects unregistered origin" {
    const trusted = @import("trusted_namespace_origins.zig");
    trusted.resetForTest();
    defer trusted.resetForTest();

    const bytes: [16]u8 = .{0x01} ** 16;
    try std.testing.expectError(
        error.UnvettedNamespace,
        Namespace.fromConfig(bytes, "unregistered.origin"),
    );
}

test "SEC-P4-04: Namespace.fromConfig accepts registered origin" {
    const trusted = @import("trusted_namespace_origins.zig");
    trusted.resetForTest();
    defer trusted.resetForTest();

    try trusted.registerTrustedNamespaceOrigin("config.tenant");
    const bytes: [16]u8 = .{0x02} ** 16;
    const ns = try Namespace.fromConfig(bytes, "config.tenant");
    try std.testing.expectEqualSlices(u8, &bytes, &ns.asUUID().bytes);
}

test "SEC-P4-04: registerTrustedNamespaceOrigin is idempotent" {
    const trusted = @import("trusted_namespace_origins.zig");
    trusted.resetForTest();
    defer trusted.resetForTest();

    try trusted.registerTrustedNamespaceOrigin("x");
    try trusted.registerTrustedNamespaceOrigin("x"); // idempotent no-op
    try std.testing.expect(trusted.isTrusted("x"));
}

test "SEC-P4-04: registerTrustedNamespaceOrigin enforces capacity" {
    const trusted = @import("trusted_namespace_origins.zig");
    trusted.resetForTest();
    defer trusted.resetForTest();

    var buf: [4]u8 = undefined;
    var i: usize = 0;
    while (i < trusted.max_trusted_origins) : (i += 1) {
        const origin = try std.fmt.bufPrint(&buf, "o{d}", .{i});
        try trusted.registerTrustedNamespaceOrigin(origin);
    }
    try std.testing.expectError(
        error.TrustedOriginLimitExceeded,
        trusted.registerTrustedNamespaceOrigin("overflow"),
    );
}
