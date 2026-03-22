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

// --- F-9: saveState / loadState ---

test "Generator.saveState and loadState round-trip (F-9 + SEC-10)" {
    // SEC-R3-02: use tmpDir for test isolation instead of a predictable /tmp path.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
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
    // When the saved last_ms is in the future (or equal to now), the
    // conservative path activates: last_ms is kept, mono_seq = maxInt.
    // SEC-R3-02: use tmpDir for test isolation.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

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
    // SEC-R3-02: use tmpDir for test isolation.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});
    var tmp_path_buf: [std.fs.max_path_bytes + 20]u8 = undefined;
    const tmp_path = try std.fmt.bufPrint(&tmp_path_buf, "{s}/state.bin.tmp", .{dir_path});

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
    // SEC-R3-02: use tmpDir for test isolation.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    var bad_buf = [_]u8{0} ** Generator.state_size;
    bad_buf[0] = 'X'; // corrupt magic

    const f = try std.fs.createFileAbsolute(path, .{});
    try f.writeAll(&bad_buf);
    f.close();

    var gen = Generator.init();
    try std.testing.expectError(Error.InvalidFormat, gen.loadState(path));
}

test "Generator.loadState: v1 format (22 bytes) accepted for backward compat (SEC-10)" {
    // Manually write a version-1 state blob and confirm it loads cleanly.
    // SEC-R3-02: use tmpDir for test isolation.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
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
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});
    var tmp_path_buf: [std.fs.max_path_bytes + 20]u8 = undefined;
    const tmp_path = try std.fmt.bufPrint(&tmp_path_buf, "{s}/state.bin.tmp", .{dir_path});

    // Pre-create a symlink at the .tmp location pointing to /dev/null.
    // /dev/null is non-destructive: writes silently succeed but no data is stored.
    // A real attack would point to a sensitive file; we use /dev/null for safety.
    try std.posix.symlink("/dev/null", tmp_path);

    // Verify the symlink is there before saveState runs.
    // Use fstatat with AT.SYMLINK_NOFOLLOW (equivalent to lstat).
    const stat_before = try std.posix.fstatat(std.posix.AT.FDCWD, tmp_path, std.posix.AT.SYMLINK_NOFOLLOW);
    try std.testing.expect(std.posix.S.ISLNK(stat_before.mode));

    var gen = Generator.init();
    gen.clock_seq = 0x0099;
    gen.clock_seq_initialized = true;

    // saveState must succeed: it removes the symlink, creates a real file,
    // writes the state, and renames it into place.
    try gen.saveState(path);

    // The .tmp file must no longer exist (renamed to path).
    const access_err = std.fs.accessAbsolute(tmp_path, .{});
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
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
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

    const f = try std.fs.createFileAbsolute(path, .{});
    try f.writeAll(&blob);
    f.close();

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
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
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

    const f = try std.fs.createFileAbsolute(path, .{});
    try f.writeAll(&blob);
    f.close();

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
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
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

    const f = try std.fs.createFileAbsolute(path, .{});
    try f.writeAll(&blob);
    f.close();

    var gen = Generator.init();
    try std.testing.expectError(Error.InvalidFormat, gen.loadState(path));
}

test "Generator.loadState: slow-restart branch uses injectable clock (QC-29)" {
    // Inject a clock returning a value ≤ saved_ms → conservative overflow branch.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    const saved_ms: i64 = 9999;
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version;
    blob[5] = 0x00;
    std.mem.writeInt(u16, blob[6..8], 0, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], saved_ms, .little);
    std.mem.writeInt(u16, blob[30..32], 0x0010, .little);

    const f2 = try std.fs.createFileAbsolute(path, .{});
    try f2.writeAll(&blob);
    f2.close();

    // Inject a clock returning 1ms (< saved_ms=9999) → conservative overflow.
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
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Place a symlink at the state path pointing to /dev/null.
    try std.posix.symlink("/dev/null", path);

    // loadState must fail — it must not read through the symlink.
    var gen = Generator.init();
    const result = gen.loadState(path);
    try std.testing.expect(std.meta.isError(result));
}
