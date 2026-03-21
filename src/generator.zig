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

pub const Generator = struct {
    clock: ClockFn = defaultClock,
    rand: RandFn = defaultRand,
    hwaddr_fn: HWAddrFn = hwaddr.get,

    // V7 monotonicity state (all protected by mutex)
    mutex: std.Thread.Mutex = .{},
    last_ms: i64 = 0,
    mono_seq: u12 = 0,

    // V1/V6 state
    clock_seq: u14 = 0,
    clock_seq_initialized: bool = false,
    last_v1_ts: u60 = 0,

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

    pub fn withHWAddr(f: HWAddrFn) Generator {
        var g = Generator.init();
        g.hwaddr_fn = f;
        return g;
    }

    pub fn newV4(self: *Generator) Error!UUID {
        var u: UUID = undefined;
        self.rand(&u.bytes) catch return Error.RandomError;
        u.setVersion(.v4);
        u.setVariant(.rfc9562);
        return u;
    }

    pub fn newV7(self: *Generator) Error!UUID {
        const now_ms: i64 = @intCast(@divTrunc(self.clock(), 1_000_000));
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
                // Overflow: yield briefly then spin until the clock advances.
                // A brief sleep avoids burning 100% CPU on a tight spin —
                // the spec calls this a "spin-wait strategy" (brief yield is acceptable).
                while (ms == self.last_ms) {
                    self.mutex.unlock();
                    std.Thread.sleep(100_000); // 0.1ms yield — avoids busy-spin
                    self.mutex.lock();
                    ms = @intCast(@divTrunc(self.clock(), 1_000_000));
                }
                // ms has advanced — fall through to random reset below
            } else {
                self.mono_seq += 1;
                seq = self.mono_seq;
                // seq is set; skip the new-ms branch
                // (use a goto-equivalent: we return directly after building the UUID)
            }
        }

        if (ms != self.last_ms) {
            // New ms (either first call, or after spin overflow above):
            // reset mono_seq to a random 12-bit value for maximum entropy.
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

    fn initClockSeq(self: *Generator) void {
        if (self.clock_seq_initialized) return;
        var buf: [2]u8 = undefined;
        self.rand(&buf) catch {
            buf = .{ 0x12, 0x34 }; // fallback
        };
        self.clock_seq = @truncate(std.mem.readInt(u16, &buf, .little) & 0x3FFF);
        self.clock_seq_initialized = true;
    }

    fn getNode(self: *Generator) Error![6]u8 {
        if (self.hwaddr_fn()) |mac| return mac else |_| {
            // Random node ID with multicast bit set (RFC-9562 §6.10)
            var node: [6]u8 = undefined;
            self.rand(&node) catch return Error.RandomError;
            node[0] |= 0x01; // set multicast bit
            return node;
        }
    }

    pub fn newV1(self: *Generator) Error!UUID {
        const ts = Timestamp.now();
        return self.newV1AtTime(ts);
    }

    pub fn newV1AtTime(self: *Generator, ts: Timestamp) Error!UUID {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.initClockSeq();
        // Increment clock_seq on clock regression (RFC-9562 §6.1)
        if (ts.value < self.last_v1_ts) {
            self.clock_seq = (self.clock_seq +% 1) & 0x3FFF;
        }
        self.last_v1_ts = ts.value;
        const node = try self.getNode();
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
        const ts = Timestamp.now();
        return self.newV6AtTime(ts);
    }

    pub fn newV6AtTime(self: *Generator, ts: Timestamp) Error!UUID {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.initClockSeq();
        if (ts.value < self.last_v1_ts) {
            self.clock_seq = (self.clock_seq +% 1) & 0x3FFF;
        }
        self.last_v1_ts = ts.value;
        const node = try self.getNode();
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
};

pub var default_generator: Generator = Generator.init();

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

test "Generator.newV7AtTime: timestamp round-trips" {
    const ts_mod = @import("timestamp.zig");
    var gen = Generator.init();
    const ms: i64 = 1_700_000_000_000; // some Unix ms
    const u = try gen.newV7AtTime(ms);
    const extracted = try ts_mod.timestampFromV7(u);
    try std.testing.expectEqual(ms, extracted);
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
    // bytes should be zero except version/variant bits
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.newV1: version=1, variant=rfc9562" {
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
    const ts = Timestamp.now();
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
    // clock_seq must change (increment mod 2^14) on regression
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
    // custom_a: bytes 0-5 should match a
    try std.testing.expectEqualSlices(u8, &a, u.bytes[0..6]);
}
