# AppSec Delta Review — devnw/zig/uuid (iteration 2)

**Scope:** `git diff 9bd6057..fcace35` (19 commits, 22 files, +1930/-102) — the 2026-06-11 audit-closure cycle, reviewed as a delta against the same-day full review (`APPSEC_REVIEW_2026-06-11.md`).
**Framework:** OWASP Top 10:2025 + CIS Controls v8.1.2 (`security:appsec-review-framework`).
**Date:** 2026-06-11
**Method:** Every code/CI/script/config hunk in the delta reviewed; the four security-critical function bodies byte-compared between baseline and HEAD; the Python hash-anchor and warn-only substring semantics re-derived empirically.

## Verdicts

**Q1 — New security issues introduced by the delta? NO.**

- `src/generator.zig`: only `.real`→`.awake` on two non-security V7 spin-sleep sites (`generator.zig:885`, `:1032`) plus doc comments. Monotonic clock for an interval timer is a robustness improvement (A10), not a regression.
- `src/root.zig:130`: version `0.1.0`→`0.1.1` — resolves prior finding NEW-03.
- `.well-known/security.txt:11`: second `Contact:` line — RFC 9116 permits multiple in preference order; improves disclosure reachability.
- `build.zig.zon:17`: `.paths` `bench`→`benchmarks` — packaging-integrity improvement (A08).
- New CI surfaces confirmed safe: `version-consistency` job greps two tracked repo-controlled files into quoted shell vars (no MR-title/branch/CI-variable interpolation; no injection surface). `benchmarks/compare.zig` `--warn-only` parsing is bound-checked and the value is used only as a `std.mem.indexOf` needle against a filename basename — no path use, no format-string use.

**Q2 — SEC-P5-01 fully remediated? YES.**

- `SAFE_HASH_RE = ^[A-Za-z0-9._-]{8,256}\Z` (`detect_diamond_deps.py:93`) applied at `_parse_dep_entries` (`:168`) before any path use; `../../etc/passwd` rejected; the `\Z` anchor rejects trailing-newline payloads that `$` would have accepted (closed in `5c2a7ea`).
- Symlink rejection at both cache candidates (`:189`, `:192`) — symlinked `build.zig.zon` returns `None`.
- `deque`/`popleft()` is PERF-60 only; no security effect.

**Q3 — Prior invariants intact? YES — byte-identical.**
SHA-256 comparison of function bodies between `9bd6057` and `fcace35`: `enforceStateMacPolicy` (SEC-P4-01), `verifyStateMacIfV3` (SEC-P3-04 timing-safe verify), `secureWipeMacKey` (CWE-316), `rotateStateMacKey` (CWE-316/320) — all IDENTICAL. New `versions.zig` tests pair every key assignment with `defer secureWipeMacKey()` (`:467`, `:489`), assert `state_mac_key == null` post-wipe (`:497`), never log key material, and write only to `defer tmp.cleanup()` temp dirs — they exercise the wipe invariant rather than weakening it.

**Q4 — SEC-P4-01 downgrade test still faithful after guard removal? YES.**
The removed comptime guard was dead code. The test body (`tests/integration.zig:458-498`) is unchanged: saves a real v3 keyed state, forges a v2 magic (`bytes[4] = 2`), truncates, and asserts `expectError(Error.StateVersionDowngrade, gen2.loadState(path))` under a keyed Generator. Removing the guard makes the test always execute — strictly stronger coverage.

## Findings Table (NEW only)

| ID | Severity | Confidence | Title | Location | OWASP 2025 | Status |
|----|----------|-----------|-------|----------|-----------|--------|
| — | — | — | **No new findings of any severity.** | — | — | — |

Prior-finding movement: NEW-03 resolved (`src/root.zig:130`); NEW-04 + SEC-P5-01 hash-format gap closed (`scripts/detect_diamond_deps.py`). Known/Won't-Do items (SEC-P4-14, O-2, H-1, NEW-01 Won't-Do, NEW-05 accepted) untouched.

## Posture statement

The appsec posture did not regress and modestly improved since the same-day full review. The delta touched zero security-critical code paths, the new CI/CLI surfaces are injection-safe, and `--warn-only state` is scoped to the fsync-bound state benchmark suite only — the contention-suite FAIL gate and `duplicate_uuids` correctness signal remain fully enforcing. No security gate was weakened. **No confirmed new vulnerabilities of any severity in the reviewed delta.**
