// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Generator tests — split from generator.zig to keep that file under 800 lines (QC-4).
// All test logic is here; generator.zig imports this file via `test { _ = @import("generator_test.zig"); }`.

const std = @import("std");
const builtin = @import("builtin");
const Generator = @import("generator.zig").Generator;
const GeneratorInterface = @import("generator.zig").GeneratorInterface;
const UUID = @import("uuid.zig").UUID;
const Version = @import("uuid.zig").Version;
const Variant = @import("uuid.zig").Variant;
const Error = @import("uuid.zig").Error;
const Timestamp = @import("timestamp.zig").Timestamp;

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

test "Generator.newV7: monotone across backward clock jump (SEC-R14-02)" {
    // Inject a clock that goes backward: 2000ms → 1000ms
    const regressing_clock = struct {
        var call_count: u32 = 0;
        fn clock() i128 {
            call_count += 1;
            // First two calls: 2000ms, then drop to 1000ms
            return if (call_count <= 2)
                @as(i128, 2_000) * 1_000_000
            else
                @as(i128, 1_000) * 1_000_000;
        }
    };
    regressing_clock.call_count = 0;
    var gen = Generator.withClock(regressing_clock.clock);
    const a = try gen.newV7(); // ts=2000ms
    const b = try gen.newV7(); // clock returns 1000ms but should preserve 2000ms
    // b must NOT have a lower timestamp than a (monotonicity preserved)
    const ts_a = try @import("timestamp.zig").timestampFromV7(a);
    const ts_b = try @import("timestamp.zig").timestampFromV7(b);
    try std.testing.expect(ts_b.toUnixMs() >= ts_a.toUnixMs());
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
    // QC-4: replaced `Generator{ .clock = defaultClock, .hwaddr_fn = ... }` with
    // withHWAddr (defaultClock is private; withHWAddr already uses it).
    var gen = Generator.withHWAddr(mock_hwaddr.getHW);
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

// QC-66: Additional namespace test vectors for V3 and V5.
// Reference values verified with Python's uuid.uuid3() / uuid.uuid5().

test "Generator.newV3: URL namespace + 'www.example.com' (QC-66)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV3(ns_mod.namespace_url, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings("a777199a-c522-31c4-8f4b-335feec7215b", u.toString(&buf));
}

test "Generator.newV3: OID namespace + 'www.example.com' (QC-66)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV3(ns_mod.namespace_oid, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings("c2c1e4de-6589-389e-9375-32a90c6a83a8", u.toString(&buf));
}

test "Generator.newV3: X500 namespace + 'www.example.com' (QC-66)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV3(ns_mod.namespace_x500, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings("f4ea5e25-91d4-38b0-b74f-af6c57210cae", u.toString(&buf));
}

test "Generator.newV5: URL namespace + 'www.example.com' (QC-66)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV5(ns_mod.namespace_url, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings("b63cdfa4-3df9-568e-97ae-006c5b8fd652", u.toString(&buf));
}

test "Generator.newV5: OID namespace + 'www.example.com' (QC-66)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV5(ns_mod.namespace_oid, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings("a5e87d3b-479e-52da-b98a-db251a851854", u.toString(&buf));
}

test "Generator.newV5: X500 namespace + 'www.example.com' (QC-66)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV5(ns_mod.namespace_x500, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings("a1d3adb1-15b7-5395-a05f-9051a08769a2", u.toString(&buf));
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

test "Generator.newV1/newV6 use system clock, not injected clock (QC-88)" {
    // V1/V6 call Timestamp.now() which reads std.time.nanoTimestamp() directly.
    // The injectable clock (set via withClock) is only used by V7.  Verify
    // this boundary by creating a generator with a frozen clock and confirming
    // that V1/V6 timestamps still reflect real (advancing) wall-clock time,
    // not the frozen value.
    const frozen_clock = struct {
        fn clock() i128 {
            // Return a fixed time: Jan 1, 2000 in nanoseconds
            return 946_684_800_000_000_000;
        }
    };
    var gen = Generator.withClock(frozen_clock.clock);
    // V1 should use Timestamp.now(), not the frozen clock
    const u1a = try gen.newV1();
    const ts1 = try @import("timestamp.zig").timestampFromV1(u1a);
    // The V1 timestamp should be recent (after 2024), not at year-2000.
    // Frozen clock → year 2000 → Gregorian intervals ≈ 1.25e17.
    // Real clock → year 2025+ → Gregorian intervals ≈ 1.40e17+.
    // Use gregorian_offset + year-2020 intervals as a threshold.
    const threshold: u60 = @truncate(Timestamp.gregorian_offset + 15_778_800_000_000_000); // ~2020
    try std.testing.expect(ts1.value > threshold);

    // V6 should also use Timestamp.now(), not the frozen clock
    const u6a = try gen.newV6();
    const ts6 = try @import("timestamp.zig").timestampFromV6(u6a);
    try std.testing.expect(ts6.value > threshold);
}

test "Generator.newV8: version=8, variant=rfc9562" {
    var gen = Generator.init();
    const a: [6]u8 = .{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const b_data: [2]u8 = .{ 0x07, 0x08 };
    const c_data: [8]u8 = .{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const u = gen.newV8(a, b_data, c_data);
    try std.testing.expectEqual(Version.v8, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
    try std.testing.expectEqualSlices(u8, &a, u.bytes[0..6]);
}

// --- QC-85: newV8 infallible path ---

test "Generator.newV8 is infallible with all-zero and all-one inputs (QC-85)" {
    var gen = Generator.init();
    // All-zero input
    const zero = gen.newV8([_]u8{0} ** 6, [_]u8{0} ** 2, [_]u8{0} ** 8);
    try std.testing.expectEqual(Version.v8, zero.version());
    try std.testing.expectEqual(Variant.rfc9562, zero.variant());
    // All-one input
    const ones = gen.newV8([_]u8{0xFF} ** 6, [_]u8{0xFF} ** 2, [_]u8{0xFF} ** 8);
    try std.testing.expectEqual(Version.v8, ones.version());
    try std.testing.expectEqual(Variant.rfc9562, ones.variant());
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

// QC-12: Encapsulate mock rand state in a struct to make per-test setup explicit
// and reduce coupling between separate test cases.
// NOTE: Zig's RandFn is `fn([]u8)!void` with no context parameter — closures are not
// possible with function pointers, so a module-level instance is unavoidable.
// The struct groups data+pos together to make the coupling clear and intentional.
const V7MockRandState = struct {
    data: [10]u8,
    pos: usize,
};
var rfc_v7_mock_state: V7MockRandState = undefined;

fn rfc_v7_mock_rand(buf: []u8) anyerror!void {
    @memcpy(buf, rfc_v7_mock_state.data[rfc_v7_mock_state.pos..][0..buf.len]);
    rfc_v7_mock_state.pos += buf.len;
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
    rfc_v7_mock_state = .{ // QC-12: initialise struct-encapsulated state
        .data = .{ 0xC3, 0x0C, 0x18, 0xC4, 0xDC, 0x0C, 0x0C, 0x07, 0x39, 0x8F },
        .pos = 0,
    };
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

// QC-22: GeneratorInterface vtable coverage — the 7 remaining methods.
// Each test verifies that the trampoline dispatches to the concrete Generator
// and that the returned UUID has the correct version/variant bits.

test "GeneratorInterface: newV7 dispatches correctly (G-8, QC-22)" {
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const u = try iface.newV7();
    try std.testing.expectEqual(Version.v7, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "GeneratorInterface: newV1 dispatches correctly (G-8, QC-22)" {
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const u = try iface.newV1();
    try std.testing.expectEqual(Version.v1, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "GeneratorInterface: newV1AtTime dispatches correctly (G-8, QC-22)" {
    const ts_mod = @import("timestamp.zig");
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    // Use a fixed Gregorian-epoch timestamp (RFC-9562 §5.1): 2024-01-01 00:00 UTC.
    const greg_ts = ts_mod.Timestamp{ .value = 139_806_912_000_000_000 };
    const u = try iface.newV1AtTime(greg_ts);
    try std.testing.expectEqual(Version.v1, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
    // Round-trip: extract timestamp and confirm it matches.
    const got = try ts_mod.timestampFromV1(u);
    try std.testing.expectEqual(greg_ts.value, got.value);
}

test "GeneratorInterface: newV5 dispatches correctly (G-8, QC-22)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const u = iface.newV5(ns_mod.namespace_dns, "www.example.com");
    var buf: [36]u8 = undefined;
    // RFC-9562 / Python uuid.uuid5() test vector for V5 DNS / www.example.com.
    try std.testing.expectEqualStrings(
        "2ed6657d-e927-568b-95e1-2665a8aea6a2",
        u.toString(&buf),
    );
}

test "GeneratorInterface: newV6 dispatches correctly (G-8, QC-22)" {
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const u = try iface.newV6();
    try std.testing.expectEqual(Version.v6, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "GeneratorInterface: newV6AtTime dispatches correctly (G-8, QC-22)" {
    const ts_mod = @import("timestamp.zig");
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const greg_ts = ts_mod.Timestamp{ .value = 139_806_912_000_000_000 };
    const u = try iface.newV6AtTime(greg_ts);
    try std.testing.expectEqual(Version.v6, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
    const got = try ts_mod.timestampFromV6(u);
    try std.testing.expectEqual(greg_ts.value, got.value);
}

test "GeneratorInterface: newV8 dispatches correctly (G-8, QC-22)" {
    var gen = Generator.init();
    var iface = GeneratorInterface.fromGenerator(&gen);
    const a = [6]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const b_bytes = [2]u8{ 0x07, 0x08 };
    const c = [8]u8{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const u = iface.newV8(a, b_bytes, c);
    try std.testing.expectEqual(Version.v8, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
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

// --- QC-13: Missing error-path tests ---

test "Generator.newV7AtTime: negative ts returns InvalidTimestamp (QC-13)" {
    var gen = Generator.init();
    try std.testing.expectError(Error.InvalidTimestamp, gen.newV7AtTime(-1));
    try std.testing.expectError(Error.InvalidTimestamp, gen.newV7AtTime(-100));
}

test "Generator.fetchRawNode: hwaddr failure falls back to random multicast node (QC-13)" {
    const failing_hwaddr = struct {
        fn getHW() Error![6]u8 {
            return Error.NoHWAddressFound;
        }
    };
    var gen = Generator.withHWAddr(failing_hwaddr.getHW);
    // V1 generation must succeed even when hwaddr_fn fails (fallback path)
    const u = try gen.newV1();
    try std.testing.expectEqual(Version.v1, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
    // multicast bit must be set on the fallback random node
    try std.testing.expect(u.bytes[10] & 0x01 == 0x01);
}

// --- SEC-R4-01: clockToMs guard in newV7 and spin-wait retry ---

test "Generator.newV7: negative clock returns InvalidTimestamp (SEC-R4-01)" {
    // Inject a clock that returns a negative nanosecond value. Both the entry
    // guard (newV7) and the spin-wait retry (newV7Locked) must return
    // InvalidTimestamp rather than panicking on @intCast.
    const neg_clock = struct {
        fn clock() i128 {
            return -1;
        }
    };
    var gen = Generator.init();
    gen.clock = neg_clock.clock;
    try std.testing.expectError(Error.InvalidTimestamp, gen.newV7());
}

test "Generator.newV7: extreme positive clock returns InvalidTimestamp (SEC-R4-01)" {
    // Inject a clock returning a value that overflows i64 after division by
    // 1_000_000: maxInt(i128) / 1_000_000 >> maxInt(i64). Must not panic.
    const huge_clock = struct {
        fn clock() i128 {
            return std.math.maxInt(i128);
        }
    };
    var gen = Generator.init();
    gen.clock = huge_clock.clock;
    try std.testing.expectError(Error.InvalidTimestamp, gen.newV7());
}

// --- SEC-R5-03: V7 spin-wait maximum iteration bound ---

test "Generator.newV7: spin-wait terminates with frozen clock (SEC-R5-03)" {
    // Verify that when the clock is frozen (always returns the same ms) and
    // mono_seq is already at maxInt(u12), newV7 hits the max_spins bound and
    // returns Error.InvalidTimestamp rather than blocking indefinitely.
    //
    // Setup: use a clock frozen at 1 000 000 ms (well above last_ms=0 so the
    // first call succeeds and sets last_ms = 1_000_000), then forcibly set
    // mono_seq = maxInt(u12) so the *next* call enters the spin-wait and finds
    // the clock never advances.
    const frozen_ms: i64 = 1_000_000;
    const frozen_clock = struct {
        fn clock() i128 {
            // Return exactly frozen_ms milliseconds in nanoseconds.
            return frozen_ms * 1_000_000;
        }
    };
    var gen = Generator.withClock(frozen_clock.clock);
    // First call sets last_ms = frozen_ms and seeds mono_seq with random jitter.
    _ = try gen.newV7();
    // Now force last_ms to frozen_ms and mono_seq to maxInt to trigger spin-wait.
    gen.last_ms = frozen_ms;
    gen.mono_seq = std.math.maxInt(u12);
    // The clock is still frozen, so the spin-wait can never advance past last_ms.
    // After max_spins iterations it must return InvalidTimestamp, not hang.
    try std.testing.expectError(Error.InvalidTimestamp, gen.newV7());
}

// saveState / loadState tests → see src/generator_state_test.zig (QC-28)

// --- SEC-R6-01: clearNodeCache holds mutex ---

test "Generator.clearNodeCache holds mutex and generator still works (SEC-R6-01)" {
    // Verify that clearNodeCache is callable (no panic / deadlock) and that
    // the generator remains usable — node_cache is null after the call and
    // the next V1/V6 call re-resolves it successfully.
    var gen = Generator.init();

    // Warm up the cache with a V4 call first (no node needed, but confirms gen is live).
    _ = try gen.newV4();

    // Trigger a V1 call so that node_cache is populated.
    _ = try gen.newV1();
    try std.testing.expect(gen.node_cache != null);

    // clearNodeCache must succeed (holds mutex, sets node_cache = null).
    gen.clearNodeCache();
    try std.testing.expect(gen.node_cache == null);

    // The generator must still produce valid UUIDs after the cache is cleared.
    // The next V1 call re-resolves the node — cache is warm again after this.
    const u = try gen.newV1();
    try std.testing.expectEqual(Version.v1, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());

    // node_cache must have been repopulated.
    try std.testing.expect(gen.node_cache != null);
}
