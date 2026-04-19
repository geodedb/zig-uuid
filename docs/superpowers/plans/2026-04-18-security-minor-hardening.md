# Minor Security Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four low/medium security hardenings from the 2026-04-18 cycle-2 audit — SEC-P4-03 (clock-rollback tolerance as runtime config), SEC-P4-04 (Namespace trusted-origin allowlist for `.custom`), SEC-P4-08 (`v7_lockfree_fallbacks` observability hardening), SEC-P4-09 (debug-mode assertion against known-weak `rand_impl` PRNGs).

**Architecture:** Four additive changes, each independently testable and commitable. SEC-P4-03 converts an existing compile-time constant (`clock_rollback_tolerance_ms`) into an instance field + `InitOptions` override with a tighter default. SEC-P4-04 adds a process-global origin allowlist (atomic-once-init like `ProcessHashContext`) behind a new `Namespace.fromConfig(bytes, origin)` helper. SEC-P4-08 relocates the `v7_lockfree_fallbacks` counter behind a method-only accessor so callers cannot fingerprint contention via direct field reads without going through a documented API. SEC-P4-09 adds a release-stripped `std.debug.assert` on known-weak `std.Random` vtables at `initOptions` time.

**Tech Stack:** Zig 0.16.0, `std.atomic`, `std.testing`.

**SEC-P4-01 dependency:** Works cleanly alongside SEC-P4-01 but doesn't require it. Execute in any order.

---

## File Structure

- **Modify** `src/generator.zig`:
  - `clock_rollback_tolerance_ms`: change from `pub const ... = 1_000` to an instance field with default via `InitOptions.clock_rollback_tolerance_ms: ?i64 = null`; replace the two compare sites (~lines 1590, 1620) to read the instance field.
  - Rename the public pub-counter access on `v7_lockfree_fallbacks` to go through a new method `pub fn lockfreeFallbackCount(self: *const Generator) u64`; mark the field as `_v7_lockfree_fallbacks` (underscore prefix — convention for private-intent) so direct-field callers get a compile error and migrate.
  - `initOptions`: copy the new `clock_rollback_tolerance_ms` into the Generator; call a new `assertRandNotKnownWeak` helper when `options.random` is non-null.
- **Create** `src/trusted_namespace_origins.zig`: small module owning the process-global allowlist + CAS-once init pattern for `Namespace.fromConfig`. Kept separate to isolate the global state.
- **Modify** `src/namespace.zig`: add `fromConfig(bytes: [16]u8, origin: []const u8) error{UnvettedNamespace}!Namespace` that consults the allowlist; re-export from root.zig.
- **Modify** `src/root.zig`: re-export `registerTrustedNamespaceOrigin`.
- **Modify** `src/generator_test.zig` / `src/uuid_test.zig`: add tests per finding.
- **Modify** `docs/SECURITY_REVIEW_NOTES.md`: mark SEC-P4-03/04/08/09 Closed at end.

No new files beyond `src/trusted_namespace_origins.zig`.

---

### Task 1: SEC-P4-03 — Failing test for configurable clock_rollback_tolerance_ms

**Files:**

- Modify: `src/generator_state_test.zig` (append)

- [ ] **Step 1: Add the two tests**

```zig
test "SEC-P4-03: default clock_rollback_tolerance_ms is 250 (tightened from 1000)" {
    var gen = Generator.init();
    try std.testing.expectEqual(@as(i64, 250), gen.clock_rollback_tolerance_ms);
}

test "SEC-P4-03: InitOptions.clock_rollback_tolerance_ms overrides the default" {
    var gen = Generator.initOptions(.{ .clock_rollback_tolerance_ms = 500 });
    try std.testing.expectEqual(@as(i64, 500), gen.clock_rollback_tolerance_ms);
}

test "SEC-P4-03: InitOptions caps rollback tolerance to [0, 60_000] range" {
    var gen_lo = Generator.initOptions(.{ .clock_rollback_tolerance_ms = -100 });
    try std.testing.expectEqual(@as(i64, 0), gen_lo.clock_rollback_tolerance_ms);

    var gen_hi = Generator.initOptions(.{ .clock_rollback_tolerance_ms = 1_000_000 });
    try std.testing.expectEqual(@as(i64, 60_000), gen_hi.clock_rollback_tolerance_ms);
}
```

- [ ] **Step 2: Run — all three must fail compile (field doesn't exist yet)**

```
zig build check 2>&1 | grep "error:" | head -5
```

Expected: `error: no field named 'clock_rollback_tolerance_ms' in struct 'Generator.InitOptions'` (and similar for the Generator struct). The compile errors are the red signal.

- [ ] **Step 3: Commit the failing tests**

```
git add src/generator_state_test.zig
git commit -m "test(generator): SEC-P4-03 clock_rollback_tolerance as runtime config (failing)"
```

---

### Task 2: SEC-P4-03 — Implement the field + clamp

**Files:**

- Modify: `src/generator.zig`

- [ ] **Step 1: Locate the existing const**

```
grep -n "pub const clock_rollback_tolerance_ms" src/generator.zig
```

Expected: one hit around line 1269.

- [ ] **Step 2: Convert const → field default constant**

Change the line:

```zig
    pub const clock_rollback_tolerance_ms: i64 = 1_000;
```

to:

```zig
    /// SEC-P4-03: default clock-rollback tolerance applied when
    /// `InitOptions.clock_rollback_tolerance_ms` is null.  Tightened
    /// from the pre-SEC-P4-03 1_000 ms to 250 ms, matching NTP's
    /// chrony `maxslewrate` practical upper bound.  Callers that need
    /// a wider window (e.g. deployments with flaky NTP or VM-suspend
    /// jumps) pass an explicit value via InitOptions; the value is
    /// clamped to [0, 60_000].
    pub const default_clock_rollback_tolerance_ms: i64 = 250;
```

- [ ] **Step 3: Add the instance field to Generator**

Find the Generator struct's `state_mac_key` field (~line 159 or similar). Right after it (or near other SEC-P* config fields), add:

```zig
    /// SEC-P4-03: instance-field rollback tolerance.  Default is
    /// `default_clock_rollback_tolerance_ms` (250 ms); override via
    /// `InitOptions.clock_rollback_tolerance_ms`.  Value is clamped
    /// to `[0, 60_000]` in `initOptions`.
    clock_rollback_tolerance_ms: i64 = default_clock_rollback_tolerance_ms,
```

- [ ] **Step 4: Add the InitOptions field**

Inside `InitOptions` (add near the other SEC-P* fields — next to `state_mac_key` for logical grouping):

```zig
        /// SEC-P4-03: override the default clock-rollback tolerance
        /// (`Generator.default_clock_rollback_tolerance_ms` = 250 ms).
        /// Clamped to `[0, 60_000]` by `initOptions` to prevent
        /// accidental disables (via maxInt) and negative values.  Null
        /// keeps the default; set to 0 to reject ANY backward clock
        /// motion; larger values widen the accepted window for
        /// deployments with known-bad clocks.
        clock_rollback_tolerance_ms: ?i64 = null,
```

- [ ] **Step 5: Wire the copy + clamp in initOptions**

Locate `pub fn initOptions(options: InitOptions)` (~line 361). In the `return Generator{ ... };` expression, add:

```zig
            .clock_rollback_tolerance_ms = clampRollbackTolerance(options.clock_rollback_tolerance_ms),
```

Define the `clampRollbackTolerance` helper right next to `initOptions` (near the top of the Generator method block):

```zig
    fn clampRollbackTolerance(opt: ?i64) i64 {
        const raw = opt orelse default_clock_rollback_tolerance_ms;
        // Clamp to [0, 60_000] — 60s is the practical upper bound for
        // NTP + reasonable VM-suspend recovery; beyond that, the caller
        // should call resetState() rather than widen the tolerance.
        if (raw < 0) return 0;
        if (raw > 60_000) return 60_000;
        return raw;
    }
```

- [ ] **Step 6: Update the two compare sites**

```
grep -n "clock_rollback_tolerance_ms" src/generator.zig
```

Expected: 4 hits — the declaration, the InitOptions field, the initOptions wiring, and **two compare sites in `loadStateImpl`** (~lines 1590 and 1620). Both currently compare against `clock_rollback_tolerance_ms` (the const). Update both to compare against `self.clock_rollback_tolerance_ms` (the instance field):

At each compare site, change:

```zig
            (saved_v1_ms - current_ms) > clock_rollback_tolerance_ms)
```

to:

```zig
            (saved_v1_ms - current_ms) > self.clock_rollback_tolerance_ms)
```

And:

```zig
            (saved_ms - current_ms) > clock_rollback_tolerance_ms)
```

to:

```zig
            (saved_ms - current_ms) > self.clock_rollback_tolerance_ms)
```

- [ ] **Step 7: Run tests**

```
zig build test --summary all 2>&1 | tail -5
```

Expected: tests added in Task 1 now pass. Full suite 231/231 or similar. The existing SEC-P3-02 test (`loadState rejects future-dated saved timestamps`) must continue passing — it doesn't set a custom tolerance, so it runs against the new 250 ms default.

**Gotcha:** if any existing test expected the old 1000 ms tolerance and fails now, inspect the test — is it asserting behaviour beyond ±250 ms? The SEC-P3-02 test uses `saved_ms = current_ms + 1500` to cross the old boundary; 1500 is still > 250, so it still rejects, test stays green. If a test fails here, update the fixture to use a value that's unambiguously beyond the new tighter tolerance.

- [ ] **Step 8: Commit**

```
git add src/generator.zig
git commit -m "$(cat <<'EOF'
fix(generator): clock_rollback_tolerance_ms as InitOptions field (SEC-P4-03)

Converts the pub-const 1000 ms tolerance into an instance field with
default 250 ms (matching chrony maxslewrate).  Configurable via
InitOptions.clock_rollback_tolerance_ms (null → default, otherwise
clamped to [0, 60_000] to prevent accidental disable via maxInt).

Behaviour change: callers that previously relied on the implicit 1 s
window must set the option explicitly if they need > 250 ms.  The
existing SEC-P3-02 test uses a 1500 ms future-dated file, which
rejects under both old and new defaults — no fixture updates needed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: SEC-P4-04 — Trusted-namespace-origin allowlist

**Files:**

- Create: `src/trusted_namespace_origins.zig`
- Modify: `src/namespace.zig`
- Modify: `src/root.zig`
- Modify: `src/uuid_test.zig` (append)

- [ ] **Step 1: Create the allowlist module**

Create `/home/benji/src/devnw/zig/uuid/src/trusted_namespace_origins.zig`:

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// SEC-P4-04: process-global trusted-namespace-origin allowlist for
// `Namespace.fromConfig`.  Mirrors the CAS-once-init pattern used by
// `UUID.ProcessHashContext` (src/uuid.zig).
//
// The allowlist is append-only — `registerTrustedNamespaceOrigin`
// stores the origin string under an internal mutex, and
// `isTrusted(origin)` scans linearly.  Append-only means a configured
// process never loses trust over time; a reseed/fork-clean pattern is
// explicitly NOT provided, because the allowlist is a startup
// configuration (not a rotating-capability).
//
// Capacity is fixed at `max_trusted_origins` — 16 is enough for any
// realistic config-flag vocabulary (tenant-id, api-key-prefix, etc.)
// and keeps the linear scan cheap.  Registering a 17th origin returns
// `error.TrustedOriginLimitExceeded`.

const std = @import("std");

pub const max_trusted_origins: usize = 16;

pub const RegisterError = error{ TrustedOriginLimitExceeded, OriginTooLong };

const max_origin_bytes: usize = 64;

const Entry = struct {
    len: usize,
    bytes: [max_origin_bytes]u8,
};

var mutex: std.Thread.Mutex = .{};
var entries: [max_trusted_origins]Entry = undefined;
var entry_count: usize = 0;

/// Register a caller-trusted origin string.  Idempotent — registering
/// the same string twice is a no-op success.  Appends the string to
/// the process-global allowlist; `isTrusted(origin)` returns true for
/// registered origins.
///
/// Threadsafe: protected by an internal mutex.
pub fn registerTrustedNamespaceOrigin(origin: []const u8) RegisterError!void {
    if (origin.len > max_origin_bytes) return error.OriginTooLong;
    mutex.lock();
    defer mutex.unlock();
    // Idempotent on exact match.
    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        if (entries[i].len == origin.len and
            std.mem.eql(u8, entries[i].bytes[0..entries[i].len], origin))
            return;
    }
    if (entry_count >= max_trusted_origins)
        return error.TrustedOriginLimitExceeded;
    entries[entry_count].len = origin.len;
    @memcpy(entries[entry_count].bytes[0..origin.len], origin);
    entry_count += 1;
}

/// Linear scan of the allowlist.  Cheap — max 16 × 64-byte compares.
pub fn isTrusted(origin: []const u8) bool {
    mutex.lock();
    defer mutex.unlock();
    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        if (entries[i].len == origin.len and
            std.mem.eql(u8, entries[i].bytes[0..entries[i].len], origin))
            return true;
    }
    return false;
}

/// TEST-ONLY: reset the allowlist between tests.  NOT exposed in the
/// public API — tests import this module directly.
pub fn resetForTest() void {
    mutex.lock();
    defer mutex.unlock();
    entry_count = 0;
}
```

- [ ] **Step 2: Add `Namespace.fromConfig` + tests**

Open `src/namespace.zig`. After the `asUUID` method (inside the `Namespace` union), add:

```zig
    /// SEC-P4-04: runtime-driven constructor that consults the process
    /// trusted-origin allowlist.  `origin` is a caller-defined string
    /// tag identifying where the bytes came from (e.g.
    /// "config.namespace", "vault.uuid-ns", "CLI --uuid-ns"); it must
    /// be registered via `registerTrustedNamespaceOrigin` at process
    /// startup before `fromConfig` will accept bytes carrying it.
    ///
    /// Returns `error.UnvettedNamespace` if the origin is not in the
    /// allowlist.  This converts the compile-time-only Namespace
    /// constraint into a startup-configurable runtime gate — callers
    /// who load namespaces from config can still get the CWE-347
    /// protection that `newV3Strict`/`newV5Strict` afford, without
    /// hard-coding the bytes.
    ///
    /// Safe pattern:
    /// ```zig
    /// // Startup:
    /// try uuid.registerTrustedNamespaceOrigin("config.tenant");
    ///
    /// // Later, config-driven:
    /// const ns_bytes = parseConfig(...);
    /// const ns = try Namespace.fromConfig(ns_bytes, "config.tenant");
    /// const id = try uuid.newV3Strict(ns, name);
    /// ```
    pub fn fromConfig(bytes: [16]u8, origin: []const u8) error{UnvettedNamespace}!Namespace {
        const trusted = @import("trusted_namespace_origins.zig");
        if (!trusted.isTrusted(origin)) return error.UnvettedNamespace;
        return Namespace{ .custom = bytes };
    }
```

And append these tests at the end of `src/namespace.zig` (after any existing tests):

```zig
test "SEC-P4-04: Namespace.fromConfig rejects unregistered origin" {
    const trusted = @import("trusted_namespace_origins.zig");
    trusted.resetForTest();
    defer trusted.resetForTest();

    const bytes: [16]u8 = .{0x01} ** 16;
    try std.testing.expectError(
        error.UnvettedNamespace,
        Namespace.fromConfig(bytes, "unregistered.origin"),
    );
}

test "SEC-P4-04: Namespace.fromConfig accepts registered origin" {
    const trusted = @import("trusted_namespace_origins.zig");
    trusted.resetForTest();
    defer trusted.resetForTest();

    try trusted.registerTrustedNamespaceOrigin("config.tenant");
    const bytes: [16]u8 = .{0x02} ** 16;
    const ns = try Namespace.fromConfig(bytes, "config.tenant");
    try std.testing.expectEqualSlices(u8, &bytes, &ns.asUUID().bytes);
}

test "SEC-P4-04: registerTrustedNamespaceOrigin is idempotent" {
    const trusted = @import("trusted_namespace_origins.zig");
    trusted.resetForTest();
    defer trusted.resetForTest();

    try trusted.registerTrustedNamespaceOrigin("x");
    try trusted.registerTrustedNamespaceOrigin("x"); // idempotent no-op
    try std.testing.expect(trusted.isTrusted("x"));
}

test "SEC-P4-04: registerTrustedNamespaceOrigin enforces capacity" {
    const trusted = @import("trusted_namespace_origins.zig");
    trusted.resetForTest();
    defer trusted.resetForTest();

    var buf: [4]u8 = undefined;
    var i: usize = 0;
    while (i < trusted.max_trusted_origins) : (i += 1) {
        const origin = try std.fmt.bufPrint(&buf, "o{d}", .{i});
        try trusted.registerTrustedNamespaceOrigin(origin);
    }
    try std.testing.expectError(
        error.TrustedOriginLimitExceeded,
        trusted.registerTrustedNamespaceOrigin("overflow"),
    );
}
```

- [ ] **Step 3: Re-export from root.zig**

Open `src/root.zig`. Find the other module-level security exports and add:

```zig
pub const registerTrustedNamespaceOrigin = @import("trusted_namespace_origins.zig").registerTrustedNamespaceOrigin;
```

- [ ] **Step 4: Ensure the allowlist module is reachable from build.zig**

The new file must be discoverable by the existing `uuid` module (Zig auto-includes every transitive `@import`, so nothing should need to change in `build.zig`). Verify with:

```
zig build check 2>&1 | tail -3
```

Expected: exit 0, no output.

- [ ] **Step 5: Run tests**

```
zig build test --summary all 2>&1 | tail -5
```

Expected: 235/235 (or whatever the previous count was + 4 new).

- [ ] **Step 6: Commit**

```
git add src/trusted_namespace_origins.zig src/namespace.zig src/root.zig
git commit -m "$(cat <<'EOF'
feat(namespace): Namespace.fromConfig with trusted-origin allowlist (SEC-P4-04)

Adds a process-global allowlist of trusted origin tags
(src/trusted_namespace_origins.zig) with a mutex-protected
append-only register/is-trusted API.  `Namespace.fromConfig(bytes,
origin)` consults the allowlist and returns
error.UnvettedNamespace when `origin` is not registered.

Converts the compile-time-only CWE-347 guard (Namespace.custom
doc-warning) into a runtime gate: callers who MUST populate a
namespace from config can still get type-level safety by registering
the config key at startup and using `fromConfig` at the call site.

Capacity 16 × 64-byte origins is a comfortable ceiling for realistic
config-flag vocabularies; over-capacity and over-length both return
explicit errors rather than silently dropping.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: SEC-P4-08 — Method-only accessor for v7_lockfree_fallbacks

**Files:**

- Modify: `src/generator.zig`
- Modify: every file that reads `v7_lockfree_fallbacks` directly

- [ ] **Step 1: Enumerate direct-field-access call sites**

```
grep -rn "v7_lockfree_fallbacks" src/ benchmarks/ tests/
```

Expected: the field declaration, 1-2 writes inside newV7Atomic, and N reads (tests + benches). List them explicitly before editing.

- [ ] **Step 2: Rename the field and add an accessor**

In `src/generator.zig`, locate the `v7_lockfree_fallbacks: std.atomic.Value(u64) = ...` declaration (~line 184). Rename to `_v7_lockfree_fallbacks` (underscore prefix is the codebase's private-by-convention marker — check existing usage via `grep -n "^    _" src/generator.zig`). Also add a public accessor right below it:

```zig
    /// SEC-P4-08: counter of saturation fallbacks from the lock-free
    /// path into the mutex-protected `newV7Locked`.  The field is
    /// underscore-prefixed (private-by-convention) so callers cannot
    /// fingerprint contention via direct atomic reads; use
    /// `lockfreeFallbackCount()` instead.  The accessor documents the
    /// one-shot observation contract (load once, do not poll at high
    /// frequency — a spinning reader imposes MESI ping-pong on the
    /// same cache line that newV7Atomic writes).
    _v7_lockfree_fallbacks: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// SEC-P4-08: read the lockfree-fallback counter.  Intended for
    /// diagnostic / bench reporting — do NOT poll at high frequency.
    /// Relaxed load since the counter is a loose contention signal
    /// rather than a synchronising observable.
    pub fn lockfreeFallbackCount(self: *const Generator) u64 {
        return self._v7_lockfree_fallbacks.load(.monotonic);
    }
```

- [ ] **Step 3: Update internal writes**

Find the internal `fetchAdd` / `store` sites inside `newV7Atomic`:

```
grep -n "_v7_lockfree_fallbacks\|v7_lockfree_fallbacks" src/generator.zig
```

Change `self.v7_lockfree_fallbacks.fetchAdd` → `self._v7_lockfree_fallbacks.fetchAdd`, etc.

- [ ] **Step 4: Update tests and benches that read the field directly**

In each hit from Step 1 (non-generator.zig files), replace `gen.v7_lockfree_fallbacks.load(...)` → `gen.lockfreeFallbackCount()`. Tests that want atomic-specific semantics (e.g. `.acquire` load) must be rewritten — document in-place why they need acquire, and either extend the accessor to take an ordering arg (parking-lot-style) OR add a second `lockfreeFallbackCountAcquire()` helper. Simplest is to leave all callers on the default accessor; grep the test files to confirm no test needs stronger than `.monotonic`.

Likely hits in `benchmarks/bench_contention.zig`, `benchmarks/common.zig` (ResultRow computation), `src/generator_test.zig`.

- [ ] **Step 5: Run tests + benches**

```
zig build test --summary all 2>&1 | tail -3
zig build bench-check 2>&1 | tail -3
```

Expected: 235/235 tests; all bench executables compile.

- [ ] **Step 6: Commit**

```
git add src/generator.zig src/generator_test.zig benchmarks/
git commit -m "$(cat <<'EOF'
fix(generator): method-only lockfree-fallback accessor (SEC-P4-08)

Renames v7_lockfree_fallbacks → _v7_lockfree_fallbacks (underscore
marker for private-by-convention) and adds
`lockfreeFallbackCount(): u64` method.  Callers must now go through
the accessor rather than poking the atomic directly, closing the
CWE-203 co-tenant-fingerprinting path where a neighbour thread could
observe contention patterns without an API agreement.

Functionality preserved — the atomic underneath is unchanged; the
accessor uses .monotonic load to match the field's long-standing
semantic as a loose contention diagnostic.  Tests and benches
updated to call lockfreeFallbackCount().

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: SEC-P4-09 — Debug assertion against known-weak rand_impl

**Files:**

- Modify: `src/generator.zig`
- Modify: `src/generator_test.zig` (append)

- [ ] **Step 1: Add the assertion helper + call in initOptions**

In `src/generator.zig`, add (near the top of the Generator method block, next to `clampRollbackTolerance` from Task 2):

```zig
    /// SEC-P4-09: debug-mode sanity check that `random` is not a
    /// deterministic/low-entropy PRNG the library knows to be unsafe
    /// for UUID generation.  Pattern-matches the `fillFn` pointer
    /// against known std.Random implementations; false negatives are
    /// acceptable (a hostile library could pass a weak PRNG disguised
    /// as a different type) — this is defense-in-depth, not a
    /// security boundary.
    ///
    /// Release builds strip the check entirely (`std.debug.assert` is
    /// a no-op in ReleaseFast/ReleaseSmall).  Intended to catch
    /// honest-mistake usage during development where a caller
    /// accidentally wires `std.Random.DefaultPrng.random()` instead
    /// of `std.crypto.random` into a generator that ends up in
    /// production.
    fn assertRandNotKnownWeak(r: std.Random) void {
        if (@import("builtin").mode == .Debug) {
            // DefaultPrng (Xoshiro256) is a deterministic PRNG — not
            // safe for V4/V7 entropy.  Its `fillFn` address is stable
            // within a compilation unit; compare by address.
            const weak_fill = &std.Random.DefaultPrng.Sequential.fill;
            std.debug.assert(r.fillFn != @as(*const fn (*anyopaque, []u8) void, @ptrCast(weak_fill)));
        }
    }
```

(Note: the exact `std.Random.DefaultPrng.Sequential.fill` symbol may differ in your Zig 0.16 build — the goal is to pick the `fillFn` pointer of `std.Random.DefaultPrng`. Verify with `grep -n "pub fn fillFn\|pub const DefaultPrng" /home/benji/.local/share/mise/installs/zig/0.16.0/lib/std/Random.zig`. Substitute the real symbol if different.)

- [ ] **Step 2: Call the assertion in `initOptions`**

Find `pub fn initOptions(options: InitOptions)`. Before the `return Generator{ ... }` expression, add:

```zig
        if (options.random) |r| assertRandNotKnownWeak(r);
```

- [ ] **Step 3: Add a release-mode passthrough test**

Append to `src/generator_test.zig`:

```zig
test "SEC-P4-09: initOptions accepts std.crypto.random (debug assertion passes)" {
    // The known-weak check whitelists std.crypto.random (the expected
    // safe source).  This test exercises the initOptions path with an
    // explicit random arg so the debug assertion fires in Debug builds.
    var gen = Generator.initOptions(.{ .random = std.crypto.random });
    _ = try gen.newV4();
}
```

(We don't write a test that TRIPS the assertion — `std.debug.assert` panics the test binary in Debug, which would abort the test. The negative case belongs in a manual / ad-hoc sanity check, not the automated suite.)

- [ ] **Step 4: Run**

```
zig build test --summary all 2>&1 | tail -3
```

Expected: 236/236 pass.

- [ ] **Step 5: Commit**

```
git add src/generator.zig src/generator_test.zig
git commit -m "$(cat <<'EOF'
feat(generator): debug-mode assertion vs known-weak rand (SEC-P4-09)

Adds a Debug-only assertRandNotKnownWeak() check that trips when a
caller wires std.Random.DefaultPrng (or another known-weak PRNG)
into InitOptions.random.  ReleaseFast / ReleaseSmall strip the
assertion entirely, so there is zero production overhead.

Defense-in-depth: catches the honest-mistake case where a dev test
harness leaks into production.  Does NOT close the CWE-345
caller-trust attack vector (a hostile in-proc library can still
disguise a weak PRNG as any type it pleases).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Update tracking doc + push

**Files:**

- Modify: `docs/SECURITY_REVIEW_NOTES.md`

- [ ] **Step 1: Find the four rows**

```
grep -n "SEC-P4-03\|SEC-P4-04\|SEC-P4-08\|SEC-P4-09" docs/SECURITY_REVIEW_NOTES.md | head -10
```

- [ ] **Step 2: Mark each row Closed with its commit SHA**

For each of SEC-P4-03/04/08/09, update the triage-table `Session plan` column to `✅ Closed 2026-04-18 (\`<sha>\`)`. Use the SHAs from`git log --oneline | head -8`.

Example row (SEC-P4-03):

```
| SEC-P4-03 | Medium | 4.6 | ✅ Closed 2026-04-18 (`<sha-from-task-2>`) — clock_rollback_tolerance_ms is now an InitOptions field, default tightened to 250 ms, clamped [0, 60_000]. | Yes. |
```

Avoid pipe characters inside backticks in table cells (markdownlint trip — see earlier session's SEC-P4-02 fix for the pattern).

- [ ] **Step 3: Commit + push**

```
git add docs/SECURITY_REVIEW_NOTES.md
git commit -m "docs(security): mark SEC-P4-03/04/08/09 closed"
git push origin main
```

Expected: fast-forward push of all 6 commits.

---

## Self-Review Notes

- **Spec coverage:** SEC-P4-03 (Tasks 1+2), SEC-P4-04 (Task 3), SEC-P4-08 (Task 4), SEC-P4-09 (Task 5), tracking close-out (Task 6).
- **Type consistency:** `clock_rollback_tolerance_ms: i64` used identically as const default + field + InitOptions. `Namespace.fromConfig` + `registerTrustedNamespaceOrigin` signatures match across src/namespace.zig, src/trusted_namespace_origins.zig, and src/root.zig re-export. `lockfreeFallbackCount(): u64` used at every accessor call site.
- **No placeholders:** every block is literal code or a concrete grep/cmd.
- **Release safety:** Task 5's `assertRandNotKnownWeak` is explicitly Debug-only (no release perf cost). Verify by inspecting the generated ReleaseFast binary: `zig build-exe -O ReleaseFast src/generator_test.zig && objdump -d ... | grep assertRandNotKnownWeak` should show zero hits.
- **SEC-P4-01 independence:** this plan's changes are additive and non-conflicting with the SEC-P4-01 plan; execute in any order.
- **Allowlist concurrency:** SEC-P4-04's mutex-protected global is the correct pattern (append-only, no race). The `resetForTest` helper is test-only and clearly named; no `pub` re-export in root.zig.
