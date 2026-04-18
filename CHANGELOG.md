# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://gitlab.com/devnw/zig/uuid/-/compare/v0.1.0...HEAD
[0.1.0]: https://gitlab.com/devnw/zig/uuid/-/releases/v0.1.0
