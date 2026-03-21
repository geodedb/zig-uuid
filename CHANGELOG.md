# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial project structure
- Core library implementation
- Unit and integration tests
- CI/CD pipeline
- Documentation

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
