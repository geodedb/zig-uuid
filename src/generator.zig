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
        const ns = self.clock();
        if (ns < 0) return Error.InvalidTimestamp;
        const now_ms: i64 = @intCast(@divTrunc(ns, 1_000_000));
        return self.newV7AtTime(now_ms);
    }

    pub fn newV7AtTime(self: *Generator, ts: i64) Error!UUID {
        if (ts < 0) return Error.InvalidFormat;
        self.mutex.lock();
        defer self.mutex.unlock();

        var ms = ts;
        // seq is always set before use in every branch below — declared here for scope.
        var seq: u12 = 0;

        if (ms == self.last_ms) {
            // Same ms: increment sequence counter
            if (self.mono_seq == std.math.maxInt(u12)) {
                // Overflow: spin-wait until the clock advances.
                while (ms == self.last_ms) {
                    self.mutex.unlock();
                    std.Thread.sleep(100_000); // 0.1ms yield
                    self.mutex.lock();
                    ms = @intCast(@divTrunc(self.clock(), 1_000_000));
                }
                // ms has advanced — fall through to random reset below
            } else {
                self.mono_seq += 1;
                seq = self.mono_seq;
            }
        }

        if (ms != self.last_ms) {
            // New ms: reset mono_seq to a random 12-bit value for entropy.
            var rand_seq: [2]u8 = undefined;
            self.rand(&rand_seq) catch return Error.RandomError;
            self.mono_seq = @truncate(std.mem.readInt(u16, &rand_seq, .little) & 0x0FFF);
            seq = self.mono_seq;
            self.last_ms = ms;
        }

        var u: UUID = undefined;
        // unix_ts_ms: 48 bits big-endian in bytes 0-5
        const ms_u: u64 = @intCast(ms);
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(ms_u >> 16), .big);
        std.mem.writeInt(u16, u.bytes[4..6], @truncate(ms_u), .big);
        // rand_a: 12-bit monotonic counter in low 12 bits of bytes 6-7
        std.mem.writeInt(u16, u.bytes[6..8], seq, .big);
        // rand_b: 62 bits random in bytes 8-15
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
    fn getNode(self: *Generator) Error![6]u8 {
        if (self.node_cache) |n| return n;

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

        self.node_cache = node;
        return node;
    }

    pub fn newV1(self: *Generator) Error!UUID {
        const ts = try Timestamp.now();
        return self.newV1AtTime(ts);
    }

    pub fn newV1AtTime(self: *Generator, ts: Timestamp) Error!UUID {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.initClockSeq(); // F-3: propagate CSPRNG failure
        // Increment clock_seq on clock regression (RFC-9562 §6.1)
        if (ts.value < self.last_v1_ts) {
            self.clock_seq = (self.clock_seq +% 1) & 0x3FFF;
        }
        self.last_v1_ts = ts.value;
        // F-4: detect node ID change and increment clock_seq
        const old_node = self.last_node;
        const node = try self.getNode();
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
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.initClockSeq(); // F-3
        if (ts.value < self.last_v1_ts) {
            self.clock_seq = (self.clock_seq +% 1) & 0x3FFF;
        }
        self.last_v1_ts = ts.value;
        // F-4: detect node ID change
        const old_node = self.last_node;
        const node = try self.getNode();
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

    /// Binary state file format (22 bytes):
    /// [0..4]  magic "UUID"
    /// [4]     format version = 1
    /// [5]     flags: bit0=clock_seq_initialized, bit1=has_node_cache
    /// [6..8]  clock_seq as u16 little-endian
    /// [8..16] last_v1_ts as u64 little-endian
    /// [16..22] node_cache (6 bytes; only meaningful when flags bit1 set)
    pub const state_magic: [4]u8 = "UUID".*;
    pub const state_format_version: u8 = 1;
    pub const state_size: usize = 22;

    /// Save V1/V6 generator state to stable storage (F-9).
    ///
    /// Writes a 22-byte binary blob so clock_seq and last timestamp survive a
    /// process restart.  If the state file already exists it is overwritten.
    /// Errors from file operations are returned to the caller.
    pub fn saveState(self: *Generator, path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var buf: [state_size]u8 = undefined;
        @memcpy(buf[0..4], &state_magic);
        buf[4] = state_format_version;

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

        const f = try std.fs.createFileAbsolute(path, .{});
        defer f.close();
        try f.writeAll(&buf);
    }

    /// Load V1/V6 generator state from stable storage (F-9).
    ///
    /// Restores clock_seq, last_v1_ts, and node_cache from a file previously
    /// written by saveState().  Returns error.InvalidFormat if the file is
    /// corrupted or written by an incompatible version.
    pub fn loadState(self: *Generator, path: []const u8) !void {
        const f = try std.fs.openFileAbsolute(path, .{});
        defer f.close();

        var buf: [state_size]u8 = undefined;
        const n = try f.readAll(&buf);
        if (n != state_size) return Error.InvalidFormat;

        if (!std.mem.eql(u8, buf[0..4], &state_magic)) return Error.InvalidFormat;
        if (buf[4] != state_format_version) return Error.InvalidFormat;

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
    }
};

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

test "Generator.saveState and loadState round-trip (F-9)" {
    const alloc = std.testing.allocator;
    const tmp_dir = std.testing.tmpDir(.{});
    _ = tmp_dir;

    // Use a temp file path
    const path = "/tmp/uuid_generator_state_test.bin";

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

    try gen.saveState(path);

    var gen2 = Generator.init();
    try gen2.loadState(path);

    try std.testing.expectEqual(gen.clock_seq, gen2.clock_seq);
    try std.testing.expectEqual(gen.clock_seq_initialized, gen2.clock_seq_initialized);
    try std.testing.expectEqual(gen.last_v1_ts, gen2.last_v1_ts);
    try std.testing.expectEqualSlices(u8, &(gen.node_cache.?), &(gen2.node_cache.?));

    std.fs.deleteFileAbsolute(path) catch {};
    _ = alloc;
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
