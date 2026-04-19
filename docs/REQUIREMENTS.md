# Requirements

Last updated: 2026-04-18
Zig version audited: 0.16.0

## Scope

This repository is a standalone RFC-9562 UUID library for Zig. Its sole
responsibility is to generate, parse, format, compare, and serialize UUIDs of
all RFC-9562 versions (V1, V3, V4, V5, V6, V7, V8) and to provide an injectable
`Generator` so callers can substitute clock, random, and hardware-address
sources for testing or policy reasons. The only external dependency is
`gitlab.com/devnw/zig/json`, consumed through the opt-in `uuid_json` module
which exposes free-function `uuidJsonMarshal` / `uuidJsonUnmarshal` /
`nullUuidJsonMarshal` / `nullUuidJsonUnmarshal` adapters. The core `uuid`
module does not import `json`, so consumers that do not need the JSON adapter
can avoid pulling in that dependency.

## Non-Goals

- **No Geode graph-registry or graph-store persistence.** Those concerns live
  in the Geode project; this library contains no graph, registry, or store
  code.
- **No application-level UUID policy** (per-tenant sharding, rate limiting,
  session mapping). Callers compose those on top.
- **No transport / networking.** MAC resolution is a read-only local concern
  (Linux ioctl / macOS getifaddrs / Windows GetAdaptersAddresses) used only by
  opt-in `Generator.withHWAddr`.

## Functional Requirements

| ID | Requirement | Evidence |
|---|---|---|
| UUID-REQ-001 | Expose UUID V1 (Gregorian time + node) generation with opt-in MAC embedding. | `src/versions.zig`, `src/generator.zig` (`newV1` / `newV1AtTime`) |
| UUID-REQ-002 | Expose UUID V3 (MD5 name-based, deterministic) generation. | `src/versions.zig` (`newV3`) |
| UUID-REQ-003 | Expose UUID V4 (CSPRNG random) generation. | `src/versions.zig` (`newV4`, backed by `std.crypto.random`) |
| UUID-REQ-004 | Expose UUID V5 (SHA-1 name-based, deterministic) generation. | `src/versions.zig` (`newV5`) |
| UUID-REQ-005 | Expose UUID V6 (k-sortable Gregorian time + node) generation. | `src/versions.zig`, `src/generator.zig` (`newV6` / `newV6AtTime`) |
| UUID-REQ-006 | Expose UUID V7 (Unix-ms + 12-bit counter + CSPRNG) with cross-restart monotonicity via `saveState` / `loadState`. | `src/versions.zig`, `src/generator.zig` (`newV7` / `newV7AtTime`) |
| UUID-REQ-007 | Expose UUID V8 (custom 128-bit payload with V8 + variant nibbles). | `src/versions.zig` (`newV8`) |
| UUID-REQ-008 | Parse canonical, braced, 32-char hex, and URN formats; reject invalid input with a typed `Error`. | `src/uuid.zig` (`UUID.fromString`, `fromBytes`, `fromStringOrNil`) |
| UUID-REQ-009 | Format as lowercase+dashes, uppercase+dashes, lowercase hex, uppercase hex, URN, and via `std.Io.Writer` `{f}`. | `src/uuid.zig` (`toString*`, `toHex*`, `toURN*`, `format`) |
| UUID-REQ-010 | Provide constant-time equality (`timingSafeEql`) for secret-token use (CWE-208). | `src/uuid.zig` (`UUID.timingSafeEql`) |
| UUID-REQ-011 | Provide injectable `Generator` with `withClock`, `withRand`, `withHWAddr`, `clearNodeCache`, `saveState`, `loadState`, and a `GeneratorInterface` vtable. | `src/generator.zig` |
| UUID-REQ-012 | Provide `Timestamp` with V1 / V6 / V7 extraction plus Unix ns / ms / s conversions. | `src/timestamp.zig`, `src/versions.zig` (`timestampFromV1/V6/V7`) |
| UUID-REQ-013 | Provide `NullUUID` wrapper plus JSON marshal / unmarshal via `gitlab.com/devnw/zig/json`. JSON ships as free functions in the separate `uuid_json` module (`uuidJsonMarshal` / `uuidJsonUnmarshal` / `nullUuidJsonMarshal` / `nullUuidJsonUnmarshal`) so the core `uuid` module does not import `json`. | `src/null_uuid.zig`, `src/uuid_json.zig` |
| UUID-REQ-014 | Provide `UUID.HashContext` (fixed-seed Wyhash) and `UUID.SecureHashContext` (CSPRNG-seeded) for `std.HashMap` keys. | `src/uuid.zig` |

## Test Requirements

| ID | Requirement | Evidence |
|---|---|---|
| UUID-TEST-001 | Unit tests cover every version, parse/format round-trip, and error branch at Debug and ReleaseFast. | `src/uuid_test.zig`, `src/generator_test.zig`, `src/generator_state_test.zig` |
| UUID-TEST-002 | Integration tests exercise the public module seam (`@import("uuid")`) end-to-end. | `tests/integration.zig` |
| UUID-TEST-003 | Fuzz harness exercises `fromString` against malformed input. | `src/fuzz.zig` |
| UUID-TEST-004 | RFC-9562 Appendix A test vectors for V1, V6, V7 assert byte-exact output. | `src/uuid_test.zig` |
| UUID-TEST-005 | Cross-compile smoke test for x86_64/aarch64 Linux, x86_64/aarch64 macOS, x86_64 Windows. | `build.zig` (`check-cross` step) |

## Acceptance

- Full RFC-9562 conformance (V1, V3, V4, V5, V6, V7, V8 with correct version
  and variant nibbles; rejection of invalid variants in parse).
- `zig build check && zig build test --summary all && zig build test-integration`
  passes 257/257 unit tests + 1 skip and 37/37 integration tests on Zig 0.16.0.
- Cross-platform MAC resolution compiles on Linux / macOS / Windows;
  `withHWAddr` is opt-in and documented as exposing the host MAC.

## Documentation Requirements

- `README.md` documents every exported symbol in a tabular API reference.
- `CHANGELOG.md` follows Keep-a-Changelog and records every public-API or
  behavior change.
- Source-level `///` doc comments drive `zig doc`; internal review docs
  (`QUALITY_GAP_ANALYSIS.md`, `PERF_GAP_ANALYSIS.md`, `SECURITY_REVIEW_NOTES.md`,
  `GAP_ANALYSIS.md`) are not user-facing.
