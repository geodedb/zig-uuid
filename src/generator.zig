// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const builtin = @import("builtin");
const UUID = @import("uuid.zig").UUID;
const Version = @import("uuid.zig").Version;
const Variant = @import("uuid.zig").Variant;
const Error = @import("uuid.zig").Error;
const hwaddr = @import("hwaddr/hwaddr.zig");
const Timestamp = @import("timestamp.zig").Timestamp;

pub const ClockFn = *const fn () i128;
pub const RandFn = *const fn (buf: []u8) anyerror!void;
pub const HWAddrFn = *const fn () Error![6]u8;

/// QC-96 / PERF-28: single-source-of-truth resolver for the process-global
/// `std.Io` handle. Inlined so the generated code is identical to the
/// previous in-line `std.Io.Threaded.global_single_threaded.io()` expression
/// at ReleaseFast — this helper just centralizes the spelling and keeps
/// future handle-shape changes to one edit site.
inline fn gio() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn defaultClock() i128 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(.REALTIME, &ts);
    if (rc != 0) return 0;
    return @as(i128, ts.sec) * std.time.ns_per_s + @as(i128, ts.nsec);
}

fn defaultRand(buf: []u8) anyerror!void {
    gio().random(buf);
}

/// QC-99: Collapse the wide underlying filesystem / I/O error set that
/// `saveStateImpl` and `loadStateImpl` inherit from std.posix / std.Io.*
/// down to the library-level `Error` set. `Error`-typed errors (e.g.
/// `Error.InvalidFormat` returned by validation branches inside loadState)
/// pass through unchanged; every other error — permission denied, disk
/// full, path not found, symlink rejected by O_NOFOLLOW, cross-device
/// rename, etc. — becomes `Error.StateIoFailure`. Callers therefore see
/// a stable error surface.
fn mapStateError(err: anyerror) Error {
    return switch (err) {
        // Library-typed validation errors: pass through.
        Error.InvalidFormat => Error.InvalidFormat,
        Error.InvalidLength => Error.InvalidLength,
        Error.InvalidBraces => Error.InvalidBraces,
        Error.InvalidURNPrefix => Error.InvalidURNPrefix,
        Error.InvalidDashes => Error.InvalidDashes,
        Error.IncorrectByteLength => Error.IncorrectByteLength,
        Error.NoHWAddressFound => Error.NoHWAddressFound,
        Error.InvalidVersion => Error.InvalidVersion,
        Error.RandomError => Error.RandomError,
        Error.InvalidTimestamp => Error.InvalidTimestamp,
        Error.StateIoFailure => Error.StateIoFailure,
        Error.StateMacMismatch => Error.StateMacMismatch,
        Error.StateVersionDowngrade => Error.StateVersionDowngrade,
        // Anything else (OS/IO errors) → StateIoFailure.
        else => Error.StateIoFailure,
    };
}

/// Convert a raw nanosecond timestamp (i128) to a Unix millisecond value
/// (i64), returning error.InvalidTimestamp for values that are negative or
/// exceed the i64 range.
///
/// SEC-R4-01: This helper is used by newV7 *and* the spin-wait retry inside
/// newV7Locked so that both sites share the same guard logic.  Without this
/// helper, an injected clock function that returns an extreme i128 value
/// (negative or > maxInt(i64) * 1_000_000) causes @intCast to panic in Safe
/// builds or silently wrap in ReleaseFast.
fn clockToMs(ns: i128) Error!i64 {
    if (ns < 0) return Error.InvalidTimestamp;
    const ms_i128 = @divTrunc(ns, 1_000_000);
    if (ms_i128 > std.math.maxInt(i64)) return Error.InvalidTimestamp;
    return @intCast(ms_i128);
}

/// UUID generator with injectable clock, random, and hardware-address functions.
///
/// ## Shared V1/V6 clock domain
///
/// `newV1AtTime` and `newV6AtTime` share a single `clock_seq` counter and
/// `last_v1_ts` high-water mark.  Both UUID versions use the Gregorian-epoch
/// timestamp format and belong to the same clock domain per RFC-9562 §6.1.
/// Callers that interleave V1 and V6 calls on the same Generator will observe
/// clock_seq increments driven by both versions — this is architecturally
/// correct but may be surprising.  If you need independent clock domains, use
/// two separate Generator instances.
///
/// ## Default node-ID behaviour (F-1)
///
/// By default (`hwaddr_fn = null`) V1 and V6 UUIDs use a random 6-byte node
/// ID with the multicast bit set (RFC-9562 §6.10).  This prevents leaking the
/// host's hardware address to UUID recipients.  To opt in to MAC-based node
/// IDs, set `hwaddr_fn` explicitly or use `Generator.withHWAddr()`.
///
/// The node ID is cached for the lifetime of the generator (F-6/G-6).  Call
/// `clearNodeCache()` to force a re-fetch on the next V1/V6 generation.
///
/// ## V7 throughput ceiling (PERF-13)
///
/// RFC-9562 §6.2 limits the rand_a counter to 12 bits = **4,096 values/ms**
/// per generator.  A single Generator can sustain at most ~4 million V7
/// UUIDs/sec.  For higher rates, create one Generator per thread:
///
/// ```zig
/// threadlocal var tl_gen: Generator = Generator.init();
/// pub fn nextV7() !UUID { return tl_gen.newV7(); }
/// ```
///
/// Each per-thread generator maintains its own counter; all generators share
/// the same ms timestamp field, so sort order is preserved across threads.
/// For rates >4M/sec with strict per-generator monotonicity, use newV7AtTime
/// with V8 for the extra sub-ms bits.
pub const Generator = struct {
    /// PERF-23: `clock` and `rand` are nullable function pointers. When
    /// they are null (the common case for untouched `Generator.init()`),
    /// the hot paths call the default helpers directly (`defaultClock` /
    /// `defaultRand`), which LLVM can inline through to the underlying
    /// syscall / CSPRNG read. A non-null value still dispatches through
    /// the pointer at the same cost as the previous design. The net
    /// result is a cheaper fast path for the default generator without
    /// changing observable behaviour for callers of `withClock` /
    /// `withRand`.
    clock: ?ClockFn = null,
    rand: ?RandFn = null,

    /// SEC-P3-08: explicit CSPRNG source supplied via `InitOptions.random`.
    /// When non-null, `randCall` fills the destination buffer by invoking
    /// `rand_impl.?.bytes(buf)` (wrapping `std.Random.bytes`), bypassing
    /// both the module-level global `std.Io` and any `rand` RandFn that a
    /// prior `withRand` call would have set.  `rand_impl` has priority
    /// over `rand`, which has priority over the global default — giving
    /// callers who inject at construction time the strongest guarantee.
    rand_impl: ?std.Random = null,

    /// Optional hardware-address function (F-1). When null (the default), V1
    /// and V6 UUIDs use a random multicast node ID, protecting privacy per
    /// RFC-9562 §8.  Set this field (or use withHWAddr) to opt in to
    /// MAC-based node IDs.
    hwaddr_fn: ?HWAddrFn = null,

    /// SEC-P3-04: optional 32-byte key for HMAC-SHA256 authentication of
    /// the persisted state file.  When set, `saveState` writes the new
    /// wire-format version 3 (v2 payload || 32-byte HMAC-SHA256(payload,
    /// key)), and `loadState` refuses to accept any v3 file whose trailer
    /// does not verify under this key.  A null key keeps saveState on the
    /// legacy v2 format, which loadState continues to accept unchanged.
    ///
    /// **Key management is the caller's responsibility.** Rotate keys by
    /// loading under the old key, re-saving under the new key, and
    /// destroying the old key afterwards.  Store the key in the same
    /// security tier as the state file itself (e.g. Linux kernel keyring,
    /// systemd-credentials, Vault Transit, AWS KMS data-key).  Do NOT
    /// hard-code the key in source.
    state_mac_key: ?[32]u8 = null,

    /// SEC-P4-01: see `StateMacPolicy` + `InitOptions.state_mac_policy`.
    /// Set via `initOptions`; `init`/`withClock`/`withRand`/`withHWAddr`
    /// all use the safe default `.require_mac_when_keyed`.
    state_mac_policy: StateMacPolicy = .require_mac_when_keyed,

    /// SEC-P4-03: instance-field rollback tolerance.  Default is
    /// `default_clock_rollback_tolerance_ms` (250 ms); override via
    /// `InitOptions.clock_rollback_tolerance_ms`.  Value is clamped
    /// to `[0, 60_000]` in `initOptions`.
    clock_rollback_tolerance_ms: i64 = default_clock_rollback_tolerance_ms,

    /// PERF-21: opt-in lock-free V7 path.  When true, `newV7` updates
    /// monotonicity state via a CAS loop over a packed `(ms:52)|(seq:12)`
    /// `u64` instead of the `v7.mutex`.  The lock-free path is wait-free
    /// for threads that do not race; on contention threads retry their CAS
    /// with fresh state, preserving RFC-9562 §6.2 strict monotonicity.
    /// On mono_seq saturation (12-bit counter exhausted within one ms)
    /// the path delegates to the mutex-protected `newV7Locked`, which
    /// sleeps precisely to the next ms boundary.  Default false (mutex
    /// path remains authoritative).  See `newV7Atomic` for the algorithm.
    v7_lockfree: bool = false,

    /// PERF-21: packed atomic V7 state `(ms:52)|(seq:12)` where `ms` is
    /// the Unix millisecond timestamp (up to ~142,808 years ≫ u48) and
    /// `seq` is the 12-bit RFC-9562 rand_a counter.  Only read/written
    /// by the lock-free path.  Initial value 0 means "no prior V7 emit";
    /// the first call observes `old_ms = 0` and takes the new-ms branch.
    v7_atomic_state: std.atomic.Value(u64) align(64) = std.atomic.Value(u64).init(0),

    /// SEC-P4-08 + PERF-40: diagnostic counters that are written by the
    /// hot path (saturation fallback) and read by external observers
    /// (`lockfreeFallbackCount()` / benches).  Wrapped in an `align(64)`
    /// sub-struct with trailing pad so the counter owns its own cache
    /// line — earlier (Phase-3) the raw `_v7_lockfree_fallbacks` field
    /// landed at offset 248 and shared cache line 3 (offsets 192-255)
    /// with the dispatch-pointer cluster (`clock`, `rand`, `rand_impl`,
    /// `hwaddr_fn`, `clock_rollback_tolerance_ms`).  Every newV* call
    /// reads that line; every saturation `fetchAdd` invalidated it on
    /// all readers (MESI ping-pong on a line the hot path touches on
    /// every call).  The witness is `test "PERF-40: stats on isolated
    /// cache line"` in generator_test.zig.
    ///
    /// The counter remains nested behind `stats.` so callers cannot
    /// fingerprint contention via direct atomic reads — public access
    /// goes through `lockfreeFallbackCount()` (one-shot observation
    /// contract; do not poll at high frequency).
    stats: struct {
        v7_lockfree_fallbacks: std.atomic.Value(u64) align(64) = std.atomic.Value(u64).init(0),
        // Trailing pad so the sub-struct's total footprint is exactly
        // one cache line.  Without this, a neighbouring field could
        // pack into the remaining 56 B of the `align(64)` slot and
        // re-introduce false sharing on the next bump.
        _pad: [56]u8 = [_]u8{0} ** 56,
    } align(64) = .{},

    // PERF-19: Two independent mutexes for V7 and V1/V6 clock domains.
    // V7 generation only acquires v7.mutex; V1/V6 generation only acquires
    // v1v6.mutex.  saveState/loadState acquire both in fixed order
    // (v7.mutex first, then v1v6.mutex) to prevent deadlock.

    // PERF-29 / PERF-33: V7 and V1/V6 monotonicity state live in
    // nested `align(64)` structs so Zig's field-reorder pass cannot
    // pack small-aligned fields from either cluster across the
    // cache-line boundary.  The earlier `[0]u8 align(64)` separator
    // was insufficient — the compiler treated zero-size fields as
    // no-storage and happily hoisted `v1v6.mutex`, `clock_seq`,
    // `last_v1_ts` into the tail of the V7 line.  Nested structs
    // create a hard boundary that reorder cannot cross.
    //
    // The order of fields inside each cluster keeps the cluster's
    // total footprint ≤ 64 bytes so the mutex and its protected
    // small fields share one line (intra-cluster co-location is
    // desirable; inter-cluster is the regression we guard against).
    //
    // The witness is `test "PERF-34: V7 and V1V6 clusters occupy
    // distinct cache lines"` in generator_test.zig — if the layout
    // ever regresses, the test fails at compile-time-evaluated
    // @offsetOf and the build stops.

    /// V7 monotonicity state (protected by `v7.mutex`).
    v7: struct {
        mutex: std.Io.Mutex align(64) = std.Io.Mutex.init,
        last_ms: i64 = 0,
        mono_seq: u12 = 0,
    } align(64) = .{},

    /// V1/V6 shared clock state (protected by `v1v6.mutex`; F-8).
    v1v6: struct {
        mutex: std.Io.Mutex align(64) = std.Io.Mutex.init,
        clock_seq: u14 = 0,
        clock_seq_initialized: bool = false,
        last_v1_ts: u60 = 0,
    } align(64) = .{},

    /// Cached node ID for V1/V6 generation (F-4 + F-6/G-6).
    ///
    /// PERF-27 (CWE-362): the cold-path `hasNodeCache()` fast-path reads
    /// this cache outside `v1v6.mutex` to decide whether the caller must
    /// pre-fetch a node ID. A plain read of an `?[6]u8` in parallel with
    /// the writer under the lock is a data race. Instead we split the
    /// logical "cache" into a valid-flag plus a byte buffer:
    ///   - `node_cache_valid` is a `std.atomic.Value(bool)` — readers
    ///     acquire-load it; writers under the lock store true with
    ///     release order AFTER populating `node_cache_bytes`.
    ///   - `node_cache_bytes` is read only when the flag is true;
    ///     the acquire/release pair provides the happens-before edge
    ///     that makes the byte read safe.
    /// Under the lock, code uses `storeNodeCache`, `loadNodeCacheBytes`,
    /// and `clearNodeCacheLocked` helpers to keep the two fields coherent.
    node_cache_valid: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    node_cache_bytes: [6]u8 = [_]u8{0} ** 6,

    /// Previously-used node ID for change detection (F-4).
    last_node: ?[6]u8 = null,

    /// PERF-23 hot-path: resolve the clock function.  When `clock` is null
    /// we call `defaultClock` directly so LLVM can inline the
    /// `clock_gettime` wrapper; when it is non-null we dispatch via the
    /// stored pointer with the same cost as a direct call.
    inline fn clockCall(self: *Generator) i128 {
        return if (self.clock) |f| f() else defaultClock();
    }

    /// PERF-23 / SEC-P3-08 hot-path: resolve the rand source.  Priority:
    ///   1. `rand_impl` (explicit `std.Random` from `InitOptions.random`).
    ///   2. `rand` (RandFn from `withRand`).
    ///   3. `defaultRand` (global `std.Io` CSPRNG).
    /// The default path reaches the CSPRNG without a pointer indirection;
    /// the injected paths dispatch through the stored source with the
    /// same cost as a direct call.
    inline fn randCall(self: *Generator, buf: []u8) anyerror!void {
        if (self.rand_impl) |r| {
            // std.Random.bytes never fails — it is a straight fill-fn
            // call — so map it into the library's RandFn signature with a
            // noop on the error side.  Preserves the RandFn contract.
            r.bytes(buf);
            return;
        }
        if (self.rand) |f| {
            return f(buf);
        } else {
            return defaultRand(buf);
        }
    }

    /// PERF-27 fast-path: is the node cache populated? Acquire-loads the
    /// atomic flag so a subsequent `loadNodeCacheBytes` under the lock is
    /// guaranteed to read the bytes written by the last storeNodeCache.
    inline fn hasNodeCache(self: *Generator) bool {
        return self.node_cache_valid.load(.acquire);
    }

    /// Caller MUST hold `v1v6.mutex`. Returns the cached bytes; only valid
    /// when `hasNodeCache()` previously returned true (or the same mutex
    /// section wrote them).
    inline fn loadNodeCacheBytes(self: *Generator) [6]u8 {
        return self.node_cache_bytes;
    }

    /// Caller MUST hold `v1v6.mutex`. Writes the bytes then publishes the
    /// valid-flag with release order so that any reader that acquire-loads
    /// `node_cache_valid == true` observes the matching bytes.
    inline fn storeNodeCache(self: *Generator, node: [6]u8) void {
        self.node_cache_bytes = node;
        self.node_cache_valid.store(true, .release);
    }

    /// Caller MUST hold `v1v6.mutex`. Drops the cached node; next
    /// `hasNodeCache()` returns false until a subsequent storeNodeCache.
    inline fn clearNodeCacheLocked(self: *Generator) void {
        self.node_cache_valid.store(false, .release);
    }

    /// SEC-P4-01: policy controlling how `loadState` handles unauthenticated
    /// state files (wire-format v1 or v2) when the generator has a
    /// `state_mac_key` configured.
    ///
    /// The default is `.require_mac_when_keyed` — when the caller has set a
    /// key, only v3 (HMAC-authenticated) files are accepted.  v1/v2 files
    /// are rejected with `Error.StateVersionDowngrade` so a local attacker
    /// cannot silently downgrade the file by stripping the trailer.  The
    /// looser `.any` policy restores the pre-SEC-P4-01 behaviour (v1/v2
    /// accepted with a `std.log.warn`) for callers mid-rotation; the
    /// stricter `.require_mac_always` rejects v1/v2 unconditionally, even
    /// when no key is configured — useful for defense-in-depth in fresh
    /// deployments that never shipped without HMAC.
    pub const StateMacPolicy = enum {
        /// Accept any state-file version; emit a warn on v1/v2 when a key
        /// is set (legacy behaviour).  Use mid-rotation or during one-shot
        /// migrations.
        any,
        /// Default.  Reject v1/v2 with `Error.StateVersionDowngrade` when
        /// a `state_mac_key` is configured; accept v1/v2 normally when no
        /// key is configured.
        require_mac_when_keyed,
        /// Reject v1/v2 with `Error.StateVersionDowngrade` unconditionally.
        require_mac_always,
    };

    /// Options for `Generator.init(opts)` (SEC-P3-08).
    ///
    /// Every field is optional; `.{}` is equivalent to the historical
    /// `init()` with all defaults.
    ///
    /// ### `random` — explicit CSPRNG injection (SEC-P3-08)
    ///
    /// When non-null, the supplied `std.Random` instance is used for every
    /// V4 / V7 entropy read the generator performs, replacing the default
    /// path through `std.Io.Threaded.global_single_threaded.io().random()`.
    ///
    /// **Why this matters:** the default path resolves the process-global
    /// `std.Io` at every call.  A hostile library loaded into the same
    /// address space could in principle substitute that module-level var
    /// to poison every consumer of `Generator.init(.{})`.  Passing a
    /// caller-owned `std.Random` bound to a vetted CSPRNG (e.g. a
    /// `std.Random.ChaCha` reseeded from `std.Io.randomSecure`, or a
    /// `std.Random.IoSource` wrapping an `std.Io` the caller controls)
    /// defeats that attack vector by removing the global from the hot
    /// path entirely.
    ///
    /// The supplied `std.Random` is stored as a flat interface value
    /// inside the Generator; callers must ensure the backing storage
    /// outlives the Generator.  `std.Random` is already a trivially-
    /// copyable `{ ptr, fillFn }` pair, so storing it by value is safe.
    pub const InitOptions = struct {
        /// SEC-P3-08: explicit CSPRNG source.  Null means fall back to the
        /// global I/O handle (the historical behaviour).
        random: ?std.Random = null,

        /// Optional override for the monotonic / wall clock.  Matches the
        /// same field on `withClock` — callers that want both a custom
        /// clock and explicit random injection can set both fields here.
        clock: ?ClockFn = null,

        /// Optional override for the hardware-address source used to
        /// derive V1 / V6 node IDs.  Matches the same field on
        /// `withHWAddr`.
        hwaddr_fn: ?HWAddrFn = null,

        /// SEC-P3-04: 32-byte key for HMAC-SHA256 authentication of the
        /// state file.  See `Generator.state_mac_key` for semantics.  The
        /// key is copied into the returned `Generator`; the caller may
        /// zero the source buffer immediately after `initOptions` returns.
        state_mac_key: ?[32]u8 = null,

        /// SEC-P4-01: policy controlling unauthenticated-state-file
        /// acceptance in `loadState`.  Default `.require_mac_when_keyed`
        /// rejects v1/v2 with `Error.StateVersionDowngrade` when
        /// `state_mac_key` is set; see `StateMacPolicy` for details.
        /// **Behaviour change** — pre-SEC-P4-01 callers that relied on
        /// v1/v2 being accepted with a warn must either set this to
        /// `.any` explicitly or call `Generator.migrateStateToV3`
        /// once to upgrade the on-disk file to v3.
        state_mac_policy: StateMacPolicy = .require_mac_when_keyed,

        /// SEC-P4-03: override the default clock-rollback tolerance
        /// (`Generator.default_clock_rollback_tolerance_ms` = 250 ms).
        /// Clamped to `[0, 60_000]` by `initOptions` to prevent
        /// accidental disables (via maxInt) and negative values.  Null
        /// keeps the default; set to 0 to reject ANY backward clock
        /// motion; larger values widen the accepted window for
        /// deployments with known-bad clocks.
        clock_rollback_tolerance_ms: ?i64 = null,

        /// PERF-21: opt into the lock-free V7 path.  Default false keeps
        /// the mutex-protected path (unchanged behaviour).  See
        /// `Generator.v7_lockfree` for algorithmic details.
        v7_lockfree: bool = false,
    };

    /// SEC-P4-08: read the lockfree-fallback counter.  Intended for
    /// diagnostic / bench reporting — do NOT poll at high frequency.
    /// Relaxed load since the counter is a loose contention signal
    /// rather than a synchronising observable.
    pub fn lockfreeFallbackCount(self: *const Generator) u64 {
        return self.stats.v7_lockfree_fallbacks.load(.monotonic);
    }

    /// Create a new generator with default clock (std.time.nanoTimestamp),
    /// CSPRNG (std.Io.random), and random multicast node ID.
    ///
    /// This is equivalent to `initOptions(.{})`.  The zero-arg form is
    /// retained for source compatibility with the historical API.
    pub fn init() Generator {
        return .{};
    }

    /// SEC-P3-08: create a generator with caller-specified options.  See
    /// `InitOptions` for the individual fields and the rationale behind
    /// explicit `std.Random` injection.
    pub fn initOptions(options: InitOptions) Generator {
        if (options.random) |r| assertRandNotKnownWeak(r);
        return .{
            .clock = options.clock,
            .rand_impl = options.random,
            .hwaddr_fn = options.hwaddr_fn,
            .state_mac_key = options.state_mac_key,
            .state_mac_policy = options.state_mac_policy,
            .clock_rollback_tolerance_ms = clampRollbackTolerance(options.clock_rollback_tolerance_ms),
            .v7_lockfree = options.v7_lockfree,
        };
    }

    /// SEC-P4-09: debug-mode sanity check that `random` is not
    /// obviously weak for UUID generation.  Release builds strip the
    /// check entirely via the `builtin.mode == .Debug` gate, so there
    /// is zero production overhead.  Defense-in-depth only — NOT a
    /// security boundary: a hostile library can disguise any PRNG with
    /// any vtable, so the check catches honest-mistake wiring (dev
    /// harness leaked into production) but not adversarial injection.
    ///
    /// Current implementation is a minimal smoke check on the `fillFn`
    /// function pointer (it must not be a zero/garbage address).  A
    /// comprehensive pattern-match against `std.Random.DefaultPrng`
    /// (Xoshiro256) and siblings would depend on the address of the
    /// anonymous wrapper struct's `fill` method generated by
    /// `std.Random.init` — that address is not exposed as a stable
    /// symbol and may not be comparable across Zig stdlib revisions.
    /// Per the stdlib's own comment on `std.Random.ptr`, direct
    /// comparison of that field is illegal behavior (it may be
    /// `undefined` when the PRNG has no associated state).  A future
    /// hardening could add structural pattern matching if stdlib
    /// stabilises the PRNG vtable layout.
    fn assertRandNotKnownWeak(r: std.Random) void {
        if (builtin.mode == .Debug) {
            // Function pointers in Zig are non-optional, but a
            // zero-initialized struct (e.g. caller forgot to call
            // `.random()` on the PRNG and passed a default-init'd
            // `std.Random{}`) would leave `fillFn` at address 0.
            std.debug.assert(@intFromPtr(r.fillFn) != 0);
        }
    }

    fn clampRollbackTolerance(opt: ?i64) i64 {
        const raw = opt orelse default_clock_rollback_tolerance_ms;
        // Clamp to [0, 60_000] — 60s is the practical upper bound for
        // NTP + reasonable VM-suspend recovery; beyond that, the caller
        // should call resetState() rather than widen the tolerance.
        if (raw < 0) return 0;
        if (raw > 60_000) return 60_000;
        return raw;
    }

    /// Create a generator with a custom clock function, useful for testing
    /// or deterministic UUID generation.  The clock function must return
    /// the current time in nanoseconds as an i128.
    pub fn withClock(f: ClockFn) Generator {
        var g = Generator.init();
        g.clock = f;
        return g;
    }

    /// Create a generator with a custom random function, useful for testing
    /// or deterministic UUID generation.  The function fills the provided
    /// buffer with random bytes.
    pub fn withRand(f: RandFn) Generator {
        var g = Generator.init();
        g.rand = f;
        return g;
    }

    /// Create a generator that uses f to obtain the hardware address for V1/V6
    /// node IDs (F-1: explicit opt-in to MAC-based nodes).
    pub fn withHWAddr(f: HWAddrFn) Generator {
        var g = Generator.init();
        g.hwaddr_fn = f;
        return g;
    }

    /// Force the next V1/V6 generation to re-fetch the node ID (F-6/G-6).
    /// If the node ID changes after a re-fetch, clock_seq is incremented (F-4).
    ///
    /// SEC-R6-01: Acquires v1v6.mutex before writing node_cache so that the
    /// write is not concurrent with resolveV1V6State (which also reads and
    /// writes node_cache under the same mutex).  Without this lock, a race
    /// exists between clearNodeCache and any in-flight V1/V6 generation.
    pub fn clearNodeCache(self: *Generator) void {
        self.v1v6.mutex.lockUncancelable(gio());
        defer self.v1v6.mutex.unlock(gio());
        self.clearNodeCacheLocked();
    }

    /// SEC-P3-01 (CWE-331 / CWE-665): clear all CSPRNG-derived cached state
    /// and the V1/V6/V7 monotonicity counters so the next UUID generation
    /// re-samples fresh random bytes from the current CSPRNG.
    ///
    /// **Intended use — post-fork():** On POSIX, `fork(2)` duplicates the
    /// parent's entire address space, including any cached CSPRNG state
    /// held by this Generator (clock_seq, mono_seq, node_cache).  Two
    /// processes that proceed to mint UUIDs from identical cached state
    /// will collide with each other until those caches naturally roll
    /// over.  Zig 0.16's standard library does NOT expose a portable
    /// `pthread_atfork` hook, and Windows has no fork at all — so the
    /// library cannot register an automatic handler.  Callers that fork
    /// must invoke `reseed()` from the child process before any UUID
    /// generation.
    ///
    /// **Thread safety:** acquires both mutexes in the library's
    /// canonical order (v7 first, then v1v6).  Safe to call from any
    /// thread, but post-fork the child is single-threaded so contention
    /// is a non-issue.
    ///
    /// **Does NOT** touch `self.clock` / `self.rand` / `self.hwaddr_fn`
    /// injection points — those remain pointer-stable across fork by
    /// virtue of being code addresses.
    pub fn reseed(self: *Generator) void {
        self.v7.mutex.lockUncancelable(gio());
        defer self.v7.mutex.unlock(gio());
        self.v1v6.mutex.lockUncancelable(gio());
        defer self.v1v6.mutex.unlock(gio());
        self.v1v6.clock_seq = 0;
        self.v1v6.clock_seq_initialized = false; // forces CSPRNG re-sample on next V1/V6
        self.v1v6.last_v1_ts = 0;
        self.v7.last_ms = 0;
        self.v7.mono_seq = 0;
        // SEC-P4-10 (CWE-665 / CWE-331): the lock-free V7 path keeps its
        // own (ms, seq) packed monotonicity word in `v7_atomic_state`.
        // reseed() must zero this alongside the mutex-path counters so a
        // forked child does not inherit the parent's seq and emit ≤ 4096
        // V7 IDs with a deterministic 12-bit suffix.  Release ordering
        // pairs with the acquire load at the top of `newV7Atomic`.
        self.v7_atomic_state.store(0, .release);
        self.clearNodeCacheLocked(); // forces node re-fetch (and re-randomise if default)
        self.last_node = null;
    }

    /// Securely zero the HMAC state-file key (`state_mac_key`) and clear it
    /// to `null`.
    ///
    /// Callers that configured a `state_mac_key` (SEC-P3-04) and hold the
    /// Generator across a long-lived process should invoke this before the
    /// Generator leaves scope, the process forks an untrusted child, or a
    /// core dump could be taken, so key bytes don't linger in process
    /// memory.  Uses `std.crypto.secureZero` (volatile write) to prevent
    /// the compiler from eliding the zeroization as a dead-store.
    ///
    /// Idempotent: safe to call when no key is configured.
    ///
    /// After this call `state_mac_key` is `null`, so subsequent `saveState`
    /// emits wire-format v2 and `loadState` refuses v3 files with
    /// `Error.StateMacMismatch`.  Re-supply a key via `initOptions` if v3
    /// semantics are needed again.
    pub fn secureWipeMacKey(self: *Generator) void {
        if (self.state_mac_key) |*key_ptr| {
            std.crypto.secureZero(u8, key_ptr);
        }
        self.state_mac_key = null;
    }

    /// Generate a UUIDv4 (random).
    ///
    /// All 122 non-version/variant bits are filled from the CSPRNG source.
    /// Returns `Error.RandomError` if the underlying random function fails.
    pub fn newV4(self: *Generator) Error!UUID {
        var u: UUID = undefined;
        self.randCall(&u.bytes) catch return Error.RandomError;
        u.setVersion(.v4);
        u.setVariant(.rfc9562);
        return u;
    }

    /// Generate a UUIDv7 (Unix Epoch timestamp + monotonic counter + random).
    ///
    /// **Throughput ceiling (PERF-13):** RFC-9562 §6.2 limits the rand_a field
    /// to 12 bits = **4,096 values per millisecond**.  At the ceiling a Generator
    /// waits for the next ms boundary before issuing the next UUID.  Sustained
    /// throughput is therefore capped at **~4 million UUIDs/sec per Generator**.
    ///
    /// To exceed this limit while preserving sort order, shard across multiple
    /// generators — one per thread or per tenant — since each generator has its
    /// own independent counter.  Use newV7AtTime with a shared clock source to
    /// keep the timestamp field monotone across shards.
    pub fn newV7(self: *Generator) Error!UUID {
        // PERF-21: dispatch to the lock-free path when opted-in.  The
        // mutex path remains the default and the correctness-authoritative
        // reference implementation.
        if (self.v7_lockfree) return self.newV7Atomic();

        // PERF-07: Read clock inside the mutex to use the freshest possible
        // timestamp and avoid stale-timestamp collisions under high contention.
        self.v7.mutex.lockUncancelable(gio());
        var ms = clockToMs(self.clockCall()) catch |err| {
            self.v7.mutex.unlock(gio());
            return err;
        };
        // SEC-R14-02 (CWE-1284): If the system clock jumped backward (NTP
        // correction, VM migration), preserve last_ms to maintain V7 k-sortable
        // monotonicity.  This only applies to clock-derived timestamps; user-
        // provided timestamps via newV7AtTime are accepted as-is.
        if (ms < self.v7.last_ms) ms = self.v7.last_ms;
        return self.newV7Locked(ms);
    }

    // =========================================================================
    // PERF-21: lock-free V7 CAS path.
    //
    // Layout: a single u64 packed as `(ms << 12) | seq`, where `ms` is the
    // 48-bit-plus Unix millisecond timestamp and `seq` is the 12-bit rand_a
    // counter (RFC-9562 §6.2).  ms occupies bits 12..64 (52 bits — enough
    // for ms values well past year 144,000), seq occupies bits 0..12.
    //
    // Algorithm:
    //   1.  Read the current clock (outside the CAS loop).
    //   2.  Snapshot old_state with acquire order.
    //   3.  If clock_ms > old_ms      → new_ms = clock_ms, new_seq = CSPRNG u12
    //       else (clock regressed or same ms):
    //           new_ms = old_ms
    //           if old_seq == 0xFFF   → saturation: fall back to mutex path.
    //           else                  → new_ms = old_ms, new_seq = old_seq + 1.
    //   4.  cmpxchgStrong(old, new, acq_rel, acquire).  On failure loop.
    //   5.  On success emit the UUID outside the CAS loop: assemble bytes
    //       and sample the 62-bit rand_b from the CSPRNG.
    //
    // Monotonicity argument:
    //   - A successful CAS publishes (ms, seq) strictly greater than any
    //     `(ms, seq)` observed by a concurrent thread that will later
    //     succeed (either ms advances, or seq increments).
    //   - Two threads that observe the same old_state will both propose
    //     either (a) the same clock_ms → same ms, different seq candidates
    //     (but only one wins the CAS; the loser retries and observes the
    //     winner's new state, forcing it into the increment branch), or
    //     (b) different clock_ms — again, only one wins; the loser retries
    //     with refreshed state.  In neither case can two UUIDs share the
    //     same `(ms, seq)` pair.
    //
    // rand_b (62 bits) is sampled from the CSPRNG *after* the CAS succeeds,
    // so failed candidates waste at most 2 bytes of random (the seq
    // candidate), never the full 8-byte rand_b read.
    // =========================================================================

    /// PERF-21: pack `(ms:52, seq:12)` into a u64.  `ms` must fit in the
    /// low 52 bits; the caller enforces this by clamping to the previous
    /// value on regression.  `seq` is a 12-bit value.
    inline fn v7PackState(ms: u64, seq: u12) u64 {
        return (ms << 12) | @as(u64, seq);
    }

    inline fn v7UnpackMs(packed_state: u64) u64 {
        return packed_state >> 12;
    }

    inline fn v7UnpackSeq(packed_state: u64) u12 {
        return @truncate(packed_state & 0x0FFF);
    }

    /// PERF-21: saturation counter increment used by the fallback branch.
    /// Public-ish for tests (via `@field`) but not re-exported at the
    /// library level.
    inline fn bumpFallback(self: *Generator) void {
        _ = self.stats.v7_lockfree_fallbacks.fetchAdd(1, .monotonic);
    }

    /// PERF-21: lock-free V7 generation.  See the comment block above for
    /// the full algorithm and monotonicity argument.
    ///
    /// On saturation (12-bit counter exhausted inside one ms) we do NOT
    /// delegate to the mutex path — the two paths maintain independent
    /// sequence state and mixing them would produce a non-monotonic
    /// stream (the lockfree state at (M, 0xFFF) is invisible to the
    /// mutex's self.v7.mono_seq, and vice versa).  Instead the lockfree
    /// path spin-sleeps to the next ms boundary under a short sleep per
    /// iteration, re-reads the clock, and retries the CAS.  This keeps
    /// the lockfree path self-contained and preserves monotonicity.
    fn newV7Atomic(self: *Generator) Error!UUID {
        const io_h = gio();

        // SEC-P4-A1: total retry budget across all CAS attempts (including
        // spin-wait retries on saturation).  Tightened from 32_768 → 4096:
        // RFC-9562 §6.2 fixes the per-ms `rand_a` counter width at 12 bits,
        // so 4096 emits exhaust the same-ms slot by pigeonhole.  An injected
        // clock that freezes time can otherwise drive the spin-sleep branch
        // 32_768 times — each iteration sleeps ~1 ms — collapsing observed
        // throughput by ~8× when the adversary holds the clock.  4096 still
        // accommodates legitimate contention (every CAS-loss thread sees
        // monotonic progress within a single ms-window) while bounding the
        // worst-case wall clock to a few ms.
        //
        // Note: a separate wall-clock budget would be a stronger guarantee
        // but is more invasive; deferred.  4096 is an upper bound on the
        // *legitimate* same-ms throughput per RFC-9562, so any retry beyond
        // it is by definition a malformed clock or pathological contention.
        const max_retries: usize = 4096;
        var retries: usize = 0;

        var committed_ms: u64 = 0;
        var committed_seq: u12 = 0;

        // Lazily-drawn seq entropy reused across retries of the clock-advance
        // branch.  Originally the 2-byte CSPRNG draw lived inside the loop;
        // on CAS loss the bytes were wasted.  Drawn at most ONCE per call:
        //   - If the first iteration takes the same-ms branch (seq+1), the
        //     draw is skipped entirely.
        //   - If the clock-advance branch is entered and we lose CAS, most
        //     retries fall into the same-ms branch (another thread already
        //     committed the new ms), so the cached bytes go unused — not
        //     leaked, the thread never emits a UUID with them.
        //   - If the retry re-enters the clock-advance branch (clock jumps
        //     again), reusing the same random bits is still safe: each
        //     successful CAS emits one UUID, so the bits are published at
        //     most once per call.
        var rand_seq_cached: u12 = undefined;
        var rand_seq_drawn: bool = false;

        while (true) : (retries += 1) {
            if (retries >= max_retries) {
                // Pathological contention with a frozen clock — treat as
                // an invalid timestamp so callers see a bounded failure
                // instead of an infinite spin.
                self.bumpFallback();
                return Error.InvalidTimestamp;
            }

            const clock_ms = try clockToMs(self.clockCall());
            const clock_ms_u: u64 = @intCast(clock_ms);

            const old = self.v7_atomic_state.load(.acquire);
            const old_ms = v7UnpackMs(old);
            const old_seq = v7UnpackSeq(old);

            var new_ms: u64 = undefined;
            var new_seq: u12 = undefined;
            if (clock_ms_u > old_ms) {
                // Clock advanced: seed seq from CSPRNG jitter per
                // RFC-9562 §6.2.  Draw is cached at function scope so a
                // CAS-lost thread that re-enters this branch does not
                // burn more entropy (see the `rand_seq_drawn` comment
                // above the loop).
                if (!rand_seq_drawn) {
                    var rand_seq: [2]u8 = undefined;
                    self.randCall(&rand_seq) catch return Error.RandomError;
                    rand_seq_cached = @truncate(std.mem.readInt(u16, &rand_seq, .little) & 0x0FFF);
                    rand_seq_drawn = true;
                }
                new_ms = clock_ms_u;
                new_seq = rand_seq_cached;
            } else {
                // Clock at or behind old_ms — preserve old_ms for
                // monotonicity (SEC-R14-02).  If the counter has saturated
                // we sleep to the next ms boundary and retry; otherwise
                // we bump the counter.
                if (old_seq == std.math.maxInt(u12)) {
                    self.bumpFallback();
                    // Sleep precisely to the next ms boundary.  Use the
                    // ns remainder of the current clock reading to pick
                    // the sleep length (matches the mutex path's PERF-12
                    // approach).  On the next loop iteration we re-read
                    // the clock — it should now be >= old_ms + 1.
                    const ns_now = self.clockCall();
                    const sleep_ns: u64 = if (ns_now > 0) blk: {
                        const ns_frac: u64 = @intCast(@rem(ns_now, 1_000_000));
                        break :blk 1_000_000 - ns_frac;
                    } else 500_000;
                    io_h.sleep(.fromNanoseconds(@intCast(sleep_ns)), .real) catch {};
                    continue; // retry with fresh clock reading
                }
                new_ms = old_ms;
                new_seq = old_seq + 1;
            }

            const new = v7PackState(new_ms, new_seq);
            if (self.v7_atomic_state.cmpxchgStrong(old, new, .acq_rel, .acquire) == null) {
                // CAS win — commit and emit outside the loop.
                committed_ms = new_ms;
                committed_seq = new_seq;
                break;
            }
            // CAS lost — retry with fresh state.
        }

        // Emit the UUID outside the CAS loop.
        var u: UUID = undefined;
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(committed_ms >> 16), .big);
        std.mem.writeInt(u16, u.bytes[4..6], @truncate(committed_ms), .big);
        std.mem.writeInt(u16, u.bytes[6..8], committed_seq, .big);
        self.randCall(u.bytes[8..16]) catch return Error.RandomError;
        u.setVersion(.v7);
        u.setVariant(.rfc9562);
        return u;
    }

    /// Generate a UUIDv7 using the given Unix millisecond timestamp instead
    /// of the system clock.  Useful for deterministic UUID generation and
    /// migrating existing timestamps into UUID form.
    ///
    /// **Errors:**
    /// - `Error.InvalidTimestamp` — `ts` is negative, or the monotonic counter
    ///   is exhausted and the injected clock fails to advance past `ts`.
    /// - `Error.RandomError` — the CSPRNG source failed.
    pub fn newV7AtTime(self: *Generator, ts: i64) Error!UUID {
        if (ts < 0) return Error.InvalidTimestamp; // QC-2: same error as newV7 for same condition
        self.v7.mutex.lockUncancelable(gio());
        return self.newV7Locked(ts);
    }

    /// V7 generation core. Caller must hold `v7.mutex` on entry; this function
    /// always releases the mutex before returning (on success or error path).
    ///
    /// QC-95: the mutex release is now driven by a single `defer unlock()` in
    /// `newV7LockedInner`, which returns the committed `(ms, seq)` pair. This
    /// wrapper then performs the unlocked post-processing (rand_b CSPRNG +
    /// UUID byte assembly) that PERF-02 kept outside the critical section.
    ///
    /// PERF-12: Uses std.Io.sleep(ns_to_next_ms) in the overflow spin-wait.
    ///   PERF-01 previously switched from sleep(100_000 ns) to Thread.yield()
    ///   to reduce per-spin latency.  However Thread.yield() maps to
    ///   sched_yield(2), which returns immediately when no other thread is
    ///   ready, producing a busy-wait that burns 82% of V7 CPU time
    ///   (~3.28M yields per 1M calls).  Sleep(ns_remaining_in_ms) sleeps
    ///   precisely until the next ms boundary: 1 syscall per overflow vs
    ///   ~8,000 yields, and correctly idles the CPU.
    ///
    /// PERF-02: Releases the mutex before the 8-byte rand_b CSPRNG call so
    ///   concurrent threads are not serialised on the getrandom syscall.
    ///   Only the lightweight state update (last_ms, mono_seq) is held.
    ///
    /// SEC-R2-14: The previous two-sequential-if design left seq=0 when another
    ///   thread "stole" the new millisecond during the spin-wait (neither branch
    ///   was entered). Fixed by using a single while-loop that exits when either
    ///   (a) the clock advances, or (b) another thread reset mono_seq, followed
    ///   by a single if/else that always assigns seq.
    fn newV7Locked(self: *Generator, ts: i64) Error!UUID {
        // Run the mutex-protected state update under `defer unlock` so every
        // error path (InvalidTimestamp, RandomError) releases the lock.
        const committed = try self.newV7LockedInner(ts);

        // PERF-02: post-unlock — assemble the UUID and sample rand_b outside
        // the critical section.
        var u: UUID = undefined;
        const ms_u: u64 = @intCast(committed.ms);
        // unix_ts_ms: 48 bits big-endian in bytes 0-5
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(ms_u >> 16), .big);
        std.mem.writeInt(u16, u.bytes[4..6], @truncate(ms_u), .big);
        // rand_a: 12-bit monotonic counter in low 12 bits of bytes 6-7
        std.mem.writeInt(u16, u.bytes[6..8], committed.seq, .big);
        // rand_b: 62 bits random in bytes 8-15 (outside the mutex, PERF-02)
        self.randCall(u.bytes[8..16]) catch return Error.RandomError;
        u.setVersion(.v7);
        u.setVariant(.rfc9562);
        return u;
    }

    /// Inner core of `newV7Locked` (QC-95): runs entirely under `v7.mutex`
    /// with a single `defer unlock()`, returning the committed `(ms, seq)`
    /// pair. Caller must hold `v7.mutex` on entry.
    fn newV7LockedInner(self: *Generator, ts: i64) Error!struct { ms: i64, seq: u12 } {
        defer self.v7.mutex.unlock(gio());

        var ms = ts;

        // If the counter is exhausted in the current ms, wait until either:
        //   (a) the clock advances to a new ms, OR
        //   (b) another thread resets mono_seq (exits the while, ms == last_ms,
        //       counter not maxed — it is safe to increment immediately).
        // PERF-12: sleep precisely to the next ms boundary to avoid the
        // busy-wait that Thread.yield() produces when single-threaded.
        //
        // SEC-R5-03: Maximum spin iterations before giving up.  A frozen or
        // maliciously-injected clock that never advances past last_ms while
        // mono_seq == maxInt(u12) would otherwise cause newV7 to block
        // indefinitely.  4096 iterations ≈ a few milliseconds at normal CPU
        // speeds; exceeding this bound is treated as an invalid/frozen clock.
        const max_spins: usize = 4096;
        var spins: usize = 0;
        while (ms == self.v7.last_ms and self.v7.mono_seq == std.math.maxInt(u12)) {
            spins += 1;
            if (spins > max_spins) {
                return Error.InvalidTimestamp;
            }
            // SEC-R13-01: Cache one clock reading per spin iteration. Both
            // the sleep-duration computation and the ms-advance check use
            // ns_now, preventing divergence from two independent self.clockCall()
            // calls under non-monotonic or injected clocks.
            const ns_now = self.clockCall();

            // SEC-R4-01: derive ms from the cached clock reading; propagate
            // InvalidTimestamp if the value is out of range.
            ms = try clockToMs(ns_now);
            // SEC-R14-02: clamp backward clock to preserve monotonicity
            if (ms < self.v7.last_ms) ms = self.v7.last_ms;

            // If the clock has already advanced past last_ms (or another
            // thread reset mono_seq), skip the sleep — the while condition
            // will exit on the next check.
            if (ms != self.v7.last_ms or self.v7.mono_seq != std.math.maxInt(u12)) break;

            // Compute nanoseconds remaining in the current millisecond.
            // @rem(ns_now, 1_000_000) gives the fraction within [0, 999_999];
            // subtracting from 1_000_000 gives the sleep duration [1, 1_000_000].
            // Fall back to 500µs if the clock returns an invalid/negative value.
            const sleep_ns: u64 = if (ns_now > 0) blk: {
                const ns_frac: u64 = @intCast(@rem(ns_now, 1_000_000));
                break :blk 1_000_000 - ns_frac;
            } else 500_000;
            // Drop the lock across the sleep so other waiters can progress;
            // re-acquire before the next loop iteration (and before the
            // `defer unlock` at function exit).
            const io_h = gio();
            self.v7.mutex.unlock(io_h);
            io_h.sleep(.fromNanoseconds(@intCast(sleep_ns)), .real) catch {};
            self.v7.mutex.lockUncancelable(io_h);
        }

        // Single branch: same-ms increment OR new-ms reset. seq is always assigned.
        // Note: clock regression is handled upstream — newV7() clamps ms to last_ms
        // before calling this function (SEC-R14-02), and the spin-wait loop applies
        // the same clamp after each clock re-read.
        var seq: u12 = undefined;
        if (ms == self.v7.last_ms) {
            // Same ms: increment (the spin-wait above guarantees mono_seq < maxInt).
            self.v7.mono_seq += 1;
            seq = self.v7.mono_seq;
        } else {
            // New ms: seed mono_seq with random jitter (RFC-9562 §6.2).
            var rand_seq: [2]u8 = undefined;
            self.randCall(&rand_seq) catch return Error.RandomError;
            self.v7.mono_seq = @truncate(std.mem.readInt(u16, &rand_seq, .little) & 0x0FFF);
            seq = self.v7.mono_seq;
            self.v7.last_ms = ms;
        }

        return .{ .ms = ms, .seq = seq };
    }

    /// Initialise clock_seq from CSPRNG (F-3).
    ///
    /// Changed from the original to propagate CSPRNG failure rather than
    /// silently using the hardcoded constant 0x1234.  RFC-9562 §6.1 MUST:
    /// "The clock sequence MUST be originally initialized to a random number."
    fn initClockSeq(self: *Generator) Error!void {
        if (self.v1v6.clock_seq_initialized) return;
        var buf: [2]u8 = undefined;
        self.randCall(&buf) catch return Error.RandomError;
        self.v1v6.clock_seq = @truncate(std.mem.readInt(u16, &buf, .little) & 0x3FFF);
        self.v1v6.clock_seq_initialized = true;
    }

    /// Return the node ID for V1/V6 UUIDs, respecting the caching and change-
    /// detection requirements of F-4 and F-6/G-6.
    ///
    /// F-1: When hwaddr_fn is null (the default), a random multicast node ID
    /// is generated and cached. hwaddr_fn is the explicit opt-in.
    /// F-6/G-6: The result is cached in node_cache. Call clearNodeCache() to
    /// force a re-fetch.
    /// Multicast bit as named constant (RFC-9562 §6.10).  Set on random node IDs
    /// to signal that the address is not a real hardware address.
    const multicast_bit: u8 = 0x01;

    /// Generate a random 6-byte node ID with the multicast bit set (RFC-9562 §6.10).
    /// Used by fetchRawNode both for the F-1 default path and hwaddr fallback. (QC-3)
    fn randomMulticastNode(self: *Generator) Error![6]u8 {
        var node: [6]u8 = undefined;
        self.randCall(&node) catch return Error.RandomError;
        node[0] |= multicast_bit;
        return node;
    }

    /// Compute raw node bytes from hwaddr_fn or CSPRNG without touching the cache.
    ///
    /// PERF-05: Safe to call without holding the mutex because it only reads
    /// immutable generator fields (hwaddr_fn, rand) that are set at init time
    /// and never mutated afterwards.  Used by newV1AtTime / newV6AtTime to
    /// perform the expensive OS syscall (getifaddrs / ioctl) BEFORE acquiring
    /// the hot-path mutex, so concurrent UUID generation is not blocked.
    fn fetchRawNode(self: *Generator) Error![6]u8 {
        if (self.hwaddr_fn) |f| {
            if (f()) |mac| {
                return mac;
            } else |_| {
                // hwaddr failed — fall back to random multicast node (QC-3)
                return self.randomMulticastNode();
            }
        }
        // F-1 default: random multicast node ID
        return self.randomMulticastNode();
    }

    fn getNode(self: *Generator) Error![6]u8 {
        // Caller holds v1v6.mutex (per resolveV1V6State); loadNodeCacheBytes
        // is consistent with storeNodeCache under the same lock.
        if (self.hasNodeCache()) return self.loadNodeCacheBytes();
        const node = try self.fetchRawNode();
        self.storeNodeCache(node);
        return node;
    }

    /// Shared state-resolution helper for V1 and V6 generation (QC-1).
    ///
    /// Acquires and releases v1v6.mutex, initialises clock_seq, updates
    /// last_v1_ts, populates the node cache, and handles F-4 node-change
    /// detection.  Returns the resolved (timestamp, node, clock_seq) so that
    /// each public function only needs to perform its version-specific
    /// timestamp byte encoding.
    ///
    /// **caller must NOT hold v1v6.mutex on entry.**
    fn resolveV1V6State(
        self: *Generator,
        ts: Timestamp,
        prefetched: ?[6]u8,
    ) Error!struct { t: u60, node: [6]u8, clock_seq: u14 } {
        self.v1v6.mutex.lockUncancelable(gio());
        defer self.v1v6.mutex.unlock(gio());
        try self.initClockSeq(); // F-3: propagate CSPRNG failure
        // Increment clock_seq on clock regression OR same-timestamp call (RFC-9562 §6.1).
        // Using <= (not <) ensures concurrent/repeated calls at identical timestamps
        // each get a unique clock_seq, preventing duplicate UUID production.
        // This fixes the same-timestamp uniqueness bug (gofrs/uuid #216).
        if (ts.value <= self.v1v6.last_v1_ts) {
            self.v1v6.clock_seq = (self.v1v6.clock_seq +% 1) & 0x3FFF;
        }
        self.v1v6.last_v1_ts = ts.value;
        // Populate cache under lock if it was empty (double-check for concurrent warmup).
        // PERF-27: hasNodeCache reads the atomic flag under the lock (.acquire
        // is strictly stronger than needed here but cheap on x86/arm64).
        if (!self.hasNodeCache()) {
            self.storeNodeCache(prefetched orelse try self.fetchRawNode());
        }
        // F-4: detect node ID change and increment clock_seq
        const old_node = self.last_node;
        const node = try self.getNode(); // guaranteed cache hit after the block above
        if (old_node) |on| {
            if (!std.mem.eql(u8, &on, &node)) {
                self.v1v6.clock_seq = (self.v1v6.clock_seq +% 1) & 0x3FFF;
            }
        }
        self.last_node = node;
        return .{ .t = ts.value, .node = node, .clock_seq = self.v1v6.clock_seq };
    }

    /// QC-113a / QC-115: shared preamble output for V1 and V6 generation.
    /// Holds the three values both byte-layouts consume — the 60-bit
    /// Gregorian timestamp, the resolved node ID, and the clock_seq —
    /// so the two callers can focus solely on their version-specific
    /// `writeInt` sequences.  This is an internal value type; not pub.
    const V1V6Core = struct {
        t: u60,
        node: [6]u8,
        clock_seq: u14,
    };

    /// QC-113a / QC-115: extract the node-prefetch + resolveV1V6State
    /// scaffolding that was duplicated between `newV1AtTime` and
    /// `newV6AtTime`.  Preserves the PERF-05 / PERF-27 invariants:
    /// the node prefetch runs OUTSIDE the v1v6 mutex, and the
    /// atomic-acquire `hasNodeCache()` probe gates the cold-path
    /// syscalls.  Behaviour-preserving: identical fetchRawNode /
    /// resolveV1V6State call sequence as before the dedup.
    fn buildV1V6Core(self: *Generator, ts: Timestamp) Error!V1V6Core {
        // PERF-05: Pre-fetch node outside the mutex on the cold path to avoid
        // blocking all threads during OS syscalls (socket + ioctl on Linux,
        // getifaddrs on macOS).  fetchRawNode reads only immutable generator
        // fields so it is safe without the lock.
        // PERF-27: fast-path probe is now an acquire-load of the atomic valid
        // flag, making the unsynchronised read data-race-free (TSan-clean).
        const prefetched: ?[6]u8 = if (!self.hasNodeCache())
            try self.fetchRawNode()
        else
            null;

        const s = try self.resolveV1V6State(ts, prefetched);
        return .{ .t = s.t, .node = s.node, .clock_seq = s.clock_seq };
    }

    /// Generate a UUIDv1 (Gregorian timestamp + node ID).
    ///
    /// Uses `Timestamp.now()` (system clock) — NOT affected by `withClock()`.
    /// Returns `Error.InvalidTimestamp` if the system clock is before the Unix
    /// epoch or far in the future, or `Error.RandomError` if the CSPRNG fails.
    pub fn newV1(self: *Generator) Error!UUID {
        const ts = try Timestamp.now();
        return self.newV1AtTime(ts);
    }

    /// Generate a UUIDv1 using the given Gregorian timestamp.
    ///
    /// **Errors:** `Error.RandomError` (CSPRNG failure for clock_seq init or
    /// random node ID), `Error.NoHWAddressFound` (hwaddr_fn set but failed).
    pub fn newV1AtTime(self: *Generator, ts: Timestamp) Error!UUID {
        const s = try self.buildV1V6Core(ts);
        var u: UUID = undefined;
        const t = s.t;
        // time_low: bits 0-31
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(t), .big);
        // time_mid: bits 32-47
        std.mem.writeInt(u16, u.bytes[4..6], @truncate(t >> 32), .big);
        // time_high: bits 48-59 (version nibble set below)
        std.mem.writeInt(u16, u.bytes[6..8], @truncate(t >> 48), .big);
        // clock_seq: 14 bits in bytes 8-9 (variant set below)
        std.mem.writeInt(u16, u.bytes[8..10], s.clock_seq, .big);
        @memcpy(u.bytes[10..16], &s.node);
        u.setVersion(.v1);
        u.setVariant(.rfc9562);
        return u;
    }

    /// Generate a UUIDv6 (reordered Gregorian timestamp + node ID).
    ///
    /// Uses `Timestamp.now()` (system clock) — NOT affected by `withClock()`.
    /// Same error surface as `newV1`.
    pub fn newV6(self: *Generator) Error!UUID {
        const ts = try Timestamp.now();
        return self.newV6AtTime(ts);
    }

    /// Generate a UUIDv6 using the given Gregorian timestamp.
    ///
    /// Same error surface as `newV1AtTime`.
    pub fn newV6AtTime(self: *Generator, ts: Timestamp) Error!UUID {
        const s = try self.buildV1V6Core(ts);
        var u: UUID = undefined;
        const t = s.t;
        // V6: reorder timestamp for lexicographic sort
        // bytes 0-3: bits 28-59 (high 32 bits)
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(t >> 28), .big);
        // bytes 4-5: bits 12-27
        std.mem.writeInt(u16, u.bytes[4..6], @truncate((t >> 12) & 0xFFFF), .big);
        // bytes 6-7: bits 0-11 (version nibble set below)
        std.mem.writeInt(u16, u.bytes[6..8], @truncate(t & 0x0FFF), .big);
        // bytes 8-9: clock_seq (variant set below)
        std.mem.writeInt(u16, u.bytes[8..10], s.clock_seq, .big);
        @memcpy(u.bytes[10..16], &s.node);
        u.setVersion(.v6);
        u.setVariant(.rfc9562);
        return u;
    }

    /// Generate a Version 3 (MD5 name-based) UUID (RFC-9562 §5.3).
    ///
    /// **SECURITY WARNING (SEC-8 / CWE-327):** MD5 is a cryptographically
    /// broken hash algorithm.  V3 UUIDs are deterministic — the same
    /// namespace+name pair always produces the same UUID — and MD5 collisions
    /// are computationally trivial to engineer.
    ///
    /// **Do NOT** use V3 UUIDs where collision resistance is required (e.g., as
    /// content-addressable identifiers, surrogate auth tokens, or de-duplication
    /// keys over attacker-controlled input).  Use V5 (SHA-1) for slightly
    /// stronger hashing, or V8 with a modern hash (SHA-256/BLAKE3) for
    /// collision-resistant name-based UUIDs.
    ///
    /// V3 exists for backward compatibility with systems that already use it.
    /// Prefer V5 for new deployments.  See RFC-9562 §6.4.
    ///
    /// **SEC-P3-05 (CWE-327 / CWE-347) — namespace forgery:** `ns` accepts
    /// any `UUID` per RFC-9562. If the namespace value is attacker-
    /// controlled, the attacker can engineer `(ns, name)` pairs that
    /// collide with a target UUID under MD5 — a forgery path that does
    /// not require a full MD5 preimage. Treat `ns` as a trusted constant
    /// (RFC namespace, config value, or compile-time literal) — NEVER
    /// pass a UUID read from untrusted input. Call `newV3Strict` to let
    /// the type system enforce this by accepting only the closed
    /// `namespace.Namespace` enum.
    ///
    /// **SEC-P4-12 (CWE-400) — unbounded hash input:** `name` is hashed
    /// in full with no internal length cap. Forwarding an
    /// attacker-controlled blob causes MD5 to consume CPU proportional
    /// to `name.len`, which a caller may not intend. Callers with
    /// attacker-influenced inputs MUST either validate `name.len` up-
    /// front or use `newV3Bounded`, which returns `Error.NameTooLong`
    /// above the caller's cap.
    pub fn newV3(_: *Generator, ns: UUID, name: []const u8) UUID {
        var md5 = std.crypto.hash.Md5.init(.{});
        md5.update(&ns.bytes);
        md5.update(name);
        var digest: [16]u8 = undefined;
        md5.final(&digest);
        var u = UUID{ .bytes = digest };
        u.setVersion(.v3);
        u.setVariant(.rfc9562);
        return u;
    }

    /// Generate a Version 5 (SHA-1 name-based) UUID (RFC-9562 §5.3).
    ///
    /// **SECURITY WARNING (SEC-8 / CWE-327):** SHA-1 is cryptographically
    /// weakened — chosen-prefix collisions have been demonstrated (SHAttered,
    /// 2017).  V5 UUIDs are deterministic: same namespace+name always yields the
    /// same UUID.
    ///
    /// **Do NOT** use V5 UUIDs where strong collision resistance is required.
    /// For new systems that need name-based UUIDs without the SHA-1 limitation,
    /// consider V8 with SHA-256 or another modern hash.
    ///
    /// V5 is substantially safer than V3 (MD5) and is the recommended
    /// name-based UUID version for interoperability.  See RFC-9562 §6.5.
    ///
    /// **SEC-P3-05 (CWE-327 / CWE-347) — namespace forgery:** `ns` accepts
    /// any `UUID` per RFC-9562. Treat it as a trusted constant — SHA-1 is
    /// weakened and an attacker-controlled namespace enables the same
    /// forgery path described for `newV3`. Prefer `newV5Strict` for new
    /// code, which restricts the namespace to a closed enum of vetted
    /// values.
    ///
    /// **SEC-P4-12 (CWE-400) — unbounded hash input:** `name` is hashed
    /// in full with no internal length cap. Forwarding an
    /// attacker-controlled blob causes SHA-1 to consume CPU proportional
    /// to `name.len`. Use `newV5Bounded` (returns `Error.NameTooLong`
    /// above the caller's cap) or validate `name.len` before calling.
    pub fn newV5(_: *Generator, ns: UUID, name: []const u8) UUID {
        var sha1 = std.crypto.hash.Sha1.init(.{});
        sha1.update(&ns.bytes);
        sha1.update(name);
        var digest: [20]u8 = undefined;
        sha1.final(&digest);
        var u = UUID{ .bytes = digest[0..16].* };
        u.setVersion(.v5);
        u.setVariant(.rfc9562);
        return u;
    }

    /// SEC-P3-05: strict V3 wrapper that accepts only the closed
    /// `namespace.Namespace` tagged-union over the four RFC-9562 namespaces
    /// (plus a vetted `.custom` variant).  Identical semantics to `newV3`
    /// for the same namespace bytes; the only difference is that the type
    /// system prevents callers from accidentally passing a UUID parsed from
    /// untrusted input as the namespace.
    pub fn newV3Strict(self: *Generator, ns: @import("namespace.zig").Namespace, name: []const u8) UUID {
        return self.newV3(ns.asUUID(), name);
    }

    /// SEC-P3-05: strict V5 wrapper — see `newV3Strict`.
    pub fn newV5Strict(self: *Generator, ns: @import("namespace.zig").Namespace, name: []const u8) UUID {
        return self.newV5(ns.asUUID(), name);
    }

    /// SEC-P4-12 (CWE-400): bounded V3 wrapper that rejects `name`
    /// inputs longer than `max_len` with `Error.NameTooLong` *before*
    /// hashing.  Semantics for accepted inputs are identical to
    /// `newV3` — the only difference is a caller-supplied length gate
    /// that prevents an attacker-controlled multi-GB `name` from
    /// forcing MD5 to consume CPU proportional to `name.len`
    /// (CPU-amplification / hash-DoS).
    ///
    /// Pick `max_len` to match the longest legitimate name for the
    /// namespace at the call site (e.g. 253 for DNS labels, 2048 for
    /// URLs, etc.).  Passing `std.math.maxInt(usize)` disables the
    /// check and is equivalent to calling `newV3` directly.
    pub fn newV3Bounded(self: *Generator, ns: UUID, name: []const u8, max_len: usize) Error!UUID {
        if (name.len > max_len) return Error.NameTooLong;
        return self.newV3(ns, name);
    }

    /// SEC-P4-12 (CWE-400): bounded V5 wrapper — see `newV3Bounded`.
    /// Rejects `name` longer than `max_len` with `Error.NameTooLong`
    /// before invoking SHA-1.  Identical output to `newV5` for
    /// accepted inputs.
    pub fn newV5Bounded(self: *Generator, ns: UUID, name: []const u8, max_len: usize) Error!UUID {
        if (name.len > max_len) return Error.NameTooLong;
        return self.newV5(ns, name);
    }

    // =========================================================================
    // PERF-30: prehashed V3 / V5 namespace variants.
    //
    // `newV3` / `newV5` re-hash the 16-byte namespace on every call. Callers
    // that issue many UUIDs under one namespace (e.g. per-row content IDs for
    // a single namespace DNS) can amortize that by snapshotting the hasher's
    // partial state after `update(ns.bytes)` once, then cloning the snapshot
    // per-name and finalising with just `update(name); final(&digest);`.
    //
    // Zig 0.16's Md5 and Sha1 are plain structs containing fixed-size fields
    // (`s: [N]u32`, `buf: [64]u8`, `buf_len: u8`, `total_len: u64`), so a
    // value-copy clone of the struct is well-defined and independent of the
    // source. We rely on that semantics via `var cloned = self.hasher;`.
    // =========================================================================

    /// Prehashed V3 (MD5) namespace — see `initV3Namespace`.
    pub const PrehashedV3 = struct {
        hasher: std.crypto.hash.Md5,

        /// Compute a V3 UUID for `name` under the prehashed namespace. The
        /// source hasher state is preserved (value-copied) so the same
        /// `PrehashedV3` may be reused for many names.
        pub fn name(self: *const PrehashedV3, name_bytes: []const u8) UUID {
            var cloned = self.hasher;
            cloned.update(name_bytes);
            var digest: [16]u8 = undefined;
            cloned.final(&digest);
            var u = UUID{ .bytes = digest };
            u.setVersion(.v3);
            u.setVariant(.rfc9562);
            return u;
        }
    };

    /// Prehashed V5 (SHA-1) namespace — see `initV5Namespace`.
    pub const PrehashedV5 = struct {
        hasher: std.crypto.hash.Sha1,

        /// Compute a V5 UUID for `name` under the prehashed namespace. The
        /// source hasher state is preserved (value-copied) so the same
        /// `PrehashedV5` may be reused for many names.
        pub fn name(self: *const PrehashedV5, name_bytes: []const u8) UUID {
            var cloned = self.hasher;
            cloned.update(name_bytes);
            var digest: [20]u8 = undefined;
            cloned.final(&digest);
            var u = UUID{ .bytes = digest[0..16].* };
            u.setVersion(.v5);
            u.setVariant(.rfc9562);
            return u;
        }
    };

    /// PERF-30: build a prehashed V3 namespace. The returned object can be
    /// reused across many `name()` calls; each call is equivalent to a full
    /// `newV3(ns, name)` but skips the 16-byte namespace re-hash.
    ///
    /// **Security:** inherits the same MD5 / collision warnings as `newV3`.
    pub fn initV3Namespace(_: *Generator, ns: UUID) PrehashedV3 {
        var h = std.crypto.hash.Md5.init(.{});
        h.update(&ns.bytes);
        return .{ .hasher = h };
    }

    /// PERF-30: build a prehashed V5 namespace. The returned object can be
    /// reused across many `name()` calls; each call is equivalent to a full
    /// `newV5(ns, name)` but skips the 16-byte namespace re-hash.
    ///
    /// **Security:** inherits the same SHA-1 / collision warnings as `newV5`.
    pub fn initV5Namespace(_: *Generator, ns: UUID) PrehashedV5 {
        var h = std.crypto.hash.Sha1.init(.{});
        h.update(&ns.bytes);
        return .{ .hasher = h };
    }

    /// Generate a UUIDv8 (custom/experimental) from caller-provided fields.
    ///
    /// This function is infallible — the body contains no fallible operations.
    /// The return type is `UUID` (not `Error!UUID`) because the caller provides
    /// all data directly; no clock, random, or I/O call is needed.
    pub fn newV8(_: *Generator, a: [6]u8, b: [2]u8, c: [8]u8) UUID {
        var u: UUID = undefined;
        // custom_a: bits 0-47 → bytes 0-5
        @memcpy(u.bytes[0..6], &a);
        // custom_b: lower 12 bits used → bytes 6-7 (version nibble will overlay high 4 bits)
        @memcpy(u.bytes[6..8], &b);
        // custom_c: lower 62 bits used → bytes 8-15 (variant bits will overlay high 2 bits)
        @memcpy(u.bytes[8..16], &c);
        u.setVersion(.v8);
        u.setVariant(.rfc9562);
        return u;
    }

    // -------------------------------------------------------------------------
    // Persistent state (F-9, RFC §6.3 SHOULD)
    // -------------------------------------------------------------------------

    /// Binary state file format.
    ///
    /// **Version 1 (22 bytes, legacy — read-only support):**
    /// [0..4]   magic "UUID"
    /// [4]      format version = 1
    /// [5]      flags: bit0=clock_seq_initialized, bit1=has_node_cache
    /// [6..8]   clock_seq as u16 LE
    /// [8..16]  last_v1_ts as u64 LE
    /// [16..22] node_cache [6]u8
    ///
    /// **Version 2 (32 bytes, backward-compatible default when no
    /// `state_mac_key` is configured):**
    /// [0..4]   magic "UUID"
    /// [4]      format version = 2
    /// [5]      flags: bit0=clock_seq_initialized, bit1=has_node_cache
    /// [6..8]   clock_seq as u16 LE
    /// [8..16]  last_v1_ts as u64 LE
    /// [16..22] node_cache [6]u8
    /// [22..30] last_ms as i64 LE  (SEC-10: V7 last-used timestamp)
    /// [30..32] mono_seq as u16 LE (SEC-10: V7 counter; see loadState for clock-based handling)
    ///
    /// **Version 3 (64 bytes, HMAC-authenticated — SEC-P3-04):**
    /// [0..32]  identical to version 2 payload, except byte [4] = 3
    /// [32..64] HMAC-SHA256(bytes [0..32], state_mac_key)
    ///
    /// Version 3 is written when `state_mac_key` is non-null; otherwise
    /// saveState emits version 2.  loadState accepts all three versions:
    /// v1/v2 load unchanged (a warning is emitted if `state_mac_key` is
    /// set — the file is unauthenticated), v3 requires `state_mac_key` to
    /// be set and the HMAC to verify with `std.crypto.timing_safe.eql`.
    pub const state_magic: [4]u8 = "UUID".*;
    /// Legacy V1/V6-only state format (22 bytes, unauthenticated).
    /// Accepted by `loadState` for backward compatibility; never written.
    pub const state_format_version_v1: u8 = 1;
    /// V1/V6 + V7 state format (32 bytes, unauthenticated). Current default
    /// when `state_mac_key` is null. Written by `saveState` and accepted by
    /// `loadState`.
    pub const state_format_version_v2: u8 = 2;
    /// V2 payload + 32-byte HMAC-SHA256 trailer (64 bytes, authenticated).
    /// Written by `saveState` iff `state_mac_key != null`; `loadState`
    /// verifies the MAC with `std.crypto.timing_safe.eql` (SEC-P3-04).
    pub const state_format_version_v3: u8 = 3; // SEC-P3-04
    /// Default write version when no `state_mac_key` is configured.
    /// Retained under the historical name for ABI/source compatibility.
    pub const state_format_version: u8 = state_format_version_v2;
    /// Wire size (in bytes) of a v1 state file payload: magic(4) + version(1)
    /// + V1/V6 state(17).
    pub const state_size_v1: usize = 22;
    /// Wire size (in bytes) of a v2 state file payload: v1 payload + V7
    /// state(10). Also the base payload size for v3 (HMAC trailer excluded).
    pub const state_size: usize = 32;
    /// SEC-P3-04: v3 adds a 32-byte HMAC-SHA256 trailer to the v2 payload.
    pub const state_mac_size: usize = 32;
    /// Wire size (in bytes) of a v3 state file: v2 payload + HMAC trailer.
    pub const state_size_v3: usize = state_size + state_mac_size;

    /// SEC-P4-03: default clock-rollback tolerance applied when
    /// `InitOptions.clock_rollback_tolerance_ms` is null.  Tightened
    /// from the pre-SEC-P4-03 1_000 ms to 250 ms, matching NTP's
    /// chrony `maxslewrate` practical upper bound.  Callers that need
    /// a wider window (e.g. deployments with flaky NTP or VM-suspend
    /// jumps) pass an explicit value via InitOptions; the value is
    /// clamped to [0, 60_000].
    pub const default_clock_rollback_tolerance_ms: i64 = 250;

    /// Save generator state to stable storage (F-9, SEC-1, SEC-9, SEC-10).
    ///
    /// **`path` must be an absolute filesystem path** (e.g. `/var/lib/myapp/uuid.state`).
    /// Relative paths are rejected by the underlying `std.fs.*Absolute` calls
    /// with `error.InvalidArgument` on POSIX or `error.BadPathName` on Windows.
    ///
    /// Persists V1/V6 state (clock_seq, last_v1_ts, node_cache) AND V7 state
    /// (last_ms, mono_seq) so that all UUID versions remain monotone and
    /// collision-free across process restarts.
    ///
    /// **SEC-1:** File is created with mode 0o600 (owner read/write only).
    /// **SEC-9:** Uses an atomic write-then-rename to prevent torn-write state.
    /// **SEC-10:** Persists V7 state; see loadState for clock-based restart handling.
    /// **PERF:** State is serialised under the mutex into a stack buffer, then the
    ///           mutex is released before any file I/O.  UUID generation is not
    ///           blocked by slow storage (NFS, spinning disk, etc.).
    pub fn saveState(self: *Generator, path: []const u8) Error!void {
        // QC-99: delegate to saveStateImpl which returns the wide underlying
        // inferred error set; collapse everything except Error-typed failures
        // into Error.StateIoFailure at the single boundary below.
        self.saveStateImpl(path) catch |e| return mapStateError(e);
    }

    /// QC-113b: pack the v1v6/v7 snapshot into the caller-supplied buffer.
    /// Runs under BOTH state mutexes (v7 first, v1v6 second — PERF-19 fixed
    /// acquisition order).  The caller owns the buffer lifetime.
    ///
    /// Writes the 32-byte v2 payload region (buf[0..state_size]); the v3
    /// HMAC trailer is appended by saveStateImpl outside this helper (and
    /// outside the mutexes, so the HMAC compute does not serialise
    /// generators on the HMAC code path).
    ///
    /// Returns `true` if `state_mac_key` is configured so saveStateImpl
    /// knows to emit wire-format v3 (payload + 32-byte HMAC trailer).
    fn packStateIntoBuffer(self: *Generator, buf: *[state_size_v3]u8) bool {
        // Snapshot state under both mutexes; release before I/O.
        // PERF-19: acquire in fixed order (v7 first, then v1v6) to prevent deadlock.
        // SEC-P3-04: buffer is sized for v3 (payload + HMAC trailer) by the
        // caller.  When `state_mac_key` is null the trailer bytes are never
        // written, so the file length stays at `state_size`.
        const is_v3 = self.state_mac_key != null;
        const write_version: u8 = if (is_v3)
            state_format_version_v3
        else
            state_format_version_v2;

        self.v7.mutex.lockUncancelable(gio());
        defer self.v7.mutex.unlock(gio());
        self.v1v6.mutex.lockUncancelable(gio());
        defer self.v1v6.mutex.unlock(gio());

        @memcpy(buf[0..4], &state_magic);
        buf[4] = write_version; // 2 or 3

        var flags: u8 = 0;
        if (self.v1v6.clock_seq_initialized) flags |= 0x01;
        const has_node = self.hasNodeCache();
        if (has_node) flags |= 0x02;
        buf[5] = flags;

        std.mem.writeInt(u16, buf[6..8], @as(u16, self.v1v6.clock_seq), .little);
        std.mem.writeInt(u64, buf[8..16], @as(u64, self.v1v6.last_v1_ts), .little);
        if (has_node) {
            const bytes = self.loadNodeCacheBytes();
            @memcpy(buf[16..22], &bytes);
        } else {
            @memset(buf[16..22], 0);
        }
        // SEC-10: persist V7 state.
        std.mem.writeInt(i64, buf[22..30], self.v7.last_ms, .little);
        std.mem.writeInt(u16, buf[30..32], @as(u16, self.v7.mono_seq), .little);
        return is_v3;
    }

    /// QC-113b: perform the atomic write-then-rename dance, owning all
    /// filesystem-level security and durability invariants.  No generator
    /// state is touched; the function is pure I/O over the caller-supplied
    /// bytes.  Invariants preserved from pre-refactor saveStateImpl:
    ///
    ///   - SEC-9: write to `<path>.tmp`, fsync, then rename atomically.
    ///   - SEC-1 / SEC-P3-03 (CWE-276 / CWE-732): mode 0o600 on POSIX via
    ///     `Permissions.fromMode` on create AND an explicit post-create
    ///     fchmod (umask-proof).  Windows has no POSIX mode concept, so
    ///     the fchmod branch is skipped.
    ///   - SEC-R3-01 (CWE-61): stale-file delete before create +
    ///     `exclusive = true` (O_EXCL) to refuse symlink follow and
    ///     refuse to overwrite a file that races into the tmp path.
    ///   - PERF-35: fsync the file data before close, then fsync the
    ///     parent directory so the rename itself is durable across crash.
    ///   - SEC-R2-15: named `tmp_suffix` / explicit PATH_MAX rather than
    ///     magic `4100`.
    fn atomicWriteStateFile(path: []const u8, bytes: []const u8) !void {
        // SEC-R2-15: Use a named constant instead of the magic number 4100.
        // 4096 = OS maximum path length (POSIX PATH_MAX); + 4 for ".tmp" suffix.
        const tmp_suffix = ".tmp";
        var tmp_path_buf: [4096 + tmp_suffix.len]u8 = undefined;
        const tmp_path = try std.fmt.bufPrint(&tmp_path_buf, "{s}{s}", .{ path, tmp_suffix });
        // Remove any stale .tmp (e.g., from a previous crashed run) or a pre-placed
        // symlink.  Errors (FileNotFound etc.) are intentionally ignored.
        const io = gio();
        std.Io.Dir.deleteFileAbsolute(io, tmp_path) catch {};
        {
            // SEC-P3-03 (CWE-276 / CWE-732): Request 0o600 via the Permissions
            // field so the initial open(2) mode is owner-only. POSIX applies
            // the process umask to this value (mode & ~umask), so on hosts
            // with a permissive umask the file could still be created
            // world-readable. The explicit fchmod after create (below, POSIX
            // only) guarantees the final mode is exactly 0o600 regardless of
            // umask, so the state file never exposes node_id / last_v1_ts to
            // other local users.
            //
            // exclusive:true → O_EXCL on POSIX: fails if any file or symlink
            // now exists at tmp_path, preventing symlink-following on create.
            //
            // The `permissions` field is POSIX-only: std.Io.File.Permissions
            // on Windows is a DWORD-backed enum without `fromMode`, so we
            // only request 0o600 when targeting POSIX.  On Windows the state
            // file inherits the default ACL of its parent directory (the
            // intended user profile / appdata location); there is no POSIX
            // mode concept to enforce.
            const create_opts: std.Io.Dir.CreateFileOptions = if (comptime builtin.os.tag == .windows)
                .{ .exclusive = true }
            else
                .{
                    .exclusive = true,
                    .permissions = std.Io.File.Permissions.fromMode(0o600),
                };
            const f = try std.Io.Dir.createFileAbsolute(io, tmp_path, create_opts);
            errdefer std.Io.Dir.deleteFileAbsolute(io, tmp_path) catch {};
            defer f.close(io);
            // SEC-P3-03: umask-proof fchmod to exactly 0o600 on POSIX. Windows
            // has no POSIX mode concept; the Permissions enum is a no-op
            // there and this branch is skipped.
            if (comptime builtin.os.tag != .windows) {
                const rc = std.os.linux.fchmod(f.handle, 0o600);
                const errno_val = std.os.linux.errno(rc);
                if (errno_val != .SUCCESS) return Error.StateIoFailure;
            }
            try f.writePositionalAll(io, bytes, 0);
            // PERF-35: flush file data to stable storage BEFORE the
            // defer-close runs.  rename(2) only atomically swaps the
            // directory entry — the file's data blocks may still be
            // buffered in the OS page cache.  A power loss between
            // rename and writeback leaves a zero/torn state file.
            try f.sync(io);
        }
        try std.Io.Dir.renameAbsolute(tmp_path, path, io);

        // PERF-35: fsync the parent directory so the rename itself is
        // durable.  Without this, a crash after rename can leave the
        // directory pointing at the tmp_path (or worse, neither) because
        // most filesystems do not implicitly fsync directory mtime
        // updates.
        //
        // TODO(zig-0.17+): replace this whole wrapper with
        // `std.Io.Dir.sync(io)` once upstream Zig exposes it.  Tracked
        // so `grep TODO` surfaces this when the workaround can go.
        //
        // std.Io.Dir does not expose a sync() method in Zig 0.16, and
        // std.posix.fsync() is not exposed either.  The Dir/File handle
        // types are both std.posix.fd_t, so we reuse std.Io.File.sync()
        // by wrapping the directory fd in a File value — the kernel-
        // level fsync(2) does not care whether the fd is a file or a
        // directory.
        //
        // IMPORTANT: we must open the dir with .iterate = true.  On Linux,
        // std.Io.Dir.openDir uses O_PATH when iterate is false, and O_PATH
        // fds cannot be used with fsync(2) — the kernel returns EBADF.
        // iterate=true opens a real readable dir fd that fsync accepts.
        //
        // Windows has no POSIX dir-fsync concept (FlushFileBuffers on the
        // dir handle is the rough equivalent but out of scope); guard so
        // non-POSIX targets still build.
        if (comptime builtin.os.tag != .windows) {
            const dir_path = std.fs.path.dirname(path) orelse "/";
            var dir = try std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true });
            defer dir.close(io);
            const dir_as_file: std.Io.File = .{
                .handle = dir.handle,
                .flags = .{ .nonblocking = false },
            };
            try dir_as_file.sync(io);
        }
    }

    /// QC-113b: orchestrator for `saveState`.  Splits into three phases:
    ///   1. `packStateIntoBuffer` — snapshot under both mutexes.
    ///   2. Append HMAC-SHA256 trailer outside mutexes if a key is set.
    ///   3. `atomicWriteStateFile` — pure I/O (open / write / fsync /
    ///      rename / dirsync), no generator state.
    fn saveStateImpl(self: *Generator, path: []const u8) !void {
        // SEC-P3-04: use a single buffer sized for v3 (payload + HMAC trailer).
        // When `state_mac_key` is null the trailer bytes are never written, so
        // the file length stays at `state_size`. When non-null we append the
        // HMAC and write `state_size_v3` bytes.
        var buf: [state_size_v3]u8 = undefined;
        const is_v3 = self.packStateIntoBuffer(&buf);

        // SEC-P3-04: compute and append HMAC-SHA256 over the payload if a
        // key is configured. HMAC runs outside the mutex — `buf[0..32]` is
        // already a snapshot, and the key is an immutable field set at
        // construction.
        // SEC-P4-02: capture the key as a pointer (`|*key_ptr|`) into
        // `self.state_mac_key`'s Optional payload, NOT by value.  A
        // value capture (`|key|`) creates a 32-byte stack copy that
        // Zig will not `secureZero` on function return — classic
        // cleartext-in-memory residue (CWE-316).  The pointer capture
        // dispatches HMAC directly through the Generator's own storage;
        // `secureWipeMacKey` (the authoritative wipe path) already
        // volatile-zeros that storage.  `HmacSha256.create` takes the
        // key as `*const [32]u8`, so the pointer capture is a drop-in
        // signature match.
        const write_len: usize = if (is_v3) blk: {
            const key_ptr: *const [32]u8 = if (self.state_mac_key) |*k| k else unreachable;
            var mac: [state_mac_size]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, buf[0..state_size], key_ptr);
            @memcpy(buf[state_size..state_size_v3], &mac);
            break :blk state_size_v3;
        } else state_size;

        // SEC-9 / SEC-1 / SEC-R3-01 / SEC-P3-03 / PERF-35: delegated to
        // the pure-I/O helper.  See atomicWriteStateFile for the full
        // invariant list.
        try atomicWriteStateFile(path, buf[0..write_len]);
    }

    /// Load generator state from stable storage (F-9, SEC-10, PERF-04).
    ///
    /// **`path` must be an absolute filesystem path** (e.g. `/var/lib/myapp/uuid.state`).
    /// Relative paths are rejected by `std.fs.openFileAbsolute` with
    /// `error.InvalidArgument` on POSIX or `error.BadPathName` on Windows.
    ///
    /// Accepts both state format version 1 (22 bytes, V1/V6 state only) and
    /// version 2 (32 bytes, V1/V6 + V7 state).  Returns error.InvalidFormat
    /// for corrupted or version-mismatched files.
    ///
    /// When loading V7 state (version 2), the current clock is compared against
    /// the saved last_ms.  On typical restarts (>1ms downtime) the clock has
    /// already advanced, so both last_ms and mono_seq are reset to zero — no
    /// spin-wait on the first post-restart V7 call.  Only when last_ms is still
    /// current (extremely fast restart within the same millisecond) is mono_seq
    /// set to maxInt(u12) to force a spin-wait and prevent collisions.
    pub fn loadState(self: *Generator, path: []const u8) Error!void {
        // QC-99: delegate and collapse wide underlying errors at the boundary.
        self.loadStateImpl(path) catch |e| return mapStateError(e);
    }

    /// SEC-P4-01: one-shot migration of a v1/v2 state file to v3
    /// (HMAC-authenticated) under the generator's current
    /// `state_mac_key`.  Usage:
    ///
    /// ```zig
    /// var gen = uuid.Generator.initOptions(.{ .state_mac_key = key });
    /// try gen.migrateStateToV3("/var/lib/myapp/uuid.state");
    /// // File is now v3; future loadState under the default policy works.
    /// ```
    ///
    /// Semantics:
    ///   1. `state_mac_key` must be configured — returns
    ///      `Error.StateMacMismatch` otherwise (the helper has nothing
    ///      to authenticate with).
    ///   2. Loads the file with a temporary `.any` policy so v1/v2 is
    ///      accepted; the generator's configured policy is restored
    ///      before saveState runs.
    ///   3. Saves under the generator's policy — because the key is
    ///      configured, `saveState` writes wire-format v3 (the
    ///      authenticated trailer is added automatically by
    ///      `saveStateImpl`).
    ///
    /// Idempotent: calling on an already-v3 file is a no-op equivalent
    /// to `loadState` + `saveState` (the v3 verify succeeds, then a
    /// fresh v3 file is written).  Callers can run migrateStateToV3
    /// in a release-rollout script without pre-checking the on-disk
    /// version.
    pub fn migrateStateToV3(self: *Generator, path: []const u8) Error!void {
        if (self.state_mac_key == null) return Error.StateMacMismatch;
        // Override the policy for the load half of the migration.
        // Save keeps the generator's configured policy.
        const saved_policy = self.state_mac_policy;
        self.state_mac_policy = .any;
        defer self.state_mac_policy = saved_policy;
        try self.loadState(path);
        try self.saveState(path);
    }

    fn loadStateImpl(self: *Generator, path: []const u8) !void {
        // SEC-R11-04 / SEC-P4-11 (CWE-61): Reject symlink / reparse-point
        // redirection of the state file on every supported platform.  An
        // attacker who can place a symlink (POSIX) or NTFS junction /
        // symbolic link (Windows) at the state-file path before loadState
        // runs could redirect the read to any file readable by the
        // running process, leaking its contents.
        //
        // POSIX: O_NOFOLLOW causes open(2) to fail with ELOOP if the
        // final path component is a symlink, closing the redirect.
        //
        // Windows: after opening the file via std.Io.Dir.openFileAbsolute,
        // query FILE_BASIC_INFORMATION via NtQueryInformationFile and
        // reject the file if its FileAttributes carry REPARSE_POINT
        // (NTFS junctions, symbolic links, mount points).  Opening via
        // openFileAbsolute does follow reparse points by default, so
        // opening succeeds for the redirected target; the post-open
        // attribute check catches that case via the *source* handle —
        // Windows preserves REPARSE_POINT on the reparse-point inode
        // itself, so a TOCTOU swap between open and query cannot let a
        // reparse point through unnoticed.
        const io = gio();
        const f = if (builtin.os.tag == .windows)
            try std.Io.Dir.openFileAbsolute(io, path, .{})
        else blk: {
            const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .NOFOLLOW = true }, 0);
            break :blk std.Io.File{ .handle = fd, .flags = .{ .nonblocking = false } };
        };
        defer f.close(io);

        if (builtin.os.tag == .windows) {
            // SEC-P4-11 (CWE-61) Windows reparse-point rejection.
            // NtQueryInformationFile + FILE_BASIC_INFORMATION exposes
            // the REPARSE_POINT bit (std.os.windows.FILE.ATTRIBUTE).
            // Reused rather than the higher-level `GetFileInformationByHandle`
            // because the latter is not exposed in Zig 0.16's std; the
            // NT-level syscall is already the canonical primitive used by
            // std.Build.Watch (see lib/std/Build/Watch.zig, ~line 497).
            const w = std.os.windows;
            var iosb: w.IO_STATUS_BLOCK = undefined;
            var basic: w.FILE.BASIC_INFORMATION = undefined;
            switch (w.ntdll.NtQueryInformationFile(
                f.handle,
                &iosb,
                &basic,
                @sizeOf(w.FILE.BASIC_INFORMATION),
                .Basic,
            )) {
                .SUCCESS => {},
                // Any query failure is treated as I/O failure — the
                // outer mapStateError collapses this to StateIoFailure.
                else => return error.Unexpected,
            }
            if (basic.FileAttributes.REPARSE_POINT) return Error.InvalidFormat;
        }

        // SEC-R13-04 (CWE-908): Zero-initialize to prevent uninitialized reads.
        // For v1 state files (22 bytes), bytes 22–63 are never written by readAll.
        // The version-2 guard prevents consumption, but zeroing eliminates the
        // latent risk if that guard is weakened in a future refactor.
        // SEC-P3-04: the buffer is sized to hold v3 (payload + HMAC trailer).
        var buf: [state_size_v3]u8 = std.mem.zeroes([state_size_v3]u8);
        const n = try f.readPositionalAll(io, &buf, 0);

        // Accept v1 (22 bytes), v2 (32 bytes), and v3 (64 bytes).
        if (n != state_size_v1 and n != state_size and n != state_size_v3)
            return Error.InvalidFormat;

        // SEC-R4-03: reject files with trailing bytes.  readAll fills buf up
        // to buf.len even when the file is larger, so n alone cannot detect
        // oversized files.  A one-byte probe read must return 0 (EOF).
        var probe: [1]u8 = undefined;
        const extra = try f.readPositionalAll(io, &probe, n);
        if (extra != 0) return Error.InvalidFormat;
        if (!std.mem.eql(u8, buf[0..4], &state_magic)) return Error.InvalidFormat;
        const file_version = buf[4];
        if (file_version != state_format_version_v1 and
            file_version != state_format_version_v2 and
            file_version != state_format_version_v3)
            return Error.InvalidFormat;

        // SEC-P3-04: enforce version-length matching so a v3 header cannot
        // be paired with a truncated (v2-length) file, and vice versa.
        const expected_len: usize = switch (file_version) {
            state_format_version_v1 => state_size_v1,
            state_format_version_v2 => state_size,
            state_format_version_v3 => state_size_v3,
            else => unreachable,
        };
        if (n != expected_len) return Error.InvalidFormat;

        // SEC-P3-04: verify HMAC for v3 files. `state_mac_key` must be set;
        // mismatch is reported as `StateMacMismatch` (distinct from
        // `InvalidFormat` so callers can distinguish tampering from a
        // corrupt file). Timing-safe equality protects against remote
        // timing oracles.
        if (file_version == state_format_version_v3) {
            // SEC-P4-02: point into the Optional's payload directly;
            // see saveStateImpl for the rationale.
            const key_ptr: *const [32]u8 = if (self.state_mac_key) |*k| k else return Error.StateMacMismatch;
            var expected: [state_mac_size]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&expected, buf[0..state_size], key_ptr);
            const trailer = buf[state_size..state_size_v3];
            if (!std.crypto.timing_safe.eql([state_mac_size]u8, expected, trailer.*)) {
                return Error.StateMacMismatch;
            }
        } else {
            // SEC-P4-01: enforce state_mac_policy against unauthenticated
            // versions.  The authoritative decision tree is:
            //
            //   .any               → always accept; emit a warn when
            //                         a key is set but the file has no
            //                         tag, matching the pre-SEC-P4-01
            //                         behaviour.
            //   .require_mac_when_keyed (default)
            //                      → reject with StateVersionDowngrade
            //                         when a key is set; accept freely
            //                         when no key is set.
            //   .require_mac_always
            //                      → reject with StateVersionDowngrade
            //                         unconditionally.
            //
            // Rejection is tamper-resistant: a local attacker cannot
            // downgrade a v3 file to v2 by stripping the trailer, since
            // loadState now refuses to consume the stripped file under
            // the default policy.
            switch (self.state_mac_policy) {
                .any => {
                    if (self.state_mac_key != null) {
                        std.log.warn(
                            "uuid: loaded unauthenticated state file (version {d}); state_mac_key is set but file has no HMAC trailer",
                            .{file_version},
                        );
                    }
                },
                .require_mac_when_keyed => {
                    if (self.state_mac_key != null) {
                        return Error.StateVersionDowngrade;
                    }
                },
                .require_mac_always => {
                    return Error.StateVersionDowngrade;
                },
            }
        }

        // SEC-R13-08 (CWE-833): Read the clock BEFORE acquiring the mutex.
        // If ClockFn blocks (network-backed NTP, slow hardware clock, test
        // double with artificial delay), all concurrent UUID generation calls
        // that contend on the mutexes would stall for the duration.  Reading
        // clock outside the critical section eliminates this availability risk.
        // QC-29: use the injectable clock (self.clock) instead of the raw
        // syscall so that the fast-restart branch is testable via clock injection.
        // Errors (negative/overflow clock) fall back to 0, which activates the
        // conservative overflow path — the safe default.
        const current_ms: i64 = clockToMs(self.clockCall()) catch 0;

        // PERF-19: acquire in fixed order (v7 first, then v1v6) to prevent deadlock.
        self.v7.mutex.lockUncancelable(gio());
        defer self.v7.mutex.unlock(gio());
        self.v1v6.mutex.lockUncancelable(gio());
        defer self.v1v6.mutex.unlock(gio());

        const flags = buf[5];
        self.v1v6.clock_seq = @truncate(std.mem.readInt(u16, buf[6..8], .little) & 0x3FFF);
        self.v1v6.clock_seq_initialized = (flags & 0x01) != 0;
        // SEC-R6-04: Reject out-of-range last_v1_ts rather than truncating
        // silently.  A u64 value above maxInt(u60) indicates a corrupt or
        // tampered state file; return InvalidFormat instead of truncating to
        // a valid-looking timestamp.
        const raw_ts = std.mem.readInt(u64, buf[8..16], .little);
        if (raw_ts > std.math.maxInt(u60)) return Error.InvalidFormat;
        const saved_v1_ts: u60 = @truncate(raw_ts);

        // SEC-P3-02 (CWE-367 / CWE-1240): reject state files whose persisted
        // V1/V6 timestamp is more than `clock_rollback_tolerance_ms` in the
        // future relative to the current wall clock. A saved timestamp that
        // far ahead of the clock indicates a clock-rollback attack (attacker
        // replayed an old post-NTP-step state file) or a corrupt persisted
        // value, either of which would lead to duplicate V1/V6 UUIDs once
        // the clock catches up.
        //
        // The tolerance absorbs small NTP skew (<1s on well-configured
        // hosts) without rejecting legitimate state files.
        //
        // Timestamp arithmetic: saved_v1_ts is in Gregorian 100-ns ticks
        // (u60). Convert to Unix ms for comparison with current_ms.
        const saved_v1_ms: i64 = (Timestamp{ .value = saved_v1_ts }).toUnixMs();
        if (current_ms != 0 and saved_v1_ms > current_ms and
            (saved_v1_ms - current_ms) > self.clock_rollback_tolerance_ms)
        {
            return Error.InvalidFormat;
        }

        // SEC-P3-02 clamp: max(existing, persisted). If loadState is called
        // after some V1/V6 generation, or twice with different files, never
        // accept a smaller value that would rewind the monotonicity guard.
        if (saved_v1_ts > self.v1v6.last_v1_ts) {
            self.v1v6.last_v1_ts = saved_v1_ts;
        }
        if ((flags & 0x02) != 0) {
            self.storeNodeCache(buf[16..22][0..6].*);
        } else {
            self.clearNodeCacheLocked();
        }

        // PERF-04 + SEC-10: restore V7 state from v2 or v3 files (v1 has no
        // V7 payload).  For v3 the HMAC has already verified above, so the
        // bytes at buf[22..30] and buf[30..32] are authenticated.
        if (file_version == state_format_version_v2 or
            file_version == state_format_version_v3)
        {
            const saved_ms = std.mem.readInt(i64, buf[22..30], .little);
            // SEC-P3-02: apply the same clock-rollback guard to V7 state.
            // A saved last_ms far in the future relative to the current
            // clock means either the clock stepped back (NTP, VM migration)
            // or the state file is stale/tampered; either way accepting it
            // would produce duplicate V7 UUIDs once the clock catches up.
            if (current_ms != 0 and saved_ms > current_ms and
                (saved_ms - current_ms) > self.clock_rollback_tolerance_ms)
            {
                return Error.InvalidFormat;
            }
            if (current_ms > saved_ms) {
                self.v7.last_ms = 0;
                self.v7.mono_seq = 0;
            } else {
                self.v7.last_ms = saved_ms;
                self.v7.mono_seq = std.math.maxInt(u12);
            }
        }
    }
};

/// Package-level default generator used by the module-level convenience
/// functions (newV4, newV7, …) in root.zig.
///
/// **SEC-11 / CWE-362 — Shared mutable state:**
/// This is a single Generator instance shared across all callers that use the
/// convenience functions.  The Generator mutex protects its own internal
/// fields, so concurrent generation is safe.  However, callers that also
/// mutate the generator (clearNodeCache(), loadState(), etc.) on this shared
/// instance may interact unexpectedly with other callers.
///
/// **When to create your own generator:**
/// - You need a different node ID (e.g., per-tenant V1/V6 UUIDs).
/// - You need persistent state isolation (different saveState paths).
/// - You need a different random or clock source (testing).
///
/// Use `Generator.init()` to create an independent, isolated instance.
pub var default_generator: Generator = Generator.init();

// =============================================================================
// GeneratorInterface — vtable-based polymorphism (G-8)
// =============================================================================

/// A vtable-based interface for UUID generators (G-8).
///
/// Allows callers to hold a `GeneratorInterface` value that dispatches to any
/// concrete generator implementation without knowing the concrete type.  Use
/// `GeneratorInterface.fromGenerator(ptr)` to wrap a `*Generator`.
///
/// Example:
/// ```zig
/// var gen = Generator.init();
/// var iface = GeneratorInterface.fromGenerator(&gen);
/// const u = try iface.newV4();
/// ```
///
/// ## PERF-31: performance trade-off (P3)
///
/// Every `GeneratorInterface` method is a pointer dispatch through the
/// vtable: a load of `self.vtable.<method>`, an indirect call, and a cast
/// from `*anyopaque` back to `*Generator`.  At ReleaseFast the indirect
/// call prevents inlining even when the concrete type is known to the
/// compiler, adding roughly one function-call frame of overhead per
/// UUID (on x86_64 ~2–4 ns on L1-hot code — not noise on the `newV4` /
/// `toString` hot paths where the library itself runs in <50 ns).
///
/// **Recommendation for hot paths:** hold the concrete `*Generator`
/// pointer directly, OR use the comptime-generic `GeneratorInterfaceFor(G)`
/// type below, which wraps `*G` and dispatches every method through a
/// direct call that LLVM fully inlines at ReleaseFast.  The vtable
/// `GeneratorInterface` remains for call sites that need runtime
/// polymorphism over implementations (DI tests, metric wrappers, fakes);
/// the comptime-generic variant is the zero-overhead alternative for the
/// common case where the concrete type is known at compile time.
pub const GeneratorInterface = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        newV4: *const fn (*anyopaque) Error!UUID,
        newV7: *const fn (*anyopaque) Error!UUID,
        newV7AtTime: *const fn (*anyopaque, i64) Error!UUID,
        newV1: *const fn (*anyopaque) Error!UUID,
        newV1AtTime: *const fn (*anyopaque, Timestamp) Error!UUID,
        newV3: *const fn (*anyopaque, UUID, []const u8) UUID,
        newV5: *const fn (*anyopaque, UUID, []const u8) UUID,
        newV6: *const fn (*anyopaque) Error!UUID,
        newV6AtTime: *const fn (*anyopaque, Timestamp) Error!UUID,
        newV8: *const fn (*anyopaque, [6]u8, [2]u8, [8]u8) UUID,
    };

    /// Generate a random UUIDv4 via the underlying generator.
    pub fn newV4(self: GeneratorInterface) Error!UUID {
        return self.vtable.newV4(self.ptr);
    }
    /// Generate a UUIDv7 using the system clock.
    pub fn newV7(self: GeneratorInterface) Error!UUID {
        return self.vtable.newV7(self.ptr);
    }
    /// Generate a UUIDv7 using the given Unix millisecond timestamp.
    pub fn newV7AtTime(self: GeneratorInterface, ts: i64) Error!UUID {
        return self.vtable.newV7AtTime(self.ptr, ts);
    }
    /// Generate a UUIDv1 (Gregorian timestamp + node ID).
    pub fn newV1(self: GeneratorInterface) Error!UUID {
        return self.vtable.newV1(self.ptr);
    }
    /// Generate a UUIDv1 using the given Gregorian timestamp.
    pub fn newV1AtTime(self: GeneratorInterface, ts: Timestamp) Error!UUID {
        return self.vtable.newV1AtTime(self.ptr, ts);
    }
    /// Generate a UUIDv3 (MD5 name-based) from namespace and name.
    pub fn newV3(self: GeneratorInterface, ns: UUID, name: []const u8) UUID {
        return self.vtable.newV3(self.ptr, ns, name);
    }
    /// Generate a UUIDv5 (SHA-1 name-based) from namespace and name.
    pub fn newV5(self: GeneratorInterface, ns: UUID, name: []const u8) UUID {
        return self.vtable.newV5(self.ptr, ns, name);
    }
    /// Generate a UUIDv6 (reordered Gregorian timestamp + node ID).
    pub fn newV6(self: GeneratorInterface) Error!UUID {
        return self.vtable.newV6(self.ptr);
    }
    /// Generate a UUIDv6 using the given Gregorian timestamp.
    pub fn newV6AtTime(self: GeneratorInterface, ts: Timestamp) Error!UUID {
        return self.vtable.newV6AtTime(self.ptr, ts);
    }
    /// Generate a UUIDv8 (custom/experimental) from caller-provided fields.
    /// This function is infallible — no clock, random, or I/O is needed.
    pub fn newV8(self: GeneratorInterface, a: [6]u8, b: [2]u8, c: [8]u8) UUID {
        return self.vtable.newV8(self.ptr, a, b, c);
    }

    /// Wrap a *Generator as a GeneratorInterface.
    pub fn fromGenerator(gen: *Generator) GeneratorInterface {
        return .{ .ptr = gen, .vtable = &generator_vtable };
    }
};

// VTable implementation for the concrete Generator type.
// Each entry casts the opaque pointer back to *Generator and delegates (QC-38).
inline fn castGen(ptr: *anyopaque) *Generator {
    return @ptrCast(@alignCast(ptr));
}

const generator_vtable = GeneratorInterface.VTable{
    .newV4 = struct {
        fn f(p: *anyopaque) Error!UUID {
            return castGen(p).newV4();
        }
    }.f,
    .newV7 = struct {
        fn f(p: *anyopaque) Error!UUID {
            return castGen(p).newV7();
        }
    }.f,
    .newV7AtTime = struct {
        fn f(p: *anyopaque, ts: i64) Error!UUID {
            return castGen(p).newV7AtTime(ts);
        }
    }.f,
    .newV1 = struct {
        fn f(p: *anyopaque) Error!UUID {
            return castGen(p).newV1();
        }
    }.f,
    .newV1AtTime = struct {
        fn f(p: *anyopaque, ts: Timestamp) Error!UUID {
            return castGen(p).newV1AtTime(ts);
        }
    }.f,
    .newV3 = struct {
        fn f(p: *anyopaque, ns: UUID, name: []const u8) UUID {
            return castGen(p).newV3(ns, name);
        }
    }.f,
    .newV5 = struct {
        fn f(p: *anyopaque, ns: UUID, name: []const u8) UUID {
            return castGen(p).newV5(ns, name);
        }
    }.f,
    .newV6 = struct {
        fn f(p: *anyopaque) Error!UUID {
            return castGen(p).newV6();
        }
    }.f,
    .newV6AtTime = struct {
        fn f(p: *anyopaque, ts: Timestamp) Error!UUID {
            return castGen(p).newV6AtTime(ts);
        }
    }.f,
    .newV8 = struct {
        fn f(p: *anyopaque, a: [6]u8, b: [2]u8, c: [8]u8) UUID {
            return castGen(p).newV8(a, b, c);
        }
    }.f,
};

// =============================================================================
// PERF-31: GeneratorInterfaceFor — comptime-generic, zero-indirection wrapper.
//
// Unlike the vtable-based `GeneratorInterface` above (which erases the
// concrete generator type through `*anyopaque` and function pointers),
// `GeneratorInterfaceFor(G)` captures the concrete type `G` at compile time
// and dispatches every method via a direct call `self.g.<method>(...)`.
// LLVM inlines through the call at ReleaseFast, so a single-type call site
// pays no per-method overhead over calling the concrete method directly.
//
// Use this wrapper whenever:
//   - the generator's concrete type is known at the call site (the common
//     case in library-internal code and most application code), AND
//   - the hot path would benefit from inlining the UUID-generation body.
//
// Use the vtable `GeneratorInterface` when runtime polymorphism matters
// (dependency injection in tests, metric-wrapping middlewares, a function
// that must accept *either* a real Generator *or* a fake without
// recompiling). Both coexist — they are mutually complementary.
//
// The returned type exposes the exact method surface of `GeneratorInterface`
// (newV4, newV7, newV7AtTime, newV1, newV1AtTime, newV6, newV6AtTime, newV3,
// newV5, newV8) so the two interfaces are drop-in compatible at call sites.
// =============================================================================

/// PERF-31: comptime-generic, zero-indirection generator wrapper.
///
/// `GeneratorInterfaceFor(G)` captures the concrete generator type `G` at
/// compile time and dispatches every method via a direct `self.g.<method>`
/// call. LLVM inlines through the call at ReleaseFast, so a single-type
/// call site pays no per-method overhead relative to calling the concrete
/// method directly.
///
/// Prefer this wrapper when the generator's concrete type is known at the
/// call site and the hot path would benefit from inlining. Use the vtable
/// `GeneratorInterface` instead when runtime polymorphism is required
/// (dependency injection in tests, metric-wrapping middlewares, functions
/// that must accept either a real `Generator` or a fake without
/// recompiling). See the banner comment block above this declaration for
/// the full trade-off matrix.
///
/// The returned type exposes the same method surface as
/// `GeneratorInterface` (`newV4`, `newV7`, `newV7AtTime`, `newV1`,
/// `newV1AtTime`, `newV6`, `newV6AtTime`, `newV3`, `newV5`, `newV8`) so
/// the two interfaces are drop-in compatible at call sites.
///
/// ```zig
/// var gen = Generator.init();
/// var iface = GeneratorInterfaceFor(Generator){ .g = &gen };
/// const u = try iface.newV4();
/// ```
pub fn GeneratorInterfaceFor(comptime G: type) type {
    return struct {
        const Self = @This();

        /// Concrete generator pointer. The wrapper is a thin view — the
        /// caller owns the underlying `G` instance.
        g: *G,

        /// Generate a random UUIDv4 via the underlying generator.
        pub inline fn newV4(self: Self) Error!UUID {
            return self.g.newV4();
        }
        /// Generate a UUIDv7 using the system clock.
        pub inline fn newV7(self: Self) Error!UUID {
            return self.g.newV7();
        }
        /// Generate a UUIDv7 using the given Unix millisecond timestamp.
        pub inline fn newV7AtTime(self: Self, ts: i64) Error!UUID {
            return self.g.newV7AtTime(ts);
        }
        /// Generate a UUIDv1 (Gregorian timestamp + node ID).
        pub inline fn newV1(self: Self) Error!UUID {
            return self.g.newV1();
        }
        /// Generate a UUIDv1 using the given Gregorian timestamp.
        pub inline fn newV1AtTime(self: Self, ts: Timestamp) Error!UUID {
            return self.g.newV1AtTime(ts);
        }
        /// Generate a UUIDv6 (reordered Gregorian timestamp + node ID).
        pub inline fn newV6(self: Self) Error!UUID {
            return self.g.newV6();
        }
        /// Generate a UUIDv6 using the given Gregorian timestamp.
        pub inline fn newV6AtTime(self: Self, ts: Timestamp) Error!UUID {
            return self.g.newV6AtTime(ts);
        }
        /// Generate a UUIDv3 (MD5 name-based) from namespace and name.
        pub inline fn newV3(self: Self, ns: UUID, name: []const u8) UUID {
            return self.g.newV3(ns, name);
        }
        /// Generate a UUIDv5 (SHA-1 name-based) from namespace and name.
        pub inline fn newV5(self: Self, ns: UUID, name: []const u8) UUID {
            return self.g.newV5(ns, name);
        }
        /// Generate a UUIDv8 (custom/experimental) from caller-provided fields.
        pub inline fn newV8(self: Self, a: [6]u8, b: [2]u8, c: [8]u8) UUID {
            return self.g.newV8(a, b, c);
        }
    };
}

// =============================================================================
// Tests — split across two files to keep each under 800 lines (QC-4, QC-28)
//   generator_test.zig       — core generation tests
//   generator_state_test.zig — saveState / loadState tests
// =============================================================================

test {
    _ = @import("generator_test.zig");
    _ = @import("generator_state_test.zig");
}
