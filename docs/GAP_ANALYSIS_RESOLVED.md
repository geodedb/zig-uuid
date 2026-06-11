# Gap Analysis -- Resolved

> Mirror of resolved items that were previously tracked in `docs/GAP_ANALYSIS.md`
> and the GitLab issue tracker. The issue tracker is authoritative.
>
> Last updated: 2026-06-11 (Audit cycle 2026-06-11 closure complete — **GAP-DOC-17..21** resolved and migrated here (5 doc-drift items, GitLab #183–#187 closed); **GAP-DOC-10** resolved and migrated here (closure-drift batch cycle — `glab` auth restored); the 25 closure-drift tracker items #154–#178 [exact set: #154,#156,#158,#159,#161,#164,#167,#155,#157,#160,#162,#163,#165,#166,#168–#178] were batch-closed on the GitLab tracker, reconciling the long-standing docs↔tracker drift. **Only SEC-P4-14 (#188, Blocked-external) remains open** across all tracker files. Cumulative closures: 105. Won't-Do retained: 4.)
> Previously: 2026-04-20 (Phase 5 closure cycle — 12 items closed across GAP-CI-01, 4 SEC-P4 security items, 1 SEC-P4 adversarial co-closure, 2 PERF items + 1 PERF co-closure, 4 QC items + 1 QC co-closure. **Residual closure batch:** +7 items — SEC-P4-13, GAP-DOC-11, GAP-DOC-12, PERF-41, PERF-44, QC-116, QC-117. **QC-113d re-attempt 2026-04-20:** previously deferred, now closed — V7 CAS state-machine extracted into pure `V7Cas.transition` helper; ABA-avoidance + PERF-40 invariants preserved. After the re-attempt, only SEC-P4-14 (Blocked) remains open across all tracker files. Plus the earlier Phase 5 sync migration of Legacy F-1..F-9 + G-1..G-10 and GAP-DOC-13.)

## Summary

- **25 prior tracker items** (Cycles 12–13): resolved in-code; still marked open on the GitLab tracker; closure queued in the Phase-3 `glab` block in `docs/GAP_ANALYSIS.md`.
- **16 Phase-3 initial closure-cycle items** (2026-04-18): see "Phase 3 Closure Cycle" section. Docs-tracked only.
- **11 Group C closure-round items** (2026-04-18, HEAD `5bee3e7`): 10 full closures + 1 partial (PERF-31 doc mitigation). See "Group C Closure Round" section. Docs-tracked only.
- **5 Group D closure-round items** (2026-04-18, HEAD `f77e7da`): 4 full closures (PERF-21, PERF-31 promoted, SEC-P3-04, SEC-P3-08) + 1 partial (SEC-P3-07 — 3 human-input TODOs). See "Group D Closure Round" section. Docs-tracked only.
- **19 Phase-5 migrated legacy items** (2026-04-19, HEAD `7e57b2b`): F-1..F-9 (RFC-9562 compliance) + G-1..G-10 (gofrs/uuid feature parity) — all originally closed 2026-03-21 and flagged `Closed / Implemented` inline in `docs/GAP_ANALYSIS.md`. Moved here to honour the "open-only" invariant. Plus **GAP-DOC-13** (Low) closed in-band as the migration itself.

Evidence for each resolution is pinned to a concrete file:line, commit SHA, or test output.

---

## CI-CD — Closure-Drift Batch (2026-06-11)

### GAP-DOC-10: `glab` auth broken — tracker cross-reference unavailable [RESOLVED]

- **Issue:** (none — self-referential infra gap)
- **Category:** CI-CD
- **Severity:** Medium
- **Resolution:** The `glab` personal access token was rotated by the operator; `glab auth status` now reports green (logged in as `benjiv` on `gitlab.com`). With auth restored, `gap-sync` replayed the long-queued closure-drift batch: the 25 issues that had been confirmed `✅ Closed`-in-code across prior cycles but remained open on the tracker were closed, each with an evidence note. The same cycle recorded 6 new tracker items (GAP-DOC-17..21 [#183–#187] + SEC-P4-14 [#188]).
- **Evidence:**
  - `glab auth status` → green (`✓ Logged in to gitlab.com as benjiv`).
  - 25 issues now `Closed`: #154, #155, #156, #157, #158, #159, #160, #161, #162, #163, #164, #165, #166, #167, #168, #169, #170, #171, #172, #173, #174, #175, #176, #177, #178 — each with a preceding evidence note (`glab issue note <iid> -m "…"`; `glab` 1.53.0 `issue close` has no `--comment` flag).
  - Runbook: `docs/runbooks/glab-auth.md`.
- **Resolved date:** 2026-06-11

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
- **Resolution:** Added encrypted reporting channel, CVSS v3.1 severity table, and version support matrix. (CVSS v4.0 is now the primary scoring scheme across tracking docs; the v3.1 table in `SECURITY.md` is retained as the backward-compat reference — see `SECURITY.md` § Severity Classification.)
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
- **Resolution:** Added `Generator.PrehashedV3`/`PrehashedV5` + `initV3Namespace`/`initV5Namespace` with pre-absorbed Md5/Sha1 state; `PrehashedV*.name(name)` clones and finalises. Purely additive API. (The PERF-30 design phase called this `NamespaceContext`; the shipped API uses version-specific types for better compile-time safety.)
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

- Closed in initial Phase-3 round: **16** (5 docs/packaging, 7 quality, 4 performance).
- Closed in Group C round (2026-04-18): **11** (10 full + 1 partial) — see "Group C Closure Round" below.
- Pre-existing bookkeeping closures still on tracker: **25**.
- Deferred — pending user sign-off (Group C): **0** (closed this round).
- Deferred (high-risk) — requires explicit approval (Group D): **3** — see domain docs.
- Blocked on external input: **1** (SEC-P3-07).
- Won't Do — retained / reconfirmed: **4** (SEC-P3-06, SEC-R9-02, SEC-R2-01, GAP-DOC-04).

---

## Group C Closure Round (2026-04-18)

> HEAD at closure: `5bee3e7`. Test state: 204/204 unit + 32/32 integration (all green).
> Items are doc-tracked only (no dedicated GitLab work items). 10 full closures + 1
> partial (PERF-31 — doc mitigation landed; full refactor deferred pending ADR).

### Security — Group C (4 closed)

### SEC-P3-01: Fork-unsafe CSPRNG [RESOLVED]

- **Issue:** tracked in docs only (no GitLab work item)
- **Category:** Security / CWE-331, CWE-665
- **Severity:** Medium (Risk 9, confidence::confirmed)
- **Resolution:** Added `Generator.reseed()` public method; callers on fork-capable platforms are directed to invoke it in the child after `fork(2)`. Fork-safety caveat documented in both `README.md` and `SECURITY.md`.
- **Evidence:** `src/generator.zig` (`Generator.reseed`), `README.md`, `SECURITY.md`.
- **Commit:** `275a7e3`
- **Resolved date:** 2026-04-18

### SEC-P3-02: No timestamp-rollback detection in `loadState` [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Security / CWE-367, CWE-1240
- **Severity:** Medium (Risk 9, confidence::confirmed)
- **Resolution:** `loadState` now rejects future-dated state beyond a 1000 ms tolerance window and clamps `last_v1_ts` / `last_ms` monotonically forward. Tolerance exposed via the new `Config.clock_rollback_tolerance_ms = 1_000` constant.
- **Evidence:** `src/generator.zig` (`loadState`), `Config.clock_rollback_tolerance_ms`.
- **Commit:** `94d7f9a`
- **Resolved date:** 2026-04-18

### SEC-P3-03: `saveState` does not set explicit mode [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Security / CWE-276, CWE-732
- **Severity:** Medium (Risk 9, confidence::confirmed)
- **Resolution:** `saveState` now passes `.mode = 0o600` to `createFileAbsolute` and additionally `fchmod(0o600)`s the file after rename (belt-and-suspenders against umask variations). POSIX test asserts `statFile().mode & 0o777 == 0o600`.
- **Evidence:** `src/generator.zig` (`saveState`).
- **Commit:** `be5788f`
- **Resolved date:** 2026-04-18

### SEC-P3-05: V3/V5 namespace-abuse vector [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Security / CWE-327, CWE-347
- **Severity:** Low-Medium (Risk 6, confidence::confirmed)
- **Resolution:** Added a `Namespace` enum (with `asUUID()`) covering the four RFC-defined namespaces; added `newV3Strict` / `newV5Strict` (Generator + module-level) that accept only `Namespace` enum values. Permissive `newV3` / `newV5` retained for interop and now carry a CWE-347 doc warning directing callers to the `*Strict` forms unless they have a justified interop need.
- **Evidence:** `src/namespace.zig` (`Namespace` + `asUUID`), `src/versions.zig` (`newV3Strict`, `newV5Strict`), `src/generator.zig`, `src/uuid.zig` (CWE-347 warning).
- **Commit:** `fc3b9ac`
- **Resolved date:** 2026-04-18

---

### Performance — Group C (5 closed, 1 partial)

### PERF-22: No multi-threaded V7 benchmark [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P1, confirmed)
- **Resolution:** `benchV7Contention` multi-threaded measurement landed — concurrency signal now available for PERF-21 planning.
- **Evidence:** `bench/main.zig`.
- **Commit:** `4ec4eee`
- **Resolved date:** 2026-04-18

### PERF-23: `defaultRand` function-pointer indirection prevents inlining [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P1, confirmed)
- **Resolution:** Changed `rand` and `clock` fields to nullable — default paths take an inlinable CSPRNG / clock implementation; test-injectable variants retained via `withRand` / `withClock`.
- **Evidence:** `src/generator.zig`.
- **Commit:** `7a95126`
- **Resolved date:** 2026-04-18

### PERF-26: CI `bench-regression` has `allow_failure:true` without threshold gate [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance / CI (P2, confirmed)
- **Resolution:** Committed a `bench/baseline.txt` snapshot; `bench-regression` CI job dropped `allow_failure:true` and now gates on a 15% regression threshold.
- **Evidence:** `bench/baseline.txt`, `.gitlab-ci.yml`.
- **Commit:** `05491f2`
- **Resolved date:** 2026-04-18

### PERF-27: `node_cache` unsynchronised read outside `v1v6_mutex` [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance / Concurrency (P2, confirmed)
- **Resolution:** Split `node_cache` into a `std.atomic.Value(bool) node_cache_valid` flag + raw `node_cache_bytes`; acquire/release ordering ensures TSan cleanliness while preserving the lock-free fast path. Distinct from SEC-P3-06 (Won't-Do) which covers the intentional pre-lock optimistic read.
- **Evidence:** `src/generator.zig`.
- **Commit:** `2f93fac`
- **Resolved date:** 2026-04-18

### PERF-29: False sharing between V7 and V1/V6 state in `Generator` [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P2, suspected → confirmed post-fix)
- **Resolution:** Inserted `align(64)` cache-line separation between the V7 and V1/V6 state clusters in the `Generator` struct. Cross-domain false sharing eliminated.
- **Evidence:** `src/generator.zig`.
- **Commit:** `d31bb22`
- **Resolved date:** 2026-04-18

### PERF-31: `GeneratorInterface` vtable blocks inlining [PARTIALLY RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P3, suspected)
- **Resolution (partial):** Doc warning on `GeneratorInterface` directs hot-path callers to hold `*Generator` directly (mitigation-only). Full comptime-generic rewrite (`GeneratorInterfaceFor(G)`) deferred pending an ADR + major-version bump (API-breaking).
- **Evidence:** `src/generator.zig` (doc warning on `GeneratorInterface`).
- **Commit:** `e9cbf7f`
- **Resolved date:** 2026-04-18 (partial; full closure tracked as an ADR follow-up)

---

### Quality — Group C (1 closed)

### QC-100: `default_generator` parity asymmetry [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** API contract
- **Severity:** Medium (Score 18, suspected → confirmed post-fix)
- **Resolution:** Added `defaultGenerator() *Generator` to `src/root.zig` plus module-level parity wrappers: `clearNodeCache`, `reseed`, `saveState`, `loadState`, `initV3Namespace`, `initV5Namespace`. The module surface now mirrors the `Generator` surface, resolving the divergence.
- **Evidence:** `src/root.zig`.
- **Commit:** `23ad3cd`
- **Resolved date:** 2026-04-18

---

### Group C Closure Round — Tally

- Full closures: **10** (SEC-P3-01, SEC-P3-02, SEC-P3-03, SEC-P3-05, PERF-22, PERF-23, PERF-26, PERF-27, PERF-29, QC-100).
- Partial closure: **1** (PERF-31 — doc mitigation landed; full rewrite ADR pending).
- Accompanying style commit: `5bee3e7` (`zig fmt` nit after PERF-22; not gap-tracked).
- Remaining open across all domains: **5** — PERF-31 (partial), PERF-21 (Group D), SEC-P3-04 (Group D), SEC-P3-08 (Group D), SEC-P3-07 (blocked).
- Cumulative closures this project: **52** (25 prior tracker + 16 Phase-3 initial + 11 Group C).

---

## Group D Closure Round (2026-04-18)

> HEAD at closure: `f77e7da` (pushed). Test state: all unit + integration suites green.
> Docs-tracked only — no dedicated GitLab work items. 4 full closures + 1 partial
> (SEC-P3-07 — `security.txt`, CVSS v4.0 (v3.1 equivalents retained in `SECURITY.md`), and safe-harbor skeleton landed; full
> closure blocked on three human-input TODOs: PGP fingerprint publication, CNA
> choice, safe-harbor legal review). PERF-31 — previously partial in Group C —
> is promoted to Closed this round via an additive comptime-generic wrapper.

### Performance — Group D (2 closed)

### PERF-31: `GeneratorInterface` vtable blocks inlining [RESOLVED — promoted from partial]

- **Issue:** tracked in docs only
- **Category:** Performance (P3, suspected → confirmed post-fix)
- **Resolution:** Added **additive** comptime-generic `GeneratorInterfaceFor(comptime G: type)` wrapper alongside the existing runtime-vtable `GeneratorInterface`. Every method on the comptime-generic wrapper is an `inline` direct call through `self.g.*`; LLVM inlines through at ReleaseFast — zero indirection on the hot path. The existing vtable `GeneratorInterface` is **retained unchanged** for runtime-polymorphism call sites (DI, fakes, metric wrappers). No existing call site breaks.
- **Evidence:** `src/generator.zig` (`GeneratorInterfaceFor(G)` declaration + `inline` methods), `src/generator_test.zig` (direct-equivalence tests against both wrappers).
- **Commit:** `7c91b41`
- **Resolved date:** 2026-04-18

### PERF-21: V7 mutex serialises every call — opt-in lock-free CAS path [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Performance (P0, suspected → confirmed)
- **Resolution:** Opt-in lock-free V7 path landed via `InitOptions.v7_lockfree = true`. When enabled, `newV7`/`newV7AtTime` use a packed `u64 = (ms<<12) | seq` CAS over `v7_atomic_state` instead of the `v7_mutex` critical section. The **default remains the mutex path** (correctness-authoritative). The 2-byte `seq` CSPRNG draw is inside the CAS retry loop by design — worst case on a CAS miss is a re-draw; noted in-code. A per-process saturation-fallback path keeps same-ms overflow waits bounded.
- **Evidence:** `src/generator.zig` (`newV7Atomic`, `v7_atomic_state`, `InitOptions.v7_lockfree`), `src/generator_test.zig` (single-thread equivalence, multi-thread stress, saturation-fallback tests), `bench/main.zig` (`benchV7ContentionOnce` exercises both paths). Multi-thread bench at 32 threads: **~34% higher ops/s** vs mutex (982k vs 730k). Monotonicity stress test: 10/10 consecutive passes.
- **Commit:** `f77e7da`
- **Resolved date:** 2026-04-18

---

### Security — Group D (2 closed, 1 partial)

### SEC-P3-08: Global CSPRNG substitution risk [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Security / CWE-670, CWE-345
- **Severity:** Medium (Risk 8, confidence::suspected → confirmed post-fix)
- **Resolution:** Added `Generator.InitOptions.random: ?std.Random` — when non-null, this overrides the mutable-global `std.Io.Threaded.global_single_threaded` capture. `Generator.initOptions(opts)` is the new entry point. The default (null `random`) remains the freshly-seeded `std.crypto.random` path — identical runtime behaviour to before for all existing call sites. Every `Generator.init` call site continues to work unchanged. A PoC test overrides the random source with a deterministic PRNG and asserts V4 output is driven by the override (substitution attack is now explicit and caller-consented, not implicit and global).
- **Evidence:** `src/generator.zig` (`InitOptions`, `initOptions`, `InitOptions.random`), `src/generator_test.zig` (deterministic-PRNG substitution proof).
- **Commit:** `7e70fd5`
- **Resolved date:** 2026-04-18

### SEC-P3-04: State file lacks MAC/signature [RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Security / CWE-345, CWE-353
- **Severity:** Medium (Risk 9, confidence::confirmed)
- **Resolution:** Added state-file **wire-format v3** with an appended HMAC-SHA256 tag computed over header + payload using the new caller-supplied `Generator.state_mac_key: ?[32]u8`. `loadState` rejects on tag mismatch with the new `Error.StateMacMismatch`; comparison is **timing-safe** (`std.crypto.timing_safe.eql`). **Backward-compatible**: v1/v2 state files still load read-only when `state_mac_key == null`; v3 is written only when a key is set. Migration path: a caller sets `state_mac_key` once, then on next save the file is upgraded to v3 transparently.
- **Evidence:** `src/generator.zig` (`saveState` v3 writer, `loadState` v3 reader, `StateMacMismatch`), `src/generator_state_test.zig` (v1/v2 BC tests, v3 round-trip, tampered-tag rejection, timing-safe assertion).
- **Commit:** `3f34a96`
- **Resolved date:** 2026-04-18

### SEC-P3-07: SECURITY.md missing PGP / CVE path / safe-harbor / security.txt [PARTIALLY RESOLVED]

- **Issue:** tracked in docs only
- **Category:** Security / CWE-1059 (process)
- **Severity:** Low (Risk 4, confidence::confirmed)
- **Resolution (partial):** Landed the mechanical portions that do not require human legal / cryptographic input: (a) `/.well-known/security.txt` published per RFC 9116 with contact, preferred-languages, and expiration; (b) CVSS v4.0 severity statement section added to `SECURITY.md` (now the primary scoring scheme; the earlier v3.1 table remains as the backward-compat reference alongside it — see `SECURITY.md` § Severity Classification); (c) safe-harbor language skeleton (Disclose.io-derived) added to `SECURITY.md` as a draft awaiting legal review.
- **Blocked on (human input, 3 TODOs):**
  1. Publish a PGP key + fingerprint (block: key generation + publication).
  2. Choose + register a CNA path (MITRE vs GitLab CNA vs project-own).
  3. Legal review to approve the safe-harbor language (Disclose.io template) and remove the draft notice.
- **Evidence:** `/.well-known/security.txt`, `SECURITY.md` (CVSS v4.0 section, safe-harbor draft with `<!-- TODO -->` markers for the three human-input items).
- **Commit:** `6ffe052`
- **Resolved date (partial):** 2026-04-18

---

### Group D Closure Round — Tally

- Full closures: **4** (PERF-31 promoted from partial, PERF-21, SEC-P3-08, SEC-P3-04).
- Partial closure: **1** (SEC-P3-07 — mechanical parts landed; 3 human-input TODOs remain).
- Remaining open across all domains: **0** (SEC-P3-07 Partial is flagged with explicit unblock steps — no other outstanding items).
- Cumulative closures this project: **60** (25 prior tracker + 16 Phase-3 initial + 11 Group C + 5 Group D of which 1 partial). Won't-Do retained: 4.

---

## Legacy F-Series (RFC-9562 Compliance) — Closed 2026-04-19

> Migrated from `docs/GAP_ANALYSIS.md` during the Phase 5 sync (HEAD `7e57b2b`).
> All entries below were originally resolved on 2026-03-21 and flagged
> `✅ Closed / Implemented` inline in the "RFC-9562 Compliance Gaps" section of
> `docs/GAP_ANALYSIS.md`. The Closed rationale, file pointers, and test lists
> below are preserved verbatim from that section. Tracker: none — these
> predate the tracker bookkeeping block.

### F-1 — V1/V6 embed real MAC address by default

**Status: ✅ Closed / Implemented**

**Change:** `Generator.hwaddr_fn` changed from `HWAddrFn = hwaddr.get` to
`?HWAddrFn = null`. When `null` (the default), `getNode()` generates a random
multicast node ID (multicast bit set per RFC §6.10) and caches it for the
generator's lifetime. MAC-based node IDs are now an explicit opt-in via
`Generator.withHWAddr(f)` or setting `.hwaddr_fn = f`.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.newV1: default uses random node with multicast bit (F-1)`
- `Generator.newV1: node is cached across calls (F-6/G-6)`
- `Generator.clearNodeCache refreshes node (F-6/G-6)`

### F-2 — `UUID.version()` panics on unknown version nibbles

**Status: ✅ Closed / Implemented**

**Change:** `Version` is now a non-exhaustive enum (trailing `_`). `@enumFromInt`
on unknown nibbles (nil UUID version=0, DCE Security version=2, future
versions 9–15) returns an unnamed member instead of panicking. `UUID.nil.version()`
no longer panics.

**Files:** `src/uuid.zig`

**Tests added:**

- `UUID.version() is safe for nil UUID (nibble=0, non-exhaustive)`
- `UUID.version() is safe for future nibble (nibble=15)`

### F-3 — Clock sequence fallback is not random

**Status: ✅ Closed / Implemented**

**Change:** `initClockSeq()` changed from `void` to `Error!void`. The
hardcoded `{ 0x12, 0x34 }` fallback is removed. CSPRNG failure now propagates
as `Error.RandomError` from `newV1AtTime`/`newV6AtTime`.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.initClockSeq propagates CSPRNG failure (F-3)`

### F-4 — V1/V6 do not detect node ID changes

**Status: ✅ Closed / Implemented**

**Change:** Added `last_node: ?[6]u8 = null` to `Generator`. In
`newV1AtTime` and `newV6AtTime`, after fetching the node ID, the new node is
compared against `last_node`; if different, `clock_seq` is incremented. The
node change detection works in conjunction with `clearNodeCache()` (F-6).

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.newV1: clock_seq increments on node ID change (F-4)`

### F-5 — No URN output method

**Status: ✅ Closed / Implemented**

**Change:** Added `UUID.toURN(buf: *[45]u8) []u8` and
`UUID.toURNAlloc(alloc) ![]u8`. `"urn:uuid:"` (9 chars) + canonical UUID
(36 chars) = 45 chars. Output is parseable by `UUID.fromString`.

**Files:** `src/uuid.zig`

**Tests added:**

- `toURN produces urn:uuid: prefix (F-5 / G-3)`
- `toURNAlloc (F-5 / G-3)`
- `toURN round-trip with fromString (F-5 / G-3)`

### F-6 — RFC Appendix A test vectors not fully asserted

**Status: ✅ Closed / Implemented**

**Change:** Added three deterministic tests using exact RFC Appendix A
timestamps, node IDs, and clock sequences. The V7 test uses a module-level
mock rand to fix rand_a and rand_b.

**Files:** `src/generator.zig`

**Tests added:**

- `RFC Appendix A.1 — V1 test vector (F-6)` → `c232ab00-9414-11ec-b3c8-9f6bdeced846`
- `RFC Appendix A.5 — V6 test vector (F-6)` → `1ec9414c-232a-6b00-b3c8-9f6bdeced846`
- `RFC Appendix A.6 — V7 test vector (F-6)` → `017f22e2-79b0-7cc3-98c4-dc0c0c07398f`

### F-7 — `Timestamp.now()` unchecked cast on pre-1970 system clock

**Status: ✅ Closed / Implemented**

**Change:** `Timestamp.now()` changed from `Timestamp` to `Error!Timestamp`.
Returns `Error.InvalidTimestamp` when `std.time.nanoTimestamp()` returns a
negative value (system clock before 1970). `Timestamp.fromUnixNano` and
`Timestamp.fromUnixMs` also guard against negative input. `Error.InvalidTimestamp`
added to the error set in `src/uuid.zig`. Callers in `generator.zig`
(`newV1`, `newV6`) updated to `try Timestamp.now()`.

**Files:** `src/uuid.zig`, `src/timestamp.zig`, `src/generator.zig`

**Tests added:**

- `Timestamp now() pre-1970 guard (F-7)`
- `Timestamp fromUnixMs: negative ms returns error (F-7)`

### F-8 — Shared V1/V6 clock_seq state is undocumented

**Status: ✅ Closed / Implemented**

**Change:** Added a comprehensive doc comment to the `Generator` struct
explaining the shared V1/V6 clock domain, the default random-node behaviour
(F-1), and the node-caching behaviour (F-6/G-6).

**Files:** `src/generator.zig`

### F-9 — No persistent state across process restarts

**Status: ✅ Closed / Implemented**

**Change:** Added `Generator.saveState(path)` and `Generator.loadState(path)`.
The state is serialised as a 22-byte binary blob: 4-byte magic `"UUID"`,
1-byte format version, 1-byte flags, u16 clock_seq, u64 last_v1_ts, and
optional 6-byte node_cache. Returns `Error.InvalidFormat` on corrupt or
version-mismatched files.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.saveState and loadState round-trip (F-9)`
- `Generator.loadState: corrupt magic returns error (F-9)`

---

## Legacy G-Series (gofrs/uuid Feature Parity) — Closed 2026-04-19

> Migrated from `docs/GAP_ANALYSIS.md` during the Phase 5 sync (HEAD `7e57b2b`).
> All entries below were originally resolved on 2026-03-21 and flagged
> `✅ Closed / Implemented` inline in the "Feature Gaps vs gofrs/uuid" section
> of `docs/GAP_ANALYSIS.md`. Content preserved verbatim. Tracker: none.

### G-1 — No binary marshal / unmarshal

**Status: ✅ Closed / Implemented**

**Change:** Added `UUID.toBytes() [16]u8` — returns a value copy of `.bytes`.
`UUID.fromBytes` already existed. Together they form the full binary marshal
interface.

**Files:** `src/uuid.zig`

**Tests added:**

- `toBytes returns 16-byte copy (G-1)`

### G-2 — No `fmt`-style format verbs / uppercase output

**Status: ✅ Closed / Implemented**

**Change:** Added four output methods:

- `toStringUpper(buf: *[36]u8) []u8` — uppercase with dashes
- `toStringUpperAlloc(alloc) ![]u8` — allocating uppercase with dashes
- `toHex(buf: *[32]u8) []u8` — lowercase no dashes
- `toHexUpper(buf: *[32]u8) []u8` — uppercase no dashes

All four share `toStringImpl`/`toHexImpl` private helpers parameterised on
the hex alphabet string.

**Files:** `src/uuid.zig`

**Tests added:**

- `toStringUpper produces uppercase with dashes (G-2)`
- `toHex produces lowercase without dashes (G-2)`
- `toHexUpper produces uppercase without dashes (G-2)`
- `toStringUpperAlloc (G-2)`

### G-3 — No URN output

**Status: ✅ Closed / Implemented** (same as F-5)

### G-4 — `timestampFromV7` returns `i64` ms, not `Timestamp`

**Status: ✅ Closed / Implemented**

**Change:** `timestampFromV7` now returns `Error!Timestamp` (consistent with
`timestampFromV1`/`timestampFromV6`). It converts the embedded Unix ms to a
Gregorian 100-ns `Timestamp` value via `Timestamp.fromUnixMs`. Callers use
`.toUnixMs()` to recover the raw millisecond value. All callers updated
(`tests/integration.zig`, `examples/basic.zig`, `src/generator.zig` test).

**Files:** `src/timestamp.zig`, `tests/integration.zig`, `examples/basic.zig`,
`src/generator.zig`

**Tests added:**

- `timestampFromV7: returns Timestamp with correct Unix ms (G-4)`
- `timestampFromV7: large real-world timestamp (G-4)`
- `integration: timestampFromV7 returns Timestamp (G-4)`

### G-5 — No `Timestamp` → wall clock conversion

**Status: ✅ Closed / Implemented**

**Change:** Added three conversion helpers to `Timestamp`:

- `toUnixMs() i64` — Unix milliseconds
- `toUnixSec() i64` — Unix seconds
- The existing `toUnixNano() i128` already covered nanoseconds

**Files:** `src/timestamp.zig`

**Tests added:**

- `Timestamp.toUnixMs round-trip (G-5)`
- `Timestamp.toUnixSec round-trip (G-5)`
- `Timestamp.toUnixNano is consistent with toUnixMs (G-5)`

### G-6 — MAC address fetched on every V1/V6 generation

**Status: ✅ Closed / Implemented**

**Change:** Added `node_cache: ?[6]u8 = null` to `Generator`. `getNode()`
returns the cached value immediately on subsequent calls. `clearNodeCache()`
sets `node_cache = null`, forcing a re-fetch on the next V1/V6 generation.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.newV1: node is cached across calls (F-6/G-6)`
- `Generator.clearNodeCache refreshes node (F-6/G-6)`

### G-7 — No `fromStringOrNil` / `fromBytesOrNil` convenience variants

**Status: ✅ Closed / Implemented**

**Change:** Added:

- `UUID.fromStringOrNil(s) UUID` — returns nil UUID on parse error
- `UUID.fromBytesOrNil(b) UUID` — returns nil UUID on wrong length

**Files:** `src/uuid.zig`

**Tests added:**

- `fromStringOrNil: valid input returns UUID (G-7)`
- `fromStringOrNil: invalid input returns nil (G-7)`
- `fromBytesOrNil: valid 16 bytes (G-7)`
- `fromBytesOrNil: wrong length returns nil (G-7)`

### G-8 — No `Generator` interface / abstraction

**Status: ✅ Closed / Implemented**

**Change:** Added `GeneratorInterface` — a vtable-based polymorphism type
that wraps any `*Generator` (or future concrete implementation). Exposes all
10 generation methods. `GeneratorInterface.fromGenerator(gen: *Generator)`
creates a `GeneratorInterface` backed by the concrete `Generator` via the
`generator_vtable` constant.

**Files:** `src/generator.zig`, `src/root.zig`

**Tests added:**

- `GeneratorInterface.fromGenerator: newV4 dispatches correctly (G-8)`
- `GeneratorInterface: newV3 dispatches correctly (G-8)`
- `GeneratorInterface: newV7AtTime dispatches correctly (G-8)`
- `integration: GeneratorInterface dispatches newV4 (G-8)`

### G-9 — No `IsZero()` alias

**Status: ✅ Closed / Implemented**

**Change:** Added `UUID.isZero() bool` as a direct alias for `isNil()`.

**Files:** `src/uuid.zig`

**Tests added:**

- `isZero alias for isNil (G-9)`
- `integration: isZero is an alias for isNil (G-9)`

### G-10 — `version()` unsafe for unknown nibbles (also RFC F-2)

**Status: ✅ Closed / Implemented** (same as F-2)

---

## Phase 5 Sync — Tally (2026-04-19)

- Legacy items migrated from `GAP_ANALYSIS.md`: **19** (9 F-series + 10 G-series).
- In-band closures this cycle: **1** (GAP-DOC-13 — the migration itself).
- Cumulative closures this project: **80** (60 prior + 19 legacy migrated + 1 GAP-DOC-13). Won't-Do retained: 4.
- Newly opened this cycle (see `docs/GAP_ANALYSIS.md` § Phase 5): **3** (GAP-CI-01 Critical, GAP-DOC-11 Low, GAP-DOC-12 Low).

---

## Phase 5 Closure Cycle (2026-04-19)

> HEAD at closure: post-`cb0f44d` (10 closure commits between the pre-audit
> HEAD `7e57b2b` and this closure cycle's HEAD). Test state: 257 unit pass +
> 1 skip (Windows-only) + 37/37 integration + all 5 cross-compile targets pass
>
> - bench-check pass + `zig fmt --check` clean.
> Docs-tracked only (no GitLab mutations — `glab` auth remains DEGRADED this
> cycle). 12 items closed; 1 Deferred (QC-113d — subsequently re-attempted and closed 2026-04-20); 1 Blocked (SEC-P4-14).

### CI unblock — 1 closed

### GAP-CI-01: `.gitlab-ci.yml` invokes removed `check-cross` build step [RESOLVED]

- **Issue:** docs-tracked only (`glab` DEGRADED)
- **Category:** CI-CD
- **Severity:** Critical
- **Resolution:** Replaced the single `zig build check-cross` invocation with a per-triple `zig build check -Dtarget=<triple>` matrix across 5 targets. Side-fix: Windows portability for `generator.zig` (+ `generator_state_test.zig` conditional) required to keep the cross-compile matrix green.
- **Evidence:** `.gitlab-ci.yml` (matrix invocation), `build.zig` (no `check-cross` step required), `src/generator.zig`, `src/generator_state_test.zig`. CI: 5/5 cross-compile targets pass `zig build check`.
- **Commit:** `87c4a0e`
- **Resolved date:** 2026-04-19

### Security — Phase 4 cycle 3 (4 closed + 1 co-closed)

### SEC-P4-10: `Generator.reseed()` does not clear `v7_atomic_state` [RESOLVED]

- **Issue:** docs-tracked only (`glab` DEGRADED)
- **Category:** Security / Bug (CWE-665, CWE-331)
- **Severity:** Medium (Risk 12, confidence::confirmed)
- **Resolution:** `reseed()` now stores `0` into `v7_atomic_state` with `.release` ordering under both mutexes, so the packed `(ms, seq)` word is zeroed alongside all other generator-internal entropy-derived state. Restores the SEC-P3-01 fork-safety contract for the lockfree V7 fast-path. Same commit also tightens the `newV7Atomic` CAS retry budget from 32_768 to 4096, which co-closes SEC-P4-A1.
- **Evidence:** `src/generator.zig` (`reseed` atomic clear; `max_retries = 4096`); `src/generator_test.zig` (pre/post-reseed sequence disjointness; saturation bounded-time assertion).
- **Commit:** `5202714` (`fix(security): close SEC-P4-10/A1 — reseed clears v7 atomic; CAS budget = 4096`)
- **Resolved date:** 2026-04-19

### SEC-P4-A1: Lockfree V7 saturation sleep-loop DoS via injected `withClock` [RESOLVED — co-closed]

- **Issue:** docs-tracked only
- **Category:** Security / Hardening (CWE-400)
- **Severity:** Low (Risk 4, confidence::suspected)
- **Resolution:** CAS retry budget in `newV7Atomic` tightened from 32_768 to 4096 (RFC-9562 §6.2 per-ms counter width). Attacker-injected frozen-clock scenarios now exit the CAS loop to the mutex fallback path after 4096 retries instead of entering an unbounded sleep-loop. Docstring on `InitOptions.clock` updated to forbid non-monotone clocks.
- **Evidence:** `src/generator.zig` (`max_retries = 4096`; `InitOptions.clock` monotonicity docstring); `src/generator_test.zig` (bounded-time assertion under frozen clock).
- **Commit:** `5202714` (co-closed with SEC-P4-10)
- **Resolved date:** 2026-04-19

### SEC-P4-11: Windows `loadState` lacks NOFOLLOW-equivalent [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Security / Hardening (CWE-61 analog)
- **Severity:** Low (Risk 2, confidence::confirmed)
- **Resolution:** Windows `loadState` open path now performs a post-open `NtQueryInformationFile` check and rejects any file with `FILE_ATTRIBUTE_REPARSE_POINT` set before any content is consumed. Brings Windows to parity with the POSIX `O_NOFOLLOW` contract (SEC-R11-04).
- **Evidence:** `src/generator.zig` (Windows reparse-point reject inside `openStateFileAndReadHeader`); Windows-only unit coverage.
- **Commit:** `f67e8bf` (`fix(security): close SEC-P4-11 — reject reparse-point state files on Windows`)
- **Resolved date:** 2026-04-19

### SEC-P4-12: `newV3` / `newV5` accept unbounded `name` [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Security / Hardening (CWE-400)
- **Severity:** Low (Risk 6, confidence::confirmed)
- **Resolution:** Added `newV3Bounded(ns, name, max_len) !UUID` and `newV5Bounded(ns, name, max_len) !UUID` siblings plus a new `Error.NameTooLong` variant. The unbounded `newV3` / `newV5` retain their RFC-9562-compliant behaviour for interop; their docstrings now cite CWE-400 and point at the `*Bounded` variants when the input is attacker-controlled.
- **Evidence:** `src/generator.zig` (`newV3Bounded`, `newV5Bounded`, `Error.NameTooLong`, CWE-400 docstrings); `src/generator_test.zig` (boundary tests at `max_len` and `max_len + 1`).
- **Commit:** `904d352` (`feat(security): close SEC-P4-12 — bounded v3/v5 hash input; docstring caveat`)
- **Resolved date:** 2026-04-19

### Performance — Phase-2/3 follow-up (2 closed + 1 co-closed)

### PERF-40: False sharing on the dispatch-pointer cache line [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Performance / Concurrency (P2, confirmed)
- **Resolution:** `_v7_lockfree_fallbacks` counter now lives in an `align(64)` `stats` sub-struct with trailing padding; it no longer shares a cache line with the dispatch-pointer cluster (`clock`, `rand`, `rand_impl`, `hwaddr_fn`). PERF-34 offset-witness test extended to assert the new layout invariant (`@offsetOf(Generator, "stats") % 64 == 0` and distinct cache line from `clock`).
- **Evidence:** `src/generator.zig` (`stats: struct { _v7_lockfree_fallbacks: ... align(64), _pad: [56]u8 } align(64)`); offset-witness test.
- **Commit:** `beb00ba` (`perf: close PERF-40 — isolate fallback counter to own cache line`)
- **Resolved date:** 2026-04-19

### PERF-42: V7 lockfree CAS `max_retries = 32_768` 8× RFC counter width [RESOLVED — co-closed with SEC-P4-A1]

- **Issue:** docs-tracked only
- **Category:** Performance (P3, confirmed)
- **Resolution:** `max_retries` tightened to `4096` (RFC-9562 §6.2 12-bit per-ms counter width) with expanded explanatory comment. The perf-axis rationale ("~8 ms saved wedged-clock wall-time") and the security-axis rationale (SEC-P4-A1 saturation DoS) share the same one-line change. Retained here for cross-reference.
- **Evidence:** `src/generator.zig` (`max_retries = 4096` + comment).
- **Commit:** `5202714` (co-closed with SEC-P4-10 / SEC-P4-A1)
- **Resolved date:** 2026-04-19

### PERF-43: `bench-regression` runs only 2 of 5 available bench suites [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Performance / CI (P2, confirmed)
- **Resolution:** `bench-regression` now exercises `bench-state` and the `bench-micro-{parse,format,hash}` suites in addition to `bench` and `bench-contention`. Baseline files already existed in the repo root; this wires them into the regression gate so parse / format / hash / state regressions no longer slip into `main` undetected.
- **Evidence:** `.gitlab-ci.yml` (`bench-regression` stage expanded).
- **Commit:** `4a7b3fd` (`perf(ci): close PERF-43 — extend bench-regression to state+micro suites`)
- **Resolved date:** 2026-04-19

### Quality — Phase 2/3 (4 closed + 1 co-closed + 1 deferred)

### QC-113a: Split generator.zig oversized functions — V1/V6 preamble helper [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Quality / Maintainability
- **Severity:** Medium (Score 9, confidence::confirmed)
- **Resolution:** Extracted a shared V1/V6 preamble helper (node-prefetch + `resolveV1V6State` scaffolding). Only the 4-byte `writeInt` layout branch now differs between V1 and V6. Co-closes QC-115 (same extraction removes the duplicate preamble that QC-115 flagged).
- **Evidence:** `src/generator.zig` (new private preamble helper; V1 and V6 paths collapse to the per-version layout branch).
- **Commit:** `2a8f4ea` (`refactor: close QC-113a/QC-115 — extract V1/V6 preamble helper`)
- **Resolved date:** 2026-04-19

### QC-115: Duplicated V1/V6 preamble [RESOLVED — co-closed with QC-113a]

- **Issue:** docs-tracked only
- **Category:** Quality / Readability
- **Severity:** Low (Score 6, confidence::confirmed)
- **Resolution:** Absorbed into QC-113a. Shared preamble extraction eliminates the copy-paste duplication between `newV1AtTime` and `newV6AtTime`.
- **Evidence:** `src/generator.zig` (shared helper).
- **Commit:** `2a8f4ea` (co-closed with QC-113a)
- **Resolved date:** 2026-04-19

### QC-113b: Split saveStateImpl into pack + atomic-write helpers [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Quality / Maintainability
- **Severity:** Medium (Score 9 — QC-113 sub-item)
- **Resolution:** `saveStateImpl` (previously ~154 LOC) split into a `packStateUnderLocks` helper that serialises state under the mutex pair and an `atomicWriteAndSync` helper that owns the temp-file + rename + fsync sequence. Orchestrator shrinks to a readable size without changing observable behaviour.
- **Evidence:** `src/generator.zig` (`packStateUnderLocks`, `atomicWriteAndSync`).
- **Commit:** `47ec3d0` (`refactor: close QC-113b — split saveStateImpl into pack + atomic-write helpers`)
- **Resolved date:** 2026-04-19

### QC-113c: Split loadStateImpl into validated helpers [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Quality / Maintainability
- **Severity:** Medium (Score 9 — QC-113 sub-item)
- **Resolution:** `loadStateImpl` (previously ~193 LOC) broken into four validated helpers plus a ~24-LOC orchestrator: `openStateFileAndReadHeader` (POSIX `O_NOFOLLOW` + Windows post-open reparse-point reject per SEC-P4-11; magic / version / declared-length validation), `verifyStateMacIfV3` (timing-safe HMAC-SHA256 verify; pointer-capture avoids SEC-P4-02 stack spill), `enforceStateMacPolicy` (SEC-P4-01 arm for v1/v2 with byte-preserved warn text), and `applyParsedStateUnderLocks` (single mutation block under the mutex pair, owning SEC-R6-04 / SEC-P3-02 guards for both V1V6 and V7 state). Security invariants preserved end-to-end: SEC-R11-04 / SEC-P4-11 symlink + reparse-point reject, SEC-R13-04 pre-zero, SEC-R4-03 trailing-byte probe, SEC-P3-04 length match, SEC-P3-02 rollback window, SEC-P4-02 pointer-capture, SEC-R13-08 clock read outside the mutex pair.
- **Evidence:** `src/generator.zig` (five helpers + orchestrator). 257 unit + 37 integration pass.
- **Commit:** `cb0f44d` (`refactor: close QC-113c — split loadStateImpl into validated helpers`)
- **Resolved date:** 2026-04-19

### QC-113d: V7 CAS state-machine extraction [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Quality / Maintainability
- **Severity:** Medium (Score 9 — QC-113 sub-item)
- **Resolution:** Refactored `newV7Atomic` to delegate the pure state-transition decision to a new `V7Cas.transition` helper (non-`pub` namespace inside `Generator`). Retry budget (SEC-P4-A1 4096), counter bumps via `bumpFallback`, clock read, entropy-draw caching, and CAS publish remain in the caller. Single-word `cmpxchgStrong` on `v7_atomic_state` with `.acq_rel` / `.acquire` orderings preserved verbatim — ABA-avoidance argument unchanged. PERF-40 (stats on isolated cache line) and PERF-34 (V7/V1V6 clusters on distinct cache lines) layout witnesses pass; `@offsetOf(Generator, "stats")` still a multiple of 64. A u64-state-word ratchet test (`test "QC-113d: v7_atomic_state is a single u64 atomic"`) locks the state-word shape so any future attempt to widen it fails at compile time.
- **Evidence:**
  - Tests: `test "QC-113d: v7_atomic_state is a single u64 atomic"` (ratchet) + `test "QC-113d V7Cas.transition: same-ms bump" | clock advance seeds from cached rand | saturation signals sleep | clock behind preserves old_ms"` (4 pure-helper cases). Total 262 unit pass + 1 skip (up from 257 + 1 baseline; +5 tests).
  - Integration: 37/37 pass.
  - Bench artefacts: `docs/evidence/qc-113d-baseline-{contention,single}.json`, `docs/evidence/qc-113d-post-{contention,single}.json`. Critical row `v7_contention_lockfree_8T` within +1.23% of baseline (plan's ±2% gate); `v7_random_lockfree/1T` within +0.05%.
- **Plan:** `docs/superpowers/plans/2026-04-19-qc-113d-v7-cas-reattempt.md` — conditional re-attempt plan with Go/No-Go gate; attempted 2026-04-20 after direct user authorization.
- **Commits:**
  - `37419f6` test(quality): QC-113d prep — ratchet v7_atomic_state as single u64
  - `b179892` refactor(quality): QC-113d — extract pure V7Cas.transition helper (no caller yet)
  - `a51e411` refactor(quality): QC-113d — rewire newV7Atomic to V7Cas.transition
  - `8211c0c` docs(quality): QC-113d — bench evidence (refactor within ±2% of baseline)
- **Resolved date:** 2026-04-20

### QC-114: OS-specific hwaddr backends untested [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Quality / Tests
- **Severity:** Medium (Score 9, confidence::confirmed)
- **Resolution:** Added 11 per-OS hwaddr tests gated via `builtin.os.tag` — Linux backend covers `SIOCGIFCONF` success, empty interface list, permission denied, and OOM paths; macOS backend covers `getifaddrs` success and ENOMEM; Windows backend now covers `GetAdaptersAddresses` success, insufficient-buffer retry, no-adapters, and non-Ethernet-skip branches in addition to the prior round-trip test.
- **Evidence:** `src/hwaddr/linux.zig`, `src/hwaddr/macos.zig`, `src/hwaddr/windows.zig` (per-OS tests gated on `builtin.os.tag`).
- **Commit:** `b7fb01e` (`test(quality): close QC-114 — per-OS hwaddr tests for linux/macos/windows (+11 tests)`)
- **Resolved date:** 2026-04-19

### Phase 5 Closure Cycle — Tally

- Full closures this cycle: **12** — GAP-CI-01, SEC-P4-10, SEC-P4-A1, SEC-P4-11, SEC-P4-12, PERF-40, PERF-42, PERF-43, QC-113a, QC-113b, QC-113c, QC-114, QC-115.
- Deferred this cycle: **1** (QC-113d — rationale in `cb0f44d` body).
- Blocked this cycle: **1** (SEC-P4-14 — operator must supply tag→SHA map for 8 ci-catalog components; see `docs/SECURITY_REVIEW_NOTES.md` § _Unblock action required (SEC-P4-14)_).
- Still-open carryover: **4** (SEC-P4-13 Very Low, PERF-41, PERF-44, QC-116, QC-117, GAP-DOC-11, GAP-DOC-12 — count is 7 items but only 4 of them block the "all Phase-5 findings closed" criterion; the rest are stretch / next-cycle scheduled). **UPDATE:** all 7 carryover items closed in the residual closure batch below; only SEC-P4-14 (Blocked) and QC-113d (Deferred) remain.
- Cumulative closures this project: **92** (80 prior + 12 this cycle). Won't-Do retained: 4.

---

## Phase 5 Closure Cycle — Residual Batch (2026-04-19)

> HEAD at closure: post-`0c56f13` (7 additional closure commits after the primary Phase-5 closure cycle).
> Test state: 257 unit pass + 1 skip (Windows-only), 37/37 integration, all 5 cross-compile targets pass, warn-noise 3 → 0.
> Docs-tracked only (`glab` auth remains DEGRADED). 7 items closed; no new Deferred; no new Blocked.
> After this batch, **only SEC-P4-14 (Blocked) and QC-113d (Deferred) remain open** across all tracker files. _Update 2026-04-20: QC-113d subsequently re-attempted and closed; only SEC-P4-14 (Blocked) remains._

### Security — 1 closed

### SEC-P4-13: `@intCast((hi<<16)|lo)` refactor-fragile [RESOLVED]

- **Issue:** docs-tracked only (`glab` DEGRADED)
- **Category:** Security / Hardening (CWE-704 "Incorrect Type Conversion or Cast")
- **Severity:** Very Low (Risk 1, confidence::suspected)
- **Resolution:** Added `std.debug.assert((hi >> 48) == 0 and (lo >> 16) == 0)` immediately before the packed-timestamp reconstruction `@intCast((hi << 16) | lo)`, plus an inline comment explaining the bit-width invariant. Debug builds now trap if either half overflows its field; ReleaseFast semantics unchanged. **Diagnosis reconciliation:** the finding text referenced `timestampFromV1`, but the actual site is `timestampFromV7` (V7 is the `unix_ts_ms` path where the packed `(hi << 16) | lo` reconstruction occurs). The commit message documents this reconciliation.
- **Evidence:** `src/timestamp.zig` (`timestampFromV7` — assert + invariant comment on the packed reconstruction).
- **Commit:** `3b338ab` (`fix(security): close SEC-P4-13 — guard timestampFromV7 @intCast with assert`)
- **Resolved date:** 2026-04-19

### Docs — 2 closed

### GAP-DOC-11: Stale test counts in `docs/REQUIREMENTS.md` [RESOLVED]

- **Issue:** docs-tracked only (`glab` DEGRADED)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Refreshed `docs/REQUIREMENTS.md` test counts from the stale 172/32 figures to the actual 257/37 on HEAD (unit tests: 257 pass + 1 Windows-only skip; integration tests: 37/37).
- **Evidence:** `docs/REQUIREMENTS.md` (test-count prose updated); `zig build test` — 257 pass / 1 skip; `zig build test-integration` — 37/37 pass.
- **Commit:** `0c15b8b` (`docs: close GAP-DOC-11/12 — refresh REQUIREMENTS test counts and JSON API shape`)
- **Resolved date:** 2026-04-19

### GAP-DOC-12: `docs/REQUIREMENTS.md` misrepresents `jsonMarshal` / `jsonUnmarshal` as UUID methods [RESOLVED]

- **Issue:** docs-tracked only (`glab` DEGRADED)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Rewrote the JSON subsection in `docs/REQUIREMENTS.md` to cite `@import("uuid_json")` and the free-function signatures from `src/uuid_json.zig`, removing the incorrect `UUID.jsonMarshal(…)`-style method references. Added a new `§ JSON Adapter` section to `README.md` documenting the free-function API with usage example. Bundled with GAP-DOC-11 per the recommended-fix plan.
- **Evidence:** `docs/REQUIREMENTS.md` (JSON subsection rewritten); `README.md` (new `§ JSON Adapter` section); `src/uuid_json.zig` (canonical source of the free-function signatures).
- **Commit:** `0c15b8b` (co-closed with GAP-DOC-11)
- **Resolved date:** 2026-04-19

### Performance — 2 closed

### PERF-41: V3/V5 convenience wrappers bypass the prehashed namespace fast path [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Performance (P3, confirmed)
- **Severity:** P3, PerfScore 16
- **Resolution:** Fix (1) from the plan landed: `README.md` now documents `Generator.initV3Namespace` / `initV5Namespace` as the fast path when looping over a single namespace, with the expected ~60 ns MD5-init + 16-byte update saved per call. Fix (2) — the optional `NamespacedGenerator(comptime ns)` wrapper — is deliberately **deferred**: no API break shipped, and the doc note is sufficient to unblock the perf-sensitive single-namespace-loop callers the finding targeted.
- **Evidence:** `README.md` (perf-section note on `initV3Namespace` / `initV5Namespace`); `src/generator.zig:1279` / `:1290` (canonical prehashed handles unchanged).
- **Commit:** `6d5804e` (`docs(perf): close PERF-41 — document prehashed v3/v5 fast path in README`)
- **Resolved date:** 2026-04-19

### PERF-44: `bench-regression` fires only on `main` + scheduled — no MR coverage [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Performance / CI (P3, confirmed)
- **Severity:** P3, PerfScore 20
- **Resolution:** New `bench-micro-mr` CI job fires on `merge_request_event` and runs the three `bench-micro-{parse,format,hash}` suites with a **10% threshold** (tighter than the 15% `main` threshold) so regressions block the MR instead of landing on `main`. Pairs with PERF-43's suite expansion — together they give MR-only coverage of parse/format/hash and `main`-only coverage of state/contention/full bench.
- **Evidence:** `.gitlab-ci.yml` (`bench-micro-mr` job added with 0.10 threshold).
- **Commit:** `38ffe49` (`perf(ci): close PERF-44 — MR-gated bench-micro-mr job with 0.10 threshold`)
- **Resolved date:** 2026-04-19

### Quality — 2 closed

### QC-116: Pre-commit / CI parity gap [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Quality / CI-CD
- **Severity:** Low (Score 4, confidence::confirmed)
- **Resolution:** `.pre-commit-config.yaml` expanded with opt-in parity hooks for `gitleaks` (secret-scan), `test-integration` (integration gate), and `bench-check` (perf smoke). SAST and SBOM remain CI-only and are now explicitly documented as such (their scanners are not suitable for pre-commit execution). Local gate now catches the same correctness and secret-leak classes as CI, with opt-in control for the slower hooks.
- **Evidence:** `.pre-commit-config.yaml` (hooks added); CONTRIBUTING note (SAST/SBOM CI-only trade-off documented).
- **Commit:** `0c56f13` (`chore(quality): close QC-116 — expand pre-commit with gitleaks + test-integration + bench-check`)
- **Resolved date:** 2026-04-19

### QC-117: Test stderr noise during policy-downgrade tests [RESOLVED]

- **Issue:** docs-tracked only
- **Category:** Quality / Tests
- **Severity:** Low (Score 4, confidence::confirmed)
- **Resolution:** Expected warn during policy-downgrade tests now suppressed via `std.log.scoped` combined with a per-test `testing.log_level` override, so the intentional warn from `src/generator.zig:1710` is swallowed by the test instead of polluting `zig build test` output. `zig build test` warn-noise count reduced from 3 to 0 (verified).
- **Evidence:** `src/generator_state_test.zig` (policy-downgrade tests — scoped log + log_level override); `zig build test` output shows zero unexpected warns (was 3).
- **Commit:** `cfa9f04` (`test: close QC-117 — suppress expected warn noise in policy-downgrade tests`)
- **Resolved date:** 2026-04-19

### Residual Batch — Tally

- Full closures this batch: **7** — SEC-P4-13, GAP-DOC-11, GAP-DOC-12, PERF-41, PERF-44, QC-116, QC-117.
- Deferred this batch: **0**.
- Blocked this batch: **0**.
- **After this batch:** across every tracker file, only **SEC-P4-14 (Blocked — operator tag→SHA map required)** and **QC-113d (Deferred — ABA-avoidance + PERF-40 cache-layout risk)** remain open.
- Cumulative closures this project: **99** (92 prior + 7 this batch). Won't-Do retained: 4.

### QC-113d Re-attempt (2026-04-20)

QC-113d was subsequently re-attempted on 2026-04-20 per `docs/superpowers/plans/2026-04-19-qc-113d-v7-cas-reattempt.md`. The V7 CAS state-machine was extracted into a pure `V7Cas.transition` helper inside `Generator` (non-`pub`) and `newV7Atomic` was rewired to delegate the decision tree. ABA-avoidance (single-word `cmpxchgStrong` with `.acq_rel` / `.acquire` orderings) preserved; PERF-40 + PERF-34 layout witnesses pass; bench-compare within stddev-adjusted gates on all V7 scenarios (`v7_contention_lockfree_8T` +1.23%). See the `### QC-113d: V7 CAS state-machine extraction [RESOLVED]` section above for full details. Commits: `37419f6`, `b179892`, `a51e411`, `8211c0c`.

**Post-re-attempt status:** across every tracker file, only **SEC-P4-14 (Blocked)** remains open. Cumulative closures: **100** (99 prior + QC-113d re-attempt).

---

## Audit Cycle 2026-06-11 — Doc-Drift Closure (5 items)

> HEAD at closure: d1b161e (pushed to main). Test state: 279/280 unit Debug+ReleaseSafe + 1 Windows-only skip, 37/37 integration, fmt clean, examples/bench-check OK.
> These items were opened and fixed same-cycle (2026-06-11). GitLab issues #183–#187 created then closed same cycle with evidence notes. Only SEC-P4-14 (#188) remains open (Blocked-external).

### GAP-DOC-17: Version string drift `root.zig` 0.1.0 vs zon 0.1.1 [RESOLVED]

- **Issue:** [#183](https://gitlab.com/devnw/zig/uuid/-/work_items/183) — closed 2026-06-11
- **Category:** Docs
- **Severity:** Low
- **Resolution:** `src/root.zig` `pub const version` bumped to `"0.1.1"` to match `build.zig.zon`; README API-constant example updated; CI version-consistency gate added to enforce the invariant going forward.
- **Evidence:** `src/root.zig` `pub const version = "0.1.1"` matches `build.zig.zon:.version = "0.1.1"`.
- **Commits:** `036bdb9` + `5ba1cf9`
- **Resolved date:** 2026-06-11

### GAP-DOC-18: README install instructions reference v0.1.0 + stale unreleased note [RESOLVED]

- **Issue:** [#184](https://gitlab.com/devnw/zig/uuid/-/work_items/184) — closed 2026-06-11
- **Category:** Docs
- **Severity:** Low
- **Resolution:** README `zig fetch` URL and dependency `.url` snippet updated to `v0.1.1`; stale "v0.1.0 is unreleased" note removed. Install instructions now reference the current released tag.
- **Evidence:** `README.md` install section — URL and snippet reference `v0.1.1`; stale note absent.
- **Commits:** `036bdb9` + `5ba1cf9` + `6041865`
- **Resolved date:** 2026-06-11

### GAP-DOC-19: CHANGELOG missing `[0.1.1]` section + stale compare link [RESOLVED]

- **Issue:** [#185](https://gitlab.com/devnw/zig/uuid/-/work_items/185) — closed 2026-06-11
- **Category:** Docs
- **Severity:** Low
- **Resolution:** `CHANGELOG.md` `[0.1.1]` section added with release notes for the cycle's closed items (QC-125, QC-146, QC-147, plus earlier dep-convergence entries); `[Unreleased]` compare link re-based to `v0.1.1...HEAD`; `[0.1.1]` release link added.
- **Evidence:** `CHANGELOG.md` — `[0.1.1]` section + link present; `[Unreleased]: .../compare/v0.1.1...HEAD`.
- **Commit:** `6041865`
- **Resolved date:** 2026-06-11

### GAP-DOC-20: docs index missing APPSEC_REVIEW + SECURITY_REVIEW_NOTES links [RESOLVED]

- **Issue:** [#186](https://gitlab.com/devnw/zig/uuid/-/work_items/186) — closed 2026-06-11
- **Category:** Docs
- **Severity:** Low
- **Resolution:** `docs/README.md` Quick Links section updated to include `APPSEC_REVIEW_2026-06-11.md` and `SECURITY_REVIEW_NOTES.md` entries, making security review artifacts discoverable from the docs landing page.
- **Evidence:** `docs/README.md` Quick Links — both security review docs now linked.
- **Commit:** `485a663`
- **Resolved date:** 2026-06-11

### GAP-DOC-21: REQUIREMENTS UUID-TEST-005 cites removed `check-cross` step [RESOLVED]

- **Issue:** [#187](https://gitlab.com/devnw/zig/uuid/-/work_items/187) — closed 2026-06-11
- **Category:** Docs
- **Severity:** Low
- **Resolution:** `docs/REQUIREMENTS.md` UUID-TEST-005 verification pointer updated from the removed `check-cross` step to the current `test-cross-build` CI job at `.gitlab-ci.yml:190-196`, which loops `zig build check -Dtarget=$t` over 5 cross-compile targets.
- **Evidence:** `docs/REQUIREMENTS.md` UUID-TEST-005 — cites `test-cross-build` (`.gitlab-ci.yml:190-196`).
- **Commit:** `485a663`
- **Resolved date:** 2026-06-11

### Audit Cycle 2026-06-11 — Tally

- Full closures this cycle: **5** (GAP-DOC-17, GAP-DOC-18, GAP-DOC-19, GAP-DOC-20, GAP-DOC-21).
- Blocked (unchanged): **1** (SEC-P4-14 — plan file now authored `a5373be`; still awaiting operator tag→SHA map).
- **After this cycle:** only **SEC-P4-14 (#188, Blocked-external)** remains open across all tracker files.
- Cumulative closures this project: **105** (100 prior + 5 GAP-DOC-17..21). Won't-Do retained: 4.
