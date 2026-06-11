# 2026-06-11 Audit Gap Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every actionable gap from the 2026-06-11 audit cycle (GAP-DOC-17..21, QC-145/146/147/149, QC-112/124/125/126/127/128, PERF-60/61/62, SEC-P5-01/02) plus author the missing SEC-P4-14 plan file.

**Architecture:** All changes are small, independent fixes to an existing Zig 0.16.0 UUID library — no new subsystems. Code fixes get tests first (TDD) where a test can express the change; doc/config fixes get verification commands. Each task is one commit referencing its Gap-IDs.

**Tech Stack:** Zig 0.16.0, Python 3 (one pre-commit script), GitLab CI YAML, Markdown.

**Verification baseline (must still hold after every task):** `zig build check` exit 0; `zig build test --summary all` → 274 pass / 1 skip (plus any tests added by this plan); `zig build test-integration --summary all` → 37 pass (38 after Task 6 stays 37 — the guard removal doesn't change count; Task 7 adds tests to the unit suite); `zig fmt --check src/ build.zig tests/ benchmarks/ examples/` clean.

**GitLab issues to reference in commits:** QC-145 #179, QC-146 #180, QC-147 #181, QC-149 #182, GAP-DOC-17 #183, GAP-DOC-18 #184, GAP-DOC-19 #185, GAP-DOC-20 #186, GAP-DOC-21 #187, SEC-P4-14 #188, PERF-60 #189, SEC-P5-01 #190, SEC-P5-02 #191, PERF-61 #192, PERF-62 #193.

---

### Task 1: QC-145 — Fix `build.zig.zon` `.paths` (`bench` → `benchmarks`)

**Files:**
- Modify: `build.zig.zon:17`

- [ ] **Step 1: Edit `.paths`**

In `build.zig.zon`, replace the line `        "bench",` with `        "benchmarks",` (the `bench/` directory does not exist; the harness lives in `benchmarks/`).

- [ ] **Step 2: Verify**

Run: `ls bench 2>&1; ls -d benchmarks && zig build check && zig build bench-check -Doptimize=ReleaseFast`
Expected: `ls bench` errors (no such dir), `benchmarks` exists, both builds exit 0.

- [ ] **Step 3: Commit**

```bash
git add build.zig.zon
git commit -m "fix(packaging): ship benchmarks/ in package paths, drop stale bench entry (QC-145, #179)"
```

---

### Task 2: GAP-DOC-17 — Version string sync + CI consistency gate

**Files:**
- Modify: `src/root.zig:130`
- Modify: `README.md` (Library metadata table, ~line 233: `uuid.version` example)
- Modify: `.gitlab-ci.yml` (add lint-stage job)

- [ ] **Step 1: Update the constant**

In `src/root.zig:130`: `pub const version = "0.1.0";` → `pub const version = "0.1.1";`

- [ ] **Step 2: Update the README example**

In `README.md` Library metadata table: `| \`uuid.version\` | Library version string (e.g. \`"0.1.0"\`) |` → `(e.g. \`"0.1.1"\`)`.

- [ ] **Step 3: Add the CI gate**

In `.gitlab-ci.yml`, after the `zig-format` job (lint stage), add:

```yaml
# GAP-DOC-17: root.zig `version` must match build.zig.zon `.version`.
# Two sources of truth drifted at the v0.1.1 bump; this gate prevents a repeat.
version-consistency:
  stage: lint
  image: debian:bookworm-slim
  script:
    - ZON_V=$(grep -oP '\.version = "\K[^"]+' build.zig.zon)
    - ROOT_V=$(grep -oP 'pub const version = "\K[^"]+' src/root.zig)
    - echo "zon=$ZON_V root=$ROOT_V"
    - test "$ZON_V" = "$ROOT_V"
```

- [ ] **Step 4: Verify**

Run: `ZON_V=$(grep -oP '\.version = "\K[^"]+' build.zig.zon); ROOT_V=$(grep -oP 'pub const version = "\K[^"]+' src/root.zig); echo "$ZON_V vs $ROOT_V"; test "$ZON_V" = "$ROOT_V" && echo MATCH`
Expected: `0.1.1 vs 0.1.1` then `MATCH`. Then `zig build check` exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/root.zig README.md .gitlab-ci.yml
git commit -m "fix(version): sync root.zig version to 0.1.1 + CI consistency gate (GAP-DOC-17, #183)"
```

---

### Task 3: PERF-61 — Monotonic clock for V7 spin-sleeps

**Files:**
- Modify: `src/generator.zig:873` and `src/generator.zig:1020`

Context: both sites sleep a relative sub-millisecond duration to the next ms boundary, then re-read the clock (self-correcting). `.real` works, but `.awake` (CLOCK_MONOTONIC) is the semantically correct clock for a relative interval and removes NTP-slew sensitivity. `std.Io.Clock` in Zig 0.16 is `enum { real, awake, boot, cpu_process, cpu_thread }` (verified at `lib/std/Io.zig:721-769`).

- [ ] **Step 1: Edit both sleep sites**

At `src/generator.zig:873` (newV7Atomic `.sleep` arm) and `src/generator.zig:1020` (mutex spin path), change:
`io_h.sleep(.fromNanoseconds(@intCast(sleep_ns)), .real) catch {};`
→
`io_h.sleep(.fromNanoseconds(@intCast(sleep_ns)), .awake) catch {};`

Update the nearby comment at the mutex site if it mentions the clock (it does not; no comment change needed). Do NOT touch any other `.real` usages (state-file retry paths are out of scope; PERF-39 tracks those separately).

- [ ] **Step 2: Verify monotonicity tests still pass**

Run: `zig build test --summary all 2>&1 | tail -5`
Expected: 274 pass / 1 skip (V7 monotonicity + saturation tests included).

- [ ] **Step 3: Commit**

```bash
git add src/generator.zig
git commit -m "fix(perf): use monotonic (.awake) clock for V7 spin-sleep intervals (PERF-61, #192)"
```

---

### Task 4: PERF-62 — Strengthen main bench-contention gate + fix stale threshold comment

**Files:**
- Modify: `.gitlab-ci.yml:299` (bench-regression contention invocation)
- Modify: `.gitlab-ci.yml:357` (stale "5% on main" comment)

- [ ] **Step 1: Add `--runs 3` to the main gate**

Line 299: `- $TASKSET_PREFIX zig build bench-contention -Doptimize=ReleaseFast -- --output benchmarks/results/latest_contention.json`
→ `- $TASKSET_PREFIX zig build bench-contention -Doptimize=ReleaseFast -- --output benchmarks/results/latest_contention.json --runs 3`

- [ ] **Step 2: Fix the stale comment**

Line 357: `# PERF-46: contention gate at 10% on MR (bench-regression keeps 5% on main).`
→ `# PERF-46: contention gate at 10% on MR (bench-regression keeps 15% on main, PERF26_THRESHOLD).`

- [ ] **Step 3: Verify YAML validity**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.gitlab-ci.yml')); print('YAML OK')"` (if PyYAML missing: `glab ci lint` or skip with a note — the pre-commit `check-yaml` hook covers it at commit time since `.gitlab-ci.yml` is excluded from pretty-format but check-yaml validates).
Expected: YAML OK (or hook pass at commit).

- [ ] **Step 4: Commit**

```bash
git add .gitlab-ci.yml
git commit -m "ci(bench): use --runs 3 median for main contention gate; fix stale 5% comment (PERF-62, #193)"
```

---

### Task 5: PERF-60 + SEC-P5-01 — Harden + speed up `detect_diamond_deps.py`

**Files:**
- Modify: `scripts/detect_diamond_deps.py`
- Modify: `.gitignore` (add `__pycache__/`)

- [ ] **Step 1: Write a failing self-test command**

Run this BEFORE the changes to confirm current behavior (traversal hash accepted, symlink followed):

```bash
python3 - <<'EOF'
import sys; sys.path.insert(0, "scripts")
import detect_diamond_deps as d
from pathlib import Path
import tempfile, os
# 1. Traversal-shaped hash currently produces a path candidate (BAD):
p = d._zon_path_for_hash(Path("/tmp/nonexistent-root"), Path("/tmp/nonexistent-cache"), "../../etc")
print("traversal candidate:", p)  # None only because the file doesn't exist — no format guard
# 2. Symlink follow:
with tempfile.TemporaryDirectory() as td:
    root = Path(td); (root/"zig-pkg"/"h1").mkdir(parents=True)
    target = root/"secret.zon"; target.write_text(".{}")
    (root/"zig-pkg"/"h1"/"build.zig.zon").symlink_to(target)
    print("symlink followed:", d._zon_path_for_hash(root, Path("/nope"), "h1"))  # currently returns the symlink path
EOF
```

Expected (pre-fix): `symlink followed: <path>` (not None) — demonstrating the gap.

- [ ] **Step 2: Implement the three changes**

In `scripts/detect_diamond_deps.py`:

a. Import deque — in the import block add: `from collections import defaultdict, deque` (replacing the existing `from collections import defaultdict`).

b. Add the hash-format guard near `HASH_RE` (module level):

```python
# SEC-P5-01 (CWE-22): Zig package hashes are `<name>-<semver>-<base64url>`
# — strictly [A-Za-z0-9._-]. Reject anything else before the hash is used
# as a path component (blocks `../` traversal from a hostile manifest).
SAFE_HASH_RE = re.compile(r"^[A-Za-z0-9._-]{8,256}$")
```

c. In `_parse_dep_entries`, after `h = HASH_RE.search(body)` / `if not h: continue`, add:

```python
        if not SAFE_HASH_RE.match(h.group("hash")):
            print(
                f"notice: skipping dep '{name}' with non-conforming hash",
                file=sys.stderr,
            )
            continue
```

d. In `_zon_path_for_hash`, reject symlinks — replace both `if candidate.exists(): return candidate` blocks with:

```python
    candidate = project_root / "zig-pkg" / pkg_hash / "build.zig.zon"
    if candidate.exists() and not candidate.is_symlink():
        return candidate
    candidate = zig_global_cache / "p" / pkg_hash / "build.zig.zon"
    if candidate.exists() and not candidate.is_symlink():
        return candidate
    return None
```

e. In `collect_transitive`, switch the BFS queue to a deque (PERF-60):
`queue: List[Path] = [root_zon]` → `queue: deque[Path] = deque([root_zon])` and `zon_path = queue.pop(0)` → `zon_path = queue.popleft()`.

f. Update the docstring "Deliberately NOT in scope" bullet about hash-format validation: replace the `*   Validating the package-hash format itself. ...` bullet with:

```
*   Resolving WHY two hashes differ.  (Hash *format* is validated as of
    SEC-P5-01: non-conforming hashes are skipped with a notice, because
    the hash is used as a filesystem path component.)
```

- [ ] **Step 3: Re-run the Step 1 self-test — now passing**

Same script as Step 1. Expected (post-fix): `symlink followed: None`. Also run:

```bash
python3 - <<'EOF'
import sys; sys.path.insert(0, "scripts")
import detect_diamond_deps as d
assert d.SAFE_HASH_RE.match("json-0.1.4-tOue4cGpCwBArfMl05wHmwv39pKM9-tjODxrMFm_sIk3")
assert d.SAFE_HASH_RE.match("thread_pool-0.2.4-11B1BnyUdgCUNlqgBwHNvE4plLwP1s1MAyCjODPafrpo")
assert not d.SAFE_HASH_RE.match("../../etc")
assert not d.SAFE_HASH_RE.match("a/b")
print("SAFE_HASH_RE OK")
EOF
```

Then end-to-end: `python3 scripts/detect_diamond_deps.py` from the repo root.
Expected: `SAFE_HASH_RE OK`; script exits 0 or 2 (2 = cache not populated, soft-pass) with no traceback.

- [ ] **Step 4: gitignore pycache**

Append `__pycache__/` to `.gitignore` and `rm -rf scripts/__pycache__`.

- [ ] **Step 5: Commit**

```bash
git add scripts/detect_diamond_deps.py .gitignore
git commit -m "fix(scripts): validate pkg hash format, reject symlinks, O(1) BFS dequeue (SEC-P5-01 #190, PERF-60 #189)"
```

---

### Task 6: QC-146 — Remove stale XFAIL guard from integration test

**Files:**
- Modify: `tests/integration.zig:455-478`

- [ ] **Step 1: Remove the guard**

In `tests/integration.zig`:

a. Section banner (lines ~455-458): change

```zig
// =============================================================================
// GAP-DOC-08.2: v3→v2 downgrade rejected when state_mac_key set (SEC-P4-01,
// currently XFAIL — activates when SEC-P4-01 lands StateVersionDowngrade).
// =============================================================================
```

to

```zig
// =============================================================================
// GAP-DOC-08.2: v3→v2 downgrade rejected when state_mac_key set (SEC-P4-01).
// =============================================================================
```

b. Test name: `test "integration: v3→v2 downgrade rejected when state_mac_key set (SEC-P4-01, currently XFAIL)"` → `test "integration: v3→v2 downgrade rejected when state_mac_key set (SEC-P4-01)"`.

c. Delete the entire stale block inside the test — the `// AUDIT NOTE: ...` comment (9 lines), the `const has_variant = comptime blk: { ... };` block, and the `if (!has_variant) { return error.SkipZigTest; }` block — so the test body starts directly at `var tmp = std.testing.tmpDir(.{});`. `StateVersionDowngrade` landed in `src/uuid.zig:123`, so the guard is dead code (QC-146).

- [ ] **Step 2: Verify the test still runs and passes**

Run: `zig build test-integration --summary all 2>&1 | tail -3`
Expected: 37/37 pass (the test was already executing; only dead code removed).

- [ ] **Step 3: Commit**

```bash
git add tests/integration.zig
git commit -m "test: drop dead XFAIL guard from SEC-P4-01 downgrade test (QC-146, #180)"
```

---

### Task 7: QC-147 — Delegation tests for 7 module-level wrappers

**Files:**
- Modify: `src/versions.zig` (append tests after the existing QC-30 delegation tests)

Follow the existing QC-30 test pattern (versions.zig:233-318). The state-file tests need an absolute path — use the tmpDir pattern from `tests/integration.zig:478-487`. These tests mutate the process-global `default_generator`; each test restores neutral state (`secureWipeMacKey` → key null) before returning.

- [ ] **Step 1: Append the tests**

After the last QC-30/SEC-P3-05 test in `src/versions.zig`, add:

```zig
// QC-147: delegation tests for the 7 wrappers added after QC-30.

test "top-level newV3Bounded delegates and enforces cap (QC-147)" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = try newV3Bounded(ns, "www.example.com", 64);
    const expected = newV3(ns, "www.example.com");
    try std.testing.expectEqual(expected, u);
    try std.testing.expectError(
        uuid_mod.Error.NameTooLong,
        newV3Bounded(ns, "www.example.com", 4),
    );
}

test "top-level newV5Bounded delegates and enforces cap (QC-147)" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = try newV5Bounded(ns, "www.example.com", 64);
    const expected = newV5(ns, "www.example.com");
    try std.testing.expectEqual(expected, u);
    try std.testing.expectError(
        uuid_mod.Error.NameTooLong,
        newV5Bounded(ns, "www.example.com", 4),
    );
}

test "top-level saveState/loadState delegate to default_generator (QC-147)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buf);
    var path_buf: [std.fs.max_path_bytes + 64]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/.zig-cache/tmp/{s}/qc147.state",
        .{ cwd_buf[0..cwd_len], tmp.sub_path[0..] },
    );

    _ = try newV7(); // ensure default_generator has V7 state to persist
    try saveState(path);
    try loadState(path); // round-trip through the module-level wrappers
}

test "top-level migrateStateToV3 delegates to default_generator (QC-147)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buf);
    var path_buf: [std.fs.max_path_bytes + 64]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/.zig-cache/tmp/{s}/qc147-migrate.state",
        .{ cwd_buf[0..cwd_len], tmp.sub_path[0..] },
    );

    // Save a v2 (keyless) file via the module wrapper, then migrate under a key.
    defer secureWipeMacKey(); // restore global key-null state for other tests
    _ = try newV7();
    try saveState(path); // v2 — no key configured
    gen_mod.default_generator.state_mac_key = .{0x42} ** 32;
    try migrateStateToV3(path);
    try loadState(path); // v3 file now loads under the configured key
}

test "top-level rotateStateMacKey + secureWipeMacKey delegate (QC-147)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buf);
    var path_buf: [std.fs.max_path_bytes + 64]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/.zig-cache/tmp/{s}/qc147-rotate.state",
        .{ cwd_buf[0..cwd_len], tmp.sub_path[0..] },
    );

    defer secureWipeMacKey(); // always restore global key-null state
    gen_mod.default_generator.state_mac_key = .{0x11} ** 32;
    _ = try newV7();
    try saveState(path); // v3 under the old key
    try rotateStateMacKey(path, .{0x22} ** 32);
    try loadState(path); // authenticates under the new key

    secureWipeMacKey();
    try std.testing.expect(gen_mod.default_generator.state_mac_key == null);
}
```

Note: if `uuid_mod.Error` is not the error-set symbol available in versions.zig, check the file's imports (`const uuid_mod = @import("uuid.zig");` exists per the QC-30 tests using `uuid_mod.Version`) — `uuid_mod.Error.NameTooLong` is correct.

- [ ] **Step 2: Run the new tests**

Run: `zig build test --summary all 2>&1 | tail -5`
Expected: 279 pass / 1 skip (274 + 5 new).

- [ ] **Step 3: Format check, then commit**

Run: `zig fmt src/versions.zig && zig build test --summary all 2>&1 | tail -3`

```bash
git add src/versions.zig
git commit -m "test: add delegation tests for 7 module-level wrappers (QC-147, #181)"
```

---

### Task 8: SEC-P5-02 — Align security contact addresses

**Files:**
- Modify: `.well-known/security.txt:11`

Decision (recorded in SECURITY_REVIEW_NOTES Phase 5): primary contact = `security@codepros.dev` (org-wide convention: conduct@/support@codepros.dev); keep `benji@codepros.org` as secondary. SECURITY.md already says `security@codepros.dev` — unchanged.

- [ ] **Step 1: Edit security.txt**

Replace line 11 `Contact: mailto:benji@codepros.org` with:

```
Contact: mailto:security@codepros.dev
Contact: mailto:benji@codepros.org
```

(RFC 9116 §2.5.3: multiple Contact fields allowed, listed in order of preference.)

- [ ] **Step 2: Verify**

Run: `grep -c "^Contact:" .well-known/security.txt && grep "security@codepros.dev" SECURITY.md .well-known/security.txt`
Expected: `2`, and the .dev address present in both files.

- [ ] **Step 3: Commit**

```bash
git add .well-known/security.txt
git commit -m "fix(security): align disclosure contacts across security.txt and SECURITY.md (SEC-P5-02, #191)"
```

---

### Task 9: GAP-DOC-18 + GAP-DOC-19 — README install refs + CHANGELOG 0.1.1

**Files:**
- Modify: `README.md:25,37,43-45`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: README install fixes (GAP-DOC-18)**

a. Line 25: `zig fetch --save https://gitlab.com/devnw/zig/uuid/-/archive/v0.1.0/uuid-v0.1.0.tar.gz` → `...archive/v0.1.1/uuid-v0.1.1.tar.gz`
b. Line ~37 (reference snippet): `.url = "https://gitlab.com/devnw/zig/uuid/-/archive/v0.1.0/uuid-v0.1.0.tar.gz",` → `v0.1.1/uuid-v0.1.1.tar.gz`
c. Delete the stale note block (lines ~43-45):

```markdown
> Note: v0.1.0 is unreleased; until the tag is published, point `.url` at a
> specific commit archive (`.../archive/<sha>.tar.gz`) and re-run
> `zig fetch --save` to refresh the hash.
```

(both v0.1.0 and v0.1.1 tags are published — the note is obsolete; remove it entirely.)

- [ ] **Step 2: CHANGELOG 0.1.1 section (GAP-DOC-19)**

The v0.1.1 tag (2026-05-02, commit `17ee3dc`) shipped everything currently under `## [Unreleased]`. Restructure:

a. Insert directly under `## [Unreleased]` a fresh empty-but-valid block and the new release heading, moving ALL existing Unreleased content under it:

```markdown
## [Unreleased]

### Fixed

- `src/root.zig` `version` constant synced to the package version (`0.1.1`)
  with a CI consistency gate (GAP-DOC-17).
- `.paths` in `build.zig.zon` now ships `benchmarks/` (the stale `bench`
  entry pointed at a directory removed in the benchmark-suite rewrite)
  (QC-145).
- V7 spin-sleep intervals use the monotonic (`.awake`) clock (PERF-61).
- `scripts/detect_diamond_deps.py`: package-hash format validation +
  symlink rejection before cache reads (SEC-P5-01); O(1) BFS dequeue
  (PERF-60).
- Disclosure contacts aligned across `SECURITY.md` and
  `.well-known/security.txt` (SEC-P5-02).

## [0.1.1] - 2026-05-02
```

b. The previous Unreleased content (the `### Release Notes -- 2026-04-18..` paragraph through the last pre-`## [0.1.0]` line) now sits under `## [0.1.1] - 2026-05-02`.

c. Update the link refs at the bottom:

```markdown
[Unreleased]: https://gitlab.com/devnw/zig/uuid/-/compare/v0.1.1...HEAD
[0.1.1]: https://gitlab.com/devnw/zig/uuid/-/compare/v0.1.0...v0.1.1
[0.1.0]: https://gitlab.com/devnw/zig/uuid/-/releases/v0.1.0
```

- [ ] **Step 3: Verify**

Run: `grep -n "v0.1.0/uuid-v0.1.0" README.md; grep -n "unreleased" README.md; grep -n "^## \[" CHANGELOG.md; grep -n "^\[" CHANGELOG.md | tail -3`
Expected: no v0.1.0 archive refs, no stale unreleased note, headings `[Unreleased]`, `[0.1.1] - 2026-05-02`, `[0.1.0] - 2026-03-21`, three link refs.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs(release): point install at v0.1.1, add CHANGELOG 0.1.1 section (GAP-DOC-18 #184, GAP-DOC-19 #185)"
```

---

### Task 10: GAP-DOC-20 + GAP-DOC-21 — docs index links + REQUIREMENTS citation

**Files:**
- Modify: `docs/README.md` (Quick Links)
- Modify: `docs/REQUIREMENTS.md:57`

- [ ] **Step 1: docs index (GAP-DOC-20)**

In `docs/README.md` Quick Links, after the `[Gap Analyses](GAP_ANALYSIS.md)` line add:

```markdown
- [AppSec Review 2026-06-11](APPSEC_REVIEW_2026-06-11.md) — OWASP 2025 + CIS v8.1.2 defensive code review
- [Security Review Notes](SECURITY_REVIEW_NOTES.md) — running ledger of all security review cycles
```

- [ ] **Step 2: REQUIREMENTS citation (GAP-DOC-21)**

Line 57: `| UUID-TEST-005 | Cross-compile smoke test for x86_64/aarch64 Linux, x86_64/aarch64 macOS, x86_64 Windows. | \`build.zig\` (\`check-cross\` step) |` — replace the evidence cell with `` `.gitlab-ci.yml` (`test-cross-build` job) `` (the `check-cross` build step was removed; coverage lives in CI).

- [ ] **Step 3: Verify**

Run: `grep -n "APPSEC_REVIEW\|SECURITY_REVIEW_NOTES" docs/README.md && grep -n "test-cross-build" docs/REQUIREMENTS.md && ! grep -n "check-cross" docs/REQUIREMENTS.md`
Expected: both links present; citation updated; no `check-cross` left.

- [ ] **Step 4: Commit**

```bash
git add docs/README.md docs/REQUIREMENTS.md
git commit -m "docs: index appsec/security docs, fix UUID-TEST-005 citation (GAP-DOC-20 #186, GAP-DOC-21 #187)"
```

---

### Task 11: QC-149 + QC-124 + QC-112 — generator.zig doc-comment completions

**Files:**
- Modify: `src/generator.zig:13-15` (type aliases), `:1354-1367` (Strict pair), `:2305-2322` (default_generator)

- [ ] **Step 1: QC-124 — document the function-pointer type aliases**

Replace lines 13-15:

```zig
pub const ClockFn = *const fn () i128;
pub const RandFn = *const fn (buf: []u8) anyerror!void;
pub const HWAddrFn = *const fn () Error![6]u8;
```

with:

```zig
/// Injectable wall-clock source: returns nanoseconds since the Unix epoch
/// (UTC), matching `std.time.nanoTimestamp`. Used by V1/V6/V7 generation.
pub const ClockFn = *const fn () i128;

/// Injectable CSPRNG source: fills `buf` with random bytes or returns an
/// error (mapped to `Error.RandomError` at the call site). Must be
/// cryptographically secure for production use — V4/V7 entropy and V1/V6
/// clock sequences derive from it.
pub const RandFn = *const fn (buf: []u8) anyerror!void;

/// Injectable hardware-address source: returns a 6-byte IEEE-802 MAC or
/// `Error.NoHWAddressFound`. Only consulted when a Generator is configured
/// to embed a real node ID in V1/V6 (privacy default is a random
/// multicast node).
pub const HWAddrFn = *const fn () Error![6]u8;
```

- [ ] **Step 2: QC-149 — Errors blocks for the Strict pair**

In the `newV3Strict` doc comment (ends `...as the namespace.`), append a final line before the `pub fn`:

```zig
    ///
    /// **Errors:** none — infallible (`UUID`, not `Error!UUID`): deterministic
    /// hashing with no clock, RNG, or I/O involved.
```

Same addition to `newV5Strict` (its doc is one line `/// SEC-P3-05: strict V5 wrapper — see \`newV3Strict\`.` — append the same `**Errors:**` block after it).

- [ ] **Step 3: QC-112 — complete the default_generator contract**

In the `default_generator` doc comment (line ~2305), after the `**SEC-11 / CWE-362 — Shared mutable state:**` paragraph, insert:

```zig
///
/// **Thread-safety:** every method on this instance is thread-safe — the
/// split `v7`/`v1v6` mutexes (and the lock-free V7 CAS word) protect all
/// internal state. What is NOT protected is the variable binding itself:
/// do not reassign `default_generator` (`default_generator = Generator.init()`)
/// while other threads may be calling into it — reassignment is not
/// synchronized and races with in-flight calls.
///
/// **State-file path agreement:** module-level `saveState`/`loadState`/
/// `migrateStateToV3`/`rotateStateMacKey` all operate on THIS instance.
/// Callers must use a consistent absolute path across those calls; mixing
/// paths across processes that share a state file is the caller's contract.
```

- [ ] **Step 4: Verify + commit**

Run: `zig fmt src/generator.zig && zig build test --summary all 2>&1 | tail -3`
Expected: 279 pass / 1 skip (count from Task 7).

```bash
git add src/generator.zig
git commit -m "docs(api): document fn-pointer aliases, Strict infallibility, default_generator contract (QC-124, QC-149 #182, QC-112)"
```

---

### Task 12: QC-125 + QC-126 + QC-127 + QC-128 — README API accuracy consolidation

**Files:**
- Modify: `README.md` (~:443 interface snippet, :419-424 error set, :214-219 contexts table, :221-223 namespace section)

- [ ] **Step 1: QC-125 — fix the non-compiling interface snippet**

At ~line 443: `const gi: uuid.GeneratorInterface = gen.interface();` → `const gi = uuid.GeneratorInterface.fromGenerator(&gen);` (there is no `Generator.interface()` method; `fromGenerator` is the real API, generator.zig:2420).

- [ ] **Step 2: QC-126 — complete the Full Error Set section**

Replace the section body (`\`uuid.Error\` is the library's error set. Members added since v0.1.0:` + the single `StateMacMismatch` bullet) with:

```markdown
`uuid.Error` is the library's complete error set (`src/uuid.zig`):

| Variant | Raised by |
|---------|-----------|
| `InvalidFormat` | `fromString` — unrecognized layout; also state-file header corruption |
| `InvalidLength` | `fromString` — input length matches no supported format |
| `InvalidBraces` | `fromString` — unbalanced `{`/`}` wrapper |
| `InvalidURNPrefix` | `fromString` — URN form without `urn:uuid:` prefix |
| `InvalidDashes` | `fromString` — dashes at wrong offsets |
| `IncorrectByteLength` | `fromBytes` / `fromBytesLE` — slice length ≠ 16 |
| `NoHWAddressFound` | hardware-address resolution found no usable MAC |
| `InvalidVersion` | version-specific accessor on a mismatched UUID (e.g. `timestampFromV7` on a V4) |
| `RandomError` | injected `RandFn` failed |
| `InvalidTimestamp` | timestamp outside representable range; also V7 retry exhaustion under a frozen clock |
| `StateIoFailure` | `saveState`/`loadState` — underlying filesystem error |
| `StateMacMismatch` | `loadState` — HMAC tag mismatch (tampered file) or v3 file with no key configured |
| `StateVersionDowngrade` | `loadState` — v1/v2 file rejected while a `state_mac_key` is set (SEC-P4-01) |
| `NameTooLong` | `newV3Bounded`/`newV5Bounded` — `name.len` exceeds the caller's cap |
```

- [ ] **Step 3: QC-127 — deduplicate the contexts tables**

Replace the upper `### HashMap contexts` block (table with 2 rows at ~:214-219) with a pointer to the complete section:

```markdown
### HashMap contexts

Three `HashContext` variants are available — see
[Hash Contexts](#hash-contexts) below for the full comparison table
(`HashContext`, `ProcessHashContext`, `SecureHashContext`).
```

- [ ] **Step 4: QC-128 — complete the Namespace section**

Replace the `### Namespace constants` body (currently just the four constants line) with:

```markdown
### Namespaces

| Symbol | Description |
|--------|-------------|
| `namespace_dns` / `namespace_url` / `namespace_oid` / `namespace_x500` | RFC-9562 §6.6 well-known namespace UUIDs |
| `Namespace` | Closed tagged union over the four RFC namespaces plus a vetted `.custom` arm — use with `newV3Strict`/`newV5Strict` so the type system rejects attacker-controlled namespace UUIDs (SEC-P3-05) |
| `Namespace.fromConfig(uuid, origin)` | Construct a `.custom` namespace from configuration, recording its trusted origin |
| `registerTrustedNamespaceOrigin(origin)` | Register a trusted origin label for `.custom` namespaces (SEC-P4-04) |
| `isTrusted(ns)` | Check whether a namespace's origin has been registered as trusted |
```

NOTE: before writing the table, verify the exact public signatures with `grep -n "pub fn fromConfig\|pub fn registerTrustedNamespaceOrigin\|pub fn isTrusted" src/namespace.zig src/trusted_namespace_origins.zig src/root.zig` and adjust parameter lists in the table to match reality. Keep the existing nil/max paragraph that follows the section.

- [ ] **Step 5: Verify + commit**

Run: `grep -n "gen.interface()" README.md; grep -c "StateVersionDowngrade\|NameTooLong" README.md`
Expected: no `gen.interface()` matches; error variants present.

```bash
git add README.md
git commit -m "docs(readme): fix interface snippet, complete error set + namespace API, dedupe context tables (QC-125..128)"
```

---

### Task 13: SEC-P4-14 — Author the missing unblock plan file

**Files:**
- Create: `docs/superpowers/plans/2026-04-19-sec-p4-ci-catalog-sha-pins.md`

This file is referenced by `docs/GAP_ANALYSIS.md`, issue #188, and the appsec report, but was never committed. Author it now so the references resolve.

- [ ] **Step 1: Write the plan file**

```markdown
# SEC-P4-14: Pin ci-catalog Components by Commit SHA

> Referenced by GAP_ANALYSIS.md (SEC-P4-14) and GitLab issue #188.
> Status: BLOCKED-EXTERNAL — requires an operator-supplied tag→SHA map
> for `gitlab.com/devnw/ci-catalog` (no read credentials from this repo's
> automation context).

## Problem

`.gitlab-ci.yml` includes 8 CI catalog components pinned by moving tags
(`@v1.7.1` ×7, `@v1.2.1` ×1). A moved tag executes unreviewed code in this
project's CI with release/SBOM privileges (CWE-494/CWE-1357, OWASP A03).

## Prerequisite (operator action)

Run, with ci-catalog read access:

​```bash
git ls-remote https://gitlab.com/devnw/ci-catalog.git \
  refs/tags/v1.7.1 refs/tags/v1.2.1
​```

Record the two commit SHAs.

## Steps (once SHAs are supplied)

1. In `.gitlab-ci.yml`, replace each `@v1.7.1` with `@<sha-of-v1.7.1>` and
   `zig-format@v1.2.1` with `@<sha-of-v1.2.1>`, keeping the tag in a
   trailing comment: `# v1.7.1`.
2. Push a branch; confirm all 8 components still resolve (GitLab resolves
   component refs by SHA identically to tags) and the pipeline is green.
3. Record the tag→SHA map and rotation procedure in
   `docs/runbooks/ci-catalog-sha-rotation.md` (create it from this plan's
   steps; fold in the H-1 APT-pin note per the appsec report).
4. Close SEC-P4-14 (#188) with the pipeline evidence; mark H-1 resolved in
   the same commit if the runbook lands.

## Rotation procedure (future upgrades)

On each ci-catalog release: re-run the `git ls-remote` above for the new
tag, review the component diff between the old and new SHAs, update the 8
pins in one commit titled `ci: bump ci-catalog to <tag> (<sha>)`.
```

(Use a real fenced code block — the `​` zero-width markers above only escape this plan's own fencing.)

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-04-19-sec-p4-ci-catalog-sha-pins.md
git commit -m "docs(plans): author referenced SEC-P4-14 ci-catalog SHA-pin plan (#188)"
```

---

### Task 14: Full verification sweep

- [ ] **Step 1: Run everything**

```bash
zig fmt --check src/ build.zig tests/ benchmarks/ examples/ \
  && zig build check \
  && zig build test --summary all 2>&1 | tail -3 \
  && zig build test-integration --summary all 2>&1 | tail -3 \
  && zig build test -Doptimize=ReleaseSafe --summary all 2>&1 | tail -3 \
  && zig build examples \
  && zig build bench-check -Doptimize=ReleaseFast \
  && python3 scripts/detect_diamond_deps.py; echo "diamond rc=$?"
```

Expected: fmt clean; 279 pass / 1 skip unit (Debug and ReleaseSafe); 37/37 integration; examples + bench-check exit 0; diamond rc 0 or 2.

- [ ] **Step 2: Push**

```bash
git push origin main
```

(then watch CI — `glab ci status` — and fix any failure before closing issues.)
