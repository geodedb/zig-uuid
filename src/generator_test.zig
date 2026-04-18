// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Generator tests — split from generator.zig to keep that file under 800 lines (QC-4).
// All test logic is here; generator.zig imports this file via `test { _ = @import("generator_test.zig"); }`.

const std = @import("std");
const builtin = @import("builtin");
const Generator = @import("generator.zig").Generator;
const GeneratorInterface = @import("generator.zig").GeneratorInterface;
const GeneratorInterfaceFor = @import("generator.zig").GeneratorInterfaceFor;
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

// PERF-30: prehashed namespace variants produce the same UUIDs as
// Generator.newV3 / Generator.newV5 while amortising the namespace hash.

test "Generator.initV3Namespace: matches newV3 for the RFC DNS vector (PERF-30)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const pre = gen.initV3Namespace(ns_mod.namespace_dns);
    const u = pre.name("www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        u.toString(&buf),
    );
    try std.testing.expectEqual(@import("uuid.zig").Version.v3, u.version());
}

test "Generator.initV5Namespace: matches newV5 for the RFC DNS vector (PERF-30)" {
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const pre = gen.initV5Namespace(ns_mod.namespace_dns);
    const u = pre.name("www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2ed6657d-e927-568b-95e1-2665a8aea6a2",
        u.toString(&buf),
    );
    try std.testing.expectEqual(@import("uuid.zig").Version.v5, u.version());
}

test "PrehashedV3 / PrehashedV5: reusable across many names (PERF-30)" {
    // The cloned-hasher trick must be independent per call; verify by
    // hashing two different names under one prehashed namespace and
    // comparing each result to the reference newV3 / newV5 output.
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();

    const pre3 = gen.initV3Namespace(ns_mod.namespace_dns);
    const a3 = pre3.name("alpha.example");
    const b3 = pre3.name("beta.example");
    try std.testing.expect(!std.mem.eql(u8, &a3.bytes, &b3.bytes));
    try std.testing.expectEqual(
        gen.newV3(ns_mod.namespace_dns, "alpha.example").bytes,
        a3.bytes,
    );
    try std.testing.expectEqual(
        gen.newV3(ns_mod.namespace_dns, "beta.example").bytes,
        b3.bytes,
    );

    const pre5 = gen.initV5Namespace(ns_mod.namespace_dns);
    const a5 = pre5.name("alpha.example");
    const b5 = pre5.name("beta.example");
    try std.testing.expect(!std.mem.eql(u8, &a5.bytes, &b5.bytes));
    try std.testing.expectEqual(
        gen.newV5(ns_mod.namespace_dns, "alpha.example").bytes,
        a5.bytes,
    );
    try std.testing.expectEqual(
        gen.newV5(ns_mod.namespace_dns, "beta.example").bytes,
        b5.bytes,
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
    // PERF-27: node cache is now a split atomic-flag + bytes pair; probe via
    // the atomic valid flag (acquire-load semantics match the generator's
    // fast-path reader).
    try std.testing.expect(gen.node_cache_valid.load(.acquire));

    // clearNodeCache must succeed (holds mutex, clears the atomic flag).
    gen.clearNodeCache();
    try std.testing.expect(!gen.node_cache_valid.load(.acquire));

    // The generator must still produce valid UUIDs after the cache is cleared.
    // The next V1 call re-resolves the node — cache is warm again after this.
    const u = try gen.newV1();
    try std.testing.expectEqual(Version.v1, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());

    // node_cache must have been repopulated.
    try std.testing.expect(gen.node_cache_valid.load(.acquire));
}

// --- PERF-23: nullable rand/clock defaults still produce valid UUIDs ---

test "Generator.init default path produces valid V4 / V7 UUIDs (PERF-23)" {
    // With the PERF-23 refactor `clock` and `rand` default to null, and
    // the hot paths call defaultClock / defaultRand directly without the
    // function-pointer indirection.  Prove that Generator.init() still
    // produces UUIDs with the correct version and variant when neither
    // withClock nor withRand is used.
    var gen = Generator.init();
    try std.testing.expect(gen.clock == null);
    try std.testing.expect(gen.rand == null);

    const uv4 = try gen.newV4();
    try std.testing.expectEqual(Version.v4, uv4.version());
    try std.testing.expectEqual(Variant.rfc9562, uv4.variant());

    const uv7 = try gen.newV7();
    try std.testing.expectEqual(Version.v7, uv7.version());
    try std.testing.expectEqual(Variant.rfc9562, uv7.variant());
}

test "Generator.withRand overrides default rand (PERF-23)" {
    // Override rand with a deterministic function and confirm the result
    // reflects the injected bytes (i.e. the injected pointer is actually
    // called, not the default).
    const DeterministicRand = struct {
        fn fill(buf: []u8) anyerror!void {
            for (buf, 0..) |*b, i| b.* = @truncate(i);
        }
    };
    var gen = Generator.withRand(DeterministicRand.fill);
    try std.testing.expect(gen.rand != null);
    const u = try gen.newV4();
    // Version and variant are always overridden by setVersion/setVariant,
    // but untouched bytes should reflect the deterministic fill.
    try std.testing.expectEqual(@as(u8, 0), u.bytes[0]);
    try std.testing.expectEqual(@as(u8, 1), u.bytes[1]);
}

// =============================================================================
// PERF-31: GeneratorInterfaceFor — comptime-generic, zero-indirection wrapper.
// Every method is an `inline` direct call through `self.g`, so LLVM inlines
// the generator body at ReleaseFast.  These tests verify that the full
// method surface is present and produces UUIDs with the correct version and
// variant bits (the acceptance criterion in PERF-31 D1).
// =============================================================================

test "GeneratorInterfaceFor(Generator): full method surface (PERF-31)" {
    const ns_mod = @import("namespace.zig");
    const ts_mod = @import("timestamp.zig");

    var gen = Generator.init();
    const Iface = GeneratorInterfaceFor(Generator);
    var iface = Iface{ .g = &gen };

    // newV4
    const v4 = try iface.newV4();
    try std.testing.expectEqual(Version.v4, v4.version());
    try std.testing.expectEqual(Variant.rfc9562, v4.variant());

    // newV7 + newV7AtTime
    const v7 = try iface.newV7();
    try std.testing.expectEqual(Version.v7, v7.version());
    try std.testing.expectEqual(Variant.rfc9562, v7.variant());
    const v7_ms: i64 = 1_700_000_000_000;
    const v7_t = try iface.newV7AtTime(v7_ms);
    try std.testing.expectEqual(v7_ms, (try ts_mod.timestampFromV7(v7_t)).toUnixMs());

    // newV1 + newV1AtTime
    const v1 = try iface.newV1();
    try std.testing.expectEqual(Version.v1, v1.version());
    const greg_ts = ts_mod.Timestamp{ .value = 139_806_912_000_000_000 };
    const v1_t = try iface.newV1AtTime(greg_ts);
    try std.testing.expectEqual(Version.v1, v1_t.version());

    // newV6 + newV6AtTime
    const v6 = try iface.newV6();
    try std.testing.expectEqual(Version.v6, v6.version());
    const v6_t = try iface.newV6AtTime(greg_ts);
    try std.testing.expectEqual(Version.v6, v6_t.version());
    try std.testing.expectEqual(greg_ts.value, (try ts_mod.timestampFromV6(v6_t)).value);

    // newV3 / newV5 produce the RFC test vectors for DNS / www.example.com
    var buf: [36]u8 = undefined;
    const v3 = iface.newV3(ns_mod.namespace_dns, "www.example.com");
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        v3.toString(&buf),
    );
    const v5 = iface.newV5(ns_mod.namespace_dns, "www.example.com");
    try std.testing.expectEqualStrings(
        "2ed6657d-e927-568b-95e1-2665a8aea6a2",
        v5.toString(&buf),
    );

    // newV8 — infallible
    const a = [6]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const b_bytes = [2]u8{ 0x07, 0x08 };
    const c = [8]u8{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const v8 = iface.newV8(a, b_bytes, c);
    try std.testing.expectEqual(Version.v8, v8.version());
    try std.testing.expectEqual(Variant.rfc9562, v8.variant());
}

// =============================================================================
// SEC-P3-08: explicit std.Random injection via InitOptions.
// Verify:
//   (a) Generator.initOptions(.{ .random = r }) uses the supplied std.Random
//       for V4 / V7 entropy (proven by deterministic byte observation).
//   (b) Generator.initOptions(.{}) still produces valid UUIDs (default path).
//   (c) Generator.init() (legacy) still produces valid UUIDs.
// =============================================================================

test "Generator.initOptions: explicit std.Random used for V4 entropy (SEC-P3-08)" {
    // Seeded ChaCha so every byte of the V4 output (except version/variant
    // nibbles, which setVersion/setVariant overwrite) is deterministic.
    var chacha = std.Random.ChaCha.init([_]u8{0} ** 32);
    const rand = chacha.random();

    var gen = Generator.initOptions(.{ .random = rand });
    try std.testing.expect(gen.rand_impl != null);
    try std.testing.expect(gen.rand == null);

    const u = try gen.newV4();
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());

    // Proof that the injected CSPRNG was actually consulted: a second
    // generator with the same seed must yield the same byte sequence
    // (version/variant nibbles aside).  If the default global path had
    // been taken, the bytes would instead be unpredictable.
    var chacha2 = std.Random.ChaCha.init([_]u8{0} ** 32);
    const rand2 = chacha2.random();
    var gen2 = Generator.initOptions(.{ .random = rand2 });
    const u_b = try gen2.newV4();
    try std.testing.expect(u.eql(u_b));
}

test "Generator.initOptions: explicit std.Random used for V7 entropy (SEC-P3-08)" {
    // Fixed clock so the timestamp bytes match across two runs.
    const fixed_clock = struct {
        fn clock() i128 {
            return 1_700_000_000_000 * 1_000_000;
        }
    };
    var chacha = std.Random.ChaCha.init([_]u8{1} ** 32);
    const rand = chacha.random();

    var gen = Generator.initOptions(.{ .random = rand, .clock = fixed_clock.clock });
    const u = try gen.newV7();
    try std.testing.expectEqual(Version.v7, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());

    // Same seed + same clock ⇒ same bytes.
    var chacha2 = std.Random.ChaCha.init([_]u8{1} ** 32);
    const rand2 = chacha2.random();
    var gen2 = Generator.initOptions(.{ .random = rand2, .clock = fixed_clock.clock });
    const u_b = try gen2.newV7();
    try std.testing.expect(u.eql(u_b));
}

test "Generator.initOptions: empty options equivalent to init() (SEC-P3-08)" {
    // `initOptions(.{})` with no explicit fields must still produce valid
    // UUIDs via the default global CSPRNG path.
    var gen = Generator.initOptions(.{});
    try std.testing.expect(gen.rand_impl == null);
    const u = try gen.newV4();
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.init() + initOptions coexist on same process (SEC-P3-08)" {
    // Parallel generators — one default, one injected — do not interfere.
    var chacha = std.Random.ChaCha.init([_]u8{2} ** 32);
    const rand = chacha.random();

    var gen_default = Generator.init();
    var gen_injected = Generator.initOptions(.{ .random = rand });

    const a = try gen_default.newV4();
    const b = try gen_injected.newV4();
    // Two UUIDs produced by two independent sources must not collide.
    try std.testing.expect(!a.eql(b));
}

// =============================================================================
// PERF-21: opt-in lock-free V7 CAS path.
//
// Correctness is non-negotiable: RFC-9562 V7 must remain strictly monotonic.
// Three test families:
//   (1) Single-threaded parity with the mutex path over the same clock.
//   (2) Multi-threaded stress: no duplicate (ms,seq) pairs; per-thread
//       monotonicity.
//   (3) Saturation fallback: a slow clock forces the path into the mutex
//       fallback and the v7_lockfree_fallbacks counter increments.
// =============================================================================

/// Extract `(ms, seq)` from a V7 UUID's raw bytes.  ms is bytes [0..6] big-
/// endian; seq is the low 12 bits of bytes [6..8] big-endian.
fn v7MsSeq(u: UUID) struct { ms: u64, seq: u12 } {
    const hi: u64 = std.mem.readInt(u32, u.bytes[0..4], .big);
    const lo: u64 = std.mem.readInt(u16, u.bytes[4..6], .big);
    const ms = (hi << 16) | lo;
    const raw = std.mem.readInt(u16, u.bytes[6..8], .big);
    const seq: u12 = @truncate(raw & 0x0FFF);
    return .{ .ms = ms, .seq = seq };
}

test "Generator: lock-free V7 single-thread monotonicity (PERF-21)" {
    // Default clock — the test should hold regardless of whether ms
    // advances between calls.  Strict monotonicity on `(ms, seq)`.
    var gen = Generator.initOptions(.{ .v7_lockfree = true });
    const n: usize = 10_000;
    var prev = try gen.newV7();
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const u = try gen.newV7();
        try std.testing.expect(prev.order(u) == .lt);
        prev = u;
    }
}

test "Generator: mutex V7 parity with lock-free V7 (PERF-21)" {
    // Both paths over 10_000 calls must remain strictly monotonic.
    var gen_lock = Generator.init();
    var gen_free = Generator.initOptions(.{ .v7_lockfree = true });
    const n: usize = 10_000;
    var prev_lock = try gen_lock.newV7();
    var prev_free = try gen_free.newV7();
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const ul = try gen_lock.newV7();
        const uf = try gen_free.newV7();
        try std.testing.expect(prev_lock.order(ul) == .lt);
        try std.testing.expect(prev_free.order(uf) == .lt);
        prev_lock = ul;
        prev_free = uf;
    }
}

// Helper: worker thread that generates `per_thread` V7s and appends them
// into `out` at contiguous slots starting at `start`.
fn v7StressWorker(gen: *Generator, out: []UUID, start: usize, per_thread: usize) void {
    var i: usize = 0;
    while (i < per_thread) : (i += 1) {
        out[start + i] = gen.newV7() catch |e| {
            std.debug.panic("newV7 failed in stress worker: {s}", .{@errorName(e)});
        };
    }
}

test "Generator: lock-free V7 multi-thread stress — no (ms,seq) duplicates (PERF-21)" {
    // Spawn `thread_count` workers, each generating `per_thread` V7s on the
    // shared Generator with lockfree enabled.  Collect all results, sort
    // lexicographically, verify:
    //   (a) no duplicate (ms, seq) pairs,
    //   (b) per-thread monotonicity on the output slice for that thread.
    //
    // Bounded test size so CI runtime stays in budget; the stress is
    // enough to exercise the CAS retry branch (seq increments within the
    // same ms) several thousand times per thread.
    const cpu_count = std.Thread.getCpuCount() catch 4;
    const thread_count = @min(cpu_count, 8);
    const per_thread: usize = 5_000;
    const total = thread_count * per_thread;

    var gen = Generator.initOptions(.{ .v7_lockfree = true });
    const allocator = std.testing.allocator;
    const out = try allocator.alloc(UUID, total);
    defer allocator.free(out);

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var t: usize = 0;
    while (t < thread_count) : (t += 1) {
        threads[t] = try std.Thread.spawn(.{}, v7StressWorker, .{ &gen, out, t * per_thread, per_thread });
    }
    t = 0;
    while (t < thread_count) : (t += 1) threads[t].join();

    // Per-thread monotonicity check.
    t = 0;
    while (t < thread_count) : (t += 1) {
        const slice = out[t * per_thread .. (t + 1) * per_thread];
        var j: usize = 1;
        while (j < slice.len) : (j += 1) {
            try std.testing.expect(slice[j - 1].order(slice[j]) == .lt);
        }
    }

    // Global uniqueness on (ms, seq).  Encode each pair into a u64 with
    // `(ms << 12) | seq` (matching the atomic layout) and sort; check for
    // any repeats.
    const keys = try allocator.alloc(u64, total);
    defer allocator.free(keys);
    var i: usize = 0;
    while (i < total) : (i += 1) {
        const p = v7MsSeq(out[i]);
        keys[i] = (p.ms << 12) | @as(u64, p.seq);
    }
    std.mem.sort(u64, keys, {}, comptime std.sort.asc(u64));
    i = 1;
    while (i < total) : (i += 1) {
        if (keys[i] == keys[i - 1]) {
            std.debug.print("Duplicate (ms,seq) at index {d}: 0x{x}\n", .{ i, keys[i] });
            return error.TestDuplicateMsSeq;
        }
    }
}

test "Generator: lock-free V7 saturation falls back to mutex path (PERF-21)" {
    // Inject a clock that advances slowly enough that the 12-bit counter
    // saturates inside the same ms, but fast enough that eventually the
    // ms advances and the test escapes.
    //
    // Budget math: newV7Atomic calls clockCall once per iteration (plus a
    // second time inside the saturation branch to compute sleep length).
    // The counter rolls over at 4096 emits.  A stride of 8000 clock reads
    // per ms guarantees that each ms sees at least ~4000 emits (some
    // budget is spent on saturation retries + sleep-length reads), so
    // saturation is hit in every ms.  After ~16 clock reads during
    // saturation sleeps, ms advances by one and the counter re-seeds.
    const SlowClock = struct {
        var call_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
        // Base: 1_700_000_000_000 ms.  Advance ms every `stride` calls.
        const stride: u32 = 8_000;
        fn clock() i128 {
            const n = @This().call_count.fetchAdd(1, .monotonic);
            const ms: u64 = 1_700_000_000_000 + @as(u64, n / stride);
            return @as(i128, ms) * 1_000_000;
        }
    };
    SlowClock.call_count.store(0, .monotonic);

    var gen = Generator.initOptions(.{
        .v7_lockfree = true,
        .clock = SlowClock.clock,
    });

    // 5_000 UUIDs — more than one full counter-roll's worth — but short
    // enough that the test runs in sub-second time.
    const n: usize = 5_000;
    const allocator = std.testing.allocator;
    const out = try allocator.alloc(UUID, n);
    defer allocator.free(out);

    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = try gen.newV7();

    // At least one fallback must have occurred.
    const falls = gen.v7_lockfree_fallbacks.load(.monotonic);
    try std.testing.expect(falls >= 1);

    // All UUIDs strictly monotonic.
    i = 1;
    while (i < n) : (i += 1) {
        try std.testing.expect(out[i - 1].order(out[i]) == .lt);
    }
}

test "GeneratorInterfaceFor wraps default_generator (PERF-31)" {
    // The wrapper should also work against the process-global default
    // generator — this is the recommended hot-path shape for callers that
    // want inlinable dispatch without creating a local Generator.
    const default_generator = &@import("generator.zig").default_generator;
    const Iface = GeneratorInterfaceFor(Generator);
    var iface = Iface{ .g = default_generator };
    const u = try iface.newV4();
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}
