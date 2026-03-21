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
