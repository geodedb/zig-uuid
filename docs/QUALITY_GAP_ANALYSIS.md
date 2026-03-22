# UUID Library — Code Quality Gap Analysis

> **Scope:** Code quality, maintainability, readability, test coverage, documentation, and CI/CD quality.
> **Date:** 2026-03-21
> **Zig version audited:** 0.15.2 (CI: 0.15.1)
> **Previous reviews:** `docs/GAP_ANALYSIS.md` (RFC-9562 compliance), `docs/PERF_GAP_ANALYSIS.md` (performance) — findings from those reviews are not duplicated here.

---

## Summary

| Severity | Count | Status |
| -------- | ----- | ------ |
| High     | 3     | ✅ All closed |
| Medium   | 5     | ✅ All closed |
| Low      | 9     | ✅ 8 closed, 🚫 1 Won't Do |

**Total issues:** 17 — **16 closed, 1 Won't Do (QC-16)**

### Top 5 Risks

1. **README Quick Start is wrong** (QC-5) — `uuid.init()` does not exist; new users cannot follow the documentation.
2. **Duplicated V1/V6 generator body** (QC-1) — ~35 lines of shared logic that must stay in sync across two functions; any future bug fix must be applied twice.
3. **Inconsistent error type in newV7AtTime** (QC-2) — same condition (negative timestamp) returns `InvalidFormat` in one call path and `InvalidTimestamp` in another.
4. **Windows cross-compile absent from CI** (QC-8) — `hwaddr/windows.zig` is never tested in CI; breakage is invisible.
5. **Missing error-path tests** (QC-13) — `newV7AtTime(-1)` guard and hwaddr fallback-to-random are untested.

---

## Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Fix Summary | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ----------- | ------ |
| 1 | High | 80 | maintainability | Duplicated newV1AtTime / newV6AtTime body | `src/generator.zig:250–350` | Two ~35-line identical blocks | [#22](https://gitlab.com/devnw/zig/uuid/-/work_items/22) | Extract shared V1/V6 state-resolution helper | ✅ Closed |
| 2 | High | 80 | api-contract | newV7AtTime returns InvalidFormat for negative ts; newV7 returns InvalidTimestamp | `src/generator.zig:117,124` | Two error values for same condition | [#23](https://gitlab.com/devnw/zig/uuid/-/work_items/23) | Change line 124 to return InvalidTimestamp | ✅ Closed |
| 3 | High | 64 | docs | README Quick Start calls non-existent uuid.init() | `README.md:47` | `uuid.init` not in root.zig | [#26](https://gitlab.com/devnw/zig/uuid/-/work_items/26) | Replace with correct newV7/newV4 example | ✅ Closed |
| 4 | Medium | 60 | maintainability | generator.zig at 1301 lines — exceeds 800-line guideline | `src/generator.zig` | `wc -l src/generator.zig` = 1301 | [#25](https://gitlab.com/devnw/zig/uuid/-/work_items/25) | Moved test block to generator_test.zig (716 lines remaining) | ✅ Closed |
| 5 | Medium | 48 | ci-cd | Windows cross-compile not verified in CI | `.gitlab-ci.yml:110–121` | Missing x86_64-windows in test-cross-build | [#29](https://gitlab.com/devnw/zig/uuid/-/work_items/29) | Added x86_64-windows to CI cross-compile job | ✅ Closed |
| 6 | Medium | 48 | tests | Missing tests: newV7AtTime negative ts, hwaddr fallback | `src/generator.zig:124,226` | No test exercises either guard | [#34](https://gitlab.com/devnw/zig/uuid/-/work_items/34) | Added two targeted unit tests in generator_test.zig | ✅ Closed |
| 7 | Medium | 36 | docs | docs/README.md links to 5 non-existent files | `docs/README.md:7–13` | `ls docs/` confirms files absent | [#27](https://gitlab.com/devnw/zig/uuid/-/work_items/27) | Removed broken links; replaced with accurate API overview | ✅ Closed |
| 8 | Medium | 36 | ci-cd | CI Zig version (0.15.1) does not match dev (0.15.2) | `.gitlab-ci.yml:23` | Version skew confirmed | [#28](https://gitlab.com/devnw/zig/uuid/-/work_items/28) | Updated ZIG_VERSION to 0.15.2 | ✅ Closed |
| 9 | Medium | 36 | tests | Global mutable test state risks test isolation | `src/generator.zig:964–978` | Module-level rfc_v7_rand_pos var | [#33](https://gitlab.com/devnw/zig/uuid/-/work_items/33) | Replaced separate pos+data vars with V7MockRandState struct | ✅ Closed |
| 10 | Low | 32 | readability | Duplicated multicast bit set in fetchRawNode | `src/generator.zig:228,233` | Two identical `node[0] \|= 0x01` lines | [#24](https://gitlab.com/devnw/zig/uuid/-/work_items/24) | Extracted multicast_bit constant + randomMulticastNode helper | ✅ Closed |
| 11 | Low | 24 | docs | versions.zig public API has no doc comments | `src/versions.zig:11–49` | Zero `///` comments on 10 public functions | [#30](https://gitlab.com/devnw/zig/uuid/-/work_items/30) | Added doc comments to all 10 public functions | ✅ Closed |
| 12 | Low | 20 | readability | parseHash uses charToDigit; parseCanonical uses hexVal — two hex decode paths | `src/uuid.zig:401,412` | Inconsistent implementation | [#32](https://gitlab.com/devnw/zig/uuid/-/work_items/32) | Unified parseHash to use hexVal | ✅ Closed |
| 13 | Low | 20 | ci-cd | examples/ not built or verified in CI | `.gitlab-ci.yml`, `build.zig` | No CI job or build step for examples | [#36](https://gitlab.com/devnw/zig/uuid/-/work_items/36) | Added `examples` step to build.zig + `build-examples` CI job | ✅ Closed |
| 14 | Low | 16 | maintainability | macos.zig header_size hardcoded as 8 instead of @offsetOf | `src/hwaddr/macos.zig:77` | `const header_size: usize = 8` | [#31](https://gitlab.com/devnw/zig/uuid/-/work_items/31) | Replace with @offsetOf(sockaddr_dl, "sdl_data") | ✅ Closed |
| 15 | Low | 16 | ci-cd | check-todos pre-commit hook always exits 0 — never blocks | `.pre-commit-config.yaml:82` | Final `\|\| exit 0` makes it a no-op | [#37](https://gitlab.com/devnw/zig/uuid/-/work_items/37) | Pre-commit hooks handled by separate controls per policy | 🚫 Won't Do |
| 16 | Low | 16 | docs | CHANGELOG.md has placeholder date YYYY-MM-DD | `CHANGELOG.md:17` | Placeholder not filled in | [#35](https://gitlab.com/devnw/zig/uuid/-/work_items/35) | Document actual 0.1.0 features with real date | ✅ Closed |
| 17 | Low | 12 | tests | bench/main.zig omits V6 benchmark | `bench/main.zig:22–26` | No benchV6 function | [#38](https://gitlab.com/devnw/zig/uuid/-/work_items/38) | Add benchV6 mirroring benchV1 | ✅ Closed |

---

## Findings by Category

### Maintainability

#### QC-1 — Duplicated newV1AtTime / newV6AtTime body (High, Score 80)

**File:** `src/generator.zig:250–350`

`newV1AtTime` and `newV6AtTime` share ~35 lines of identical code covering: PERF-05 prefetch pattern, mutex acquisition, `initClockSeq`, same-timestamp clock_seq increment, double-checked node cache population, F-4 node-change detection, and `last_node` update. Only the 7-line timestamp encoding block differs. Any future maintenance to the shared logic must be applied in two places.

**Fix:** Extract a private `resolveV1V6State` helper returning `(t, node, clock_seq)`. Each public function becomes a 10-line wrapper.

**Confidence:** confirmed

---

#### QC-2 — Inconsistent error type in newV7AtTime vs newV7 (High, Score 80)

**File:** `src/generator.zig:117,124`

`newV7` returns `Error.InvalidTimestamp` for a pre-epoch clock; `newV7AtTime` returns `Error.InvalidFormat` for a negative `ts` argument. The same semantic condition (timestamp before epoch) produces different errors depending on call path.

**Fix:** Change `src/generator.zig:124` from `return Error.InvalidFormat` to `return Error.InvalidTimestamp`.

**Confidence:** confirmed

---

#### QC-4 — generator.zig at 1301 lines (Medium, Score 60)

**File:** `src/generator.zig`

At 1301 lines (tests: lines 706–1301, ~595 lines), the file is 63% over the 800-line soft limit. Mixed production code and tests in one file increases cognitive load.

**Fix:** Move the test block to `src/generator_test.zig`.

**Confidence:** confirmed

---

#### QC-10 — macos.zig header_size hardcoded (Low, Score 16)

**File:** `src/hwaddr/macos.zig:77`

`const header_size: usize = 8` should be `@offsetOf(c.sockaddr_dl, "sdl_data")` so the compiler validates correctness if the struct layout changes.

**Confidence:** confirmed

---

### Readability

#### QC-3 — Duplicated multicast bit set (Low, Score 32)

**File:** `src/generator.zig:228,233`

`node[0] |= 0x01` appears in two branches of `fetchRawNode` for the same semantic operation. A named constant and a private helper would keep both paths in sync.

**Confidence:** confirmed

---

#### QC-11 — Two hex decode paths (Low, Score 20)

**File:** `src/uuid.zig:401,412`

`parseCanonical` uses private `hexVal`; `parseHash` uses `std.fmt.charToDigit`. Both are semantically identical but different implementations.

**Confidence:** confirmed

---

### Tests

#### QC-12 — Global mutable test state (Medium, Score 36)

**File:** `src/generator.zig:964–978`

Module-level `var rfc_v7_rand_pos` is shared across the test file. While reset at test entry, this anti-pattern risks ordering-dependent failures if tests are ever parallelised or reordered.

**Confidence:** confirmed

---

#### QC-13 — Missing error-path tests (Medium, Score 48)

**File:** `src/generator.zig:124,226`

Two error paths have no tests: `newV7AtTime(-1)` negative guard, and the hwaddr fallback-to-random path when `hwaddr_fn` fails.

**Confidence:** confirmed

---

#### QC-17 — Missing V6 benchmark (Low, Score 12)

**File:** `bench/main.zig:22–26`

V6 throughput is not characterized. Given V6 is the recommended k-sortable alternative to V1, its performance relative to V1 and V7 is a gap in the benchmark suite.

**Confidence:** confirmed

---

### Documentation

#### QC-5 — README Quick Start calls non-existent uuid.init() (High, Score 64)

**File:** `README.md:47`

The Quick Start example shows `try uuid.init(.{ .debug = true })`. This function does not exist. Additionally the "Zero Dependencies" claim is false — the library depends on `gitlab.com/devnw/zig/json`.

**Fix:** Replace with a correct snippet using `uuid.newV7()`. Remove or correct the dependency claim.

**Confidence:** confirmed

---

#### QC-6 — Broken docs/README.md links (Medium, Score 36)

**File:** `docs/README.md:7–13`

Links to `getting-started.md`, `api-reference.md`, `examples.md`, `architecture.md`, and `faq.md` — none of which exist.

**Confidence:** confirmed

---

#### QC-9 — versions.zig has no doc comments (Low, Score 24)

**File:** `src/versions.zig:11–49`

All 10 public convenience functions have no `///` doc comments. These are the primary API entry points visible to `zig doc` users.

**Confidence:** confirmed

---

#### QC-14 — CHANGELOG.md placeholder date (Low, Score 16)

**File:** `CHANGELOG.md:17`

`[0.1.0] - YYYY-MM-DD` has a template placeholder date and does not describe the actual features implemented.

**Confidence:** confirmed

---

### CI/CD

#### QC-7 — Zig version skew between CI and dev (Medium, Score 36)

**File:** `.gitlab-ci.yml:23`

CI pins `ZIG_VERSION: "0.15.1"` while `zig version` returns `0.15.2` and `build.zig.zon` specifies minimum `0.15.1`. Dev tests on a version that CI does not use.

**Fix:** Update `ZIG_VERSION` to `"0.15.2"`.

**Confidence:** confirmed

---

#### QC-8 — Windows cross-compile absent from CI (Medium, Score 48)

**File:** `.gitlab-ci.yml:110–121`

`test-cross-build` CI job omits `x86_64-windows` despite `build.zig`'s `check-cross` step including it. `hwaddr/windows.zig` is never verified in CI.

**Fix:** Add `-Dtarget=x86_64-windows` to the CI cross-compile job, or use `zig build check-cross`.

**Confidence:** confirmed

---

#### QC-15 — examples/ not built in CI (Low, Score 20)

**File:** `.gitlab-ci.yml`, `build.zig`

`examples/basic.zig` is never compiled in CI. API drift between the example and the library (as seen in QC-5) will produce no CI signal.

**Confidence:** confirmed

---

#### QC-16 — check-todos hook is a no-op (Low, Score 16) — 🚫 Won't Do

**File:** `.pre-commit-config.yaml:82`

`exit 0 || exit 0` ensures the hook never blocks a commit, making it ineffective.

**Resolution:** Won't Do. Pre-commit hook enforcement (including CI/CD hash pinning and Docker tag pinning) is handled by separate controls outside this repository. Fixing individual hooks in `.pre-commit-config.yaml` is out of scope for this codebase. Future agents should not re-open this item.

**Confidence:** confirmed

---

## Action Plan

### Quick Wins (S effort, high impact — do first)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#23](https://gitlab.com/devnw/zig/uuid/-/work_items/23) | Fix newV7AtTime error type | S | High |
| [#26](https://gitlab.com/devnw/zig/uuid/-/work_items/26) | Fix README Quick Start | S | High |
| [#28](https://gitlab.com/devnw/zig/uuid/-/work_items/28) | Update CI Zig version | S | Medium |
| [#29](https://gitlab.com/devnw/zig/uuid/-/work_items/29) | Add Windows to CI cross-compile | S | Medium |
| [#34](https://gitlab.com/devnw/zig/uuid/-/work_items/34) | Add missing error-path tests | S | Medium |
| [#30](https://gitlab.com/devnw/zig/uuid/-/work_items/30) | Add doc comments to versions.zig | S | Medium |
| [#32](https://gitlab.com/devnw/zig/uuid/-/work_items/32) | Unify hex decode to hexVal | S | Low |
| [#24](https://gitlab.com/devnw/zig/uuid/-/work_items/24) | Extract multicast bit helper | S | Low |
| [#31](https://gitlab.com/devnw/zig/uuid/-/work_items/31) | Use @offsetOf for header_size | S | Low |
| [#35](https://gitlab.com/devnw/zig/uuid/-/work_items/35) | Fill in CHANGELOG date/content | S | Low |
| [#36](https://gitlab.com/devnw/zig/uuid/-/work_items/36) | Wire examples into build+CI | S | Low |
| [#37](https://gitlab.com/devnw/zig/uuid/-/work_items/37) | Fix check-todos hook | S | Low |
| [#38](https://gitlab.com/devnw/zig/uuid/-/work_items/38) | Add V6 benchmark | S | Low |

### Medium-term (M effort)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#22](https://gitlab.com/devnw/zig/uuid/-/work_items/22) | Extract V1/V6 shared logic helper | M | High |
| [#25](https://gitlab.com/devnw/zig/uuid/-/work_items/25) | Split generator.zig test block | M | Medium |
| [#27](https://gitlab.com/devnw/zig/uuid/-/work_items/27) | Create missing docs files | M | Medium |
| [#33](https://gitlab.com/devnw/zig/uuid/-/work_items/33) | Remove global mutable test state | S | Medium |

---

_Last updated: 2026-03-21 (Cycle 1)_

---

## Quality Review Cycle 2

> **Date:** 2026-03-21
> **Zig version audited:** 0.15.2
> **Previous cycle:** Cycle 1 above — QC-1 through QC-17, all fixed in code (issues #22–#38 remain open in GitLab; see QC-23).
> **Scope:** New findings only — items already addressed in Cycle 1 are not re-opened.

---

### Summary

| Severity | Count |
| -------- | ----- |
| High     | 2     |
| Medium   | 2     |
| Low      | 2     |

**Total new issues:** 6 — all open, status::triage

### Top 5 Risks

1. **CI 'build' job is a no-op** (QC-18) — `zig build` with no install artifacts compiles only the build runner, not uuid source. Source errors pass the build gate undetected.
2. **Cross-compile CI is ineffective** (QC-19) — `zig build -Dtarget=X` is the same no-op; `hwaddr/windows.zig` and platform files are never cross-compiled in CI despite QC-8 claiming to fix this.
3. **bench/main.zig never compiled in CI** (QC-20) — benchmark API drift is invisible to CI; the same gap QC-15 fixed for `examples/` applies here.
4. **saveState/loadState absolute-path requirement undocumented** (QC-21) — callers passing relative paths get an opaque OS error with no guidance.
5. **GeneratorInterface tests cover only 3 of 10 vtable methods** (QC-22) — 7 dispatch trampolines have zero test coverage.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | High | 80 | ci-cd | CI 'build' job runs `zig build` (no source compilation) | `.gitlab-ci.yml:42-52` | `zig build` with no installArtifact compiles only build runner; `zig-out/` never created | [#61](https://gitlab.com/devnw/zig/uuid/-/work_items/61) | ✅ Closed |
| 2 | High | 80 | ci-cd | test-cross-build uses `zig build -Dtarget=X` (no-op) not `zig build check-cross` | `.gitlab-ci.yml:119-132` | Same no-op as QC-18; hwaddr platform files never cross-compiled | [#62](https://gitlab.com/devnw/zig/uuid/-/work_items/62) | ✅ Closed |
| 3 | Medium | 48 | ci-cd | bench/main.zig never compiled in CI | `.gitlab-ci.yml` | No CI job runs `zig build bench`; API drift in bench undetected | [#63](https://gitlab.com/devnw/zig/uuid/-/work_items/63) | ✅ Closed |
| 4 | Medium | 36 | docs | saveState/loadState doc comments omit absolute-path requirement | `src/generator.zig:478-490,548-560` | Functions use `*Absolute` stdlib APIs; relative paths produce opaque EINVAL | [#64](https://gitlab.com/devnw/zig/uuid/-/work_items/64) | ✅ Closed |
| 5 | Low | 24 | tests | GeneratorInterface vtable tests cover only 3 of 10 methods | `src/generator_test.zig:553-583` | newV7, newV1, newV1AtTime, newV5, newV6, newV6AtTime, newV8 untested via interface | [#65](https://gitlab.com/devnw/zig/uuid/-/work_items/65) | ✅ Closed |
| 6 | Low | 12 | cleanup | All 17 Cycle 1 GitLab issues remain open despite code fixes | Issues #22–#38 | `glab issue list --label quality` shows all 17 open 2026-03-21 | [#66](https://gitlab.com/devnw/zig/uuid/-/work_items/66) | ✅ Closed |

---

### Findings by Category

#### CI/CD

##### QC-18 — CI 'build' job runs `zig build` (no source compilation) (High, Score 80)

**File:** `.gitlab-ci.yml:42-52`

The `build` CI job executes `zig build` with no step argument. Because `build.zig` defines the library as a module (`b.addModule`) without any `b.installArtifact` call, the default install step has nothing to compile. The only binary produced is `.zig-cache/o/.../build` (the build runner). The job declares `artifacts: paths: [zig-out/]` but `zig-out/` is never created.

**Impact:** Syntax or type errors in any `src/*.zig` file pass the build gate silently. The first signal of a compilation failure is in the `test` stage — bypassing the semantic model of build → test.

**Fix:** Change `zig build` to `zig build check` in the build job script. Remove the empty `artifacts` block.

**✅ Fixed:** `.gitlab-ci.yml` `build` job now runs `zig build check`; empty `artifacts` block removed.

**Verify:** Introduce a type error in `src/uuid.zig`; `zig build check` fails, `zig build` (old) would not.

**Confidence:** confirmed

---

##### QC-19 — test-cross-build uses `zig build -Dtarget=X` (no-op) not `zig build check-cross` (High, Score 80)

**File:** `.gitlab-ci.yml:119-132`

`test-cross-build` runs `zig build -Dtarget=x86_64-linux` (and 4 more targets). Same root cause as QC-18: the install step has no artifacts, so these commands compile only the build runner for the host. The cross-compile verification is completely ineffective. `hwaddr/windows.zig`, `hwaddr/macos.zig`, and `hwaddr/linux.zig` are never cross-compiled in CI.

**Impact:** This undoes the intended fix from QC-8 (issue #29). Platform-specific ABI errors in Windows or macOS code are invisible.

**Fix:** Replace the 5-line per-target loop with `zig build check-cross`. The `check-cross` step (already defined in `build.zig:104-127`) compiles all 5 targets unconditionally.

**✅ Fixed:** `.gitlab-ci.yml` `test-cross-build` now runs `zig build check-cross` (single call, all 5 targets).

**Confidence:** confirmed

---

##### QC-20 — bench/main.zig never compiled in CI (Medium, Score 48)

**File:** `.gitlab-ci.yml`, `bench/main.zig`

No CI job runs `zig build bench` or any step that compiles `bench/main.zig`. The benchmark imports `uuid.newV4`, `uuid.newV7`, `uuid.newV1`, `uuid.newV6` — all public API that could drift without detection. QC-15 (issue #36) fixed the same gap for `examples/basic.zig` by adding `build-examples`; the same treatment is needed for `bench/`.

**Fix:** Add a `build-bench` CI job in the `build` stage that runs `zig build bench`. Alternatively, add a `bench-check` step to `build.zig` that compiles without running (faster in CI).

**✅ Fixed:** `build-bench` job added to `.gitlab-ci.yml` build stage; runs `zig build bench -Doptimize=ReleaseFast`.

**Confidence:** confirmed

---

#### Documentation

##### QC-21 — saveState/loadState doc comments omit absolute-path requirement (Medium, Score 36)

**File:** `src/generator.zig:478-490, 548-560`

`saveState` and `loadState` use `std.fs.createFileAbsolute`, `std.fs.deleteFileAbsolute`, `std.fs.renameAbsolute`, and `std.fs.openFileAbsolute` internally. Neither function's doc comment mentions that `path` must be an absolute path. A caller passing `"uuid.state"` (relative) receives `error.InvalidArgument` (EINVAL) with no diagnostic.

**Fix:** Add to each function's doc comment: `/// **Path:** Must be an absolute path. Use std.fs.Dir.realpath to convert relative paths.`

**✅ Fixed:** Both `saveState` and `loadState` doc comments now lead with an explicit absolute-path requirement sentence including the specific error returned for relative paths.

**Confidence:** confirmed

---

#### Tests

##### QC-22 — GeneratorInterface vtable tests cover only 3 of 10 methods (Low, Score 24)

**File:** `src/generator_test.zig:553-583`, `src/generator.zig:702-753`

`GeneratorInterface` has a 10-method VTable. Tests only call: `newV4`, `newV3`, `newV7AtTime`. The 7 remaining trampolines — `newV7` (line 708), `newV1` (line 719), `newV1AtTime` (line 723), `newV5` (line 733), `newV6` (line 738), `newV6AtTime` (line 743), `newV8` (line 748) — have no dispatch test. A typo in any trampoline (e.g., calling the wrong concrete method) would be undetected.

**Fix:** Add 7 tests mirroring the existing `GeneratorInterface.fromGenerator: newV4 dispatches correctly` pattern, one per untested method.

**✅ Fixed:** 7 new tests added in `src/generator_test.zig` covering `newV7`, `newV1`, `newV1AtTime`, `newV5`, `newV6`, `newV6AtTime`, `newV8`. All 139 tests pass.

**Confidence:** confirmed

---

#### Cleanup

##### QC-23 — All 17 Cycle 1 GitLab issues remain open despite code fixes (Low, Score 12)

**File:** GitLab issues #22–#38

The QUALITY_GAP_ANALYSIS.md marks QC-1 through QC-17 as `✅ Closed`. All 17 corresponding GitLab issues (#22–#38) remain open (verified 2026-03-21). Code fixes are in place; only the issue lifecycle is incomplete.

**Fix:** Close issues #22–#38 with resolution comments linking to the implementing commit(s). Issue #37 (Won't Do) should be closed with the documented rationale.

**✅ Fixed:** All 17 issues (#22–#38) closed via `glab issue close`. Code was already merged in prior commits.

**Confidence:** confirmed

---

### Action Plan (Cycle 2)

#### Quick Wins (S effort — do first)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#61](https://gitlab.com/devnw/zig/uuid/-/work_items/61) | Fix CI build job: `zig build` → `zig build check` | S | High |
| [#62](https://gitlab.com/devnw/zig/uuid/-/work_items/62) | Fix cross-compile CI: per-target no-op → `zig build check-cross` | S | High |
| [#63](https://gitlab.com/devnw/zig/uuid/-/work_items/63) | Add `build-bench` CI job | S | Medium |
| [#64](https://gitlab.com/devnw/zig/uuid/-/work_items/64) | Document absolute-path requirement in saveState/loadState | S | Medium |
| [#65](https://gitlab.com/devnw/zig/uuid/-/work_items/65) | Add 7 GeneratorInterface vtable tests | S | Low |
| [#66](https://gitlab.com/devnw/zig/uuid/-/work_items/66) | Close GitLab issues #22–#38 with resolution comments | S | Low |

---

_Last updated: 2026-03-21 — Cycle 2 complete; all 6 findings implemented and closed. 139 tests pass (124 unit + 15 integration)._

> **Won't Do Policy (all quality review cycles — for future agents):**
> CI/CD Zig toolchain download checksum verification, Docker image digest/tag pinning,
> CI catalog component tag pinning, and pre-commit hook modifications are handled by
> separate pipeline governance controls. These items MUST remain 🚫 Won't Do across ALL
> `*GAP_ANALYSIS.md` files. Future agents MUST NOT re-open, re-implement, or re-report
> these items. This policy is documented in `docs/GAP_ANALYSIS.md` Won't Do Policy blocks
> and applies to all review cycles.
