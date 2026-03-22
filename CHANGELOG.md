# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `toHexAlloc` / `toHexUpperAlloc` — allocating hex-without-dashes variants completing the API surface (QC-42)
- `benchFromStringHex` / `benchFromStringURN` benchmarks in `bench/main.zig` (QC-45)
- `UUID.timingSafeEql(other) bool` — constant-time equality for UUIDs used as secret tokens; wraps `std.crypto.timing_safe.eql` (SEC-R9-01 / CWE-208)
- `benchEql` / `benchTimingSafeEql` benchmarks in `bench/main.zig` (QC-73)

### Fixed

- `fromString("urn:")` now returns `Error.InvalidURNPrefix` instead of `Error.InvalidLength` (QC-47)
- `Timestamp.now()` now returns `Error.InvalidTimestamp` for far-future clocks (year >60,424) instead of panicking; adds upper-bound guard matching `fromUnixNano` (SEC-R11-01 / CWE-190)
- `Generator.loadState()` now opens the state file with `O_NOFOLLOW` on POSIX, preventing symlink redirect attacks (SEC-R11-04 / CWE-61)

### Changed

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
