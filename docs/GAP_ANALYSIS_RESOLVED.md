# Gap Analysis -- Resolved

> Mirror of resolved items that were previously tracked in `docs/GAP_ANALYSIS.md`
> and the GitLab issue tracker. The issue tracker is authoritative.
>
> Last updated: 2026-04-18 (Group D closure round — 5 additional resolutions appended; cumulative 60; 4 full + 1 partial this round)

## Summary

- **25 prior tracker items** (Cycles 12–13): resolved in-code; still marked open on the GitLab tracker; closure queued in the Phase-3 `glab` block in `docs/GAP_ANALYSIS.md`.
- **16 Phase-3 initial closure-cycle items** (2026-04-18): see "Phase 3 Closure Cycle" section. Docs-tracked only.
- **11 Group C closure-round items** (2026-04-18, HEAD `5bee3e7`): 10 full closures + 1 partial (PERF-31 doc mitigation). See "Group C Closure Round" section. Docs-tracked only.
- **5 Group D closure-round items** (2026-04-18, HEAD `f77e7da`): 4 full closures (PERF-21, PERF-31 promoted, SEC-P3-04, SEC-P3-08) + 1 partial (SEC-P3-07 — 3 human-input TODOs). See "Group D Closure Round" section. Docs-tracked only.

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
> (SEC-P3-07 — `security.txt`, CVSS v4.0, and safe-harbor skeleton landed; full
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
- **Resolution (partial):** Landed the mechanical portions that do not require human legal / cryptographic input: (a) `/.well-known/security.txt` published per RFC 9116 with contact, preferred-languages, and expiration; (b) CVSS v4.0 severity statement section added to `SECURITY.md`; (c) safe-harbor language skeleton (Disclose.io-derived) added to `SECURITY.md` as a draft awaiting legal review.
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
