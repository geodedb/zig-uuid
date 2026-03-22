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

fn defaultClock() i128 {
    return std.time.nanoTimestamp();
}

fn defaultRand(buf: []u8) anyerror!void {
    std.crypto.random.bytes(buf);
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
    clock: ClockFn = defaultClock,
    rand: RandFn = defaultRand,

    /// Optional hardware-address function (F-1). When null (the default), V1
    /// and V6 UUIDs use a random multicast node ID, protecting privacy per
    /// RFC-9562 §8.  Set this field (or use withHWAddr) to opt in to
    /// MAC-based node IDs.
    hwaddr_fn: ?HWAddrFn = null,

    // PERF-19: Two independent mutexes for V7 and V1/V6 clock domains.
    // V7 generation only acquires v7_mutex; V1/V6 generation only acquires
    // v1v6_mutex.  saveState/loadState acquire both in fixed order
    // (v7_mutex first, then v1v6_mutex) to prevent deadlock.

    // V7 monotonicity state (protected by v7_mutex)
    v7_mutex: std.Thread.Mutex = .{},
    last_ms: i64 = 0,
    mono_seq: u12 = 0,

    // V1/V6 shared clock state (protected by v1v6_mutex; F-8: documented above)
    v1v6_mutex: std.Thread.Mutex = .{},
    clock_seq: u14 = 0,
    clock_seq_initialized: bool = false,
    last_v1_ts: u60 = 0,

    /// Cached node ID for V1/V6 generation (F-4 + F-6/G-6).
    /// null = not yet fetched; populated on first V1/V6 call.
    node_cache: ?[6]u8 = null,

    /// Previously-used node ID for change detection (F-4).
    last_node: ?[6]u8 = null,

    /// Create a new generator with default clock (std.time.nanoTimestamp),
    /// CSPRNG (std.crypto.random), and random multicast node ID.
    pub fn init() Generator {
        return .{};
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
    /// SEC-R6-01: Acquires v1v6_mutex before writing node_cache so that the
    /// write is not concurrent with resolveV1V6State (which also reads and
    /// writes node_cache under the same mutex).  Without this lock, a race
    /// exists between clearNodeCache and any in-flight V1/V6 generation.
    pub fn clearNodeCache(self: *Generator) void {
        self.v1v6_mutex.lock();
        defer self.v1v6_mutex.unlock();
        self.node_cache = null;
    }

    /// Generate a UUIDv4 (random).
    ///
    /// All 122 non-version/variant bits are filled from the CSPRNG source.
    /// Returns `Error.RandomError` if the underlying random function fails.
    pub fn newV4(self: *Generator) Error!UUID {
        var u: UUID = undefined;
        self.rand(&u.bytes) catch return Error.RandomError;
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
        // PERF-07: Read clock inside the mutex to use the freshest possible
        // timestamp and avoid stale-timestamp collisions under high contention.
        self.v7_mutex.lock();
        var ms = clockToMs(self.clock()) catch |err| {
            self.v7_mutex.unlock();
            return err;
        };
        // SEC-R14-02 (CWE-1284): If the system clock jumped backward (NTP
        // correction, VM migration), preserve last_ms to maintain V7 k-sortable
        // monotonicity.  This only applies to clock-derived timestamps; user-
        // provided timestamps via newV7AtTime are accepted as-is.
        if (ms < self.last_ms) ms = self.last_ms;
        return self.newV7Locked(ms);
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
        self.v7_mutex.lock();
        return self.newV7Locked(ts);
    }

    /// V7 generation core. Caller must hold `mutex` on entry; this function
    /// always releases `mutex` before returning (on success or error path).
    ///
    /// PERF-12: Uses Thread.sleep(ns_to_next_ms) in the overflow spin-wait.
    ///   PERF-01 previously switched from Thread.sleep(100_000 ns) to
    ///   Thread.yield() to reduce per-spin latency.  However Thread.yield()
    ///   maps to sched_yield(2), which returns immediately when no other thread
    ///   is ready, producing a busy-wait that burns 82% of V7 CPU time
    ///   (~3.28M yields per 1M calls).  Thread.sleep(ns_remaining_in_ms)
    ///   sleeps precisely until the next ms boundary: 1 syscall per overflow
    ///   vs ~8,000 yields, and correctly idles the CPU.
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
        while (ms == self.last_ms and self.mono_seq == std.math.maxInt(u12)) {
            spins += 1;
            if (spins > max_spins) {
                self.v7_mutex.unlock();
                return Error.InvalidTimestamp;
            }
            // SEC-R13-01: Cache one clock reading per spin iteration. Both
            // the sleep-duration computation and the ms-advance check use
            // ns_now, preventing divergence from two independent self.clock()
            // calls under non-monotonic or injected clocks.
            const ns_now = self.clock();

            // SEC-R4-01: derive ms from the cached clock reading; propagate
            // InvalidTimestamp if the value is out of range.
            ms = clockToMs(ns_now) catch |err| {
                self.v7_mutex.unlock();
                return err;
            };
            // SEC-R14-02: clamp backward clock to preserve monotonicity
            if (ms < self.last_ms) ms = self.last_ms;

            // If the clock has already advanced past last_ms (or another
            // thread reset mono_seq), skip the sleep — the while condition
            // will exit on the next check.
            if (ms != self.last_ms or self.mono_seq != std.math.maxInt(u12)) break;

            // Compute nanoseconds remaining in the current millisecond.
            // @rem(ns_now, 1_000_000) gives the fraction within [0, 999_999];
            // subtracting from 1_000_000 gives the sleep duration [1, 1_000_000].
            // Fall back to 500µs if the clock returns an invalid/negative value.
            const sleep_ns: u64 = if (ns_now > 0) blk: {
                const ns_frac: u64 = @intCast(@rem(ns_now, 1_000_000));
                break :blk 1_000_000 - ns_frac;
            } else 500_000;
            self.v7_mutex.unlock();
            std.Thread.sleep(sleep_ns);
            self.v7_mutex.lock();
        }

        // Single branch: same-ms increment OR new-ms reset. seq is always assigned.
        // Note: clock regression is handled upstream — newV7() clamps ms to last_ms
        // before calling this function (SEC-R14-02), and the spin-wait loop applies
        // the same clamp after each clock re-read.
        var seq: u12 = undefined;
        if (ms == self.last_ms) {
            // Same ms: increment (the spin-wait above guarantees mono_seq < maxInt).
            self.mono_seq += 1;
            seq = self.mono_seq;
        } else {
            // New ms: seed mono_seq with random jitter (RFC-9562 §6.2).
            var rand_seq: [2]u8 = undefined;
            self.rand(&rand_seq) catch {
                self.v7_mutex.unlock();
                return Error.RandomError;
            };
            self.mono_seq = @truncate(std.mem.readInt(u16, &rand_seq, .little) & 0x0FFF);
            seq = self.mono_seq;
            self.last_ms = ms;
        }

        // PERF-02: Release v7_mutex before the 8-byte rand_b CSPRNG call.
        // All shared state (last_ms, mono_seq) is committed above; UUID
        // construction uses only stack-local variables.
        self.v7_mutex.unlock();

        var u: UUID = undefined;
        // unix_ts_ms: 48 bits big-endian in bytes 0-5
        const ms_u: u64 = @intCast(ms);
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(ms_u >> 16), .big);
        std.mem.writeInt(u16, u.bytes[4..6], @truncate(ms_u), .big);
        // rand_a: 12-bit monotonic counter in low 12 bits of bytes 6-7
        std.mem.writeInt(u16, u.bytes[6..8], seq, .big);
        // rand_b: 62 bits random in bytes 8-15 (outside the mutex, PERF-02)
        self.rand(u.bytes[8..16]) catch return Error.RandomError;
        u.setVersion(.v7);
        u.setVariant(.rfc9562);
        return u;
    }

    /// Initialise clock_seq from CSPRNG (F-3).
    ///
    /// Changed from the original to propagate CSPRNG failure rather than
    /// silently using the hardcoded constant 0x1234.  RFC-9562 §6.1 MUST:
    /// "The clock sequence MUST be originally initialized to a random number."
    fn initClockSeq(self: *Generator) Error!void {
        if (self.clock_seq_initialized) return;
        var buf: [2]u8 = undefined;
        self.rand(&buf) catch return Error.RandomError;
        self.clock_seq = @truncate(std.mem.readInt(u16, &buf, .little) & 0x3FFF);
        self.clock_seq_initialized = true;
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
        self.rand(&node) catch return Error.RandomError;
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
        if (self.node_cache) |n| return n;
        const node = try self.fetchRawNode();
        self.node_cache = node;
        return node;
    }

    /// Shared state-resolution helper for V1 and V6 generation (QC-1).
    ///
    /// Acquires and releases v1v6_mutex, initialises clock_seq, updates
    /// last_v1_ts, populates the node cache, and handles F-4 node-change
    /// detection.  Returns the resolved (timestamp, node, clock_seq) so that
    /// each public function only needs to perform its version-specific
    /// timestamp byte encoding.
    ///
    /// **caller must NOT hold v1v6_mutex on entry.**
    fn resolveV1V6State(
        self: *Generator,
        ts: Timestamp,
        prefetched: ?[6]u8,
    ) Error!struct { t: u60, node: [6]u8, clock_seq: u14 } {
        self.v1v6_mutex.lock();
        defer self.v1v6_mutex.unlock();
        try self.initClockSeq(); // F-3: propagate CSPRNG failure
        // Increment clock_seq on clock regression OR same-timestamp call (RFC-9562 §6.1).
        // Using <= (not <) ensures concurrent/repeated calls at identical timestamps
        // each get a unique clock_seq, preventing duplicate UUID production.
        // This fixes the same-timestamp uniqueness bug (gofrs/uuid #216).
        if (ts.value <= self.last_v1_ts) {
            self.clock_seq = (self.clock_seq +% 1) & 0x3FFF;
        }
        self.last_v1_ts = ts.value;
        // Populate cache under lock if it was null (double-check for concurrent warmup).
        if (self.node_cache == null) {
            self.node_cache = prefetched orelse try self.fetchRawNode();
        }
        // F-4: detect node ID change and increment clock_seq
        const old_node = self.last_node;
        const node = try self.getNode(); // guaranteed cache hit after the block above
        if (old_node) |on| {
            if (!std.mem.eql(u8, &on, &node)) {
                self.clock_seq = (self.clock_seq +% 1) & 0x3FFF;
            }
        }
        self.last_node = node;
        return .{ .t = ts.value, .node = node, .clock_seq = self.clock_seq };
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
        // PERF-05: Pre-fetch node outside the mutex on the cold path to avoid
        // blocking all threads during OS syscalls (socket + ioctl on Linux,
        // getifaddrs on macOS).  fetchRawNode reads only immutable generator
        // fields so it is safe without the lock.
        const prefetched: ?[6]u8 = if (self.node_cache == null)
            try self.fetchRawNode()
        else
            null;

        const s = try self.resolveV1V6State(ts, prefetched);
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
        // PERF-05: Pre-fetch node outside the mutex on the cold path.
        const prefetched: ?[6]u8 = if (self.node_cache == null)
            try self.fetchRawNode()
        else
            null;

        const s = try self.resolveV1V6State(ts, prefetched);
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
    /// **Version 2 (32 bytes, current):**
    /// [0..4]   magic "UUID"
    /// [4]      format version = 2
    /// [5]      flags: bit0=clock_seq_initialized, bit1=has_node_cache
    /// [6..8]   clock_seq as u16 LE
    /// [8..16]  last_v1_ts as u64 LE
    /// [16..22] node_cache [6]u8
    /// [22..30] last_ms as i64 LE  (SEC-10: V7 last-used timestamp)
    /// [30..32] mono_seq as u16 LE (SEC-10: V7 counter; see loadState for clock-based handling)
    ///
    /// saveState() always writes version 2.  loadState() accepts both versions.
    pub const state_magic: [4]u8 = "UUID".*;
    pub const state_format_version_v1: u8 = 1;
    pub const state_format_version: u8 = 2; // current write version
    pub const state_size_v1: usize = 22;
    pub const state_size: usize = 32;

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
    pub fn saveState(self: *Generator, path: []const u8) !void {
        // Snapshot state under both mutexes; release before I/O.
        // PERF-19: acquire in fixed order (v7 first, then v1v6) to prevent deadlock.
        var buf: [state_size]u8 = undefined;
        {
            self.v7_mutex.lock();
            defer self.v7_mutex.unlock();
            self.v1v6_mutex.lock();
            defer self.v1v6_mutex.unlock();

            @memcpy(buf[0..4], &state_magic);
            buf[4] = state_format_version; // = 2

            var flags: u8 = 0;
            if (self.clock_seq_initialized) flags |= 0x01;
            if (self.node_cache != null) flags |= 0x02;
            buf[5] = flags;

            std.mem.writeInt(u16, buf[6..8], @as(u16, self.clock_seq), .little);
            std.mem.writeInt(u64, buf[8..16], @as(u64, self.last_v1_ts), .little);
            if (self.node_cache) |n| {
                @memcpy(buf[16..22], &n);
            } else {
                @memset(buf[16..22], 0);
            }
            // SEC-10: persist V7 state.
            std.mem.writeInt(i64, buf[22..30], self.last_ms, .little);
            std.mem.writeInt(u16, buf[30..32], @as(u16, self.mono_seq), .little);
        }

        // SEC-9: atomic write — write to <path>.tmp then rename so that a
        // crash or signal between write and close never leaves a torn file.
        // SEC-1: mode 0o600 prevents other local users reading the state,
        // which may contain the node ID (hardware MAC when hwaddr_fn is set).
        // SEC-R3-01 (CWE-61): Remove any stale or attacker-placed file/symlink at
        // the .tmp path before creating, then use exclusive:true (O_EXCL|O_CREAT on
        // POSIX) so the OS refuses to follow a symlink or overwrite any file that
        // appears between delete and create.  This makes saveState symlink-safe:
        //   - deleteFileAbsolute unlinks any pre-placed symlink (not the target).
        //   - exclusive:true fails with EEXIST if a new symlink/file appears in the
        //     TOCTOU window, preventing the write from reaching the symlink target.
        // The mutex is NOT held during I/O (see PERF note above).
        // SEC-R2-15: Use a named constant instead of the magic number 4100.
        // 4096 = OS maximum path length (POSIX PATH_MAX); + 4 for ".tmp" suffix.
        const tmp_suffix = ".tmp";
        var tmp_path_buf: [4096 + tmp_suffix.len]u8 = undefined;
        const tmp_path = try std.fmt.bufPrint(&tmp_path_buf, "{s}{s}", .{ path, tmp_suffix });
        // Remove any stale .tmp (e.g., from a previous crashed run) or a pre-placed
        // symlink.  Errors (FileNotFound etc.) are intentionally ignored.
        std.fs.deleteFileAbsolute(tmp_path) catch {};
        {
            // exclusive:true → O_EXCL on POSIX: fails if any file or symlink now
            // exists at tmp_path, preventing symlink-following on creation.
            const f = try std.fs.createFileAbsolute(tmp_path, .{ .mode = 0o600, .exclusive = true });
            errdefer std.fs.deleteFileAbsolute(tmp_path) catch {};
            defer f.close();
            try f.writeAll(&buf);
        }
        try std.fs.renameAbsolute(tmp_path, path);
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
    pub fn loadState(self: *Generator, path: []const u8) !void {
        // SEC-R11-04 (CWE-61): Open the state file without following symlinks
        // on POSIX targets.  An attacker who can place a symlink at the state-file
        // path before loadState runs could redirect the read to any world-readable
        // file, leaking its contents.  O_NOFOLLOW causes open(2) to fail with
        // ELOOP if the path is a symlink, closing the redirect.  On Windows,
        // symlink handling is enforced differently by the OS; openFileAbsolute
        // is used unchanged.
        const f = if (builtin.os.tag == .windows)
            try std.fs.openFileAbsolute(path, .{})
        else blk: {
            const fd = try std.posix.open(path, .{ .NOFOLLOW = true }, 0);
            break :blk std.fs.File{ .handle = fd };
        };
        defer f.close();

        // SEC-R13-04 (CWE-908): Zero-initialize to prevent uninitialized reads.
        // For v1 state files (22 bytes), bytes 22–31 are never written by readAll.
        // The version-2 guard prevents consumption, but zeroing eliminates the
        // latent risk if that guard is weakened in a future refactor.
        var buf: [state_size]u8 = std.mem.zeroes([state_size]u8);
        const n = try f.readAll(&buf);

        // Accept both v1 (22 bytes) and v2 (32 bytes).
        if (n != state_size_v1 and n != state_size) return Error.InvalidFormat;

        // SEC-R4-03: reject files with trailing bytes.  readAll fills buf up
        // to buf.len even when the file is larger, so n alone cannot detect
        // oversized files.  A one-byte probe read must return 0 (EOF).
        var probe: [1]u8 = undefined;
        const extra = try f.read(&probe);
        if (extra != 0) return Error.InvalidFormat;
        if (!std.mem.eql(u8, buf[0..4], &state_magic)) return Error.InvalidFormat;
        if (buf[4] != state_format_version_v1 and buf[4] != state_format_version) return Error.InvalidFormat;

        // SEC-R13-08 (CWE-833): Read the clock BEFORE acquiring the mutex.
        // If ClockFn blocks (network-backed NTP, slow hardware clock, test
        // double with artificial delay), all concurrent UUID generation calls
        // that contend on the mutexes would stall for the duration.  Reading
        // clock outside the critical section eliminates this availability risk.
        // QC-29: use the injectable clock (self.clock) instead of the raw
        // syscall so that the fast-restart branch is testable via clock injection.
        // Errors (negative/overflow clock) fall back to 0, which activates the
        // conservative overflow path — the safe default.
        const current_ms: i64 = clockToMs(self.clock()) catch 0;

        // PERF-19: acquire in fixed order (v7 first, then v1v6) to prevent deadlock.
        self.v7_mutex.lock();
        defer self.v7_mutex.unlock();
        self.v1v6_mutex.lock();
        defer self.v1v6_mutex.unlock();

        const flags = buf[5];
        self.clock_seq = @truncate(std.mem.readInt(u16, buf[6..8], .little) & 0x3FFF);
        self.clock_seq_initialized = (flags & 0x01) != 0;
        // SEC-R6-04: Reject out-of-range last_v1_ts rather than truncating
        // silently.  A u64 value above maxInt(u60) indicates a corrupt or
        // tampered state file; return InvalidFormat instead of truncating to
        // a valid-looking timestamp.
        const raw_ts = std.mem.readInt(u64, buf[8..16], .little);
        if (raw_ts > std.math.maxInt(u60)) return Error.InvalidFormat;
        self.last_v1_ts = @truncate(raw_ts);
        if ((flags & 0x02) != 0) {
            self.node_cache = buf[16..22][0..6].*;
        } else {
            self.node_cache = null;
        }

        // PERF-04 + SEC-10: restore V7 state only from version-2 files.
        if (buf[4] == state_format_version and n == state_size) {
            const saved_ms = std.mem.readInt(i64, buf[22..30], .little);
            if (current_ms > saved_ms) {
                self.last_ms = 0;
                self.mono_seq = 0;
            } else {
                self.last_ms = saved_ms;
                self.mono_seq = std.math.maxInt(u12);
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
// Tests — split across two files to keep each under 800 lines (QC-4, QC-28)
//   generator_test.zig       — core generation tests
//   generator_state_test.zig — saveState / loadState tests
// =============================================================================

test {
    _ = @import("generator_test.zig");
    _ = @import("generator_state_test.zig");
}
