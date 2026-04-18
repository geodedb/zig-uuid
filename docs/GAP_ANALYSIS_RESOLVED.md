# Gap Analysis -- Resolved

> Mirror of resolved items that were previously tracked in `docs/GAP_ANALYSIS.md`
> and the GitLab issue tracker. The issue tracker is authoritative.
>
> Last updated: 2026-04-18 (Phase 3 closure cycle — 16 new resolutions appended)

## Summary

- **25 prior tracker items** (Cycles 12–13): resolved in-code; still marked open on the GitLab tracker; closure queued in the Phase-3 `glab` block in `docs/GAP_ANALYSIS.md`.
- **16 Phase-3 closure-cycle items** (2026-04-18): closed this cycle (see "Phase 3 Closure Cycle" section below). These items are tracked in docs only — they do not have dedicated GitLab work items.

Evidence for each resolution is pinned to a concrete file:line, commit SHA, or test output.

---

## Security -- Cycle 12

### SEC-R12-02: `Timestamp.fromUnixNano` secondary u64 addition overflow [RESOLVED]

- **Issue:** [#154](https://gitlab.com/devnw/zig/uuid/-/work_items/154) (still open on tracker)
- **Category:** Security / CWE-190
- **Severity:** Info
- **Resolution:** `max_safe` guard added before the `intervals_since_unix + gregorian_offset` addition.
- **Evidence:** `src/timestamp.zig:89-94` -- guard checks `intervals_since_unix > maxInt(u64) - gregorian_offset`.
- **Tests:** 172/172 pass on Zig 0.16.0.
- **Resolved date:** 2026-03-22

---

## Security -- Cycle 13

### SEC-R13-01: V7 spin-wait double `self.clock()` invocation [RESOLVED]

- **Issue:** [#156](https://gitlab.com/devnw/zig/uuid/-/work_items/156) (still open on tracker)
- **Category:** Security / CWE-362 (TOCTOU)
- **Severity:** Medium
- **Resolution:** Single `self.clock()` read cached before the spin-wait loop.
- **Evidence:** `src/generator.zig` V7 timestamp path; see `docs/GAP_ANALYSIS.md:3122-3139`.
- **Resolved date:** 2026-03-22

### SEC-R13-03: Fuzz corpus missing SEC-R12-02 overflow boundary [RESOLVED]

- **Issue:** [#158](https://gitlab.com/devnw/zig/uuid/-/work_items/158) (still open on tracker)
- **Category:** Security / CWE-754
- **Severity:** Low
- **Resolution:** Two fuzz corpus entries added at the SEC-R12-02 overflow boundary.
- **Evidence:** `src/fuzz.zig:184-197` -- nano_corpus extended with boundary seeds.
- **Resolved date:** 2026-03-22

### SEC-R13-04: `loadState` undefined buffer leaves bytes 22-31 uninitialized [RESOLVED]

- **Issue:** [#159](https://gitlab.com/devnw/zig/uuid/-/work_items/159) (still open on tracker)
- **Category:** Security / CWE-908
- **Severity:** Medium
- **Resolution:** Replaced `var buf: [state_size]u8 = undefined` with `std.mem.zeroes([state_size]u8)`.
- **Evidence:** `src/generator.zig:644` -- `buf` is zero-initialised.
- **Resolved date:** 2026-03-22

### SEC-R13-06: Linux SIOCGIFCONF truncation is dead empty block [RESOLVED]

- **Issue:** [#161](https://gitlab.com/devnw/zig/uuid/-/work_items/161) (still open on tracker)
- **Category:** Security / CWE-390 (observability)
- **Severity:** Low
- **Resolution:** Dead empty block replaced with `std.log.warn` on truncation.
- **Evidence:** `src/hwaddr/linux.zig:57-61`.
- **Resolved date:** 2026-03-22

### SEC-R13-07: SECURITY.md missing PGP / CVSS / EOL policy [RESOLVED]

- **Issue:** [#164](https://gitlab.com/devnw/zig/uuid/-/work_items/164) (still open on tracker)
- **Category:** Security / Process
- **Severity:** Info
- **Resolution:** Added encrypted reporting channel, CVSS v3.1 severity table, and version support matrix.
- **Evidence:** `SECURITY.md` (all three sections present).
- **Resolved date:** 2026-03-22

### SEC-R13-08: `loadState` may call `self.clock()` under mutex [RESOLVED]

- **Issue:** [#167](https://gitlab.com/devnw/zig/uuid/-/work_items/167) (still open on tracker)
- **Category:** Security / CWE-833 (availability)
- **Severity:** Low
- **Resolution:** Cached `clockToMs(self.clock())` before `self.mutex.lock()`.
- **Evidence:** `src/generator.zig:628-701` -- clock read precedes the lock acquisition.
- **Resolved date:** 2026-03-22

---

## Performance -- Cycle 4

### PERF-19: Single mutex serializes V7 and V1/V6 clock domains [RESOLVED]

- **Issue:** [#155](https://gitlab.com/devnw/zig/uuid/-/work_items/155) (still open on tracker)
- **Category:** Performance / Concurrency
- **Severity:** P2/P3, PerfScore 24
- **Resolution:** Dual-mutex architecture separating V7 and V1/V6 clock state.
- **Evidence:** `src/generator.zig:89` and surrounding mutex declarations.
- **Resolved date:** 2026-03-22

### PERF-20: `toHex` (lowercase no-alloc) missing from benchmark suite [RESOLVED]

- **Issue:** [#157](https://gitlab.com/devnw/zig/uuid/-/work_items/157) (still open on tracker)
- **Category:** Performance / Coverage
- **Severity:** P3, PerfScore 8
- **Resolution:** `toHex` lowercase no-alloc variant added to benchmark suite.
- **Evidence:** `bench/main.zig`.
- **Resolved date:** 2026-03-22

---

## Quality -- Cycle 12

### QC-76: `Generator.init`, `withClock`, `withRand` missing doc comments [RESOLVED]

- **Issue:** [#160](https://gitlab.com/devnw/zig/uuid/-/work_items/160) (still open on tracker)
- **Severity:** Low (Score 24)
- **Resolution:** Doc comments added for `init`, `withClock`, `withRand`.
- **Evidence:** `src/generator.zig:105-118`.
- **Resolved date:** 2026-03-22

### QC-77: `Variant` enum has no doc comment [RESOLVED]

- **Issue:** [#162](https://gitlab.com/devnw/zig/uuid/-/work_items/162) (still open on tracker)
- **Severity:** Low (Score 24)
- **Resolution:** Doc comment added to `Variant` enum.
- **Evidence:** `src/uuid.zig:38-43`.
- **Resolved date:** 2026-03-22

### QC-78: `Generator.newV4` has no doc comment [RESOLVED]

- **Issue:** [#163](https://gitlab.com/devnw/zig/uuid/-/work_items/163) (still open on tracker)
- **Severity:** Low (Score 24)
- **Resolution:** Doc comment added.
- **Evidence:** `src/generator.zig:142`.
- **Resolved date:** 2026-03-22

### QC-79: All 10 `GeneratorInterface` dispatch methods missing doc comments [RESOLVED]

- **Issue:** [#165](https://gitlab.com/devnw/zig/uuid/-/work_items/165) (still open on tracker)
- **Severity:** Low (Score 24)
- **Resolution:** Doc comments added to all 10 dispatch methods.
- **Evidence:** `src/generator.zig:755-784`.
- **Resolved date:** 2026-03-22

### QC-81: `newV8` return type documentation gap [RESOLVED]

- **Issue:** [#168](https://gitlab.com/devnw/zig/uuid/-/work_items/168) (still open on tracker)
- **Severity:** Low (Score 20)
- **Resolution:** `newV8` return type changed from `Error!UUID` to `UUID` (infallible).
- **Evidence:** `src/versions.zig:63`.
- **Resolved date:** 2026-03-22

### QC-82: Double export `uuid.nil`/`uuid.UUID.nil`; README wrong form [RESOLVED]

- **Issue:** [#169](https://gitlab.com/devnw/zig/uuid/-/work_items/169) (still open on tracker)
- **Severity:** Low (Score 16)
- **Resolution:** Single canonical export; README updated to the correct form.
- **Evidence:** `src/root.zig:42-43`.
- **Resolved date:** 2026-03-22

### QC-83: `Timestamp.toUnixNano` absent from README [RESOLVED]

- **Issue:** [#170](https://gitlab.com/devnw/zig/uuid/-/work_items/170) (still open on tracker)
- **Severity:** Low (Score 16)
- **Resolution:** README timestamp section now lists `toUnixNano`.
- **Evidence:** `src/timestamp.zig:38`; README "Timestamp Helpers".
- **Resolved date:** 2026-03-22

### QC-84: `Timestamp.fromUnixNano`/`fromUnixMs` absent from README [RESOLVED]

- **Issue:** [#171](https://gitlab.com/devnw/zig/uuid/-/work_items/171) (still open on tracker)
- **Severity:** Low (Score 16)
- **Resolution:** Both functions documented in README.
- **Evidence:** `src/timestamp.zig:78,92`.
- **Resolved date:** 2026-03-22

### QC-85: No test for infallible `newV8` path [RESOLVED]

- **Issue:** [#172](https://gitlab.com/devnw/zig/uuid/-/work_items/172) (still open on tracker)
- **Severity:** Low (Score 12)
- **Resolution:** Test added covering `newV8` infallibility.
- **Evidence:** `src/generator.zig:494` and surrounding tests.
- **Resolved date:** 2026-03-22

### QC-86: `newV7AtTime` full error set undocumented [RESOLVED]

- **Issue:** [#173](https://gitlab.com/devnw/zig/uuid/-/work_items/173) (still open on tracker)
- **Severity:** Low (Score 12)
- **Resolution:** Doc comment expanded to list full error set.
- **Evidence:** `src/generator.zig:172-176`.
- **Resolved date:** 2026-03-22

### QC-87: `Timestamp.now()` doc silent on injectable-clock bypass [RESOLVED]

- **Issue:** [#174](https://gitlab.com/devnw/zig/uuid/-/work_items/174) (still open on tracker)
- **Severity:** Info (Score 8)
- **Resolution:** Doc comment now states the function bypasses `withClock` injection.
- **Evidence:** `src/timestamp.zig:25`.
- **Resolved date:** 2026-03-22

### QC-88: No test asserts `newV1`/`newV6` bypass the injected clock [RESOLVED]

- **Issue:** [#175](https://gitlab.com/devnw/zig/uuid/-/work_items/175) (still open on tracker)
- **Severity:** Info (Score 8)
- **Resolution:** Test added asserting `newV1`/`newV6` do not consult the injected clock.
- **Evidence:** `src/generator_test.zig`.
- **Resolved date:** 2026-03-22

### QC-90: `root.zig` doc tells external callers to `@import("generator.zig")` [RESOLVED]

- **Issue:** [#176](https://gitlab.com/devnw/zig/uuid/-/work_items/176) (still open on tracker)
- **Severity:** Medium (Score 36)
- **Resolution:** Doc updated to show the correct external import (`@import("uuid")`).
- **Evidence:** `src/root.zig:67`.
- **Resolved date:** 2026-03-22

### QC-91: `examples/basic.zig` uses `{any}` for `NullUUID` [RESOLVED]

- **Issue:** [#177](https://gitlab.com/devnw/zig/uuid/-/work_items/177) (still open on tracker)
- **Severity:** Low (Score 16)
- **Resolution:** Format specifier changed from `{any}` to `{f}`.
- **Evidence:** `examples/basic.zig:104-105`.
- **Resolved date:** 2026-03-22

### QC-92: README "See docs/ for detailed documentation" misleading [RESOLVED]

- **Issue:** [#178](https://gitlab.com/devnw/zig/uuid/-/work_items/178) (still open on tracker)
- **Severity:** Low (Score 16)
- **Resolution:** README now describes `docs/` as internal review notes rather than user docs.
- **Evidence:** `README.md:202`.
- **Resolved date:** 2026-03-22

---

## Note on QC-80

QC-80 (README `.hash = "..."` placeholder) was marked Closed on the tracker
([#166](https://gitlab.com/devnw/zig/uuid/-/work_items/166)) and then
regressed — the Phase 3 gap-detector found the literal placeholder string
`"<hash printed by zig fetch>"` at `README.md:28`. The regression was
re-fixed in the Phase 3 closure cycle (commit `b2bc924`) and is now
recorded under "Phase 3 Closure Cycle" below.

---

## Phase 3 Closure Cycle (2026-04-18)

> HEAD at closure: `b2d7766`. 16 items closed this cycle; evidence pinned to
> commit SHA + file:line. These items are tracked in docs only and do not have
> dedicated GitLab work items (the previously-verified 25 items above remain on
> the tracker; their closure is queued in the Phase-3 `glab` block in
> `docs/GAP_ANALYSIS.md`).

### Documentation / Packaging

### GAP-DOC-01 / QC-93: MSRV drift — README/build.zig.zon claimed 0.15.2, code required 0.16.0 [RESOLVED]

- **Issue:** tracked in docs only (no GitLab work item)
- **Category:** Docs / Packaging
- **Severity:** High
- **Resolution:** Bumped `minimum_zig_version` to `0.16.0`; refreshed README badge, `src/root.zig` doc header, and added a CHANGELOG entry.
- **Evidence:** `build.zig.zon:5`, `README.md:4`, `src/root.zig:23`, `CHANGELOG.md`.
- **Commit:** `ec99ed2`
- **Resolved date:** 2026-04-18

### QC-80 (regression re-fix): README `.hash` placeholder removed [RESOLVED]

- **Issue:** [#166](https://gitlab.com/devnw/zig/uuid/-/work_items/166) — previously closed, regressed, re-fixed
- **Category:** Docs / Packaging
- **Severity:** Medium
- **Resolution:** Removed the literal `.hash = "<hash printed by zig fetch>"` placeholder; README now instructs readers to run `zig fetch --save`.
- **Evidence:** `README.md:28` (no placeholder present).
- **Commit:** `b2bc924`
- **Resolved date:** 2026-04-18

### QC-94: README Quick Start silent on Zig 0.16 `std.Io.Writer` contract [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Docs
- **Severity:** Medium
- **Resolution:** Quick Start updated with an example using the new `std.Io.Writer` contract.
- **Evidence:** `README.md` Quick Start section.
- **Commit:** `b068dc7`
- **Resolved date:** 2026-04-18

### GAP-DOC-03: Quality/Perf/Security review doc headers stuck on Zig 0.15.2 [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated the three doc headers to `0.16.0`.
- **Evidence:** `docs/QUALITY_GAP_ANALYSIS.md:5`, `docs/PERF_GAP_ANALYSIS.md`, `docs/SECURITY_REVIEW_NOTES.md`.
- **Commit:** `7ca88ba`
- **Resolved date:** 2026-04-18

### GAP-DOC-02: `docs/REQUIREMENTS.md` stale and referenced non-existent Geode paths [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Docs
- **Severity:** Medium
- **Resolution:** Refreshed `REQUIREMENTS.md` to cite only paths inside this repo; added a mirror-disclaimer footer.
- **Evidence:** `docs/REQUIREMENTS.md`.
- **Commit:** `f1db8ec`
- **Resolved date:** 2026-04-18

---

### Quality — Cycle 13 (Phase 3)

### QC-102: `*Alloc` doc comments misleading about allocator cost [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Docs
- **Severity:** Low (Score 12)
- **Resolution:** Rewrote the `*Alloc` doc comments to describe the allocator parameter; moved the fixed-allocator bench note into a separate callout.
- **Evidence:** `src/uuid.zig:382-414`.
- **Commit:** `4591a9b`
- **Resolved date:** 2026-04-18

### QC-96 / PERF-28: `std.Io.Threaded.global_single_threaded.io()` re-resolved 18–23× [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Readability / Performance
- **Severity:** Medium (Score 27)
- **Resolution:** Hoisted `const io = std.Io.Threaded.global_single_threaded.io();` to a per-function (or struct-field) constant; 23 inline sites collapsed.
- **Evidence:** `src/generator.zig`.
- **Commit:** `bbfad76`
- **Resolved date:** 2026-04-18

### QC-95: `newV7Locked` manually unlocked mutex on 3 early-return branches [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Maintainability
- **Severity:** High (Score 36)
- **Resolution:** Refactored to single-acquire + `defer self.mutex.unlock()`; manual unlocks removed from all early-return branches.
- **Evidence:** `src/generator.zig` (`newV7Locked`).
- **Commit:** `54a087a`
- **Resolved date:** 2026-04-18

### QC-97: 5 `*Alloc` helpers were near-identical copy/paste [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Maintainability
- **Severity:** Low (Score 18)
- **Resolution:** Collapsed to a single generic helper parameterised by formatter/length.
- **Evidence:** `src/uuid.zig:382-414`.
- **Commit:** `0a919ea`
- **Resolved date:** 2026-04-18

### QC-98: Duplicated MAC-filter predicate across OS backends [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Maintainability
- **Severity:** Low (Score 18)
- **Resolution:** Hoisted `isUsableMac` predicate into a shared `src/hwaddr/common.zig`; Linux/macOS/Windows backends now call the shared predicate.
- **Evidence:** `src/hwaddr/common.zig`, `src/hwaddr/{linux,macos,windows}.zig`.
- **Commit:** `828e80a`
- **Resolved date:** 2026-04-18

### QC-99: `saveState`/`loadState` returned bare `!void` [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** API contract
- **Severity:** Medium (Score 27)
- **Resolution:** Tightened signatures to `Error!void`; documented the error set.
- **Evidence:** `src/generator.zig:626,704`.
- **Commit:** `cafa0b0`
- **Resolved date:** 2026-04-18

### QC-101: `loadState` v1→v2 upgrade + fast-restart branches lacked coverage [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Tests
- **Severity:** Medium (Score 18)
- **Resolution:** Added a table test covering the v1→v2 upgrade and fast-restart branches.
- **Evidence:** `src/generator_state_test.zig`.
- **Commit:** `f2a1bc6`
- **Resolved date:** 2026-04-18

---

### Performance — Cycle 5 (Phase 3)

### PERF-24: `std.log.warn` in hwaddr hot path with >128 interfaces [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P1, PerfScore 48)
- **Resolution:** Downgraded the warn to `debug` / once-flag to remove the hot-path cost on container/VLAN deployments.
- **Evidence:** `src/hwaddr/linux.zig`.
- **Commit:** `f30658e`
- **Resolved date:** 2026-04-18

### PERF-25: `jsonMarshal` two-pass (toString + `allocator.dupe`) [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P2, PerfScore 36)
- **Resolution:** Single-pass: allocate the 36-byte heap buffer first, then write via `toStringInto(buf)`; stack copy removed.
- **Evidence:** `src/uuid.zig`.
- **Commit:** `8374793`
- **Resolved date:** 2026-04-18

### PERF-30: Md5/Sha1 init per V3/V5 call — no prehashed-namespace variant [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P3, PerfScore 16)
- **Resolution:** Added `NamespaceContext` with pre-absorbed Md5/Sha1 state; `newV3InNamespace`/`newV5InNamespace` clone and finalise. Purely additive API.
- **Evidence:** `src/generator.zig`.
- **Commit:** `dc9458e`
- **Resolved date:** 2026-04-18

### PERF-32: Add `ProcessHashContext` — per-process salted V5 (zero runtime cost) [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P3, PerfScore 8)
- **Resolution:** Added `ProcessHashContext.init()` with a 128-bit CSPRNG seed picked at process start; `v5InProcessNamespace(name)` absorbs seed + name. Same-process determinism; cross-process variability.
- **Evidence:** `src/uuid.zig`.
- **Commit:** `b2d7766`
- **Resolved date:** 2026-04-18

---

### Phase 3 Closure Cycle — Tally

- Closed this cycle: **16** (5 docs/packaging, 7 quality, 4 performance).
- Pre-existing bookkeeping closures still on tracker: **25**.
- Deferred — pending user sign-off (Group C): **11** — see domain docs.
- Deferred (high-risk) — requires explicit approval (Group D): **3** — see domain docs.
- Blocked on external input: **1** (SEC-P3-07).
- Won't Do — retained / reconfirmed: **4** (SEC-P3-06, SEC-R9-02, SEC-R2-01, GAP-DOC-04).
