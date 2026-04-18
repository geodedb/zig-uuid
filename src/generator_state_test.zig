// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Generator state tests (saveState / loadState) — split from generator_test.zig
// to keep both files under 800 lines (QC-28, extends QC-4 policy).
// Imported by generator.zig via `test { _ = @import("generator_state_test.zig"); }`.

const std = @import("std");
const builtin = @import("builtin");
const Generator = @import("generator.zig").Generator;
const Error = @import("uuid.zig").Error;

/// Resolve the absolute path of a Dir handle via /proc/self/fd/<fd> (Linux only).
/// On non-Linux platforms, returns an error (caller should skip the test).
fn dirAbsPath(dir: std.Io.Dir, buf: []u8) error{ Unsupported, FileNotFound, NoSpaceLeft }![]const u8 {
    const linux = if (comptime builtin.os.tag == .linux) std.os.linux else return error.Unsupported;
    const fd: linux.fd_t = dir.handle;
    var link_buf: [64:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&link_buf, "/proc/self/fd/{d}", .{fd}) catch return error.NoSpaceLeft;
    const rc = linux.readlink(&link_buf, buf.ptr, buf.len);
    const err = linux.errno(rc);
    if (err != .SUCCESS) return error.FileNotFound;
    return buf[0..rc];
}

// --- F-9: saveState / loadState ---

test "Generator.saveState and loadState round-trip (F-9 + SEC-10)" {
    // SEC-R3-02: use tmpDir for test isolation instead of a predictable /tmp path.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

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
    // When the saved last_ms is equal to now (within NTP tolerance), the
    // conservative path activates: last_ms is kept, mono_seq = maxInt.
    //
    // SEC-P3-02 note: the previous version of this test used
    // last_ms = maxInt(i64) with the default clock, relying on the saved
    // timestamp being far in the future.  That now trips the
    // clock-rollback guard (any saved_ms > current_ms + 1s is rejected).
    // We inject a clock matching the saved timestamp so the guard passes
    // AND the fast-restart (else-branch) fires.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    const saved_ms: i64 = 1_700_000_000_000; // 2023-11-14 in ms
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01; // clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], saved_ms, .little);
    std.mem.writeInt(u16, blob[30..32], 0x0042, .little);

    const f = try std.Io.Dir.createFileAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{});
    try f.writePositionalAll(std.Io.Threaded.global_single_threaded.io(), &blob, 0);
    f.close(std.Io.Threaded.global_single_threaded.io());

    // Inject a clock equal to saved_ms so current_ms <= saved_ms AND the
    // SEC-P3-02 rollback guard (saved_ms - current_ms > 1000) does not fire.
    const same_ms_clock = struct {
        fn clock() i128 {
            return @as(i128, 1_700_000_000_000) * 1_000_000;
        }
    };
    var gen = Generator.withClock(same_ms_clock.clock);
    try gen.loadState(path);
    // current_ms == saved_ms → conservative overflow branch fires.
    try std.testing.expectEqual(saved_ms, gen.last_ms);
    try std.testing.expectEqual(@as(u12, std.math.maxInt(u12)), gen.mono_seq);
}

test "Generator.saveState is atomic: no .tmp file lingers on success (SEC-9)" {
    // SEC-R3-02: use tmpDir for test isolation.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});
    var tmp_path_buf: [std.fs.max_path_bytes + 20]u8 = undefined;
    const tmp_path = try std.fmt.bufPrint(&tmp_path_buf, "{s}/state.bin.tmp", .{dir_path});

    var gen = Generator.init();
    gen.clock_seq = 0x0042;
    gen.clock_seq_initialized = true;
    try gen.saveState(path);

    // After a successful save the .tmp file must not exist.
    std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), tmp_path, .{}) catch |err| {
        // Expected: FileNotFound (or equivalent) means the tmp was cleaned up.
        try std.testing.expect(err == error.FileNotFound);
        return;
    };
    // If we reach here the tmp file still exists — that is a bug.
    return error.TmpFileLingers;
}

test "Generator.loadState: corrupt magic returns error (F-9)" {
    // SEC-R3-02: use tmpDir for test isolation.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    var bad_buf = [_]u8{0} ** Generator.state_size;
    bad_buf[0] = 'X'; // corrupt magic

    const f = try std.Io.Dir.createFileAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{});
    try f.writePositionalAll(std.Io.Threaded.global_single_threaded.io(), &bad_buf, 0);
    f.close(std.Io.Threaded.global_single_threaded.io());

    var gen = Generator.init();
    try std.testing.expectError(Error.InvalidFormat, gen.loadState(path));
}

test "Generator.loadState: v1 format (22 bytes) accepted for backward compat (SEC-10)" {
    // Manually write a version-1 state blob and confirm it loads cleanly.
    // SEC-R3-02: use tmpDir for test isolation.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    var blob: [Generator.state_size_v1]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version_v1; // version 1
    blob[5] = 0x01; // flags: clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0x0ABC, .little);
    // SEC-R6-04: last_v1_ts must be within u60 range (max 0x0FFF_FFFF_FFFF_FFFF).
    // Use 0x0DEADBEEFCAFE (a recognisable value that fits in u60).
    std.mem.writeInt(u64, blob[8..16], 0x0DEAD_BEEF_CAFE, .little);
    @memset(blob[16..22], 0); // no node cache

    const f = try std.Io.Dir.createFileAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{});
    try f.writePositionalAll(std.Io.Threaded.global_single_threaded.io(), &blob, 0);
    f.close(std.Io.Threaded.global_single_threaded.io());

    var gen = Generator.init();
    try gen.loadState(path);
    try std.testing.expectEqual(@as(u14, 0x0ABC), gen.clock_seq);
    try std.testing.expect(gen.clock_seq_initialized);
    // V7 state defaults to zero (no data in v1 blob).
    try std.testing.expectEqual(@as(i64, 0), gen.last_ms);
}

test "Generator.saveState: symlink at .tmp path does not redirect write (SEC-R3-01)" {
    // SEC-R3-01 (CWE-61): Verify that a pre-placed symlink at <path>.tmp is
    // removed by saveState rather than followed.  saveState must unlink any
    // existing .tmp file before creating the real one with O_EXCL, so the write
    // always goes to a fresh, owned file — never to a symlink target.
    //
    // Skip on Windows: symlink creation requires elevated privileges.
    if (builtin.os.tag == .windows) return;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});
    var tmp_path_buf: [std.fs.max_path_bytes + 20]u8 = undefined;
    const tmp_path = try std.fmt.bufPrint(&tmp_path_buf, "{s}/state.bin.tmp", .{dir_path});

    // Pre-create a symlink at the .tmp location pointing to /dev/null.
    // /dev/null is non-destructive: writes silently succeed but no data is stored.
    // A real attack would point to a sensitive file; we use /dev/null for safety.
    try std.Io.Dir.symLinkAbsolute(std.Io.Threaded.global_single_threaded.io(), "/dev/null", tmp_path, .{});

    // Verify the symlink is there before saveState runs.
    // If accessAbsolute succeeds, the symlink target (/dev/null) is reachable.
    try std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), tmp_path, .{});

    var gen = Generator.init();
    gen.clock_seq = 0x0099;
    gen.clock_seq_initialized = true;

    // saveState must succeed: it removes the symlink, creates a real file,
    // writes the state, and renames it into place.
    try gen.saveState(path);

    // The .tmp file must no longer exist (renamed to path).
    const access_err = std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), tmp_path, .{});
    try std.testing.expectError(error.FileNotFound, access_err);

    // The state must have been written correctly (round-trip load).
    var gen2 = Generator.init();
    try gen2.loadState(path);
    try std.testing.expectEqual(gen.clock_seq, gen2.clock_seq);
    try std.testing.expect(gen2.clock_seq_initialized);
}

// --- SEC-R4-03: loadState rejects oversized state files ---

test "Generator.loadState: file with trailing bytes returns InvalidFormat (SEC-R4-03)" {
    // Write a valid 32-byte state blob followed by extra bytes.  loadState
    // must reject this rather than silently ignoring the trailer.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Build a syntactically valid v2 blob (32 bytes).
    var blob: [Generator.state_size + 4]u8 = undefined; // 4 trailing bytes
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01; // clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0x0042, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], 0, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);
    // Trailing garbage
    blob[32] = 0xFF;
    blob[33] = 0xFE;
    blob[34] = 0xFD;
    blob[35] = 0xFC;

    const f = try std.Io.Dir.createFileAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{});
    try f.writePositionalAll(std.Io.Threaded.global_single_threaded.io(), &blob, 0);
    f.close(std.Io.Threaded.global_single_threaded.io());

    var gen = Generator.init();
    try std.testing.expectError(Error.InvalidFormat, gen.loadState(path));
}

// --- QC-29: loadState uses injectable clock for fast-restart detection ---

test "Generator.loadState: fast-restart branch uses injectable clock (QC-29)" {
    // Verify that loadState reads the current time via self.clock() rather than
    // std.time.nanoTimestamp() directly.  We inject a clock returning a value
    // greater than saved_ms so the clean-reset branch fires (last_ms=0, mono_seq=0).
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Write a v2 blob with a saved last_ms of 1ms (very old).
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01; // clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], 1, .little); // saved_ms = 1
    std.mem.writeInt(u16, blob[30..32], 0x0042, .little);

    const f = try std.Io.Dir.createFileAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{});
    try f.writePositionalAll(std.Io.Threaded.global_single_threaded.io(), &blob, 0);
    f.close(std.Io.Threaded.global_single_threaded.io());

    // Inject a clock returning 2ms (> saved_ms=1) → clean-reset branch fires.
    const future_clock = struct {
        fn clock() i128 {
            return 2 * 1_000_000; // 2ms in nanoseconds
        }
    };
    var gen = Generator.withClock(future_clock.clock);
    try gen.loadState(path);

    // Clock advanced past saved_ms → clean reset: last_ms=0, mono_seq=0.
    try std.testing.expectEqual(@as(i64, 0), gen.last_ms);
    try std.testing.expectEqual(@as(u12, 0), gen.mono_seq);
}

// --- SEC-R6-04: loadState rejects out-of-range last_v1_ts ---

test "Generator.loadState: rejects out-of-range last_v1_ts (SEC-R6-04)" {
    // A u64 last_v1_ts value above maxInt(u60) = 0x0FFF_FFFF_FFFF_FFFF must
    // cause loadState to return Error.InvalidFormat rather than silently
    // truncating to a valid-looking timestamp.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Build a syntactically valid v2 blob (32 bytes) with an out-of-range
    // last_v1_ts: maxInt(u60) + 1 = 0x1000_0000_0000_0000.
    const out_of_range_ts: u64 = @as(u64, std.math.maxInt(u60)) + 1;
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01; // clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0x0042, .little);
    std.mem.writeInt(u64, blob[8..16], out_of_range_ts, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], 0, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);

    const f = try std.Io.Dir.createFileAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{});
    try f.writePositionalAll(std.Io.Threaded.global_single_threaded.io(), &blob, 0);
    f.close(std.Io.Threaded.global_single_threaded.io());

    var gen = Generator.init();
    try std.testing.expectError(Error.InvalidFormat, gen.loadState(path));
}

test "Generator.loadState: slow-restart branch uses injectable clock (QC-29)" {
    // Inject a clock returning a value ≤ saved_ms → conservative overflow branch.
    // SEC-P3-02: saved_ms must be within clock_rollback_tolerance_ms (1000)
    // of current_ms; otherwise the rollback guard rejects the load.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    const saved_ms: i64 = 1001;
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x00;
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], saved_ms, .little);
    std.mem.writeInt(u16, blob[30..32], 0x0010, .little);

    const f2 = try std.Io.Dir.createFileAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{});
    try f2.writePositionalAll(std.Io.Threaded.global_single_threaded.io(), &blob, 0);
    f2.close(std.Io.Threaded.global_single_threaded.io());

    // Inject a clock returning 1ms (< saved_ms=1001; diff=1000 ≤ tolerance).
    const past_clock = struct {
        fn clock() i128 {
            return 1 * 1_000_000; // 1ms in nanoseconds
        }
    };
    var gen = Generator.withClock(past_clock.clock);
    try gen.loadState(path);

    // Clock has NOT advanced past saved_ms → keep saved_ms, overflow mono_seq.
    try std.testing.expectEqual(saved_ms, gen.last_ms);
    try std.testing.expectEqual(@as(u12, std.math.maxInt(u12)), gen.mono_seq);
}

// --- QC-101: loadState v1→v2 upgrade path + fast-restart within-same-ms ---

test "Generator.loadState: v1 blob with injected clock zeroes V7 state (QC-101)" {
    // (QC-101/a) A v1 state blob contains no V7 fields (last_ms, mono_seq).
    // loadState must leave those at the Generator.init() defaults (both 0) so
    // that the first post-upgrade V7 call does not spin-wait on a stale
    // timestamp.  Uses an injected clock for determinism — the v1 path should
    // not even read the clock for V7 state, but we still pin it to avoid the
    // wall clock influencing the test.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Build a valid v1 (22-byte) blob.
    var blob: [Generator.state_size_v1]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version_v1;
    blob[5] = 0x01; // clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0x0ABC, .little);
    std.mem.writeInt(u64, blob[8..16], 0x0DEAD_BEEF_CAFE, .little);
    @memset(blob[16..22], 0);

    const io = std.Io.Threaded.global_single_threaded.io();
    const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
    try f.writePositionalAll(io, &blob, 0);
    f.close(io);

    // Inject a clock that returns a recognisable, far-future value. If the
    // upgrade path erroneously took the v2 fast-restart branch (saved_ms
    // undefined → treated as 0 → current_ms > saved_ms), the clean-reset
    // branch would still produce last_ms=0, mono_seq=0 by coincidence. The
    // stronger assertion is that V7 state is never touched at all — both
    // fields remain at Generator.init() defaults.
    const injected_clock = struct {
        fn clock() i128 {
            return 10_000 * 1_000_000; // 10s in ns, >> any v1 saved state
        }
    };
    var gen = Generator.withClock(injected_clock.clock);
    try gen.loadState(path);

    // V1/V6 state loaded from blob:
    try std.testing.expectEqual(@as(u14, 0x0ABC), gen.clock_seq);
    try std.testing.expect(gen.clock_seq_initialized);
    // V7 state must be zero (no data in a v1 blob; loadState skips the
    // version-2-only restore branch).
    try std.testing.expectEqual(@as(i64, 0), gen.last_ms);
    try std.testing.expectEqual(@as(u12, 0), gen.mono_seq);
}

test "Generator.loadState: saved_ms >= current_ms forces mono_seq overflow (QC-101)" {
    // (QC-101/b) generator.zig's loadStateImpl branches on
    //     if (current_ms > saved_ms) { last_ms = 0; mono_seq = 0; }
    //     else { last_ms = saved_ms; mono_seq = maxInt(u12); }
    // The else-branch is the "fast restart within the same ms" guard: if the
    // clock has NOT advanced past the persisted last_ms, the next V7 call
    // must spin-wait on mono_seq overflow rather than rewinding the counter.
    //
    // Uses an injected clock set to EXACTLY saved_ms so the comparison
    // `current_ms > saved_ms` is false (the documented same-ms case).
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    const saved_ms: i64 = 1_700_000_000_000; // 2023-11-14 in ms
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01;
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], saved_ms, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little); // saved mono_seq irrelevant

    const io = std.Io.Threaded.global_single_threaded.io();
    const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
    try f.writePositionalAll(io, &blob, 0);
    f.close(io);

    // Inject a clock set to EXACTLY saved_ms (same-ms case). current_ms ==
    // saved_ms → the strict `>` comparison is false → else-branch fires.
    const same_ms_clock = struct {
        fn clock() i128 {
            return @as(i128, 1_700_000_000_000) * 1_000_000; // saved_ms in ns
        }
    };
    var gen = Generator.withClock(same_ms_clock.clock);
    try gen.loadState(path);

    // Fast-restart overflow branch: keep saved_ms, force counter to max.
    try std.testing.expectEqual(saved_ms, gen.last_ms);
    try std.testing.expectEqual(@as(u12, std.math.maxInt(u12)), gen.mono_seq);
}

// --- SEC-P3-02: loadState rejects future-dated state (clock-rollback guard) ---

test "Generator.loadState: rejects last_ms beyond NTP tolerance (SEC-P3-02)" {
    // SEC-P3-02 (CWE-367 / CWE-1240): a saved last_ms whose value is more
    // than clock_rollback_tolerance_ms in the future relative to the clock
    // indicates a rollback/replay attack or a corrupt persisted value.
    // Accepting it would produce duplicate V7 UUIDs once the clock
    // "catches up".  loadState must return Error.InvalidFormat.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // current_ms = 1_000 ms; saved_ms = 1_000 + 1001 = 2_001 → diff=1001 > 1000.
    const current_ms: i64 = 1_000;
    const saved_ms: i64 = current_ms + Generator.clock_rollback_tolerance_ms + 1;
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01;
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], saved_ms, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);

    const io = std.Io.Threaded.global_single_threaded.io();
    const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
    try f.writePositionalAll(io, &blob, 0);
    f.close(io);

    const injected_clock = struct {
        fn clock() i128 {
            return @as(i128, 1_000) * 1_000_000; // 1s in ns
        }
    };
    var gen = Generator.withClock(injected_clock.clock);
    try std.testing.expectError(Error.InvalidFormat, gen.loadState(path));
}

test "Generator.loadState: accepts last_ms within NTP tolerance (SEC-P3-02)" {
    // Same setup as the rejection test but with saved_ms exactly at the
    // tolerance boundary (current + 1000).  diff == tolerance → NOT > → accepted.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    const current_ms: i64 = 1_000;
    const saved_ms: i64 = current_ms + Generator.clock_rollback_tolerance_ms;
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01;
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], saved_ms, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);

    const io = std.Io.Threaded.global_single_threaded.io();
    const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
    try f.writePositionalAll(io, &blob, 0);
    f.close(io);

    const injected_clock = struct {
        fn clock() i128 {
            return @as(i128, 1_000) * 1_000_000;
        }
    };
    var gen = Generator.withClock(injected_clock.clock);
    // Must NOT return an error.
    try gen.loadState(path);
    try std.testing.expectEqual(saved_ms, gen.last_ms);
}

test "Generator.loadState: clamps last_v1_ts to max(existing, persisted) (SEC-P3-02)" {
    // SEC-P3-02 clamp: loadState must never rewind the V1/V6 monotonicity
    // high-water mark.  If `self.last_v1_ts` is already ahead of the
    // persisted value (e.g. caller generated some V1 UUIDs before loading,
    // or two loadState calls with different files), keep the larger value.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Persisted last_v1_ts = 1000 (small Gregorian value → converts to a
    // very-negative Unix ms → passes the rollback guard trivially).
    const persisted_v1_ts: u64 = 1_000;
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x01;
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], persisted_v1_ts, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], 0, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);

    const io = std.Io.Threaded.global_single_threaded.io();
    const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
    try f.writePositionalAll(io, &blob, 0);
    f.close(io);

    // Pre-populate the generator with a LARGER last_v1_ts than the file.
    const pre_existing_v1_ts: u60 = 5_000;
    var gen = Generator.init();
    gen.last_v1_ts = pre_existing_v1_ts;
    try gen.loadState(path);

    // Clamp must keep the pre-existing (larger) value, not rewind to 1_000.
    try std.testing.expectEqual(pre_existing_v1_ts, gen.last_v1_ts);
}

// --- SEC-P3-03: saveState produces a file with mode 0o600 ---

test "Generator.saveState: result file has POSIX mode 0o600 (SEC-P3-03)" {
    // SEC-P3-03 (CWE-276 / CWE-732): verify the final state file is owner-
    // only regardless of the process umask.  The implementation requests
    // .permissions=0o600 at create time AND performs an umask-proof fchmod
    // before writing bytes, so the rename target must have mode == 0o600.
    //
    // Skip on Windows — POSIX mode bits do not apply.
    if (builtin.os.tag == .windows) return;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Deliberately set a permissive umask so that open(2) alone would leave
    // the file world-readable.  The fchmod fallback in saveState must still
    // force 0o600.  Use the raw Linux umask(2) syscall (std.posix has no
    // umask wrapper in 0.16).
    const old_umask: usize = std.os.linux.syscall1(.umask, 0o000);
    defer _ = std.os.linux.syscall1(.umask, old_umask);

    var gen = Generator.init();
    gen.clock_seq = 0x0099;
    gen.clock_seq_initialized = true;
    try gen.saveState(path);

    // statx(AT_FDCWD, path, AT_SYMLINK_NOFOLLOW, STATX_MODE, &stx) and verify
    // the low 9 mode bits are exactly 0o600.
    var path_z_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path_z = try std.fmt.bufPrintZ(&path_z_buf, "{s}", .{path});
    var stx: std.os.linux.Statx = undefined;
    const AT_SYMLINK_NOFOLLOW: u32 = 0x100;
    const rc = std.os.linux.statx(
        std.os.linux.AT.FDCWD,
        path_z.ptr,
        AT_SYMLINK_NOFOLLOW,
        .{ .MODE = true },
        &stx,
    );
    try std.testing.expectEqual(std.os.linux.E.SUCCESS, std.os.linux.errno(rc));
    const perm_bits: u16 = @intCast(stx.mode & 0o777);
    try std.testing.expectEqual(@as(u16, 0o600), perm_bits);
}

// --- SEC-R11-04: loadState rejects symlinks (O_NOFOLLOW) ---

test "Generator.loadState: symlink at state path is rejected (SEC-R11-04)" {
    // SEC-R11-04 (CWE-61): loadState must refuse to follow a symlink at the
    // given path.  An attacker who can pre-place a symlink could redirect the
    // read to any world-readable file, leaking its contents.  With O_NOFOLLOW
    // the open(2) returns ELOOP and loadState propagates an error.
    //
    // Skip on Windows: symlink creation typically requires elevated privileges,
    // and the OS enforces different symlink semantics.
    if (builtin.os.tag == .windows) return;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Place a symlink at the state path pointing to /dev/null.
    try std.Io.Dir.symLinkAbsolute(std.Io.Threaded.global_single_threaded.io(), "/dev/null", path, .{});

    // loadState must fail — it must not read through the symlink.
    var gen = Generator.init();
    const result = gen.loadState(path);
    try std.testing.expect(std.meta.isError(result));
}
