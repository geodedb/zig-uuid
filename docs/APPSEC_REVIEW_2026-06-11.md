# AppSec Code Review — devnw/zig/uuid (RFC-9562 UUID library)

**Reviewer:** Defensive AppSec code review (OWASP Top 10:2025 + CIS Controls v8.1.2)
**Date:** 2026-06-11
**Target:** `/home/benji/src/gl/gitlab.com/devnw/zig/uuid` @ HEAD `9bd6057` (branch `main`, clean tree)
**Framework:** `security:appsec-review-framework`

---

## 1. Scope and Assumptions

### Reviewed

- **Core source** (`src/`): `generator.zig` (2632 LOC — RNG, state persistence, HMAC state MAC, `rotateStateMacKey`, `reseed`, lock-free V7 CAS), `timestamp.zig`, `uuid.zig` + `uuid_json.zig` (untrusted-input parse paths), `versions.zig`, `namespace.zig`, `trusted_namespace_origins.zig`, `null_uuid.zig`, `root.zig`, `hwaddr/{hwaddr,linux,macos,windows}.zig`.
- **Supply chain / build / CI:** `build.zig`, `build.zig.zon`, `.gitlab-ci.yml`, `.pre-commit-config.yaml`, `scripts/detect_diamond_deps.py`, `.gitleaks.toml`, `Makefile`.
- **History delta:** the commits named in the contract — dependency-pin convergence (`9bd6057`, `d2f9c69`, `17ee3dc`, `df891b6`, `3d127c7`, `932eb7f`, `a91e1f8`), v0.1.1 bump (`17ee3dc`), pre-commit standardization (`4178e42`), and the diamond-dep detector (`d3241fc`).
- **Prior ledger:** `docs/SECURITY_REVIEW_NOTES.md` (Cycles 1–12 + Phase 3/4) and `docs/GAP_ANALYSIS.md` (through 2026-04-20 Phase 4 cycle 4) — used to anchor KNOWN vs NEW.

### Verification performed

- `zig build check` → **exit 0** (reviewed source compiles cleanly under Zig 0.16.0).
- Dependency-pin history reconstructed via `git log -p -- build.zig.zon`.
- `hwaddr/*` and CI/supply-chain files independently deep-reviewed by dedicated sub-agents with file:line evidence.

### Assumptions

- This is a **pure library** with **no auth model, no network listener, no service deployment** (OWASP A01/A07/SSRF/CORS/CSP are N/A by construction). The artifact is source tagged `v0.1.1`.
- Untrusted inputs are: UUID strings to `fromString`/JSON unmarshal; persisted state files at a caller-supplied **absolute** path (caller validates the path itself, per documented contract); OS-kernel data for MAC resolution (semi-trusted).
- The CSPRNG is `std.crypto.random` via `std.Io` (assumed correct per Zig stdlib).
- Findings already adjudicated **Won't-Do** in the ledger for valid governance reasons (Docker tag pinning, `check-yaml --unsafe`, Zig-download TOFU) are not re-litigated.

### Not reviewed / out of scope

- The external `json` dependency's internal source (only its pin integrity at this repo's boundary).
- Runtime fuzzing execution and full multi-mode test-suite runs (compile-check only here).
- The upstream `devnw/ci-catalog` component bodies (not accessible; see SEC-P4-14).

---

## 2. Executive Summary

- **No new Critical/High/Medium application-security vulnerabilities were found in the reviewed scope.** The crypto/RNG/state-persistence paths (the highest-risk surface) are exceptionally well-hardened, and **every prior security invariant the contract asked me to preserve is present and intact** in the current source (SEC-P3-04 HMAC state MAC, SEC-P4-01 no-downgrade policy, SEC-P4-02 key stack-spill fix, SEC-P4-10/A1 V7 atomic reseed + bounded retries, SEC-P4-13 timestamp cast assert; CWE-316/CWE-320 key hygiene via `secureWipeMacKey`/`rotateStateMacKey`).
- **The three known-open items re-validate as accurately scoped and unchanged:** **SEC-P4-14** (Medium-High, ci-catalog tag pins — still 8/8 tag-pinned at `.gitlab-ci.yml:11-24`, still Blocked on operator SHA map), **O-2** (Info, no post-fork reseed lint), **H-1** (Info, unpinned APT installs). Nothing regressed them.
- **One NEW Low finding** in the in-scope pre-commit standardization commit (`4178e42`): all 6 third-party pre-commit hook repos are pinned to **mutable Git tags rather than commit SHAs** (A03 / CWE-1357), and `pre-commit.ci` auto-fix is enabled — a developer-side analogue of SEC-P4-14.
- **Three NEW Info findings**, all introduced by the in-scope dependency/version churn: a transient **mutable git-tag dependency pin** (`#v0.1.4`) that existed mid-convergence with an observable **content-hash change** for the same tag (HEAD is now correctly SHA+hash pinned), a **version-string drift** (`root.zig` reports `0.1.0` while the package is `0.1.1`), and a **symlink-following** read in the new `detect_diamond_deps.py` hook (developer-local, low impact).
- **Supply chain at HEAD is verifiable:** the single `json` dependency is pinned by immutable 40-char commit SHA **and** Zig content hash (`build.zig.zon:8-9`); `.gitleaks.toml` is not weakened; no CI variable injection (`ZIG_VERSION` is passed to Python via env var, not interpolated into source) and the Zig tarball is SHA-256 verified in-repo before extraction.
- **Overall confidence: High** for the core library; **Medium** for CI/supply chain (the ci-catalog component bodies remain unauditable from here — the SEC-P4-14 blocker).

---

## 3. Findings Table

| ID | Severity | Confidence | Title | Location | OWASP 2025 | NEW/KNOWN | Status |
|----|----------|-----------|-------|----------|-----------|-----------|--------|
| NEW-01 | Low | High | Pre-commit hooks pinned to mutable tags, not commit SHAs (auto-fix enabled) | `.pre-commit-config.yaml:16,61,71,83,93,103,184` | A03 Supply Chain | NEW | Open |
| NEW-02 | Info | High | Transient mutable git-tag dependency pin + content-hash drift during convergence (HEAD now SHA-pinned) | `build.zig.zon` history (`17ee3dc`→`9bd6057`) | A03 Supply Chain / A08 Integrity | NEW | Resolved-at-HEAD |
| NEW-03 | Info | High | Version string drift: `root.zig` reports `0.1.0`, package is `0.1.1` | `src/root.zig:130` vs `build.zig.zon:3` | A08 Integrity | NEW | Open |
| NEW-04 | Info | Medium | `detect_diamond_deps.py` follows symlinks when reading cache `build.zig.zon` files | `scripts/detect_diamond_deps.py` (`_zon_path_for_hash` / `read_text`) | A08 Integrity | NEW | Open |
| NEW-05 | Info | Low | Unbounded kernel linked-list traversal in MAC enumeration (Windows `.Next`, macOS `ifa_next`) | `src/hwaddr/windows.zig:84-98`, `src/hwaddr/macos.zig:62` | A10 Exceptional Conditions | NEW | Open (within threat model) |
| SEC-P4-14 | Medium-High | Confirmed | CI catalog components pinned by moving tag `@v1.7.1` (8 includes) | `.gitlab-ci.yml:11-24` | A03 Supply Chain | KNOWN | Open / Blocked-external |
| O-2 | Info | Suspected | No runtime post-`fork(2)` `reseed()` lint/assertion | `src/generator.zig:544-586` | A06 Insecure Design | KNOWN | Open |
| H-1 | Info | Suspected | Unpinned APT installs in CI (`curl`/`xz-utils`/`python3`/`util-linux`/`procps`) | `.gitlab-ci.yml:40,276,365` | A03 Supply Chain | KNOWN | Open (folded into SEC-P4-14) |

CWE mappings: NEW-01 → CWE-1357/CWE-494; NEW-02 → CWE-1357/CWE-494; NEW-03 → CWE-1059 (informational integrity); NEW-04 → CWE-59 (link following); NEW-05 → CWE-835/CWE-125 (theoretical, kernel-trust-bounded). SEC-P4-14 → CWE-494/CWE-1357; H-1 → CWE-829; O-2 → CWE-665/CWE-331.

---

## 4. Finding Details

### NEW-01 (Low) — Pre-commit hooks pinned to mutable tags instead of commit SHAs

**Evidence.** All six third-party hook repositories in `.pre-commit-config.yaml` are pinned by version tag, not a 40-char commit SHA:

- `:16` `pre-commit/pre-commit-hooks` `rev: v6.0.0`
- `:61` `shellcheck-py` `rev: v0.11.0.1`
- `:71` `astral-sh/ruff-pre-commit` `rev: v0.14.14`
- `:83` `markdownlint-cli` `rev: v0.43.0`
- `:93` `macisamuele/language-formatters-pre-commit-hooks` `rev: v2.16.0`
- `:103` `commitizen-tools/commitizen` `rev: v4.12.1`

Blast radius is widened by `:184` `ci.autofix_prs: true` — `pre-commit.ci` runs these hooks and can auto-commit fixes to merge requests. This file was rewritten by the in-scope commit `4178e42` ("standardize .pre-commit-config.yaml from geode upstream").

**Attack scenario (non-destructive).** A Git tag on GitHub is a mutable ref. If any hook publisher's account or repo is compromised, an attacker re-points (e.g.) `v0.14.14` to a malicious commit. The next `pre-commit autoupdate`-free run — or the `pre-commit.ci` runner — fetches and executes the new hook code in the developer's checkout / CI context, with the ability to auto-commit. This is the same class as SEC-P4-14 but on the developer-tooling tier.

**Impact.** Arbitrary code execution in the pre-commit/`pre-commit.ci` context; potential tampering with commits via autofix. Not reachable by an external consumer of the library; requires upstream-hook compromise.

**Root cause.** Mutable-ref pinning for third-party executable components (CIS Controls v8.1.2: trusted/version-pinned third-party components, SBOM hygiene).

**Remediation.** Pin each `rev:` to the tag's full commit SHA, keeping the human-readable tag in a trailing comment:

```yaml
- repo: https://github.com/astral-sh/ruff-pre-commit
  rev: 9f8b2c...<40 hex>   # v0.14.14
```

Run `pre-commit autoupdate --freeze` to do this for every hook automatically. Note this is consistent with the project's own SEC-P4-14 remediation philosophy; if the org has decided pre-commit pinning is "developer tooling team" governance (as ledgered for `check-yaml --unsafe`), record this finding as **Won't-Do** with that same rationale rather than leaving it implicitly open.

**Regression test / verification.** Add a pre-commit hook (or CI lint) that fails if any `rev:` in `.pre-commit-config.yaml` is not a 40-hex string. `grep -E "rev: v" .pre-commit-config.yaml` should return nothing after the fix.

**References.** OWASP A03:2025; CWE-1357, CWE-494; CIS Controls v8.1.2 (third-party component inventory, trusted/supported dependencies).

---

### NEW-02 (Info) — Transient mutable git-tag dependency pin and content-hash drift during convergence

**Evidence.** Reconstructed from `git log -p -- build.zig.zon`:

- Commit `17ee3dc` (the v0.1.1 bump) set the dependency URL to a **mutable tag ref**: `.url = "git+https://gitlab.com/devnw/zig/json.git#v0.1.4"` with hash `json-0.1.4-tOue4X2pCwC2H64hrrIwVKj76kiuJFGAzVqsWjROghkg`.
- Commit `d2f9c69` re-pinned to a commit SHA `#96592a8a...` with a **different** hash `...tOue4Z-pCwC-u6tE4-gUm4rocTBoF41SiKsSHNiKPrXr`.
- Commit `9bd6057` (HEAD) re-pinned again to `#284b1390d3f...` with hash `...tOue4cGpCwBArfMl05wHmwv39pKM9-tjODxrMFm_sIk3` (`build.zig.zon:8-9`).

Across these, the same nominal version "0.1.4" carried **three distinct content hashes** — direct evidence that the upstream `v0.1.4` tag (and intermediate SHAs) pointed at different trees during the convergence.

**Impact.** None at HEAD: the current `build.zig.zon` pins an **immutable 40-char commit SHA plus a Zig content hash**, so a downstream build verifies the exact tree. The Info concern is process hygiene — a mutable `#v0.1.4` pin shipped in the v0.1.1 release commit before being corrected, and the changing hash for one tag confirms why tag pinning is unsafe.

**Root cause.** Mid-convergence churn temporarily traded an immutable pin for a tag ref (CWE-1357 reliance on insufficiently trustworthy component pin), corrected in later commits.

**Remediation.** None required at HEAD. Process control: ensure release-tag commits (the ones that get a `v*` tag) only ever contain commit-SHA + content-hash pins; add the diamond-dep / pin-style check to the release gate so a `#v<semver>`-style URL cannot be tagged. The `json` content hash should be re-confirmed stable on the next dependency bump.

**Verification.** `grep -nE '#v[0-9]' build.zig.zon` returns nothing at HEAD (confirmed). The pin is SHA-based with a content hash.

**References.** OWASP A03/A08:2025; CWE-1357, CWE-494; CIS Controls v8.1.2 (SBOM, trusted dependencies).

---

### NEW-03 (Info) — Version string drift between source and package manifest

**Evidence.** `src/root.zig:130` declares `pub const version = "0.1.0";` while `build.zig.zon:3` declares `.version = "0.1.1"`. The v0.1.1 bump commit `17ee3dc` updated the manifest but not the source constant. Not tracked in any existing GAP entry (grep of `docs/` found only CHANGELOG-related `0.1.0` references, not this constant).

**Impact.** A consumer that reads `uuid.version` for telemetry, compatibility gating, or "report your library version" diagnostics receives `0.1.0` for a `0.1.1` artifact. No memory-safety or confidentiality impact; this is a software-integrity/consistency defect with mild security relevance (misreported provenance during incident response or SBOM cross-checks).

**Root cause.** Two sources of truth for the version with no consistency check.

**Remediation.** Either update `src/root.zig:130` to `"0.1.1"` on each release, or (better) derive it at build time from `build.zig.zon` and inject via a build option so the two cannot drift. Add a CI assertion comparing `root.zig` `version` to the zon `version`.

**Verification.** After fix, `zig build` produces a module whose `version` equals the zon `.version`; a unit test `try std.testing.expectEqualStrings("0.1.1", uuid.version)` (or a build-time comparison) gates future drift.

**References.** OWASP A08:2025; CWE-1059; CIS Controls v8.1.2 (software inventory accuracy).

---

### NEW-04 (Info) — `detect_diamond_deps.py` follows symlinks when reading cache `build.zig.zon` files

**Evidence.** The new pre-commit hook (commit `d3241fc`) resolves candidate dependency files as `project_root / "zig-pkg" / pkg_hash / "build.zig.zon"` and `<zig_global_cache> / "p" / pkg_hash / "build.zig.zon"`, then reads them with `pathlib.Path.read_text()` after an `.exists()` check. `pkg_hash` originates from the parsed `.hash` field of `build.zig.zon`. The script never calls `is_symlink()`/`resolve()` and does not pass `follow_symlinks=False`, so a symlinked cache `build.zig.zon` would be followed and read. (Confirmed: no `subprocess`/`shell=True`/`eval`/`pickle`/unsafe-deserialization, no writes anywhere, BFS dedupes via `seen_hashes` so no infinite loop, and the `DEP_BLOCK_RE` regex is not catastrophic-backtracking.)

**Impact.** Very low. The script only runs on a developer's own checkout against their own Zig cache, reads files, and surfaces dependency tuples on stderr — there is no code execution and no exfiltration channel. A `pkg_hash` like `../../etc` cannot escape usefully because the candidate must already `.exists()` and only a `build.zig.zon`-shaped file is parsed. The symlink path is a defense-in-depth gap, not an exploitable vulnerability.

**Root cause.** Cache reads trust the on-disk path without confining to the cache root or rejecting links (CWE-59 link following).

**Remediation (optional hardening).** In `_zon_path_for_hash`, return `None` when `candidate.is_symlink()`, or `resolve()` the path and assert it stays within the intended cache root before `read_text`. Treat `pkg_hash` as opaque and validate it matches the expected Zig hash charset (`[A-Za-z0-9_-]`) before using it in a path join.

**Verification.** Unit test: a symlinked `build.zig.zon` in a temp cache dir is skipped (returns `None`) rather than read.

**References.** OWASP A08:2025; CWE-59; CIS Controls v8.1.2 (secure SDLC tooling).

---

### NEW-05 (Info) — Unbounded kernel linked-list traversal in MAC enumeration

**Evidence.** `src/hwaddr/windows.zig:84-98` follows kernel-supplied `Next` pointers from `GetAdaptersAddresses` with no iteration cap or `Length`-based bounding; `src/hwaddr/macos.zig:62` similarly walks the `getifaddrs(3)` `ifa_next` chain. A malicious/buggy kernel returning a cyclic or dangling `Next` would loop indefinitely or read freed memory.

**Impact.** Negligible under the stated semi-trusted-kernel threat model — the OS owns these buffers, and a hostile kernel can compromise the process by far simpler means. Flagged only for completeness/defense-in-depth. All per-node field reads are otherwise correctly bounds-checked (verified: `PhysicalAddressLength != 6` skip before reading `PhysicalAddress[0..6]`; macOS `sdl_len` guard before slicing `sdl_data`).

**Root cause.** Trust in kernel-returned linked-list termination (CWE-835 loop / CWE-125 read, both kernel-trust-bounded).

**Remediation (optional).** Add a sanity iteration cap (e.g., 4096 adapters) to both traversals so a pathological kernel response degrades to "no MAC found → random node ID fallback" instead of hanging.

**Verification.** Not practically testable without a kernel mock; document as accepted risk or add the cap with a unit test on a synthetic over-long chain (Linux ioctl path is already slot-capped at 128).

**References.** OWASP A10:2025; CWE-835/CWE-125; CIS Controls v8.1.2 (robust error handling).

---

### KNOWN — Re-validation (confirming scope/severity)

**SEC-P4-14 (Medium-High, CWE-494/CWE-1357) — Open / Blocked-external. Accurately scoped; unchanged.**
Confirmed exactly **8** `include:` ci-catalog components, all pinned by moving tag: `.gitlab-ci.yml:11` `security-sast@v1.7.1`, `:12` `security-dependency-scanning@v1.7.1`, `:13` `security-secrets@v1.7.1`, `:14` `security-gitleaks@v1.7.1`, `:17` `zig-format@v1.2.1`, `:20` `sbom-generate@v1.7.1`, `:21` `sbom-scan@v1.7.1`, `:24` `release-semantic@v1.7.1`. No new components added; none migrated to SHA pins. Still blocked on the operator-provided tag→SHA map for `gitlab.com/devnw/ci-catalog@v1.7.1`. The ledger's `🚧 Blocked` / `blocked-external-dependency` classification remains correct. **No regression.**

**O-2 (Info, CWE-665/CWE-331) — Open. Accurately scoped; unchanged.**
`reseed()` (`src/generator.zig:544-586`) correctly clears all CSPRNG-derived state including the V7 atomic word (SEC-P4-10 fix at `:583`), but the library still has **no runtime detection** of a caller who `fork(2)`s and mints UUIDs without calling `reseed()`. Zig 0.16 exposes no portable `pthread_atfork`; the contract remains doc-only. Downstream-correctness surface, not attacker-exploitable. **No regression.**

**H-1 (Info, CWE-829) — Open / folded into SEC-P4-14. Accurately scoped; unchanged.**
Unpinned APT installs confirmed at `.gitlab-ci.yml:40` (`curl xz-utils python3`), `:276` and `:365` (`util-linux procps`). Risk acceptance still holds: the Zig tarball is SHA-256 verified **in this repo's CI** before extraction (the `.install-zig` anchor fetches `index.json`, extracts the expected shasum, and runs `sha256sum --check --strict` prior to `tar`). The `util-linux`/`procps` installs add only `taskset`/`nproc` helpers. **No regression.** (Minor doc note for the ledger: the checksum verification lives in this repo's `.install-zig` anchor, not solely in a ci-catalog `zig.sh` installer as one Won't-Do remark implied.)

**Preserved invariants — all confirmed present in current source:**

- **SEC-P3-04** HMAC-SHA256 state MAC (wire v3) + timing-safe verify: `verifyStateMacIfV3` at `generator.zig:2106-2122` (`std.crypto.timing_safe.eql`).
- **SEC-P4-01** no-downgrade policy: default `state_mac_policy = .require_mac_when_keyed` (`:165`, `:415`), enforced in `enforceStateMacPolicy` (`:2144-2168`) returning `Error.StateVersionDowngrade`; `verifyStateMacIfV3` runs before the policy gate and they are mutually exclusive on file version — ordering is correct.
- **SEC-P4-02** HMAC key stack-spill fix: pointer-capture `if (key_copy) |*k|` in `saveStateImpl` (`:1821`) and `?*const [32]u8` key in load (`:2284`), plus `defer std.crypto.secureZero` (`:1804`).
- **SEC-P4-10 / SEC-P4-A1**: `reseed()` zeroes `v7_atomic_state` (`:583`); `newV7Atomic` retry budget bounded at `max_retries = 4096` (`:806`, `:829-835`) returning `Error.InvalidTimestamp` on a frozen/hostile clock.
- **SEC-P4-13**: `timestampFromV7` `std.debug.assert((combined >> 48) == 0)` before `@intCast` (`timestamp.zig:190`).
- **CWE-316/CWE-320 key hygiene**: `secureWipeMacKey` (`:604`) and `rotateStateMacKey` (`:1960-1978`, secure-zeros old key at `:1972`, loads under configured policy with **no `.any` override** preserving SEC-P4-01).
- **State-file filesystem hardening**: `0o600` create + umask-proof `fchmod` (`:1719`,`:1728`), `O_EXCL` exclusive create refusing symlink-on-create (`:1718`), `O_NOFOLLOW` on load (`:2034`) + Windows REPARSE_POINT reject (`:2062`), atomic write-then-rename + fsync (`:1738-1776`), oversize-file probe (`:2074-2079`), version/length matching (`:2089-2095`), `u60` range guard on `last_v1_ts` (`:2196`), clock-rollback guards (`:2199-2217`, `:2238-2247`).
- **Parse-path safety**: length-strict `fromString` (`uuid.zig:474-495`), `fromBytes` length check (`:428`), `hexVal` rejects all non-hex incl. bytes >127 via `else` arm (`:666-673`), `parseCanonical`/`parseHash` index only within validated-length slices.
- **CWE-327 / SEC-P3-05 / SEC-P4-12**: V3/V5 broken-hash + namespace-forgery + unbounded-input warnings and `newV3Bounded`/`newV5Bounded` + `newV3Strict`/`newV5Strict` all present (`generator.zig:1273-1401`).
- **Timing safety**: `timingSafeEql` (`uuid.zig:306`) + CWE-208 notes on `eql`/`isNil`/`isMax`.

---

## 5. Secure Design Notes (positive controls observed)

- **Defense-in-depth state persistence** is the standout: authenticated (HMAC-SHA256) wire format, timing-safe MAC compare, anti-downgrade policy as the *default*, key zeroization on wipe/rotate, atomic durable writes with fsync, symlink/reparse-point rejection on both POSIX and Windows, oversize/length/magic validation, and clock-rollback replay guards. This is materially stronger than typical UUID libraries.
- **Privacy-by-default**: V1/V6 use a random multicast node ID unless MAC is explicitly opted in (`generator.zig:94-99`); MAC exposure is documented.
- **CSPRNG throughout** with optional caller-injected `std.Random` to remove the process-global from the hot path (SEC-P3-08), plus a Debug-only weak-PRNG smoke check.
- **Memory-safety discipline**: length checks precede every slice index in parse and hwaddr paths; integer casts are guarded (`clockToMs`, timestamp overflow guards, `u60` range check); buffers are pre-zeroed before partial reads (CWE-908).
- **Concurrency correctness**: split mutexes with fixed acquisition order (deadlock-free), acquire/release node-cache publication, a rigorously argued lock-free V7 CAS with bounded retries.
- **Hardened build tooling**: `build.zig` uses no `@cImport`/`@embedFile`/`addSystemLibrary`/system-lib fetches; the new diamond-dep detector does no process spawning, no writes, and no unsafe deserialization; `.gitleaks.toml` keeps the full default ruleset; the Zig toolchain download is checksum-verified before extraction.
- **HEAD dependency pin is correct**: immutable commit SHA + Zig content hash for the sole `json` dependency.

---

## 6. Coverage Gaps and Questions

- **ci-catalog component bodies are unauditable from this environment** (the SEC-P4-14 blocker — no credentials / `git ls-remote` fails). The 8 included components execute in CI but their source cannot be reviewed here; this is the single largest residual unknown. Confidence on CI supply chain is therefore Medium.
- **No runtime fuzzing or full test-suite execution** was performed (compile-check only). The ledger notes a fuzz-corpus gap at the SEC-R12-02 overflow boundary (`docs/GAP_ANALYSIS.md:2836`) — worth confirming the timestamp-overflow fix has organic fuzz coverage; out of scope for this static pass.
- **`.zigversion` referenced in the input contract is absent** from the repo; the toolchain pin lives in mise / `minimum_zig_version` in `build.zig.zon`. Minor; confirm intentional.
- **Windows state-path and reparse-point logic** was read but not executed on a Windows host; the POSIX paths were the focus.
- **Open question for the maintainer:** should NEW-01 (pre-commit tag pinning) be treated as actionable, or classified **Won't-Do** under the same "developer-tooling-team governance" rationale already applied to `check-yaml --unsafe`? The decision should be recorded explicitly so it does not resurface each cycle.

---

## 7. Prioritized Next Actions

1. **NEW-01 (Low)** — Freeze pre-commit hook `rev:`s to commit SHAs (`pre-commit autoupdate --freeze`) **or** record an explicit Won't-Do with the developer-tooling-governance rationale. Given `ci.autofix_prs: true`, prefer freezing. *(Smallest safe change; closes the only NEW non-Info item.)*
2. **SEC-P4-14 (Medium-High, KNOWN/Blocked)** — Unblock by obtaining the operator tag→SHA map for the 8 ci-catalog components and applying the prepared plan (`docs/superpowers/plans/2026-04-19-sec-p4-ci-catalog-sha-pins.md`); fold the H-1 APT-pin note into the same `ci-catalog-sha-rotation.md` runbook. This remains the top structural item.
3. **NEW-03 (Info)** — Single-source the version (derive `root.zig` `version` from `build.zig.zon`, or sync on release) and add a CI consistency assertion. Quick, prevents provenance drift.
4. **NEW-02 (Info)** — Add a release-gate check that tagged commits' `build.zig.zon` contain only SHA+content-hash pins (no `#v<semver>` URLs); re-confirm the `json` content hash on the next bump.
5. **NEW-04 / NEW-05 (Info, optional)** — Add symlink rejection (or cache-root confinement) in `detect_diamond_deps.py`, and add iteration caps to the Windows/macOS MAC linked-list walks. Defense-in-depth only.
6. **O-2 (Info, KNOWN)** — Land one of the documented options (Debug-mode fork-detection assert, `pthread_atfork` shim where libc is linked, or a dedicated `docs/runbooks/post-fork-reseed.md`) when convenient; no urgency.

**Bottom line:** No confirmed new vulnerabilities of Medium severity or above were found in the reviewed scope; the recent in-scope commits introduced no regressions to the security invariants; the three known-open items are accurately scoped and unchanged; and the only NEW actionable item is a Low-severity pre-commit pinning hardening.
