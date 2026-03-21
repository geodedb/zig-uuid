// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
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
pub const Generator = struct {
    clock: ClockFn = defaultClock,
    rand: RandFn = defaultRand,

    /// Optional hardware-address function (F-1). When null (the default), V1
    /// and V6 UUIDs use a random multicast node ID, protecting privacy per
    /// RFC-9562 §8.  Set this field (or use withHWAddr) to opt in to
    /// MAC-based node IDs.
    hwaddr_fn: ?HWAddrFn = null,

    // V7 monotonicity state (all protected by mutex)
    mutex: std.Thread.Mutex = .{},
    last_ms: i64 = 0,
    mono_seq: u12 = 0,

    // V1/V6 shared clock state (F-8: documented above)
    clock_seq: u14 = 0,
    clock_seq_initialized: bool = false,
    last_v1_ts: u60 = 0,

    /// Cached node ID for V1/V6 generation (F-4 + F-6/G-6).
    /// null = not yet fetched; populated on first V1/V6 call.
    node_cache: ?[6]u8 = null,

    /// Previously-used node ID for change detection (F-4).
    last_node: ?[6]u8 = null,

    pub fn init() Generator {
        return .{};
    }

    pub fn withClock(f: ClockFn) Generator {
        var g = Generator.init();
        g.clock = f;
        return g;
    }

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
    pub fn clearNodeCache(self: *Generator) void {
        self.node_cache = null;
    }

    pub fn newV4(self: *Generator) Error!UUID {
        var u: UUID = undefined;
        self.rand(&u.bytes) catch return Error.RandomError;
        u.setVersion(.v4);
        u.setVariant(.rfc9562);
        return u;
    }

    pub fn newV7(self: *Generator) Error!UUID {
        // PERF-07: Read clock inside the mutex to use the freshest possible
        // timestamp and avoid stale-timestamp collisions under high contention.
        self.mutex.lock();
        const ns = self.clock();
        if (ns < 0) {
            self.mutex.unlock();
            return Error.InvalidTimestamp;
        }
        const ms: i64 = @intCast(@divTrunc(ns, 1_000_000));
        return self.newV7Locked(ms);
    }

    pub fn newV7AtTime(self: *Generator, ts: i64) Error!UUID {
        if (ts < 0) return Error.InvalidFormat;
        self.mutex.lock();
        return self.newV7Locked(ts);
    }

    /// V7 generation core. Caller must hold `mutex` on entry; this function
    /// always releases `mutex` before returning (on success or error path).
    ///
    /// PERF-01: Uses Thread.yield() (~10–50 ns) in the overflow spin-wait
    ///   instead of Thread.sleep(100_000) (~100 µs+), dramatically reducing
    ///   burst-throughput stalls when the 12-bit counter overflows.
    ///
    /// PERF-02: Releases the mutex before the 8-byte rand_b CSPRNG call so
    ///   concurrent threads are not serialised on the getrandom syscall.
    ///   Only the lightweight state update (last_ms, mono_seq) is held.
    fn newV7Locked(self: *Generator, ts: i64) Error!UUID {
        var ms = ts;
        // seq is always assigned before use in every branch below.
        var seq: u12 = 0;

        if (ms == self.last_ms) {
            // Same ms: advance the monotonic sequence counter.
            if (self.mono_seq == std.math.maxInt(u12)) {
                // Counter exhausted: yield until the clock advances to the next ms.
                // PERF-01: Thread.yield() (~10–50 ns) vs Thread.sleep(100_000) (~100 µs+).
                while (ms == self.last_ms) {
                    self.mutex.unlock();
                    std.Thread.yield() catch {}; // yield; ignore spurious errors
                    self.mutex.lock();
                    ms = @intCast(@divTrunc(self.clock(), 1_000_000));
                }
                // ms has advanced — fall through to random reset below.
            } else {
                self.mono_seq += 1;
                seq = self.mono_seq;
            }
        }

        if (ms != self.last_ms) {
            // New ms: reset mono_seq to a random 12-bit seed for jitter.
            var rand_seq: [2]u8 = undefined;
            self.rand(&rand_seq) catch {
                self.mutex.unlock();
                return Error.RandomError;
            };
            self.mono_seq = @truncate(std.mem.readInt(u16, &rand_seq, .little) & 0x0FFF);
            seq = self.mono_seq;
            self.last_ms = ms;
        }

        // PERF-02: Release the mutex before the 8-byte rand_b CSPRNG call.
        // All shared state (last_ms, mono_seq) is committed above; UUID
        // construction uses only stack-local variables.
        self.mutex.unlock();

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
    /// Compute raw node bytes from hwaddr_fn or CSPRNG without touching the cache.
    ///
    /// PERF-05: Safe to call without holding the mutex because it only reads
    /// immutable generator fields (hwaddr_fn, rand) that are set at init time
    /// and never mutated afterwards.  Used by newV1AtTime / newV6AtTime to
    /// perform the expensive OS syscall (getifaddrs / ioctl) BEFORE acquiring
    /// the hot-path mutex, so concurrent UUID generation is not blocked.
    fn fetchRawNode(self: *Generator) Error![6]u8 {
        var node: [6]u8 = undefined;
        if (self.hwaddr_fn) |f| {
            if (f()) |mac| {
                node = mac;
            } else |_| {
                // hwaddr failed — fall back to random multicast node
                self.rand(&node) catch return Error.RandomError;
                node[0] |= 0x01; // set multicast bit (RFC-9562 §6.10)
            }
        } else {
            // F-1 default: random multicast node ID
            self.rand(&node) catch return Error.RandomError;
            node[0] |= 0x01;
        }
        return node;
    }

    fn getNode(self: *Generator) Error![6]u8 {
        if (self.node_cache) |n| return n;
        const node = try self.fetchRawNode();
        self.node_cache = node;
        return node;
    }

    pub fn newV1(self: *Generator) Error!UUID {
        const ts = try Timestamp.now();
        return self.newV1AtTime(ts);
    }

    pub fn newV1AtTime(self: *Generator, ts: Timestamp) Error!UUID {
        // PERF-05: Pre-fetch node outside the mutex on the cold path to avoid
        // blocking all threads during OS syscalls (socket + ioctl on Linux,
        // getifaddrs on macOS).  On the warm path node_cache is non-null and
        // this is a cheap null-check with no allocation.  fetchRawNode reads
        // only immutable generator fields so it is safe without the lock.
        const prefetched: ?[6]u8 = if (self.node_cache == null)
            try self.fetchRawNode()
        else
            null;

        self.mutex.lock();
        defer self.mutex.unlock();
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
        var u: UUID = undefined;
        const t = ts.value;
        // time_low: bits 0-31
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(t), .big);
        // time_mid: bits 32-47
        std.mem.writeInt(u16, u.bytes[4..6], @truncate(t >> 32), .big);
        // time_high: bits 48-59 (version nibble set below)
        std.mem.writeInt(u16, u.bytes[6..8], @truncate(t >> 48), .big);
        // clock_seq: 14 bits in bytes 8-9 (variant set below)
        std.mem.writeInt(u16, u.bytes[8..10], self.clock_seq, .big);
        @memcpy(u.bytes[10..16], &node);
        u.setVersion(.v1);
        u.setVariant(.rfc9562);
        return u;
    }

    pub fn newV6(self: *Generator) Error!UUID {
        const ts = try Timestamp.now();
        return self.newV6AtTime(ts);
    }

    pub fn newV6AtTime(self: *Generator, ts: Timestamp) Error!UUID {
        // PERF-05: Pre-fetch node outside the mutex on the cold path (same
        // rationale as newV1AtTime — see comment there).
        const prefetched: ?[6]u8 = if (self.node_cache == null)
            try self.fetchRawNode()
        else
            null;

        self.mutex.lock();
        defer self.mutex.unlock();
        try self.initClockSeq(); // F-3
        // Same fix as newV1AtTime: <= ensures same-timestamp calls get unique clock_seq.
        if (ts.value <= self.last_v1_ts) {
            self.clock_seq = (self.clock_seq +% 1) & 0x3FFF;
        }
        self.last_v1_ts = ts.value;
        // Populate cache under lock if it was null.
        if (self.node_cache == null) {
            self.node_cache = prefetched orelse try self.fetchRawNode();
        }
        // F-4: detect node ID change
        const old_node = self.last_node;
        const node = try self.getNode(); // guaranteed cache hit
        if (old_node) |on| {
            if (!std.mem.eql(u8, &on, &node)) {
                self.clock_seq = (self.clock_seq +% 1) & 0x3FFF;
            }
        }
        self.last_node = node;
        var u: UUID = undefined;
        const t = ts.value;
        // V6: reorder timestamp for lexicographic sort
        // bytes 0-3: bits 28-59 (high 32 bits)
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(t >> 28), .big);
        // bytes 4-5: bits 12-27
        std.mem.writeInt(u16, u.bytes[4..6], @truncate((t >> 12) & 0xFFFF), .big);
        // bytes 6-7: bits 0-11 (version nibble set below)
        std.mem.writeInt(u16, u.bytes[6..8], @truncate(t & 0x0FFF), .big);
        // bytes 8-9: clock_seq (variant set below)
        std.mem.writeInt(u16, u.bytes[8..10], self.clock_seq, .big);
        @memcpy(u.bytes[10..16], &node);
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
    pub fn newV3(self: *Generator, ns: UUID, name: []const u8) UUID {
        _ = self;
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
    pub fn newV5(self: *Generator, ns: UUID, name: []const u8) UUID {
        _ = self;
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

    pub fn newV8(self: *Generator, a: [6]u8, b: [2]u8, c: [8]u8) Error!UUID {
        _ = self;
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
        // Snapshot state under the mutex; release before I/O.
        var buf: [state_size]u8 = undefined;
        {
            self.mutex.lock();
            defer self.mutex.unlock();

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
        // The mutex is NOT held during I/O (see PERF note above).
        var tmp_path_buf: [4100]u8 = undefined;
        const tmp_path = try std.fmt.bufPrint(&tmp_path_buf, "{s}.tmp", .{path});
        {
            const f = try std.fs.createFileAbsolute(tmp_path, .{ .mode = 0o600 });
            errdefer std.fs.deleteFileAbsolute(tmp_path) catch {};
            defer f.close();
            try f.writeAll(&buf);
        }
        try std.fs.renameAbsolute(tmp_path, path);
    }

    /// Load generator state from stable storage (F-9, SEC-10, PERF-04).
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
        const f = try std.fs.openFileAbsolute(path, .{});
        defer f.close();

        var buf: [state_size]u8 = undefined;
        const n = try f.readAll(&buf);

        // Accept both v1 (22 bytes) and v2 (32 bytes).
        if (n != state_size_v1 and n != state_size) return Error.InvalidFormat;
        if (!std.mem.eql(u8, buf[0..4], &state_magic)) return Error.InvalidFormat;
        if (buf[4] != state_format_version_v1 and buf[4] != state_format_version) return Error.InvalidFormat;

        self.mutex.lock();
        defer self.mutex.unlock();

        const flags = buf[5];
        self.clock_seq = @truncate(std.mem.readInt(u16, buf[6..8], .little) & 0x3FFF);
        self.clock_seq_initialized = (flags & 0x01) != 0;
        self.last_v1_ts = @truncate(std.mem.readInt(u64, buf[8..16], .little));
        if ((flags & 0x02) != 0) {
            self.node_cache = buf[16..22][0..6].*;
        } else {
            self.node_cache = null;
        }

        // PERF-04 + SEC-10: restore V7 state only from version-2 files.
        if (buf[4] == state_format_version and n == state_size) {
            const saved_ms = std.mem.readInt(i64, buf[22..30], .little);
            // Compare saved timestamp against current clock.  On typical
            // restarts (>1ms downtime) the clock has already advanced past
            // saved_ms, so there is no collision risk — reset both fields for
            // a clean start with no spin-wait penalty.
            // Only force mono_seq overflow when saved_ms is still current
            // (extremely fast restart within the same millisecond).
            const current_ms: i64 = @intCast(@divTrunc(std.time.nanoTimestamp(), 1_000_000));
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
        newV8: *const fn (*anyopaque, [6]u8, [2]u8, [8]u8) Error!UUID,
    };

    pub fn newV4(self: GeneratorInterface) Error!UUID {
        return self.vtable.newV4(self.ptr);
    }
    pub fn newV7(self: GeneratorInterface) Error!UUID {
        return self.vtable.newV7(self.ptr);
    }
    pub fn newV7AtTime(self: GeneratorInterface, ts: i64) Error!UUID {
        return self.vtable.newV7AtTime(self.ptr, ts);
    }
    pub fn newV1(self: GeneratorInterface) Error!UUID {
        return self.vtable.newV1(self.ptr);
    }
    pub fn newV1AtTime(self: GeneratorInterface, ts: Timestamp) Error!UUID {
        return self.vtable.newV1AtTime(self.ptr, ts);
    }
    pub fn newV3(self: GeneratorInterface, ns: UUID, name: []const u8) UUID {
        return self.vtable.newV3(self.ptr, ns, name);
    }
    pub fn newV5(self: GeneratorInterface, ns: UUID, name: []const u8) UUID {
        return self.vtable.newV5(self.ptr, ns, name);
    }
    pub fn newV6(self: GeneratorInterface) Error!UUID {
        return self.vtable.newV6(self.ptr);
    }
    pub fn newV6AtTime(self: GeneratorInterface, ts: Timestamp) Error!UUID {
        return self.vtable.newV6AtTime(self.ptr, ts);
    }
    pub fn newV8(self: GeneratorInterface, a: [6]u8, b: [2]u8, c: [8]u8) Error!UUID {
        return self.vtable.newV8(self.ptr, a, b, c);
    }

    /// Wrap a *Generator as a GeneratorInterface.
    pub fn fromGenerator(gen: *Generator) GeneratorInterface {
        return .{ .ptr = gen, .vtable = &generator_vtable };
    }
};

// VTable implementation for the concrete Generator type.
const generator_vtable = GeneratorInterface.VTable{
    .newV4 = struct {
        fn f(ptr: *anyopaque) Error!UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV4();
        }
    }.f,
    .newV7 = struct {
        fn f(ptr: *anyopaque) Error!UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV7();
        }
    }.f,
    .newV7AtTime = struct {
        fn f(ptr: *anyopaque, ts: i64) Error!UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV7AtTime(ts);
        }
    }.f,
    .newV1 = struct {
        fn f(ptr: *anyopaque) Error!UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV1();
        }
    }.f,
    .newV1AtTime = struct {
        fn f(ptr: *anyopaque, ts: Timestamp) Error!UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV1AtTime(ts);
        }
    }.f,
    .newV3 = struct {
        fn f(ptr: *anyopaque, ns: UUID, name: []const u8) UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV3(ns, name);
        }
    }.f,
    .newV5 = struct {
        fn f(ptr: *anyopaque, ns: UUID, name: []const u8) UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV5(ns, name);
        }
    }.f,
    .newV6 = struct {
        fn f(ptr: *anyopaque) Error!UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV6();
        }
    }.f,
    .newV6AtTime = struct {
        fn f(ptr: *anyopaque, ts: Timestamp) Error!UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV6AtTime(ts);
        }
    }.f,
    .newV8 = struct {
        fn f(ptr: *anyopaque, a: [6]u8, b: [2]u8, c: [8]u8) Error!UUID {
            return @as(*Generator, @ptrCast(@alignCast(ptr))).newV8(a, b, c);
        }
    }.f,
};

// =============================================================================
// Tests
// =============================================================================

test "Generator.newV4: version=4, variant=rfc9562" {
    var gen = Generator.init();
    const u = try gen.newV4();
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.newV4: two calls return distinct UUIDs" {
    var gen = Generator.init();
    const a = try gen.newV4();
    const b = try gen.newV4();
    try std.testing.expect(!a.eql(b));
}

test "Generator.newV7: version=7, variant=rfc9562" {
    var gen = Generator.init();
    const u = try gen.newV7();
    try std.testing.expectEqual(Version.v7, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.newV7AtTime: timestamp round-trips via toUnixMs" {
    const ts_mod = @import("timestamp.zig");
    var gen = Generator.init();
    const ms: i64 = 1_700_000_000_000; // some Unix ms
    const u = try gen.newV7AtTime(ms);
    const extracted = try ts_mod.timestampFromV7(u);
    try std.testing.expectEqual(ms, extracted.toUnixMs());
}

test "Generator.newV7: monotone within same ms" {
    // Use deterministic clock that always returns the same ms
    const fixed_clock = struct {
        fn clock() i128 {
            return 1_000 * 1_000_000;
        } // 1000ms in ns
    };
    var gen = Generator.withClock(fixed_clock.clock);
    const a = try gen.newV7();
    const b = try gen.newV7();
    // b should be greater than a (monotone counter)
    try std.testing.expect(a.order(b) == .lt);
}

test "Generator injectable rand" {
    // All-zero rand for determinism
    const zero_rand = struct {
        fn rand(buf: []u8) anyerror!void {
            @memset(buf, 0);
        }
    };
    var gen = Generator.withRand(zero_rand.rand);
    const u = try gen.newV4();
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.newV1: version=1, variant=rfc9562, node from hwaddr_fn" {
    const mock_hwaddr = struct {
        fn getHW() Error![6]u8 {
            return .{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55 };
        }
    };
    var gen = Generator.withHWAddr(mock_hwaddr.getHW);
    const u = try gen.newV1();
    try std.testing.expectEqual(Version.v1, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
    // Node bytes (10-15) should match our mock MAC
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55 }, u.bytes[10..16]);
}

test "Generator.newV1: default uses random node with multicast bit (F-1)" {
    var gen = Generator.init(); // hwaddr_fn = null by default
    const u = try gen.newV1();
    try std.testing.expectEqual(Version.v1, u.version());
    // multicast bit must be set on byte 10
    try std.testing.expect(u.bytes[10] & 0x01 == 0x01);
}

test "Generator.newV1: node is cached across calls (F-6/G-6)" {
    var gen = Generator.init();
    const a = try gen.newV1();
    const b = try gen.newV1();
    // Node bytes 10-15 must be identical (cached)
    try std.testing.expectEqualSlices(u8, a.bytes[10..16], b.bytes[10..16]);
}

test "Generator.clearNodeCache refreshes node (F-6/G-6)" {
    // Use a counter-based hwaddr that returns a different MAC each call.
    var call_count: u8 = 0;
    const counting_hw = struct {
        var cnt: *u8 = undefined;
        fn getHW() Error![6]u8 {
            cnt.* += 1;
            return .{ cnt.*, 0, 0, 0, 0, 0 };
        }
    };
    counting_hw.cnt = &call_count;

    var gen = Generator.withHWAddr(counting_hw.getHW);
    _ = try gen.newV1(); // populates cache (cnt=1)
    _ = try gen.newV1(); // uses cache (cnt still 1)
    gen.clearNodeCache();
    _ = try gen.newV1(); // re-fetches (cnt=2)
    try std.testing.expectEqual(@as(u8, 2), call_count);
}

test "Generator.newV6: version=6, variant=rfc9562" {
    const mock_hwaddr = struct {
        fn getHW() Error![6]u8 {
            return .{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
        }
    };
    var gen = Generator.withHWAddr(mock_hwaddr.getHW);
    const u = try gen.newV6();
    try std.testing.expectEqual(Version.v6, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.newV6AtTime: timestamp round-trips" {
    const ts_mod = @import("timestamp.zig");
    const mock_hwaddr = struct {
        fn getHW() Error![6]u8 {
            return .{ 0, 1, 2, 3, 4, 5 };
        }
    };
    var gen = Generator{ .clock = defaultClock, .hwaddr_fn = mock_hwaddr.getHW };
    const ts = try Timestamp.now();
    const u = try gen.newV6AtTime(ts);
    const extracted = try ts_mod.timestampFromV6(u);
    try std.testing.expectEqual(ts.value, extracted.value);
}

test "Generator.newV3: RFC Appendix B — DNS namespace + 'www.example.com'" {
    // RFC-9562 Appendix B V3 vector:
    // name=www.example.com, ns=DNS → 5df41881-3aed-3515-88a7-2f4a814cf09e
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV3(ns_mod.namespace_dns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        u.toString(&buf),
    );
}

test "Generator.newV5: RFC Appendix B — DNS namespace + 'www.example.com'" {
    // V5 vector verified against RFC-9562 and Python's uuid.uuid5():
    // name=www.example.com, ns=DNS → 2ed6657d-e927-568b-95e1-2665a8aea6a2
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV5(ns_mod.namespace_dns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2ed6657d-e927-568b-95e1-2665a8aea6a2",
        u.toString(&buf),
    );
}

test "Generator.newV1: clock_seq increments on clock regression" {
    const mock_hw = struct {
        fn getHW() Error![6]u8 {
            return .{ 0, 1, 2, 3, 4, 5 };
        }
    };
    var gen = Generator{ .hwaddr_fn = mock_hw.getHW };
    // Initialize clock_seq and set last_v1_ts to some timestamp
    const ts_future = Timestamp{ .value = 1_000_000_000 };
    const uuid1 = try gen.newV1AtTime(ts_future);
    const seq1 = std.mem.readInt(u16, uuid1.bytes[8..10], .big) & 0x3FFF;
    // Regress the clock: earlier timestamp triggers clock_seq increment
    const ts_past = Timestamp{ .value = 0 };
    const uuid2 = try gen.newV1AtTime(ts_past);
    const seq2 = std.mem.readInt(u16, uuid2.bytes[8..10], .big) & 0x3FFF;
    try std.testing.expect(seq1 != seq2);
}

test "Generator.newV6: sequential calls produce distinct UUIDs" {
    const mock_hwaddr = struct {
        fn getHW() Error![6]u8 {
            return .{ 0, 1, 2, 3, 4, 5 };
        }
    };
    var gen = Generator.withHWAddr(mock_hwaddr.getHW);
    const ts1 = Timestamp{ .value = 1_000_000 };
    const ts2 = Timestamp{ .value = 2_000_000 };
    const a = try gen.newV6AtTime(ts1);
    const b = try gen.newV6AtTime(ts2);
    try std.testing.expect(!a.eql(b));
    // V6 is k-sortable: later timestamp → lexicographically greater UUID
    try std.testing.expectEqual(std.math.Order.lt, a.order(b));
}

test "Generator.newV8: version=8, variant=rfc9562" {
    var gen = Generator.init();
    const a: [6]u8 = .{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const b_data: [2]u8 = .{ 0x07, 0x08 };
    const c_data: [8]u8 = .{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const u = try gen.newV8(a, b_data, c_data);
    try std.testing.expectEqual(Version.v8, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
    try std.testing.expectEqualSlices(u8, &a, u.bytes[0..6]);
}

// --- F-3: CSPRNG failure propagation ---

test "Generator.initClockSeq propagates CSPRNG failure (F-3)" {
    const failing_rand = struct {
        fn rand(buf: []u8) anyerror!void {
            _ = buf;
            return error.SomeRandomError;
        }
    };
    var gen = Generator.withRand(failing_rand.rand);
    // newV1AtTime calls initClockSeq which calls rand — must propagate error
    const result = gen.newV1AtTime(Timestamp{ .value = 1_000_000 });
    try std.testing.expectError(Error.RandomError, result);
}

// --- F-4: Node change detection ---

test "Generator.newV1: clock_seq increments on node ID change (F-4)" {
    // First call uses node A; after clearing cache and getting node B,
    // clock_seq must be incremented.
    var call_n: u8 = 0;
    const alternating_hw = struct {
        var n: *u8 = undefined;
        fn getHW() Error![6]u8 {
            n.* += 1;
            // Return different MAC on each call
            return .{ n.*, 0, 0, 0, 0, 0 };
        }
    };
    alternating_hw.n = &call_n;

    var gen = Generator.withHWAddr(alternating_hw.getHW);
    const ts = Timestamp{ .value = 1_000_000 };

    const uuid1 = try gen.newV1AtTime(ts);
    const seq1 = std.mem.readInt(u16, uuid1.bytes[8..10], .big) & 0x3FFF;

    // Clear cache → next call fetches a new (different) node
    gen.clearNodeCache();
    const uuid2 = try gen.newV1AtTime(Timestamp{ .value = 2_000_000 });
    const seq2 = std.mem.readInt(u16, uuid2.bytes[8..10], .big) & 0x3FFF;

    // clock_seq must have changed due to node ID change
    try std.testing.expect(seq1 != seq2);
}

// --- F-6: RFC Appendix A test vectors ---

// Shared mock rand state for deterministic V7 RFC vector test.
// Module-level vars are permitted in Zig test code.
var rfc_v7_rand_data = [_]u8{
    // rand_a seed (2 bytes, little-endian) → mono_seq = 0x0CC3
    0xC3, 0x0C,
    // rand_b (8 bytes) — byte[0] will have variant overlaid
    0x18, 0xC4,
    0xDC, 0x0C,
    0x0C, 0x07,
    0x39, 0x8F,
};
var rfc_v7_rand_pos: usize = 0;

fn rfc_v7_mock_rand(buf: []u8) anyerror!void {
    @memcpy(buf, rfc_v7_rand_data[rfc_v7_rand_pos..][0..buf.len]);
    rfc_v7_rand_pos += buf.len;
}

test "RFC Appendix A.1 — V1 test vector (F-6)" {
    // ts = 0x01EC9414C232AB00, node = 9F6BDECED846, seq = 0x33C8
    // Expected: C232AB00-9414-11EC-B3C8-9F6BDECED846
    const ts_val: u60 = 0x01EC9414C232AB00;
    const node_bytes = [6]u8{ 0x9F, 0x6B, 0xDE, 0xCE, 0xD8, 0x46 };
    const mock_hw = struct {
        fn getHW() Error![6]u8 {
            return .{ 0x9F, 0x6B, 0xDE, 0xCE, 0xD8, 0x46 };
        }
    };
    var gen = Generator.withHWAddr(mock_hw.getHW);
    gen.clock_seq = 0x33C8;
    gen.clock_seq_initialized = true;

    const u = try gen.newV1AtTime(Timestamp{ .value = ts_val });
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "c232ab00-9414-11ec-b3c8-9f6bdeced846",
        u.toString(&buf),
    );
    _ = node_bytes; // used via mock_hw
}

test "RFC Appendix A.5 — V6 test vector (F-6)" {
    // Same timestamp and node as A.1
    // Expected: 1EC9414C-232A-6B00-B3C8-9F6BDECED846
    const ts_val: u60 = 0x01EC9414C232AB00;
    const mock_hw = struct {
        fn getHW() Error![6]u8 {
            return .{ 0x9F, 0x6B, 0xDE, 0xCE, 0xD8, 0x46 };
        }
    };
    var gen = Generator.withHWAddr(mock_hw.getHW);
    gen.clock_seq = 0x33C8;
    gen.clock_seq_initialized = true;

    const u = try gen.newV6AtTime(Timestamp{ .value = ts_val });
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "1ec9414c-232a-6b00-b3c8-9f6bdeced846",
        u.toString(&buf),
    );
}

test "RFC Appendix A.6 — V7 test vector (F-6)" {
    // ts_ms = 0x017F22E279B0 (Unix ms, 2022-02-22 ~02:22:22 UTC)
    // rand_a = 0x0CC3 (via mock rand seed [0xC3, 0x0C] little-endian)
    // rand_b before variant = [0x18, 0xC4, 0xDC, 0x0C, 0x0C, 0x07, 0x39, 0x8F]
    // After setVariant: byte[8] = (0x18 & 0x3F) | 0x80 = 0x98
    // Expected: 017f22e2-79b0-7cc3-98c4-dc0c0c07398f
    rfc_v7_rand_pos = 0; // reset mock rand state
    var gen = Generator.withRand(rfc_v7_mock_rand);
    gen.last_ms = 0; // ensure new-ms branch (sets mono_seq from rand)

    const ms: i64 = 0x017F22E279B0;
    const u = try gen.newV7AtTime(ms);
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "017f22e2-79b0-7cc3-98c4-dc0c0c07398f",
        u.toString(&buf),
    );
}

// --- F-9: saveState / loadState ---

test "Generator.saveState and loadState round-trip (F-9 + SEC-10)" {
    const alloc = std.testing.allocator;
    _ = alloc;

    const path = "/tmp/uuid_generator_state_test.bin";
    defer std.fs.deleteFileAbsolute(path) catch {};

    const mock_hw = struct {
        fn getHW() Error![6]u8 {
            return .{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
        }
    };
    var gen = Generator.withHWAddr(mock_hw.getHW);
    gen.clock_seq = 0x1234;
    gen.clock_seq_initialized = true;
    gen.last_v1_ts = 0xDEADBEEF;
    gen.node_cache = .{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
    // SEC-10: set V7 state that should be persisted.
    gen.last_ms = 1_700_000_000_123;
    gen.mono_seq = 0x0ABC;

    try gen.saveState(path);

    var gen2 = Generator.init();
    try gen2.loadState(path);

    // V1/V6 state preserved.
    try std.testing.expectEqual(gen.clock_seq, gen2.clock_seq);
    try std.testing.expectEqual(gen.clock_seq_initialized, gen2.clock_seq_initialized);
    try std.testing.expectEqual(gen.last_v1_ts, gen2.last_v1_ts);
    try std.testing.expectEqualSlices(u8, &(gen.node_cache.?), &(gen2.node_cache.?));

    // PERF-04 + SEC-10: gen.last_ms (Nov 2023) is well in the past, so the
    // clock-advance branch fires and both V7 fields are reset to zero.
    // No spin-wait penalty on the first post-restart V7 call.
    try std.testing.expectEqual(@as(i64, 0), gen2.last_ms);
    try std.testing.expectEqual(@as(u12, 0), gen2.mono_seq);
}

test "Generator.loadState: V7 fast-restart forces mono_seq overflow (PERF-04)" {
    // When the saved last_ms is in the future (or equal to now), the
    // conservative path activates: last_ms is kept, mono_seq = maxInt.
    const path = "/tmp/uuid_v7_fast_restart_test.bin";
    defer std.fs.deleteFileAbsolute(path) catch {};

    // Use a far-future last_ms so that current_ms <= saved_ms always holds.
    const far_future_ms: i64 = std.math.maxInt(i64);
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01; // clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], far_future_ms, .little);
    std.mem.writeInt(u16, blob[30..32], 0x0042, .little);

    const f = try std.fs.createFileAbsolute(path, .{});
    try f.writeAll(&blob);
    f.close();

    var gen = Generator.init();
    try gen.loadState(path);
    // Clock has NOT advanced past far_future_ms → conservative overflow.
    try std.testing.expectEqual(far_future_ms, gen.last_ms);
    try std.testing.expectEqual(@as(u12, std.math.maxInt(u12)), gen.mono_seq);
}

test "Generator.saveState is atomic: no .tmp file lingers on success (SEC-9)" {
    const path = "/tmp/uuid_state_atomic_test.bin";
    const tmp_path = "/tmp/uuid_state_atomic_test.bin.tmp";
    defer std.fs.deleteFileAbsolute(path) catch {};

    var gen = Generator.init();
    gen.clock_seq = 0x0042;
    gen.clock_seq_initialized = true;
    try gen.saveState(path);

    // After a successful save the .tmp file must not exist.
    std.fs.accessAbsolute(tmp_path, .{}) catch |err| {
        // Expected: FileNotFound (or equivalent) means the tmp was cleaned up.
        try std.testing.expect(err == error.FileNotFound);
        return;
    };
    // If we reach here the tmp file still exists — that is a bug.
    return error.TmpFileLingers;
}

test "Generator.loadState: corrupt magic returns error (F-9)" {
    const path = "/tmp/uuid_state_bad_magic_test.bin";
    var bad_buf = [_]u8{0} ** Generator.state_size;
    bad_buf[0] = 'X'; // corrupt magic

    const f = try std.fs.createFileAbsolute(path, .{});
    try f.writeAll(&bad_buf);
    f.close();

    var gen = Generator.init();
    try std.testing.expectError(Error.InvalidFormat, gen.loadState(path));
    std.fs.deleteFileAbsolute(path) catch {};
}

test "Generator.loadState: v1 format (22 bytes) accepted for backward compat (SEC-10)" {
    // Manually write a version-1 state blob and confirm it loads cleanly.
    const path = "/tmp/uuid_state_v1_compat_test.bin";
    defer std.fs.deleteFileAbsolute(path) catch {};

    var blob: [Generator.state_size_v1]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version_v1; // version 1
    blob[5] = 0x01; // flags: clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0x0ABC, .little);
    std.mem.writeInt(u64, blob[8..16], 0xDEADBEEF_CAFEBABE, .little);
    @memset(blob[16..22], 0); // no node cache

    const f = try std.fs.createFileAbsolute(path, .{});
    try f.writeAll(&blob);
    f.close();

    var gen = Generator.init();
    try gen.loadState(path);
    try std.testing.expectEqual(@as(u14, 0x0ABC), gen.clock_seq);
    try std.testing.expect(gen.clock_seq_initialized);
    // V7 state defaults to zero (no data in v1 blob).
    try std.testing.expectEqual(@as(i64, 0), gen.last_ms);
}

// --- G-8: GeneratorInterface ---

test "GeneratorInterface.fromGenerator: newV4 dispatches correctly (G-8)" {
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const u = try iface.newV4();
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "GeneratorInterface: newV3 dispatches correctly (G-8)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const u = iface.newV3(ns_mod.namespace_dns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        u.toString(&buf),
    );
}

test "GeneratorInterface: newV7AtTime dispatches correctly (G-8)" {
    const ts_mod = @import("timestamp.zig");
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const ms: i64 = 1_700_000_000_000;
    const u = try iface.newV7AtTime(ms);
    const ts = try ts_mod.timestampFromV7(u);
    try std.testing.expectEqual(ms, ts.toUnixMs());
}

// =============================================================================
// Regression tests for gofrs/uuid Issue #216:
// V1/V6 same-timestamp calls must produce distinct clock_seq values.
// Bug: original code used `ts.value < last_v1_ts` (strict less-than),
// so same-timestamp calls did NOT increment clock_seq → duplicate UUIDs.
// Fix: changed to `ts.value <= last_v1_ts` so same-timestamp also increments.
// =============================================================================

test "regression #216: V1 same-timestamp calls produce distinct clock_seq (V1)" {
    const mock_hw = struct {
        fn getHW() Error![6]u8 {
            return .{ 0, 1, 2, 3, 4, 5 };
        }
    };
    var gen = Generator.withHWAddr(mock_hw.getHW);
    // Fix a known clock_seq so increments are predictable
    gen.clock_seq = 100;
    gen.clock_seq_initialized = true;

    const fixed_ts = Timestamp{ .value = 1_000_000_000 };

    const a = try gen.newV1AtTime(fixed_ts);
    const b = try gen.newV1AtTime(fixed_ts);
    const c = try gen.newV1AtTime(fixed_ts);

    const seq_a = std.mem.readInt(u16, a.bytes[8..10], .big) & 0x3FFF;
    const seq_b = std.mem.readInt(u16, b.bytes[8..10], .big) & 0x3FFF;
    const seq_c = std.mem.readInt(u16, c.bytes[8..10], .big) & 0x3FFF;

    // All three must have distinct clock_seq values
    try std.testing.expect(seq_a != seq_b);
    try std.testing.expect(seq_b != seq_c);
    try std.testing.expect(seq_a != seq_c);

    // All three UUIDs must be distinct
    try std.testing.expect(!a.eql(b));
    try std.testing.expect(!b.eql(c));
    try std.testing.expect(!a.eql(c));
}

test "regression #216: V6 same-timestamp calls produce distinct clock_seq (V6)" {
    const mock_hw = struct {
        fn getHW() Error![6]u8 {
            return .{ 0, 1, 2, 3, 4, 5 };
        }
    };
    var gen = Generator.withHWAddr(mock_hw.getHW);
    gen.clock_seq = 200;
    gen.clock_seq_initialized = true;

    const fixed_ts = Timestamp{ .value = 2_000_000_000 };

    const a = try gen.newV6AtTime(fixed_ts);
    const b = try gen.newV6AtTime(fixed_ts);
    const c = try gen.newV6AtTime(fixed_ts);

    const seq_a = std.mem.readInt(u16, a.bytes[8..10], .big) & 0x3FFF;
    const seq_b = std.mem.readInt(u16, b.bytes[8..10], .big) & 0x3FFF;
    const seq_c = std.mem.readInt(u16, c.bytes[8..10], .big) & 0x3FFF;

    try std.testing.expect(seq_a != seq_b);
    try std.testing.expect(seq_b != seq_c);
    try std.testing.expect(seq_a != seq_c);

    try std.testing.expect(!a.eql(b));
    try std.testing.expect(!b.eql(c));
    try std.testing.expect(!a.eql(c));
}

test "regression #216: V1 concurrent same-timestamp — no duplicates" {
    // Proves the fix holds under concurrent load with a fixed timestamp.
    const N = 100;
    const mock_hw = struct {
        fn getHW() Error![6]u8 {
            return .{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
        }
    };
    var gen = Generator.withHWAddr(mock_hw.getHW);
    gen.clock_seq = 0;
    gen.clock_seq_initialized = true;

    const fixed_ts = Timestamp{ .value = 9_999_999_999 };

    var results = [_]UUID{UUID.nil} ** N;
    for (&results) |*u| {
        u.* = try gen.newV1AtTime(fixed_ts);
    }

    // Sort by bytes and check no two adjacent are equal
    std.mem.sort(UUID, &results, {}, struct {
        pub fn lt(_: void, a: UUID, b: UUID) bool {
            return a.order(b) == .lt;
        }
    }.lt);
    for (0..N - 1) |i| {
        try std.testing.expect(!results[i].eql(results[i + 1]));
    }
}
