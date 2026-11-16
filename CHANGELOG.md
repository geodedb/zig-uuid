# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.10] - 2026-11-15

### Changed

- json v0.1.20 -> v0.1.21, which carries thread-pool v0.2.11, so uuid's
  consumers resolve a single thread-pool (SONNY-6630).

## [0.1.8] - 2026-10-11

### Changed

- json v0.1.19 and thread-pool v0.2.8 (single thread-pool in the graph).
- CI: create GitLab Releases with the job token.
- fips v0.1.3 (one fips version across the devnw/zig graph).
- CI: test-fips provisions the OpenSSL 3.6.5 FIPS provider through the fips
  dependency's own installer (`zig build provision-fips`), replacing the
  fips-deps job that called a nonexistent `make deps` target.

### Fixed

- bench-contention no longer exhausts memory. It handed the harness an
  arena, so per-run buffer frees were ignored and `--runs 3` grew past 8 GiB.
  Peak RSS is now about 250 MiB.

## [0.1.7] - 2026-09-12

### Changed

- Converge thread_pool v0.2.7, fips v0.1.1, protobuf v0.1.5 (GAP-0838 diamond sync).

## [0.1.2] - 2026-06-11

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
- README dependency-injection example used a non-existent
  `gen.interface()` method; corrected to
  `GeneratorInterface.fromGenerator(&gen)` (QC-125). Full error-set
  table, namespace API, and hash-context tables also corrected
  (QC-126..128).

### Added (tests)

- Delegation tests for the 7 module-level wrappers added after QC-30
  (`newV3Bounded`, `newV5Bounded`, `saveState`, `loadState`,
  `migrateStateToV3`, `rotateStateMacKey`, `secureWipeMacKey`) — unit
  suite 274 → 279 passing (QC-147). Dead XFAIL guard removed from the
  SEC-P4-01 downgrade integration test (QC-146).

## [0.1.1] - 2026-05-02

### Release Notes -- 2026-04-18..2026-04-20 Phase 2/3 Quality Audit Closures (QC-113..QC-117, QC-114, PERF-41/44, SEC-P4-13)

Phase 2/3 quality-audit closure batch landed between 2026-04-18 and 2026-04-20. Five quality findings (QC-113a/b/c/d, QC-114, QC-115, QC-116, QC-117) closed across four commits plus a late-cycle QC-113d re-attempt; two performance findings (PERF-41, PERF-44) and one security follow-up (SEC-P4-13 — save-during-wipe race) recorded in adjacent `docs/PERF_GAP_ANALYSIS.md` and `docs/GAP_ANALYSIS.md`. No public API surface changes; all closures are refactor / test / tooling / documentation improvements preserving the SEC-P3-04 HMAC contract, the PERF-21 dual-path V7 design, and the PERF-34 align(64) cache-line separator invariant. See `docs/QUALITY_GAP_ANALYSIS.md` Phase 2/3 section (line 2575 onward) for the full evidence + commit chain.

### Changed

- **(refactor)** `src/generator.zig` — `loadStateImpl` / `saveStateImpl` / `newV7Atomic` oversized-fn split (QC-113a/b/c, commits `2a8f4ea`, `47ec3d0`, `cb0f44d`). V1/V6 preamble deduplication co-closed with QC-113a (QC-115).
- **(refactor)** `src/generator.zig` — pure `V7Cas.transition` helper extracted and `newV7Atomic` rewired to delegate state-transition decisions (QC-113d, commits `b179892`, `a51e411`). ABA-avoidance preserved via the u64-state-word ratchet test (commit `37419f6`); PERF-40 + PERF-34 layout witnesses intact; bench evidence at `docs/evidence/qc-113d-*.json` within stddev-adjusted gates (commit `8211c0c`); QC-113d marked resolved in `docs/QUALITY_GAP_ANALYSIS.md` (commit `2c76a4b`).
- **(pre-commit)** `.pre-commit-config.yaml` — added `gitleaks`, `test-integration`, and `bench-check` hooks for pre-commit ↔ CI parity (QC-116, commit `0c56f13`). SAST/SBOM documented as CI-only.

### Added (tests)

- Per-OS hwaddr unit tests across `src/hwaddr/linux.zig` / `macos.zig` / `windows.zig`: +11 tests covering success + OOM + ENOENT + permission-denied + empty-iface branches, gated by `builtin.os.tag` (QC-114, commit `b7fb01e`).

### Fixed

- Test stderr noise during policy-downgrade tests suppressed via `std.log.scoped` + per-test `testing.log_level` override; warn-noise count 3 → 0 on `zig build test` (QC-117, commit `cfa9f04`).

### Performance

- **(PERF-41)** — see `docs/PERF_GAP_ANALYSIS.md` for evidence chain. Landed 2026-04-18..2026-04-20.
- **(PERF-44)** — see `docs/PERF_GAP_ANALYSIS.md` for evidence chain. Landed 2026-04-18..2026-04-20.

### Security (open — tracked)

- **(SEC-P4-13)** Potential save-during-wipe race in `saveStateImpl` re-reading `self.state_mac_key` outside the state mutex after `packStateIntoBuffer` released it; if `secureWipeMacKey()` runs concurrently the `else unreachable` branch at `src/generator.zig:1739` could panic. Tracked as QC-118 in `docs/QUALITY_GAP_ANALYSIS.md`; shared root cause with SEC-P4-13 in `docs/GAP_ANALYSIS.md`. Recommended fix: pass the key pointer out of the locked section. **Status: Open, suspected (no observed panic).**

### Release Notes -- 2026-04-18 SEC-P4-01 HMAC Downgrade Resistance (BEHAVIOUR CHANGE)

Closes the HIGH-severity v3→v2 HMAC downgrade finding (SEC-P4-01). `loadState` now rejects unauthenticated v1/v2 state files with `Error.StateVersionDowngrade` when `state_mac_key` is configured, closing the trivial downgrade attack (CWE-757) where a local attacker strips the 32-byte HMAC trailer from a v3 file to silently bypass integrity verification. New `InitOptions.state_mac_policy` knob with three variants (`.any` / `.require_mac_when_keyed` / `.require_mac_always`); default is `.require_mac_when_keyed`. New `Generator.migrateStateToV3(path)` helper + module-level `uuid.migrateStateToV3(path)` for one-shot on-disk upgrade. The XFAIL integration guard at `tests/integration.zig` (GAP-DOC-08.2, commit `5fe1771`) activates with this release — integration suite is now 37/37 passing with zero skipped.

**Migration:** callers that previously loaded v1/v2 files under a configured `state_mac_key` have two clean paths:

1. Mid-rotation: set `InitOptions.state_mac_policy = .any` explicitly to restore the pre-SEC-P4-01 warn-and-accept behaviour.
2. Permanent: call `uuid.migrateStateToV3(path)` once at startup after configuring the key; subsequent loads under the default policy succeed.

### Added

- `uuid.StateMacPolicy` enum (`.any` / `.require_mac_when_keyed` / `.require_mac_always`).
- `InitOptions.state_mac_policy: StateMacPolicy = .require_mac_when_keyed` field.
- `Generator.state_mac_policy: StateMacPolicy` instance field.
- `Generator.migrateStateToV3(path: []const u8) Error!void` method.
- `uuid.migrateStateToV3(path)` module-level wrapper.
- `Error.StateVersionDowngrade` variant (distinct from `StateMacMismatch` so callers can pattern-match tampering vs downgrade separately).

### Changed

- **(BEHAVIOUR)** `loadState` default policy rejects unauthenticated v1/v2 files when `state_mac_key` is configured. The pre-SEC-P4-01 `std.log.warn` was a detection signal only; the new policy is a hard gate.

### Release Notes -- 2026-04-18 Benchmark Suite Rewrite

Replaced the legacy `bench/main.zig` + `bench/baseline.txt` text harness with a structured JSON benchmark suite under `benchmarks/`, modelled after the sibling thread-pool repo. Every scenario runs 7 times (median-of-6 + stddev); results are emitted as JSON so the new `bench-compare` step can gate CI on both a hard 15% regression threshold and a per-row `max(threshold, 3*stddev)` noise floor (PERF-26 retained). New build steps: `bench`, `bench-check`, `bench-contention`, `bench-state`, `bench-micro-parse`, `bench-micro-format`, `bench-micro-hash`, `bench-micro`, `bench-all`, `bench-compare`. Added UUID-specific correctness witnesses: `duplicate_uuids` (must be 0 for contention scenarios) and `lockfree_fallbacks` (PERF-21 saturation counter). Baselines committed at `benchmarks/results/baseline*.json`.

### Changed

- Benchmark harness migrated from `bench/main.zig` (text output, single entry point) to `benchmarks/` (JSON output, six executables + harness + compare tool)
- `bench/baseline.txt` replaced by `benchmarks/results/baseline.json` (schema documented in `benchmarks/common.zig`)
- `.gitlab-ci.yml` `bench-regression` job simplified to `zig build bench` + `zig build bench-compare` (no inline Python parser)
- `bench-check` now compile-checks every benchmark executable (previously only `bench/main.zig`)

### Release Notes -- 2026-04-18 Gap Closure Cycle (Groups A + B + C + D)

This release closes a 60-item gap-analysis cycle spanning security, performance, quality, and documentation: 52 items closed in prior rounds (25 Phase-2 bookkeeping tracker items, 16 Phase-3 initial closures, and 11 Group C closures) are joined by 4 full closures and 1 partial from Group D. Performance gets an opt-in lock-free V7 CAS path (`InitOptions.v7_lockfree`, ~34% uplift at 32 threads with the mutex path remaining the default for correctness-authority) and a zero-indirection comptime-generic `GeneratorInterfaceFor(G)` that complements — without replacing — the runtime vtable `GeneratorInterface`. Security gets explicit CSPRNG injection via `InitOptions.random: ?std.Random` (`Generator.initOptions(opts)`), HMAC-SHA256-authenticated state-file wire-format v3 with timing-safe tag compare and full v1/v2 backward compatibility (opt-in via `Generator.state_mac_key`; new `Error.StateMacMismatch`), fork-safety via `Generator.reseed()`, V3/V5 `newV3Strict`/`newV5Strict` guarded by a `Namespace` enum, `loadState` clock-rollback rejection, explicit `0o600` mode on `saveState`, and a published `/.well-known/security.txt` (RFC 9116) alongside CVSS v4.0 and a Disclose.io-derived safe-harbor draft (3 human-input TODOs remain: PGP fingerprint publication, CNA choice, safe-harbor legal review). Module-surface parity landed via `defaultGenerator()` plus wrappers (`clearNodeCache`, `reseed`, `saveState`, `loadState`, `initV3Namespace`, `initV5Namespace`). Performance also gains `PrehashedV3/V5`, `ProcessHashContext`, an `align(64)` false-sharing separator between V7 and V1/V6 state, atomic `node_cache`, and a threshold-gated CI `bench-regression`. Four Won't-Do items reaffirmed (SEC-P3-06, SEC-R9-02, SEC-R2-01, GAP-DOC-04). No existing call sites break: every Group C + Group D change is additive or default-preserving.

### Added

- `uuid.GeneratorInterfaceFor(comptime G: type)` — comptime-generic zero-indirection wrapper around any concrete generator type; complements (does not replace) the runtime vtable `GeneratorInterface` (PERF-31)
- `Generator.InitOptions { random, clock, hwaddr_fn, state_mac_key, v7_lockfree }` + `Generator.initOptions(opts)` — single entry point for explicit random-source, clock, hwaddr, state-file MAC key, and opt-in lock-free V7 selection (SEC-P3-08, SEC-P3-04, PERF-21)
- `Generator.state_mac_key: ?[32]u8` — optional caller-supplied HMAC-SHA256 key enabling state-file wire-format v3 with timing-safe tag verification; default `null` preserves v1/v2 read behaviour (SEC-P3-04)
- `Generator.v7_lockfree: bool` — opt-in lock-free V7 CAS path (default `false`; mutex path remains correctness-authoritative) (PERF-21)
- `Error.StateMacMismatch` — returned by `loadState` when a v3 state file fails HMAC verification (SEC-P3-04)
- `/.well-known/security.txt` per RFC 9116 (SEC-P3-07 partial)
- `Generator.reseed()` — fork-safe CSPRNG re-seeding; callers should invoke post-`fork(2)` on fork-capable platforms (SEC-P3-01)
- `Namespace` enum + `asUUID()`; `newV3Strict` / `newV5Strict` Generator + module-level variants (SEC-P3-05)
- `defaultGenerator() *Generator` + module-level parity wrappers (`clearNodeCache`, `reseed`, `saveState`, `loadState`, `initV3Namespace`, `initV5Namespace`) (QC-100)
- `Config.clock_rollback_tolerance_ms = 1_000` (SEC-P3-02)
- `Generator.PrehashedV3` / `Generator.PrehashedV5` + `initV3Namespace(ns)` / `initV5Namespace(ns)` — pre-absorbed Md5/Sha1 state for V3/V5 in-namespace callers; also re-exported at module level as `uuid.initV3Namespace` / `uuid.initV5Namespace` (PERF-30)
- `ProcessHashContext` — per-process CSPRNG-seeded V5 helper; zero runtime cost (PERF-32)
- `benchV7Contention` multi-threaded V7 bench (PERF-22)
- `bench/baseline.txt` snapshot + CI threshold-gated `bench-regression` job (PERF-26)

### Changed

- `loadState` rejects future-dated state beyond `Config.clock_rollback_tolerance_ms = 1_000`; clamps `last_v1_ts` monotonically (SEC-P3-02)
- `saveState` sets explicit `.mode = 0o600` + belt-and-suspenders `fchmod(0o600)` (SEC-P3-03)
- `node_cache` now uses atomic `node_cache_valid` flag + raw `node_cache_bytes` with acquire/release ordering (PERF-27)
- `align(64)` cache-line separator between V7 and V1/V6 state clusters in `Generator` (PERF-29)
- `rand` / `clock` fields are nullable — default paths use inlinable CSPRNG / clock; test-injectable variants retained (PERF-23)
- `std.Io.Threaded.global_single_threaded.io()` hoisted to per-function / field constant (PERF-28 / QC-96)
- `jsonMarshal` is now single-pass (PERF-25)

### Added (prior)

- `toHexAlloc` / `toHexUpperAlloc` — allocating hex-without-dashes variants completing the API surface (QC-42)
- `benchFromStringHex` / `benchFromStringURN` benchmarks in `bench/main.zig` (QC-45)
- `UUID.timingSafeEql(other) bool` — constant-time equality for UUIDs used as secret tokens; wraps `std.crypto.timing_safe.eql` (SEC-R9-01 / CWE-208)
- `benchEql` / `benchTimingSafeEql` benchmarks in `bench/main.zig` (QC-73)

### Fixed

- `fromString("urn:")` now returns `Error.InvalidURNPrefix` instead of `Error.InvalidLength` (QC-47)
- `Timestamp.now()` now returns `Error.InvalidTimestamp` for far-future clocks (year >60,424) instead of panicking; adds upper-bound guard matching `fromUnixNano` (SEC-R11-01 / CWE-190)
- `Generator.loadState()` now opens the state file with `O_NOFOLLOW` on POSIX, preventing symlink redirect attacks (SEC-R11-04 / CWE-61)

### Changed

- **MSRV bumped to Zig 0.16.0** — `build.zig.zon`, `README.md`, and module
  docstrings now require Zig 0.16.0 or later; this matches the actual
  toolchain used by CI and the `std.Io`-based APIs that replaced
  `std.time`/`std.fs.File.writer()` in Zig 0.16 (GAP-DOC-01, QC-93)
- Aligned minimum Zig version to 0.15.2 in `README.md` and `build.zig.zon` (QC-44)
- `UUID.eql()` doc comment extended with CWE-208 timing-safety warning directing secret-token callers to `timingSafeEql` (SEC-R9-01)
- `UUID.isNil()` and `UUID.isMax()` doc comments extended with CWE-208 timing notes directing secret-comparison callers to `timingSafeEql(UUID.nil)` / `timingSafeEql(UUID.max)` (SEC-R11-03)

### Documentation

- Added comprehensive doc comment to `fromString` listing all accepted formats and possible errors (QC-46)

## [0.1.0] - 2026-03-21

### Added

- Full RFC-9562 compliance: V1, V3, V4, V5, V6, V7, V8 UUID generation
- Injectable `Generator` (clock, random, hardware-address functions)
- Cross-platform MAC address resolution (Linux, macOS, Windows)
- Multiple parse formats: canonical (`xxxxxxxx-xxxx-...`), braced, 32-char hex, URN
- Multiple output formats: lowercase/uppercase, with/without dashes, URN
- V7 monotonicity guarantee with 12-bit counter and CSPRNG jitter
- V7 persistent state (save/load) for collision-free cross-restart monotonicity
- V1/V6 clock-sequence management with regression and node-change detection
- `NullUUID` nullable wrapper
- JSON serialization via `gitlab.com/devnw/zig/json`
- `GeneratorInterface` for dependency injection and mocking
- RFC-9562 Appendix A test vectors for V1, V6, V7

[Unreleased]: https://gitlab.com/devnw/zig/uuid/-/compare/v0.1.2...HEAD
[0.1.2]: https://gitlab.com/devnw/zig/uuid/-/compare/v0.1.1...v0.1.2
[0.1.1]: https://gitlab.com/devnw/zig/uuid/-/compare/v0.1.0...v0.1.1
[0.1.0]: https://gitlab.com/devnw/zig/uuid/-/releases/v0.1.0
