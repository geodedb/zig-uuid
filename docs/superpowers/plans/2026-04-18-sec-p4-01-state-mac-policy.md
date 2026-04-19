# SEC-P4-01 State MAC Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the HIGH-severity v3→v2 HMAC downgrade finding (SEC-P4-01) by adding an `InitOptions.state_mac_policy` enum knob that rejects unauthenticated state files when a key is configured. Includes a `Generator.migrateStateToV3` helper so operators mid-rotation can seal the migration without the policy hole.

**Architecture:** Three pieces: (1) a new `StateMacPolicy` enum with three variants and a safe default (`.require_mac_when_keyed`), wired into `InitOptions` and the `Generator` struct. (2) a new `Error.StateVersionDowngrade` variant that `loadStateImpl` returns when the policy forbids an unauthenticated version. (3) a `migrateStateToV3` helper that loads under `.any` then saves under v3. The new error variant also activates the XFAIL integration test `GAP-DOC-08.2` already in `tests/integration.zig` (added in `5fe1771`), giving us black-box downgrade-rejection coverage automatically.

**Tech Stack:** Zig 0.16.0, existing HMAC-SHA256 infrastructure (SEC-P3-04), `std.testing`.

**Behavior change callout:** `loadState` default behavior changes when `state_mac_key` is set. Previously accepted v1/v2 files with a `std.log.warn`; now rejects them with `Error.StateVersionDowngrade`. Callers mid-rotation must either (a) pass `.state_mac_policy = .any` explicitly in `InitOptions`, OR (b) call `Generator.migrateStateToV3(path)` once to upgrade the on-disk file. CHANGELOG flags this as a breaking change.

---

## File Structure

- **Modify** `src/uuid.zig`:
  - `Error` set (~line 77): add `StateVersionDowngrade` variant next to `StateMacMismatch`.
- **Modify** `src/generator.zig`:
  - ~line 38 (`mapStateError`): add the new error variant to the passthrough list.
  - ~line 140 (`InitOptions` struct): add `state_mac_policy: StateMacPolicy = .require_mac_when_keyed` field.
  - ~line 170 (`Generator` struct): add `state_mac_policy: StateMacPolicy = .require_mac_when_keyed` field.
  - Declare the `StateMacPolicy` enum near the other public types (after `RandFn`/`ClockFn`/`HWAddrFn`, before `InitOptions`).
  - `initOptions` (~line 361): copy `options.state_mac_policy` into the returned Generator.
  - `loadStateImpl` (~line 1505-1540): after reading `file_version`, check the policy against `self.state_mac_key` and the version byte; reject with `StateVersionDowngrade` when policy forbids.
  - Add a `pub fn migrateStateToV3(self, path: []const u8) Error!void` method that: validates `self.state_mac_key != null`; loads with a temporary `.any` policy override; saves under the current policy (which will write v3 because key is set).
- **Modify** `src/versions.zig`: module-level wrapper `migrateStateToV3(path)` for parity with `saveState`/`loadState`.
- **Modify** `src/root.zig`: `pub const StateMacPolicy = @import("generator.zig").StateMacPolicy;` + `pub const migrateStateToV3 = @import("versions.zig").migrateStateToV3;`.
- **Modify** `src/generator_state_test.zig`: add 4 unit tests — policy default rejects v2 with key; `.any` accepts v2 with key; `.require_mac_always` rejects v1/v2 even without key; migrateStateToV3 round-trip.
- **Modify** `CHANGELOG.md`: new entry flagging the behavior change + migration instructions.
- **Modify** `docs/SECURITY_REVIEW_NOTES.md`: mark SEC-P4-01 Closed with the commit SHA.
- **Observe activation of** `tests/integration.zig` GAP-DOC-08.2 — the XFAIL guard at `5fe1771` will auto-activate once `Error.StateVersionDowngrade` exists; verify it passes.

---

### Task 1: Add `Error.StateVersionDowngrade` variant

**Files:**

- Modify: `src/uuid.zig` — the `Error` set declaration.
- Modify: `src/generator.zig` — `mapStateError` passthrough.

- [ ] **Step 1: Find the current Error set declaration**

```
grep -n "pub const Error\|StateMacMismatch\|StateIoFailure" src/uuid.zig | head -5
```

Expected: one hit for `pub const Error = error{` near line 55-80, containing `StateMacMismatch`, `StateIoFailure`, etc.

- [ ] **Step 2: Add `StateVersionDowngrade` to the Error set**

Locate the `StateMacMismatch,` line inside the error set in `src/uuid.zig`. Add below it:

```zig
    /// SEC-P4-01: `loadState` refused an unauthenticated state file
    /// (version 1 or 2) under a policy that requires HMAC authentication.
    /// Signals that the file predates the caller's current
    /// `state_mac_key` configuration and must be migrated via
    /// `Generator.migrateStateToV3` before it can be consumed under the
    /// strict policy.  Distinct from `StateMacMismatch` so callers can
    /// programmatically offer a migration path without mis-classifying
    /// tampering as downgrade (and vice-versa).
    StateVersionDowngrade,
```

- [ ] **Step 3: Extend `mapStateError` to passthrough the new variant**

Locate `fn mapStateError` in `src/generator.zig` (~line 38-60). The function matches underlying errors and returns the mapped library `Error`. Find the line `Error.StateMacMismatch => Error.StateMacMismatch,` (currently around line 59). Add below it:

```zig
        Error.StateVersionDowngrade => Error.StateVersionDowngrade,
```

- [ ] **Step 4: Compile-check**

```
zig build check 2>&1 | tail -3
```

Expected: exit 0, no output.

- [ ] **Step 5: Commit**

```
git add src/uuid.zig src/generator.zig
git commit -m "$(cat <<'EOF'
fix(generator): add Error.StateVersionDowngrade variant (SEC-P4-01 prep)

New error variant distinguishes an HMAC-policy downgrade refusal
from a tampering mismatch (StateMacMismatch). The next commit wires
the policy check that returns it from loadState; this commit is a
pure type addition so the rest of the series can reference the
variant without `@hasDecl` gates.

The existing XFAIL integration test at tests/integration.zig
(GAP-DOC-08.2, commit 5fe1771) will auto-activate as soon as this
variant lands; the check currently uses @typeInfo(Error).error_set
scan with string-equality on "StateVersionDowngrade".

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Declare `StateMacPolicy` enum and wire the InitOptions field

**Files:**

- Modify: `src/generator.zig` — add enum + InitOptions field + Generator field + initOptions copy.

- [ ] **Step 1: Locate the InitOptions struct and the surrounding type declarations**

```
grep -n "pub const InitOptions\|pub const RandFn\|pub const ClockFn\|pub const HWAddrFn" src/generator.zig | head -5
```

Expected: one hit for `pub const InitOptions = struct {` (~line 320-345), plus hits for the `RandFn`/`ClockFn`/`HWAddrFn` typedefs earlier.

- [ ] **Step 2: Add the `StateMacPolicy` enum definition**

Just before the `pub const InitOptions = struct {` line, add:

```zig
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
```

- [ ] **Step 3: Add the `state_mac_policy` field to `InitOptions`**

Inside the `InitOptions` struct body, after the `state_mac_key: ?[32]u8 = null,` line, add:

```zig
        /// SEC-P4-01: policy controlling unauthenticated-state-file
        /// acceptance in `loadState`.  Default `.require_mac_when_keyed`
        /// rejects v1/v2 with `Error.StateVersionDowngrade` when
        /// `state_mac_key` is set; see `StateMacPolicy` for details.
        /// **Behaviour change** — pre-SEC-P4-01 callers that relied on
        /// v1/v2 being accepted with a warn must either set this to
        /// `.any` explicitly or call `Generator.migrateStateToV3`
        /// once to upgrade the on-disk file to v3.
        state_mac_policy: StateMacPolicy = .require_mac_when_keyed,
```

- [ ] **Step 4: Add the `state_mac_policy` field to the Generator struct**

Locate the line `state_mac_key: ?[32]u8 = null,` in the Generator struct (around line 159). Add immediately below it:

```zig
    /// SEC-P4-01: see `StateMacPolicy` + `InitOptions.state_mac_policy`.
    /// Set via `initOptions`; `init`/`withClock`/`withRand`/`withHWAddr`
    /// all use the safe default `.require_mac_when_keyed`.
    state_mac_policy: StateMacPolicy = .require_mac_when_keyed,
```

- [ ] **Step 5: Copy the policy into the Generator in `initOptions`**

Locate `pub fn initOptions(options: InitOptions)` (~line 361). The function currently contains a `return Generator{ ... };` expression assigning `state_mac_key = options.state_mac_key,`. Add below that line:

```zig
            .state_mac_policy = options.state_mac_policy,
```

- [ ] **Step 6: Compile**

```
zig build check 2>&1 | tail -3
zig build test --summary all 2>&1 | tail -3
```

Expected: 228/228 tests pass. No new behaviour yet — field just stored.

- [ ] **Step 7: Commit**

```
git add src/generator.zig
git commit -m "$(cat <<'EOF'
feat(generator): StateMacPolicy enum + InitOptions field (SEC-P4-01 prep)

Declares the three-variant StateMacPolicy enum (any,
require_mac_when_keyed, require_mac_always) and threads it through
InitOptions and the Generator struct. No behaviour change yet — the
policy is stored but not consulted. The next commit wires the
loadState check that returns Error.StateVersionDowngrade when the
policy forbids an unauthenticated version.

Default is .require_mac_when_keyed so fresh generators inherit the
strict policy; callers mid-rotation pass .any explicitly in
InitOptions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Write the failing loadState-policy test

**Files:**

- Modify: `src/generator_state_test.zig` (append)

- [ ] **Step 1: Add a test that exercises the default policy rejecting v2 when keyed**

Append to `src/generator_state_test.zig`:

```zig
test "SEC-P4-01: default policy rejects v2 when state_mac_key is set" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Write a v2 blob by hand (keyless save would also produce v2, but
    // we fabricate it directly so the test is independent of saveState
    // ordering).
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version_v2;
    blob[5] = 0x01; // clock_seq_initialized
    std.mem.writeInt(u16, blob[6..8], 0x1111, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], 0, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);

    const io = std.Io.Threaded.global_single_threaded.io();
    const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
    try f.writePositionalAll(io, &blob, 0);
    f.close(io);

    // Default policy with a key configured must refuse the v2 file.
    const key: [32]u8 = .{0x77} ** 32;
    var gen = Generator.initOptions(.{ .state_mac_key = key });
    try std.testing.expectError(Error.StateVersionDowngrade, gen.loadState(path));
}
```

- [ ] **Step 2: Add a test that `.any` policy accepts v2 with key (warn path)**

```zig
test "SEC-P4-01: .any policy accepts v2 when state_mac_key is set" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version_v2;
    blob[5] = 0x01;
    std.mem.writeInt(u16, blob[6..8], 0x2222, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], 0, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);

    const io = std.Io.Threaded.global_single_threaded.io();
    const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
    try f.writePositionalAll(io, &blob, 0);
    f.close(io);

    const key: [32]u8 = .{0x77} ** 32;
    var gen = Generator.initOptions(.{
        .state_mac_key = key,
        .state_mac_policy = .any,
    });
    try gen.loadState(path);
    try std.testing.expectEqual(@as(u14, 0x2222), gen.v1v6.clock_seq);
}
```

- [ ] **Step 3: Add a test that `.require_mac_always` rejects v2 even without key**

```zig
test "SEC-P4-01: .require_mac_always rejects v2 even without key" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version_v2;
    blob[5] = 0x01;
    std.mem.writeInt(u16, blob[6..8], 0x3333, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], 0, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);

    const io = std.Io.Threaded.global_single_threaded.io();
    const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
    try f.writePositionalAll(io, &blob, 0);
    f.close(io);

    var gen = Generator.initOptions(.{
        .state_mac_policy = .require_mac_always,
    });
    try std.testing.expectError(Error.StateVersionDowngrade, gen.loadState(path));
}
```

- [ ] **Step 4: Run — all three tests must FAIL because the policy is not yet enforced**

```
zig build test --summary all 2>&1 | tail -5
```

Expected: three new-test failures plus 228 other passes. Tests 1 and 3 fail because loadState currently accepts the v2 blob. Test 2 passes today (loadState already accepts v2).

- [ ] **Step 5: Commit the failing tests**

```
git add src/generator_state_test.zig
git commit -m "$(cat <<'EOF'
test(generator): SEC-P4-01 loadState policy tests (2 failing, 1 passing)

Three tests drive the loadState policy enforcement in the next commit:
- Default .require_mac_when_keyed rejects v2 with a key → currently
  FAILS because the policy check is not yet wired.
- .any accepts v2 with a key → currently PASSES (existing behaviour).
- .require_mac_always rejects v2 even without a key → currently
  FAILS because the policy check is not yet wired.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

The red commit is intentional; the next task lands the enforcement that drives the first and third tests green.

---

### Task 4: Enforce the policy in `loadStateImpl`

**Files:**

- Modify: `src/generator.zig` — the version-check block inside `loadStateImpl`.

- [ ] **Step 1: Find the version-check block**

```
grep -n "file_version == state_format_version_v3\|file_version != state_format_version_v3" src/generator.zig | head -5
```

Expected: hits around lines 1509, 1517, 1527. The ones to modify are near 1509 (the initial version-unknown check) and the block that currently handles the v3-key-missing / v1-v2-with-key-warn branches (~lines 1527-1540).

- [ ] **Step 2: Locate the exact warn-and-accept branch**

```
grep -n "loaded unauthenticated state file\|state_mac_key is set but file has no HMAC trailer" src/generator.zig
```

Expected: one hit inside `loadStateImpl`. The surrounding code (read with the `Read` tool from ~15 lines above to ~10 lines below) is of the form:

```zig
        if (file_version == state_format_version_v3) {
            // ... HMAC verify block ...
        } else if (self.state_mac_key != null) {
            std.log.warn(
                "uuid: loaded unauthenticated state file (version {d}); state_mac_key is set but file has no HMAC trailer",
                .{file_version},
            );
        }
```

- [ ] **Step 3: Replace the warn-and-accept branch with the policy check**

Replace the `else if (self.state_mac_key != null) { std.log.warn(...); }` branch with:

```zig
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
```

(Note: the closing `}` of the outer `if (file_version == state_format_version_v3)` block is already present; this replacement keeps the structure intact.)

- [ ] **Step 4: Run tests**

```
zig build test --summary all 2>&1 | tail -5
```

Expected: all 231 tests pass (228 previous + 3 new SEC-P4-01 tests). If the first/third tests still fail, the policy logic didn't take effect — re-read the replacement block.

- [ ] **Step 5: Run integration tests — the XFAIL should auto-activate**

```
zig build test-integration --summary all 2>&1 | tail -5
```

Expected: **37 pass, 0 skipped** (was 36 passed + 1 skipped — the SEC-P4-01 XFAIL that was guarded on `@typeInfo(Error).error_set` for `StateVersionDowngrade`). The downgrade test now has a real error variant to match against.

If the XFAIL still skips, inspect `tests/integration.zig` around the `GAP-DOC-08.2` test and confirm the string literal it matches against is exactly `"StateVersionDowngrade"`.

- [ ] **Step 6: Commit**

```
git add src/generator.zig
git commit -m "$(cat <<'EOF'
fix(generator): enforce state_mac_policy in loadState (SEC-P4-01)

Replaces the warn-and-accept branch for v1/v2 files when a
state_mac_key is configured with a policy-driven decision:
- .any: legacy behaviour — warn and accept.
- .require_mac_when_keyed (default): reject with
  Error.StateVersionDowngrade when a key is set.
- .require_mac_always: reject unconditionally.

Closes the trivial v3→v2 downgrade attack (CWE-757) where a local
attacker strips the 32-byte HMAC trailer from a v3 file to silently
bypass integrity verification.  The pre-SEC-P4-01 log.warn was a
detection signal only; the new policy is a hard gate.

Behaviour change: pre-SEC-P4-01 callers that set state_mac_key and
loaded older v1/v2 files must either set
InitOptions.state_mac_policy = .any or call migrateStateToV3 once
to upgrade the on-disk file.  See CHANGELOG for the migration
recipe.

Also activates the XFAIL integration test at tests/integration.zig
(GAP-DOC-08.2, commit 5fe1771) now that Error.StateVersionDowngrade
exists — integration suite grows to 37/37 passing with 0 skipped.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Write the failing migrateStateToV3 test

**Files:**

- Modify: `src/generator_state_test.zig` (append)

- [ ] **Step 1: Add the migration round-trip test**

Append:

```zig
test "SEC-P4-01: migrateStateToV3 round-trips a v2 file into v3 under the default policy" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    // Place a v2 file on disk.
    var blob: [Generator.state_size]u8 = undefined;
    @memcpy(blob[0..4], &Generator.state_magic);
    blob[4] = Generator.state_format_version_v2;
    blob[5] = 0x01;
    std.mem.writeInt(u16, blob[6..8], 0x4444, .little);
    std.mem.writeInt(u64, blob[8..16], 0, .little);
    @memset(blob[16..22], 0);
    std.mem.writeInt(i64, blob[22..30], 0, .little);
    std.mem.writeInt(u16, blob[30..32], 0, .little);

    const io = std.Io.Threaded.global_single_threaded.io();
    {
        const f = try std.Io.Dir.createFileAbsolute(io, path, .{});
        try f.writePositionalAll(io, &blob, 0);
        f.close(io);
    }

    const key: [32]u8 = .{0x99} ** 32;

    // Default policy gen: migrate the file.  After migration, the
    // file must be v3 (64 bytes) and a fresh default-policy load must
    // succeed.
    var gen = Generator.initOptions(.{ .state_mac_key = key });
    try gen.migrateStateToV3(path);

    // Verify on-disk size is now v3.
    const f2 = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer f2.close(io);
    const stat = try f2.stat(io);
    try std.testing.expectEqual(@as(u64, Generator.state_size_v3), stat.size);

    // Fresh default-policy load now succeeds.
    var gen2 = Generator.initOptions(.{ .state_mac_key = key });
    try gen2.loadState(path);
    try std.testing.expectEqual(@as(u14, 0x4444), gen2.v1v6.clock_seq);
}

test "SEC-P4-01: migrateStateToV3 rejects when no key configured" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try dirAbsPath(tmp.dir, &dir_buf);
    var path_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/state.bin", .{dir_path});

    var gen = Generator.init();
    // File doesn't even need to exist for this check — the key-not-set
    // guard fires first.
    try std.testing.expectError(
        Error.StateMacMismatch,
        gen.migrateStateToV3(path),
    );
}
```

- [ ] **Step 2: Run — tests must fail (migrateStateToV3 doesn't exist yet)**

```
zig build test --summary all 2>&1 | tail -5
```

Expected: compile error — `no member named 'migrateStateToV3'`.

- [ ] **Step 3: Commit**

```
git add src/generator_state_test.zig
git commit -m "$(cat <<'EOF'
test(generator): SEC-P4-01 migrateStateToV3 round-trip + guard (failing)

The migration helper lets operators mid-rotation upgrade v2 state
files to v3 without temporarily loosening the policy.  This commit
lands the tests first (red, fails compile because the method does
not yet exist); the next commit implements the helper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Implement `Generator.migrateStateToV3` + module wrapper

**Files:**

- Modify: `src/generator.zig` — new method.
- Modify: `src/versions.zig` — module-level wrapper.
- Modify: `src/root.zig` — re-export wrapper.

- [ ] **Step 1: Find the right insertion point**

Place `migrateStateToV3` immediately after `loadState` in `src/generator.zig`. Find:

```
grep -n "pub fn loadState\|pub fn secureWipeMacKey" src/generator.zig | head -5
```

Expected: `pub fn loadState` near 1465 and `pub fn secureWipeMacKey` near 463 (different order depending on file). The migration helper logically belongs right after `loadState` since it composes `loadState` + `saveState`.

- [ ] **Step 2: Add the method**

Insert after the closing `}` of `loadStateImpl` (the helper beneath `loadState`). Add:

```zig
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
```

- [ ] **Step 3: Add the module-level wrapper**

Open `src/versions.zig`. Find `pub fn loadState(path: []const u8) Error!void {` (~line 158). Add immediately below it:

```zig
/// SEC-P4-01: module-level wrapper for `Generator.migrateStateToV3`
/// operating on the shared `default_generator`.  See
/// `Generator.migrateStateToV3` for semantics.  Requires
/// `default_generator.state_mac_key` to be set (configure via a one-
/// off local Generator + save, or by mutating
/// `uuid.defaultGenerator().state_mac_key` — see the advanced-API
/// section of README for key-handling patterns).
pub fn migrateStateToV3(path: []const u8) Error!void {
    return gen_mod.default_generator.migrateStateToV3(path);
}
```

- [ ] **Step 4: Re-export from root.zig**

Open `src/root.zig`. Find `pub const loadState = @import("versions.zig").loadState;` (~line 100). Add:

```zig
pub const migrateStateToV3 = @import("versions.zig").migrateStateToV3;
```

Also add right alongside it (or wherever the existing `pub const Error` lives — check via `grep -n "pub const Error" src/root.zig`):

```zig
pub const StateMacPolicy = @import("generator.zig").StateMacPolicy;
```

- [ ] **Step 5: Run tests**

```
zig build test --summary all 2>&1 | tail -5
zig build test-integration --summary all 2>&1 | tail -5
```

Expected: 233/233 unit tests pass (228 + 3 policy + 2 migrate), integration 37/37.

- [ ] **Step 6: Commit**

```
git add src/generator.zig src/versions.zig src/root.zig
git commit -m "$(cat <<'EOF'
feat(generator): migrateStateToV3 helper + module wrapper (SEC-P4-01)

Adds Generator.migrateStateToV3(path) that loads a v1/v2 file under a
temporary .any policy and re-saves it under the generator's configured
policy. Because the key is set, saveState writes v3. Operators running
a rotation can invoke this once per process startup to seal the
migration without mutating InitOptions defaults.

Exposes StateMacPolicy + migrateStateToV3 at the module level via
root.zig so `uuid.migrateStateToV3(path)` and
`uuid.StateMacPolicy.any` work without reaching into the Generator
type.

Test count: 233 unit + 37 integration; the SEC-P4-01 XFAIL
integration test is now green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: CHANGELOG entry + SECURITY_REVIEW_NOTES close

**Files:**

- Modify: `CHANGELOG.md`
- Modify: `docs/SECURITY_REVIEW_NOTES.md`

- [ ] **Step 1: Add an Unreleased entry in CHANGELOG.md**

Append under the top-of-file `Unreleased` section (create one if missing, above the most recent released version):

```markdown
### Security

- **SEC-P4-01 — HMAC state-file downgrade resistance (behaviour change).**
  `loadState` now rejects unauthenticated v1/v2 files with
  `Error.StateVersionDowngrade` when `state_mac_key` is configured,
  closing the trivial v3→v2 downgrade attack (CWE-757). New
  `InitOptions.state_mac_policy` knob with three variants
  (`.any` / `.require_mac_when_keyed` / `.require_mac_always`);
  default is `.require_mac_when_keyed`. New
  `Generator.migrateStateToV3(path)` helper for one-shot migration of
  on-disk files. **Migration:** callers that previously loaded v1/v2
  files under a configured key must either set
  `InitOptions.state_mac_policy = .any` (mid-rotation) or call
  `migrateStateToV3` once (permanent). New module-level wrapper
  `uuid.migrateStateToV3(path)` for callers using the convenience
  default generator.
```

- [ ] **Step 2: Update SECURITY_REVIEW_NOTES.md**

Find the SEC-P4-01 row in the triage table (around line 825):

```
grep -n "SEC-P4-01" docs/SECURITY_REVIEW_NOTES.md | head -5
```

Change the `Session plan` column for SEC-P4-01 from the current warning text to:

```
| SEC-P4-01 | HIGH | 7.4 | ✅ Closed 2026-04-18 (`<sha-from-task-4>` enforcement + `<sha-from-task-6>` migration helper) — InitOptions.state_mac_policy default `.require_mac_when_keyed` rejects v1/v2 with `Error.StateVersionDowngrade` when keyed. Behaviour change flagged in CHANGELOG; migrateStateToV3 provides one-shot migration. | Separate PR — landed. |
```

Use the actual commit SHAs from `git log --oneline | head -10`.

- [ ] **Step 3: Commit**

```
git add CHANGELOG.md docs/SECURITY_REVIEW_NOTES.md
git commit -m "docs: mark SEC-P4-01 closed + CHANGELOG migration note"
```

- [ ] **Step 4: Push**

```
git push origin main
```

Expected: fast-forward push of all 7 commits.

---

## Self-Review Notes

- **Spec coverage:** Error variant (Task 1), enum + option (Task 2), policy tests (Task 3), enforcement (Task 4), migration tests (Task 5), migration implementation (Task 6), CHANGELOG + close-out (Task 7). All seven SEC-P4-01 spec items are covered; the XFAIL activation of GAP-DOC-08.2 is validated in Task 4 Step 5.
- **Type consistency:** `StateMacPolicy` spelled identically in generator.zig declaration, InitOptions field, Generator field, root.zig re-export, and CHANGELOG. `Error.StateVersionDowngrade` identical across the set declaration, `mapStateError`, policy enforcement, migration guard, and integration test string-match.
- **No placeholders:** every code block is literal; every grep command has an expected result.
- **Behavior change risk:** the default flip is the crux of this plan. The CHANGELOG entry and migrateStateToV3 helper are both mandatory before release — do not cut either.
- **XFAIL test contract:** Task 4 Step 5 explicitly verifies that the integration test activates. If the string-match in `tests/integration.zig` doesn't catch the new variant, that's a test bug (not a plan bug) — inspect and repair the integration test's `@typeInfo(Error).error_set` scan.
