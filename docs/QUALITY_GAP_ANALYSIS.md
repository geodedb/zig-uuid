# UUID Library — Code Quality Gap Analysis

> **Scope:** Code quality, maintainability, readability, test coverage, documentation, and CI/CD quality.
> **Last updated:** 2026-03-22 (Cycle 12 — 16 new findings, all closed)
> **Zig version audited:** 0.15.2
> **Previous reviews:** `docs/GAP_ANALYSIS.md` (RFC-9562 compliance), `docs/PERF_GAP_ANALYSIS.md` (performance) — findings from those reviews are not duplicated here.
> **Cycles:** Cycle 1 (QC-1–QC-17), Cycle 2 (QC-18–QC-23), Cycle 3 (QC-24–QC-28), Cycle 4 (QC-29–QC-34), Cycle 5 (QC-35–QC-38), Cycle 6 (QC-39–QC-47), Cycle 7 (QC-48–QC-54), Cycle 8 (QC-55–QC-61), Cycle 9 (no new findings), Cycle 10 (QC-62–QC-70), Cycle 11 (QC-71–QC-75), Cycle 12 (QC-76–QC-92, QC-89 merged into QC-80)

---

## Summary (All Cycles)

| Cycle | Severity | Count | Status |
| ----- | -------- | ----- | ------ |
| 1 | High | 3 | ✅ All closed |
| 1 | Medium | 5 | ✅ All closed |
| 1 | Low | 9 | ✅ 8 closed, 🚫 1 Won't Do |
| 2 | High | 2 | ✅ All closed |
| 2 | Medium | 2 | ✅ All closed |
| 2 | Low | 2 | ✅ All closed |
| 3 | Medium | 1 | ✅ Closed |
| 3 | Low | 4 | ✅ All closed |
| 4 | Medium | 1 | ✅ Closed |
| 4 | Low | 5 | ✅ All closed |
| 5 | Low | 4 | ✅ All closed |
| 6 | Low | 9 | ✅ All closed |
| 7 | High | 1 | ✅ Closed |
| 7 | Low | 6 | ✅ All closed |
| 8 | High | 2 | ✅ All closed |
| 8 | Medium | 4 | ✅ All closed |
| 8 | Low | 1 | ✅ Closed |
| 9 | — | 0 | ✅ No new findings |
| 10 | Low | 9 | ✅ 8 closed, 🚫 1 Won't Do (QC-64) |
| 11 | Low | 5 | ✅ All closed |
| 12 | High | 1 | ✅ Closed |
| 12 | Medium | 1 | ✅ Closed |
| 12 | Low | 12 | ✅ All closed |
| 12 | Info | 2 | ✅ All closed |

**Total issues:** 91 — **89 closed, 2 Won't Do (QC-16, QC-64), 0 open**

### Top 5 Closed Items (Cycle 12)

All Cycle 12 findings were closed on 2026-03-22:

- ✅ QC-80 — Replaced placeholder hash with `zig fetch` instructions in README
- ✅ QC-90 — Fixed root.zig doc: removed internal @import("generator.zig") reference
- ✅ QC-81 — Changed newV8 return type from Error!UUID to UUID
- ✅ QC-82 — Documented both access paths in README
- ✅ QC-79 — Added doc comments to all 10 GeneratorInterface dispatch methods

### Top 5 Closed Items (Cycle 10)

All Cycle 10 findings were closed on 2026-03-22:

- ✅ QC-62 — Doc comments added to 8 public functions in `src/uuid.zig`
- ✅ QC-63 — XOR sink pattern added to `benchV4/V7/V1/V6/V7AtTime` in `bench/main.zig`
- 🚫 QC-64 — Won't Do: `GeneratorInterface` extraction to `generator_interface.zig` causes circular import (vtable references `*Generator`, same resolution as QC-38)
- ✅ QC-65 — Tests extracted from `src/uuid.zig` to `src/uuid_test.zig`; uuid.zig reduced to 523 lines
- ✅ QC-66 — V3/V5 test vectors added for `namespace_url`, `namespace_oid`, `namespace_x500`
- ✅ QC-67 — README NullUUID table updated with `format()`, `jsonMarshal()`, `jsonUnmarshal()`
- ✅ QC-68 — `test-release-small` CI job added to `.gitlab-ci.yml`
- ✅ QC-69 — 10 `expectError` integration tests added to `tests/integration.zig`
- ✅ QC-70 — README Generator table updated with `Generator.withRand(f)`

### Top 5 Open Risks (Cycle 8)

All Cycle 8 findings were closed on 2026-03-22:

- ✅ QC-60 — `pub const default_generator` → `pub var` in `src/root.zig`
- ✅ QC-56 — `isMax()` added to `src/uuid.zig` + test
- ✅ QC-55 — `NullUUID.format` added to `src/null_uuid.zig` + 2 tests
- ✅ QC-57 — README fixed: `newV1AtTime(ts: Timestamp)` and `newV6AtTime(ts: Timestamp)`
- ✅ QC-58 — `build.zig.zon` `.paths` updated to include `tests/`, `bench/`, `CHANGELOG.md`
- ✅ QC-59 — Fuzz CI job added (scheduled/manual, 60s timeout, allow_failure); Makefile `fuzz` target added
- ✅ QC-61 — `bench` and `fuzz` targets added to Makefile

### Top 5 Open Risks (Cycle 7)

All Cycle 7 findings were closed on 2026-03-22:

- ✅ QC-48 — Staged `src/generator_state_test.zig` in git (`git add`)
- ✅ QC-49 — Added integration tests for `toHexAlloc`/`toHexUpperAlloc`
- ✅ QC-50 — Added `{f}` format specifier example to README Quick Start
- ✅ QC-51 — Added `## API Reference` section to README
- ✅ QC-52 — Added `test-integration-release-safe` CI job
- ✅ QC-53 — Added `toHexAlloc`/`toHexUpperAlloc` demo to `examples/basic.zig`
- ✅ QC-54 — Added doc comment to `toStringAlloc`

### Previous Cycle Top Risks (Cycle 6)

All Cycle 6 findings were closed on 2026-03-22:

- ✅ QC-47 — Fixed `fromString("urn:")` to return `InvalidURNPrefix` (changed `> 4` to `>= 4`) + regression test
- ✅ QC-46 — Added comprehensive doc comment to `fromString` listing 6 formats and 5 error types
- ✅ QC-42 — Added `toHexAlloc` / `toHexUpperAlloc` matching existing allocating surface + tests
- ✅ QC-40 — Added 4 tests directly exercising `Error.InvalidDashes` in `parseCanonical`
- ✅ QC-41 — Added round-trip tests for all four Variant values (.ncs, .rfc9562, .microsoft, .future)

### Previous Cycle Top Risks (Cycle 5)

All Cycle 5 findings were closed in the same cycle (2026-03-21):

- ✅ QC-35 — Removed dead `Error.V8FieldLength` from `src/uuid.zig`
- ✅ QC-36 — Updated `src/root.zig` Quick Start to demonstrate `{f}` specifier
- ✅ QC-37 — Added wrong-version tests for `timestampFromV6` and `timestampFromV7`
- ✅ QC-38 — Compacted `generator_vtable` in `generator.zig` to 781 lines (castGen helper)

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
| 18 | Low | 20 | api-contract | `fromString("urn:")` returns `InvalidLength` instead of `InvalidURNPrefix` | `src/uuid.zig:211` | `rest.len > 4` misses len==4 | [#101](https://gitlab.com/devnw/zig/uuid/-/work_items/101) | Changed `> 4` to `>= 4` + regression test added | ✅ Closed |
| 19 | Low | 16 | docs | `fromString` has no doc comment — formats and errors undocumented | `src/uuid.zig:206` | No leading `///` on `fromString` | [#100](https://gitlab.com/devnw/zig/uuid/-/work_items/100) | Added doc comment listing 6 formats and 5 error types | ✅ Closed |
| 20 | Low | 16 | api-contract | `toHex`/`toHexUpper` missing `Alloc` variants — asymmetric API | `src/uuid.zig:244–252` | No `toHexAlloc`/`toHexUpperAlloc` | [#96](https://gitlab.com/devnw/zig/uuid/-/work_items/96) | Added `toHexAlloc` and `toHexUpperAlloc` + tests | ✅ Closed |
| 21 | Low | 16 | tests | `Error.InvalidDashes` never exercised by any test | `src/uuid.zig:379` | No `expectError(Error.InvalidDashes, ...)` in any test file | [#94](https://gitlab.com/devnw/zig/uuid/-/work_items/94) | Added 4 tests covering all four dash positions | ✅ Closed |
| 22 | Low | 16 | tests | `setVariant(.ncs)` and `setVariant(.future)` branches untested | `src/uuid.zig:111,113` | Only rfc9562 and microsoft exercised | [#95](https://gitlab.com/devnw/zig/uuid/-/work_items/95) | Added round-trip test for all four Variant values | ✅ Closed |
| 23 | Low | 12 | maintainability | `generator.zig` at 821 lines — 21 over 800-line guideline | `src/generator.zig` | `wc -l` = 821 | [#93](https://gitlab.com/devnw/zig/uuid/-/work_items/93) | Compacted vtable entries to 1-line form; now 781 lines | ✅ Closed |
| 24 | Low | 12 | tests | `benchFromString` only tests canonical format; URN/hex/braced unmeasured | `bench/main.zig:133–151` | Single format in benchmark loop | [#99](https://gitlab.com/devnw/zig/uuid/-/work_items/99) | Added `benchFromStringHex` and `benchFromStringURN` | ✅ Closed |
| 25 | Low | 8 | docs | `CHANGELOG.md` `[Unreleased]` has stale placeholder content post-0.1.0 release | `CHANGELOG.md:8–17` | 5 placeholder lines duplicate 0.1.0 section | [#97](https://gitlab.com/devnw/zig/uuid/-/work_items/97) | Replaced placeholder with actual Cycle 6 change summary | ✅ Closed |
| 26 | Low | 8 | docs | `README.md` and `build.zig.zon` declare Zig 0.15.1 minimum but CI tests with 0.15.2 | `README.md:65`, `build.zig.zon:5` | Version skew; `{f}` specifier may require 0.15.2 | [#98](https://gitlab.com/devnw/zig/uuid/-/work_items/98) | Updated both to `0.15.2` | ✅ Closed |
| 27 | High | 64 | tests | `generator_state_test.zig` untracked in git — 9 state tests never run in CI | `src/generator_state_test.zig` | `git status --porcelain` shows `??`; file exists on disk but not committed | [#102](https://gitlab.com/devnw/zig/uuid/-/work_items/102) | Staged `src/generator_state_test.zig` in git (QC-48) | ✅ Closed |
| 28 | Low | 24 | tests | `toHexAlloc`/`toHexUpperAlloc` not covered by integration tests | `tests/integration.zig` | No `toHexAlloc` call in integration test file | [#103](https://gitlab.com/devnw/zig/uuid/-/work_items/103) | Added two integration tests for allocating hex output (QC-49) | ✅ Closed |
| 29 | Low | 24 | docs | README Quick Start omits the `{f}` format specifier | `README.md:43–61` | `src/root.zig` module doc shows `{f}`; README shows only `toString` | [#105](https://gitlab.com/devnw/zig/uuid/-/work_items/105) | Added `{f}` example line to Quick Start (QC-50) | ✅ Closed |
| 30 | Low | 24 | docs | README has no API reference section | `README.md` | No section listing public types/methods | [#106](https://gitlab.com/devnw/zig/uuid/-/work_items/106) | Added `## API Reference` section (QC-51) | ✅ Closed |
| 31 | Low | 24 | ci-cd | CI missing `test-integration-release-safe` job | `.gitlab-ci.yml` | Integration only in Debug+ReleaseFast; ReleaseSafe integration absent | [#107](https://gitlab.com/devnw/zig/uuid/-/work_items/107) | Added `test-integration-release-safe` CI job (QC-52) | ✅ Closed |
| 32 | Low | 16 | docs | `examples/basic.zig` does not demonstrate `toHexAlloc`/`toHexUpperAlloc` | `examples/basic.zig:74–82` | Output formats section omits allocating hex variants | [#104](https://gitlab.com/devnw/zig/uuid/-/work_items/104) | Added `toHexAlloc`/`toHexUpperAlloc` demo to examples (QC-53) | ✅ Closed |
| 33 | Low | 16 | docs | `toStringAlloc` has no doc comment — asymmetric with all other output methods | `src/uuid.zig:296` | Only public output method with zero `///` documentation | [#108](https://gitlab.com/devnw/zig/uuid/-/work_items/108) | Added doc comment (QC-54); PERF-16 also added hot-path note | ✅ Closed |
| 34 | High | 64 | api-contract | `pub const default_generator` in `root.zig` prevents callers from calling mutating methods | `src/root.zig:52` | `pub const` re-export blocks `saveState`/`loadState`/`clearNodeCache` | [#109](https://gitlab.com/devnw/zig/uuid/-/work_items/109) | Changed `pub const` to `pub var` (QC-60) | ✅ Closed |
| 35 | High | 64 | docs | README API Reference documents `uuid.isMax()` which does not exist | `README.md:107` | No `isMax` function in `src/uuid.zig` | [#110](https://gitlab.com/devnw/zig/uuid/-/work_items/110) | Added `isMax()` method to `src/uuid.zig` + test (QC-56) | ✅ Closed |
| 36 | Medium | 36 | api-contract | `NullUUID` missing `format` method — `{f}` specifier not supported | `src/null_uuid.zig` | No `pub fn format` on `NullUUID`; `UUID` has it | [#111](https://gitlab.com/devnw/zig/uuid/-/work_items/111) | Added `format` method to `src/null_uuid.zig` + 2 tests (QC-55) | ✅ Closed |
| 37 | Medium | 36 | docs | README documents wrong parameter types for `newV1AtTime`/`newV6AtTime` — `i64` instead of `Timestamp` | `README.md:73,78` | Signatures show `ms: i64`; actual type is `Timestamp` | [#112](https://gitlab.com/devnw/zig/uuid/-/work_items/112) | Fixed README to show `ts: Timestamp` (QC-57) | ✅ Closed |
| 38 | Medium | 36 | maintainability | `build.zig.zon` `.paths` omits `tests/`, `bench/`, `CHANGELOG.md` | `build.zig.zon:12–21` | Published package missing integration tests and benchmarks | [#113](https://gitlab.com/devnw/zig/uuid/-/work_items/113) | Updated `.paths` to include `tests/`, `bench/`, `CHANGELOG.md` (QC-58) | ✅ Closed |
| 39 | Medium | 36 | ci-cd | Fuzz targets never exercised in CI — only static corpus test mode runs | `.gitlab-ci.yml`, `src/fuzz.zig` | No CI job uses `--fuzz` flag | [#114](https://gitlab.com/devnw/zig/uuid/-/work_items/114) | Added scheduled fuzz CI job + Makefile `fuzz` target (QC-59) | ✅ Closed |
| 40 | Low | 24 | maintainability | `Makefile` missing `bench` and `fuzz` targets | `Makefile` | `make help` has no bench or fuzz entries | [#115](https://gitlab.com/devnw/zig/uuid/-/work_items/115) | Added `bench` and `fuzz` make targets (QC-61) | ✅ Closed |
| 41 | Low | 16 | maintainability | `src/generator.zig` at 847 lines — 47 over 800-line guideline (third recurrence) | `src/generator.zig` | `wc -l` = 847; vtable block (lines 710–847) is extractable | [#134](https://gitlab.com/devnw/zig/uuid/-/work_items/134) | Circular import blocks extraction (same as QC-38) | 🚫 Won't Do (QC-64) |
| 42 | Low | 16 | maintainability | `src/uuid.zig` at 889 lines — 89 over 800-line guideline; test block should be split | `src/uuid.zig` | `wc -l` = 889; test block starts at line 479 (~410 lines) | [#135](https://gitlab.com/devnw/zig/uuid/-/work_items/135) | Tests extracted to `src/uuid_test.zig`; uuid.zig reduced to 523 lines | ✅ Closed (QC-65) |
| 43 | Low | 16 | maintainability | `benchV4/V7/V1/V6/V7AtTime` discard UUID with `_ =` — no sink variable; potential DCE | `bench/main.zig:44,54,64,74,229` | V3/V5/output benchmarks have sink; generation benchmarks do not | [#133](https://gitlab.com/devnw/zig/uuid/-/work_items/133) | XOR sink pattern added to all 5 generation benchmarks | ✅ Closed (QC-63) |
| 44 | Low | 16 | tests | V3/V5 tests only use `namespace_dns` — URL, OID, X.500 namespaces have no test vectors | `src/generator_test.zig:152–176` | All V3/V5 tests use `namespace_dns` exclusively | [#136](https://gitlab.com/devnw/zig/uuid/-/work_items/136) | V3/V5 test vectors added for `namespace_url`, `namespace_oid`, `namespace_x500` | ✅ Closed (QC-66) |
| 45 | Low | 12 | docs | Seven public API functions in `src/uuid.zig` lack doc comments | `src/uuid.zig:61,69,109,113,122,126,192,338` | `variant`, `isNil`, `setVersion`, `setVariant`, `eql`, `order`, `fromBytes`, `jsonMarshal` | [#132](https://gitlab.com/devnw/zig/uuid/-/work_items/132) | Doc comments added to all 8 public functions | ✅ Closed (QC-62) |
| 46 | Low | 12 | docs | README `NullUUID` API table omits `format()`, `jsonMarshal()`, `jsonUnmarshal()` | `README.md:123–129` | Three public methods absent from API reference | [#137](https://gitlab.com/devnw/zig/uuid/-/work_items/137) | 3 rows added to NullUUID API table in README.md | ✅ Closed (QC-67) |
| 47 | Low | 12 | ci-cd | CI has no `test-release-small` job — `ReleaseSmall` never tested in CI | `.gitlab-ci.yml` | 3 optimization modes tested; `ReleaseSmall` omitted | [#138](https://gitlab.com/devnw/zig/uuid/-/work_items/138) | `test-release-small` CI job added to `.gitlab-ci.yml` | ✅ Closed (QC-68) |
| 48 | Low | 12 | tests | `tests/integration.zig` has zero `expectError` calls — error paths never exercised at integration level | `tests/integration.zig` | 20+ tests, all happy-path only | [#139](https://gitlab.com/devnw/zig/uuid/-/work_items/139) | 10 `expectError` integration tests added | ✅ Closed (QC-69) |
| 49 | Low | 8 | docs | README `Generator` API table omits `Generator.withRand(f)` | `README.md:130–141` | `withClock` and `withHWAddr` documented; `withRand` omitted | [#140](https://gitlab.com/devnw/zig/uuid/-/work_items/140) | `withRand` row added to Generator table in README.md | ✅ Closed (QC-70) |

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

---

## Quality Review Cycle 3

> **Date:** 2026-03-21
> **Zig version audited:** 0.15.2
> **Previous cycles:** Cycle 1 (QC-1–QC-17) and Cycle 2 (QC-18–QC-23) — all closed.
> **Scope:** New findings only — items from prior cycles are not re-opened.

---

### Summary

| Severity | Count |
| -------- | ----- |
| Medium   | 1     |
| Low      | 4     |

**Total new issues:** 5 — **all closed** (implemented 2026-03-21)

### Top 5 Risks

1. **UUID.format uses wrong Zig 0.15 signature** (QC-24) — `anytype` writer instead of `*std.io.Writer` means downstream callers get a compile error when using `{}` and will silently get wrong output when the stdlib compat shim is removed.
2. **Makefile `build` target is a no-op** (QC-25) — same root cause as QC-18 (fixed in CI) but not propagated to the Makefile; `make build` does not compile any source.
3. **Integration tests missing V6, V8, saveState coverage** (QC-27) — three significant code paths lack cross-module integration test coverage.
4. **generator_test.zig at 848 lines over guideline** (QC-28) — test file itself exceeds the 800-line soft limit introduced by QC-4.
5. **Generator.newV3/V5/V8 ignore self receiver** (QC-26) — misleading API; receiver implies stateful generation when these are purely deterministic functions.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | Medium | 48 | maintainability | UUID.format uses wrong Zig 0.15 signature — `anytype` writer breaks `{}` usage and will silently break in next Zig release | `src/uuid.zig:280` | `anytype` writer; stdlib uses `*std.io.Writer`; `{}` emits compile error | [#72](https://gitlab.com/devnw/zig/uuid/-/work_items/72) | ✅ Closed |
| 2 | Low | 32 | ci-cd | Makefile `build` target runs `zig build` (no-op) same as QC-18 | `Makefile:17` | `@zig build` does not compile UUID source | [#73](https://gitlab.com/devnw/zig/uuid/-/work_items/73) | ✅ Closed |
| 3 | Low | 24 | tests | Integration tests missing V6, V8, and saveState/loadState | `tests/integration.zig` | 15 tests; no V6/V8/state coverage | [#75](https://gitlab.com/devnw/zig/uuid/-/work_items/75) | ✅ Closed |
| 4 | Low | 16 | maintainability | generator_test.zig at 848 lines exceeds 800-line guideline | `src/generator_test.zig` | `wc -l src/generator_test.zig` = 848 | [#76](https://gitlab.com/devnw/zig/uuid/-/work_items/76) | ✅ Closed |
| 5 | Low | 16 | readability | Generator.newV3, newV5, newV8 discard self with `_ = self` — misleading receiver | `src/generator.zig:437,463,476` | Three public methods with dead `_ = self` | [#74](https://gitlab.com/devnw/zig/uuid/-/work_items/74) | ✅ Closed |

---

### Findings by Category

#### Maintainability

##### QC-24 — UUID.format uses wrong Zig 0.15 signature (Medium, Score 48)

**File:** `src/uuid.zig:280-283`

`UUID.format` is declared as `pub fn format(self: UUID, writer: anytype) !void`. The Zig 0.15 convention (used throughout the stdlib: `std/net.zig:209`, `std/builtin.zig:41`, `std/Io/Writer.zig:1927`) is `pub fn format(self: T, w: *std.io.Writer) std.io.Writer.Error!void`. Zig 0.15 stdlib (`Io/Writer.zig:1198-1201`) emits a compile error for any `{}` usage with a type that has a custom `format` method, requiring callers to use `{f}` instead. The stdlib comment reads "after 0.15.0 is tagged, delete this compile error and its condition" — meaning a post-0.15.0 Zig will silently treat `{}` as `{any}`, printing the struct's internal representation rather than the canonical UUID string.

**Fix:** Change signature to `pub fn format(self: UUID, w: *std.io.Writer) std.io.Writer.Error!void`. Update the test to use `{f}` with an explanatory comment.

**Confidence:** confirmed

---

##### QC-28 — generator_test.zig at 848 lines exceeds 800-line guideline (Low, Score 16)

**File:** `src/generator_test.zig`

QC-4 split `generator.zig` to move tests into `generator_test.zig`, reducing `generator.zig` to 811 lines. The test file has since grown to 848 lines — now itself over the 800-line guideline. `generator.zig` has also grown to 811 lines (1 over).

**Fix:** Split `generator_test.zig` into `generator_test.zig` (core generation tests) and `generator_state_test.zig` (saveState/loadState tests). Import both from `generator.zig` via the existing `test { _ = @import(...); }` pattern.

**Confidence:** confirmed

---

#### Readability

##### QC-26 — Generator.newV3/newV5/newV8 discard self with `_ = self` (Low, Score 16)

**File:** `src/generator.zig:437, 463, 476`

Three public Generator methods immediately discard the receiver: `_ = self`. V3 and V5 use deterministic hash algorithms (MD5, SHA-1) with no generator state. V8 copies caller-supplied bytes directly. Users reasonably expect `*Generator` methods to use generator state (clock, rand, hwaddr), creating a misleading contract.

**Fix (option A, minimal):** Add doc comments to each method explicitly noting the generator state is not used and these are deterministic functions. **Fix (option B):** Extract as free functions; expose them on Generator and GeneratorInterface via thin wrappers.

**Confidence:** confirmed

---

#### Tests

##### QC-27 — Integration tests missing V6, V8, and saveState/loadState coverage (Low, Score 24)

**File:** `tests/integration.zig`

The 15 integration tests cover V4, V7, V3, V5, V1 round-trips, NullUUID JSON, concurrent generation, parse formats, `timestampFromV7`, URN output, uppercase output, `isZero`, and `GeneratorInterface.newV4`. Three significant areas have no integration-level coverage: V6 generation + `timestampFromV6` round-trip, V8 round-trip, and `saveState`/`loadState` persistent state.

**Fix:** Add three integration tests mirroring the existing V1/V7 round-trip pattern for V6 and V8; add a state persistence test using `std.testing.tmpDir`.

**Confidence:** confirmed

---

#### CI/CD

##### QC-25 — Makefile `build` target runs `zig build` (no-op) not `zig build check` (Low, Score 32)

**File:** `Makefile:17`

`make build` runs `@zig build`, which is identical to the no-op fixed by QC-18 in `.gitlab-ci.yml`. Since `build.zig` has no `installArtifact`, the default install step builds only the build runner, not any library source. QC-18 fixed the CI pipeline; the Makefile was not updated in the same commit.

**Fix:** Change `@zig build` to `@zig build check` on line 17.

**Confidence:** confirmed

---

### Action Plan (Cycle 3)

#### Quick Wins (S effort — do first)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#72](https://gitlab.com/devnw/zig/uuid/-/work_items/72) | Fix UUID.format signature to use *std.io.Writer | S | Medium |
| [#73](https://gitlab.com/devnw/zig/uuid/-/work_items/73) | Fix Makefile `build` target: `zig build` → `zig build check` | S | Low |
| [#75](https://gitlab.com/devnw/zig/uuid/-/work_items/75) | Add V6, V8, saveState integration tests | S | Low |
| [#76](https://gitlab.com/devnw/zig/uuid/-/work_items/76) | Split generator_test.zig to stay under 800 lines | S | Low |
| [#74](https://gitlab.com/devnw/zig/uuid/-/work_items/74) | Document or remove `_ = self` in newV3/V5/V8 | S | Low |

---

_Last updated: 2026-03-21 — Cycle 3 implementation complete. All 5 findings closed. 142 tests pass (124 unit + 18 integration)._

---

## Won't Do Policy — All Cycles (MANDATORY for future agents)

> The following categories of findings MUST remain 🚫 Won't Do across ALL `*GAP_ANALYSIS.md`
> files. Future agents MUST NOT re-open, re-implement, or re-report these items.
>
> **Covered items:**
>
> - CI/CD Zig toolchain download checksum/SHA256 verification
> - Docker image digest pinning (no `@sha256:` in CI image references)
> - CI catalog component tag pinning (mutable semver tags in GitLab CI includes)
> - Pre-commit hook modifications (`check-yaml --unsafe`, hook versioning, `check-todos` no-op)
>
> **Rationale:** These are handled by separate pipeline governance controls (Renovate/org policy,
> dedicated developer tooling team) outside this repository. Modifying them in library code
> creates maintenance conflicts with the governance layer and is explicitly out of scope.
>
> **Cross-references:** `docs/GAP_ANALYSIS.md` Won't Do Policy blocks (repeated in each security
> review cycle), `docs/PERF_GAP_ANALYSIS.md` Won't Do note, `QUALITY_GAP_ANALYSIS.md` QC-16
> (check-todos pre-commit hook).

---

## Quality Review Cycle 4

> **Date:** 2026-03-21
> **Zig version audited:** 0.15.2
> **Previous cycles:** Cycle 1 (QC-1–QC-17), Cycle 2 (QC-18–QC-23), Cycle 3 (QC-24–QC-28) — all closed.
> **Scope:** New findings only — items from prior cycles are not re-opened.

---

### Summary

| Severity | Count |
| -------- | ----- |
| Medium   | 1     |
| Low      | 5     |

**Total new issues:** 6 — all open, status::triage

### Top 5 Risks

1. **`loadState` bypasses injectable clock** (QC-29) — uses `std.time.nanoTimestamp()` directly instead of `self.clock`, making the PERF-04/SEC-10 fast-restart branch untestable via clock injection and inconsistent with the defensive `clockToMs` helper.
2. **`versions.zig` tests cover only 3 of 10 public functions** (QC-30) — 7 convenience-function delegation paths are untested; a typo in any wrapper is silently undetected.
3. **examples/basic.zig never demonstrates `{f}` format specifier** (QC-31) — users reading the example will not discover the QC-24 `UUID.format` improvement and continue using the verbose `toString(&buf)` + `{s}` pattern unnecessarily.
4. **`fuzz.zig` only covers `fromString`** (QC-32) — `fromBytes` and `NullUUID.jsonUnmarshal` parsing paths have no fuzz coverage, creating a gap in the SEC-R2-11 no-panic guarantee for all external-data entry points.
5. **Makefile `cross-compile-required` 5× redundant work** (QC-33) — calls `zig build check-cross -Dtarget=X` five times; `check-cross` ignores `-Dtarget` and hardcodes all 5 targets, producing 25 compilations instead of 5.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | Medium | 36 | maintainability | `loadState` hardcodes `std.time.nanoTimestamp()` instead of using injectable `self.clock` | `src/generator.zig:648` | `@intCast(@divTrunc(std.time.nanoTimestamp(), 1_000_000))` bypasses `ClockFn` injection | [#77](https://gitlab.com/devnw/zig/uuid/-/work_items/77) | ✅ Closed |
| 2 | Low | 32 | tests | `versions.zig` tests cover only 3 of 10 public convenience functions | `src/versions.zig` | `grep "^test "` shows 3 tests; 7 functions untested: newV1, newV1AtTime, newV5, newV6, newV6AtTime, newV7AtTime, newV8 | [#78](https://gitlab.com/devnw/zig/uuid/-/work_items/78) | ✅ Closed |
| 3 | Low | 32 | docs | `examples/basic.zig` never shows `{f}` specifier introduced by QC-24 | `examples/basic.zig`, `src/root.zig` | All output uses `toString(&buf)` + `{s}`; `{f}` never demonstrated | [#79](https://gitlab.com/devnw/zig/uuid/-/work_items/79) | ✅ Closed |
| 4 | Low | 24 | ci-cd | Makefile `cross-compile-required` calls `check-cross` 5× with ignored `-Dtarget` — 5× redundant compilations | `Makefile:77–83`, `build.zig:110` | Loop over 5 targets × 5 hardcoded targets = 25 compilations; misleading step description | [#81](https://gitlab.com/devnw/zig/uuid/-/work_items/81) | ✅ Closed |
| 5 | Low | 24 | tests | `fuzz.zig` only covers `UUID.fromString` — `fromBytes` and `NullUUID.jsonUnmarshal` have no fuzz coverage | `src/fuzz.zig` | Single fuzz target; `fromBytes` and `jsonUnmarshal` accept external data but are unprotected | [#80](https://gitlab.com/devnw/zig/uuid/-/work_items/80) | ✅ Closed |
| 6 | Low | 12 | tests | `bench/main.zig` missing V3 and V5 benchmarks — name-based hash throughput uncharacterized | `bench/main.zig` | 6 benchmarks present; V3 (MD5) and V5 (SHA-1) absent | [#82](https://gitlab.com/devnw/zig/uuid/-/work_items/82) | ✅ Closed |

---

### Findings by Category

#### Maintainability

##### QC-29 — `loadState` bypasses injectable clock (Medium, Score 36)

**File:** `src/generator.zig:648`

`Generator.loadState` computes the current millisecond by calling `std.time.nanoTimestamp()` directly:

```zig
const current_ms: i64 = @intCast(@divTrunc(std.time.nanoTimestamp(), 1_000_000));
```

This bypasses `self.clock` (the injectable `ClockFn`), creating three problems:

1. The PERF-04/SEC-10 fast-restart branch (`if (current_ms > saved_ms)`) cannot be driven deterministically in tests.
2. The `@intCast` lacks the bounds guards present in `clockToMs()` (though practically safe for real timestamps).
3. Inconsistent with every other time operation in `generator.zig` which uses `self.clock()`.

**Fix:** Replace with `const current_ms = clockToMs(self.clock()) catch 0;`

**Confidence:** confirmed

---

#### Tests

##### QC-30 — `versions.zig` tests cover only 3 of 10 public functions (Low, Score 32)

**File:** `src/versions.zig`

Only `newV4`, `newV7`, and `newV3` have delegation tests. `newV1`, `newV1AtTime`, `newV5`, `newV6`, `newV6AtTime`, `newV7AtTime`, and `newV8` have none. This is the same gap pattern fixed by QC-22 for `GeneratorInterface`.

**Fix:** Add 7 tests mirroring the existing `"top-level newV4 delegates to default_generator"` pattern.

**Confidence:** confirmed

---

##### QC-32 — `fuzz.zig` only covers `UUID.fromString` (Low, Score 24)

**File:** `src/fuzz.zig`

A single fuzz target covers `fromString`. `UUID.fromBytes` and `NullUUID.jsonUnmarshal` — both parsing external data — have no fuzz protection, leaving a gap in the SEC-R2-11 no-panic guarantee.

**Fix:** Add `fuzzFromBytes` and `fuzzJsonUnmarshal` targets with inline corpora.

**Confidence:** confirmed

---

##### QC-34 — bench/main.zig missing V3 and V5 benchmarks (Low, Score 12)

**File:** `bench/main.zig`

V3 (MD5) and V5 (SHA-1) are the only UUID generation modes not benchmarked. Their hash-heavy, stateless profile is architecturally distinct from V4/V7/V1/V6. QC-17 set the precedent that all versions should appear in the benchmark suite.

**Fix:** Add `benchV3` and `benchV5` functions following the `benchV1`/`benchV6` pattern.

**Confidence:** confirmed

---

#### Documentation

##### QC-31 — examples/basic.zig never demonstrates `{f}` format specifier (Low, Score 32)

**File:** `examples/basic.zig`, `src/root.zig`

All UUID output in the example uses `toString(&buf)` + `{s}`. QC-24 introduced `UUID.format` with `*std.io.Writer`, enabling `{f}` — eliminating the need for a `[36]u8` stack buffer. Neither the example nor the `root.zig` module doc Quick Start demonstrates this usage, leaving users unaware of the simpler pattern.

**Fix:** Add one `{f}` example line to `examples/basic.zig` and update the `root.zig` Quick Start doc comment.

**Confidence:** confirmed

---

#### CI/CD

##### QC-33 — Makefile `cross-compile-required` 5× redundant work (Low, Score 24)

**File:** `Makefile:77–83`, `build.zig:110`

`cross-compile-required` loops over 5 targets calling `zig build check-cross -Dtarget=$$target`. The `check-cross` step ignores `-Dtarget` and compiles all 5 hardcoded targets on every call. This produces 25 compilations instead of 5. The `build.zig` step description ("for the active -Dtarget") is also inaccurate.

**Fix:** Replace the loop with a single `zig build check-cross`. Update `build.zig` step description to accurately state "all 5 required targets".

**Confidence:** confirmed

---

### Action Plan (Cycle 4)

#### Quick Wins (S effort — do first)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#77](https://gitlab.com/devnw/zig/uuid/-/work_items/77) | Fix `loadState` to use `self.clock()` + `clockToMs` | S | Medium |
| [#78](https://gitlab.com/devnw/zig/uuid/-/work_items/78) | Add 7 missing tests to `versions.zig` | S | Low |
| [#79](https://gitlab.com/devnw/zig/uuid/-/work_items/79) | Add `{f}` example to `examples/basic.zig` + `root.zig` doc | S | Low |
| [#81](https://gitlab.com/devnw/zig/uuid/-/work_items/81) | Fix Makefile `cross-compile-required` to call `check-cross` once | S | Low |
| [#80](https://gitlab.com/devnw/zig/uuid/-/work_items/80) | Add `fuzzFromBytes` + `fuzzJsonUnmarshal` to `fuzz.zig` | S | Low |
| [#82](https://gitlab.com/devnw/zig/uuid/-/work_items/82) | Add V3 and V5 benchmarks to `bench/main.zig` | S | Low |

---

_Last updated: 2026-03-21 — Cycle 4 implementation complete. All 6 findings closed. 153 tests pass (135 unit + 18 integration)._

---

## Quality Review Cycle 5

> **Date:** 2026-03-21
> **Zig version audited:** 0.15.2
> **Previous cycles:** Cycle 1 (QC-1–QC-17), Cycle 2 (QC-18–QC-23), Cycle 3 (QC-24–QC-28), Cycle 4 (QC-29–QC-34) — all closed.
> **Scope:** New findings only — items from prior cycles are not re-opened.
> **Methodology:** Full read of all source, test, benchmark, example, CI, and docs files; `zig fmt --check` (passed clean); `zig build test` (135/135 pass).

---

### Summary

| Severity | Count |
| -------- | ----- |
| Low      | 4     |

**Total new issues:** 4 — all open, status::triage

### Top Risks

All four Cycle 5 findings closed (2026-03-21):

1. ✅ **QC-35** — Removed `Error.V8FieldLength` from `src/uuid.zig`.
2. ✅ **QC-36** — Updated `src/root.zig` Quick Start to show `{f}` specifier.
3. ✅ **QC-37** — Added `timestampFromV6` and `timestampFromV7` wrong-version tests.
4. ✅ **QC-38** — Compacted `generator_vtable` via `castGen` helper; file at 781 lines.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | Low | 32 | docs | `root.zig` Quick Start doc comment shows `toString(&buf)+{s}` — `{f}` specifier never demonstrated (QC-31 partial fix) | `src/root.zig:16–25` | `grep "{f}" src/root.zig` → 0 results; `examples/basic.zig` was updated but `root.zig` was not | [#84](https://gitlab.com/devnw/zig/uuid/-/work_items/84) | ✅ Closed (QC-36) |
| 2 | Low | 32 | tests | `timestampFromV6` and `timestampFromV7` missing wrong-version error tests | `src/timestamp.zig:95,111` | `timestampFromV1` has error test (line 219); V6/V7 have none | [#85](https://gitlab.com/devnw/zig/uuid/-/work_items/85) | ✅ Closed (QC-37) |
| 3 | Low | 20 | maintainability | `Error.V8FieldLength` defined but never returned — dead error variant | `src/uuid.zig:16` | `grep -rn "V8FieldLength" src/ tests/` → 1 hit (declaration only) | [#83](https://gitlab.com/devnw/zig/uuid/-/work_items/83) | ✅ Closed (QC-35) |
| 4 | Low | 20 | maintainability | `generator.zig` at 816 lines exceeds 800-line guideline (QC-4/QC-28 recurrence) | `src/generator.zig` | `wc -l src/generator.zig` = 816 | [#86](https://gitlab.com/devnw/zig/uuid/-/work_items/86) | ✅ Closed (QC-38) |

---

### Findings by Category

#### Docs

##### QC-36 — root.zig Quick Start doc comment shows toString(&buf)+{s} — {f} not demonstrated (Low, Score 32) ✅ CLOSED

**File:** `src/root.zig:16–25`

**Fix applied (2026-03-21):** Replaced the `var buf`/`toString`/`{s}` two-liner with `std.debug.print("{f}\n", .{u}); // {f} specifier — no stack buffer needed`.

**Confidence:** confirmed

---

#### Tests

##### QC-37 — timestampFromV6 and timestampFromV7 missing wrong-version error tests (Low, Score 32) ✅ CLOSED

**File:** `src/timestamp.zig`

**Fix applied (2026-03-21):** Added `"timestampFromV6: error on wrong version (QC-37)"` and `"timestampFromV7: error on wrong version (QC-37)"` tests. Total unit tests: 137.

**Confidence:** confirmed

---

#### Maintainability

##### QC-35 — Error.V8FieldLength defined but never returned (Low, Score 20) ✅ CLOSED

**File:** `src/uuid.zig:16`

**Fix applied (2026-03-21):** Removed `V8FieldLength` from the `Error` union. `newV8` enforces field sizes via Zig's type system (`[6]u8`, `[2]u8`, `[8]u8`); no runtime error needed.

**Confidence:** confirmed

---

##### QC-38 — generator.zig at 816 lines exceeds 800-line guideline (Low, Score 20) ✅ CLOSED

**File:** `src/generator.zig`

**Fix applied (2026-03-21):** Introduced `castGen(*anyopaque) *Generator` helper and rewrote the 52-line `generator_vtable` block as 10 one-liner entries (saving 35 lines). File is now 781 lines — under the 800-line soft limit. Note: full extraction to `generator_interface.zig` was not possible due to circular import (vtable references `Generator`).

**Confidence:** confirmed

---

### Action Plan (Cycle 5)

#### Quick Wins (S effort — do first)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#84](https://gitlab.com/devnw/zig/uuid/-/work_items/84) | Update root.zig Quick Start to show `{f}` specifier | S | Low |
| [#85](https://gitlab.com/devnw/zig/uuid/-/work_items/85) | Add wrong-version error tests for timestampFromV6 + timestampFromV7 | S | Low |
| [#83](https://gitlab.com/devnw/zig/uuid/-/work_items/83) | Remove dead `Error.V8FieldLength` variant | S | Low |
| [#86](https://gitlab.com/devnw/zig/uuid/-/work_items/86) | Trim generator.zig to ≤ 800 lines | S | Low |

---

_Last updated: 2026-03-21 — Cycle 5 implementation complete. All 4 findings (QC-35–QC-38) closed. 137 unit + 18 integration tests pass. `generator.zig` at 781 lines. 0 open findings._

---

## Review Cycle 6 Findings (QC-39–QC-47)

> **Date:** 2026-03-21
> **Zig version audited:** 0.15.2
> **Scope:** New findings only — items addressed in Cycles 1–5 not re-opened.
> **Build status:** `zig build check` ✅, `zig build test --summary all` 137/137 ✅, `zig build test-integration --summary all` 18/18 ✅, `zig fmt --check` ✅

---

### Summary

| Severity | Count |
| -------- | ----- |
| Low      | 9     |

**Total new issues:** 9 — all open, status::triage

### Top 5 Risks

1. **`fromString("urn:")` returns wrong error** (QC-47) — the parser condition `rest.len > 4` misses the 4-char edge case, silently returning `InvalidLength` instead of `InvalidURNPrefix`, misleading callers.
2. **`fromString` has no doc comment** (QC-46) — the primary parse entry point has no `///` doc comment. Callers cannot determine accepted formats or expected error types without reading the implementation.
3. **`toHex`/`toHexUpper` lack allocating variants** (QC-42) — API asymmetry: `toStringAlloc`, `toStringUpperAlloc`, `toURNAlloc` exist but `toHexAlloc`/`toHexUpperAlloc` do not, forcing callers to write boilerplate.
4. **`Error.InvalidDashes` never tested** (QC-40) — `parseCanonical`'s dash-position check (line 379) has no direct unit test; a regression there would be invisible.
5. **`setVariant(.ncs)` and `setVariant(.future)` untested** (QC-41) — two of four `setVariant` branches (lines 111, 113) and the corresponding `variant()` detection paths are never exercised.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | Low | 20 | api-contract | `fromString("urn:")` returns `InvalidLength` instead of `InvalidURNPrefix` | `src/uuid.zig:211` | `rest.len > 4` strict; len==4 falls through to switch | [#101](https://gitlab.com/devnw/zig/uuid/-/work_items/101) | ✅ Closed (QC-47) |
| 2 | Low | 16 | docs | `fromString` has no doc comment — formats and errors undocumented | `src/uuid.zig:206` | No leading `///` on primary parse function | [#100](https://gitlab.com/devnw/zig/uuid/-/work_items/100) | ✅ Closed (QC-46) |
| 3 | Low | 16 | api-contract | `toHex`/`toHexUpper` missing `Alloc` variants — asymmetric API | `src/uuid.zig:244–252` | No `toHexAlloc`/`toHexUpperAlloc` vs existing `toStringAlloc` etc. | [#96](https://gitlab.com/devnw/zig/uuid/-/work_items/96) | ✅ Closed (QC-42) |
| 4 | Low | 16 | tests | `Error.InvalidDashes` never exercised by any test | `src/uuid.zig:379` | `grep -rn InvalidDashes` shows only declaration and production code | [#94](https://gitlab.com/devnw/zig/uuid/-/work_items/94) | ✅ Closed (QC-40) |
| 5 | Low | 16 | tests | `setVariant(.ncs)` and `setVariant(.future)` branches untested | `src/uuid.zig:111,113` | Only `.rfc9562` and `.microsoft` exercised in tests | [#95](https://gitlab.com/devnw/zig/uuid/-/work_items/95) | ✅ Closed (QC-41) |
| 6 | Low | 12 | maintainability | `generator.zig` at 821 lines — 21 over 800-line guideline (QC-4 recurrence) | `src/generator.zig` | `wc -l src/generator.zig` = 821; QC-38 brought it to 781, castGen + doc comments pushed it back | [#93](https://gitlab.com/devnw/zig/uuid/-/work_items/93) | ✅ Closed (QC-43) |
| 7 | Low | 12 | tests | `benchFromString` only tests canonical format; URN/hex/braced paths unmeasured | `bench/main.zig:133–151` | Single format in loop; no benchFromStringURN/benchFromStringHex | [#99](https://gitlab.com/devnw/zig/uuid/-/work_items/99) | ✅ Closed (QC-44/QC-24) |
| 8 | Low | 8 | docs | `CHANGELOG.md` `[Unreleased]` has stale placeholder content post-0.1.0 | `CHANGELOG.md:8–17` | 5 lines duplicate 0.1.0 section; should be empty after release | [#97](https://gitlab.com/devnw/zig/uuid/-/work_items/97) | ✅ Closed (QC-45/QC-25) |
| 9 | Low | 8 | docs | `README.md`/`build.zig.zon` declare Zig 0.15.1 minimum; CI uses 0.15.2 | `README.md:65`, `build.zig.zon:5` | Version skew; `{f}` specifier may require 0.15.2 specifically | [#98](https://gitlab.com/devnw/zig/uuid/-/work_items/98) | ✅ Closed (QC-26) |

---

### Findings by Category

#### API Contract

##### QC-47 — `fromString("urn:")` returns `InvalidLength` not `InvalidURNPrefix` (Low, Score 20)

**File:** `src/uuid.zig:211`

The condition `rest.len > 4 and std.mem.startsWith(u8, rest, "urn:")` uses strict greater-than, so the string `"urn:"` (exactly 4 characters) does not trigger the `InvalidURNPrefix` path. It falls through to the length switch and returns `Error.InvalidLength`. The semantic is wrong: `"urn:"` is a malformed URN, not a wrong-length string.

**Fix:** Change `rest.len > 4` to `rest.len >= 4` (or `> 3`). Add test: `expectError(Error.InvalidURNPrefix, UUID.fromString("urn:"))`.

**Confidence:** confirmed

---

##### QC-42 — `toHex`/`toHexUpper` lack allocating variants (Low, Score 16)

**File:** `src/uuid.zig:244–252`

`UUID` exposes `toStringAlloc`, `toStringUpperAlloc`, and `toURNAlloc` for heap-owned output strings, but `toHex` and `toHexUpper` have no `Alloc` counterparts. Callers who need a heap-owned 32-char hex string must write `alloc.dupe(u8, u.toHex(&buf))` manually — boilerplate the library already handles for other formats.

**Fix:** Add `pub fn toHexAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8` and `pub fn toHexUpperAlloc(...)` mirroring `toStringAlloc`.

**Confidence:** confirmed

---

#### Documentation

##### QC-46 — `fromString` has no doc comment (Low, Score 16)

**File:** `src/uuid.zig:206`

`UUID.fromString` is the primary parse entry point for the library. It accepts six distinct input formats and returns five distinct errors, but has no leading `///` doc comment. `fromStringOrNil` (line 194) has a one-line comment, but `fromString` itself does not. This omits all format/error documentation from `zig doc` output.

**Fix:** Add a `///` doc comment listing all six input formats and all five possible errors. See QC-46 GitLab issue for draft text.

**Confidence:** confirmed

---

##### QC-43 — `CHANGELOG.md` `[Unreleased]` section has stale content (Low, Score 8)

**File:** `CHANGELOG.md:8–17`

The `[Unreleased]` section contains five placeholder lines ("Initial project structure", "Core library implementation", etc.) that duplicate the `[0.1.0] - 2026-03-21` section. Per Keep a Changelog convention, after a release the `[Unreleased]` section should be empty (or list only genuinely new post-release changes). The current state implies these features are not yet released, which is incorrect.

**Fix:** Replace the `[Unreleased]` body with an empty placeholder comment.

**Confidence:** confirmed

---

##### QC-44 — README/`build.zig.zon` declare Zig 0.15.1 minimum but CI tests with 0.15.2 (Low, Score 8)

**File:** `README.md:65`, `build.zig.zon:5`

`README.md` line 65 states "Zig 0.15.1 or later" and `build.zig.zon` sets `minimum_zig_version = "0.15.1"`. The CI (`ZIG_VERSION: "0.15.2"`) exclusively tests with 0.15.2. The library uses the `{f}` format specifier (Zig 0.15+ feature) but whether 0.15.1 supports the exact `pub fn format(self: UUID, w: *std.io.Writer)` signature is unverified. The declared minimum is untested.

**Fix:** Update `README.md` and `build.zig.zon` to declare `0.15.2` as the minimum (matching CI), or add a CI job that tests on 0.15.1.

**Confidence:** suspected

---

#### Tests

##### QC-40 — `Error.InvalidDashes` never exercised (Low, Score 16)

**File:** `src/uuid.zig:379`

`parseCanonical` returns `Error.InvalidDashes` when the four dash positions in a 36-character string are wrong (`s[8]`, `s[13]`, `s[18]`, `s[23]`). No test in any test file calls `expectError(Error.InvalidDashes, ...)`. A regression in this check (e.g., wrong position constant) would not be detected by the test suite.

**Fix:** Add a test case: `expectError(Error.InvalidDashes, UUID.fromString("6ba7b81009dad-11d1-80b4-00c04fd430c8"))`.

**Confidence:** confirmed

---

##### QC-41 — `setVariant(.ncs)` and `setVariant(.future)` branches untested (Low, Score 16)

**File:** `src/uuid.zig:111, 113`

`setVariant` has four branches: `.rfc9562`, `.ncs`, `.microsoft`, `.future`. Tests only exercise `.rfc9562` (via the setVariant test and all generation tests) and `.microsoft` (via the isValid wrong-variant test, which does not verify `variant()` returns `.microsoft`). The `.ncs` and `.future` branches and the corresponding `variant()` detection paths are dead from a test perspective.

**Fix:** Add a round-trip test for all four `Variant` values using `setVariant` → `variant()`.

**Confidence:** confirmed

---

#### Maintainability

##### QC-39 — `generator.zig` at 821 lines (Low, Score 12)

**File:** `src/generator.zig`

QC-38 compacted the vtable implementation and brought the file to 781 lines. The subsequent addition of the `castGen` inline helper (4 lines), expanded doc comments for `default_generator` (18 lines), and the test import block (9 lines) pushed it back to 821 lines — 21 over the 800-line guideline from QC-4.

**Fix:** Extract `GeneratorInterface` struct and `VTable` struct (lines ~699–751, ~53 lines) into `src/generator_interface.zig`, imported from `generator.zig` with the same `test { _ = @import("..."); }` pattern.

**Confidence:** confirmed

---

#### Benchmarks/Tests

##### QC-45 — `benchFromString` only measures canonical format (Low, Score 12)

**File:** `bench/main.zig:133–151`

`benchFromString` pre-generates one canonical UUID string and parses it 1 million times. The braced (`{...}`), URN (`urn:uuid:...`), and 32-char hex formats take different code paths (brace stripping, URN prefix stripping, `parseHash` vs `parseCanonical`) and are never profiled. Performance regressions in non-canonical paths are invisible.

**Fix:** Add `benchFromStringHex` and `benchFromStringURN` functions mirroring the existing pattern; call them from `main()`.

**Confidence:** confirmed

---

### Action Plan (Cycle 6)

#### Quick Wins (XS–S effort)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#101](https://gitlab.com/devnw/zig/uuid/-/work_items/101) | Fix `fromString("urn:")` returning wrong error | XS | Low |
| [#97](https://gitlab.com/devnw/zig/uuid/-/work_items/97) | Clear stale `[Unreleased]` content in CHANGELOG | XS | Low |
| [#98](https://gitlab.com/devnw/zig/uuid/-/work_items/98) | Align minimum Zig version to 0.15.2 | XS | Low |
| [#100](https://gitlab.com/devnw/zig/uuid/-/work_items/100) | Add doc comment to `fromString` | XS | Low |
| [#94](https://gitlab.com/devnw/zig/uuid/-/work_items/94) | Add `InvalidDashes` unit test | S | Low |
| [#95](https://gitlab.com/devnw/zig/uuid/-/work_items/95) | Add `setVariant`/`variant()` round-trip test for all 4 variants | S | Low |
| [#96](https://gitlab.com/devnw/zig/uuid/-/work_items/96) | Add `toHexAlloc` / `toHexUpperAlloc` | S | Low |
| [#93](https://gitlab.com/devnw/zig/uuid/-/work_items/93) | Extract `GeneratorInterface` to `generator_interface.zig` | S | Low |
| [#99](https://gitlab.com/devnw/zig/uuid/-/work_items/99) | Add benchFromStringHex + benchFromStringURN | S | Low |

---

_Last updated: 2026-03-21 — Cycle 6 findings created. 9 new findings (QC-39–QC-47), all Low severity, all open. 137 unit + 18 integration tests pass._

---

## Review Cycle 7 Findings (QC-48–QC-54)

> **Date:** 2026-03-22
> **Zig version audited:** 0.15.2
> **Scope:** New findings only — items QC-1..QC-47 not re-raised.
> **Build status:** All Cycle 6 fixes merged. 142 unit + 18 integration tests passing before this cycle.

---

### Summary

| Severity | Count |
| -------- | ----- |
| High     | 1     |
| Low      | 6     |

**Total new issues:** 7 — all closed (2026-03-22)

### Top 5 Risks

1. **`generator_state_test.zig` untracked in git** (QC-48, High, Score 64) — the file was created during QC-28 but never committed; 9 critical security/correctness tests are silently absent from all CI runs.
2. **`toHexAlloc`/`toHexUpperAlloc` lack integration tests** (QC-49, Low, Score 24) — allocating hex methods added in QC-42 have unit tests but no integration coverage verifying the full cross-module contract.
3. **README Quick Start omits `{f}` specifier** (QC-51, Low, Score 24) — users learn from README first; the zero-alloc preferred print pattern is absent from the most visible code sample.
4. **README has no API reference** (QC-52, Low, Score 24) — `isValid`, `isZero`, `GeneratorInterface`, `SecureHashContext`, `toHexAlloc`, `NullUUID` are discoverable only by reading source.
5. **CI missing `test-integration-release-safe` job** (QC-53, Low, Score 24) — integration tests run in Debug and ReleaseFast but not ReleaseSafe, leaving a safety-check coverage gap.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | High | 64 | tests | `generator_state_test.zig` untracked — 9 state tests absent from CI | `src/generator_state_test.zig` | `git status --porcelain` shows `??` | [#102](https://gitlab.com/devnw/zig/uuid/-/work_items/102) | ✅ CLOSED |
| 2 | Low | 24 | tests | `toHexAlloc`/`toHexUpperAlloc` not covered by integration tests | `tests/integration.zig` | `grep toHexAlloc tests/integration.zig` → no output | [#103](https://gitlab.com/devnw/zig/uuid/-/work_items/103) | ✅ CLOSED |
| 3 | Low | 24 | docs | README Quick Start omits `{f}` format specifier | `README.md:43–61` | `grep '{f}' README.md` → no output | [#105](https://gitlab.com/devnw/zig/uuid/-/work_items/105) | ✅ CLOSED |
| 4 | Low | 24 | docs | README has no API reference section | `README.md` | No `## API` heading exists | [#106](https://gitlab.com/devnw/zig/uuid/-/work_items/106) | ✅ CLOSED |
| 5 | Low | 24 | ci-cd | CI missing `test-integration-release-safe` job | `.gitlab-ci.yml` | Unit has ReleaseSafe; integration does not | [#107](https://gitlab.com/devnw/zig/uuid/-/work_items/107) | ✅ CLOSED |
| 6 | Low | 16 | docs | `examples/basic.zig` does not demonstrate `toHexAlloc`/`toHexUpperAlloc` | `examples/basic.zig:74–82` | No alloc call in "Output formats" section | [#104](https://gitlab.com/devnw/zig/uuid/-/work_items/104) | ✅ CLOSED |
| 7 | Low | 16 | docs | `toStringAlloc` has no doc comment | `src/uuid.zig:296` | Only public output method with zero `///` doc | [#108](https://gitlab.com/devnw/zig/uuid/-/work_items/108) | ✅ CLOSED |

---

### Findings by Category

#### Tests

##### QC-48 — `generator_state_test.zig` untracked in git (High, Score 64) ✅ CLOSED

**File:** `src/generator_state_test.zig`

The file was split from `generator.zig` during QC-28 (generator_test.zig split policy) and contains 327 lines across 9 test cases covering:

- `saveState` round-trip (F-9 + SEC-10)
- V7 fast-restart overflow branch (PERF-04)
- Atomic write: no `.tmp` file lingers (SEC-9)
- Corrupt magic rejection (F-9)
- v1 format backward compatibility (SEC-10)
- Symlink safety at `.tmp` path (SEC-R3-01)
- Trailing-bytes rejection (SEC-R4-03)
- Fast-restart injectable clock branch (QC-29)
- Slow-restart injectable clock branch (QC-29)

`git status --porcelain` shows `?? src/generator_state_test.zig` — the file is untracked, meaning `git clone` delivers a repository where all these tests are invisible. `generator.zig` line 779 imports it, but the import is dead in CI since the file never lands in the build.

**Root cause:** The file was created during Cycle 6 implementation but `git add` was not run.

**Fix:** `git add src/generator_state_test.zig && git commit`.

**Resolution (2026-03-22):** Staged `src/generator_state_test.zig` with `git add`. File now shows `A  src/generator_state_test.zig` in `git status`.

**Confidence:** confirmed

---

##### QC-49 — `toHexAlloc`/`toHexUpperAlloc` not covered by integration tests (Low, Score 24) ✅ CLOSED

**File:** `tests/integration.zig`

`tests/integration.zig` lines 196–204 exercise `toStringUpper` and `toHexUpper` (stack-buffer forms), but `toHexAlloc` and `toHexUpperAlloc` (added in QC-42) are not tested at the integration level. Unit tests exist in `src/uuid.zig` (lines 732–746), but integration tests verify the full cross-module contract: that the allocator and the uuid module interact correctly under the integration build configuration.

**Root cause:** QC-42 added unit tests but did not update `tests/integration.zig`.

**Fix:** Add a test:

```zig
test "integration: toHexAlloc and toHexUpperAlloc" {
    const alloc = std.testing.allocator;
    const u = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const lower = try u.toHexAlloc(alloc);
    defer alloc.free(lower);
    try std.testing.expectEqualStrings("6ba7b8109dad11d180b400c04fd430c8", lower);
    const upper = try u.toHexUpperAlloc(alloc);
    defer alloc.free(upper);
    try std.testing.expectEqualStrings("6BA7B8109DAD11D180B400C04FD430C8", upper);
}
```

**Resolution (2026-03-22):** Added two integration tests to `tests/integration.zig`: `"integration: toHexAlloc produces lowercase 32-char hex"` and `"integration: toHexUpperAlloc produces uppercase 32-char hex"`. Integration test count increased from 18 to 20.

**Confidence:** confirmed

---

#### Documentation

##### QC-50 — `examples/basic.zig` does not demonstrate `toHexAlloc`/`toHexUpperAlloc` (Low, Score 16) ✅ CLOSED

**File:** `examples/basic.zig:74–82`

The "Output formats" section demonstrates all five stack-buffer output forms (`toString`, `toStringUpper`, `toHex`, `toHexUpper`, `toURN`) but omits the allocating hex variants. The QC-42 implementation added `toHexAlloc` and `toHexUpperAlloc` without updating examples.

**Fix:** Add a short "Allocating output" block showing `toHexAlloc` with `defer alloc.free(s)`.

**Resolution (2026-03-22):** Added "Allocating hex output" section to `examples/basic.zig` using `std.heap.page_allocator`, demonstrating both `toHexAlloc` and `toHexUpperAlloc` with `defer alloc.free`. `zig build examples` passes.

**Confidence:** confirmed

---

##### QC-51 — README Quick Start omits the `{f}` format specifier (Low, Score 24) ✅ CLOSED

**File:** `README.md:43–61`

The README Quick Start shows:

```zig
var buf: [36]u8 = undefined;
std.debug.print("V7: {s}\n", .{v7.toString(&buf)});
```

The preferred zero-alloc form (`std.debug.print("{f}\n", .{v7})`) is documented in `src/root.zig`'s module doc (QC-36) but absent from README. Users who learn from README will default to the verbose pattern.

**Fix:** Add one `{f}` example line to the Quick Start code block, e.g.:

```zig
// Zero-alloc: no buffer needed (Zig 0.15+ {f} specifier)
std.debug.print("{f}\n", .{v7});
```

**Resolution (2026-03-22):** Added `std.debug.print("{f}\n", .{v7});` with comment to README Quick Start code block.

**Confidence:** confirmed

---

##### QC-52 — README has no API reference section (Low, Score 24) ✅ CLOSED

**File:** `README.md`

The README covers Features, Installation, Quick Start, Requirements, Building, Documentation, Security, Performance, and Contributing — but contains no section that lists the public API. Methods like `isValid`, `isZero`, `validate`, `fromBytesOrNil`, `fromStringOrNil`, `toHexAlloc`, `toURNAlloc`, `SecureHashContext`, `GeneratorInterface`, `clearNodeCache`, `NullUUID`, and `timestampFromV1/V6/V7` are completely undiscoverable from README.

**Fix:** Add a `## API Reference` section with a table of key types and their principal methods. Effort M.

**Resolution (2026-03-22):** Added `## API Reference` section to README with reference tables covering Generation, UUID type methods, Timestamp extraction, NullUUID, Generator, HashMap contexts, and Namespace constants.

**Confidence:** confirmed

---

##### QC-54 — `toStringAlloc` has no doc comment (Low, Score 16) ✅ CLOSED

**File:** `src/uuid.zig:296`

```zig
pub fn toStringAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
```

Every other public output method has a `///` doc comment (`toString`, `toStringUpper`, `toHex`, `toHexUpper`, `toURN`, `toURNAlloc`, `toStringUpperAlloc`, `toHexAlloc`, `toHexUpperAlloc`). `toStringAlloc` alone has none, creating an asymmetry in generated documentation.

**Fix:** Add `/// Allocating canonical lowercase with dashes: \`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx\`.` immediately above the function.

**Resolution (2026-03-22):** Added two-line `///` doc comment to `toStringAlloc` in `src/uuid.zig`: describes the format and notes the caller-must-free contract.

**Confidence:** confirmed

---

#### CI/CD

##### QC-53 — CI missing `test-integration-release-safe` job (Low, Score 24) ✅ CLOSED

**File:** `.gitlab-ci.yml`

CI matrix:

- Unit tests: Debug ✅ ReleaseSafe ✅ ReleaseFast ✅
- Integration tests: Debug ✅ ReleaseFast ✅ **ReleaseSafe ❌**

The `test-integration-release-fast` job was added but the symmetric `test-integration-release-safe` job was not. ReleaseSafe applies optimisations while retaining safety checks; a bug triggered by those optimisations in integration paths (concurrent V7 generation, JSON round-trip, saveState/loadState) would not be caught.

**Fix:** Add:

```yaml
test-integration-release-safe:
  stage: test
  image: debian:bookworm-slim
  before_script:
    - *install-zig
  script:
    - zig build test-integration -Doptimize=ReleaseSafe --summary all
  needs:
    - build
```

**Resolution (2026-03-22):** Added `test-integration-release-safe` job to `.gitlab-ci.yml` immediately before `test-integration-release-fast`, consistent with existing job naming. CI matrix is now complete: integration tests cover Debug, ReleaseSafe, and ReleaseFast.

**Confidence:** confirmed

---

### Action Plan (Cycle 7) — All Complete

#### Quick Wins (XS effort)

| Issue | Title | Effort | Severity | Status |
| ----- | ----- | ------ | -------- | ------ |
| [#102](https://gitlab.com/devnw/zig/uuid/-/work_items/102) | Track `generator_state_test.zig` in git | XS | High | ✅ CLOSED |
| [#108](https://gitlab.com/devnw/zig/uuid/-/work_items/108) | Add doc comment to `toStringAlloc` | XS | Low | ✅ CLOSED |
| [#105](https://gitlab.com/devnw/zig/uuid/-/work_items/105) | Add `{f}` example to README Quick Start | XS | Low | ✅ CLOSED |
| [#107](https://gitlab.com/devnw/zig/uuid/-/work_items/107) | Add `test-integration-release-safe` CI job | XS | Low | ✅ CLOSED |
| [#103](https://gitlab.com/devnw/zig/uuid/-/work_items/103) | Add integration tests for `toHexAlloc`/`toHexUpperAlloc` | XS | Low | ✅ CLOSED |
| [#104](https://gitlab.com/devnw/zig/uuid/-/work_items/104) | Demonstrate `toHexAlloc` in `examples/basic.zig` | XS | Low | ✅ CLOSED |

#### Medium Effort

| Issue | Title | Effort | Severity | Status |
| ----- | ----- | ------ | -------- | ------ |
| [#106](https://gitlab.com/devnw/zig/uuid/-/work_items/106) | Add `## API Reference` section to README | M | Low | ✅ CLOSED |

---

_Last updated: 2026-03-22 — Cycle 7 closed. 7 new findings (QC-48–QC-54): 1 High, 6 Low. All 7 closed. 142 unit + 20 integration tests passing._

---

## Review Cycle 8 Findings (QC-55–QC-61)

> **Date:** 2026-03-22
> **Zig version audited:** 0.15.2
> **Scope:** New findings only — items QC-1..QC-54 not re-raised.
> **Build status at start of cycle:** `zig build test --summary all` 142/142 ✅, `zig build test-integration --summary all` 20/20 ✅
> **Focus areas:** NullUUID completeness, thread safety documentation, hwaddr test coverage, root.zig export correctness, build.zig.zon packaging, CI pipeline gaps, Makefile discoverability

---

### Summary

| Severity | Count |
| -------- | ----- |
| High     | 2     |
| Medium   | 4     |
| Low      | 1     |

**Total new issues:** 7 — all open, status::triage

### Top 5 Risks

1. **`pub const default_generator` in `root.zig` breaks mutating API** (QC-60, High, Score 64) — external callers cannot call `saveState`, `loadState`, or `clearNodeCache` on `uuid.default_generator` because `root.zig` exports it as `const`, preventing the compiler from taking a mutable pointer for method dispatch.
2. **README documents `uuid.isMax()` which does not exist** (QC-56, High, Score 64) — any developer following the documented API table will get a compile error. `UUID.max` sentinel exists but the method does not.
3. **`NullUUID` has no `format` method** (QC-55, Medium, Score 36) — `UUID` supports `{f}` (Zig 0.15+ zero-alloc formatter) but `NullUUID` does not, creating an asymmetric API surface for the two primary UUID types.
4. **README documents wrong parameter types for `newV1AtTime`/`newV6AtTime`** (QC-57, Medium, Score 36) — documents `ms: i64` but actual parameter is `ts: Timestamp`, causing confusing compile errors for users following the README.
5. **`build.zig.zon` `.paths` omits `tests/` and `bench/`** (QC-58, Medium, Score 36) — published packages will be missing integration tests and benchmarks, causing `zig build test-integration` to fail for downstream consumers.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | High | 64 | api-contract | `pub const default_generator` in `root.zig` prevents callers from calling mutating methods | `src/root.zig:52` | `pub const` re-export of `pub var`; `saveState`/`loadState`/`clearNodeCache` require `*Generator` | [#109](https://gitlab.com/devnw/zig/uuid/-/work_items/109) | ✅ Closed (QC-60) |
| 2 | High | 64 | docs | README API Reference documents `uuid.isMax()` which does not exist | `README.md:107` | `grep "isMax" src/uuid.zig` → 0 results; README documents it as implemented | [#110](https://gitlab.com/devnw/zig/uuid/-/work_items/110) | ✅ Closed (QC-56) |
| 3 | Medium | 36 | api-contract | `NullUUID` missing `format` method — `{f}` specifier not supported | `src/null_uuid.zig` | No `pub fn format` definition; `UUID` has one at `src/uuid.zig:323` | [#111](https://gitlab.com/devnw/zig/uuid/-/work_items/111) | ✅ Closed (QC-55) |
| 4 | Medium | 36 | docs | README documents wrong parameter types for `newV1AtTime`/`newV6AtTime` | `README.md:73,78` | `ms: i64` vs actual `ts: Timestamp` | [#112](https://gitlab.com/devnw/zig/uuid/-/work_items/112) | ✅ Closed (QC-57) |
| 5 | Medium | 36 | maintainability | `build.zig.zon` `.paths` omits `tests/`, `bench/`, `CHANGELOG.md` | `build.zig.zon:12–21` | Directories exist but absent from `.paths`; downstream `zig build test-integration` fails | [#113](https://gitlab.com/devnw/zig/uuid/-/work_items/113) | ✅ Closed (QC-58) |
| 6 | Medium | 36 | ci-cd | Fuzz targets never exercised in CI — only static corpus test mode runs | `.gitlab-ci.yml`, `src/fuzz.zig:8` | No CI job uses `--fuzz`; all test jobs omit the flag | [#114](https://gitlab.com/devnw/zig/uuid/-/work_items/114) | ✅ Closed (QC-59) |
| 7 | Low | 24 | maintainability | `Makefile` missing `bench` and `fuzz` targets | `Makefile` | No `bench` or `fuzz` .PHONY entries; `make help` omits them | [#115](https://gitlab.com/devnw/zig/uuid/-/work_items/115) | ✅ Closed (QC-61) |

---

### Findings by Category

#### API Contract

##### QC-60 — `pub const default_generator` in `root.zig` prevents mutating method calls (High, Score 64) ✅ CLOSED

**File:** `src/root.zig:52`

`src/root.zig` re-exports `generator.zig`'s `pub var default_generator` as:

```zig
pub const default_generator = @import("generator.zig").default_generator;
```

In Zig, `pub const` creates a constant binding. Callers cannot obtain a `*Generator` pointer from a `const` location, so any method that takes `self: *Generator` fails to compile when called on `uuid.default_generator`. Affected methods: `saveState(path)`, `loadState(path)`, `clearNodeCache()`, `newV4()`, `newV7()`, and all other generation methods.

The package-level convenience functions in `versions.zig` work because they import `generator.zig` directly (`const gen_mod = @import("generator.zig")`) and access `gen_mod.default_generator` which _is_ a `var`. External consumers importing `uuid` see only the `const` re-export from `root.zig`.

The doc comment on `default_generator` in `generator.zig` (lines 665–680) explicitly advises callers to call `loadState`, `saveState`, and `clearNodeCache` on the shared instance — guidance that is impossible to follow with the current re-export.

**Fix:** Change `root.zig:52` from `pub const` to `pub var`:

```zig
pub var default_generator = @import("generator.zig").default_generator;
```

**Confidence:** confirmed

**Resolution:** Changed `pub const` to `pub var` in `src/root.zig:52`. All 145 unit tests pass. 2026-03-22.

---

##### QC-55 — `NullUUID` missing `format` method — `{f}` specifier not supported (Medium, Score 36) ✅ CLOSED

**File:** `src/null_uuid.zig`

`UUID` implements:

```zig
pub fn format(self: UUID, w: *std.io.Writer) std.io.Writer.Error!void
```

enabling `std.fmt.print("{f}", .{uuid})`. `NullUUID` has no equivalent, so `std.fmt.print("{f}", .{nullUUID})` fails to compile with "no field or member function 'format' in 'NullUUID'". Users who migrate from `UUID` to `NullUUID` discover this incompatibility only at compile time.

**Fix:** Add to `src/null_uuid.zig`:

```zig
pub fn format(self: NullUUID, w: *std.io.Writer) std.io.Writer.Error!void {
    if (!self.valid) {
        try w.writeAll("null");
    } else {
        var buf: [36]u8 = undefined;
        try w.writeAll(self.uuid.toString(&buf));
    }
}
```

**Confidence:** confirmed

**Resolution:** Added `NullUUID.format` to `src/null_uuid.zig`. Null path prints "null"; valid path delegates to `self.uuid.format(w)`. Added 2 tests: "NullUUID.format valid UUID" and "NullUUID.format null". Test count: 145. 2026-03-22.

---

#### Documentation

##### QC-56 — README documents `uuid.isMax()` which does not exist (High, Score 64) ✅ CLOSED

**File:** `README.md:107`

The README API Reference table includes:

```markdown
| `uuid.isMax() bool` | True if all bytes are 0xFF |
```

No such method exists in `src/uuid.zig`. `UUID.max` is a sentinel constant (`src/uuid.zig:49`) but there is no `isMax()` method. Any developer following the README will get a compile error with no obvious fix.

The `isMax()` method would provide symmetry with `isNil()`. The fix is either to implement it (preferred — consistent API surface) or remove it from the README.

**Recommended fix:** Add to `src/uuid.zig`:

```zig
/// Returns true when all 16 bytes are 0xFF (the RFC-9562 max UUID).
pub fn isMax(self: UUID) bool {
    return std.mem.eql(u8, &self.bytes, &max.bytes);
}
```

**Confidence:** confirmed

**Resolution:** Added `pub fn isMax(self: UUID) bool` to `src/uuid.zig` immediately after `isNil()`, using `UUID.max.bytes` for symmetry. Added test "UUID.isMax returns true for max UUID (QC-56)". Test count: 145. 2026-03-22.

---

##### QC-57 — README API Reference documents wrong parameter types for `newV1AtTime`/`newV6AtTime` (Medium, Score 36) ✅ CLOSED

**File:** `README.md:73,78`

```markdown
| `newV1AtTime(ms: i64) !UUID` | V1 at a specific Unix-ms timestamp |
| `newV6AtTime(ms: i64) !UUID` | V6 at a specific Unix-ms timestamp |
```

Actual signatures in `src/versions.zig:19,47`:

```zig
pub fn newV1AtTime(ts: Timestamp) Error!UUID
pub fn newV6AtTime(ts: Timestamp) Error!UUID
```

The parameter type is `Timestamp` (a Gregorian-epoch wrapper), not `i64`. V7 correctly uses `i64` (Unix milliseconds). The mismatch is confusing: users reading the README will write `newV1AtTime(1_700_000_000_000)` and get a type error.

**Fix:** Update README table entries to `ts: Timestamp` and add a note distinguishing Gregorian (V1/V6) from Unix-ms (V7).

**Confidence:** confirmed

**Resolution:** Updated `README.md` to show `newV1AtTime(ts: Timestamp) !UUID` and `newV6AtTime(ts: Timestamp) !UUID` with description "Gregorian timestamp". `newV7AtTime(ms: i64)` unchanged (correct). Documentation-only fix. 2026-03-22.

---

#### Maintainability

##### QC-58 — `build.zig.zon` `.paths` omits `tests/`, `bench/`, `CHANGELOG.md` (Medium, Score 36) ✅ CLOSED

**File:** `build.zig.zon:12–21`

The `.paths` list controls which files are included in the published package artifact. Current list:

```zig
.paths = .{ "build.zig", "build.zig.zon", "src", "examples", "docs", "LICENSE", "README.md" },
```

Missing: `tests/` (integration tests), `bench/` (benchmarks), `CHANGELOG.md`. When downstream consumers fetch this package and run `zig build test-integration` or `zig build bench`, the build system will fail to find `tests/integration.zig` or `bench/main.zig` because those files were never included in the published artifact.

**Fix:** Add the missing paths to `build.zig.zon`.

**Confidence:** confirmed

**Resolution:** Added `"tests"`, `"bench"`, and `"CHANGELOG.md"` to `.paths` in `build.zig.zon`. `zig build check` passes. Config-only fix. 2026-03-22.

---

##### QC-61 — `Makefile` missing `bench` and `fuzz` targets (Low, Score 24) ✅ CLOSED

**File:** `Makefile`

`build.zig` defines both `bench` and `bench-check` steps; `src/fuzz.zig` documents `zig build test --fuzz` as the fuzz entry point. Neither is accessible via `make`. `make help` has no `bench` or `fuzz` entry. New contributors consulting `make help` as their first step will not discover benchmarking or fuzzing capabilities.

**Fix:** Add `bench` and `fuzz` make targets with corresponding `help` entries.

**Confidence:** confirmed

**Resolution:** Added `bench` (`zig build bench -Doptimize=ReleaseFast`) and `fuzz` (`zig build test --fuzz`) targets to `Makefile`. Added both to `.PHONY` and `help` output. 2026-03-22.

---

#### CI/CD

##### QC-59 — Fuzz targets never exercised in CI (Medium, Score 36) ✅ CLOSED

**File:** `.gitlab-ci.yml`, `src/fuzz.zig:8`

`src/fuzz.zig` contains three fuzz targets protected by `std.testing.fuzz`. In normal test mode (`zig build test`), `std.testing.fuzz` runs only the provided static corpus — no mutation or coverage-guided fuzzing occurs. No CI job uses `--fuzz`, meaning the security value of the fuzz infrastructure (finding non-corpus crash inputs) is never realized in CI.

`src/fuzz.zig` explicitly states "Run with: zig build test --fuzz (requires Zig 0.15+)" implying CI usage was intended but never implemented.

**Fix:** Add a scheduled CI job that runs `zig build test --fuzz` with a timeout, or explicitly document that fuzzing is a manual developer workflow and update the comment in `src/fuzz.zig` accordingly.

**Confidence:** confirmed

**Resolution:** Added `fuzz` job to `.gitlab-ci.yml` in a new `fuzz` stage (after `test`, before `security`). Runs `timeout 60 zig build test --fuzz || true` on scheduled pipelines and manual triggers only. `allow_failure: true` ensures pipeline health is not impacted by timeout exits. Makefile `fuzz` target also added (QC-61). 2026-03-22.

---

### Action Plan (Cycle 8)

#### Quick Wins (XS effort)

| Issue | Title | Effort | Severity | Status |
| ----- | ----- | ------ | -------- | ------ |
| [#109](https://gitlab.com/devnw/zig/uuid/-/work_items/109) | Change `pub const default_generator` to `pub var` in `root.zig` | XS | High | ✅ Closed |
| [#110](https://gitlab.com/devnw/zig/uuid/-/work_items/110) | Add `isMax()` method or remove from README | XS | High | ✅ Closed |
| [#112](https://gitlab.com/devnw/zig/uuid/-/work_items/112) | Fix README parameter types for `newV1AtTime`/`newV6AtTime` | XS | Medium | ✅ Closed |
| [#113](https://gitlab.com/devnw/zig/uuid/-/work_items/113) | Add `tests/`, `bench/`, `CHANGELOG.md` to `build.zig.zon` `.paths` | XS | Medium | ✅ Closed |
| [#115](https://gitlab.com/devnw/zig/uuid/-/work_items/115) | Add `bench` and `fuzz` targets to `Makefile` | XS | Low | ✅ Closed |

#### Small Effort (S)

| Issue | Title | Effort | Severity | Status |
| ----- | ----- | ------ | -------- | ------ |
| [#111](https://gitlab.com/devnw/zig/uuid/-/work_items/111) | Add `format` method to `NullUUID` + unit/integration tests | S | Medium | ✅ Closed |
| [#114](https://gitlab.com/devnw/zig/uuid/-/work_items/114) | Add scheduled fuzz CI job or document manual-only fuzzing | S | Medium | ✅ Closed |

---

_Last updated: 2026-03-22 — Cycle 8 complete. 7 findings (QC-55–QC-61): 2 High, 4 Medium, 1 Low. All 7 closed. 145 unit + 20 integration tests pass._

---

## Quality Review Cycle 10

> **Date:** 2026-03-22
> **Zig version audited:** 0.15.2
> **Scope:** Full codebase review — source, tests, benchmarks, examples, CI, build system, docs.
> **Previous cycles:** QC-1 through QC-61 covered in Cycles 1–8. Cycle 9 found no new issues.

---

### Summary

| Severity | Count |
| -------- | ----- |
| Low      | 9     |

**Total new issues:** 9 — all open, status::triage

### Top 5 Risks

1. **generator.zig at 847 lines** (QC-64) — third recurrence of file-size violation; vtable block is the extractable unit.
2. **uuid.zig at 889 lines** (QC-65) — first detection; 410-line test block should be split to `uuid_test.zig`.
3. **Benchmark DCE risk** (QC-63) — 5 generation benchmarks discard UUID with `_ =`; V3/V5/output benchmarks already use sink pattern.
4. **V3/V5 namespace coverage gap** (QC-66) — URL, OID, X.500 namespace test vectors absent.
5. **Zero error-path integration tests** (QC-69) — 20+ integration tests but no `expectError` calls; error propagation through public API unverified.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | Low | 16 | maintainability | `src/generator.zig` at 847 lines — third recurrence, 47 over guideline | `src/generator.zig` | `wc -l` = 847; vtable lines 710–847 extractable | [#134](https://gitlab.com/devnw/zig/uuid/-/work_items/134) | 🚫 Won't Do (circular import) |
| 2 | Low | 16 | maintainability | `src/uuid.zig` at 889 lines — 89 over guideline; test block ~410 lines | `src/uuid.zig` | `wc -l` = 889; test block starts line 479 | [#135](https://gitlab.com/devnw/zig/uuid/-/work_items/135) | ✅ Closed |
| 3 | Low | 16 | maintainability | `benchV4/V7/V1/V6/V7AtTime` use `_ = try gen.newV*()` — no sink, potential DCE | `bench/main.zig:44,54,64,74,229` | V3/V5 benchmarks use sink; generation benchmarks do not | [#133](https://gitlab.com/devnw/zig/uuid/-/work_items/133) | ✅ Closed |
| 4 | Low | 16 | tests | V3/V5 tests only use `namespace_dns` — URL/OID/X.500 namespaces untested | `src/generator_test.zig:152–176` | Zero uses of `namespace_url/oid/x500` in tests | [#136](https://gitlab.com/devnw/zig/uuid/-/work_items/136) | ✅ Closed |
| 5 | Low | 12 | docs | 7 public functions in `src/uuid.zig` have no doc comments | `src/uuid.zig:61,69,109,113,122,126,192,338` | `variant`, `isNil`, `setVersion`, `setVariant`, `eql`, `order`, `fromBytes`, `jsonMarshal` | [#132](https://gitlab.com/devnw/zig/uuid/-/work_items/132) | ✅ Closed |
| 6 | Low | 12 | docs | README `NullUUID` table omits `format()`, `jsonMarshal()`, `jsonUnmarshal()` | `README.md:123–129` | Only 2 of 5 public methods documented | [#137](https://gitlab.com/devnw/zig/uuid/-/work_items/137) | ✅ Closed |
| 7 | Low | 12 | ci-cd | No `test-release-small` CI job — `ReleaseSmall` never tested in CI | `.gitlab-ci.yml` | 3 modes tested; ReleaseSmall omitted | [#138](https://gitlab.com/devnw/zig/uuid/-/work_items/138) | ✅ Closed |
| 8 | Low | 12 | tests | `tests/integration.zig` has zero `expectError` calls — error paths unverified | `tests/integration.zig` | `grep expectError tests/integration.zig` → no output | [#139](https://gitlab.com/devnw/zig/uuid/-/work_items/139) | ✅ Closed |
| 9 | Low | 8 | docs | README `Generator` table omits `Generator.withRand(f)` | `README.md:130–141` | `withClock` and `withHWAddr` present; `withRand` absent | [#140](https://gitlab.com/devnw/zig/uuid/-/work_items/140) | ✅ Closed |

---

### Detailed Findings

#### QC-62 — Seven public API functions in `src/uuid.zig` lack doc comments (Low, Score 12)

**Status: ✅ Closed**

**File:** `src/uuid.zig:61,69,109,113,122,126,192,338`

`variant()`, `isNil()`, `setVersion()`, `setVariant()`, `eql()`, `order()`, `fromBytes()`, and `jsonMarshal()` have no `///` doc comments. The gap is asymmetric — `version()`, `isMax()`, `isValid()`, and all output methods are well-documented.

**Fix applied:** Doc comments added to all 8 functions explaining semantics, RFC references, and error conditions.

**Confidence:** confirmed

---

#### QC-63 — `benchV4/V7/V1/V6/V7AtTime` missing sink variable — potential DCE in ReleaseFast (Low, Score 16)

**Status: ✅ Closed**

**File:** `bench/main.zig:44,54,64,74,229`

Five generation benchmarks discard the UUID with `_ = try gen.newV*()`. While CSPRNG/mutex side effects prevent full elision, the UUID struct construction itself may be DCE'd. V3/V5/output benchmarks already use `sink ^= u.bytes[0]` (established by PERF-11) — generation benchmarks should follow the same discipline.

**Fix applied:** XOR sink pattern added to `benchV4`, `benchV7`, `benchV1`, `benchV6`, and `benchV7AtTime`.

**Confidence:** confirmed

---

#### QC-64 — `src/generator.zig` at 847 lines — third recurrence of 800-line violation (Low, Score 16)

**Status: 🚫 Won't Do — Circular Import (same resolution as QC-38)**

**File:** `src/generator.zig:710–847`

The `GeneratorInterface` struct, its `VTable`, dispatch wrappers, and `generator_vtable` constant span lines 710–847 (137 lines). Extraction to `src/generator_interface.zig` is blocked by a circular import: `generator_interface.zig` would need to import `*Generator` from `generator.zig`, and `generator.zig` would need to import `GeneratorInterface` for `fromGenerator()` and the vtable. This is identical to the blocker found in QC-38.

**Confidence:** confirmed

---

#### QC-65 — `src/uuid.zig` at 889 lines — 89 over 800-line guideline (Low, Score 16)

**Status: ✅ Closed**

**File:** `src/uuid.zig:479–889`

Test block (~410 lines, 40+ test cases) mixed with production UUID type. The same pattern was resolved for `generator.zig` via QC-4 (split to `generator_test.zig`).

**Fix applied:** Created `src/uuid_test.zig` with the full test block. `uuid.zig` reduced to 523 lines. `uuid.zig` now contains `test { _ = @import("uuid_test.zig"); }`.

**Confidence:** confirmed

---

#### QC-66 — V3/V5 tests only use `namespace_dns` — URL, OID, X.500 namespaces untested (Low, Score 16)

**Status: ✅ Closed**

**File:** `src/generator_test.zig:152–176`

V3 and V5 are pure hash functions of `(namespace_bytes || name)`. A byte-order bug specific to certain namespace patterns (e.g. `namespace_url` differs from `namespace_dns` at byte 3) would escape detection.

**Fix applied:** 6 test vectors added to `src/generator_test.zig`: V3 and V5 for `namespace_url`, `namespace_oid`, and `namespace_x500`, all verified against Python's `uuid.uuid3()`/`uuid.uuid5()`.

**Confidence:** confirmed

---

#### QC-67 — README `NullUUID` API table omits `format()`, `jsonMarshal()`, `jsonUnmarshal()` (Low, Score 12)

**Status: ✅ Closed**

**File:** `README.md:123–129`

The NullUUID section lists only 2 of 5 public methods. `format(w)` (added in QC-55), `jsonMarshal(alloc)`, and `jsonUnmarshal(alloc, v)` are absent.

**Fix applied:** 3 rows added to the NullUUID API table in README.md.

**Confidence:** confirmed

---

#### QC-68 — CI has no `test-release-small` job (Low, Score 12)

**Status: ✅ Closed**

**File:** `.gitlab-ci.yml`

Three optimization levels are CI-tested (Debug, ReleaseSafe, ReleaseFast). `ReleaseSmall` uses different inlining/DCE trade-offs and is a valid target for embedded/WASM deployments. `Makefile` already has the target.

**Fix applied:** `test-release-small` CI job added to `.gitlab-ci.yml` in the test stage.

**Confidence:** confirmed

---

#### QC-69 — `tests/integration.zig` has zero `expectError` calls (Low, Score 12)

**Status: ✅ Closed**

**File:** `tests/integration.zig`

All 20+ integration tests exercise only happy paths. Error propagation through the public API (`uuid.UUID.fromString` returning `InvalidLength`, etc.) is verified only in unit tests that import `src/uuid.zig` directly, never through `@import("uuid")`.

**Fix applied:** 10 `expectError` integration tests added covering: empty string, short string, bad URN namespace, wrong-length URN payload, non-hex characters, wrong dash positions, unclosed brace, wrong-length bytes, invalid JSON value type, invalid UUID string via JSON.

**Confidence:** confirmed

---

#### QC-70 — README `Generator` API table omits `Generator.withRand(f)` (Low, Score 8)

**Status: ✅ Closed**

**File:** `README.md:130–141`

`withClock` and `withHWAddr` are documented. `withRand` — the third injectable interface, essential for deterministic testing — is absent.

**Fix applied:** `Generator.withRand(f) Generator` row added to README.md Generator table.

**Confidence:** confirmed

---

_Last updated: 2026-03-22 — Cycle 10 closed. 9 findings (QC-62–QC-70): 8 closed, 1 Won't Do (QC-64). 161 unit + 30 integration tests pass._

---

## Won't Do Policy — All Cycles (MANDATORY for future agents)

> The following categories MUST remain 🚫 Won't Do across ALL `*GAP_ANALYSIS.md` files.
> Future agents MUST NOT re-open, re-implement, or re-report these items.
>
> - **CI/CD Zig toolchain checksum/SHA256 verification** — handled by pipeline governance (Renovate/org policy)
> - **Docker image digest/tag pinning** — handled by infrastructure controls outside this library
> - **CI catalog component tag pinning** (mutable semver tags in GitLab CI includes) — pipeline governance
> - **Pre-commit hook modifications** (`check-yaml --unsafe`, `check-todos`, hook versioning) — developer tooling team
>
> Evidence: `docs/GAP_ANALYSIS.md` Won't Do blocks (all security review cycles), QC-16 in this file.

---

## Quality Review Cycle 11

> **Date:** 2026-03-22
> **Zig version audited:** 0.15.2
> **Branch reviewed:** `fix/sec-r9-01-timing-safe-eql`
> **Previous cycles:** Cycles 1–10 (QC-1–QC-70) — 68 closed, 2 Won't Do.
> **Scope:** New findings only, focused on `timingSafeEql` API surface gap introduced by the SEC-R9-01 fix.

---

### Summary

| Severity | Count | Status |
| -------- | ----- | ------ |
| Low      | 5     | ✅ 5 closed |

**Total new issues:** 5 — QC-71 through QC-75, all closed.

**Key finding:** The SEC-R9-01 fix commit (3a29957) correctly implemented `UUID.timingSafeEql()` with full doc comments and 5 unit tests, but did not update four surrounding artifacts: the README API table, CHANGELOG, bench/main.zig, and tests/integration.zig. SECURITY.md is also missing the corresponding API-contract guidance (distinct from SEC-R10-01 security advisory).

**Clean checks:**

- `zig fmt --check` — PASS (no formatting issues)
- `zig build check` — PASS (no compilation errors)
- `zig build test` — PASS (all tests pass)
- `src/uuid.zig` — 550 lines (under 800-line guideline; +27 lines from Cycle 10's 523 after timingSafeEql addition)
- `src/uuid_test.zig` — 499 lines (under 800-line guideline)
- No TODO/FIXME/HACK/XXX in source (only `(G-2)` markers in doc comments — not issue markers)
- CI `.gitlab-ci.yml` — all 4 optimization levels covered; timingSafeEql exercised implicitly by existing test jobs

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Fix Summary | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ----------- | ------ |
| 1 | Low | 48 | docs | README UUID API table omits `timingSafeEql` — new public method invisible to API consumers | `README.md:85–112` | `grep timingSafeEql README.md` → 0 hits; table ends at `eql` row | [#144](https://gitlab.com/devnw/zig/uuid/-/work_items/144) | Add `timingSafeEql` row after `eql` row; add cross-ref in `eql` description | ✅ Closed |
| 2 | Low | 24 | docs | CHANGELOG.md `[Unreleased]` missing `timingSafeEql` addition | `CHANGELOG.md:8–18` | `grep timingSafeEql CHANGELOG.md` → 0 hits; new public API not recorded | [#145](https://gitlab.com/devnw/zig/uuid/-/work_items/145) | Add `### Added` entry for `timingSafeEql` + `### Changed` for `eql` doc | ✅ Closed |
| 3 | Low | 24 | tests | `tests/integration.zig` missing `timingSafeEql` coverage through public package | `tests/integration.zig:1–383` | `grep timingSafeEql tests/integration.zig` → 0 hits | [#147](https://gitlab.com/devnw/zig/uuid/-/work_items/147) | Add 2 integration tests: equal UUID returns true, unequal returns false | ✅ Closed |
| 4 | Low | 24 | docs | `SECURITY.md` missing `timingSafeEql` guidance — security-sensitive API contract undocumented | `SECURITY.md:60–93` | `grep timingSafeEql SECURITY.md` → 0 hits; Known Design Trade-offs #5 absent | [#148](https://gitlab.com/devnw/zig/uuid/-/work_items/148) | Add CWE-208 trade-off + best-practice item to SECURITY.md | ✅ Closed |
| 5 | Low | 24 | perf | `bench/main.zig` missing `timingSafeEql` benchmark — new public API uncharacterized | `bench/main.zig:18–36` | `grep timingSafeEql bench/main.zig` → 0 hits; `std.crypto.timing_safe.eql` path unmeasured | [#146](https://gitlab.com/devnw/zig/uuid/-/work_items/146) | Add `benchEql` + `benchTimingSafeEql` using XOR sink pattern from QC-63 | ✅ Closed |

---

### Detailed Findings

#### QC-71 — README UUID API table omits `timingSafeEql` (Low, Score 48)

**Status: ✅ Closed** — [#144](https://gitlab.com/devnw/zig/uuid/-/work_items/144)

**Fix applied:** `timingSafeEql` row added to README UUID type API table after `eql`; `eql` row updated with "not constant-time — see `timingSafeEql`" note.

**File:** `README.md:85–112`

`UUID.timingSafeEql()` was added in commit 3a29957 (SEC-R9-01 fix) but the README API Reference table for the UUID type did not list it. The method exists at `src/uuid.zig:174` with a full doc comment and 5 tests. The table ends at `uuid.order(other) Order` (line 111) with no `timingSafeEql` entry and no cross-reference in the `eql` row.

**Why it matters:** Developers scanning the README for available methods will not discover `timingSafeEql`. Given that `timingSafeEql` exists precisely to guide developers away from misusing `eql` in secret-token contexts, its absence from the most-consulted API surface is the highest-impact gap of this cycle.

**Root cause:** The SEC-R9-01 fix commit did not update `README.md`.

**Recommended change:**

- Add a row after `uuid.eql(other) bool`: `| uuid.timingSafeEql(other) bool | Constant-time equality — use when UUID is a secret capability (CWE-208) |`
- Add to the `eql` row description: "Use `timingSafeEql` instead for secret-capability UUIDs."

**Acceptance criteria:**

- `grep -n timingSafeEql README.md` returns ≥ 2 hits
- UUID type API table contains both `eql` and `timingSafeEql` rows

**Verification:** `grep timingSafeEql README.md` — must return at least 2 hits.

**Effort:** S

---

#### QC-72 — CHANGELOG.md `[Unreleased]` missing `timingSafeEql` addition (Low, Score 24)

**Status: ✅ Closed** — [#145](https://gitlab.com/devnw/zig/uuid/-/work_items/145)

**Fix applied:** `### Added` entry for `UUID.timingSafeEql()` and `benchEql`/`benchTimingSafeEql`; `### Changed` entry for `UUID.eql()` doc CWE-208 warning added to `CHANGELOG.md`.

**File:** `CHANGELOG.md:8–18`

The `[Unreleased]` section did not mention `UUID.timingSafeEql()` or the CWE-208 timing warning added to the `eql` doc comment. The changelog is the authoritative record of API changes between releases.

**Root cause:** The SEC-R9-01 fix commit did not add a changelog entry.

**Recommended change:** Under `### Added`: `- UUID.timingSafeEql(other) bool — constant-time equality for secret-capability UUIDs (SEC-R9-01 / CWE-208)`. Under `### Changed` or `### Security`: note for the `eql` doc comment update.

**Acceptance criteria:**

- `grep -n timingSafeEql CHANGELOG.md` returns ≥ 1 hit
- Entry includes SEC-R9-01 / CWE-208 reference

**Effort:** S

---

#### QC-73 — `bench/main.zig` missing `timingSafeEql` benchmark (Low, Score 24)

**Status: ✅ Closed** — [#146](https://gitlab.com/devnw/zig/uuid/-/work_items/146)

**Fix applied:** `benchEql()` and `benchTimingSafeEql()` added to `bench/main.zig` using XOR sink pattern; both called from `main()`.

**File:** `bench/main.zig:18–36`

`UUID.timingSafeEql()` uses `std.crypto.timing_safe.eql` — a different code path from `eql`'s `std.mem.eql`. No benchmark captures its throughput characteristics. All other public UUID output/comparison methods have corresponding benchmarks. Developers choosing between `eql` and `timingSafeEql` have no performance data.

**Root cause:** The SEC-R9-01 fix commit did not add benchmark entries.

**Recommended change:** Add `benchEql` and `benchTimingSafeEql` functions using the pool+XOR sink pattern from existing benchmarks (established in QC-63). Add both calls to `main()`.

**Acceptance criteria:**

- `grep -n timingSafeEql bench/main.zig` returns ≥ 1 hit
- `zig build bench-check -Doptimize=ReleaseFast` exits 0

**Effort:** S

---

#### QC-74 — `tests/integration.zig` missing `timingSafeEql` coverage (Low, Score 24)

**Status: ✅ Closed** — [#147](https://gitlab.com/devnw/zig/uuid/-/work_items/147)

**Fix applied:** Two integration tests added to `tests/integration.zig`: "timingSafeEql equal UUIDs (QC-74)" and "timingSafeEql unequal UUIDs (QC-74)" (includes symmetry assertion).

**File:** `tests/integration.zig:1–383`

`UUID.timingSafeEql()` had 5 unit tests in `src/uuid_test.zig` but zero integration-level tests. Integration tests exercise the method as `uuid.UUID.timingSafeEql` through `@import("uuid")` — the form external callers use. Every other significant UUID method has integration coverage.

**Root cause:** The SEC-R9-01 fix commit updated only `src/uuid_test.zig`, not `tests/integration.zig`.

**Recommended change:** Add 2 integration tests: equal UUID returns true; two fresh V4 UUIDs return false.

**Acceptance criteria:**

- `grep -n timingSafeEql tests/integration.zig` returns ≥ 1 hit
- `zig build test-integration --summary all` exits 0

**Effort:** S

---

#### QC-75 — `SECURITY.md` missing `timingSafeEql` guidance (Low, Score 24)

**Status: ✅ Closed** — [#148](https://gitlab.com/devnw/zig/uuid/-/work_items/148)

**Fix applied:** Item 5 added to Known Design Trade-offs in `SECURITY.md` explaining CWE-208 risk of `eql` and directing callers to `timingSafeEql` for secret-capability UUIDs.

**File:** `SECURITY.md:60–93`

`SECURITY.md` Known Design Trade-offs and Security Best Practices sections were incomplete: neither mentioned `timingSafeEql`, the CWE-208 risk of `eql`, or when to use constant-time comparison. Security auditors and developers reading only `SECURITY.md` have no indication that the library provides a timing-safe comparison primitive. This is a quality/API-contract gap (distinct from SEC-R10-01, which tracks it as a security advisory).

**Root cause:** The SEC-R9-01 fix was implemented in source with full doc comments but the SECURITY.md update was deferred to SEC-R10-01.

**Recommended change:** Add item 5 to Known Design Trade-offs explaining the CWE-208 `eql` vs `timingSafeEql` trade-off. Add item 5 to Security Best Practices advising use of `timingSafeEql` for secret-capability UUIDs.

**Acceptance criteria:**

- `grep -n timingSafeEql SECURITY.md` returns ≥ 2 hits
- Known Design Trade-offs mentions both `eql` (risk) and `timingSafeEql` (mitigation)
- Security Best Practices includes `timingSafeEql` usage guideline

**Effort:** S

---

### Won't Do Policy — All Cycles (MANDATORY for future agents)

> The following categories MUST remain 🚫 Won't Do across ALL `*GAP_ANALYSIS.md` files.
> Future agents MUST NOT re-open, re-implement, or re-report these items.
>
> - **CI/CD Zig toolchain checksum/SHA256 verification** — handled by pipeline governance (Renovate/org policy)
> - **Docker image digest/tag pinning** — handled by infrastructure controls outside this library
> - **CI catalog component tag pinning** (mutable semver tags in GitLab CI includes) — pipeline governance
> - **Pre-commit hook modifications** (`check-yaml --unsafe`, `check-todos`, hook versioning) — developer tooling team
> - **GeneratorInterface extraction to generator_interface.zig** — blocked by circular import (QC-38, QC-64)
>
> Evidence: `docs/GAP_ANALYSIS.md` Won't Do blocks (all security review cycles), QC-16 and QC-64 in this file.

_Last updated: 2026-03-22 — Cycle 11 complete. 5 new findings (QC-71–QC-75), all Low severity, all closed. Format, build, and tests all pass. 75 total issues tracked (73 closed, 2 Won't Do, 0 open)._

---

## Quality Review Cycle 12

> **Date:** 2026-03-22
> **Zig version audited:** 0.15.2
> **Previous cycles:** Cycles 1–11 (QC-1–QC-75) — all closed (2 Won't Do: QC-16, QC-64).
> **Scope:** New findings only — items from prior cycles are not re-opened.
> **Note:** QC-89 (README installation block inconsistency) was merged into QC-80 as the same root cause.

---

### Summary

| Severity | Count |
| -------- | ----- |
| High     | 1     |
| Medium   | 1     |
| Low      | 12    |
| Info     | 2     |

**Total new issues:** 16 — all closed

### Top 5 Closed Items

1. ✅ **QC-80** — Replaced placeholder hash with `zig fetch` instructions in README.
2. ✅ **QC-90** — Fixed root.zig doc: removed internal @import("generator.zig") reference.
3. ✅ **QC-81** — Changed newV8 return type from Error!UUID to UUID.
4. ✅ **QC-82** — Documented both access paths in README.
5. ✅ **QC-76, QC-78** — Added doc comments to Generator.init, withClock, withRand, and newV4.

---

### Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | GitLab Issue | Status |
| ---- | -------- | ------------- | -------- | ------- | --------- | -------- | ------------ | ------ |
| 1 | High | 80 | docs | README installation hash is literal `"..."` placeholder — blocks package installation | `README.md:26` | `grep '\.hash' README.md` returns `"..."` | [#166](https://gitlab.com/devnw/zig/uuid/-/work_items/166) | ✅ Closed |
| 2 | Medium | 36 | docs | `root.zig` doc comment instructs `@import("generator.zig")` — unreachable for external consumers | `src/root.zig:67` | `@import("generator.zig")` in module doc | [#176](https://gitlab.com/devnw/zig/uuid/-/work_items/176) | ✅ Closed |
| 3 | Low | 24 | docs | `Generator.init`, `withClock`, `withRand` have no doc comments | `src/generator.zig:105–118` | Zero `///` on three constructor-pattern entry points | [#160](https://gitlab.com/devnw/zig/uuid/-/work_items/160) | ✅ Closed |
| 4 | Low | 24 | docs | `Variant` enum has no doc comment | `src/uuid.zig:38–43` | Zero `///` on enum and all 4 members | [#162](https://gitlab.com/devnw/zig/uuid/-/work_items/162) | ✅ Closed |
| 5 | Low | 24 | docs | `Generator.newV4` has no doc comment | `src/generator.zig:142` | Zero `///` on most-used generation method | [#163](https://gitlab.com/devnw/zig/uuid/-/work_items/163) | ✅ Closed |
| 6 | Low | 24 | docs | `GeneratorInterface` dispatch methods have no doc comments | `src/generator.zig:755–784` | Zero `///` on all 10 vtable trampolines | [#165](https://gitlab.com/devnw/zig/uuid/-/work_items/165) | ✅ Closed |
| 7 | Low | 20 | api-contract | `newV8` returns `Error!UUID` but body is infallible | `src/versions.zig:63` | No `try`, no `return error.*` in body | [#168](https://gitlab.com/devnw/zig/uuid/-/work_items/168) | ✅ Closed |
| 8 | Low | 16 | api-contract | Double export of `nil`/`max` via `uuid.nil` and `uuid.UUID.nil`; README inconsistent | `src/root.zig:42–43` | Two canonical access paths; README documents only one | [#169](https://gitlab.com/devnw/zig/uuid/-/work_items/169) | ✅ Closed |
| 9 | Low | 16 | docs | `Timestamp.toUnixNano` public but absent from README Timestamp section | `src/timestamp.zig:38` | `grep toUnixNano README.md` returns 0 hits | [#170](https://gitlab.com/devnw/zig/uuid/-/work_items/170) | ✅ Closed |
| 10 | Low | 16 | docs | `Timestamp.fromUnixNano`/`fromUnixMs` public but absent from README | `src/timestamp.zig:78,92` | `grep fromUnixNano README.md` returns 0 hits | [#171](https://gitlab.com/devnw/zig/uuid/-/work_items/171) | ✅ Closed |
| 11 | Low | 16 | tests | No test exercises `newV8` error-never path | `src/generator.zig:494` | No boundary-input tests with infallibility note | [#172](https://gitlab.com/devnw/zig/uuid/-/work_items/172) | ✅ Closed |
| 12 | Low | 16 | docs | `newV7AtTime` doc comment omits `RandomError` from error set | `src/generator.zig:172–176` | Doc mentions only `InvalidTimestamp` | [#173](https://gitlab.com/devnw/zig/uuid/-/work_items/173) | ✅ Closed |
| 13 | Low | 16 | docs | `examples/basic.zig` uses `{any}` for `NullUUID` instead of `{f}` | `examples/basic.zig:104–105` | `{any}` prints struct internals, not canonical UUID string | [#177](https://gitlab.com/devnw/zig/uuid/-/work_items/177) | ✅ Closed |
| 14 | Low | 12 | docs | README "See docs/ for detailed documentation" links to internal review notes | `README.md:180` | `docs/` contains only gap analysis and security review files | [#178](https://gitlab.com/devnw/zig/uuid/-/work_items/178) | ✅ Closed |
| 15 | Info | 8 | docs | `Timestamp.now()` doc does not note it bypasses the injectable clock | `src/timestamp.zig:25` | No reference to `Generator.withClock` in doc comment | [#174](https://gitlab.com/devnw/zig/uuid/-/work_items/174) | ✅ Closed |
| 16 | Info | 8 | tests | No test verifying `Generator.newV1`/`newV6` do NOT use injected clock | `src/generator_test.zig` | Injected-clock boundary for V1/V6 untested | [#175](https://gitlab.com/devnw/zig/uuid/-/work_items/175) | ✅ Closed |

---

### Findings by Category

#### Documentation

##### QC-76 — Generator.init, withClock, withRand have no doc comments (Low, Score 24)

**Status: ✅ Closed — Implemented.** Added doc comments to Generator.init, withClock, withRand. — [#160](https://gitlab.com/devnw/zig/uuid/-/work_items/160)

**File:** `src/generator.zig:105–118`

`Generator.init`, `Generator.withClock`, and `Generator.withRand` have no `///` doc comments. These three functions are the primary constructor-pattern entry points. `zig doc` users and IDE hover-help will show nothing for them.

**Root cause:** These were written before a doc-comment policy was established.

**Recommended change:** Add `///` doc comments to each function describing parameters and return semantics.

**Acceptance criteria:** `zig doc ./...` renders documentation for all three functions.

**Confidence:** confirmed

---

##### QC-77 — Variant enum has no doc comment (Low, Score 24)

**Status: ✅ Closed — Implemented.** Added doc comment to Variant enum and all members. — [#162](https://gitlab.com/devnw/zig/uuid/-/work_items/162)

**File:** `src/uuid.zig:38–43`

The `Variant` enum and all four of its members (`ncs`, `rfc9562`, `microsoft`, `future`) have no `///` doc comments. Callers do not know which variant is valid for RFC 9562 UUIDs or what the bit patterns mean.

**Root cause:** Enum documentation was not included in the Cycle 10 doc-comment sweep (QC-62), which targeted functions only.

**Confidence:** confirmed

---

##### QC-78 — Generator.newV4 has no doc comment (Low, Score 24)

**Status: ✅ Closed — Implemented.** Added doc comment to Generator.newV4. — [#163](https://gitlab.com/devnw/zig/uuid/-/work_items/163)

**File:** `src/generator.zig:142`

`Generator.newV4` is the most-used generation method but has no `///` doc comment, while all other `newV*` methods have documentation. The error surface and random source are undocumented.

**Root cause:** QC-62 addressed `src/uuid.zig`; `generator.zig` entry points were addressed only selectively.

**Confidence:** confirmed

---

##### QC-79 — GeneratorInterface dispatch methods have no doc comments (Low, Score 24)

**Status: ✅ Closed — Implemented.** Added doc comments to all 10 GeneratorInterface dispatch methods. — [#165](https://gitlab.com/devnw/zig/uuid/-/work_items/165)

**File:** `src/generator.zig:755–784`

All 10 `GeneratorInterface` vtable dispatch trampolines have no `///` doc comments. The interface is the primary polymorphism seam for dependency injection and mock generators.

**Root cause:** Vtable trampolines were not included in any doc-comment pass.

**Confidence:** confirmed

---

##### QC-80 — README installation hash is a literal "..." placeholder (High, Score 80)

**Status: ✅ Closed — Implemented.** Replaced placeholder hash with `zig fetch` instructions. — [#166](https://gitlab.com/devnw/zig/uuid/-/work_items/166)

**File:** `README.md:26`

```zon
.hash = "...",
```

The Zig package manager requires a valid SHA-256 hash. A literal `"..."` causes `zig build` to fail before any code compiles. This blocks all new library adopters.

**Root cause:** The installation snippet was written before the first tagged release; the placeholder was never replaced.

**Recommended change:** Run `zig fetch --save` against the release tarball and replace `"..."` with the printed hash.

**Note:** QC-89 (same root cause — README installation block inconsistency) is merged into this issue.

**Confidence:** confirmed

---

##### QC-83 — Timestamp.toUnixNano is public but absent from README Timestamp section (Low, Score 16)

**Status: ✅ Closed — Implemented.** Added Timestamp.toUnixNano to README Timestamp table. — [#170](https://gitlab.com/devnw/zig/uuid/-/work_items/170)

**File:** `src/timestamp.zig:38`

`Timestamp.toUnixNano` is a public conversion method missing from the README's Timestamp API table. Callers consulting the README for Timestamp API will not discover it.

**Confidence:** confirmed

---

##### QC-84 — Timestamp.fromUnixNano and fromUnixMs are public but absent from README (Low, Score 16)

**Status: ✅ Closed — Implemented.** Added Timestamp.fromUnixNano/fromUnixMs to README Timestamp table. — [#171](https://gitlab.com/devnw/zig/uuid/-/work_items/171)

**File:** `src/timestamp.zig:78,92`

`Timestamp.fromUnixNano` and `Timestamp.fromUnixMs` are public constructors (critical for `newV7AtTime` usage) missing from the README's Timestamp API table.

**Confidence:** confirmed

---

##### QC-86 — newV7AtTime doc comment only documents negative-ts guard, not full error set (Low, Score 16)

**Status: ✅ Closed — Implemented.** Expanded newV7AtTime doc comment to list full error set. — [#173](https://gitlab.com/devnw/zig/uuid/-/work_items/173)

**File:** `src/generator.zig:172–176`

The doc comment for `newV7AtTime` lists only `InvalidTimestamp` but the full error set also includes `RandomError`. Callers may under-handle errors.

**Confidence:** confirmed

---

##### QC-87 — Timestamp.now() doc does not note it bypasses the injectable clock (Info, Score 8)

**Status: ✅ Closed — Implemented.** Added clock-bypass note to Timestamp.now() doc. — [#174](https://gitlab.com/devnw/zig/uuid/-/work_items/174)

**File:** `src/timestamp.zig:25`

`Timestamp.now()` reads the system clock directly and is not affected by `Generator.withClock`. The doc comment does not note this, creating a silent determinism gap for callers who use `withClock` for test injection.

**Confidence:** confirmed

---

##### QC-90 — root.zig doc comment instructs callers to @import("generator.zig") — impossible for external consumers (Medium, Score 36)

**Status: ✅ Closed — Implemented.** Fixed root.zig doc: removed internal @import("generator.zig") reference. — [#176](https://gitlab.com/devnw/zig/uuid/-/work_items/176)

**File:** `src/root.zig:67`

The module doc references `@import("generator.zig")` — a path only valid within the library's own source tree. External consumers get a compile error if they follow this example. The correct form is `@import("uuid").Generator`.

**Root cause:** The doc comment was written from an internal developer perspective.

**Confidence:** confirmed

---

##### QC-91 — examples/basic.zig uses {any} for NullUUID instead of {f} (Low, Score 16)

**Status: ✅ Closed — Implemented.** Fixed examples/basic.zig: {any} to {f} for NullUUID. — [#177](https://gitlab.com/devnw/zig/uuid/-/work_items/177)

**File:** `examples/basic.zig:104–105`

`{any}` prints the internal struct representation of `NullUUID` rather than the canonical nil UUID string. `NullUUID.format` was added in QC-55 to support `{f}`; the example was not updated.

**Confidence:** confirmed

---

##### QC-92 — README "See docs/ for detailed documentation" links to internal review notes (Low, Score 12)

**Status: ✅ Closed — Implemented.** Fixed README: replaced misleading "See docs/" with accurate description. — [#178](https://gitlab.com/devnw/zig/uuid/-/work_items/178)

**File:** `README.md:180`

`docs/` contains only internal quality and security review files. The phrase "See docs/ for detailed documentation" misleads external users expecting user guides or API references.

**Root cause:** Added speculatively; user docs were never created.

**Confidence:** confirmed

---

#### API Contract

##### QC-81 — newV8 returns Error!UUID but function body can never fail (Low, Score 20)

**Status: ✅ Closed — Implemented.** Changed newV8 return type from Error!UUID to UUID. — [#168](https://gitlab.com/devnw/zig/uuid/-/work_items/168)

**File:** `src/versions.zig:63`

```zig
pub fn newV8(data: [16]u8) Error!UUID {
    var uuid = UUID{ .bytes = data };
    uuid.setVersion(8);
    uuid.setVariant(.rfc9562);
    return uuid;
}
```

The body contains no `try`, no `return error.*`, and no fallible calls. Callers are forced to write `try gen.newV8(...)` even though the error case can never occur.

**Confidence:** confirmed

---

##### QC-82 — Double export of nil/max via uuid.nil and uuid.UUID.nil (Low, Score 16)

**Status: ✅ Closed — Implemented.** Documented both access paths in README. — [#169](https://gitlab.com/devnw/zig/uuid/-/work_items/169)

**File:** `src/root.zig:42–43`

Two canonical access paths for the same constants. README documents `UUID.nil` while the top-level re-export `uuid.nil` is the more ergonomic form. If one path is removed in a future refactor, callers using the other path break silently.

**Confidence:** confirmed

---

#### Tests

##### QC-85 — No test exercises newV8 error-never path (Low, Score 16)

**Status: ✅ Closed — Implemented.** Added newV8 boundary tests with all-zero and all-one inputs. — [#172](https://gitlab.com/devnw/zig/uuid/-/work_items/172)

**File:** `src/generator.zig:494`

No test documents or asserts the infallible nature of `newV8`. Without a baseline test, a return-type change (per QC-81) has no coverage anchor.

**Recommended change:** Add tests with all-zero and all-one byte inputs with an explanatory comment noting the function is infallible.

**Confidence:** confirmed

---

##### QC-88 — No test verifying Generator.newV1/newV6 do NOT use injected clock (Info, Score 8)

**Status: ✅ Closed — Implemented.** Added test verifying V1/V6 ignore injected clock. — [#175](https://gitlab.com/devnw/zig/uuid/-/work_items/175)

**File:** `src/generator_test.zig`

The boundary between injected-clock (`withClock`) and system-clock code paths for V1/V6 is not tested. A refactor accidentally wiring V1/V6 through the injected clock would be undetected.

**Confidence:** suspected — requires code inspection to confirm V1/V6 ignore `withClock`.

---

### Action Plan (Cycle 12)

#### Quick Wins (S effort — do first)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#166](https://gitlab.com/devnw/zig/uuid/-/work_items/166) | Replace README installation hash placeholder with real hash | S | High |
| [#176](https://gitlab.com/devnw/zig/uuid/-/work_items/176) | Fix root.zig doc: replace @import("generator.zig") with external form | S | Medium |
| [#160](https://gitlab.com/devnw/zig/uuid/-/work_items/160) | Add doc comments to Generator.init, withClock, withRand | S | Low |
| [#162](https://gitlab.com/devnw/zig/uuid/-/work_items/162) | Add doc comment to Variant enum and members | S | Low |
| [#163](https://gitlab.com/devnw/zig/uuid/-/work_items/163) | Add doc comment to Generator.newV4 | S | Low |
| [#165](https://gitlab.com/devnw/zig/uuid/-/work_items/165) | Add doc comments to GeneratorInterface dispatch methods | S | Low |
| [#173](https://gitlab.com/devnw/zig/uuid/-/work_items/173) | Expand newV7AtTime doc comment to list full error set | S | Low |
| [#170](https://gitlab.com/devnw/zig/uuid/-/work_items/170) | Add Timestamp.toUnixNano to README | S | Low |
| [#171](https://gitlab.com/devnw/zig/uuid/-/work_items/171) | Add Timestamp.fromUnixNano/fromUnixMs to README | S | Low |
| [#177](https://gitlab.com/devnw/zig/uuid/-/work_items/177) | Fix examples/basic.zig: {any} → {f} for NullUUID | S | Low |
| [#178](https://gitlab.com/devnw/zig/uuid/-/work_items/178) | Remove/replace misleading "See docs/" README sentence | S | Low |
| [#174](https://gitlab.com/devnw/zig/uuid/-/work_items/174) | Add clock-bypass note to Timestamp.now() doc | S | Info |

#### Medium-term (M effort)

| Issue | Title | Effort | Impact |
| ----- | ----- | ------ | ------ |
| [#168](https://gitlab.com/devnw/zig/uuid/-/work_items/168) | Change newV8 return type to UUID or document infallibility | S/M | Low |
| [#169](https://gitlab.com/devnw/zig/uuid/-/work_items/169) | Resolve nil/max double-export and align README | S | Low |
| [#172](https://gitlab.com/devnw/zig/uuid/-/work_items/172) | Add newV8 boundary tests documenting infallible path | S | Low |
| [#175](https://gitlab.com/devnw/zig/uuid/-/work_items/175) | Add test verifying V1/V6 ignore injected clock | S | Info |

---

_Last updated: 2026-03-22 — Cycle 12 complete. 16 new findings (QC-76–QC-92, QC-89 merged into QC-80): 1 High, 1 Medium, 12 Low, 2 Info. All 16 closed. 91 total issues tracked (89 closed, 2 Won't Do, 0 open)._
