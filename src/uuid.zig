// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

// -----------------------------------------------------------------------------
// PERF-32: Process-wide hash seed for `UUID.ProcessHashContext`.
//
// Sampled from CSPRNG on the first call to `processHashSeed()` and reused
// by every subsequent call in the same process.  This gives HashDoS
// resistance at the cost of one CSPRNG sample per process, not one per
// HashContext instance the way `SecureHashContext` does.
//
// We use a small atomic state machine instead of std.once (which does not
// exist in Zig 0.16) — see PERF-32 instruction's fallback note.
// -----------------------------------------------------------------------------
var process_seed: u64 = 0;
const ProcessSeedState = enum(u8) { uninit = 0, initializing = 1, ready = 2 };
var process_seed_state: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(ProcessSeedState.uninit));

/// PERF-32: Return the process-wide hash seed, initialising it lazily
/// from `std.crypto.random` on first use.  All callers in the same
/// process observe the same value; different processes observe
/// independently sampled seeds.  Thread-safe via cmpxchg.
fn processHashSeed() u64 {
    // Fast path: seed is already published.
    if (process_seed_state.load(.acquire) == @intFromEnum(ProcessSeedState.ready)) {
        return @atomicLoad(u64, &process_seed, .acquire);
    }
    // Try to claim initialisation.  Only the first thread wins the CAS;
    // every other thread spins until the winner publishes `.ready`.
    if (process_seed_state.cmpxchgStrong(
        @intFromEnum(ProcessSeedState.uninit),
        @intFromEnum(ProcessSeedState.initializing),
        .acquire,
        .acquire,
    ) == null) {
        var seed_buf: [8]u8 = undefined;
        std.Io.Threaded.global_single_threaded.io().random(&seed_buf);
        const seed = std.mem.readInt(u64, &seed_buf, .little);
        @atomicStore(u64, &process_seed, seed, .release);
        process_seed_state.store(@intFromEnum(ProcessSeedState.ready), .release);
        return seed;
    }
    // Another thread is initialising; spin until it finishes.
    while (process_seed_state.load(.acquire) != @intFromEnum(ProcessSeedState.ready)) {
        std.atomic.spinLoopHint();
    }
    return @atomicLoad(u64, &process_seed, .acquire);
}

pub const Error = error{
    /// Returned by `UUID.fromString` when the supplied text cannot be parsed
    /// as an RFC 9562 canonical (8-4-4-4-12), braced (`{...}`), or URN
    /// (`urn:uuid:...`) form — e.g. stray whitespace, non-hex bytes inside
    /// a segment, or the hyphen layout is malformed in a subtler way than
    /// the dedicated `InvalidDashes` variant covers.
    InvalidFormat,
    /// Returned by `UUID.fromString` when the input length does not match
    /// any of the three accepted envelope sizes (36 canonical, 38 braced,
    /// 45 URN).  Length is validated before any hex parsing so callers
    /// see this variant instead of `InvalidFormat` for short/long input.
    InvalidLength,
    /// Returned by `UUID.fromString` when the input is 38 bytes but is
    /// missing a matching `{` / `}` pair (one present without the other,
    /// or both absent).  Length alone matched the braced form, so the
    /// dedicated variant distinguishes brace-envelope errors from generic
    /// `InvalidFormat`.
    InvalidBraces,
    /// Returned by `UUID.fromString` when the input is 45 bytes but does
    /// not begin with the case-insensitive `urn:uuid:` prefix required by
    /// RFC 9562 §4.  Length alone matched the URN form; this variant
    /// flags a malformed prefix specifically.
    InvalidURNPrefix,
    /// Returned by `UUID.fromString` when the hyphen positions inside the
    /// 36-byte canonical body are wrong (missing hyphen at one of bytes
    /// 8/13/18/23, or a hyphen where a hex digit is expected).  Distinct
    /// from `InvalidFormat` so callers can pattern-match layout bugs.
    InvalidDashes,
    /// Returned by `UUID.fromBytes` when the caller-supplied byte slice is
    /// not exactly 16 bytes long.  Parsing is length-strict: over- or
    /// under-sized buffers are rejected rather than silently truncated.
    IncorrectByteLength,
    /// Returned by the V1/V6 generators (via the configured `HWAddrFn`) when
    /// no non-loopback MAC address can be discovered on the host — e.g.
    /// the machine has no network interfaces, or all interfaces are
    /// administratively down.  Callers that cannot tolerate the random-node
    /// fallback should treat this as a hard failure.
    NoHWAddressFound,
    /// Returned by helpers that operate on a parsed `UUID` (e.g.
    /// `UUID.getTimestamp`) when the version nibble does not match what
    /// the helper expects — e.g. asking for a V7 timestamp from a V4 UUID.
    InvalidVersion,
    /// Returned when the configured `RandFn` (or the default CSPRNG) fails
    /// to fill the requested buffer — e.g. the OS random source returned
    /// short or the caller-supplied random source errored out.  Signals
    /// that no UUID could be generated because entropy was unavailable.
    RandomError,
    /// Returned by Timestamp.now() when the system clock is before the Unix epoch.
    InvalidTimestamp,
    /// QC-99: Returned by `Generator.saveState` / `Generator.loadState` when
    /// the underlying filesystem I/O fails (permission denied, disk full,
    /// path not found, symlink rejected by O_NOFOLLOW, rename across
    /// filesystems, etc.). This collapses the wide underlying
    /// `std.posix` / `std.Io.File` / `std.Io.Dir` error set into a single
    /// library-level error so callers depend on a stable error surface.
    StateIoFailure,
    /// SEC-P3-04: returned by `Generator.loadState` when the persisted state
    /// file is wire-format version 3 (HMAC-authenticated) and the HMAC-SHA256
    /// trailer fails timing-safe verification against the configured
    /// `state_mac_key`.  Also returned when a version-3 file is encountered
    /// and no `state_mac_key` is configured (the library refuses to accept
    /// data it cannot authenticate).
    StateMacMismatch,
    /// SEC-P4-01: `loadState` refused an unauthenticated state file
    /// (version 1 or 2) under a policy that requires HMAC authentication.
    /// Signals that the file predates the caller's current
    /// `state_mac_key` configuration and must be migrated via
    /// `Generator.migrateStateToV3` before it can be consumed under the
    /// strict policy.  Distinct from `StateMacMismatch` so callers can
    /// programmatically offer a migration path without mis-classifying
    /// tampering as downgrade (and vice-versa).
    StateVersionDowngrade,
    /// SEC-P4-12 (CWE-400): Returned by `Generator.newV3Bounded` /
    /// `Generator.newV5Bounded` (and the module-level
    /// `uuid.newV3Bounded` / `uuid.newV5Bounded` wrappers) when
    /// `name.len` exceeds the caller-supplied `max_len` cap.  The
    /// bounded variants let callers reject attacker-controlled or
    /// oversized inputs before they reach the MD5 / SHA-1 hasher,
    /// closing a CPU-amplification (hash-DoS) path where a multi-GB
    /// `name` would force the library to hash the entire buffer.
    NameTooLong,
};

/// UUID version nibble (bits 76-79 of byte 6).
///
/// This is a non-exhaustive enum: unrecognised nibble values (e.g. `0` for
/// the nil UUID, `2` for DCE Security, or `9`–`15` for future versions) are
/// returned as unnamed enum members rather than causing a safety-checked panic.
/// Callers that switch on Version must include an `else` branch.
pub const Version = enum(u8) {
    v1 = 1,
    v3 = 3,
    v4 = 4,
    v5 = 5,
    v6 = 6,
    v7 = 7,
    v8 = 8,
    _, // non-exhaustive: allows @enumFromInt on unknown nibbles without panic
};

/// UUID variant field (RFC 9562 §4.1).  Determines which UUID specification
/// the UUID conforms to, encoded in the high bits of byte 8 (clock_seq_hi).
///
/// Most modern UUIDs use `rfc9562` (variant bits `10x`).
pub const Variant = enum(u8) {
    /// NCS backward compatibility (variant bits `0xx`).
    ncs,
    /// RFC 9562 / RFC 4122 (variant bits `10x`) — the standard variant.
    rfc9562,
    /// Microsoft backward compatibility (variant bits `110`).
    microsoft,
    /// Reserved for future definition (variant bits `111`).
    future,
};

pub const UUID = struct {
    bytes: [16]u8,

    pub const nil: UUID = .{ .bytes = [_]u8{0x00} ** 16 };
    pub const max: UUID = .{ .bytes = [_]u8{0xFF} ** 16 };

    /// Return the version nibble as a Version enum value.
    ///
    /// Because Version is a non-exhaustive enum, this never panics — unknown
    /// nibbles (nil UUID version=0, DCE Security version=2, future versions
    /// 9–15) are returned as unnamed members. Use `switch (u.version()) { .v4
    /// => ..., else => ... }` to handle unknown values safely.
    pub fn version(self: UUID) Version {
        return @enumFromInt(self.bytes[6] >> 4);
    }

    /// Return the variant field from byte 8 as a Variant enum value.
    ///
    /// Interprets the two or three high-order bits of byte 8 per RFC-9562 §4.1.
    /// All well-formed RFC-9562 UUIDs (V1–V8) return `.rfc9562`; the nil UUID
    /// and max UUID return `.ncs` and `.future` respectively.
    pub fn variant(self: UUID) Variant {
        const b = self.bytes[8];
        if (b & 0x80 == 0x00) return .ncs;
        if (b & 0xC0 == 0x80) return .rfc9562;
        if (b & 0xE0 == 0xC0) return .microsoft;
        return .future;
    }

    /// Returns true when all 16 bytes are zero (the nil UUID per RFC-9562 §5.9).
    ///
    /// Equivalent to `uuid.eql(UUID.nil)`. Use `UUID.nil` as a sentinel value
    /// for "not yet assigned" UUID fields.
    ///
    /// **SEC-R11-03 / CWE-208 — Timing note:** This function uses `std.mem.eql`,
    /// which is not constant-time.  For the typical use case (nil sentinel check
    /// on a public identifier) this is correct and efficient.  If the nil check
    /// is part of a secret-token comparison, use `timingSafeEql(UUID.nil)` instead.
    pub fn isNil(self: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &nil.bytes);
    }

    /// Returns true when all 16 bytes are 0xFF (the max UUID per RFC-9562 §5.10).
    ///
    /// **SEC-R11-03 / CWE-208 — Timing note:** This function uses `std.mem.eql`,
    /// which is not constant-time.  For the typical use case (max sentinel check
    /// on a public identifier) this is correct and efficient.  If the max check
    /// is part of a secret-token comparison, use `timingSafeEql(UUID.max)` instead.
    pub fn isMax(self: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &UUID.max.bytes);
    }

    /// Returns true when this UUID has a known RFC-9562 version nibble (1–8)
    /// and the RFC-9562 variant bits.  Useful for strict conformance checking
    /// without mandating it at parse time (RFC-9562 §6.12 opacity guidance).
    ///
    /// The nil UUID and max UUID return false (version nibble 0 and 0xF are
    /// not defined RFC-9562 versions).
    ///
    /// Implements the validation pattern requested in gofrs/uuid issue #198.
    pub fn isValid(self: UUID) bool {
        const is_known_version = switch (self.version()) {
            .v1, .v3, .v4, .v5, .v6, .v7, .v8 => true,
            _ => false,
        };
        return is_known_version and self.variant() == .rfc9562;
    }

    /// Strict RFC-9562 conformance check.  Returns error.InvalidVersion when
    /// the UUID has an unknown version nibble or a non-rfc9562 variant.
    ///
    /// Callers that need to accept any well-formed UUID regardless of version
    /// should use isNil()/version()/variant() directly instead.
    pub fn validate(self: UUID) Error!void {
        if (!self.isValid()) return Error.InvalidVersion;
    }

    /// Alias for isNil(). Satisfies the bsoncodec.Zeroer-style interface
    /// pattern used in some serialization frameworks (G-9).
    pub fn isZero(self: UUID) bool {
        return self.isNil();
    }

    /// Set the version nibble in byte 6 (bits 76-79) to the given version.
    ///
    /// Preserves the lower 4 bits of byte 6 (time_hi bits 0-3 in V1/V6).
    /// Should be followed by `setVariant(.rfc9562)` when constructing
    /// RFC-9562-conformant UUIDs from scratch.
    pub fn setVersion(self: *UUID, v: Version) void {
        self.bytes[6] = (self.bytes[6] & 0x0F) | (@as(u8, @intFromEnum(v)) << 4);
    }

    /// Set the variant bits in byte 8 according to the given Variant.
    ///
    /// Overwrites only the high-order variant bits; the remaining clock-sequence
    /// bits are preserved.  For RFC-9562-conformant UUIDs, call with `.rfc9562`.
    pub fn setVariant(self: *UUID, v: Variant) void {
        switch (v) {
            .rfc9562 => self.bytes[8] = (self.bytes[8] & 0x3F) | 0x80,
            .ncs => self.bytes[8] = self.bytes[8] & 0x7F,
            .microsoft => self.bytes[8] = (self.bytes[8] & 0x1F) | 0xC0,
            .future => self.bytes[8] = (self.bytes[8] & 0x0F) | 0xE0,
        }
    }

    /// Returns true when this UUID and `other` have identical byte sequences.
    ///
    /// UUID comparison is byte-by-byte (case-insensitive string representations
    /// are not compared here).  Use `fromString` to normalise both sides first
    /// if you need to compare string-encoded UUIDs.
    ///
    /// **SEC-R9-01 / CWE-208 — Timing safety warning:**
    /// This function uses `std.mem.eql`, which is a short-circuit comparison and
    /// is **not** constant-time.  It is correct and efficient for the typical use
    /// case of UUID identity checks (UUIDs are public identifiers).
    ///
    /// However, if a UUID is used as a secret capability — for example as a V4
    /// session token, invite token, or bearer credential — comparing it with
    /// `eql` leaks timing information that an attacker can use to recover the
    /// secret byte-by-byte via a remote timing oracle.
    ///
    /// Use `timingSafeEql` instead whenever the UUID being compared is secret.
    pub fn eql(self: UUID, other: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    /// Constant-time equality check for UUIDs used as secrets.
    ///
    /// Equivalent to `eql` in semantics but uses `std.crypto.timing_safe.eql`
    /// to ensure the comparison takes the same amount of time regardless of
    /// where the first differing byte occurs.
    ///
    /// **Use this function** when the UUID represents a secret capability (e.g.
    /// a V4 session token, invite token, or bearer credential) and the result
    /// is used in an authentication or authorisation decision.  Using `eql` in
    /// that context leaks timing information (CWE-208).
    ///
    /// For ordinary UUID identity checks where the UUID is a public identifier,
    /// `eql` is preferred — it is faster and constant-time safety is unnecessary.
    pub fn timingSafeEql(self: UUID, other: UUID) bool {
        return std.crypto.timing_safe.eql([16]u8, self.bytes, other.bytes);
    }

    /// Lexicographic ordering of UUID bytes (big-endian byte comparison).
    ///
    /// Returns `.lt`, `.eq`, or `.gt`.  For time-ordered UUID versions (V1, V6,
    /// V7) this ordering coincides with temporal ordering when UUIDs are generated
    /// by the same Generator.  For V4 the order is unpredictable.
    pub fn order(self: UUID, other: UUID) std.math.Order {
        return std.mem.order(u8, &self.bytes, &other.bytes);
    }

    /// A zero-size HashMap context for UUID keys using Wyhash with a fixed
    /// seed of zero.
    ///
    /// **SEC-6 / CWE-330 — HashDoS warning:**
    /// The fixed seed means that two UUIDs which collide under this seed will
    /// **always** collide, across every run and every process.  An adversary
    /// who can control which UUIDs are inserted into a HashMap using this
    /// context can engineer O(n²) worst-case behaviour.
    ///
    /// **Use `HashContext` only when UUID keys are fully trusted** (e.g.,
    /// internally-generated V4 UUIDs, compile-time constants, or values from
    /// a controlled internal datastore).  When keys arrive from untrusted
    /// sources (parsed from user input, external APIs, log files, etc.) use
    /// `SecureHashContext` instead.
    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: UUID) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(&key.bytes);
            return hasher.final();
        }
        pub fn eql(_: HashContext, a: UUID, b: UUID) bool {
            return a.eql(b);
        }
    };

    /// A HashMap context for UUID keys using a randomly-seeded Wyhash instance,
    /// providing HashDoS resistance when UUID keys may be attacker-controlled.
    ///
    /// **SEC-6:** Use this context instead of `HashContext` whenever UUIDs are
    /// received from untrusted sources (user input, external APIs, network
    /// messages) and inserted into a HashMap.
    ///
    /// Because `SecureHashContext` carries the random seed as instance state,
    /// it is used with Zig's context-aware map APIs.  Example:
    ///
    /// ```zig
    /// var ctx = UUID.SecureHashContext.init();
    /// var map = std.HashMapUnmanaged(UUID, MyVal, UUID.SecureHashContext, 80){};
    /// try map.putContext(allocator, key, value, ctx);
    /// ```
    ///
    /// The seed is sampled from `std.crypto.random` at construction time; each
    /// `SecureHashContext.init()` call produces a different seed.
    pub const SecureHashContext = struct {
        seed: u64,

        /// Create a new SecureHashContext with a cryptographically random seed.
        pub fn init() SecureHashContext {
            return .{ .seed = blk: {
                var seed_buf: [8]u8 = undefined;
                std.Io.Threaded.global_single_threaded.io().random(&seed_buf);
                break :blk std.mem.readInt(u64, &seed_buf, .little);
            } };
        }

        pub fn hash(self: SecureHashContext, key: UUID) u64 {
            var hasher = std.hash.Wyhash.init(self.seed);
            hasher.update(&key.bytes);
            return hasher.final();
        }

        pub fn eql(_: SecureHashContext, a: UUID, b: UUID) bool {
            return a.eql(b);
        }
    };

    /// PERF-32: A HashMap context that is **zero-size** (like `HashContext`)
    /// but uses a per-process random seed sampled once from CSPRNG on first
    /// use (like `SecureHashContext`).
    ///
    /// **When to pick which context:**
    /// - `HashContext` — fixed seed of 0.  Fastest, but NO HashDoS resistance.
    ///   Use only when keys are fully trusted (internal constants, values
    ///   from a controlled datastore).
    /// - `ProcessHashContext` — process-wide random seed.  Same zero-cost
    ///   API as `HashContext` (no per-map state to carry), yet an adversary
    ///   cannot precompute colliding keys across different runs because the
    ///   seed differs per process.  A colluding pair of maps inside a SINGLE
    ///   process can still be attacked jointly; use `SecureHashContext` when
    ///   that is part of your threat model.
    /// - `SecureHashContext` — per-instance random seed.  Strongest; even
    ///   two maps in the same process have unrelated seeds.  Carries the
    ///   seed as instance state so must be used with Zig's context-aware
    ///   map APIs (`putContext`, etc.).
    ///
    /// The seed is lazily initialised on the first hash() call (via
    /// `processHashSeed()`); all subsequent calls in the same process
    /// observe the same value with one `@atomicLoad` of acquire-ordered u8.
    pub const ProcessHashContext = struct {
        pub fn hash(_: ProcessHashContext, key: UUID) u64 {
            var hasher = std.hash.Wyhash.init(processHashSeed());
            hasher.update(&key.bytes);
            return hasher.final();
        }
        pub fn eql(_: ProcessHashContext, a: UUID, b: UUID) bool {
            return a.eql(b);
        }
    };

    /// Construct a UUID from a 16-byte slice.
    ///
    /// Returns `Error.IncorrectByteLength` if `b.len != 16`.  The bytes are
    /// copied as-is; no version or variant bits are set.  Use `setVersion` and
    /// `setVariant` to mark the UUID after construction if needed.
    pub fn fromBytes(b: []const u8) Error!UUID {
        if (b.len != 16) return Error.IncorrectByteLength;
        var u: UUID = undefined;
        @memcpy(&u.bytes, b);
        return u;
    }

    /// Parse any supported UUID format (canonical, braced, URN, 32-hex).
    /// Returns nil UUID on parse error — useful for initializing package-level
    /// variables from known-good literals (G-7).
    pub fn fromStringOrNil(s: []const u8) UUID {
        return UUID.fromString(s) catch UUID.nil;
    }

    /// Wrap a 16-byte slice — returns nil UUID on wrong length (G-7).
    pub fn fromBytesOrNil(b: []const u8) UUID {
        return UUID.fromBytes(b) catch UUID.nil;
    }

    /// Parse a UUID from any of the six supported string formats.
    ///
    /// **Accepted formats:**
    /// - Canonical (lowercase or uppercase, with dashes):
    ///   `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (36 chars)
    /// - Braced canonical:
    ///   `{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}` (38 chars)
    /// - 32-char hex (no dashes):
    ///   `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` (32 chars)
    /// - Braced hex:
    ///   `{xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx}` (34 chars)
    /// - URN canonical:
    ///   `urn:uuid:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (45 chars)
    /// - URN hex:
    ///   `urn:uuid:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` (41 chars)
    ///
    /// **Errors:**
    /// - `Error.InvalidURNPrefix` — starts with `urn:` but not `urn:uuid:`
    /// - `Error.InvalidBraces`   — opening `{` without closing `}`
    /// - `Error.InvalidLength`   — stripped string is not 36 or 32 chars
    /// - `Error.InvalidDashes`   — 36-char form has wrong dash positions
    /// - `Error.InvalidFormat`   — non-hex character encountered
    ///
    /// **Example:**
    /// ```zig
    /// const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    /// const u2 = try UUID.fromString("urn:uuid:6ba7b8109dad11d180b400c04fd430c8");
    /// ```
    pub fn fromString(s: []const u8) Error!UUID {
        // Detect and strip URN prefix (SEC-R8-03: case-insensitive per RFC 2141 §5).
        // The "urn:" scheme and "uuid:" NID are both case-insensitive.
        var rest = s;
        if (rest.len >= 9 and std.ascii.eqlIgnoreCase(rest[0..9], "urn:uuid:")) {
            rest = rest[9..];
        } else if (rest.len >= 4 and std.ascii.eqlIgnoreCase(rest[0..4], "urn:")) {
            return Error.InvalidURNPrefix;
        }

        // Detect and strip braces
        if (rest.len > 0 and rest[0] == '{') {
            if (rest[rest.len - 1] != '}') return Error.InvalidBraces;
            rest = rest[1 .. rest.len - 1];
        }

        return switch (rest.len) {
            36 => parseCanonical(rest), // with dashes
            32 => parseHash(rest), // no dashes
            else => Error.InvalidLength,
        };
    }

    /// Return the raw 16 bytes as a value copy (G-1).
    /// Equivalent to reading .bytes directly but more explicit at call sites.
    pub fn toBytes(self: UUID) [16]u8 {
        return self.bytes;
    }

    /// Canonical lowercase with dashes: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
    pub fn toString(self: UUID, buf: *[36]u8) []u8 {
        return toStringImpl(self, buf, "0123456789abcdef");
    }

    /// Canonical uppercase with dashes: `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX` (G-2)
    pub fn toStringUpper(self: UUID, buf: *[36]u8) []u8 {
        return toStringImpl(self, buf, "0123456789ABCDEF");
    }

    /// Lowercase hex without dashes: `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` (G-2)
    pub fn toHex(self: UUID, buf: *[32]u8) []u8 {
        return toHexImpl(self, buf, "0123456789abcdef");
    }

    /// Uppercase hex without dashes: `XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX` (G-2)
    pub fn toHexUpper(self: UUID, buf: *[32]u8) []u8 {
        return toHexImpl(self, buf, "0123456789ABCDEF");
    }

    /// URN format: `urn:uuid:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (F-5 / G-3).
    /// buf must be exactly 45 bytes.
    pub fn toURN(self: UUID, buf: *[45]u8) []u8 {
        @memcpy(buf[0..9], "urn:uuid:");
        _ = self.toString(buf[9..45]);
        return buf[0..45];
    }

    /// QC-97: shared body for the five `toXxxAlloc` wrappers. `encode` is the
    /// stack-encoding variant (`toURN`, `toString`, `toStringUpper`, `toHex`,
    /// `toHexUpper`) and `N` is the fixed output byte count for that variant.
    /// Kept `inline` so the generated code is a straight `alloc.dupe(...)`
    /// with no indirection at ReleaseFast.
    inline fn toAllocGeneric(
        self: UUID,
        alloc: std.mem.Allocator,
        comptime N: usize,
        comptime encode: fn (UUID, *[N]u8) []u8,
    ) ![]u8 {
        var buf: [N]u8 = undefined;
        return alloc.dupe(u8, encode(self, &buf));
    }

    /// Allocating URN format (F-5 / G-3). Returns heap-allocated 45-byte string; caller must free.
    /// **Hot path note:** the cost of the allocation is set by the `alloc`
    /// argument — an arena or bump allocator is effectively free, a GPA is a
    /// few hundred ns, and `std.heap.page_allocator` adds roughly ~1.8 us per
    /// call (see `docs/PERF_GAP_ANALYSIS.md` Cycle 3 measurements). Prefer
    /// `toURN(&buf)` (~6 ns/op) for performance-sensitive code.
    pub fn toURNAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        return self.toAllocGeneric(alloc, 45, toURN);
    }

    /// Allocating canonical lowercase with dashes: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.
    /// Returns a heap-allocated 36-byte string; caller must free with the same allocator.
    /// **Hot path note:** the cost of the allocation is set by `alloc` (see
    /// `toURNAlloc` for the arena-vs-page_allocator comparison). Prefer
    /// `toString(&buf)` (~6 ns/op) for performance-sensitive code.
    pub fn toStringAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        return self.toAllocGeneric(alloc, 36, toString);
    }

    /// Allocating uppercase string (G-2). Returns heap-allocated 36-byte string; caller must free.
    /// **Hot path note:** the cost of the allocation is set by `alloc` (see
    /// `toURNAlloc` for the arena-vs-page_allocator comparison). Prefer
    /// `toStringUpper(&buf)` (~6 ns/op) for performance-sensitive code.
    pub fn toStringUpperAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        return self.toAllocGeneric(alloc, 36, toStringUpper);
    }

    /// Allocating lowercase hex without dashes (QC-42). Returns heap-allocated 32-byte string; caller must free.
    /// **Hot path note:** the cost of the allocation is set by `alloc` (see
    /// `toURNAlloc` for the arena-vs-page_allocator comparison). Prefer
    /// `toHex(&buf)` (~5 ns/op) for performance-sensitive code.
    pub fn toHexAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        return self.toAllocGeneric(alloc, 32, toHex);
    }

    /// Allocating uppercase hex without dashes (QC-42). Returns heap-allocated 32-byte string; caller must free.
    /// **Hot path note:** the cost of the allocation is set by `alloc` (see
    /// `toURNAlloc` for the arena-vs-page_allocator comparison). Prefer
    /// `toHexUpper(&buf)` (~5 ns/op) for performance-sensitive code.
    pub fn toHexUpperAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
        return self.toAllocGeneric(alloc, 32, toHexUpper);
    }

    /// Format UUID as a canonical lowercase hyphenated string for use with
    /// `{f}` in std.fmt (Zig 0.15+). Example: `std.debug.print("{f}\n", .{u})`.
    pub fn format(self: UUID, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var buf: [36]u8 = undefined;
        try w.writeAll(self.toString(&buf));
    }

    // json adapters moved to src/uuid_json.zig (opt-in submodule) so the
    // core `uuid` module doesn't force a `json` dependency on downstream
    // consumers. Instantiating uuid from multiple build contexts with a
    // top-level json import caused duplicate-module diamond errors. The
    // json adapters remain available via `@import("uuid_json")` for
    // consumers that wire up the uuid-json submodule.
};

// --- private helpers ---

/// PERF-09: Fully unrolled UUID-to-canonical-string encoding.
///
/// Using `comptime hex` (compile-time-known table) + `inline for` with
/// comptime-tracked buffer offsets eliminates all runtime loop overhead:
/// no loop counter, no conditional dash check, hex table stays in registers.
/// The compiler emits 36 fixed-offset byte stores with no branches.
fn toStringImpl(self: UUID, buf: *[36]u8, comptime hex: *const [16]u8) []u8 {
    // Group 1: UUID bytes 0-3 → buf[0..7]
    comptime var pos: usize = 0;
    inline for (0..4) |i| {
        buf[pos] = hex[self.bytes[i] >> 4];
        buf[pos + 1] = hex[self.bytes[i] & 0x0F];
        pos += 2;
    }
    buf[pos] = '-';
    pos += 1;
    // Group 2: UUID bytes 4-5 → buf[9..12]
    inline for (0..2) |i| {
        buf[pos] = hex[self.bytes[4 + i] >> 4];
        buf[pos + 1] = hex[self.bytes[4 + i] & 0x0F];
        pos += 2;
    }
    buf[pos] = '-';
    pos += 1;
    // Group 3: UUID bytes 6-7 → buf[14..17]
    inline for (0..2) |i| {
        buf[pos] = hex[self.bytes[6 + i] >> 4];
        buf[pos + 1] = hex[self.bytes[6 + i] & 0x0F];
        pos += 2;
    }
    buf[pos] = '-';
    pos += 1;
    // Group 4: UUID bytes 8-9 → buf[19..22]
    inline for (0..2) |i| {
        buf[pos] = hex[self.bytes[8 + i] >> 4];
        buf[pos + 1] = hex[self.bytes[8 + i] & 0x0F];
        pos += 2;
    }
    buf[pos] = '-';
    pos += 1;
    // Group 5: UUID bytes 10-15 → buf[24..35]
    inline for (0..6) |i| {
        buf[pos] = hex[self.bytes[10 + i] >> 4];
        buf[pos + 1] = hex[self.bytes[10 + i] & 0x0F];
        pos += 2;
    }
    return buf[0..36];
}

/// PERF-09: Same inline-for optimization as toStringImpl.
fn toHexImpl(self: UUID, buf: *[32]u8, comptime hex: *const [16]u8) []u8 {
    inline for (0..16) |i| {
        buf[i * 2] = hex[self.bytes[i] >> 4];
        buf[i * 2 + 1] = hex[self.bytes[i] & 0x0F];
    }
    return buf[0..32];
}

/// PERF-10: Decode a single hex character to its 4-bit value.
/// A switch-with-ranges pattern that LLVM typically lowers to branchless code.
inline fn hexVal(c: u8) Error!u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => Error.InvalidFormat,
    };
}

/// PERF-10: Fixed-offset canonical UUID parse.
///
/// Dash positions are validated once upfront, then each of the 16 UUID bytes
/// is decoded at a compile-time-known string offset via `inline for`.  This
/// eliminates the loop counter variable, the `if (s[i] == '-') continue`
/// branch per iteration, and the post-loop `out != 16` check.
fn parseCanonical(s: []const u8) Error!UUID {
    // Validate dash positions: 8-4-4-4-12
    if (s[8] != '-' or s[13] != '-' or s[18] != '-' or s[23] != '-')
        return Error.InvalidDashes;

    // Precomputed string offsets for each of the 16 UUID bytes.
    // Groups: [0..7], [9..12], [14..17], [19..22], [24..35]
    // Verified: offsets[15] = 34, s[34]+s[35] encodes bytes[15]. ✓
    const offsets = comptime blk: {
        var off: [16]usize = undefined;
        var byte_i: usize = 0;
        var str_p: usize = 0;
        for ([5]usize{ 4, 2, 2, 2, 6 }, 0..) |n, gi| {
            if (gi > 0) str_p += 1; // skip dash
            var j: usize = 0;
            while (j < n) : (j += 1) {
                off[byte_i] = str_p;
                byte_i += 1;
                str_p += 2;
            }
        }
        break :blk off;
    };

    var u: UUID = undefined;
    inline for (offsets, 0..) |off, i| {
        const hi = try hexVal(s[off]);
        const lo = try hexVal(s[off + 1]);
        u.bytes[i] = (hi << 4) | lo;
    }
    return u;
}

/// PERF-14: Use `inline for` with comptime-constant offsets so the compiler
/// can unroll the 16-iteration loop and eliminate the runtime counter, matching
/// the pattern applied to parseCanonical in PERF-10.  Measured: 5 ns/op vs
/// 11 ns/op with the previous while-loop (2.2× improvement).
fn parseHash(s: []const u8) Error!UUID {
    var u: UUID = undefined;
    inline for (0..16) |i| {
        const hi = try hexVal(s[i * 2]);
        const lo = try hexVal(s[i * 2 + 1]);
        u.bytes[i] = (hi << 4) | lo;
    }
    return u;
}

// =============================================================================
// Tests — split to uuid_test.zig to keep this file under 800 lines (QC-65).
// =============================================================================

test {
    _ = @import("uuid_test.zig");
}
