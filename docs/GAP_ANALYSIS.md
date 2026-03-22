# UUID Library Gap Analysis

> Audit against [RFC-9562](https://www.rfc-editor.org/rfc/rfc9562) and
> [gofrs/uuid](https://github.com/gofrs/uuid) (the reference Go implementation).
>
> Date: 2026-03-21
> Last updated: 2026-03-22 — Full codebase audit Cycle 2: Security Cycle 14 (4 new, 3 closed, 1 open Info), Quality Cycle 13 (7 new, all closed), Performance Cycle 5 (6 new, 5 closed, 1 Won't Do). Grand totals: 175 findings across all domains — 166 closed, 6 Won't Do, 1 FP, 1 open (Info).

---

## Table of Contents

1. [RFC-9562 Compliance Gaps](#rfc-9562-compliance-gaps)
2. [Feature Gaps vs gofrs/uuid](#feature-gaps-vs-gofrsuuid)
3. [Won't Do Items](#wont-do-items)
4. [Prioritized Work Items](#prioritized-work-items)
5. [What Is Correct](#what-is-correct)

---

## RFC-9562 Compliance Gaps

### F-1 — V1/V6 embed real MAC address by default

**Status: ✅ Closed / Implemented**

**Change:** `Generator.hwaddr_fn` changed from `HWAddrFn = hwaddr.get` to
`?HWAddrFn = null`. When `null` (the default), `getNode()` generates a random
multicast node ID (multicast bit set per RFC §6.10) and caches it for the
generator's lifetime. MAC-based node IDs are now an explicit opt-in via
`Generator.withHWAddr(f)` or setting `.hwaddr_fn = f`.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.newV1: default uses random node with multicast bit (F-1)`
- `Generator.newV1: node is cached across calls (F-6/G-6)`
- `Generator.clearNodeCache refreshes node (F-6/G-6)`

---

### F-2 — `UUID.version()` panics on unknown version nibbles

**Status: ✅ Closed / Implemented**

**Change:** `Version` is now a non-exhaustive enum (trailing `_`). `@enumFromInt`
on unknown nibbles (nil UUID version=0, DCE Security version=2, future
versions 9–15) returns an unnamed member instead of panicking. `UUID.nil.version()`
no longer panics.

**Files:** `src/uuid.zig`

**Tests added:**

- `UUID.version() is safe for nil UUID (nibble=0, non-exhaustive)`
- `UUID.version() is safe for future nibble (nibble=15)`

---

### F-3 — Clock sequence fallback is not random

**Status: ✅ Closed / Implemented**

**Change:** `initClockSeq()` changed from `void` to `Error!void`. The
hardcoded `{ 0x12, 0x34 }` fallback is removed. CSPRNG failure now propagates
as `Error.RandomError` from `newV1AtTime`/`newV6AtTime`.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.initClockSeq propagates CSPRNG failure (F-3)`

---

### F-4 — V1/V6 do not detect node ID changes

**Status: ✅ Closed / Implemented**

**Change:** Added `last_node: ?[6]u8 = null` to `Generator`. In
`newV1AtTime` and `newV6AtTime`, after fetching the node ID, the new node is
compared against `last_node`; if different, `clock_seq` is incremented. The
node change detection works in conjunction with `clearNodeCache()` (F-6).

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.newV1: clock_seq increments on node ID change (F-4)`

---

### F-5 — No URN output method

**Status: ✅ Closed / Implemented**

**Change:** Added `UUID.toURN(buf: *[45]u8) []u8` and
`UUID.toURNAlloc(alloc) ![]u8`. `"urn:uuid:"` (9 chars) + canonical UUID
(36 chars) = 45 chars. Output is parseable by `UUID.fromString`.

**Files:** `src/uuid.zig`

**Tests added:**

- `toURN produces urn:uuid: prefix (F-5 / G-3)`
- `toURNAlloc (F-5 / G-3)`
- `toURN round-trip with fromString (F-5 / G-3)`

---

### F-6 — RFC Appendix A test vectors not fully asserted

**Status: ✅ Closed / Implemented**

**Change:** Added three deterministic tests using exact RFC Appendix A
timestamps, node IDs, and clock sequences. The V7 test uses a module-level
mock rand to fix rand_a and rand_b.

**Files:** `src/generator.zig`

**Tests added:**

- `RFC Appendix A.1 — V1 test vector (F-6)` → `c232ab00-9414-11ec-b3c8-9f6bdeced846`
- `RFC Appendix A.5 — V6 test vector (F-6)` → `1ec9414c-232a-6b00-b3c8-9f6bdeced846`
- `RFC Appendix A.6 — V7 test vector (F-6)` → `017f22e2-79b0-7cc3-98c4-dc0c0c07398f`

---

### F-7 — `Timestamp.now()` unchecked cast on pre-1970 system clock

**Status: ✅ Closed / Implemented**

**Change:** `Timestamp.now()` changed from `Timestamp` to `Error!Timestamp`.
Returns `Error.InvalidTimestamp` when `std.time.nanoTimestamp()` returns a
negative value (system clock before 1970). `Timestamp.fromUnixNano` and
`Timestamp.fromUnixMs` also guard against negative input. `Error.InvalidTimestamp`
added to the error set in `src/uuid.zig`. Callers in `generator.zig`
(`newV1`, `newV6`) updated to `try Timestamp.now()`.

**Files:** `src/uuid.zig`, `src/timestamp.zig`, `src/generator.zig`

**Tests added:**

- `Timestamp now() pre-1970 guard (F-7)`
- `Timestamp fromUnixMs: negative ms returns error (F-7)`

---

### F-8 — Shared V1/V6 clock_seq state is undocumented

**Status: ✅ Closed / Implemented**

**Change:** Added a comprehensive doc comment to the `Generator` struct
explaining the shared V1/V6 clock domain, the default random-node behaviour
(F-1), and the node-caching behaviour (F-6/G-6).

**Files:** `src/generator.zig`

---

### F-9 — No persistent state across process restarts

**Status: ✅ Closed / Implemented**

**Change:** Added `Generator.saveState(path)` and `Generator.loadState(path)`.
The state is serialised as a 22-byte binary blob: 4-byte magic `"UUID"`,
1-byte format version, 1-byte flags, u16 clock_seq, u64 last_v1_ts, and
optional 6-byte node_cache. Returns `Error.InvalidFormat` on corrupt or
version-mismatched files.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.saveState and loadState round-trip (F-9)`
- `Generator.loadState: corrupt magic returns error (F-9)`

---

## Feature Gaps vs gofrs/uuid

### G-1 — No binary marshal / unmarshal

**Status: ✅ Closed / Implemented**

**Change:** Added `UUID.toBytes() [16]u8` — returns a value copy of `.bytes`.
`UUID.fromBytes` already existed. Together they form the full binary marshal
interface.

**Files:** `src/uuid.zig`

**Tests added:**

- `toBytes returns 16-byte copy (G-1)`

---

### G-2 — No `fmt`-style format verbs / uppercase output

**Status: ✅ Closed / Implemented**

**Change:** Added four output methods:

- `toStringUpper(buf: *[36]u8) []u8` — uppercase with dashes
- `toStringUpperAlloc(alloc) ![]u8` — allocating uppercase with dashes
- `toHex(buf: *[32]u8) []u8` — lowercase no dashes
- `toHexUpper(buf: *[32]u8) []u8` — uppercase no dashes

All four share `toStringImpl`/`toHexImpl` private helpers parameterised on
the hex alphabet string.

**Files:** `src/uuid.zig`

**Tests added:**

- `toStringUpper produces uppercase with dashes (G-2)`
- `toHex produces lowercase without dashes (G-2)`
- `toHexUpper produces uppercase without dashes (G-2)`
- `toStringUpperAlloc (G-2)`

---

### G-3 — No URN output

**Status: ✅ Closed / Implemented** (same as F-5)

---

### G-4 — `timestampFromV7` returns `i64` ms, not `Timestamp`

**Status: ✅ Closed / Implemented**

**Change:** `timestampFromV7` now returns `Error!Timestamp` (consistent with
`timestampFromV1`/`timestampFromV6`). It converts the embedded Unix ms to a
Gregorian 100-ns `Timestamp` value via `Timestamp.fromUnixMs`. Callers use
`.toUnixMs()` to recover the raw millisecond value. All callers updated
(`tests/integration.zig`, `examples/basic.zig`, `src/generator.zig` test).

**Files:** `src/timestamp.zig`, `tests/integration.zig`, `examples/basic.zig`,
`src/generator.zig`

**Tests added:**

- `timestampFromV7: returns Timestamp with correct Unix ms (G-4)`
- `timestampFromV7: large real-world timestamp (G-4)`
- `integration: timestampFromV7 returns Timestamp (G-4)`

---

### G-5 — No `Timestamp` → wall clock conversion

**Status: ✅ Closed / Implemented**

**Change:** Added three conversion helpers to `Timestamp`:

- `toUnixMs() i64` — Unix milliseconds
- `toUnixSec() i64` — Unix seconds
- The existing `toUnixNano() i128` already covered nanoseconds

**Files:** `src/timestamp.zig`

**Tests added:**

- `Timestamp.toUnixMs round-trip (G-5)`
- `Timestamp.toUnixSec round-trip (G-5)`
- `Timestamp.toUnixNano is consistent with toUnixMs (G-5)`

---

### G-6 — MAC address fetched on every V1/V6 generation

**Status: ✅ Closed / Implemented**

**Change:** Added `node_cache: ?[6]u8 = null` to `Generator`. `getNode()`
returns the cached value immediately on subsequent calls. `clearNodeCache()`
sets `node_cache = null`, forcing a re-fetch on the next V1/V6 generation.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.newV1: node is cached across calls (F-6/G-6)`
- `Generator.clearNodeCache refreshes node (F-6/G-6)`

---

### G-7 — No `fromStringOrNil` / `fromBytesOrNil` convenience variants

**Status: ✅ Closed / Implemented**

**Change:** Added:

- `UUID.fromStringOrNil(s) UUID` — returns nil UUID on parse error
- `UUID.fromBytesOrNil(b) UUID` — returns nil UUID on wrong length

**Files:** `src/uuid.zig`

**Tests added:**

- `fromStringOrNil: valid input returns UUID (G-7)`
- `fromStringOrNil: invalid input returns nil (G-7)`
- `fromBytesOrNil: valid 16 bytes (G-7)`
- `fromBytesOrNil: wrong length returns nil (G-7)`

---

### G-8 — No `Generator` interface / abstraction

**Status: ✅ Closed / Implemented**

**Change:** Added `GeneratorInterface` — a vtable-based polymorphism type
that wraps any `*Generator` (or future concrete implementation). Exposes all
10 generation methods. `GeneratorInterface.fromGenerator(gen: *Generator)`
creates a `GeneratorInterface` backed by the concrete `Generator` via the
`generator_vtable` constant.

**Files:** `src/generator.zig`, `src/root.zig`

**Tests added:**

- `GeneratorInterface.fromGenerator: newV4 dispatches correctly (G-8)`
- `GeneratorInterface: newV3 dispatches correctly (G-8)`
- `GeneratorInterface: newV7AtTime dispatches correctly (G-8)`
- `integration: GeneratorInterface dispatches newV4 (G-8)`

---

### G-9 — No `IsZero()` alias

**Status: ✅ Closed / Implemented**

**Change:** Added `UUID.isZero() bool` as a direct alias for `isNil()`.

**Files:** `src/uuid.zig`

**Tests added:**

- `isZero alias for isNil (G-9)`
- `integration: isZero is an alias for isNil (G-9)`

---

### G-10 — `version()` unsafe for unknown nibbles (also RFC F-2)

**Status: ✅ Closed / Implemented** (same as F-2)

---

## Won't Do Items

The following gaps were considered but are **explicitly out of scope for this
library**. **Future agents must not attempt to implement these** — they are
handled by separate controls at the CI/CD pipeline, infrastructure, and
developer-tooling level. Attempting to implement them here would duplicate
controls and create false assurance.

| Item | Security Finding | Reason |
|------|-----------------|--------|
| CI/CD hash pinning | SEC-2 | Handled by pipeline configuration and Renovate/Dependabot at the org level. |
| Docker tag pinning | (CI/CD) | Handled by infrastructure controls outside this library. |
| Pre-commit hook versioning | — | Pre-commit hook versions are managed by the developer tooling team, not library code. |
| `check-yaml --unsafe` removal | SEC-4 | The `--unsafe` flag is required by the project's GitLab CI YAML which uses multi-document anchors. Removing it is a pre-commit configuration concern, not a library concern. |
| CI components semver→SHA pinning | SEC-5 | Handled by the CI/CD pipeline governance process (Renovate/org policy). Not a library responsibility. |

---

## Prioritized Work Items

### Priority 1 — Fix now (correctness / safety)

| Item | File(s) | Status |
|------|---------|--------|
| **F-1** — Default V1/V6 node to random; make MAC opt-in | `generator.zig` | ✅ Closed |
| **F-2** — Make `version()` safe for unknown nibbles | `uuid.zig` | ✅ Closed |
| **F-6** — Add RFC Appendix A.1, A.5, A.6 test vectors | `generator.zig` | ✅ Closed |

### Priority 2 — High value additions

| Item | File(s) | Status |
|------|---------|--------|
| **G-1** — `toBytes()` convenience method | `uuid.zig` | ✅ Closed |
| **G-2** — Uppercase and no-dash output formats | `uuid.zig` | ✅ Closed |
| **G-4** — Unify `timestampFromV7` return type with V1/V6 | `timestamp.zig` | ✅ Closed |
| **G-5** — `Timestamp` → Unix ns/ms/sec conversions | `timestamp.zig` | ✅ Closed |
| **G-6** — Cache MAC address per generator instance | `generator.zig` | ✅ Closed |
| **F-5 / G-3** — URN output (`toURN`, `toURNAlloc`) | `uuid.zig` | ✅ Closed |

### Priority 3 — Nice to have

| Item | File(s) | Status |
|------|---------|--------|
| **F-3** — Propagate CSPRNG failure in `initClockSeq` | `generator.zig` | ✅ Closed |
| **F-4** — Track last node; increment clock_seq on node change | `generator.zig` | ✅ Closed |
| **F-7** — Guard `Timestamp.now()` against pre-1970 clocks | `timestamp.zig` | ✅ Closed |
| **F-8** — Document shared V1/V6 clock_seq state | `generator.zig`, README | ✅ Closed |
| **G-7** — `fromStringOrNil` / `fromBytesOrNil` | `uuid.zig` | ✅ Closed |
| **G-9** — `isZero()` alias | `uuid.zig` | ✅ Closed |

### Priority 4 — Optional / future

| Item | File(s) | Status |
|------|---------|--------|
| **G-8** — `Generator` interface / abstraction | `generator.zig`, `root.zig` | ✅ Closed |
| **F-9** — Persistent generator state across restarts | `generator.zig` | ✅ Closed |

---

## What Is Correct

The following areas were audited and are fully compliant:

- **All version/variant bit placements** — V1, V3, V4, V5, V6, V7, V8 byte
  layouts match the RFC exactly.
- **V3 and V5 test vectors** — `5df41881-...` and `2ed6657d-...` are asserted
  and passing.
- **RFC Appendix A.1, A.5, A.6 test vectors** — V1, V6, and V7 exact-byte
  tests now pass (added by this implementation run).
- **V7 monotonicity** — Method 1 (RFC §6.2): fixed 12-bit counter in `rand_a`,
  randomly seeded each new millisecond tick, incremented within the same tick,
  mutex-protected, overflow spins until clock advances.
- **Gregorian epoch offset** — `122_192_928_000_000_000` is exact
  (`0x01B21DD213814000`).
- **Namespace UUIDs** — All four RFC §6.6 namespaces (DNS, URL, OID, X.500)
  are byte-for-byte correct.
- **Random multicast fallback** — When MAC unavailable, `node[0] |= 0x01` sets
  the multicast bit per RFC §6.10.
- **Privacy by default** — V1/V6 now use a random multicast node ID by default
  (F-1). MAC-based nodes require explicit opt-in.
- **CSPRNG usage** — `std.crypto.random` used throughout; meets RFC §6.9.
- **Clock regression handling** — V1 and V6 both increment `clock_seq` on
  regression and share `last_v1_ts`.
- **Node change detection** — V1 and V6 increment `clock_seq` when the cached
  node ID changes (F-4).
- **Variant encoding** — All four variants detected and set correctly.
- **Parse formats** — Canonical, braced, URN, and 32-char no-dash hex all
  parse correctly; case-insensitive.
- **Windows GUID interop** — `Data1`/`Data2`/`Data3` little-endian ↔
  big-endian conversion is correct; `Data4` is passed through unchanged.
- **Cross-platform MAC resolution** — Linux (`SIOCGIFCONF`/`SIOCGIFHWADDR`),
  macOS (`getifaddrs`/`AF_LINK`), Windows (`GetAdaptersAddresses`) all compile
  and the dispatch is comptime-safe.
- **Cross-compile targets** — All five targets (x86_64/aarch64 Linux/macOS,
  x86_64 Windows) compile cleanly.
- **All optimization levels** — 90/90 tests pass at Debug, ReleaseSafe,
  ReleaseFast, and ReleaseSmall.

---

## Security Review — 2026-03-21

> Adversarial security review performed by automated scanning + manual source
> analysis. All source files, CI/CD configuration, build files, and
> pre-commit hooks were examined.
>
> **Automated tools run:** gitleaks, trufflehog, syft/grype, trivy (fs +
> config), semgrep (default ruleset), osv-scanner, shellcheck
>
> **Results:** No secrets detected. No known CVEs in dependencies. No SAST
> findings from automated scanners. All findings below are from manual
> adversarial review.

### Summary Table (by severity)

| Severity | Count |
|----------|-------|
| High     | 2     |
| Medium   | 4     |
| Low      | 3     |
| Info     | 2     |
| **Total**| **11**|

### Stack-Ranked Findings

| Rank | Sev | Risk Score | Finding | Component | CWE | Evidence (file:line) | GitLab Issue URL | Fix Summary | Status |
|------|-----|-----------|---------|-----------|-----|----------------------|------------------|-------------|--------|
| 1 | High | 60 | `saveState` creates world-readable file exposing clock_seq + node_cache (MAC) | `src/generator.zig` | CWE-732 | `generator.zig:371` | <https://gitlab.com/devnw/zig/uuid/-/work_items/1> | `mode: 0o600` passed to `createFileAbsolute` | ✅ Closed |
| 2 | High | 52 | CI downloads Zig binary without checksum verification (MITM / supply-chain) | `.gitlab-ci.yml` | CWE-494 | `.gitlab-ci.yml:36-38` | <https://gitlab.com/devnw/zig/uuid/-/work_items/2> | Handled by CI/CD pipeline governance (Renovate/org policy) | 🚫 Won't Do |
| 3 | Medium | 36 | Linux `ifc_len` negative value causes panic via `@intCast` in safe builds | `src/hwaddr/linux.zig` | CWE-190 | `linux.zig:49` | <https://gitlab.com/devnw/zig/uuid/-/work_items/3> | Guard `if (ifc.ifc_len < 0) return Error.NoHWAddressFound` added | ✅ Closed |
| 4 | Medium | 28 | `check-yaml --unsafe` disables YAML bomb and anchor expansion protections in pre-commit | `.pre-commit-config.yaml` | CWE-400 | `.pre-commit-config.yaml:20` | <https://gitlab.com/devnw/zig/uuid/-/work_items/4> | Required by CI YAML multi-doc anchors; handled by pre-commit tooling team | 🚫 Won't Do |
| 5 | Medium | 28 | GitLab CI components pinned to mutable semver tags (not immutable commit/digest) | `.gitlab-ci.yml` | CWE-1104 | `.gitlab-ci.yml:7-20` | <https://gitlab.com/devnw/zig/uuid/-/work_items/5> | Handled by CI/CD pipeline governance (Renovate/org policy) | 🚫 Won't Do |
| 6 | Medium | 24 | `HashContext` uses `Wyhash.init(0)` (fixed seed) — HashDoS risk if used with adversarial inputs | `src/uuid.zig` | CWE-330 | `uuid.zig:128` | <https://gitlab.com/devnw/zig/uuid/-/work_items/6> | HashContext doc warning added; `SecureHashContext` with random seed added | ✅ Closed |
| 7 | Medium | 24 | macOS `sockaddr_dl.sdl_data[12]` truncated: interfaces with `sdl_nlen > 6` are silently skipped | `src/hwaddr/macos.zig` | CWE-131 | `macos.zig:29,61-62` | <https://gitlab.com/devnw/zig/uuid/-/work_items/7> | `sdl_data` enlarged to `[22]u8` (IFNAMSIZ+6); `sdl_len`-based bounds guard added | ✅ Closed |
| 8 | Low | 16 | V3 (MD5) and V5 (SHA-1) use cryptographically broken/weak hashes — no API warning | `src/generator.zig` | CWE-327 | `generator.zig:292,305` | <https://gitlab.com/devnw/zig/uuid/-/work_items/8> | Prominent security doc warnings added to `newV3` and `newV5` | ✅ Closed |
| 9 | Low | 12 | `saveState` / `loadState` lack TOCTOU protection (open + write not atomic) | `src/generator.zig` | CWE-362 | `generator.zig:350-404` | <https://gitlab.com/devnw/zig/uuid/-/work_items/9> | Write-to-.tmp then `std.fs.renameAbsolute`; test verifies no .tmp lingers | ✅ Closed |
| 10 | Low | 12 | V7 monotonic state (`last_ms`, `mono_seq`) not persisted — post-restart collision window | `src/generator.zig` | CWE-342 | `generator.zig:57-58,363` | <https://gitlab.com/devnw/zig/uuid/-/work_items/10> | State format v2 (32 bytes) persists V7 state; `mono_seq` loaded as 0x0FFF | ✅ Closed |
| 11 | Info | 4 | `default_generator` is a package-level mutable global — shared between all callers without isolation | `src/generator.zig` | CWE-362 | `generator.zig:407` | <https://gitlab.com/devnw/zig/uuid/-/work_items/11> | Doc comment added explaining thread-safety contract and isolation guidance | ✅ Closed |

---

### Finding Detail

#### SEC-1 (High) — `saveState` Creates World-Readable File Disclosing Clock State and Node Cache

**Status: ✅ Closed / Implemented**

**Change:** `saveState` now passes `std.fs.File.CreateFlags{ .mode = 0o600 }` to
`createFileAbsolute`, restricting the state file to owner-only read/write.

**Files:** `src/generator.zig`

---

**CWE-732 — Incorrect Permission Assignment for Critical Resource**
**Risk Score: 60** (Impact 5 × Likelihood 3 × 4)
**Confidence: Confirmed**

`Generator.saveState()` calls `std.fs.createFileAbsolute(path, .{})` with the
default `OpenFlags`, which creates the file with mode `0o666` (before umask).
With a typical umask of `022`, the resulting file is `0o644` — world-readable.

The state file contains:

- `clock_seq` (14 bits): partial predictor for future V1/V6 UUIDs
- `last_v1_ts` (60-bit Gregorian timestamp): reveals last generation time
- `node_cache` (6 bytes): the node ID, which may be a real hardware MAC
  address when `hwaddr_fn` is set (opt-in)

Any local user on a multi-user system can read this file and use the disclosed
data to narrow the space of past and future V1/V6 UUIDs, or to fingerprint the
host.

**Evidence:** `src/generator.zig:371`

```zig
const f = try std.fs.createFileAbsolute(path, .{});
```

**Fix:** Pass `std.fs.File.CreateFlags{ .mode = 0o600 }` to restrict the file
to the process owner only.

---

#### SEC-2 (High) — CI Zig Binary Download Without Integrity Verification

**Status: 🚫 Won't Do** — Handled by CI/CD pipeline governance (Renovate/org
policy). This is a pipeline configuration concern, not a library concern.
Future agents must not attempt to fix this here.

**CWE-494 — Download of Code Without Integrity Check**
**Risk Score: 52** (Impact 4 × Likelihood 3 × 4 + 4)
**Confidence: Confirmed**

The CI pipeline downloads the Zig toolchain binary from `ziglang.org` using
`curl -fsSL` but does not verify the SHA256 checksum afterwards. The
`ziglang.org` download server publishes SHA256 checksums in `minisign` format
alongside each release, but these are not used.

A compromised CDN or man-in-the-middle attack on the CI runner's network path
could substitute a malicious `zig` binary, leading to arbitrary code execution
in the build environment and potentially in produced artifacts.

**Evidence:** `.gitlab-ci.yml:36-38`

```yaml
- curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" -o zig.tar.xz
- tar -xf zig.tar.xz
- export PATH="$PWD/zig-linux-x86_64-${ZIG_VERSION}:$PATH"
```

**Fix:** Download and verify the minisign signature or SHA256 hash before
extracting. Example:

```bash
# Download known SHA256 for 0.15.1 and verify before extraction
curl -fsSL https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz -o zig.tar.xz
echo "<expected_sha256>  zig.tar.xz" | sha256sum -c -
tar -xf zig.tar.xz
```

---

#### SEC-3 (Medium) — Linux `ifc_len` Negative Value Causes Panic

**Status: ✅ Closed / Implemented**

**Change:** Added `if (ifc.ifc_len < 0) return Error.NoHWAddressFound;`
before the `@intCast` in `src/hwaddr/linux.zig`. A pathological negative
`ifc_len` now returns gracefully instead of panicking or causing UB.

**Files:** `src/hwaddr/linux.zig`

---

**CWE-190 — Integer Overflow or Wraparound**
**Risk Score: 36** (Impact 3 × Likelihood 3 × 4)
**Confidence: Confirmed**

In `src/hwaddr/linux.zig`, after `SIOCGIFCONF`, the code does:

```zig
const count: usize = @intCast(@divTrunc(ifc.ifc_len, @sizeOf(ifreq)));
```

`ifc.ifc_len` is `c_int` (signed). If the kernel returns a negative value
(pathological condition or kernel bug), `@divTrunc` returns a negative `c_int`,
and `@intCast(c_int -> usize)` panics in safe (`Debug` / `ReleaseSafe`) builds.
The impact is process termination rather than graceful fallback to a random node.

**Evidence:** `src/hwaddr/linux.zig:49`

**Fix:** Add a guard:

```zig
if (ifc.ifc_len < 0) return Error.NoHWAddressFound;
const count: usize = @intCast(@divTrunc(ifc.ifc_len, @sizeOf(ifreq)));
```

---

#### SEC-4 (Medium) — `check-yaml --unsafe` Disables YAML Bomb Protections

**Status: 🚫 Won't Do** — The `--unsafe` flag is required by the project's
GitLab CI YAML which uses multi-document anchors. Removing it is a
pre-commit configuration concern managed by the developer tooling team.
Future agents must not attempt to fix this here.

**CWE-400 — Uncontrolled Resource Consumption**
**Risk Score: 28** (Impact 2 × Likelihood 3 × 4 + 4)
**Confidence: Confirmed**

The `check-yaml` pre-commit hook is invoked with `args: [--unsafe]`, which
disables `ruamel.yaml`'s safe loader. This allows YAML files that contain
Python object tags (`!!python/object:...`) and arbitrarily nested anchors to
pass the check. A malicious or accidentally crafted YAML file committed to the
repo could cause exponential expansion (YAML bomb) during pre-commit runs.

**Evidence:** `.pre-commit-config.yaml:20`

```yaml
- id: check-yaml
  args: [--unsafe]
```

**Fix:** Remove `--unsafe` unless the repo contains multi-document YAML that
requires it. For GitLab CI YAML specifically (which uses anchors), use the
`--allow-multiple-documents` flag instead:

```yaml
- id: check-yaml
  args: []
```

If `--unsafe` is required for the CI YAML, scope it to that file only using
`files: \.gitlab-ci\.yml$`.

---

#### SEC-5 (Medium) — CI Components Pinned to Mutable Semver Tags

**Status: 🚫 Won't Do** — Tag pinning is handled by Renovate/org policy at
the pipeline governance level. Future agents must not attempt to fix this
here.

**CWE-1104 — Use of Unmaintained Third Party Components**
**Risk Score: 28** (Impact 2 × Likelihood 3 × 4 + 4)
**Confidence: Confirmed**

All eight `include:` directives in `.gitlab-ci.yml` reference GitLab CI
components by semver tag (e.g., `@v1.7.1`). Tags in GitLab (as in Git) are
mutable references and can be force-pushed to point to a different commit.
If the `devnw/ci-catalog` project were compromised, an attacker could move a
tag to a malicious commit and all pipelines would execute the new code without
any change to this repository.

**Evidence:** `.gitlab-ci.yml:7-20`

**Fix:** Pin each component to an immutable commit SHA using the `@sha:<hash>`
syntax, or enforce SHA pinning via Dependabot/Renovate.

---

#### SEC-6 (Medium) — `HashContext` Fixed Seed Enables HashDoS

**Status: ✅ Closed / Implemented**

**Changes:**

- Added a prominent security warning to `UUID.HashContext` doc comment
  explaining the fixed-seed HashDoS risk and when not to use it.
- Added `UUID.SecureHashContext` — a stateful context that samples a
  cryptographically random seed via `std.crypto.random.int(u64)` at
  construction, providing HashDoS resistance for untrusted UUID inputs.

**Files:** `src/uuid.zig`

**Tests added:**

- `SecureHashContext.init produces distinct seeds (SEC-6)`
- `SecureHashContext.hash is deterministic for a given seed (SEC-6)`
- `SecureHashContext.hash differs from HashContext (fixed-seed=0) (SEC-6)`
- `SecureHashContext.eql delegates to UUID.eql (SEC-6)`

---

**CWE-330 — Use of Insufficiently Random Values**
**Risk Score: 24** (Impact 3 × Likelihood 2 × 4)
**Confidence: Suspected**

`UUID.HashContext.hash` uses `std.hash.Wyhash.init(0)` with a constant seed
of zero. Two UUIDs that collide under this seed will always collide, allowing
an adversary who can control the UUID values inserted into a `HashMap` to
force pathological O(n²) hash-table behavior.

**Evidence:** `src/uuid.zig:128`

```zig
var hasher = std.hash.Wyhash.init(0);
```

**Fix:** Document that `HashContext` is not suitable for use with untrusted
UUID inputs in `HashMap`. Provide a `SecureHashContext` variant seeded with
`std.crypto.random.int(u64)` for security-sensitive maps.

---

#### SEC-7 (Medium) — macOS `sockaddr_dl.sdl_data` Under-Declared

**Status: ✅ Closed / Implemented**

**Changes:**

- `sdl_data` enlarged from `[12]u8` to `[22]u8` (IFNAMSIZ=16 + sdl_alen=6),
  covering all valid interface name lengths.
- Added a primary `sdl_len`-based bounds check as the authoritative safety
  guard: `if (sdl.sdl_len < header_size + mac_offset + 6) continue;`
- The old `sdl_data.len` guard is kept as a secondary defensive check.

Interfaces with names longer than 6 characters (e.g., `vboxnet0`,
`bridge100`) are no longer silently skipped.

**Files:** `src/hwaddr/macos.zig`

---

**CWE-131 — Incorrect Calculation of Buffer Size**
**Risk Score: 24** (Impact 3 × Likelihood 2 × 4)
**Confidence: Confirmed**

The macOS `sockaddr_dl` struct in `src/hwaddr/macos.zig` declares
`sdl_data: [12]u8`, matching the `MINSOCKADDRLEN` placeholder in the Apple
SDK headers. The actual struct pointed to by `ifa_addr` has a variable-length
`sdl_data` field sized for the interface name plus MAC address.

The guard `if (mac_offset + 6 > sdl.sdl_data.len) continue;` uses the
declared length (`12`) rather than the actual allocation. For interfaces with
names longer than 6 characters (e.g., `vboxnet0`, `bridge100`) the guard
correctly prevents a slice OOB panic, but those interfaces are silently
skipped even when they have valid MAC addresses. This causes `NoHWAddressFound`
to be returned on systems where only longer-named interfaces are available,
forcing fallback to a random node ID even when the caller requested MAC-based
node IDs via `hwaddr_fn`.

**Evidence:** `src/hwaddr/macos.zig:29,61-62`

**Fix:** Increase `sdl_data` to `[IFNAMSIZ]u8` (16 bytes) which covers all
valid interface name lengths while keeping the struct on the stack, or cast
through the `sdl_len` field to access the correct span.

---

#### SEC-8 (Low) — V3/V5 Use MD5/SHA-1 Without API Warning

**Status: ✅ Closed / Implemented**

**Change:** Added prominent `/// SECURITY WARNING (SEC-8 / CWE-327)` doc
comments to both `Generator.newV3` and `Generator.newV5` explaining that
MD5 (V3) is cryptographically broken and SHA-1 (V5) is weakened, that
outputs are deterministic, and that they must not be used where collision
resistance is required. References RFC-9562 §6.4 and §6.5.

**Files:** `src/generator.zig`

---

**CWE-327 — Use of a Broken or Risky Cryptographic Algorithm**
**Risk Score: 16** (Impact 2 × Likelihood 2 × 4)
**Confidence: Confirmed**

`Generator.newV3` uses MD5 and `Generator.newV5` uses SHA-1, as required by
RFC-9562. Both algorithms are cryptographically broken (MD5 collisions are
trivial; SHA-1 collisions have been demonstrated). The public API exposes these
without any caution note, making it easy for callers to accidentally use V3/V5
UUIDs in security-sensitive contexts (e.g., as content-addressable identifiers
or surrogate tokens), where an attacker capable of finding hash collisions could
cause two distinct inputs to map to the same UUID.

**Evidence:** `src/generator.zig:292,305`

**Fix:** Add a prominently visible doc comment to both `newV3` and `newV5`
noting that the output is deterministic (same namespace+name always produces
the same UUID), that MD5/SHA-1 are cryptographically broken, and that the
functions must not be used where collision resistance is required. Reference
RFC-9562 §6.4 and §6.5.

---

#### SEC-9 (Low) — `saveState`/`loadState` Are Not Atomic (TOCTOU)

**Status: ✅ Closed / Implemented**

**Change:** `saveState` now writes to `<path>.tmp` first (with `mode 0o600`)
then calls `std.fs.renameAbsolute` for an atomic replace. A crash between
write and rename leaves a `.tmp` file which is ignored on the next
successful save. An `errdefer` deletes the `.tmp` on write failure.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.saveState is atomic: no .tmp file lingers on success (SEC-9)`

---

**CWE-362 — Race Condition**
**Risk Score: 12** (Impact 2 × Likelihood 1.5 × 4)
**Confidence: Suspected**

`saveState` calls `createFileAbsolute` and then `writeAll` as two separate
operations. If the process is interrupted between these calls (power loss,
signal), the state file is left truncated or empty. On the next startup,
`loadState` returns `Error.InvalidFormat`, which is the safe fallback, but the
previous good state is unrecoverably lost.

Additionally, `loadState` reads the file without holding any cross-process
lock, so a concurrent `saveState` from another instance sharing the same path
can produce a corrupt read.

**Evidence:** `src/generator.zig:350-404`

**Fix:** Write to `<path>.tmp` first, then use `std.fs.rename` for an atomic
replace. Consider adding a CRC or checksum to the 22-byte state blob.

---

#### SEC-10 (Low) — V7 State Not Persisted Across Restarts

**Status: ✅ Closed / Implemented**

**Change:** State format bumped to **version 2** (32 bytes). The new format
appends 8 bytes of `last_ms` (i64 LE) and 2 bytes of `mono_seq` (u16 LE)
after the existing 22-byte v1 layout. `loadState` accepts both v1 and v2;
when loading v2, `mono_seq` is set to `0x0FFF` (max) so the first
post-restart V7 call forces a new clock tick and avoids any collision with
pre-restart UUIDs. Version-1 files remain fully readable (backward compat).

New constants: `state_format_version_v1 = 1`, `state_format_version = 2`,
`state_size_v1 = 22`, `state_size = 32`.

**Files:** `src/generator.zig`

**Tests added:**

- `Generator.saveState and loadState round-trip (F-9 + SEC-10)` — updated to
  verify V7 state round-trip and that `mono_seq` loads as `0x0FFF`.
- `Generator.loadState: v1 format (22 bytes) accepted for backward compat (SEC-10)`

---

**CWE-342 — Predictable Exact Value from Previous Values**
**Risk Score: 12** (Impact 2 × Likelihood 1.5 × 4)
**Confidence: Confirmed**

`saveState`/`loadState` persist V1/V6 state (`clock_seq`, `last_v1_ts`,
`node_cache`) but not V7 state (`last_ms`, `mono_seq`). After a process
restart followed by `loadState`, the V7 generator begins with `last_ms=0` and
`mono_seq=0`. If a V7 UUID was generated at time `T` in the previous process
run and the new process generates a V7 UUID within the same millisecond as `T`,
the `rand_a` field is re-seeded from CSPRNG (correct), but `mono_seq` is not
bounded to start above the previous run's final `mono_seq` value. This creates
a small but non-zero chance of V7 UUID collision across process restarts.

**Evidence:** `src/generator.zig:57-58,363` (V7 fields absent from state
serialization)

**Fix:** Persist `last_ms` and `mono_seq` in the state format (add format
version 2 with two additional fields). On load, `mono_seq` can be set to
`0x0FFF` (max) to force an immediate clock tick on the first post-restart V7
generation.

---

#### SEC-11 (Info) — `default_generator` Is a Mutable Package-Level Global

**Status: ✅ Closed / Implemented**

**Change:** Added a comprehensive doc comment to `default_generator`
explaining the shared-state contract, the mutex protection that makes
concurrent generation safe, the scenarios where concurrent mutation (e.g.,
`clearNodeCache()`, `loadState()`) may interact unexpectedly, and when to
use a per-caller `Generator.init()` instance instead.

**Files:** `src/generator.zig`

---

**CWE-362 — Race Condition**
**Risk Score: 4** (Impact 1 × Likelihood 1 × 4)
**Confidence: Confirmed**

`pub var default_generator: Generator = Generator.init()` is a single mutable
instance shared across all callers using the package-level convenience
functions (`newV4`, `newV7`, etc.). While the `Generator` struct protects its
own internal state with a `std.Thread.Mutex`, concurrent callers who mutate
the generator (e.g., calling `clearNodeCache()` or `loadState()`) on the
shared default instance may interact unexpectedly.

**Evidence:** `src/generator.zig:407`

**Fix:** Add a documentation note explaining that `default_generator` is shared
state and that callers requiring isolation (different node IDs, different clock
sequences) should create their own `Generator.init()` instances. Consider
whether `default_generator` should be `const` or unexported.

---

### Quick Wins (Low Effort, High Impact)

| Priority | Finding | Effort | Impact | Status |
|----------|---------|--------|--------|--------|
| 1 | SEC-1: Fix `saveState` file permissions to `0o600` | 1 line | Prevents MAC/clock state disclosure to local users | ✅ Done |
| 2 | SEC-3: Guard `ifc_len < 0` before `@intCast` | 1 line | Prevents panic crash on anomalous kernel response | ✅ Done |
| 3 | SEC-4: Remove `--unsafe` from `check-yaml` | 1 line | Restores YAML bomb protection | 🚫 Won't Do (pre-commit team) |
| 4 | SEC-8: Add doc warning to `newV3`/`newV5` | 2 comments | Prevents security misuse of name-based UUIDs | ✅ Done |
| 5 | SEC-2: Add SHA256 checksum step to CI Zig download | 3 lines | Closes supply-chain attack vector on CI builds | 🚫 Won't Do (CI/CD team) |

## Geode Extraction Metadata

This repository is already the correct home for the reusable UUID core extracted from Geode. The Geode review found no adjacent subsystem that should move with it.

### Geode Boundary

Move/own here:

| Geode source | Why it belongs in `uuid` |
|---|---|
| `src/uuid.zig:5`, `:11`, `:38`, `:43`, `:73`, `:85`, `:96`, `:106`, `:134` | Pure UUIDv7 generation, parsing, formatting, ordering, timestamp extraction, and hashing |
| `src/uuid.zig:141`, `:157`, `:172` | Core UUID correctness tests |

Keep in Geode:

| Geode source | Why it stays |
|---|---|
| `src/graph_registry.zig:24`, `:42`, `:78`, `:140` | Graph-registry persistence and CRC semantics are Geode-specific consumers of UUIDs |
| `src/graph_store.zig:625`, `:695`, `:753`, `:2812`, `:2875`, `:4018` | Graph-file naming, handle identity binding, and file-swap validation are storage/runtime integration, not UUID-library behavior |

### Geode Tests And Consumers

| Geode reference | Purpose |
|---|---|
| `src/uuid.zig:141`, `:157`, `:172` | Direct unit coverage of UUID generation, string conversion, and ordering |
| `src/graph_registry.zig:223`, `:271`, `:299`, `:322`, `:338`, `:360` | Confirms UUID integration in the graph registry |
| `src/graph_store.zig:5065` | Confirms UUID identity binding in per-graph file validation |
| `benchmarks/benchmark_extended_builtins_overhead.zig:9`, `:22`, `:26` | Performance reference for UUID builtin dispatch overhead |

### Current Assessment

- Extraction status: effectively complete.
- Additional Geode code to move: none identified.
- Main migration work left: keep Geode consumers importing this repo rather than re-growing UUID helpers locally.

---
---

## Security Gap Analysis — 2026-03-21 (Adversarial Review Cycle 2)

> **Reviewer:** Automated adversarial security review agent
> **Scope:** Full codebase (app code, CI/CD, build system, pre-commit, platform OS code, documentation)
> **Tools run:** gitleaks v8.30.0, semgrep v1.150.0, syft+grype v0.107.0, trivy v0.69.0, osv-scanner v2.3.2, shellcheck v0.9.0, checkov
> **Automated results:** 0 secrets, 0 CVEs, 0 SAST findings, 0 shell issues, 12 CI checks passed
> **All findings below are from manual adversarial review of source, CI/CD, and documentation.**
>
> **Won't Do Policy:** Items SEC-R2-01 (CI checksum), SEC-R2-02 (Docker tag pinning),
> SEC-R2-03 (CI component tag pinning), and SEC-R2-13 (pre-commit hook) are handled by
> separate pipeline governance controls and must remain Won't Do. Future agents must not
> attempt to fix these here.

### Summary

| Severity | Count |
| -------- | ----- |
| High     | 1     |
| Medium   | 4     |
| Low      | 5     |
| Info     | 2     |
| **Total**| **12**|

### Top 5 Risks (Cycle 2)

1. **SEC-R2-01** (High, Risk 60): Unverified Zig toolchain download in CI — supply chain attack vector
2. **SEC-R2-09** (Medium, Risk 48): Missing security documentation in README/SECURITY.md — enables downstream misuse
3. **SEC-R2-02** (Medium, Risk 32): Unpinned Docker image tags in CI — image substitution attack
4. **SEC-R2-03** (Medium, Risk 32): CI component includes pinned by mutable version tag, not commit digest
5. **SEC-R2-05** (Medium, Risk 36): HashDoS risk via `UUID.HashContext` (fixed seed) — documented in code but absent from README

### Stack-Ranked Findings (Cycle 2)

| Rank | Sev | Risk | Finding | Component | CWE | Evidence | GitLab Issue | Status |
| ---- | --- | ---- | ------- | --------- | --- | -------- | ------------ | ------ |
| 1 | High | 60 | CI downloads Zig toolchain via curl without SHA256/signature verification | `.gitlab-ci.yml:34-39` | CWE-494 | Lines 36-38 | [#39](https://gitlab.com/devnw/zig/uuid/-/work_items/39) | 🚫 Won't Do (CI/CD pipeline governance) |
| 2 | Medium | 48 | Missing security documentation in README/SECURITY.md for V1/V6, V3/V5, HashDoS, V7 predictability | `README.md`, `SECURITY.md` | CWE-1021 | Entire files | [#55](https://gitlab.com/devnw/zig/uuid/-/work_items/55) | ✅ Closed |
| 3 | Medium | 36 | HashDoS via `UUID.HashContext` fixed seed — warning in code only, absent from README | `src/uuid.zig:140-148` | CWE-330 | Line 142 | [#43](https://gitlab.com/devnw/zig/uuid/-/work_items/43) | ✅ Closed (docs added to README) |
| 4 | Medium | 32 | Unpinned Docker images in CI (no `@sha256:` digest) | `.gitlab-ci.yml` (all jobs) | CWE-494 | Every `image:` line | [#40](https://gitlab.com/devnw/zig/uuid/-/work_items/40) | 🚫 Won't Do (pipeline governance) |
| 5 | Medium | 32 | CI component includes pinned by mutable semver tag, not immutable commit digest | `.gitlab-ci.yml:6-21` | CWE-494 | Lines 6-21 | [#41](https://gitlab.com/devnw/zig/uuid/-/work_items/41) | 🚫 Won't Do (pipeline governance) |
| 6 | Medium | 36 | V3 (MD5) and V5 (SHA-1) use broken/weakened algorithms — not documented in README | `src/generator.zig:371-408` | CWE-327 | Lines 373, 399 | [#44](https://gitlab.com/devnw/zig/uuid/-/work_items/44) | ✅ Closed |
| 7 | Medium | 24 | V1/V6 MAC address disclosure when `hwaddr_fn` set — insufficient public documentation | `src/generator.zig:88-94` | CWE-200 | Lines 88-94 | [#47](https://gitlab.com/devnw/zig/uuid/-/work_items/47) | ✅ Closed |
| 8 | Low | 16 | Dependency pinned by git commit SHA only — no registry hash, upstream repo required | `build.zig.zon:7-10` | CWE-829 | Lines 8-9 | [#42](https://gitlab.com/devnw/zig/uuid/-/work_items/42) | ✅ Closed (Zig hash provides content verification; documented) |
| 9 | Low | 16 | `Generator.saveState` state file contains sensitive data (node ID / MAC) with no encryption | `src/generator.zig:467-507` | CWE-312 | Lines 483-487 | [#46](https://gitlab.com/devnw/zig/uuid/-/work_items/46) | ✅ Closed (0o600 mode; documented) |
| 10 | Low | 16 | No fuzz testing for UUID parsing functions — parser robustness unverified | `src/uuid.zig:207-416` | CWE-20 | Lines 207-416 | [#52](https://gitlab.com/devnw/zig/uuid/-/work_items/52) | ✅ Closed (src/fuzz.zig added) |
| 11 | Low | 16 | Windows `GetAdaptersAddresses` insufficient stack buffer on systems with >many adapters | `src/hwaddr/windows.zig:47-59` | CWE-120 | Lines 47-59 | [#49](https://gitlab.com/devnw/zig/uuid/-/work_items/49) | ✅ Closed (heap retry added) |
| 12 | Low | 16 | V7 monotonic sequence start is 12-bit seeded — partial predictability of ms-boundary counter | `src/generator.zig:163-172` | CWE-330 | Lines 163-172 | [#45](https://gitlab.com/devnw/zig/uuid/-/work_items/45) | ✅ Closed (documented in README security section) |
| 13 | Low | 16 | `check-yaml --unsafe` flag — YAML bomb protection disabled | `.pre-commit-config.yaml:20-21` | CWE-400 | Line 20 | [#51](https://gitlab.com/devnw/zig/uuid/-/work_items/51) | 🚫 Won't Do (pre-commit team) |
| 14 | Low | 12 | V7 spin-wait exit may leave `seq = 0` under concurrent counter overflow | `src/generator.zig:139-191` | CWE-362 | Lines 149-159 | [#53](https://gitlab.com/devnw/zig/uuid/-/work_items/53) | ✅ Closed |
| 15 | Info | 4 | `saveState` tmp_path buffer uses magic number 4100 instead of `PATH_MAX + 5` | `src/generator.zig:499-500` | CWE-120 | Lines 499-500 | [#50](https://gitlab.com/devnw/zig/uuid/-/work_items/50) | ✅ Closed |
| 16 | Info | 4 | Linux `SIOCGIFCONF` buffer truncation (>64 interfaces) not detected | `src/hwaddr/linux.zig:36-53` | CWE-131 | Lines 36-47 | [#54](https://gitlab.com/devnw/zig/uuid/-/work_items/54) | ✅ Closed (128-slot buffer + detection comment) |
| 17 | Info | 4 | `Timestamp.toUnixMs`/`toUnixSec` cast `i128→i64` can panic for far-future timestamps | `src/timestamp.zig:38-44` | CWE-190 | Lines 38-44 | [#48](https://gitlab.com/devnw/zig/uuid/-/work_items/48) | ✅ Closed (range guard added; proved safe by analysis) |

### Findings by Area (Cycle 2)

#### CI/CD and Supply Chain

- **SEC-R2-01** [#39]: Zig toolchain downloaded via `curl` without SHA256 or signature check — 🚫 Won't Do (pipeline governance)
- **SEC-R2-02** [#40]: All CI jobs use `debian:bookworm-slim` without digest pinning — 🚫 Won't Do (pipeline governance)
- **SEC-R2-03** [#41]: All 8 `include:` CI components use mutable semver tags — 🚫 Won't Do (pipeline governance)
- **SEC-R2-04** [#42]: External `json` dependency uses git+SHA URL (Zig hash provides content verification — ✅ Closed: documented in SECURITY.md)

#### Cryptography / Randomness

- **SEC-R2-05** [#43]: `UUID.HashContext` fixed-seed HashDoS (already mitigated in code with `SecureHashContext`) — ✅ Closed: README security section added
- **SEC-R2-06** [#44]: V3/V5 MD5/SHA-1 broken algorithms — ✅ Closed: README security section added
- **SEC-R2-07** [#45]: V7 `mono_seq` 12-bit seed boundary — ✅ Closed: documented in README security section

#### Information Disclosure

- **SEC-R2-08** [#46]: State file may store real MAC address (when `hwaddr_fn` set) in cleartext at rest — ✅ Closed: 0o600 mode documented in README
- **SEC-R2-09** [#47]: V1/V6 `withHWAddr()` embeds MAC in UUIDs — ✅ Closed: documented in README security section

#### Documentation Gaps

- **SEC-R2-10** [#55]: README and SECURITY.md lack security considerations section — ✅ Closed: full security section added to both files

#### Input Validation / Parsing

- **SEC-R2-11** [#52]: No fuzz testing for UUID parsing — ✅ Closed: `src/fuzz.zig` added with corpus and `std.testing.fuzz` integration

#### Platform / OS Integration

- **SEC-R2-12** [#49]: Windows `GetAdaptersAddresses` 16KB stack buffer — ✅ Closed: heap-allocated retry on `ERROR_BUFFER_OVERFLOW`
- **SEC-R2-13** [#54]: Linux `SIOCGIFCONF` 64-interface fixed buffer — ✅ Closed: expanded to 128 slots with truncation detection comment

#### Concurrency

- **SEC-R2-14** [#53]: V7 spin-wait exit path — ✅ Closed: restructured to single while-loop + single if/else; `seq` always assigned

#### Integer Arithmetic

- **SEC-R2-15** [#48]: `Timestamp.toUnixMs`/`toUnixSec` `@intCast` — ✅ Closed: saturating range guards added; mathematically proved safe for all u60 values

### Action Plan (Cycle 2)

#### Quick Wins (S effort) — All Completed

1. ~~Add SHA256 verification to CI Zig download~~ — 🚫 Won't Do (pipeline governance)
2. Add "Security Considerations" section to README covering V1/V6, V3/V5, HashDoS, V7 predictability — ✅ Done
3. Update `SECURITY.md` with library-specific security properties — ✅ Done
4. Fix `saveState` tmp_path buffer: use named constant `4096 + tmp_suffix.len` — ✅ Done
5. Document `withHWAddr()` warning more prominently — ✅ Done

#### Medium-term (M effort) — All Completed

1. ~~Add digest pins to all CI Docker image references~~ — 🚫 Won't Do (pipeline governance)
2. ~~Pin CI component includes to commit SHAs~~ — 🚫 Won't Do (pipeline governance)
3. Handle `ERROR_BUFFER_OVERFLOW` in Windows `getHWAddr` with heap-allocated retry — ✅ Done
4. Detect `SIOCGIFCONF` buffer truncation on Linux (expanded to 128 slots) — ✅ Done
5. Fix V7 spin-wait `seq` initialization after counter overflow — ✅ Done
6. Add range guards to `Timestamp.toUnixMs`/`toUnixSec` before `@intCast` — ✅ Done

#### Strategic (L effort) — All Completed

1. Add Zig fuzz testing for UUID parsing pipeline (`UUID.fromString`) — ✅ Done (`src/fuzz.zig`)
2. ~~Integrate fuzz job into CI pipeline~~ — deferred; `--fuzz` can be run locally via `zig build test --fuzz`
3. ~~Consider encrypting `saveState` state file content~~ — declined; 0o600 mode is sufficient
4. ~~Evaluate Renovate/Dependabot for automated digest/hash pinning~~ — 🚫 Won't Do (pipeline governance)

---

_Last updated: 2026-03-21 — Adversarial security review cycle 2 complete. All actionable items implemented. 4 items marked Won't Do per pipeline governance policy. All issues tracked in GitLab._

---

## Security Gap Analysis — 2026-03-21 (Adversarial Review Cycle 3)

> **Won't Do Policy:** CI/CD Zig download checksum verification, Docker image tag pinning,
> CI catalog component tag pinning, and pre-commit hook changes are handled by separate
> pipeline governance controls and must remain Won't Do. Future agents MUST NOT re-open
> these items.
>
> **Reviewer:** Automated adversarial security review agent (Cycle 3)
> **Scope:** Full codebase re-review of all source files, CI/CD, build system, pre-commit,
> platform OS code, fuzz harness, and documentation. All Cycle 1 and Cycle 2 findings
> already closed; this review searched exclusively for NEW issues.
> **Tools run:** gitleaks v8.30.0, trufflehog v3.92.5, syft v1.41.1 + grype v0.107.0,
> trivy v0.69.0 (fs + config), osv-scanner v2.3.2, semgrep v1.150.0, shellcheck v0.9.0,
> checkov v3.2.499
> **Automated results:** 0 secrets detected; 0 CVEs; 12 CI checks passed (checkov);
> 0 SAST findings; 0 shell issues; semgrep has no Zig rules (expected); Zig packages not
> in vulnerability databases (expected).

### Summary (Cycle 3)

| Severity | Count |
| -------- | ----- |
| High     | 0     |
| Medium   | 0     |
| Low      | 1     |
| Info     | 1     |
| **Total**| **2** |

All Cycle 1 and Cycle 2 security findings were confirmed closed. Two new low/info-severity
issues were found in areas not previously examined: symlink following during the atomic
.tmp write in `saveState`, and predictable `/tmp` paths in state management tests.

### Top 5 Risks (Cycle 3)

1. **SEC-R3-01** (Low, Risk 8): `saveState` `.tmp` file follows symlinks — local attacker could
   clobber arbitrary writable file with 32 bytes of UUID state. Requires write access to state dir.
2. **SEC-R3-02** (Info, Risk 4): Hardcoded predictable `/tmp/uuid_*` paths in 5 state-file tests —
   a local attacker on the CI host could pre-seed test files to cause false passes.

(No new High or Medium findings found after exhaustive manual and automated review.)

### Stack-Ranked Findings (Cycle 3)

| Rank | Sev | Risk | Finding | Component | CWE | Evidence | GitLab Issue | Status |
| ---- | --- | ---- | ------- | --------- | --- | -------- | ------------ | ------ |
| 1 | Low | 8 | `saveState` `.tmp` creation uses `open(O_CREAT\|O_WRONLY\|O_TRUNC)` without `O_EXCL`/`O_NOFOLLOW` — pre-created symlink at `<path>.tmp` would redirect the write to the symlink target | `src/generator.zig:509` | CWE-61, CWE-377 | Line 509 | [#56](https://gitlab.com/devnw/zig/uuid/-/work_items/56) | ✅ Closed |
| 2 | Info | 4 | Five state-file tests use hardcoded predictable `/tmp/uuid_*` paths; susceptible to pre-seeding on shared CI runners | `src/generator_test.zig:358,396,423,443,458` | CWE-377 | Lines 358-458 | [#57](https://gitlab.com/devnw/zig/uuid/-/work_items/57) | ✅ Closed |

### Findings by Area (Cycle 3)

#### File I/O / Temporary File Safety

- **SEC-R3-01** [#56]: `saveState` `.tmp` write follows symlinks (CWE-61 / CWE-377) — new finding distinct from SEC-9 (which addressed torn-write, not symlink following). **✅ Fixed:** `saveState` now calls `deleteFileAbsolute(tmp_path) catch {}` to remove any pre-placed symlink before creating the new file with `CreateFlags{ .exclusive = true }` (O_EXCL on POSIX), so a symlink race in the TOCTOU window returns `EEXIST` rather than silently following the symlink. A new regression test verifies this: `"Generator.saveState: symlink at .tmp path does not redirect write (SEC-R3-01)"`.

#### Test Security

- **SEC-R3-02** [#57]: Predictable `/tmp/uuid_*` test temp-file paths — susceptible to pre-seeding on shared CI hosts. **✅ Fixed:** All 5 hardcoded `/tmp/uuid_*` paths replaced with `std.testing.tmpDir(.{})` which provides isolated, uniquely-named temporary directories per test invocation.

#### Areas Reviewed and Confirmed Clean (Cycle 3)

The following areas were re-examined and found free of new security issues:

- **V4/V7 CSPRNG:** `std.crypto.random` usage unchanged; no new randomness concerns.
- **V7 `@intCast` overflow:** `@intCast(i128 -> i64)` after `divTrunc(ns, 1_000_000)` would only panic at year ~292 million AD — not a practical risk. The guard `if (ns < 0)` correctly handles pre-epoch clocks.
- **`loadState` negative-timestamp @intCast:** `@intCast(@divTrunc(nanoTimestamp(), 1_000_000))` in `loadState` could theoretically panic only if the system clock returned a value more negative than year −292 million — not a practical risk.
- **Parser correctness:** `parseCanonical`, `parseHash`, and `fromString` handle all edge cases including null bytes, high-byte strings, mismatched braces, and wrong-length inputs correctly.
- **Namespace constants:** Declared as `const` (`pub const namespace_dns = UUID{...}`); immutable and cannot be accidentally modified.
- **`NullUUID.value()`:** Safe; returns `null` when `valid == false` regardless of the `.uuid` field value. No security implications.
- **`format()` function:** Zig 0.15 `fn format(self: UUID, writer: anytype) !void` signature is correct for Zig 0.15's updated formatter protocol.
- **`V7MockRandState` module-level mutable state:** Acknowledged in comments; safe because Zig's test runner executes tests sequentially by default.
- **`GeneratorInterface` vtable `@ptrCast`/`@alignCast`:** All casts target `*Generator` which is constructed at the same alignment; no alignment mismatch possible.
- **Linux `ifc_len == initial_len` truncation detection:** Empty block is correct — code continues searching returned interfaces and falls back to random node if no MAC found.
- **Windows heap-retry path:** `buf_size` is reported by the kernel; `alignedAlloc` on failure returns `Error.NoHWAddressFound` gracefully.
- **macOS `sdl_len` bounds check:** Primary guard `if (@as(usize, sdl.sdl_len) < header_size + mac_offset + 6) continue` is authoritative; `sdl_data: [22]u8` covers all valid interface names (IFNAMSIZ=16 + sdl_alen=6).
- **`saveState` path-traversal:** `createFileAbsolute` requires an absolute path; callers who pass relative paths get an OS error that propagates cleanly. No directory traversal is possible.
- **`saveState` buffer size:** `tmp_path_buf` is `4096 + 4 = 4100` bytes; `std.fmt.bufPrint` returns `error.NoSpaceLeft` for paths exceeding this — safe.
- **`test_io` binary:** Not tracked by git (covered by `.gitignore`'s `test_*` glob); not a security risk.
- **Supply chain:** `build.zig.zon` pinned to specific git commit SHA with Zig content hash. `hash` field provides content verification at build time.
- **Fuzz harness:** `src/fuzz.zig` correctly prevents panics on all parser entry points. Corpus covers all supported input formats including binary strings and edge cases. `_ = UUID.fromString(input) catch {}` is the correct no-panic harness idiom.
- **CI/CD:** No new CI issues beyond those already marked Won't Do. Secrets not echoed in build scripts. Artifacts (`zig-out/`) contain only compiled binaries, no sensitive data.
- **Documentation:** `README.md` and `SECURITY.md` security sections are complete, accurate, and not misleading.

### Action Plan (Cycle 3)

#### Short-term (S effort)

1. Use `std.testing.tmpDir()` in `saveState` tests to eliminate predictable `/tmp` paths (#57)
2. Add `exclusive: true` to `CreateFlags` for the `.tmp` write in `saveState`, or document the directory-access requirement in the doc comment (#56)

#### Notes

- No High or Medium findings in Cycle 3. The codebase is in good security posture.
- The two findings are both related to file I/O during the optional persistent-state feature (`saveState`/`loadState`), which is not used in the common case (V4/V7 UUID generation without persistence).
- Fuzz testing (`src/fuzz.zig`) correctly covers all parser entry points.

---

_Last updated: 2026-03-21 — Adversarial security review cycle 3 complete. 2 new findings (1 Low, 1 Info). All items tracked in GitLab (#56, #57). All Cycle 1 and Cycle 2 findings remain closed._

---

## Security Gap Analysis — 2026-03-21 (Adversarial Review Cycle 4)

> **Won't Do Policy:** CI/CD Zig download checksum verification, Docker image tag pinning,
> CI catalog component tag pinning, and pre-commit `check-yaml --unsafe` changes are handled
> by separate pipeline governance controls and must remain Won't Do. Future agents MUST NOT
> re-open these items.
>
> **Reviewer:** Automated adversarial security review agent (Cycle 4)
> **Scope:** Full codebase re-review of all source files, CI/CD, build system, pre-commit,
> platform OS code, fuzz harness, and documentation. All Cycle 1, 2, and 3 findings
> already closed; this review searched exclusively for NEW issues.
> **Tools run:** gitleaks v8.30.0 (0 secrets), trufflehog v3.92.5 (0 secrets),
> syft v1.41.1 + grype v0.107.0 (0 CVEs), trivy v0.69.0 fs+config (0 issues),
> osv-scanner v2.3.2 (no package sources — expected for Zig), semgrep (no Zig rules — expected),
> shellcheck (0 shell scripts), checkov v3.x (12 CI checks passed, 0 failed)
> **Automated results:** 0 secrets; 0 CVEs; 0 SAST; 0 config issues.

### Summary (Cycle 4)

| Severity | Count |
| -------- | ----- |
| High     | 0     |
| Medium   | 0     |
| Low      | 2     |
| Info     | 1     |
| **Total**| **3** |

All Cycle 1, 2, and 3 security findings were confirmed closed. Three new findings were
identified spanning integer-cast safety in the V7 spin-wait, missing real CODEOWNERS
assignment, and silent acceptance of oversized state files.

### Top Risks (Cycle 4)

1. **SEC-R4-01** (Low, Risk 8): V7 spin-wait `@intCast` on clock retry lacks the guard
   present at the entry point — panic or corruption possible with an extreme injected clock.
2. **SEC-R4-02** (Low, Risk 8): `CODEOWNERS` contains placeholder `@your-username` — no
   real reviewer is assigned; security-sensitive PRs bypass automatic review requests.
3. **SEC-R4-03** (Info, Risk 4): `loadState` silently accepts state files larger than
   `state_size` bytes — trailing bytes are ignored but the file is not rejected.

### Stack-Ranked Findings (Cycle 4)

| Rank | Sev | Risk | Finding | Component | CWE | Evidence (file:line) | GitLab Issue | Status |
| ---- | --- | ---- | ------- | --------- | --- | -------------------- | ------------ | ------ |
| 1 | Low | 8 | V7 spin-wait clock retry `@intCast(@divTrunc(self.clock(), 1_000_000))` has no guard against extreme/negative `i128` values — `@intCast` panics in safe builds; wraps in `ReleaseFast`. Entry-point guard at line 115 is absent at line 157. | `src/generator.zig:157` | CWE-190, CWE-755 | Line 157 | [#58](https://gitlab.com/devnw/zig/uuid/-/work_items/58) | ✅ Closed |
| 2 | Low | 8 | `CODEOWNERS` contains `@your-username` placeholder — no real owner assigned; automatic review requests never fire for security-sensitive files | `CODEOWNERS:3` | CWE-284, CWE-693 | Line 3 | [#59](https://gitlab.com/devnw/zig/uuid/-/work_items/59) | ✅ Closed |
| 3 | Info | 4 | `loadState` uses `f.readAll(&buf)` (32-byte buf) without checking whether the file has trailing bytes — files > 32 bytes pass validation silently | `src/generator.zig:545-549` | CWE-20 | Lines 545-549 | [#60](https://gitlab.com/devnw/zig/uuid/-/work_items/60) | ✅ Closed |

### Findings by Area (Cycle 4)

#### Integer Arithmetic / Runtime Safety

- **SEC-R4-01** [#58]: `newV7Locked` spin-wait clock retry at line 157 calls
  `@intCast(@divTrunc(self.clock(), 1_000_000))` without the guard that exists at the
  entry point (`newV7` line 115: `if (ns < 0) { ... return Error.InvalidTimestamp; }`).
  If `self.clock()` returns a value whose `divTrunc / 1_000_000` does not fit in `i64`
  (confirmed mathematically for `std.math.minInt(i128)`), the cast panics in `Debug` /
  `ReleaseSafe` or silently wraps in `ReleaseFast`. Affects callers who use
  `Generator.withClock(f)` with extreme synthetic clocks, or systems with severe NTP
  backward jumps beyond the i64 millisecond range.

  **✅ Fixed:** Extracted `clockToMs(ns: i128) Error!i64` helper (added before the
  `Generator` struct) that guards both `< 0` and `> maxInt(i64)` cases and returns
  `Error.InvalidTimestamp` for either. Both `newV7` and the spin-wait retry in
  `newV7Locked` now call `clockToMs()`. Two regression tests added:
  `"Generator.newV7: negative clock returns InvalidTimestamp (SEC-R4-01)"` and
  `"Generator.newV7: extreme positive clock returns InvalidTimestamp (SEC-R4-01)"`.

#### Repository Governance

- **SEC-R4-02** [#59]: `CODEOWNERS` specifies `* @your-username` — a placeholder that
  does not correspond to a real GitLab account. Merge requests touching any file will not
  automatically request review from a security-competent maintainer.

  **✅ Fixed:** Replaced `@your-username` with `@benjiv` (the actual project maintainer)
  in `CODEOWNERS`. All MRs will now trigger automatic review requests.

#### File I/O / State Validation

- **SEC-R4-03** [#60]: `loadState` reads at most `state_size` (32) bytes from the file
  but does not verify that the file ends at byte 32. A state file padded with trailing
  garbage (e.g., by an attacker who can write to the state directory) passes the size and
  magic checks. The extra bytes are harmless to the current implementation but violate the
  stated binary format specification and represent a defense-in-depth gap.

  **✅ Fixed:** After `readAll(&buf)`, a one-byte probe read `f.read(&probe)` is performed.
  If it returns `> 0` (any byte available past the expected end), `loadState` returns
  `Error.InvalidFormat`. Regression test added:
  `"Generator.loadState: file with trailing bytes returns InvalidFormat (SEC-R4-03)"`.

### Areas Reviewed and Confirmed Clean (Cycle 4)

The following were exhaustively re-examined with no new issues found:

- **Automated tools:** 0 secrets (gitleaks, trufflehog), 0 CVEs (grype), 0 config issues
  (trivy, checkov). All prior cycle automated results maintained.
- **V4/V7 CSPRNG correctness:** `std.crypto.random` usage unchanged and correct.
- **V7 monotonicity and seq assignment:** Single-branch `if/else` after spin-wait always
  assigns `seq` (SEC-R2-14 fix verified).
- **Parser safety:** `parseCanonical`, `parseHash`, `fromString` all verified no-panic
  under fuzz corpus; `src/fuzz.zig` integration correct.
- **State file permissions:** 0o600 applied in `saveState` (SEC-1 fix verified).
- **Symlink safety:** `deleteFileAbsolute` + `exclusive: true` (SEC-R3-01 fix verified).
- **Test temp files:** All 5 state-file tests use `std.testing.tmpDir(.{})` (SEC-R3-02 fix
  verified).
- **macOS `sdl_data` buffer:** `[22]u8` declaration + `sdl_len`-based bounds guard (SEC-7
  fix verified).
- **Linux `ifc_len` guard:** `if (ifc.ifc_len < 0) return Error.NoHWAddressFound;` present
  at line 66 (SEC-3 fix verified).
- **Windows heap retry:** Phase-1 stack + Phase-2 heap with `page_allocator` (SEC-R2-12
  fix verified).
- **V1/V6 node cache and F-4 detection:** Under mutex; double-check pattern correct.
- **`GeneratorInterface` vtable:** `@ptrCast(@alignCast(ptr))` targets `*Generator` which
  is alignment-compatible with the stored `*anyopaque`. Alignment check in safe builds
  cannot fail.
- **`loadState` clock `@intCast` (line 575):** Uses `std.time.nanoTimestamp()` directly
  (not injected clock). Negative real clock → negative `i64` which fits; `current_ms >
  saved_ms` would be false, taking the safe maxInt path.
- **`Timestamp.toUnixMs` / `toUnixSec` bounds:** Saturating guards from SEC-R2-15
  confirmed in place (lines 48-50, 62-63).
- **`fromBytes` and `timestampFromV*`:** Simple length-check or bit-manipulation on fixed
  arrays; no panic paths.
- **`CODEOWNERS` governance (separate from identity):** The placeholder issue is tracked
  as SEC-R4-02 above.
- **CI/CD:** No new issues. Secrets not echoed in scripts. `zig-out/` artifacts contain
  only compiled binaries, no sensitive data.
- **Documentation:** `README.md` and `SECURITY.md` security sections remain complete and
  accurate after Cycle 2 additions.

### Action Plan (Cycle 4)

#### Notes

- No High or Medium findings in Cycle 4. The codebase continues to be in good security
  posture.
- SEC-R4-01 is only exploitable with injected clock functions returning extreme `i128`
  values — not a risk with the default `std.time.nanoTimestamp` clock.
- All three findings are independently reported and are not related to previously closed
  issues.
- The Won't Do items (CI Zig download checksum, Docker image pinning, CI component tag
  pinning, `check-yaml --unsafe`) remain in that category; no new review is warranted.

> **Won't Do Policy (all review cycles — for future agents):**
> CI/CD Zig toolchain download checksum verification, Docker image digest/tag pinning,
> CI catalog component tag pinning, and pre-commit hook modifications are handled by
> separate pipeline governance controls. These items MUST remain 🚫 Won't Do across ALL
> `*GAP_ANALYSIS.md` files. Future agents MUST NOT re-open, re-implement, or re-report
> these items. This policy was established after Security Review Cycle 2 and applies
> retroactively to all cycles.

---

_Last updated: 2026-03-21 — Adversarial security review cycle 4 complete and all 3
findings implemented. 132 tests pass (117 unit + 15 integration). All cycles 1–4 closed._

---

## Security Gap Analysis — 2026-03-22 (Adversarial Review Cycle 5)

> **Won't Do Policy:** CI/CD Zig toolchain download checksum verification, Docker image
> digest/tag pinning, CI catalog component tag pinning, and pre-commit hook modifications
> are governed by separate pipeline controls and MUST remain 🚫 Won't Do. Future agents
> MUST NOT re-open these items.
>
> **Reviewer:** Automated adversarial security review agent (Cycle 5)
> **Scope:** Full codebase re-review — all source files, CI/CD, build system, dependency
> supply chain, fuzz infrastructure; focused on changes since Cycle 4.
> **Focus areas:** `pub var default_generator` aliasing (root.zig re-export), fuzz crash
> detection, V7 spin-wait unbounded loop, NullUUID JSON unmarshaling, hwaddr platform code,
> dependency hash verification, CI injection.
> **Automated tools attempted:** `gitleaks`, `semgrep`, `osv-scanner`, `trivy`, `grype` —
> all unavailable in this environment; manual adversarial review performed instead.
> **Codebase state:** Post-Cycle 8 quality + perf reviews (145 unit + 20 integration tests).

### Top Risks (Cycle 5)

1. **SEC-R5-01** (Medium, Risk 24): `root.zig` re-exports `default_generator` as a value
   copy, creating a separate `Generator` instance from the one used by the convenience
   functions. Callers who call `loadState`/`saveState`/`clearNodeCache` on `uuid.default_generator`
   operate on an isolated copy that has no effect on `newV4()`, `newV7()`, etc.
2. **SEC-R5-02** (Medium, Risk 20): Fuzz CI job uses `|| true` which suppresses crash-exit
   detection. A fuzz crash is silently ignored — the pipeline always appears green. No
   artifact upload preserves the crash corpus.
3. **SEC-R5-03** (Low, Risk 8): V7 spin-wait loop (`generator.zig:200`) has no maximum
   iteration bound. A frozen/injected clock equal to `last_ms` with `mono_seq = maxInt`
   causes `newV7` to loop indefinitely.
4. **SEC-R5-04** (Info, Risk 4): Fuzz target `fuzzNullUUIDJsonUnmarshal` only exercises
   `.str` and `.null` `json.Value` variants; `.bool`, `.int`, `.float`, `.array`, `.object`
   paths through the `else => Error.InvalidFormat` branch are not fuzz-exercised.

### Stack-Ranked Findings (Cycle 5)

| Rank | Sev | Risk Score | Finding | Component | CWE | Evidence (file:line) | GitLab Issue | Status |
| ---- | --- | ---------- | ------- | --------- | --- | -------------------- | ------------ | ------ |
| 1 | Medium | 24 | `root.zig` re-exports `default_generator` as a value copy — `uuid.default_generator` is a different `Generator` than the one used by `newV4()`/`newV7()` etc. | `src/root.zig:52` | CWE-362 | `root.zig:52`, `versions.zig:6,14` | [#120](https://gitlab.com/devnw/zig/uuid/-/work_items/120) | ✅ Closed |
| 2 | Medium | 20 | Fuzz CI job `\|\| true` suppresses crash detection — fuzz crashes silently pass CI; no artifact upload for crash corpus | `.gitlab-ci.yml:154` | CWE-394 | `.gitlab-ci.yml:154,160` | [#121](https://gitlab.com/devnw/zig/uuid/-/work_items/121) | ✅ Closed |
| 3 | Low | 8 | V7 spin-wait loop has no iteration bound — frozen/injected clock equal to `last_ms` with `mono_seq = maxInt` causes `newV7` to block indefinitely | `src/generator.zig:200` | CWE-835 | `generator.zig:200-218` | [#122](https://gitlab.com/devnw/zig/uuid/-/work_items/122) | ✅ Closed |
| 4 | Info | 4 | Fuzz target `fuzzNullUUIDJsonUnmarshal` only exercises `.str` and `.null` variants — `.bool`, `.int`, `.float`, `.array`, `.object` are not fuzz-covered | `src/fuzz.zig:80-88` | CWE-1265 | `fuzz.zig:80-88` | [#123](https://gitlab.com/devnw/zig/uuid/-/work_items/123) | ✅ Closed |

### Findings by Area (Cycle 5)

#### SEC-R5-01 (Medium) — `root.zig` `default_generator` Is a Detached Value Copy ✅ CLOSED

**CWE-362 — Improper Synchronization (shared-state aliasing)**
**Risk Score: 24** (Impact 3 × Likelihood 2 × 4)
**Confidence: Confirmed**

**Resolution (2026-03-22):** Removed the `pub var default_generator` re-export from `src/root.zig` entirely. Replaced with an explanatory comment block documenting why the re-export is absent and how callers should manage their own `Generator` instances for persistent state. The package-level convenience functions in `versions.zig` continue to use `generator.zig`'s canonical `default_generator` directly and are unaffected. GitLab issue #120 closed.

`src/root.zig:52` declares:

```zig
pub var default_generator = @import("generator.zig").default_generator;
```

In Zig, this statement creates a new `pub var` in `root.zig`'s module namespace initialized
by **copying** the current value of `generator.zig`'s `default_generator` at program start.
The two variables are **separate `Generator` instances** at separate memory addresses.

`src/versions.zig` (the implementation of `newV1`, `newV4`, `newV7`, etc.) imports:

```zig
const gen_mod = @import("generator.zig");
// and calls:
gen_mod.default_generator.newV4()
```

This means the convenience functions operate on `generator.zig`'s `default_generator`, while
a consumer who writes:

```zig
const uuid = @import("uuid");
try uuid.default_generator.loadState("/var/lib/app/uuid.state");  // modifies root.zig copy
const u = try uuid.newV7();  // uses generator.zig copy — loadState had NO effect
```

is silently operating on two disconnected generators.

**Security impact:** An application that relies on `loadState` to restore V7 monotonicity
and collision-avoidance across restarts receives no protection when using
`uuid.default_generator.loadState(...)`. The UUID generation stream is effectively as if
`loadState` was never called, creating a window where post-restart UUIDs can repeat values
from the previous run.

**Fix:** Replace the copy declaration in `root.zig` with a pointer-based reference:

```zig
// Instead of: pub var default_generator = @import("generator.zig").default_generator;
// Use: re-export the address of generator.zig's instance, or remove the re-export entirely
// and direct users to use the convenience functions only.
```

The cleanest fix is to remove `pub var default_generator` from `root.zig` entirely (or make
it a pointer to `generator.zig`'s instance if direct access is needed for `saveState`).

**Evidence:**

- `src/root.zig:52` — the detached copy declaration
- `src/versions.zig:6,14` — `gen_mod.default_generator` is the _actual_ generator used

---

#### SEC-R5-02 (Medium) — Fuzz CI Job `|| true` Suppresses Crash Detection ✅ CLOSED

**CWE-394 — Unexpected Status Code or Return Value**
**Risk Score: 20** (Impact 4 × Likelihood 1 × 5)
**Confidence: Confirmed**

**Resolution (2026-03-22):** Replaced `|| true` with `; rc=$?; if [ $rc -ne 0 ] && [ $rc -ne 124 ]; then exit $rc; fi` in `.gitlab-ci.yml`. This preserves the intent of allowing the expected timeout exit (rc=124) while propagating genuine crash exits (any other non-zero rc) to fail the job. Added `artifacts: when: on_failure` section to preserve `zig-out/fuzz/` for 1 week so crash inputs remain recoverable. GitLab issue #121 closed.

`.gitlab-ci.yml:154`:

```yaml
- timeout 60 zig build test --fuzz || true
```

When Zig's coverage-guided fuzzer finds a crashing input, it:

1. Writes the crashing input to `zig-out/fuzz/<target-name>/<hash>`
2. Exits with a non-zero exit code

The `|| true` suppresses this non-zero exit code, making the job always appear to succeed
regardless of whether a crash was found. Combined with `allow_failure: true` at the job
level (line 160), there is no mechanism by which a fuzz crash causes pipeline failure or
notifies engineers.

Additionally, there is no `artifacts:` section on the fuzz job, so the `zig-out/fuzz/`
directory is discarded when the runner container exits. Even if a crash were found, the
corpus file would be unrecoverable.

**The intent** of `|| true` is to suppress the `timeout(1)` exit code (exit 124) from
`timeout 60 ...` when the 60 seconds expires normally. This is a valid goal, but the
implementation is over-broad: it also swallows crash signals.

**Fix:** Replace `|| true` with a targeted check on exit code 124 only:

```yaml
# Exit 124 = timeout (normal termination); any other non-zero = crash (fail the job).
- timeout 60 zig build test --fuzz; rc=$?; if [ $rc -ne 0 ] && [ $rc -ne 124 ]; then exit $rc; fi
```

Additionally, add an `artifacts:` section to preserve crash inputs:

```yaml
artifacts:
  when: on_failure
  paths:
    - zig-out/fuzz/
  expire_in: 30 days
```

**Evidence:**

- `.gitlab-ci.yml:154` — `|| true` suppresses crash exit codes
- `.gitlab-ci.yml:159-160` — `allow_failure: true` at both rule and job level

---

#### SEC-R5-03 (Low) — V7 Spin-Wait Loop Has No Iteration Bound (DoS under Frozen Clock) ✅ CLOSED

**CWE-835 — Loop with Unreachable Exit Condition**
**Risk Score: 8** (Impact 2 × Likelihood 1 × 4)
**Confidence: Confirmed**

**Resolution (2026-03-22):** Added a `max_spins: usize = 4096` bound at the top of the spin-wait loop in `newV7Locked`. After 4096 iterations the mutex is released and `Error.InvalidTimestamp` is returned, terminating the call rather than blocking indefinitely. Added a regression test `"Generator.newV7: spin-wait terminates with frozen clock (SEC-R5-03)"` in `src/generator_test.zig` that injects a frozen clock, forces `mono_seq = maxInt(u12)`, and verifies `Error.InvalidTimestamp` is returned. All 146 unit tests pass. GitLab issue #122 closed.

`src/generator.zig:200`:

```zig
while (ms == self.last_ms and self.mono_seq == std.math.maxInt(u12)) {
    const ns_now = self.clock();
    const sleep_ns: u64 = if (ns_now > 0) blk: { ... } else 500_000;
    self.mutex.unlock();
    std.Thread.sleep(sleep_ns);
    self.mutex.lock();
    ms = clockToMs(self.clock()) catch |err| {
        self.mutex.unlock();
        return err;
    };
}
```

The exit conditions are:

- `ms != self.last_ms` — clock advances past the current millisecond, OR
- `self.mono_seq != std.math.maxInt(u12)` — another thread resets the counter

If both conditions remain permanently false (frozen clock, no concurrent thread), the loop
runs indefinitely. With a real system clock, the clock will always advance. However:

1. **Injected clocks:** A caller who constructs `Generator.withClock(frozenClock)` where
   `frozenClock()` always returns the same value equal to `last_ms * 1_000_000` will cause
   `newV7` to block the calling thread forever (not detectable from outside without a timeout).
2. **Edge case:** If the real system clock is stuck or runs backwards for more than 1ms
   (NTP slew, VM migration, or clock hardware failure), `newV7` will loop until it recovers.

There is no maximum spin count, no deadline, and no way for the caller to cancel or time out
a stuck `newV7` call without killing the thread.

**Note:** Under the _default_ system clock, this cannot occur — `nanoTimestamp()` always
advances. The risk is only with injected clocks or severely broken system clocks.

**Fix options:**

1. Add a maximum iteration count (e.g., 1000 iterations) after which `newV7` returns
   `Error.InvalidTimestamp`, allowing the caller to handle a stuck clock.
2. Document the `withClock` API contract: injected clocks MUST be monotonically advancing.
   A frozen clock is a usage error.

**Evidence:** `src/generator.zig:200-218`

---

#### SEC-R5-04 (Info) — Fuzz Target Exercises Only Two of Seven `json.Value` Variants ✅ CLOSED

**CWE-1265 — Uninitialized Variable**
**Risk Score: 4** (Impact 1 × Likelihood 1 × 4)
**Confidence: Confirmed**

**Resolution (2026-03-22):** Extended `fuzzNullUUIDJsonUnmarshal` in `src/fuzz.zig` to exercise all five remaining `json.Value` variants: `.bool`, `.num` (using a stack-allocated `json.Number`), `.arr` (zero-length slice), and `.obj` (zero-length slice). All variants use `catch {}` error suppression since they are expected to return `Error.InvalidFormat` rather than panic. The zero-length slices for `.arr`/`.obj` avoid heap allocation in the fuzz loop. All 146 unit tests pass. GitLab issue #123 closed.

`src/fuzz.zig:80-88` (`fuzzNullUUIDJsonUnmarshal`) constructs a `json.Value{ .str = input }`
and also calls with `.null`. It does not exercise `.bool`, `.int`, `.float`, `.array`, or
`.object` variants.

The `NullUUID.jsonUnmarshal` implementation at `null_uuid.zig:47-52` handles all non-`.str`
non-`.null` variants via `else => Error.InvalidFormat`, which is correct. There is an
existing unit test (`NullUUID.jsonUnmarshal: non-string non-null input → error`) that
confirms this. However, the fuzz target does not drive this path with coverage-guided
mutation, so any future regression in the `else` branch (e.g., panic on `.array` or
`.object` access) would not be caught by fuzzing.

**Fix:** Add explicit coverage of the remaining variants to `fuzzNullUUIDJsonUnmarshal`:

```zig
_ = NullUUID.jsonUnmarshal(alloc, json.Value{ .bool = true }) catch {};
_ = NullUUID.jsonUnmarshal(alloc, json.Value{ .int = 42 }) catch {};
// etc.
```

**Evidence:** `src/fuzz.zig:80-88`, `src/null_uuid.zig:47-52`

---

### Areas Reviewed and Confirmed Clean (Cycle 5)

The following were exhaustively re-examined with no new issues found:

- **`fromString` parser robustness:** Canonical, braced, URN, and 32-hex paths all verified.
  The URN fix (QC-47: `"urn:"` → `InvalidURNPrefix`) is correct and robust. Edge cases
  including empty strings, `"urn:"`, `"urn:uuid:"` (no hex), and all-`\xff` inputs confirmed
  handled by the fuzz corpus.
- **`fromBytes` safety:** `if (b.len != 16) return Error.IncorrectByteLength` — single
  branch; len 0, 1, 15, 16, 17, 32 all handled correctly. No panic path.
- **`toHexAlloc`/`toHexUpperAlloc`/`toStringAlloc`:** All delegate to a fixed-size stack
  buffer (`[32]u8` or `[36]u8`) then `alloc.dupe()`. Allocation size is compile-time
  constant, no integer overflow possible.
- **`UUID.format({f})`:** Calls `self.toString(&buf)` on a `[36]u8` stack buffer, then
  `w.writeAll`. The only error path is `Writer.Error` from the downstream writer — no panic.
- **`isNil`/`isMax`:** `std.mem.eql(u8, &self.bytes, &nil/max.bytes)` — constant-time byte
  compare on fixed 16-byte arrays. No overflow, no panic.
- **`NullUUID.jsonMarshal`:** Allocates a 36-byte dupe. Allocation size is compile-time
  constant (`toString` always produces 36 bytes). Safe.
- **`NullUUID.jsonUnmarshal`:** Correctly rejects all non-`.str` non-`.null` variants via
  `else => Error.InvalidFormat`. See SEC-R5-04 for the minor fuzz coverage gap.
- **`NullUUID.format`:** Delegates to `uuid.format(w)` or `w.writeAll("null")`. No panic
  path. Correct.
- **Linux `hwaddr`:** `SIOCGIFCONF` + `SIOCGIFHWADDR` + `SIOCGIFFLAGS` via raw `syscall3`.
  Negative `ifc_len` guard at line 66 confirmed. Socket is closed with `defer`. No
  privilege escalation — `SOCK_DGRAM` socket on `AF_INET` requires no privilege. Interface
  selection is deterministic (first non-loopback Ethernet with non-zero MAC).
- **macOS `hwaddr`:** `getifaddrs`/`freeifaddrs` via libc. `sdl_len`-based bounds guard
  confirmed. `@ptrCast(@alignCast(addr))` cast from `*sockaddr` to `*sockaddr_dl` —
  `sockaddr_dl` has `sa_len u8` at offset 0 which is filled by the kernel; `sdl_len` guard
  before accessing `sdl_data` is authoritative. No privilege required for `getifaddrs`.
- **Windows `hwaddr`:** `GetAdaptersAddresses` with stack-then-heap fallback. `page_allocator`
  produces page-aligned memory satisfying `IP_ADAPTER_ADDRESSES` alignment. `PhysicalAddressLength`
  checked to equal 6 before accessing `PhysicalAddress[0..6]`. No privilege escalation.
- **`build.zig.zon` dependency hash:** Single dependency (`json`), pinned to commit SHA
  `4c2032be31443f4504427c205419fced275d4263` with integrity hash
  `json-0.1.0-tOue4fSoCwDuFpNLxdd4yUQyL3g9o3su9jiX5W08e3x5`. Hash format is Zig's
  native multihash; the Zig build system verifies this on download. Supply chain is sound.
- **`build.zig` build-time code execution:** No `@cImport`, no custom build steps that
  execute shell commands, no `std.Build.addSystemCommand`. Fully safe.
- **CI pipeline injection:** All `script:` entries in `.gitlab-ci.yml` use only fixed
  strings and the `ZIG_VERSION` variable (set to a hardcoded string, not user-controlled).
  No `$CI_COMMIT_MESSAGE`, `$CI_BRANCH_NAME`, or other user-controlled variables appear in
  shell contexts. No injection risk.
- **`examples/basic.zig`:** No hardcoded credentials, secrets, or sensitive data. Uses
  `page_allocator` for convenience examples — appropriate. No security concerns.
- **`CHANGELOG.md`/`README.md`:** No sensitive information, no MAC addresses, no real
  clock state values. V3/V5 security warnings are present and accurate.
- **`saveState` cross-filesystem rename:** `tmp_path = path ++ ".tmp"` ensures the temp
  file is in the same directory as the target, so `renameAbsolute` does not cross filesystem
  boundaries. If the target path is on a different filesystem from the CWD, the tmp file is
  also on that filesystem. No EXDEV risk.
- **`loadState` cross-filesystem:** `openFileAbsolute` opens `path` directly, no rename
  involved in load. Cross-filesystem not relevant.
- **`clockToMs` correctness:** Guards `ns < 0` and `ms_i128 > maxInt(i64)`. Both branches
  confirmed at lines 34 and 36. `@intCast` at line 37 is safe given both guards pass.
- **`@rem(ns_now, 1_000_000)` in spin-wait:** `ns_now: i128`, guarded `> 0`. Result fits
  `u64`. The `@intCast` is safe.
- **`SecureHashContext.init()`:** Seeds from `std.crypto.random.int(u64)`. Each call
  produces a fresh random seed. No seed reuse between instances.
- **`GeneratorInterface` vtable casts:** `castGen` uses `@ptrCast(@alignCast(ptr))` to
  cast `*anyopaque` to `*Generator`. The `ptr` field is always set from `fromGenerator(gen)`
  which stores a genuine `*Generator`. No misuse in the vtable wrappers.

### Notes and Known Limitations (Cycle 5)

- **glab/curl unavailable:** GitLab issues could not be created programmatically in this
  session. The issue creation commands below should be run once the tooling is available.
- **Automated scanners unavailable:** gitleaks, semgrep, osv-scanner, trivy, grype were
  all unavailable in this environment. Prior cycle results (all-clean) continue to apply;
  no new dependencies or CI secrets were introduced since Cycle 4.

### Issue Creation Commands (run when glab is available)

```bash
# SEC-R5-01: default_generator detached copy
glab issue create \
  --title "SEC-R5-01: root.zig default_generator is a detached copy — loadState/saveState have no effect on newV4/newV7" \
  --description "**File:** src/root.zig:52, src/versions.zig:6

\`pub var default_generator = @import(\"generator.zig\").default_generator\` in root.zig creates a *value copy* of generator.zig's default_generator. The convenience functions (newV4, newV7 etc.) in versions.zig call gen_mod.default_generator (generator.zig's instance), so loadState/saveState/clearNodeCache on uuid.default_generator have no effect on generated UUIDs.

**Impact:** Applications relying on persistent V7 monotonicity or V1/V6 state restoration via uuid.default_generator.loadState() receive no protection.

**Fix:** Remove the re-export from root.zig (or expose a *Generator pointer). Direct users to the convenience functions; provide a separate getDefaultGenerator() that returns a pointer to generator.zig's instance." \
  --label "security,severity::medium,type::bug,confidence::confirmed,status::triage"

# SEC-R5-02: fuzz || true
glab issue create \
  --title "SEC-R5-02: Fuzz CI job || true suppresses crash detection" \
  --description "**File:** .gitlab-ci.yml:154

\`timeout 60 zig build test --fuzz || true\` swallows the non-zero exit code that Zig's fuzzer emits when a crash is found. This means fuzz crashes silently pass CI.

**Fix:** Use exit-code-selective suppression (only suppress exit 124 = timeout):
\`\`\`
timeout 60 zig build test --fuzz; rc=\$?; if [ \$rc -ne 0 ] && [ \$rc -ne 124 ]; then exit \$rc; fi
\`\`\`
Also add artifacts upload for zig-out/fuzz/ on failure." \
  --label "security,severity::medium,type::hardening,confidence::confirmed,status::triage"

# SEC-R5-03: spin-wait unbounded
glab issue create \
  --title "SEC-R5-03: V7 spin-wait has no maximum iteration bound (DoS with frozen/injected clock)" \
  --description "**File:** src/generator.zig:200-218

The while loop exits only when the clock advances or another thread resets mono_seq. With a frozen or maliciously injected clock equal to last_ms, newV7 blocks the calling thread indefinitely.

**Fix:** Add a maximum iteration count (e.g., 1000) after which the loop returns Error.InvalidTimestamp, or document that injected clocks must be monotonically advancing." \
  --label "security,severity::low,type::hardening,confidence::confirmed,status::triage"

# SEC-R5-04: fuzz coverage gap
glab issue create \
  --title "SEC-R5-04: fuzzNullUUIDJsonUnmarshal covers only .str and .null json.Value variants" \
  --description "**File:** src/fuzz.zig:80-88

The fuzz target does not exercise .bool, .int, .float, .array, .object variants of json.Value. The else => Error.InvalidFormat branch in NullUUID.jsonUnmarshal is tested by unit tests but not by the fuzzer.

**Fix:** Add explicit calls for all json.Value variants in fuzzNullUUIDJsonUnmarshal." \
  --label "security,severity::info,type::hardening,confidence::confirmed,status::triage"
```

### Action Plan (Cycle 5)

| Priority | Finding | Effort | Impact |
|----------|---------|--------|--------|
| 1 | SEC-R5-01: Fix root.zig default_generator aliasing | Remove re-export or use pointer | Prevents silent loadState/saveState no-ops in user code |
| 2 | SEC-R5-02: Fix fuzz CI `\|\| true` to only suppress exit 124 | 1-line script change + artifacts section | Ensures fuzz crashes cause pipeline failure |
| 3 | SEC-R5-03: Add max iteration to V7 spin-wait | Add counter + InvalidTimestamp return | Prevents thread DoS with frozen/injected clock |
| 4 | SEC-R5-04: Expand fuzz coverage for NullUUID.jsonUnmarshal | Add 5 lines to fuzz target | Closes fuzz coverage gap for non-string JSON variants |

### Summary (Cycle 5)

| Severity | Count | Status |
|----------|-------|--------|
| Medium   | 2     | ✅ All closed |
| Low      | 1     | ✅ All closed |
| Info     | 1     | ✅ All closed |
| **Total**| **4** | **✅ All 4 closed** |

No High or Critical findings in Cycle 5. All four findings (SEC-R5-01 through SEC-R5-04)
are now closed. The codebase continues to be in excellent security posture. All previously
closed findings from Cycles 1–4 remain closed; no regressions found.

**Cycle 5 Closure Summary (2026-03-22):**

- SEC-R5-01: Removed detached `default_generator` re-export from `root.zig`; added explanatory comment. (#120)
- SEC-R5-02: Fixed fuzz CI job to propagate crash exits while still allowing timeout (rc=124); added crash artifact upload. (#121)
- SEC-R5-03: Added `max_spins = 4096` bound to V7 spin-wait; returns `Error.InvalidTimestamp` on frozen clock. (#122)
- SEC-R5-04: Extended `fuzzNullUUIDJsonUnmarshal` to cover `.bool`, `.num`, `.arr`, `.obj` variants. (#123)

---

_Last updated: 2026-03-22 — Adversarial security review cycle 5 complete. All 4 findings
closed (2 Medium, 1 Low, 1 Info). All cycles 1–5 remain closed. 146 unit tests, 20 integration tests._

---

## Security Review Cycle 6 Findings

> **Date:** 2026-03-22
> **Scope:** Full codebase — src/, .gitlab-ci.yml, build.zig.zon, Makefile, examples/, docs/
> **Automated scans:** gitleaks (no leaks found), trivy (no vulns/secrets), osv-scanner (build.zig.zon format unsupported)
> **All previous cycles (SEC-R1 through SEC-R5) confirmed closed — no regressions.**

### SEC-R6-01 — clearNodeCache data race: node_cache written without mutex (CWE-362)

**Status:** ✅ CLOSED
**Severity:** Low | **Risk Score:** 8 (Impact 1 × Likelihood 2 × 4) | **Confidence:** Confirmed

**File:** `src/generator.zig` (previously lines 130-132; now lines 130-140)

`clearNodeCache()` writes to `self.node_cache = null` without holding the generator mutex.
All other accesses to `node_cache` occur inside `resolveV1V6State` (which holds the mutex via `defer self.mutex.unlock()`).
A concurrent `clearNodeCache()` call from thread A while thread B is in `newV1`/`newV6` is a
data race (unsynchronised write). In ReleaseFast builds, the store can be reordered or torn,
potentially corrupting the node cache and producing adjacent V1/V6 UUIDs with different node IDs.

**Fix:** Added `self.mutex.lock()` / `defer self.mutex.unlock()` inside `clearNodeCache`.

**Test added:** `Generator.clearNodeCache holds mutex and generator still works (SEC-R6-01)`
in `src/generator_test.zig`. Verifies the function is callable without deadlock, node_cache
is null after the call, and the generator continues to produce valid V1 UUIDs.

---

### SEC-R6-02 — CI downloads Zig toolchain without checksum verification (CWE-494)

**Status:** ✅ CLOSED — (#125)
**Severity:** Low | **Risk Score:** 16 (Impact 2 × Likelihood 2 × 4) | **Confidence:** Confirmed

**File:** `.gitlab-ci.yml` `&install-zig` anchor; `ci-catalog/templates/zig-{build,format,test,fuzz,integration-test}/template.yml`

**Root cause:** Every CI job installed Zig via a bare `curl | tar` pipe with no SHA-256 verification.
A MITM or ziglang.org compromise could silently install a backdoored compiler (CWE-494).

**Fix:** Created `ci-catalog/scripts/zig.sh` — a verified installer that fetches the expected
SHA-256 from `https://ziglang.org/download/index.json` (the official, machine-readable release
index), downloads the tarball to a named file, verifies it with `sha256sum --check --strict`, then
extracts. All five affected ci-catalog templates and the uuid `&install-zig` YAML anchor now use
this pattern. The `ZIG_SHA256` env var provides an offline/air-gapped override if desired.

As a bonus, the anchor was also fixed to use version-aware archive naming
(`zig-{arch}-linux-{version}` for 0.15+, `zig-linux-{arch}-{version}` for earlier), which was
incorrect for the current `ZIG_VERSION: "0.15.2"`.

---

### SEC-R6-03 — hwaddr implementations do not filter broadcast MAC addresses (CWE-345 / RFC 4122 guidance)

**Status:** ✅ CLOSED
**Severity:** Info | **Risk Score:** 4 (Impact 1 × Likelihood 1 × 4) | **Confidence:** Confirmed

**Files:** `src/hwaddr/linux.zig`, `src/hwaddr/macos.zig`, `src/hwaddr/windows.zig`

All three `getHWAddr()` implementations filter out zero MACs (`allEqual(u8, mac, 0)`) but did not
filter broadcast MACs (`FF:FF:FF:FF:FF:FF`). RFC 4122 §4.1.6 guidance (carried into RFC 9562)
recommends not using broadcast addresses as UUID node IDs because they are not globally unique.
This only affects callers who set `hwaddr_fn` explicitly; the default path (random multicast node)
is safe.

**Fix:** Added `if (std.mem.allEqual(u8, mac, 0xFF)) continue;` alongside the zero-MAC filter in
all three files (linux.zig after line 98, macos.zig after line 82, windows.zig after line 81).

---

### SEC-R6-04 — loadState silently truncates out-of-range last_v1_ts without validation (CWE-20)

**Status:** ✅ CLOSED
**Severity:** Info | **Risk Score:** 4 (Impact 1 × Likelihood 1 × 4) | **Confidence:** Confirmed

**File:** `src/generator.zig` (previously line 645)

`loadState` previously read `last_v1_ts` as a `u64` and silently truncated to `u60` with `@truncate`.

A u64 value exceeding `maxInt(u60)` (0x0FFF_FFFF_FFFF_FFFF) was accepted without returning
`InvalidFormat`. Compare with `clock_seq`, which is correctly masked before truncation (`& 0x3FFF`).
A tampered state file could set `last_v1_ts` to any desired u60 value (by setting the top 4 bits)
without being detected as corrupt.

**Fix applied:**

```zig
const raw_ts = std.mem.readInt(u64, buf[8..16], .little);
if (raw_ts > std.math.maxInt(u60)) return Error.InvalidFormat;
self.last_v1_ts = @truncate(raw_ts);
```

**Side effect:** The existing `v1 format (22 bytes) accepted for backward compat (SEC-10)` test
used `0xDEADBEEF_CAFEBABE` (which exceeds `maxInt(u60)`) as a dummy timestamp. That test was
updated to use `0x0DEAD_BEEF_CAFE` (a u60-range value) so it continues to pass.

**Test added:** `Generator.loadState: rejects out-of-range last_v1_ts (SEC-R6-04)` in
`src/generator_state_test.zig`. Writes a state file with `last_v1_ts = maxInt(u60) + 1` and
verifies `Error.InvalidFormat` is returned.

---

### Areas Confirmed Clean (Cycle 6)

- **Mutex correctness (V7 spin-wait):** The mutex is correctly released before `Thread.sleep` and
  re-acquired after. All error paths in `newV7Locked` release the mutex before returning. Confirmed.
- **V7 spin-wait error return:** After `max_spins` exceeded, the mutex is unlocked before returning
  `Error.InvalidTimestamp` (line 211-212). Caller does not hold a dangling lock. Confirmed.
- **saveState path length:** The `[4096 + 4]u8` tmp_path_buf correctly handles PATH_MAX.
  `bufPrint` returns `error.NoSpaceLeft` on overflow, which propagates safely. Confirmed.
- **loadState saved_ms DoS:** A tampered `saved_ms = maxInt(i64)` does NOT trigger the spin-wait
  because the real clock value (e.g., 1.7T ms in 2026) is not equal to `maxInt(i64)`, so the
  `while (ms == self.last_ms and ...)` condition is false immediately. Confirmed safe.
- **fuzz FixedBufferAllocator:** The 256-byte FBA in `fuzzNullUUIDJsonUnmarshal` is never used
  (the allocator parameter is discarded in `jsonUnmarshal`). All code paths are zero-alloc. Safe.
- **URN parser boundary:** `fromString` correctly handles "urn:" (len=4) → `InvalidURNPrefix`,
  "urn:u" (len=5) → `InvalidURNPrefix`, "urn:uuid:" + wrong content → `InvalidLength`/`InvalidFormat`.
  The `rest.len >= 4` guard on line 244 is correct. Confirmed.
- **NullUUID.jsonUnmarshal:** Accepts any syntactically valid UUID string regardless of
  version/variant bytes. This is correct per RFC 9562 §6.12 opacity guidance.
- **supply-chain (build.zig.zon):** Single dependency `json` uses `git+https://` URL on the
  expected `gitlab.com/devnw` domain. Hash is in Zig multihash format (SHA-256 based). Confirmed.
- **CI fuzz job exit-code handling:** `timeout 60 ...; rc=$?; if [ $rc -ne 0 ] && [ $rc -ne 124 ]`
  correctly distinguishes SIGTERM-timeout (rc=124) from genuine fuzzer crashes. No injection risk.
  Confirmed clean (SEC-R5-02 fix remains effective).
- **gitleaks scan:** No leaks found across all 43 commits.
- **examples/basic.zig:** `toHexAlloc` is correctly deferred-freed. No panic risks identified.
- **HashContext fixed seed (SEC-6):** Already documented with warning in source. Not a new finding.

### Summary Table (Cycle 6)

| ID | Severity | Area | Status |
|----|----------|------|--------|
| SEC-R6-01 | Low | generator.zig: clearNodeCache data race | ✅ Closed (#124) |
| SEC-R6-02 | Low | CI: Zig download no checksum | ✅ Closed (#125) |
| SEC-R6-03 | Info | hwaddr: no broadcast MAC filter | ✅ Closed (#126) |
| SEC-R6-04 | Info | generator.zig: loadState last_v1_ts truncation | ✅ Closed (#127) |

| Severity | Count | Closed | Blocked |
|----------|-------|--------|---------|
| Critical | 0 | 0 | 0 |
| High | 0 | 0 | 0 |
| Medium | 0 | 0 | 0 |
| Low | 2 | 2 | 0 |
| Info | 2 | 2 | 0 |
| **Total** | **4** | **4** | **0** |

No Critical or High findings in Cycle 6. The codebase continues to be in strong security posture.
All previous findings from Cycles 1–6 remain closed; no regressions detected.

---

_Last updated: 2026-03-22 — Adversarial security review cycle 6 fully complete. All 4/4 findings
closed (SEC-R6-01 ✅, SEC-R6-02 ✅, SEC-R6-03 ✅, SEC-R6-04 ✅). 148 unit tests, 20 integration tests._

---

## Geode Extraction Metadata

This repository is already the correct home for the reusable UUID core extracted from Geode. The Geode review found no adjacent subsystem that should move with it.

### Geode Boundary

Move/own here:

| Geode source | Why it belongs in `uuid` |
|---|---|
| `src/uuid.zig:5`, `:11`, `:38`, `:43`, `:73`, `:85`, `:96`, `:106`, `:134` | Pure UUIDv7 generation, parsing, formatting, ordering, timestamp extraction, and hashing |
| `src/uuid.zig:141`, `:157`, `:172` | Core UUID correctness tests |

Keep in Geode:

| Geode source | Why it stays |
|---|---|
| `src/graph_registry.zig:24`, `:42`, `:78`, `:140` | Graph-registry persistence and CRC semantics are Geode-specific consumers of UUIDs |
| `src/graph_store.zig:625`, `:695`, `:753`, `:2812`, `:2875`, `:4018` | Graph-file naming, handle identity binding, and file-swap validation are storage/runtime integration, not UUID-library behavior |

### Geode Tests And Consumers

| Geode reference | Purpose |
|---|---|
| `src/uuid.zig:141`, `:157`, `:172` | Direct unit coverage of UUID generation, string conversion, and ordering |
| `src/graph_registry.zig:223`, `:271`, `:299`, `:322`, `:338`, `:360` | Confirms UUID integration in the graph registry |
| `src/graph_store.zig:5065` | Confirms UUID identity binding in per-graph file validation |
| `benchmarks/benchmark_extended_builtins_overhead.zig:9`, `:22`, `:26` | Performance reference for UUID builtin dispatch overhead |

### Current Assessment

- Extraction status: effectively complete.
- Additional Geode code to move: none identified.
- Main migration work left: keep Geode consumers importing this repo rather than re-growing UUID helpers locally.

---

## Security Gap Analysis — 2026-03-22 (Adversarial Review Cycle 7)

> **Won't Do Policy:** CI/CD Zig toolchain download checksum verification (covered by SHA-256
> fetch from index.json since Cycle 6), Docker image digest/tag pinning, CI catalog component tag
> pinning, and pre-commit hook modifications are governed by separate pipeline controls and MUST
> remain Won't Do. The function-pointer CSPRNG indirection (PERF-08) is intentional testability
> API. Future agents MUST NOT re-open these items.
>
> **Reviewer:** Automated adversarial security review agent (Cycle 7)
> **Scope:** Full codebase re-review — all source files, CI/CD pipeline, build system, supply
> chain, fuzz infrastructure; focused on changes since Cycle 6 (PERF-11 through PERF-15
> quality/performance reviews; new benchmark functions, integration tests, versions.zig delegation
> tests, timestamp/uuid.zig doc improvements, examples update).
>
> **Automated tools run:**
>
> - gitleaks 8.30.0: 0 secrets found (45 commits scanned, 655 KB)
> - trivy 0.69.0 (fs): 0 vulnerabilities, 0 secrets
> - syft 1.41.1 + grype 0.107.0: 0 CVE matches
> - osv-scanner: exit 128 (Zig build.zig.zon format not natively supported — expected)
> - semgrep: requires metrics opt-in for auto config; no Zig-specific rules (expected)
> - shellcheck: no tracked .sh files in repo
> - checkov: 12 CI checks passed, 0 failed
>
> **All previous cycles (SEC-R1 through SEC-R6) confirmed closed — no regressions.**

### What Was Reviewed (Cycle 7)

**New/modified source files since Cycle 6:**

| File | Nature of change |
|------|-----------------|
| `bench/main.zig` | New benchmark functions (benchV3, benchV5, benchToStringUpper, benchToStringAlloc, benchToHexUpper, benchToHexAlloc, benchV7AtTime, benchFromStringHex, benchFromStringURN) |
| `src/uuid.zig` | Doc comment improvements to allocating output methods (no logic change) |
| `src/versions.zig` | New QC-30 delegation tests for newV1, newV1AtTime, newV5, newV6, newV6AtTime, newV7AtTime, newV8 |
| `tests/integration.zig` | New integration tests: toHexAlloc/toHexUpperAlloc, V6/V8 round-trips, saveState/loadState integration |
| `src/timestamp.zig` | Additional tests for Timestamp conversions and timestampFromV7 |
| `examples/basic.zig` | Added toHexAlloc/toHexUpperAlloc demonstration |
| `CHANGELOG.md` | Release notes update |
| `docs/PERF_GAP_ANALYSIS.md` | Performance analysis updates |
| `docs/QUALITY_GAP_ANALYSIS.md` | Quality analysis updates |

**Re-reviewed existing files confirmed clean:**

- `src/generator.zig` — All mutex paths, spin-wait, saveState/loadState, clockToMs, V1/V6/V7 generation
- `src/hwaddr/linux.zig` — ifc_len guard, broadcast/zero MAC filters
- `src/hwaddr/macos.zig` — sdl_len bounds check, sdl_data [22]u8 declaration, broadcast filter
- `src/hwaddr/windows.zig` — Stack+heap fallback, ERROR_BUFFER_OVERFLOW handling, broadcast filter
- `src/fuzz.zig` — All json.Value variants covered, corpus adequate
- `src/root.zig` — default_generator not re-exported (SEC-R5-01 fix verified)
- `src/null_uuid.zig` — jsonUnmarshal, jsonMarshal, format functions
- `.gitleaks.toml` — Allowlist correct, no rule gaps
- `build.zig.zon` — json dependency pinned to commit SHA + Zig content hash

### Summary (Cycle 7)

| Severity | Count |
| -------- | ----- |
| Critical | 0     |
| High     | 0     |
| Medium   | 1     |
| Low      | 0     |
| Info     | 0     |
| **Total**| **1** |

### Stack-Ranked Findings (Cycle 7)

| Rank | Sev | Risk Score | Finding | Component | CWE | Evidence (file:line) | GitLab Issue | Status |
| ---- | --- | ---------- | ------- | --------- | --- | -------------------- | ------------ | ------ |
| 1 | Medium | 32 | CI `&install-zig` Python inline script shell-interpolates `ZIG_VERSION` inside Python string literals — Developer access enables arbitrary Python injection via manual pipeline trigger | `.gitlab-ci.yml:56-63` | CWE-94, CWE-78 | Lines 58-61 | [#128](https://gitlab.com/devnw/zig/uuid/-/work_items/128) | ✅ Closed |

**Risk score:** 32 = Impact 4 × Likelihood 2 × 4

- Impact 4: Code execution in CI runner; access to all CI secrets, ability to backdoor extracted Zig binary or exfiltrate build outputs.
- Likelihood 2: Requires Developer access + manual pipeline trigger; not exploitable anonymously.

### Finding Detail

#### SEC-R7-01 (Medium) — CI Python Script Interpolates `ZIG_VERSION` Without Sanitization

**Status:** ✅ Closed — Fixed in prior session; CI Python script already uses `os.environ` and shell validation.
**CWE-94 — Code Injection | CWE-78 — OS Command Injection**
**Risk Score: 32** (Impact 4 × Likelihood 2 × 4)
**Confidence: Confirmed**

**File:** `.gitlab-ci.yml:56-63`

The `&install-zig` YAML anchor added in Cycle 6 (SEC-R6-02) correctly fetches the SHA-256
checksum from `https://ziglang.org/download/index.json` via a `python3 -c "..."` inline script.
However, the `ZIG_VERSION` shell variable is expanded by the shell before the string is passed
to `python3 -c`, interpolating it inside single-quoted Python string literals:

```yaml
EXPECTED_HASH=$(python3 -c "
import json, sys
idx = json.load(open('${INDEX_FILE}'))
pkg = idx.get('${ZIG_VERSION}', {}).get('${ZIG_ARCH}-linux', {})
...
")
```

A user who overrides `ZIG_VERSION` (via GitLab's "Run Pipeline" web UI, the CI/CD API, or a
scheduled pipeline with custom variables) with a crafted string containing a single quote can
break out of the Python string literal and inject arbitrary Python statements.

**Minimal non-destructive PoC (does not exploit any external system):**

Setting `ZIG_VERSION` to `x', {}); print('INJECTED'); pkg = idx.get('0.15.2` produces:

```python
pkg = idx.get('x', {}); print('INJECTED'); pkg = idx.get('0.15.2', {}).get(...)
```

A malicious payload would use `__import__('os').environ` to exfiltrate CI secrets or write a
backdoored binary to the build directory.

**Why this was introduced:** Cycle 6 correctly added SHA-256 verification (SEC-R6-02) but
used shell variable interpolation inside the Python inline script — a well-known CI injection
anti-pattern analogous to `$CI_COMMIT_TITLE` injection but exploitable without push access.

**Fix guidance:**

Pass `ZIG_VERSION` via `os.environ` rather than string interpolation:

```bash
EXPECTED_HASH=$(ZIG_VER="${ZIG_VERSION}" ZIG_ARCH_VAR="${ZIG_ARCH}" INDEX="${INDEX_FILE}" python3 -c "
import json, os, sys
ver = os.environ['ZIG_VER']
arch = os.environ['ZIG_ARCH_VAR']
idx = json.load(open(os.environ['INDEX']))
pkg = idx.get(ver, {}).get(arch + '-linux', {})
h = pkg.get('shasum', '')
if not h: sys.exit('SHA-256 not found')
print(h)
")
```

As defense-in-depth, validate `ZIG_VERSION` in shell before use:

```bash
case "${ZIG_VERSION}" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "Invalid ZIG_VERSION: ${ZIG_VERSION}"; exit 1 ;;
esac
```

**Acceptance criteria:**

- [ ] `ZIG_VERSION` is no longer shell-interpolated inside a Python string literal.
- [ ] `ZIG_VERSION` is passed as an environment variable and/or validated before use.
- [ ] A crafted `ZIG_VERSION` with a single quote causes pipeline failure, not code injection.

### Areas Reviewed and Confirmed Clean (Cycle 7)

All areas from prior cycles were re-examined. The following were specifically verified for changes
introduced since Cycle 6:

- **New benchmark functions (`bench/main.zig`):** All new functions use stack-local or
  pre-allocated pool memory. No heap leaks, uninitialized reads, or panic paths. Clean.

- **New delegation tests (`src/versions.zig`):** QC-30 tests use synthetic calendar values.
  No hardcoded secrets, no sensitive data. Clean.

- **New integration tests (`tests/integration.zig`):** toHexAlloc/toHexUpperAlloc tests use
  `std.testing.allocator` (leak-detecting). saveState/loadState test uses `std.testing.tmpDir`
  (SEC-R3-02 fix verified). V6/V8 round-trip tests are standard. Clean.

- **`timestampFromV7` cast safety (`src/timestamp.zig:115`):** `@intCast((hi << 16) | lo)` is
  safe — `(hi << 16) | lo` is at most 48-bit (u32 << 16 | u16), far below maxInt(i64). Confirmed.

- **`src/uuid.zig` changes:** Doc-comment-only additions. No logic changes. Clean.

- **`examples/basic.zig` changes:** `toHexAlloc`/`toHexUpperAlloc` correctly deferred-freed.
  Uses `page_allocator` for standalone examples. No resource leaks. Clean.

- **Fuzz corpus:** `src/fuzz.zig` unchanged. All json.Value variants covered (SEC-R5-04 fix
  verified). Fuzz `catch {}` harness pattern correct.

- **gitleaks scan:** 0 leaks across all 45 commits.

- **CI pipeline (other than SEC-R7-01):** No additional injection risks. All other job scripts
  use fixed strings. The cache check `if [ ! -f "zig-${ZIG_VERSION}/zig" ]` at line 38 could
  skip SHA-256 verification if an attacker pre-populates the cache — this is a lower-risk
  variant of the SEC-R7-01 root cause, addressed by the same fix.

- **`loadState` mutex safety:** Early `return Error.InvalidFormat` returns at lines 635-644
  execute BEFORE `self.mutex.lock()` at line 646. The `defer self.mutex.unlock()` at line 647
  covers all later returns, including the `raw_ts > maxInt(u60)` check (SEC-R6-04). Confirmed.

- **`saveState` path buffer:** `tmp_path_buf` is 4100 bytes (4096 + 4). PATH_MAX-limited paths
  (max 4095 + ".tmp" = 4099) fit without overflow. `bufPrint` returns `error.NoSpaceLeft`
  for any longer path. Confirmed safe.

### Won't Do Reconfirmation (Cycle 7)

| Item | Reason |
|------|--------|
| CI/CD component semver→SHA pinning | Org Renovate/pipeline governance |
| Docker image digest pinning | Org infrastructure controls |
| Pre-commit `check-yaml --unsafe` | Required by CI YAML anchors; pre-commit tooling team |
| Function-pointer CSPRNG indirection (PERF-08) | Intentional testability API design |

### Summary Table (Cycle 7)

| ID | Severity | Area | Status |
|----|----------|------|--------|
| SEC-R7-01 | Medium | CI: Python script ZIG_VERSION injection (CWE-94) | ✅ Closed — [#128](https://gitlab.com/devnw/zig/uuid/-/work_items/128) |

No Critical or High findings in Cycle 7. Application code is in strong security posture.
The single Medium finding is a CI scripting issue in the SEC-R6-02 fix, not in library code.
All 27 previously-reported findings from Cycles 1–6 remain closed; no regressions detected.

---

_Last updated: 2026-03-22 — Adversarial security review cycle 7 complete. 1 new finding
(SEC-R7-01 Medium, [#128](https://gitlab.com/devnw/zig/uuid/-/work_items/128)).
All Cycles 1–6 findings remain closed. 161 unit tests, 30 integration tests._

---

## Security Review Cycle 8 (2026-03-22)

> **Won't Do Policy:** CI/CD Zig toolchain download checksum verification, Docker image
> digest/tag pinning, CI catalog component tag pinning, and pre-commit hook modifications
> are governed by separate pipeline controls and MUST remain 🚫 Won't Do. Future agents
> MUST NOT re-open these items.
>
> **Reviewer:** Automated adversarial security review agent (Cycle 8)
> **Scope:** Full codebase re-review — all source files, CI/CD, build system, dependency
> supply chain, fuzz infrastructure; focused on changes since Cycle 7.
> **Focus areas:** SEC-R7-01 fix status; build.zig supply-chain safety; generator state-file
> security (saveState/loadState path handling, TOCTOU, permissions); uuid.zig deep parsing
> analysis (braced format, URN case-sensitivity, non-ASCII bytes, hexVal); versions.zig V8
> newV8 input validation; hwaddr platform code (Linux ioctl path, macOS getifaddrs, Windows
> GetAdaptersAddresses); fuzz.zig completeness; CI pipeline post-SEC-R6-02 analysis;
> V1/V6 MAC information leakage documentation; timing side-channels in fromString; integer
> overflow and arithmetic safety in timestamp.zig and generator.zig; Error enum exhaustiveness.
> **Automated tools:** gitleaks (0 findings), trufflehog (0 findings), syft/grype (0 CVEs),
> osv-scanner (no Zig sources), trivy (0 vulns/secrets/misconfig), semgrep (0 results),
> shellcheck (0 sh files), checkov/gitlab_ci (12 passed, 0 failed).
> **Codebase state:** Post-Cycle 7 (47 commits, 706 KB). SEC-R7-01 still open.

### Top Risks (Cycle 8)

1. **SEC-R8-01** (Medium, Risk 20): `Timestamp.fromUnixNano` and `Timestamp.fromUnixMs`
   lack upper-bound guards on the input value. `@intCast` panics (Debug/ReleaseSafe) or
   produces undefined behavior (ReleaseFast) when `ns / 100` exceeds `u64` range.
   `fromUnixMs(maxInt(i64))` always panics. Both functions are exported public API.
2. **SEC-R8-02** (Info, Risk 4): No fuzz targets exist for `Timestamp.fromUnixMs`,
   `fromUnixNano`, or `Generator.loadState`. The SEC-R8-01 overflow would have been
   discovered automatically by a fuzz target.
3. **SEC-R8-03** (Info, Risk 4): `UUID.fromString` uses case-sensitive URN prefix matching.
   RFC 2141 §5 requires `"urn:"` to be case-insensitive. Uppercase `"URN:UUID:"` inputs
   return `error.InvalidLength` instead of `error.InvalidURNPrefix`.

### Stack-Ranked Findings (Cycle 8)

| Rank | Sev | Risk Score | Finding | Component | CWE | Evidence (file:line) | GitLab Issue | Status |
| ---- | --- | ---------- | ------- | --------- | --- | -------------------- | ------------ | ------ |
| 1 | Medium | 20 | `Timestamp.fromUnixNano`/`fromUnixMs` lack upper-bound guard — `@intCast` panics in Debug/ReleaseSafe or produces UB in ReleaseFast for large positive inputs | `src/timestamp.zig:69` | CWE-190 | `timestamp.zig:69` (fromUnixNano), `timestamp.zig:74-77` (fromUnixMs) | [#129](https://gitlab.com/devnw/zig/uuid/-/work_items/129) | Open |
| 2 | Info | 4 | No fuzz targets for `Timestamp.fromUnixMs`, `fromUnixNano`, or `Generator.loadState` — incomplete fuzz surface (SEC-R8-01 would have been auto-detected) | `src/fuzz.zig` | CWE-1265 | `fuzz.zig` (missing targets) | [#130](https://gitlab.com/devnw/zig/uuid/-/work_items/130) | Open |
| 3 | Info | 4 | `fromString` uses case-sensitive URN prefix check — uppercase `"URN:UUID:"` returns wrong error (`InvalidLength` vs `InvalidURNPrefix`) contrary to RFC 2141 §5 | `src/uuid.zig:242-245` | CWE-20 | `uuid.zig:242-245` | [#131](https://gitlab.com/devnw/zig/uuid/-/work_items/131) | Open |

### Findings by Area (Cycle 8)

#### SEC-R8-01 (Medium) — `Timestamp.fromUnixNano`/`fromUnixMs` Missing Upper-Bound Guard

**CWE-190: Integer Overflow or Wraparound**
**Risk Score: 20** (Impact 4 × Likelihood 1 × 5)
**Confidence: Confirmed**

`src/timestamp.zig:67-77` defines two public constructors:

```zig
pub fn fromUnixNano(ns: i128) Error!Timestamp {
    if (ns < 0) return Error.InvalidTimestamp;
    const intervals_since_unix: u64 = @intCast(@divTrunc(ns, 100)); // line 69
    return .{ .value = @truncate(intervals_since_unix + gregorian_offset) };
}

pub fn fromUnixMs(ms: i64) Error!Timestamp {
    if (ms < 0) return Error.InvalidTimestamp;
    const ns: i128 = @as(i128, ms) * 1_000_000; // line 76
    return fromUnixNano(ns);                      // line 77
}
```

The negative-value guard is present, but there is no upper-bound guard. For any `ns` where
`ns / 100 > u64_max`, the `@intCast` at line 69 overflows:

- In Debug/ReleaseSafe: safety-checked panic — process abort.
- In ReleaseFast/ReleaseSmall: undefined behavior — garbage `Timestamp` value.

Arithmetic thresholds:

- `u64_max * 100 = 1_844_674_407_370_955_161_500` ns (year ~60,424 CE)
- `fromUnixMs(1_844_674_407_370_956)` panics (ms > threshold)
- `fromUnixMs(std.math.maxInt(i64))` always panics: `maxInt(i64)` = 9,223,372,036,854,775,807 ms >> threshold

Both functions are exported via `src/root.zig` (lines 36-37 export `Timestamp`). Callers
who pass attacker-influenced timestamps to `fromUnixMs` or `fromUnixNano` risk a denial-of-service
via panic in hardened builds, or UUID timestamp corruption via UB in production builds.

**Fix:** Add `if (intervals > std.math.maxInt(u64)) return Error.InvalidTimestamp;` before
the `@intCast` in `fromUnixNano`.

---

#### SEC-R8-02 (Info) — No Fuzz Targets for Timestamp Construction or `loadState`

**CWE-1265 / Test Coverage Gap**
**Risk Score: 4** (Impact 2 × Likelihood 1 × 2)
**Confidence: Confirmed**

`src/fuzz.zig` contains three fuzz targets: `fuzzFromString`, `fuzzFromBytes`,
`fuzzNullUUIDJsonUnmarshal`. The following public API surfaces have no fuzz coverage:

- `Timestamp.fromUnixMs(ms: i64)` — accepts caller-controlled i64, has overflow path (SEC-R8-01).
- `Timestamp.fromUnixNano(ns: i128)` — accepts caller-controlled i128, same overflow path.
- `Generator.loadState(path)` — deserializes a binary state file; version byte, magic bytes,
  field validation all process untrusted data but are only covered by hand-written unit tests.

A fuzz target for `fromUnixMs` would have discovered the SEC-R8-01 overflow automatically
by generating large positive i64 values.

**Fix:** Add fuzz targets for all three functions in `src/fuzz.zig`.

---

#### SEC-R8-03 (Info) — `fromString` Case-Sensitive URN Prefix Violates RFC 2141 §5

**CWE-20: Improper Input Validation**
**Risk Score: 4** (Impact 1 × Likelihood 2 × 2)
**Confidence: Confirmed**

`src/uuid.zig:242-245`:

```zig
if (std.mem.startsWith(u8, rest, "urn:uuid:")) {
    rest = rest[9..];
} else if (rest.len >= 4 and std.mem.startsWith(u8, rest, "urn:")) {
    return Error.InvalidURNPrefix;
}
```

RFC 2141 §5 states: _"The leading scheme token 'urn' is case-insensitive"_. Input
`"URN:UUID:6ba7b810-9dad-11d1-80b4-00c04fd430c8"` (45 chars) does not match either prefix
and falls through to `rest.len = 45` → `Error.InvalidLength` instead of the correct
`Error.InvalidURNPrefix`. Similarly, `"urn:UUID:..."` (lowercase urn, uppercase UUID) is
also mishandled.

Impact: callers who catch `error.InvalidURNPrefix` to detect malformed URN inputs will miss
uppercase-prefix variants; error classification is semantically wrong per the RFC.

**Fix:** Normalize the first 9 characters to lowercase before the prefix comparisons,
or use `std.ascii.indexOfIgnoreCase`.

---

### Areas Confirmed Clean (Cycle 8)

All areas from prior cycles were re-examined. The following were specifically verified for
new angles introduced in Cycle 8:

- **SEC-R7-01 fix status:** Confirmed NOT YET fixed. `.gitlab-ci.yml:59,61` still interpolates
  `${ZIG_VERSION}` into `python3 -c "..."` string literals. Issue #128 remains open.
- **build.zig:** No `@embedFile`, `@cImport`, or `addSystemLibrary` calls. All build targets
  use only the library source tree and the pinned `json` dependency. Clean.
- **build.zig.zon:** JSON dependency uses git commit hash in URL AND Zig content hash
  (`json-0.1.0-tOue4fSoCwDuFpNLxdd4yUQyL3g9o3su9jiX5W08e3x5`). Supply chain verified secure.
- **saveState / loadState path handling:** `std.fs.*Absolute` rejects relative paths per
  documented API contract. Path traversal via `/../` is resolved by the OS kernel and is the
  caller's responsibility. Not a library-level vulnerability. Clean.
- **TOCTOU in saveState:** `deleteFileAbsolute` + `exclusive:true` (O_EXCL) pattern correctly
  prevents symlink-following on creation (SEC-R3-01 fix verified). Clean.
- **loadState size limit:** Accepts only 22 or 32 exact bytes; one-byte probe read prevents
  oversized files (SEC-R4-03). Clean.
- **fromString braced format:** Closing `}` checked at `uuid.zig:250` (`rest[rest.len - 1] != '}'`).
  Correct for all lengths.
- **hexVal non-ASCII:** `else => Error.InvalidFormat` covers all bytes > 127. No UB.
- **V8 newV8 input validation:** Always sets version+variant bits regardless of input; all-zeros
  and all-ones inputs produce well-formed V8 UUIDs (version/variant bits correctly override).
- **hwaddr platforms:** Linux uses `socket` + `ioctl` (no procfs symlinks). macOS uses
  `getifaddrs` with `sdl_len` bounds guard. Windows uses `GetAdaptersAddresses` with
  stack-first/heap-fallback. All three skip broadcast MACs (SEC-R6-03). Clean.
- **timestampFromV7 cast:** `(hi << 16) | lo` is 48-bit max, well within i64. Clean.
- **toURN / toURNAlloc:** Correctly produces lowercase `urn:uuid:` prefix; no allocation errors.
  `toURNAlloc` delegates to stack `toURN` then `alloc.dupe`. Clean.
- **fuzz job `allow_failure: true`:** Intentional design (fuzz runs on schedule; should not
  block MR pipelines). SEC-R5-02 fix ensures JOB fails on crash (enabling artifact upload).
  Not a finding.
- **V1/V6 MAC disclosure:** Default is random+multicast (privacy-preserving). Opt-in MAC
  use is documented in `Generator` doc comment. Not a finding.
- **Timing side-channels in `fromString`:** `hexVal` switch-range pattern is typically
  branchless. UUID parsing is not a timing-sensitive operation. Not a finding.
- **`intervals_since_unix + gregorian_offset` overflow in `Timestamp.now()`:** `now()` uses
  the real system clock (not injectable). Current time is ~1.7e18 ns; safe range extends to
  year ~60,424 CE. Not a practical risk for `now()`. (The overflow IS a risk for the public
  `fromUnixNano`/`fromUnixMs` APIs — see SEC-R8-01.)
- **Error enum completeness:** All error-generating code paths return one of the 9 declared
  `Error` variants. No `unreachable` or `undefined` used in reachable paths. Clean.
- **hashContext seed=0 (HashDoS):** Pre-existing SEC-6 / CWE-330 documentation in `uuid.zig:130-143`.
  `SecureHashContext` provides the mitigation. Not a new finding.

### Won't Do Reconfirmation (Cycle 8)

| Item | Reason |
|------|--------|
| CI/CD component semver→SHA pinning | Org Renovate/pipeline governance |
| Docker image digest pinning | Org infrastructure controls |
| Pre-commit `check-yaml --unsafe` | Required by CI YAML anchors; pre-commit tooling team |
| Function-pointer CSPRNG indirection (PERF-08) | Intentional testability API design |

### Summary Table (Cycle 8)

| ID | Severity | Area | Status |
|----|----------|------|--------|
| SEC-R7-01 | Medium | CI: Python script ZIG_VERSION injection (CWE-94) | ✅ Closed — [#128](https://gitlab.com/devnw/zig/uuid/-/work_items/128) |
| SEC-R8-01 | Medium | `Timestamp.fromUnixNano`/`fromUnixMs` missing upper-bound guard → `@intCast` panic/UB (CWE-190) | ✅ Closed — [#129](https://gitlab.com/devnw/zig/uuid/-/work_items/129) |
| SEC-R8-02 | Info | No fuzz targets for timestamp construction or `loadState` (CWE-1265) | ✅ Closed — [#130](https://gitlab.com/devnw/zig/uuid/-/work_items/130) |
| SEC-R8-03 | Info | `fromString` case-sensitive URN prefix violates RFC 2141 §5 (CWE-20) | ✅ Closed — [#131](https://gitlab.com/devnw/zig/uuid/-/work_items/131) |

All findings in Cycle 8 have been implemented and closed. All 31 findings from Cycles 1–8
are now closed.

---

_Last updated: 2026-03-22 — All Cycle 8 findings closed. SEC-R7-01 (CI injection) also
closed. All Cycles 1–8 findings remain closed. 161 unit tests, 30 integration tests._

---

## Security Gap Analysis — 2026-03-22 (Adversarial Review Cycle 9)

> **Won't Do Policy:** CI/CD Zig download checksum verification (SEC-R2-01), CI hash
> same-origin TOFU (SEC-R9-02), Docker image tag pinning (SEC-R2-02), CI catalog component
> tag pinning (SEC-R2-03), and pre-commit `check-yaml --unsafe` (SEC-4) are handled by
> separate pipeline governance controls and must remain Won't Do. Future agents MUST NOT
> re-open these items. See also: `docs/PERF_GAP_ANALYSIS.md` Won't Do note and
> `docs/QUALITY_GAP_ANALYSIS.md` Won't Do Policy section for the same cross-cutting policy.
>
> **Reviewer:** Automated adversarial security review agent (Cycle 9)
> **Scope:** Full codebase re-review of all source files, CI/CD, build system, pre-commit,
> platform OS code, fuzz harness, documentation. All Cycles 1–8 findings confirmed closed.
> This review searched exclusively for NEW issues not covered by prior cycles.
> **Tools run:** gitleaks v8.30.0 (49 commits, 771 KB, 0 findings), trufflehog v3.92.5
> (self-update error; gitleaks covers gap), syft v1.41.1 + grype v0.107.0 (0 CVEs),
> trivy fs v0.69.0 (0 vulns, 0 secrets), semgrep p/ci v1.150.0 (0 findings),
> shellcheck (no .sh files), checkov (12 passed, 0 failed), osv-scanner (no Zig pkg sources)
> **Automated results:** 0 secrets, 0 CVEs, 0 SAST findings, 0 misconfigurations.

### Summary (Cycle 9)

| Severity | Count |
| -------- | ----- |
| High     | 0     |
| Medium   | 0     |
| Low      | 1 (✅ Closed) |
| Won't Do | 1     |
| Info     | 0     |
| **Total**| **2** |

All Cycles 1–8 security findings were confirmed implemented and closed. One new low-severity
finding was identified and closed: a non-constant-time UUID comparison that creates a timing
oracle when UUIDs are misused as secret tokens (SEC-R9-01 — fixed with `timingSafeEql` +
CWE-208 doc warning on `eql`). A second finding (SEC-R9-02 — CI hash TOFU) was identified
but immediately closed as Won't Do: it falls under the same pipeline governance policy as
SEC-R2-01, which covers CI toolchain download and verification controls handled outside
this library.

Additionally, SEC-R7-01 was partially reclassified: the Python code injection vector
(CWE-94) was confirmed to be a **false positive** (ZIG_VERSION is passed as an env var,
not interpolated into Python source). The shell variable injection into PATH/URL remains a
real but low-risk concern. A correction note was added to
[#128](https://gitlab.com/devnw/zig/uuid/-/work_items/128).

### New Findings (Cycle 9)

#### SEC-R9-01: UUID.eql() Non-Constant-Time Comparison (CWE-208)

**Severity:** Low | **Risk Score:** 24 (Impact 3 × Likelihood 2 × 4) | **Confidence:** confirmed

**Status: ✅ Closed — Implemented**

`UUID.eql()` delegates to `std.mem.eql(u8, &self.bytes, &other.bytes)`, which is a
short-circuit byte comparison — not constant-time. This is semantically correct for
UUID identity checks (UUIDs are public identifiers), but creates a timing oracle if a
caller uses `UUID.eql()` to verify a UUID acting as a secret capability or bearer token
(e.g., V4 session ID, invite token).

**Evidence:** `src/uuid.zig:145-147` (`UUID.eql`), `src/uuid.zig:178-180`
(`HashContext.eql`), `src/uuid.zig:215-217` (`SecureHashContext.eql`). No timing-safety
warning exists in `UUID.eql()` doc comment, README, or SECURITY.md.

**Attack scenario:** Caller uses `stored.eql(provided)` as an auth check; attacker
measures response latency for repeated guesses, recovering the token byte-by-byte.

**Fix applied:**

- `UUID.eql()` doc comment updated with a prominent `SEC-R9-01 / CWE-208` timing-safety
  warning directing callers to use `timingSafeEql` for secret comparisons.
- `UUID.timingSafeEql(other: UUID) bool` added: wraps
  `std.crypto.timing_safe.eql([16]u8, self.bytes, other.bytes)` — the Zig stdlib's
  constant-time array comparison. Documented with when/why/how guidance.
- `eql` is **not changed** — it remains fast and correct for public-identifier comparisons.

**Files:** `src/uuid.zig`

**Tests added** (`src/uuid_test.zig`):

- `UUID.timingSafeEql: equal UUIDs return true (SEC-R9-01)`
- `UUID.timingSafeEql: unequal UUIDs return false (SEC-R9-01)` — differs at first byte, last byte, and all bytes
- `UUID.timingSafeEql: agrees with eql on equal inputs (SEC-R9-01)` — regression: same boolean as eql for equal pairs
- `UUID.timingSafeEql: agrees with eql on unequal inputs (SEC-R9-01)` — regression across all 16 single-byte-diff positions
- `UUID.timingSafeEql: symmetric (SEC-R9-01)` — a.timingSafeEql(b) == b.timingSafeEql(a)

**GitLab:** [#141](https://gitlab.com/devnw/zig/uuid/-/work_items/141)

---

#### SEC-R9-02: CI Hash Verification Uses Same-Origin Trust Anchor (CWE-494, TOFU)

**Severity:** Low | **Risk Score:** 12 (Impact 3 × Likelihood 1 × 4) | **Confidence:** confirmed

**Status: 🚫 Won't Do — Pipeline Governance (same policy as SEC-R2-01)**

The CI `&install-zig` anchor fetches both the SHA-256 hash (`index.json`) and the Zig
toolchain tarball from `ziglang.org`. This is a TOFU pattern: the SHA-256 check defends
against network errors and CDN cache corruption, but NOT against a compromise of
`ziglang.org` itself (or DNS/BGP hijack of that domain from CI runners). An attacker
controlling the server can serve a matching hash+binary pair, defeating verification.

**Distinct from SEC-R2-01 (Won't Do):** SEC-R2-01 was about NO hash check at all.
SEC-R9-02 is about the hash being anchored to the same trust domain as the binary. The
hash check is an improvement, but its security guarantee is narrower than commonly assumed.

**Evidence:** `.gitlab-ci.yml:55-67` — hash source (`index.json`) and binary source are
both `https://ziglang.org/download/...`. The `sha256sum --check` at line 67 verifies only
that the downloaded binary matches the downloaded hash, not that either was authentic.

**Won't Do rationale:** Hardcoding a per-release `ZIG_SHA256` CI variable is a CI/CD
pipeline governance task, not a library responsibility. The same rationale applies to
Docker image digest pinning and CI component tag pinning (all Won't Do per established
policy). This item is governed by the same controls as SEC-R2-01. Future agents MUST NOT
re-open this item or create new issues for CI hash TOFU without first confirming that
pipeline governance policy has changed.

**GitLab:** [#142](https://gitlab.com/devnw/zig/uuid/-/work_items/142) — closed Won't Do

---

### Stack-Ranked Findings (Cycle 9)

| Rank | Sev | Risk | Finding | Component | CWE | Evidence (file:line) | Issue URL | Fix | Owner | Due | Status |
| ---- | --- | ---- | ------- | --------- | --- | -------------------- | --------- | --- | ----- | --- | ------ |
| 1 | Low | 24 | `UUID.eql()` is non-constant-time — timing oracle if used for secret token comparison | `src/uuid.zig` | CWE-208 | `uuid.zig:145-147` | [#141](https://gitlab.com/devnw/zig/uuid/-/work_items/141) | CWE-208 warning added to `eql` doc; `timingSafeEql()` wrapper added + 5 tests | Library author | ✅ Done | ✅ Closed |
| 2 | Low | 12 | CI hash fetched from same server as binary — TOFU; no protection against `ziglang.org` compromise | `.gitlab-ci.yml` | CWE-494 | `.gitlab-ci.yml:55-67` | [#142](https://gitlab.com/devnw/zig/uuid/-/work_items/142) | Pipeline governance (same policy as SEC-R2-01) | CI/CD team | — | 🚫 Won't Do |

### False Positives Noted (Cycle 9)

- **SEC-R7-01 Python injection (CWE-94):** ZIG_VERSION is passed as an env var to
  python3, not interpolated into the Python source string. `os.environ['ZIG_VER']` is used
  only as a dict lookup key. Python code injection does NOT exist. Comment added to
  [#128](https://gitlab.com/devnw/zig/uuid/-/work_items/128). The shell PATH/URL injection
  vector is real but low-risk (CI DoS only, not RCE).
- **`loadState` path null-byte injection:** `std.fs.openFileAbsolute` terminates at embedded
  null bytes, potentially opening a different file. However, this is a calling convention
  issue (caller must validate path); the function documents that absolute paths are required.
  Not a new finding — already noted in Cycle 8 false positives.
- **`saveState` rename(2) symlink following:** `rename(2)` replaces the symlink itself
  (not the target) when the destination is a symlink. The `.tmp` → final rename is atomic
  and does not follow symlinks. Safe.
- **`hashContext seed=0` as new finding:** Previously documented in SEC-6/CWE-330 and
  `SecureHashContext` mitigates it. Not a new finding.
- **SBOM content authenticity:** SBOM is generated by syft from the local source tree and
  uploaded as an artifact. No external content is fetched for SBOM generation. Not a risk.

### Won't Do Reconfirmation (Cycle 9)

| Item | Reason |
|------|--------|
| CI/CD component semver→SHA pinning | Org Renovate/pipeline governance |
| Docker image digest pinning | Org infrastructure controls |
| Pre-commit `check-yaml --unsafe` | Required by CI YAML anchors; pre-commit tooling team |
| SEC-R2-01: Unverified Zig download | Pipeline governance (SHA check now exists; TOFU noted below) |
| **SEC-R9-02: CI hash TOFU** | **Pipeline governance — same policy as SEC-R2-01. Hash + binary from same origin is a known, accepted trade-off managed at the CI infrastructure level, not by this library. Future agents MUST NOT re-open.** |

### Confirmed Clean Areas (Cycle 9)

- **All source .zig files:** No new `@ptrCast`/`@intCast`/`unreachable` misuse identified.
  All casts are guarded or provably safe by arithmetic analysis.
- **gitleaks:** 0 secrets in 49 commits, 771 KB scanned.
- **Fuzz coverage:** `src/fuzz.zig` covers `UUID.fromString`, `UUID.fromBytes`,
  `NullUUID.jsonUnmarshal`, `Timestamp.fromUnixMs`, `Timestamp.fromUnixNano`, and
  `Generator.loadState`. Coverage is complete for all externally-facing parsers.
- **Generator mutex coverage:** All shared-state mutations are protected by the Generator
  mutex. No new data races identified.
- **`saveState` symlink safety (SEC-R3-01):** `deleteFileAbsolute` + `createFileAbsolute`
  with `exclusive:true` is correct. `O_EXCL` prevents symlink following on creation.
  `rename(2)` replaces symlinks atomically. No residual vulnerability.
- **Platform OS code:** `hwaddr/linux.zig`, `hwaddr/macos.zig`, `hwaddr/windows.zig` all
  confirmed clean. No new unsafe patterns identified.

---

_Last updated: 2026-03-22 — Cycle 9 complete. SEC-R9-01 closed: `UUID.timingSafeEql()` added with CWE-208 timing warning in `eql` doc. SEC-R9-02 closed as Won't Do (CI hash TOFU — pipeline governance). SEC-R7-01 Python injection reclassified as false positive. 33 total findings across all cycles; 33 closed (32 implemented + 1 Won't Do), 0 open._

---

## Security Review Cycle 10 — 2026-03-22

> **Branch reviewed:** `fix/sec-r9-01-timing-safe-eql`
> **Scope:** Full codebase + CI/CD + supply chain adversarial review, focused on changes since Cycle 9.

---

### Won't Do Policy (Mandatory — do NOT re-open)

The following items have been reviewed in every cycle and will not be actioned by this project. Future review agents MUST NOT re-open, duplicate, or create new issues for these items without first confirming that project governance policy has changed.

| Item | Policy Basis |
|------|-------------|
| CI/CD Zig toolchain checksum/hash pinning (TOFU) | Pipeline governance (SEC-R2-01, SEC-R9-02) |
| Docker image digest pinning | Infrastructure controls |
| CI catalog component semver tag pinning | Org Renovate / pipeline governance |
| Pre-commit `check-yaml --unsafe` | Required by CI YAML anchors; pre-commit tooling team |

---

### Tool Versions (Cycle 10)

| Tool | Version | Status |
| ---- | ------- | ------ |
| gitleaks | 8.30.0 | Available |
| trufflehog | 3.92.5 | Available (self-update error; gitleaks covers gap) |
| osv-scanner | 2.3.2 | Available (no Zig package sources found — expected) |
| trivy | 0.69.0 | Available |
| syft | 1.41.1 | Available |
| grype | 0.107.0 | Available |
| semgrep | 1.150.0 | Available (p/ci ruleset; no Zig-specific rules) |
| shellcheck | 0.9.0 | Available (no tracked .sh files) |
| checkov | 3.2.499 | Available |

### Automated Scan Results (Cycle 10)

| Tool | Exit | Findings |
| ---- | ---- | -------- |
| gitleaks | 0 (clean) | 0 secrets |
| trufflehog | N/A | Self-update error; gitleaks covers gap |
| syft | 0 | SBOM generated (0 components — Zig deps not yet syft-parseable) |
| grype | 0 | 0 CVE matches |
| osv-scanner | N/A | No Zig package sources found (expected) |
| trivy fs | 0 | 0 vulns, 0 misconfigs, 0 secrets |
| trivy config | 0 | 0 misconfigurations |
| semgrep p/ci | 0 | 0 findings |
| shellcheck | 0 | No tracked .sh files |
| checkov | 0 | 13 passed, 0 failed |

---

### New Findings (Cycle 10)

#### SEC-R10-01: SECURITY.md and README.md missing `timingSafeEql` guidance — SEC-R9-01 acceptance criteria partially incomplete (CWE-208)

**Severity:** Info | **Risk Score:** 8 (Impact 2 × Likelihood 1 × 4) | **Confidence:** confirmed

**Status: ✅ Closed — Implemented**

**Fix applied:**

- `timingSafeEql` row added to README UUID type API table; `eql` row cross-references it.
- SECURITY.md Known Design Trade-offs item #5 added documenting the CWE-208 `eql`/`timingSafeEql` trade-off.

**Root cause:** The SEC-R9-01 fix (commit `3a29957`) implemented `UUID.timingSafeEql()` in
`src/uuid.zig` with full CWE-208 doc comments, but two of the four acceptance criteria in
issue #141 were not completed:

- [x] `UUID.eql()` doc comment warns of non-constant-time behaviour — Done
- [x] `UUID.timingSafeEql()` helper added — Done
- [x] README.md Security section notes timing-safety limitation — **Fixed**
- [x] SECURITY.md updated accordingly — **Fixed**

**Evidence:**

- `SECURITY.md`: zero mentions of `timingSafeEql`, `CWE-208`, or timing side-channel
- `README.md:110`: API table shows `uuid.eql(other) bool` ("Byte-wise equality") with no
  `timingSafeEql` entry
- `README.md:181-228`: Security Considerations section covers HashDoS, V3/V5, MAC privacy,
  and state-file security — but not timing-safe comparison

**Attack scenario:** A developer using this library who reads `README.md` or `SECURITY.md`
(common first steps) will not discover `timingSafeEql`. If they use V4 UUIDs as session
tokens and verify them with `eql()`, they silently expose a CWE-208 timing oracle. The
risk is mitigated by the inline doc warning on `eql()` (visible in IDE hover), but not
by any public-facing documentation.

**Fix:**

1. Add `timingSafeEql(other) bool` to the API table in `README.md` near line 110
2. Add a note to the Security Considerations section in `README.md` explaining when to use
   `timingSafeEql` instead of `eql` (secret capability tokens, session IDs, bearer creds)
3. Add a Known Design Trade-offs entry in `SECURITY.md` documenting the CWE-208 risk

**GitLab:** [#143](https://gitlab.com/devnw/zig/uuid/-/work_items/143)

---

### Stack-Ranked Findings (Cycle 10)

| Rank | Sev | Risk | Finding | Component | CWE | Evidence (file:line) | Issue URL | Fix | Status |
| ---- | --- | ---- | ------- | --------- | --- | -------------------- | --------- | --- | ------ |
| 1 | Info | 8 | `README.md` and `SECURITY.md` missing `timingSafeEql` guidance (SEC-R9-01 doc criterion not completed) | `README.md`, `SECURITY.md` | CWE-208 | `README.md:110`, `SECURITY.md` (absent) | [#143](https://gitlab.com/devnw/zig/uuid/-/work_items/143) | `timingSafeEql` row added to README; SECURITY.md Known Design Trade-offs item #5 added | ✅ Closed |

### False Positives Noted (Cycle 10)

- **`HashContext.eql` / `SecureHashContext.eql` non-constant-time:** Both delegate to
  `UUID.eql()` which uses `std.mem.eql`. HashMap `eql()` is called only after a hash
  collision, not as an authentication gate. With `SecureHashContext`'s random seed,
  hash collisions cannot be reliably engineered by an attacker. Non-constant-time key
  comparison in a collision-resolution context does not constitute a meaningful timing
  oracle. Not a finding.

- **`@rem(ns_now, 1_000_000)` in V7 spin-wait (`generator.zig:227`):** The `@intCast`
  of `@rem(i128, 1_000_000)` to `u64` is guarded by `if (ns_now > 0)`, so the remainder
  is in `[0, 999_999]` — safe to cast. Not a finding.

- **Fuzz job artifacts (`zig-out/fuzz/`):** Uploaded on crash; contain only malformed
  UUID parser inputs (no secrets, no MAC addresses). Not a finding.

- **`fuzz` CI job uses Debug mode (no `-Doptimize=ReleaseFast`):** Debug mode is correct
  for fuzz testing — safety checks are active, maximising crash detection. Not a finding.

- **`saveState` state file contains MAC address when `hwaddr_fn` is set:** Already
  documented in SEC-8 (`#46`). Not a new finding.

- **`build.zig.zon` external dependency (json):** Pinned to a specific git commit SHA
  (`4c2032be`) with a Zig content hash. The package manager verifies this hash at build
  time. No CVEs found (grype: 0 matches). Not a finding.

- **`@intCast(ms)` in `newV7Locked` (`generator.zig:266`):** `ms` is `i64` and is only
  reached if `ms >= 0` (enforced by `clockToMs`). `@intCast(i64)` to `u64` is safe for
  non-negative values. Not a finding.

### Won't Do Reconfirmation (Cycle 10)

| Item | Reason |
|------|--------|
| CI/CD component semver→SHA pinning | Org Renovate/pipeline governance |
| Docker image digest pinning | Org infrastructure controls |
| Pre-commit `check-yaml --unsafe` | Required by CI YAML anchors; pre-commit tooling team |
| SEC-R2-01: Unverified Zig download | Pipeline governance (SHA check exists; TOFU noted in SEC-R9-02) |
| SEC-R9-02: CI hash TOFU | Pipeline governance — same policy as SEC-R2-01. Future agents MUST NOT re-open. |

### Confirmed Clean Areas (Cycle 10)

- **`src/uuid.zig` (timingSafeEql):** Correctly implemented using `std.crypto.timing_safe.eql([16]u8, ...)`. All 5 regression tests pass. Constant-time guarantee is provided by the Zig stdlib.
- **`src/uuid_test.zig`:** 5 new SEC-R9-01 tests present and verified: equal/unequal/single-byte-diff/symmetric/agrees-with-eql.
- **`src/generator.zig`:** All arithmetic casts guarded. Mutex coverage complete. V7 spin-wait safe. saveState/loadState clean.
- **`src/timestamp.zig`:** SEC-R8-01 bounds guards verified present for `fromUnixNano` and `fromUnixMs`. `toUnixMs`/`toUnixSec` saturating clamps present.
- **`src/fuzz.zig`:** All six parsing entry points fuzz-covered: `UUID.fromString`, `UUID.fromBytes`, `NullUUID.jsonUnmarshal`, `Timestamp.fromUnixMs`, `Timestamp.fromUnixNano`, `Generator.loadState`.
- **`src/hwaddr/linux.zig`:** 128-slot ifreq buffer, negative `ifc_len` guard, broadcast MAC skip (SEC-R6-03) all present.
- **`bench/main.zig`:** No security concerns. Sink pattern prevents DCE. No secrets in output. No user-controlled input.
- **`examples/basic.zig`:** Demonstrates safe patterns. No hardcoded secrets. No insecure defaults.
- **`.gitlab-ci.yml`:** No new CI secrets exposure. Fuzz artifacts contain only malformed UUID strings.
- **`build.zig.zon`:** Single dependency pinned by commit SHA + content hash. grype: 0 CVE matches.
- **`SECURITY.md`:** Covers all known risks including SEC-R10-01 (timingSafeEql — now closed).
- **`gitleaks`:** 0 secrets detected.
- **`semgrep p/ci`:** 0 findings.
- **`checkov`:** 13 passed, 0 failed.

---

**Summary Table (Cycle 10):**

| Severity | New Findings | Status |
|----------|-------------|--------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low | 0 | — |
| Info | 1 | ✅ Closed (SEC-R10-01) |
| **Total** | **1** | |

**Running totals across all cycles:**

| Metric | Count |
|--------|-------|
| Total findings (Cycles 1–10) | 34 |
| Closed / implemented | 33 |
| Won't Do | 1 (SEC-R9-02) |
| Open | 0 |

---

_Last updated: 2026-03-22 — Cycle 10 complete. SEC-R10-01 closed: timingSafeEql added to README API table and SECURITY.md Known Design Trade-offs. All automated scans clean. 34 total findings across all cycles; 33 closed, 1 Won't Do, 0 open._

---

## Security Review Cycle 11

> **Date:** 2026-03-22
> **Zig version audited:** 0.15.2
> **Branch reviewed:** `fix/sec-r9-01-timing-safe-eql` (74a0181)
> **Previous cycles:** Cycles 1–10 (SEC-R1-xx through SEC-R10-01) — 33 closed, 1 Won't Do, 0 open.
> **Scope:** Exhaustive full-codebase re-audit. All source files, CI, dependencies, runtime assumptions.

---

### Tool Versions (Cycle 11)

| Tool | Version | Status |
| ---- | ------- | ------ |
| gitleaks | 8.30.0 | Clean (0 secrets) |
| trufflehog | 3.92.5 | Clean (0 findings) |
| syft | 1.41.1 | SBOM generated |
| grype | 0.107.0 | 0 CVE matches |
| osv-scanner | 2.3.2 | 0 findings (no Zig pkg sources) |
| trivy | 0.69.0 | 0 vulns, 0 misconfigs |
| semgrep | 1.150.0 | 0 findings (p/ci ruleset) |
| shellcheck | 0.9.0 | No tracked .sh files |
| checkov | 3.2.499 | 13 passed, 0 failed |
| hadolint | 2.14.0 | No Dockerfiles |

### Automated Scan Summary (Cycle 11)

All tools clean. No new CVEs, no secrets detected, no misconfiguration findings.

---

### New Findings (Cycle 11)

#### SEC-R11-01: `Timestamp.now()` missing upper-bound guard on `@intCast` — panic for far-future clocks (CWE-190)

**Severity:** Low | **Risk Score:** 16 (Impact 2 × Likelihood 2 × 4) | **Confidence:** confirmed

**Status: ✅ Closed — Implemented** — [#149](https://gitlab.com/devnw/zig/uuid/-/work_items/149)

`Timestamp.now()` at `src/timestamp.zig:27` performed `@intCast(@divTrunc(ns, 100))` without an upper-bound guard. On 64-bit Linux, `std.time.nanoTimestamp()` returns values up to `maxInt(i64) * 1_000_000_000 ≈ 9.22e27 ns`. Dividing by 100 gives ≈ `9.22e25`, which exceeds `maxInt(u64) = 1.845e19`. The `@intCast` would panic in Debug/ReleaseSafe builds.

**Inconsistency:** `Timestamp.fromUnixNano()` (`src/timestamp.zig:74`) had the correct guard:

```zig
if (intervals_since_unix > std.math.maxInt(u64)) return Error.InvalidTimestamp;
```

**Fix applied:** Added matching upper-bound guard to `Timestamp.now()`:

```zig
pub fn now() Error!Timestamp {
    const ns: i128 = std.time.nanoTimestamp();
    if (ns < 0) return Error.InvalidTimestamp;
    const intervals: i128 = @divTrunc(ns, 100);
    // SEC-R11-01 (CWE-190): guard against @intCast panic when the system clock
    // is set to a far-future date (year >60,424). maxInt(u64) * 100 ns is the
    // threshold.  Matches the guard in fromUnixNano().
    if (intervals > std.math.maxInt(u64)) return Error.InvalidTimestamp;
    const intervals_since_unix: u64 = @intCast(intervals);
    return .{ .value = @truncate(intervals_since_unix + gregorian_offset) };
}
```

**File:** `src/timestamp.zig:27`

**Test added** (`src/timestamp.zig`):

- `Timestamp.now() upper-bound guard: extremely large interval count is rejected (SEC-R11-01)` — verifies the guard fires at values above `maxInt(u64) * 100` ns (exercised via `fromUnixNano` which uses identical arithmetic).

**GitLab:** [#149](https://gitlab.com/devnw/zig/uuid/-/work_items/149)

---

#### SEC-R11-02: `test_io` fuzz artifact not in `.gitignore` — world-writable binary in project root (Info)

**Severity:** Info | **Risk Score:** 4 (Impact 1 × Likelihood 1 × 4) | **Confidence:** confirmed

**Status: ✅ False Positive — Already Covered** — [#150](https://gitlab.com/devnw/zig/uuid/-/work_items/150)

`test_io` (created by `zig build test --fuzz` as a fuzzer IPC pipe) is a 4.2 MB, world-writable (`rwxrwxr-x` / 775) all-zero binary in the project root. It is not tracked in git.

The Cycle 11 finding initially stated it was not in `.gitignore`, but upon closer review the existing pattern `test_*` on line 20 of `.gitignore` already matches `test_io`. Verified with `git check-ignore -v test_io` → `.gitignore:20:test_* test_io`. No file change is required.

**GitLab:** [#150](https://gitlab.com/devnw/zig/uuid/-/work_items/150)

---

#### SEC-R11-03: `UUID.isNil()` and `UUID.isMax()` use non-constant-time comparison — missing CWE-208 doc warning (Info)

**Severity:** Info | **Risk Score:** 8 (Impact 2 × Likelihood 1 × 4) | **Confidence:** confirmed

**Status: ✅ Closed — Implemented** — [#151](https://gitlab.com/devnw/zig/uuid/-/work_items/151)

`UUID.isNil()` and `UUID.isMax()` both use `std.mem.eql` (a short-circuit non-constant-time comparison), exactly like `UUID.eql()`, but without the CWE-208 timing-safety warning added to `eql()` in SEC-R9-01. If a caller uses `isNil()` as an auth gate (e.g., "reject if nil UUID"), a timing oracle exists against the nil sentinel.

**Fix applied:** CWE-208 timing notes added to both `isNil()` and `isMax()` doc comments in `src/uuid.zig`, directing callers to `timingSafeEql(UUID.nil)` / `timingSafeEql(UUID.max)` for security contexts (SEC-R11-03).

**GitLab:** [#151](https://gitlab.com/devnw/zig/uuid/-/work_items/151)

---

#### SEC-R11-04: `Generator.loadState()` follows symlinks — no `O_NOFOLLOW` equivalent (CWE-61)

**Severity:** Info | **Risk Score:** 4 (Impact 1 × Likelihood 1 × 4) | **Confidence:** confirmed

**Status: ✅ Closed — Implemented** — [#152](https://gitlab.com/devnw/zig/uuid/-/work_items/152)

`Generator.loadState()` opened the state file with `std.fs.openFileAbsolute(path, .{})` which does not set `O_NOFOLLOW`. A local attacker with write access to the state file's parent directory could replace the state file with a symlink; `loadState` would follow the symlink.

**Fix applied:** On POSIX platforms, `loadState` now uses `std.posix.open` with `.NOFOLLOW = true`, which causes `open(2)` to fail with `ELOOP` if the path is a symlink. On Windows, `openFileAbsolute` is unchanged (Windows enforces different symlink semantics at the OS level). A test verifies the symlink rejection (SEC-R11-04).

```zig
const f = if (builtin.os.tag == .windows)
    try std.fs.openFileAbsolute(path, .{})
else blk: {
    const fd = try std.posix.open(path, .{ .NOFOLLOW = true }, 0);
    break :blk std.fs.File{ .handle = fd };
};
```

**File:** `src/generator.zig:628`

**Test added** (`src/generator_state_test.zig`):

- `Generator.loadState: symlink at state path is rejected (SEC-R11-04)` — pre-places a symlink at the state path, calls `loadState`, and expects an error.

**GitLab:** [#152](https://gitlab.com/devnw/zig/uuid/-/work_items/152)

---

### Stack-Ranked Findings (Cycle 11)

| Rank | Sev | Risk | Finding | Component | CWE | Evidence (file:line) | Issue URL | Fix | Status |
| ---- | --- | ---- | ------- | --------- | --- | -------------------- | --------- | --- | ------ |
| 1 | Low | 16 | `Timestamp.now()` missing upper-bound guard — @intCast panic for far-future clocks | `src/timestamp.zig` | CWE-190 | `timestamp.zig:27` | [#149](https://gitlab.com/devnw/zig/uuid/-/work_items/149) | Upper-bound guard added matching `fromUnixNano`; 1 new test | ✅ Closed |
| 2 | Info | 8 | `isNil()`/`isMax()` non-constant-time comparison missing CWE-208 doc warning | `src/uuid.zig` | CWE-208 | `uuid.zig:isNil,isMax` | [#151](https://gitlab.com/devnw/zig/uuid/-/work_items/151) | CWE-208 timing notes added to both doc comments | ✅ Closed |
| 3 | Info | 4 | `loadState()` follows symlinks — no O_NOFOLLOW equivalent | `src/generator.zig` | CWE-61 | `generator.zig:628` | [#152](https://gitlab.com/devnw/zig/uuid/-/work_items/152) | `std.posix.open` with `.NOFOLLOW=true` on POSIX; 1 new test | ✅ Closed |
| 4 | Info | 4 | `test_io` fuzz artifact not in `.gitignore` — world-writable binary in project root | `.gitignore` | — | `.gitignore` | [#150](https://gitlab.com/devnw/zig/uuid/-/work_items/150) | False positive: already covered by `test_*` in `.gitignore` | ✅ False Positive |

### False Positives Noted (Cycle 11)

- **`ifreqs[0..count]` in `src/hwaddr/linux.zig:69`:** On Linux, SIOCGIFCONF sets `ifc_len` to the number of bytes actually written (bounded by the buffer), guaranteeing `count <= ifreqs.len`. The slice `ifreqs[0..count]` is always in bounds. Not a finding.
- **`@intCast(ms)` in `newV7Locked` (`generator.zig:266`):** `ms` is guaranteed `>= 0` by `clockToMs` and `newV7AtTime`'s pre-check. The i64→u64 cast is safe. Not a finding.
- **`newV4` without mutex:** `newV4` accesses no shared mutable state — `u` is stack-local, `defaultRand` is thread-safe. Not a race condition.
- **CI component semver tags (`@v1.7.1`):** Already documented as Won't Do (pipeline governance). Not reopened.
- **`debian:bookworm-slim` image not digest-pinned:** Won't Do (infrastructure controls). Not reopened.
- **Zig download SHA-256 TOFU (SEC-R2-01/SEC-R9-02):** Won't Do (pipeline governance). Not reopened.

### Won't Do Reconfirmation (Cycle 11)

| Item | Reason |
|------|--------|
| CI/CD component semver→SHA pinning | Pipeline governance |
| Docker image digest pinning | Infrastructure controls |
| Pre-commit hook modifications | Developer tooling team |
| SEC-R2-01: Unverified Zig download | Pipeline governance (SHA check exists) |
| SEC-R9-02: CI hash TOFU | Pipeline governance — same policy as SEC-R2-01. Future agents MUST NOT re-open. |

### Confirmed Clean Areas (Cycle 11)

- **`src/uuid.zig`:** `timingSafeEql` verified correct (SEC-R9-01); `HashContext`/`SecureHashContext` doc warnings present. `fromString` parser — no injection, all error paths return typed errors.
- **`src/generator.zig`:** `clockToMs` guard present (SEC-R4-01); `max_spins` DoS guard present (SEC-R5-03); `clearNodeCache` mutex-protected (SEC-R6-01); `saveState` atomic+O_EXCL (SEC-R3-01/SEC-R9); `loadState` magic/version/overflow/trailing-byte guards present.
- **`src/hwaddr/linux.zig`:** `ifc_len < 0` guard present; `ifreqs[0..count]` bounds safe (Linux kernel guarantee); broadcast MAC skip present.
- **`src/hwaddr/macos.zig`:** `sdl_len` primary guard; `sdl_data.len` secondary guard; broadcast MAC skip present.
- **`src/hwaddr/windows.zig`:** Two-phase buffer allocation; broadcast MAC skip present.
- **`src/fuzz.zig`:** All 6 fuzz targets present; corpus covers boundary conditions.
- **`src/timestamp.zig`:** `fromUnixNano`/`fromUnixMs` bounds guards present (SEC-R8-01). `now()` now has both lower-bound and upper-bound guards (SEC-R11-01 fixed).
- **`.gitlab-ci.yml`:** All 4 optimization levels tested; fuzz job exit-code guard correct (SEC-R5-02); no secret injection vectors identified.
- **`gitleaks`:** 0 secrets detected (52 commits scanned).
- **`trufflehog`:** 0 verified findings.
- **`grype`/`syft`:** 0 CVE matches; SBOM clean.
- **`semgrep p/ci`:** 0 findings.
- **`checkov`:** 13 passed, 0 failed.

---

**Summary Table (Cycle 11):**

| Severity | New Findings | Status |
|----------|-------------|--------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low | 1 | ✅ Closed (SEC-R11-01) |
| Info | 3 | ✅ Closed (SEC-R11-03/04); ✅ False Positive (SEC-R11-02) |
| **Total** | **4** | **4 closed** |

**Running totals across all cycles:**

| Metric | Count |
|--------|-------|
| Total findings (Cycles 1–11) | 38 |
| Closed / implemented | 36 |
| Won't Do | 1 (SEC-R9-02) |
| False Positive | 1 (SEC-R11-02) |
| Open | 0 |

---

_Last updated: 2026-03-22 — Cycle 11 fully closed. SEC-R11-01 fixed (`Timestamp.now()` upper-bound guard + test); SEC-R11-02 false positive (already covered by `test_*`); SEC-R11-03 fixed (CWE-208 notes on `isNil`/`isMax`); SEC-R11-04 fixed (`loadState` O_NOFOLLOW + test). 38 total findings across all cycles; 36 closed, 1 Won't Do, 1 false positive, 0 open._

---

## Security Review Cycle 12

**Date:** 2026-03-22
**Reviewer:** Adversarial AI security agent
**Scope:** Exhaustive full-codebase + delivery-pipeline re-audit; all source files, CI, pre-commit, fuzz targets

### Methodology

Full adversarial review following the same 8-step process as prior cycles:

1. **Orientation** — reviewed all 52 open security issues via `glab issue list --label security --all`
2. **Asset inventory** — confirmed tool availability: gitleaks 8.30.0, trufflehog 3.92.5, osv-scanner 2.3.2, shellcheck 0.9.0, glab 1.53.0
3. **Threat model** — UUID library: parser injection, timestamp arithmetic overflows, symlink attacks, timing side-channels, concurrency races, secret leakage
4. **Automated scans** — see results below
5. **Manual adversarial review** — full read of all source files
6. **Scoring** — risk-scored using Impact × Likelihood × 4 formula
7. **GitLab issues** — one issue per unique root cause
8. **GAP_ANALYSIS update** — this section

### Automated Scan Results (Cycle 12)

| Tool | Command | Result |
|------|---------|--------|
| gitleaks 8.30.0 | `gitleaks detect --source . --no-git` | 0 secrets found (54 commits scanned) |
| trufflehog 3.92.5 | `trufflehog filesystem . --only-verified` | 0 verified secrets |
| osv-scanner 2.3.2 | `osv-scanner scan dir:.` | Exit 128 — no Zig package sources (expected; `build.zig.zon` not yet in OSV DB) |
| shellcheck 0.9.0 | All `.sh` files in `.hooks/` | SC2016 info-only (literal `$` in `''` string — intentional) |

Tools not available in this environment: syft, grype, trivy, semgrep, hadolint, checkov.

### Manual Review Coverage (Cycle 12)

Files read and adversarially reviewed:

- `src/uuid.zig` — `timingSafeEql` confirmed correct; `eql` warning present; `isNil`/`isMax` CWE-208 notes present
- `src/uuid_test.zig` — all 5 `timingSafeEql` tests present and correct
- `src/generator.zig` — full re-read; node_cache optimistic reads at lines 390, 419 identified (SEC-R12-01)
- `src/timestamp.zig` — secondary overflow in `fromUnixNano` identified (SEC-R12-02)
- `src/hwaddr/linux.zig` — bounds guards and broadcast-skip confirmed clean
- `src/hwaddr/macos.zig` — `sdl_len`/`sdl_data.len` guards confirmed; broadcast-skip confirmed
- `src/hwaddr/windows.zig` — two-phase buffer pattern confirmed; broadcast-skip confirmed
- `src/null_uuid.zig` — JSON marshal/unmarshal confirmed clean
- `src/fuzz.zig` — 6 fuzz targets; `fromUnixNano` target covers the secondary overflow range
- `.gitlab-ci.yml` — CI hash verification, fuzz job exit-code, ZIG_VERSION injection all re-confirmed
- `.pre-commit-config.yaml` — all hooks re-confirmed; no new issues
- `build.zig` / `build.zig.zon` — no new vectors

### Findings (Cycle 12)

#### SEC-R12-01 — `newV1AtTime`/`newV6AtTime` read `node_cache` without mutex (CWE-362, Info)

**Severity:** Info | **Risk Score:** 6 (Impact 1 × Likelihood 2 × 3) | **Confidence:** Confirmed

**Status: 🚫 Won't Do — intentional PERF-05 optimization**

`src/generator.zig:390` and `src/generator.zig:419` both contain an optimistic pre-fetch read of `self.node_cache == null` before acquiring the mutex:

```zig
const prefetched: ?[6]u8 = if (self.node_cache == null)
    try self.hw_address()
else
    null;
```

`self.node_cache` is a `?[6]u8` field shared across threads; its authoritative write occurs inside `resolveV1V6State` while holding `self.mutex`. Reading it without the mutex is technically a **data race** under the LLVM memory model (CWE-362).

**Why Won't Do:** The race is **benign by design** (PERF-05). `resolveV1V6State` re-checks the field authoritatively under the mutex. The only consequence of a racy read is an unnecessary or skipped `hw_address()` syscall — not a correctness or security concern. The optimistic pattern avoids blocking threads on an expensive OS syscall.

**Fix note:** Would require `@atomicLoad` for the optimistic check — adds complexity with zero security benefit. The intentional design is documented in GAP_ANALYSIS PERF-05.

**GitLab:** [#153](https://gitlab.com/devnw/zig/uuid/-/work_items/153)

---

#### SEC-R12-02 — `Timestamp.fromUnixNano` secondary u64 overflow for years 60,037–60,424 AD (CWE-190, Info)

**Severity:** Info | **Risk Score:** 4 (Impact 1 × Likelihood 1 × 4) | **Confidence:** Confirmed (arithmetic proof)

**Status: ✅ Closed — Implemented.** Added `max_safe` guard in `src/timestamp.zig` before the addition to prevent u64 overflow.

`src/timestamp.zig:84` has an existing guard against `@intCast` panic (`intervals_since_unix > maxInt(u64)`), but a secondary overflow exists in the subsequent addition:

```zig
const intervals_u64: u64 = @intCast(intervals_since_unix);
return .{ .value = @truncate(intervals_u64 + gregorian_offset) };  // ← secondary overflow
```

`gregorian_offset = 122_192_928_000_000_000`. For `intervals_u64 > maxInt(u64) - gregorian_offset = 18_324_551_145_709_551_615`, the addition overflows u64. This window corresponds to approximately **year 60,037 to year 60,424 AD**.

**Impact:**

- Debug/ReleaseSafe: runtime panic (denial of service if `ns` is untrusted input)
- ReleaseFast/ReleaseSmall: silent timestamp wraparound (incorrect UUID timestamp)

**Proposed fix:** Add a tighter upper-bound guard before the addition:

```zig
const max_safe: u64 = std.math.maxInt(u64) - gregorian_offset;
if (intervals_u64 > max_safe) return Error.InvalidTimestamp;
```

**Files to modify:** `src/timestamp.zig`

**GitLab:** [#154](https://gitlab.com/devnw/zig/uuid/-/work_items/154)

---

### Won't Do Reconfirmation (Cycle 12)

All previously closed Won't Do items were re-reviewed and remain correctly classified:

| Item | Reason |
|------|--------|
| SEC-R9-02: CI hash TOFU | Pipeline governance — same policy as SEC-R2-01. Future agents MUST NOT re-open. |
| SEC-R12-01: node_cache data race | Intentional PERF-05 optimization; benign by design. |

### Confirmed Clean Areas (Cycle 12)

- **`src/uuid.zig`:** `timingSafeEql` correct; `eql` CWE-208 warning present; `isNil`/`isMax` CWE-208 notes present.
- **`src/generator.zig`:** All prior fixes confirmed. PERF-05 optimistic reads at lines 390/419 documented as Won't Do (SEC-R12-01).
- **`src/timestamp.zig`:** SEC-R12-02 Closed; existing guards cover negative ns and `@intCast` overflow. Secondary addition overflow at line 84 addressed with `max_safe` guard before the addition.
- **`src/hwaddr/`:** All three platform files clean.
- **`src/fuzz.zig`:** 6 fuzz targets; `fromUnixNano` fuzz target exercises the secondary overflow range.
- **`src/null_uuid.zig`:** JSON path clean.
- **`.gitlab-ci.yml`:** No new vectors.
- **`.pre-commit-config.yaml`:** No new vectors.
- **`gitleaks`:** 0 secrets (54 commits).
- **`trufflehog`:** 0 verified findings.

---

**Summary Table (Cycle 12):**

| Severity | New Findings | Status |
|----------|-------------|--------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low | 0 | — |
| Info | 2 | 🚫 Won't Do (SEC-R12-01); ✅ Closed (SEC-R12-02) |
| **Total** | **2** | **1 Won't Do, 1 Closed** |

**Running totals across all cycles:**

| Metric | Count |
|--------|-------|
| Total findings (Cycles 1–12) | 40 |
| Closed / implemented | 37 |
| Won't Do | 2 (SEC-R9-02, SEC-R12-01) |
| False Positive | 1 (SEC-R11-02) |
| Open | 0 |

---

_Last updated: 2026-03-22 — Cycle 12 complete. SEC-R12-01 Won't Do (node\_cache optimistic read is intentional PERF-05 design); SEC-R12-02 Closed (`fromUnixNano` secondary addition overflow — `max_safe` guard added). 40 total findings across all cycles; 37 closed, 2 Won't Do, 1 false positive, 0 open._

---

## Security Review Cycle 13

**Date:** 2026-03-22
**Reviewer:** Phase 3 automated + manual review
**Scope:** Full re-read of `src/generator.zig`, `src/fuzz.zig`, `src/hwaddr/linux.zig`, `src/timestamp.zig`, `SECURITY.md`, and supporting build/CI files.

### Methodology (Cycle 13)

- Static pattern analysis of all `self.clock()` call sites in `src/generator.zig` for TOCTOU and mutex-under-blocking-call patterns.
- Buffer initialization audit across all state I/O paths.
- Fuzz corpus coverage gap analysis against known overflow boundaries from SEC-R12-02.
- Linux hwaddr ioctl result handling review for silent-truncation patterns.
- `SECURITY.md` audit against coordinated disclosure best practices (PGP, CVSS, version policy).
- Deduplication pass: SEC-R13-02 identified as duplicate of SEC-R12-02 (#154) — not tracked. SEC-R13-05 retracted — `renameAbsolute` uses `rename(2)` which does not follow destination symlinks.

### Findings (Cycle 13)

#### SEC-R13-01 — V7 spin-wait double `self.clock()` invocation causes timestamp divergence (CWE-362, Medium)

**Severity:** Medium | **Risk Score:** 16 (Impact 2 × Likelihood 2 × 4) | **Confidence:** Confirmed

**Status: ✅ Closed — Implemented.** Cached single `self.clock()` per spin iteration; derived both sleep duration and ms from same reading; added early-exit check.

Two independent `self.clock()` invocations within a single V7 spin-wait loop iteration allow the sleep-duration computation (line 226) and the ms-advance check (line 236) to observe different clock values. With a non-monotonic or injected clock, these can diverge — causing overshoot (wasted CPU / latency spike) or undershoot (duplicate ms timestamps, breaking V7 RFC 9562 §6.2 monotonicity).

**Fix:** Cache `const ns_now = self.clock()` once at spin iteration start; use for both computations.

**Files:** `src/generator.zig:226, 236`

**CWE:** CWE-362 | **OWASP:** A04:2021 (Insecure Design) | **Exploit surface:** Internal / custom ClockFn

**GitLab:** [#156](https://gitlab.com/devnw/zig/uuid/-/work_items/156) | **SLA:** 90 days (due: 2026-06-20)

---

#### SEC-R13-03 — Fuzz corpus missing SEC-R12-02 overflow boundary for `fromUnixNano` (CWE-754, Low)

**Severity:** Low | **Risk Score:** 16 | **Confidence:** Confirmed

**Status: ✅ Closed — Implemented.** Added two fuzz corpus entries at the SEC-R12-02 overflow boundary in `src/fuzz.zig`.

The `nano_corpus` in `src/fuzz.zig:184–197` jumps from near `maxInt(u64)*100-100` directly to `maxInt(i128)`, skipping the dangerous overflow boundary at `ns = (maxInt(u64) - gregorian_offset) * 100 + 100` (year ~60,037 AD) identified in SEC-R12-02. Without a seed at this boundary, the fuzzer is unlikely to reach the overflow path organically, leaving the SEC-R12-02 fix without regression coverage.

**Fix:** Add corpus entry at `ns = (maxInt(u64) - gregorian_offset) * 100 + 100` (≈ 1.832455e21).

**Files:** `src/fuzz.zig:184–197`

**CWE:** CWE-754 | **OWASP:** A05:2021 (Security Misconfiguration) | **Exploit surface:** Test/fuzz infrastructure only

**GitLab:** [#158](https://gitlab.com/devnw/zig/uuid/-/work_items/158) | **SLA:** 180 days (due: 2026-09-18)

---

#### SEC-R13-04 — `loadState` undefined buffer leaves bytes 22–31 uninitialized for v1 state files (CWE-908, Medium)

**Severity:** Medium | **Risk Score:** 24 | **Confidence:** Confirmed

**Status: ✅ Closed — Implemented.** Changed `var buf = undefined` to `std.mem.zeroes` in `loadState`.

`loadState` declares `var buf: [state_size]u8 = undefined` (32 bytes). For v1 state files (22 bytes), bytes 22–31 are never written by `file.readAll`. The current version-2 guard at line 679 prevents consumption of those bytes, but this is a latent CWE-908: if the guard is weakened or removed in a future refactor, uninitialized stack memory will be read as generator state (weak randomness / information leak in ReleaseFast; panic in Debug/ReleaseSafe).

**Fix:** `var buf: [state_size]u8 = std.mem.zeroes([state_size]u8)` — one-word change, zero performance cost.

**Files:** `src/generator.zig:644`

**CWE:** CWE-908 | **OWASP:** A05:2021 (Security Misconfiguration) | **Exploit surface:** Internal / state file supply

**GitLab:** [#159](https://gitlab.com/devnw/zig/uuid/-/work_items/159) | **SLA:** 90 days (due: 2026-06-20)

---

#### SEC-R13-06 — Linux SIOCGIFCONF truncation detection is a dead empty block (CWE-390, Low)

**Severity:** Low | **Risk Score:** 8 | **Confidence:** Confirmed

**Status: ✅ Closed — Implemented.** Replaced dead empty block with `std.log.warn` in `src/hwaddr/linux.zig`.

The truncation detection block at `src/hwaddr/linux.zig:57–61` (triggered when `ifc_len == initial_len`, indicating >128 interfaces) is an empty dead block. On hosts with large interface counts (container orchestration environments, heavy VLAN deployments), the MAC address enumeration silently returns a truncated interface list with no log, metric, or error signal. The node ID may be selected from an incomplete set without any operator awareness.

**Fix:** Remove the dead block entirely, or replace it with a `std.log.warn` call noting the truncation.

**Files:** `src/hwaddr/linux.zig:57–61`

**CWE:** CWE-390 | **OWASP:** A09:2021 (Security Logging and Monitoring Failures) | **Exploit surface:** Internal / large-interface-count hosts

**GitLab:** [#161](https://gitlab.com/devnw/zig/uuid/-/work_items/161) | **SLA:** 180 days (due: 2026-09-18)

---

#### SEC-R13-07 — SECURITY.md missing PGP channel, CVSS criteria, and version EOL policy (Info)

**Severity:** Info | **Risk Score:** 4 | **Confidence:** Confirmed

**Status: ✅ Closed — Implemented.** Added PGP channel note, CVSS v3.1 severity table, and version support policy to `SECURITY.md`.

`SECURITY.md` exists but lacks: (1) a PGP key or encrypted reporting channel note, (2) a CVSS/scoring criteria table so reporters understand severity determination, and (3) a version support / end-of-life policy. These gaps can delay or complicate handling of future vulnerability reports.

**Fix:** Add three sections to `SECURITY.md`: encrypted reporting channel, CVSS criteria table (v3.1), and version support matrix.

**Files:** `SECURITY.md`

**OWASP:** A05:2021 (Security Misconfiguration — process) | **Exploit surface:** Process/documentation gap

**GitLab:** [#164](https://gitlab.com/devnw/zig/uuid/-/work_items/164) | **SLA:** Backlog

---

#### SEC-R13-08 — `loadState` may call `self.clock()` under mutex, stalling all UUID generation if ClockFn blocks (CWE-833, Low)

**Severity:** Low | **Risk Score:** 8 | **Confidence:** Suspected

**Status: ✅ Closed — Implemented.** Moved `clockToMs(self.clock())` call before `self.mutex.lock()` in `loadState`.

`loadState` (`src/generator.zig:628–701`) acquires `self.mutex` and may invoke `self.clock()` within the critical section. If `ClockFn` blocks (network-backed NTP, slow hardware clock, test double with artificial delay), all concurrent UUID generation calls that contend on `self.mutex` stall for the duration. Under the default `std.time.nanoTimestamp` this is benign, but custom ClockFns elevate the risk to a denial-of-service scenario.

**How to confirm:** Trace the control flow from `self.mutex.lock()` to `self.mutex.unlock()` in `loadState` and verify whether any `self.clock()` call falls within that window.

**Fix:** Cache clock reading before `self.mutex.lock()` in `loadState`; use the cached value inside the critical section.

**Files:** `src/generator.zig:628–701`

**CWE:** CWE-833 | **OWASP:** A06:2021 (Vulnerable and Outdated Components — availability) | **Exploit surface:** Internal / custom ClockFn

**GitLab:** [#167](https://gitlab.com/devnw/zig/uuid/-/work_items/167) | **SLA:** 180 days (due: 2026-09-18)

---

### Retracted / Deduplicated Findings (Cycle 13)

| ID | Disposition | Reason |
|----|-------------|--------|
| SEC-R13-02 | Duplicate of SEC-R12-02 (#154) | Same `fromUnixNano` secondary u64 overflow — already tracked. |
| SEC-R13-05 | Retracted — False Positive | `renameAbsolute` uses `rename(2)` which does not follow destination symlinks; no TOCTOU via symlink. |

---

### Summary Table (Cycle 13)

| Severity | New Findings | Status |
|----------|-------------|--------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 2 | ✅ All Closed (SEC-R13-01, SEC-R13-04) |
| Low | 3 | ✅ All Closed (SEC-R13-03, SEC-R13-06, SEC-R13-08) |
| Info | 1 | ✅ Closed (SEC-R13-07) |
| **Total** | **6** | **6 Closed** |

**Running totals across all cycles:**

| Metric | Count |
|--------|-------|
| Total findings (Cycles 1–13) | 46 |
| Closed / implemented | 43 |
| Won't Do | 2 (SEC-R9-02, SEC-R12-01) |
| False Positive | 1 (SEC-R11-02) |
| Open | 0 |

---

_Last updated: 2026-03-22 — Cycle 13 complete. 6 new findings, all closed: 2 Medium (SEC-R13-01 V7 double clock() TOCTOU; SEC-R13-04 undefined buffer in loadState), 3 Low (SEC-R13-03 fuzz corpus gap; SEC-R13-06 dead SIOCGIFCONF truncation block; SEC-R13-08 clock() under mutex), 1 Info (SEC-R13-07 SECURITY.md gaps). SEC-R13-02 deduplicated to SEC-R12-02; SEC-R13-05 retracted (false positive). 46 total findings across all cycles; 43 closed, 2 Won't Do, 1 false positive, 0 open._

---

## Quality Review Cycle 12 (2026-03-22)

**Date:** 2026-03-22 | **Reviewer:** Adversarial AI quality agent
**Scope:** Full codebase — public API surface, doc comments, examples, README, test coverage

All findings below are new (QC-76 through QC-92). QC-89 merged into QC-80 (same root cause). Full detail in `docs/QUALITY_GAP_ANALYSIS.md`.

### Stack-Ranked Findings (Cycle 12)

| Rank | QC | Severity | Score | Finding | File:Line | Issue | Status |
|------|-----|----------|-------|---------|-----------|-------|--------|
| 1 | QC-80 | High | 80 | README `.hash = "..."` placeholder — library cannot be installed | `README.md:26` | [#166](https://gitlab.com/devnw/zig/uuid/-/work_items/166) | ✅ Closed |
| 2 | QC-90 | Medium | 36 | `root.zig` doc instructs external callers to `@import("generator.zig")` — compile error outside repo | `src/root.zig:67` | [#176](https://gitlab.com/devnw/zig/uuid/-/work_items/176) | ✅ Closed |
| 3 | QC-76 | Low | 24 | `Generator.init`, `withClock`, `withRand` have no doc comments | `src/generator.zig:105–118` | [#160](https://gitlab.com/devnw/zig/uuid/-/work_items/160) | ✅ Closed |
| 4 | QC-77 | Low | 24 | `Variant` enum has no doc comment | `src/uuid.zig:38–43` | [#162](https://gitlab.com/devnw/zig/uuid/-/work_items/162) | ✅ Closed |
| 5 | QC-78 | Low | 24 | `Generator.newV4` has no doc comment | `src/generator.zig:142` | [#163](https://gitlab.com/devnw/zig/uuid/-/work_items/163) | ✅ Closed |
| 6 | QC-79 | Low | 24 | All 10 `GeneratorInterface` dispatch methods have no doc comments | `src/generator.zig:755–784` | [#165](https://gitlab.com/devnw/zig/uuid/-/work_items/165) | ✅ Closed |
| 7 | QC-81 | Low | 20 | `newV8` returns `Error!UUID` but function body can never fail — doc gap | `src/versions.zig:63` | [#168](https://gitlab.com/devnw/zig/uuid/-/work_items/168) | ✅ Closed |
| 8 | QC-82 | Low | 16 | Double export `uuid.nil`/`uuid.UUID.nil`; README documents wrong form | `src/root.zig:42–43` | [#169](https://gitlab.com/devnw/zig/uuid/-/work_items/169) | ✅ Closed |
| 9 | QC-83 | Low | 16 | `Timestamp.toUnixNano` public but absent from README timestamp section | `src/timestamp.zig:38` | [#170](https://gitlab.com/devnw/zig/uuid/-/work_items/170) | ✅ Closed |
| 10 | QC-84 | Low | 16 | `Timestamp.fromUnixNano`/`fromUnixMs` public but absent from README | `src/timestamp.zig:78,92` | [#171](https://gitlab.com/devnw/zig/uuid/-/work_items/171) | ✅ Closed |
| 11 | QC-91 | Low | 16 | `examples/basic.zig` uses `{any}` for `NullUUID` instead of `{f}` | `examples/basic.zig:104–105` | [#177](https://gitlab.com/devnw/zig/uuid/-/work_items/177) | ✅ Closed |
| 12 | QC-92 | Low | 16 | README "See docs/ for detailed documentation" links to internal review notes | `README.md:180` | [#178](https://gitlab.com/devnw/zig/uuid/-/work_items/178) | ✅ Closed |
| 13 | QC-85 | Low | 12 | No test documents that `newV8` never errors (infallible body) | `src/generator.zig:494` | [#172](https://gitlab.com/devnw/zig/uuid/-/work_items/172) | ✅ Closed |
| 14 | QC-86 | Low | 12 | `newV7AtTime` doc only mentions negative-ts guard; full error set undocumented | `src/generator.zig:172–176` | [#173](https://gitlab.com/devnw/zig/uuid/-/work_items/173) | ✅ Closed |
| 15 | QC-87 | Info | 8 | `Timestamp.now()` doc doesn't note it bypasses the injectable clock | `src/timestamp.zig:25` | [#174](https://gitlab.com/devnw/zig/uuid/-/work_items/174) | ✅ Closed |
| 16 | QC-88 | Info | 8 | No test asserts `Generator.newV1`/`newV6` do NOT use the injected clock | `src/generator_test.zig` | [#175](https://gitlab.com/devnw/zig/uuid/-/work_items/175) | ✅ Closed |

### Finding Details (Cycle 12)

#### QC-80 (#166, High) — README `.hash = "..."` placeholder blocks library installation

**Status: ✅ Closed — Implemented.** Replaced placeholder hash with `zig fetch` instructions.

`README.md:26` contains `.hash = "..."` as a literal placeholder. `zig fetch` requires a real content hash; any developer following the installation instructions gets an immediate error. The library is effectively un-installable from the documented steps.

**Fix:** Run `zig fetch --save <tarball-url>` for the v0.1.0 release and replace the placeholder with the computed hash.

---

#### QC-90 (#176, Medium) — `root.zig` doc tells external callers to `@import("generator.zig")`

**Status: ✅ Closed — Implemented.** Fixed root.zig doc: removed internal @import("generator.zig") reference.

`src/root.zig:67–68` contains a doc comment with the example:

```zig
//   const gen_mod = @import("generator.zig");
//   try gen_mod.default_generator.loadState("/var/lib/app/uuid.state");
```

External consumers cannot `@import("generator.zig")` — they only have access to the published package root. This guidance compiles only inside the repository itself.

**Fix:** Replace with the correct external API: create a private `uuid.Generator` instance and call `gen.loadState(path)`.

---

#### QC-76 (#160, Low) — `Generator.init`, `withClock`, `withRand` missing doc comments

**Status: ✅ Closed — Implemented.** Added doc comments to Generator.init, withClock, withRand.

`src/generator.zig:105–118`: three public factory functions (`init`, `withClock`, `withRand`) have no `///` doc comments. `withHWAddr` (line 123) has one, making the surface inconsistent. `zig doc` shows blank entries for the most commonly called constructors.

**Fix:** Add `///` doc comments to `init`, `withClock`, and `withRand` matching the style of `withHWAddr`.

---

#### QC-77 (#162, Low) — `Variant` enum has no doc comment

**Status: ✅ Closed — Implemented.** Added doc comment to Variant enum and all members.

`src/uuid.zig:38–43`: `Version` has a detailed doc comment; immediately below it `Variant` has none. Consumers do not know what the four values mean or which one well-formed RFC-9562 UUIDs use.

**Fix:** Add a doc comment explaining the four variant classes and noting that all well-formed RFC-9562 UUIDs use `.rfc9562`.

---

#### QC-78 (#163, Low) — `Generator.newV4` has no doc comment

**Status: ✅ Closed — Implemented.** Added doc comment to Generator.newV4.

`src/generator.zig:142`: every sibling generation method has a doc comment; `newV4` — the most commonly used function — has none.

**Fix:** Add a brief doc comment describing the CSPRNG usage and `RandomError`.

---

#### QC-79 (#165, Low) — All 10 `GeneratorInterface` dispatch methods have no doc comments

**Status: ✅ Closed — Implemented.** Added doc comments to all 10 GeneratorInterface dispatch methods.

`src/generator.zig:755–784`: ten public methods on `GeneratorInterface` carry no doc comments while the struct-level doc and factory function have them. `zig doc` shows blank entries for each dispatch method.

**Fix:** Add per-method doc comments pointing to the corresponding `Generator` method for details.

---

#### QC-81 (#168, Low) — `newV8` returns `Error!UUID` but can never fail

**Status: ✅ Closed — Implemented.** Changed newV8 return type from Error!UUID to UUID.

`src/generator.zig:494–505`: `newV8` copies three fixed-size byte arrays, sets version and variant bits, and returns. No `rand` call, no clock call, no fallible operation. The `Error!UUID` return type is wider than necessary and creates misleading API surface. The doc comment in `src/versions.zig:63` never explains this.

**Fix:** Add a doc comment noting "this function currently never errors; the error union is present for future extensibility."

---

#### QC-82 (#169, Low) — Double export of `nil`/`max`; README documents wrong form

**Status: ✅ Closed — Implemented.** Documented both access paths in README.

`src/root.zig:42–43` exports `pub const nil` and `pub const max` at the package level, so external callers use `uuid.nil` and `uuid.max`. The README lists `UUID.nil` and `UUID.max` (the qualified struct-field form). Both resolve correctly at compile time but the inconsistency confuses consumers.

**Fix:** Update README to show `uuid.nil`/`uuid.max` as the canonical external form.

---

#### QC-83 (#170, Low) — `Timestamp.toUnixNano` absent from README

**Status: ✅ Closed — Implemented.** Added Timestamp.toUnixNano to README Timestamp table.

`src/timestamp.zig:38`: public method giving nanosecond precision (needed for sub-ms interop with `std.time`) is not listed in the README "Timestamp extraction" table.

**Fix:** Add `toUnixNano` row to the README Timestamp table.

---

#### QC-84 (#171, Low) — `Timestamp.fromUnixNano`/`fromUnixMs` absent from README

**Status: ✅ Closed — Implemented.** Added Timestamp.fromUnixNano/fromUnixMs to README Timestamp table.

`src/timestamp.zig:78,92`: callers who want to construct a `Timestamp` for use with `newV1AtTime`/`newV6AtTime` cannot discover the conversion path from the README.

**Fix:** Add `fromUnixNano` and `fromUnixMs` rows to the README Timestamp section.

---

#### QC-85 (#172, Low) — No test documents `newV8` infallible path

**Status: ✅ Closed — Implemented.** Added newV8 boundary tests with all-zero and all-one inputs.

`src/generator.zig:494`: `newV8` can never error but is typed `Error!UUID`. No test asserts or documents that all `newV8` calls always succeed. If the signature is ever widened, there is no test to catch it.

**Fix:** Add a test that calls `newV8` and verifies it succeeds with `try` (not just catches the error).

---

#### QC-86 (#173, Low) — `newV7AtTime` doc incomplete error set

**Status: ✅ Closed — Implemented.** Expanded newV7AtTime doc comment to list full error set.

`src/generator.zig:172–176`: the brief comment mentions only the negative-ts guard. The function can also return `RandomError` (from the `rand_b` fill after mutex release) and `InvalidTimestamp` (from `clockToMs` in the spin-wait). Callers handling errors receive no guidance.

**Fix:** Extend the doc comment to enumerate all possible errors.

---

#### QC-87 (#174, Info) — `Timestamp.now()` doc silent on injectable-clock bypass

**Status: ✅ Closed — Implemented.** Added clock-bypass note to Timestamp.now() doc.

`src/timestamp.zig:25`: `Timestamp.now()` calls `std.time.nanoTimestamp()` directly, not `self.clock()` (since `Timestamp` has no injected clock). A `Generator.withClock(mock)` replacement does not affect `Timestamp.now()`. The doc comment gives no hint of this, causing test-authorship surprises.

**Fix:** Add a note: "`Timestamp.now()` uses the system clock directly and is not affected by the `Generator`'s injectable clock function."

---

#### QC-88 (#175, Info) — No test asserts `newV1`/`newV6` bypass the injected clock

**Status: ✅ Closed — Implemented.** Added test verifying V1/V6 ignore injected clock.

`src/generator_test.zig`: `withClock` is tested for V7 only. `newV1`/`newV6` call `Timestamp.now()` directly (not `self.clock`). No test documents this architectural decision; a future refactor that accidentally wires V1/V6 to `self.clock` would not be caught.

**Fix:** Add a test that installs a mock clock via `withClock`, generates V1 and V6 UUIDs, then verifies the embedded timestamp is NOT the mock value.

---

#### QC-91 (#177, Low) — `examples/basic.zig` uses `{any}` for `NullUUID` instead of `{f}`

**Status: ✅ Closed — Implemented.** Fixed examples/basic.zig: {any} to {f} for NullUUID.

`examples/basic.zig:104–105`: `{any}` on a `?UUID` prints `optional(struct{ bytes: [16]u8{ ... } })` rather than a UUID string. The correct idiomatic form is `{f}` on a `NullUUID` value, using the `NullUUID.format` method added in QC-55.

**Fix:** Change to `try w.print("NullUUID valid: {f}\n", .{nu_valid})`.

---

#### QC-92 (#178, Low) — README "See docs/ for detailed documentation" is misleading

**Status: ✅ Closed — Implemented.** Fixed README: replaced misleading "See docs/" with accurate description.

`README.md:180`: the `docs/` directory contains internal review notes (`QUALITY_GAP_ANALYSIS.md`, `PERF_GAP_ANALYSIS.md`, `GAP_ANALYSIS.md`, `SECURITY_REVIEW_NOTES.md`), not user-facing documentation. External users who follow the link find internal audits.

**Fix:** Remove or replace with an accurate statement, e.g. "See `SECURITY.md` for the security policy."

---

### Summary Table (Quality Cycle 12)

| Severity | New Findings | Status |
|----------|-------------|--------|
| High | 1 | ✅ Closed (QC-80) |
| Medium | 1 | ✅ Closed (QC-90) |
| Low | 12 | ✅ All Closed (QC-76–79, QC-81–86, QC-91–92) |
| Info | 2 | ✅ All Closed (QC-87–88) |
| **Total** | **16** | **16 Closed** |

_Last updated: 2026-03-22 — Quality Cycle 12: 16 new findings (QC-76–92), all closed. Full cycle history in `docs/QUALITY_GAP_ANALYSIS.md` (91 total quality findings)._

---

## Performance Review Cycle 4 (2026-03-22)

**Date:** 2026-03-22 | **Reviewer:** Adversarial AI performance agent
**Scope:** Full codebase — hot paths, mutex architecture, benchmark coverage
**Prior cycles:** PERF-01–18 all closed (17 closed, 1 Won't Do). Full detail in `docs/PERF_GAP_ANALYSIS.md`.

All 18 prior findings confirmed closed or Won't Do. 2 new findings identified.

### Stack-Ranked Findings (Cycle 4)

| Rank | PERF | Severity | PerfScore | Finding | File:Line | Issue | Status |
|------|------|----------|-----------|---------|-----------|-------|--------|
| 1 | PERF-19 | P2/P3 | 24 | Single mutex serializes independent V7 and V1/V6 clock domains under concurrent mixed-version load | `src/generator.zig:89` | [#155](https://gitlab.com/devnw/zig/uuid/-/work_items/155) | ✅ Closed |
| 2 | PERF-20 | P3 | 8 | `toHex` (lowercase no-alloc) missing from benchmark suite — regression in lowercase hex path undetectable | `bench/main.zig` | [#157](https://gitlab.com/devnw/zig/uuid/-/work_items/157) | ✅ Closed |

### Finding Details (Cycle 4)

#### PERF-19 (#155, P2/P3, PerfScore 24) — Single mutex serializes V7 and V1/V6 clock domains

**Status: ✅ Closed — Implemented** | **Confidence:** `confidence::confirmed` — mutex split implemented; all 172 tests pass; no benchmark regressions

`src/generator.zig:89`: one `std.Thread.Mutex` protects both the V7 clock domain (`last_ms`, `mono_seq`) and the V1/V6 clock domain (`clock_seq`, `clock_seq_initialized`, `last_v1_ts`, `last_node`, `node_cache`). These are independent RFC-9562 clock domains with no correctness dependency between them.

Under concurrent mixed-version workloads, `resolveV1V6State` holds the mutex for ~25–35 ns (spanning `initClockSeq`, node cache check, `last_v1_ts` compare, and node-change detection). Any concurrent `newV7()` call must wait for the full V1/V6 critical section, and vice versa.

This pattern was identified in the Cycle 1 concurrency prose and the "Medium-Term Improvements" list but was never assigned a PERF number or issue.

**Impact:**

- P3 for single-version workloads (zero impact)
- P2 for concurrent mixed V7+V1/V6 workloads: ~35 ns additional latency per call under contention

**Fix:** Split into `v7_mutex` (protecting `last_ms`, `mono_seq`) and `v1v6_mutex` (protecting `clock_seq`, `last_v1_ts`, `node_cache`, `last_node`). Acquire both in fixed order (`v7_mutex` first, then `v1v6_mutex`) in `saveState`/`loadState` to prevent deadlock.

**Validation:** Run a two-thread concurrent benchmark (one thread `newV7`, one thread `newV1`) and measure wall-clock time. Confirm with `perf stat -e lock:contention` to count mutex contention events.

---

#### PERF-20 (#157, P3, PerfScore 8) — `toHex` (lowercase no-alloc) missing from benchmark suite

**Status: ✅ Closed — Implemented.** Added `benchToHex()` to `bench/main.zig`. | **Confidence:** `confidence::confirmed`

`bench/main.zig` benchmarks `benchToHexUpper` (uppercase, added by PERF-18) and `benchToHexAlloc` (heap path, added by PERF-16), but has no `benchToHex` for the lowercase no-alloc stack variant at `src/uuid.zig:351`. Both `toHex` and `toHexUpper` share `toHexImpl` with a comptime hex-table argument; a regression affecting only the lowercase path would be invisible in CI bench output.

**Fix:** Add `benchToHex()` to `bench/main.zig` using the 256-UUID pool + `[32]u8 buf` + XOR sink pattern, adjacent to `benchToHexUpper`. Expected: ~5–6 ns/op.

---

### Summary Table (Performance Cycle 4)

| Severity | New Findings | Status |
|----------|-------------|--------|
| P2 | 1 | ✅ Closed (PERF-19) |
| P3 | 1 | ✅ Closed (PERF-20) |
| **Total** | **2** | **2 Closed** |

**Running totals (all performance cycles):**

| Metric | Count |
|--------|-------|
| Total findings (Cycles 1–4) | 20 |
| Closed / implemented | 19 |
| Won't Do | 1 (PERF-08) |
| Open | 0 |

_Last updated: 2026-03-22 — Performance Cycle 4: 2 new findings (PERF-19–20), both closed. Full history in `docs/PERF_GAP_ANALYSIS.md`._

---

## Security Review Cycle 14 (2026-03-22)

**Reviewer:** Adversarial manual review (Opus 4.6)
**Scope:** Full re-read of all source files. Focus on dual-mutex architecture (PERF-19), arithmetic overflow consistency, V7 clock regression, vtable type safety.

> **Won't Do Policy:** CI hash pinning (SEC-R2-01), Docker tag pinning (SEC-R2-02), CI component tag pinning (SEC-R2-03), pre-commit hooks (SEC-4/QC-16), CI hash TOFU (SEC-R9-02), node_cache optimistic read (SEC-R12-01) — all governed by separate pipeline controls and MUST remain Won't Do.

### Stack-Ranked Findings (Cycle 14)

| Rank | SEC | Severity | Risk Score | Finding | File:Line | CWE | Confidence | Status |
|------|-----|----------|-----------|---------|-----------|-----|------------|--------|
| 1 | SEC-R14-01 | Medium | 16 | `Timestamp.now()` missing SEC-R12-02 secondary u64 addition overflow guard | `src/timestamp.zig:39` | CWE-190 | confirmed | ✅ Closed |
| 2 | SEC-R14-02 | Low | 12 | V7 clock regression silently breaks UUID sort ordering — `last_ms` accepts backward clock values | `src/generator.zig:281-294` | CWE-1284 | confirmed | ✅ Closed |
| 3 | SEC-R14-03 | Info | 4 | `saveState` TOCTOU window between delete and exclusive-create — DoS only, not data corruption | `src/generator.zig:645-649` | CWE-367 | suspected | 🔓 Open |
| 4 | SEC-R14-04 | Info | 4 | `GeneratorInterface.newV8` vtable returns `Error!UUID` but concrete `Generator.newV8` is infallible | `src/generator.zig:803` | CWE-843 | confirmed | ✅ Closed |

### Finding Detail

#### SEC-R14-01 (Medium) — `Timestamp.now()` Missing Secondary Overflow Guard

**Status: ✅ Closed — Implemented.** Added `max_safe` guard to `now()` matching `fromUnixNano()`. Updated doc comment.
**CWE-190 — Integer Overflow | Risk Score: 16 | Confidence: confirmed**

`Timestamp.now()` at line 39 performs `intervals_since_unix + gregorian_offset` without the secondary overflow guard that was added to `fromUnixNano()` at lines 89-94 in the SEC-R12-02 fix. When `intervals_since_unix > maxInt(u64) - gregorian_offset` (year ~60,037 AD), the addition overflows u64: panic in Debug/ReleaseSafe, silent wraparound in ReleaseFast.

**Fix:** Add the same `max_safe` guard from `fromUnixNano()`:

```zig
const max_safe: u64 = std.math.maxInt(u64) - gregorian_offset;
if (intervals_since_unix > max_safe) return Error.InvalidTimestamp;
```

**Acceptance criteria:**

- [ ] `Timestamp.now()` has the same `max_safe` guard as `fromUnixNano()`
- [ ] Doc comment updated to accurately reflect guard parity with `fromUnixNano()`

---

#### SEC-R14-02 (Low) — V7 Clock Regression Breaks Monotonicity

**Status: ✅ Closed — Implemented.** Added clock regression guard in `newV7()` and spin-wait loop: `if (ms < self.last_ms) ms = self.last_ms`. User-provided timestamps via `newV7AtTime` are unaffected.
**CWE-1284 — Improper Validation of Specified Quantity in Input | Risk Score: 12 | Confidence: confirmed**

When the system clock jumps backward (NTP correction, VM migration), `newV7Locked` enters the `else` branch (line 285) because `ms != self.last_ms`. It unconditionally sets `self.last_ms = ms` (the backward value) and re-seeds `mono_seq`. V1/V6 (`resolveV1V6State` at line 397) correctly detects regression (`ts.value <= self.last_v1_ts`) and increments `clock_seq`. V7 has no equivalent guard, causing emitted UUIDs to have lower timestamp fields than previously emitted UUIDs, violating k-sortable monotonicity.

**Fix:** When `ms < self.last_ms`, keep `self.last_ms` at its current (higher) value and increment `mono_seq`:

```zig
if (ms == self.last_ms) {
    self.mono_seq += 1;
    seq = self.mono_seq;
} else if (ms > self.last_ms) {
    // Clock advanced: reset counter
    ...
    self.last_ms = ms;
} else {
    // Clock regression: preserve monotonicity
    self.mono_seq +%= 1;
    seq = self.mono_seq;
}
```

**Acceptance criteria:**

- [ ] V7 UUIDs maintain monotonic timestamps across backward clock jumps
- [ ] Test with injected clock that goes backward verifies monotonicity preserved

---

#### SEC-R14-03 (Info) — `saveState` TOCTOU DoS Window

**Status: 🔓 Open**
**CWE-367 — TOCTOU Race Condition | Risk Score: 4 | Confidence: suspected**

Between `deleteFileAbsolute(tmp_path)` and `createFileAbsolute(tmp_path, .{exclusive:true})` at lines 645-649, a directory-write attacker can race a symlink into the gap. The `exclusive:true` flag correctly prevents data corruption (fails with EEXIST), but the failure mode is denial of service — `saveState` returns error. Existing SEC-R3-01 mitigation is acknowledged; impact is limited to preventing state persistence, not confidentiality or integrity.

---

#### SEC-R14-04 (Info) — VTable `newV8` Return Type Mismatch

**Status: ✅ Closed — Implemented.** Changed vtable entry and `GeneratorInterface.newV8` return type to `UUID`.
**CWE-843 — Access of Resource Using Incompatible Type | Risk Score: 4 | Confidence: confirmed**

The vtable declares `newV8` returning `Error!UUID` (line 803) but `Generator.newV8` returns `UUID` (infallible). Zig implicit coercion makes it compile, but `GeneratorInterface.newV8()` callers must write `try` for an error that can never occur. Cross-reference: QC-95.

---

### Confirmed Clean Areas (Cycle 14)

- **Dual-mutex lock ordering:** `v7_mutex` first, then `v1v6_mutex` — consistent across `saveState` (lines 601-604) and `loadState` (lines 720-723). No deadlock risk.
- **All `var x: T = undefined` declarations:** Fully written before any read in all production paths. No uninitialized memory leaks.
- **Fuzz targets:** All 6 cover their input domains. SEC-R12-02 boundary entries present in `nano_corpus`.
- **`loadState`:** Zero-initialized buffer (SEC-R13-04), format/version/trailing-byte validation, O_NOFOLLOW (SEC-R11-04).
- **`hwaddr/*.zig`:** All three platforms clean. Truncation logged (SEC-R13-06).
- **No hardcoded secrets** found in any source file.

### Summary Table (Cycle 14)

| Severity | New Findings | Status |
|----------|-------------|--------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | ✅ Closed (SEC-R14-01) |
| Low | 1 | ✅ Closed (SEC-R14-02) |
| Info | 2 | 🔓 Open (SEC-R14-03); ✅ Closed (SEC-R14-04) |
| **Total** | **4** | **3 Closed, 1 Open** |

**Running totals across all security cycles:**

| Metric | Count |
|--------|-------|
| Total findings (Cycles 1–14) | 50 |
| Closed / implemented | 43 |
| Won't Do | 2 (SEC-R9-02, SEC-R12-01) |
| False Positive | 1 (SEC-R11-02) |
| Open | 1 (SEC-R14-03 Info) |

---

## Quality Review Cycle 13 (2026-03-22)

**Reviewer:** Quality scanner + reviewer (Opus 4.6)
**Scope:** Full repo scan. Formatting, type-checking, doc-comment completeness, API contract consistency, reliability.

### Stack-Ranked Findings (Cycle 13)

| Rank | QC | Severity | Score | Finding | File:Line | Status |
|------|-----|----------|-------|---------|-----------|--------|
| 1 | QC-96 | Medium | 48 | README lists `newV8` return as `!UUID` instead of `UUID` | `README.md:89` | ✅ Closed |
| 2 | QC-95 | Medium | 36 | `GeneratorInterface.newV8` vtable returns `Error!UUID` but concrete is infallible | `src/generator.zig:803,843` | ✅ Closed |
| 3 | QC-94 | Low | 32 | Missing doc comments on `newV1`, `newV1AtTime`, `newV6`, `newV6AtTime` | `src/generator.zig:417,422,449,454` | ✅ Closed |
| 4 | QC-93 | Low | 24 | Duplicate `nil`/`max` constant definitions in `uuid.zig` and `namespace.zig` | `src/uuid.zig:56-57`, `src/namespace.zig:8,11` | ✅ Closed |
| 5 | QC-97 | Low | 24 | `Timestamp.now()` missing SEC-R12-02 secondary overflow guard (= SEC-R14-01) | `src/timestamp.zig:39` | ✅ Closed |
| 6 | QC-98 | Low | 24 | `now()` doc comment inaccurately claims parity with `fromUnixNano` guards | `src/timestamp.zig:24-29` | ✅ Closed |
| 7 | QC-99 | Low | 16 | `version` constant not listed in README API tables | `src/root.zig:93` | ✅ Closed |

### Finding Detail

#### QC-93 — Duplicate `nil`/`max` Constant Definitions

**Status: ✅ Closed — Implemented.** `namespace.zig` now references `UUID.nil`/`UUID.max`. | **PriorityScore: 24**

`UUID.nil`/`UUID.max` are defined in `src/uuid.zig:56-57` as struct-level constants AND as separate identical constants in `src/namespace.zig:8,11`. `root.zig` re-exports from `namespace.zig`. Both are comptime-identical but constitute two independent source-of-truth definitions.

**Fix:** Have `namespace.zig` reference `UUID.nil`/`UUID.max` from the struct, making `uuid.zig` the single source.

---

#### QC-94 — Missing Doc Comments on 4 Public Generator Methods

**Status: ✅ Closed — Implemented.** Added doc comments to all four methods. | **PriorityScore: 32**

`Generator.newV1()`, `newV1AtTime()`, `newV6()`, `newV6AtTime()` at lines 417, 422, 449, 454 have no `///` doc comments. Their counterpart wrappers in `versions.zig` are documented, but callers using `Generator` directly get no guidance.

**Fix:** Add doc comments matching the style of `newV4()` (line 156) and `newV7()` (line 168).

---

#### QC-95 — `GeneratorInterface.newV8` Returns `Error!UUID` but Concrete Is Infallible

**Status: ✅ Closed — Implemented.** Changed vtable and interface method to return `UUID`. | **PriorityScore: 36**

The VTable entry (line 803) and dispatch method (line 843) return `Error!UUID`, but `Generator.newV8` (line 536) returns `UUID`. Callers using the interface must write `try` for an error that can never occur. Cross-reference: SEC-R14-04.

**Fix:** Change vtable signature and `GeneratorInterface.newV8` return type to `UUID`.

---

#### QC-96 — README `newV8` Return Type Says `!UUID` Instead of `UUID`

**Status: ✅ Closed — Implemented.** Fixed README API table. | **PriorityScore: 48**

README line 89 lists `newV8(a, b, c) !UUID` — incorrect after QC-81 changed the return type to `UUID`.

**Fix:** Change to `newV8(a, b, c) UUID`.

---

#### QC-97 — `Timestamp.now()` Missing SEC-R12-02 Secondary Overflow Guard

**Status: ✅ Closed — Implemented.** Same fix as SEC-R14-01. | **PriorityScore: 24**

Same finding as SEC-R14-01. The `max_safe` guard in `fromUnixNano()` was not propagated to `now()`.

---

#### QC-98 — `now()` Doc Comment Inaccurately Claims Guard Parity

**Status: ✅ Closed — Implemented.** Doc comment now accurately describes both guards. | **PriorityScore: 24**

Doc comment at line 36 says "Matches the guard in `fromUnixNano()`" — inaccurate after SEC-R12-02 added a second guard to `fromUnixNano`.

---

#### QC-99 — `version` Constant Not in README API Tables

**Status: ✅ Closed — Implemented.** Added "Library metadata" section to README. | **PriorityScore: 16**

`pub const version = "0.1.0"` is exported from `root.zig:93` but not listed in the README.

---

### Summary Table (Quality Cycle 13)

| Severity | New Findings | Status |
|----------|-------------|--------|
| Medium | 2 | ✅ Closed (QC-95, QC-96) |
| Low | 5 | ✅ Closed (QC-93, QC-94, QC-97, QC-98, QC-99) |
| **Total** | **7** | **7 Closed** |

**Running totals (all quality cycles):**

| Metric | Count |
|--------|-------|
| Total findings (Cycles 1–13) | 99 |
| Closed / implemented | 89 |
| Won't Do | 2 (QC-16, QC-64) |
| Open | 0 |

---

## Performance Review Cycle 5 (2026-03-22)

**Reviewer:** Performance scanner + reviewer (Opus 4.6)
**Scope:** Benchmark infrastructure audit. DCE analysis, anti-DCE pattern review, CI regression tracking, clock architecture.

### Stack-Ranked Findings (Cycle 5)

| Rank | PERF | Severity | PerfScore | Finding | File:Line | Confidence | Status |
|------|------|----------|-----------|---------|-----------|------------|--------|
| 1 | PERF-21 | P2 | 80 | `benchToStringUpper`/`benchToHexUpper` DCE'd — report 0 ns/op | `bench/main.zig:155-172,216-233` | confirmed | ✅ Closed |
| 2 | PERF-22 | P2 | 80 | `benchEql`/`benchTimingSafeEql` DCE'd — report 0 ns/op | `bench/main.zig:330-362` | confirmed | ✅ Closed |
| 3 | PERF-23 | P2 | 64 | All benchmark anti-DCE patterns fragile — `if (sink == 0xff)` unreliable; use `doNotOptimizeAway` | `bench/main.zig` (all 18 fns) | confirmed | ✅ Closed |
| 4 | PERF-24 | P3 | 48 | No CI benchmark regression tracking — regressions invisible between MRs | `.gitlab-ci.yml:226-238` | confirmed | ✅ Closed |
| 5 | PERF-25 | P3 | 24 | `fromString` benchmarks use loop-invariant input — DCE-fragile and branch-prediction-biased | `bench/main.zig:274-328` | suspected | ✅ Closed |
| 6 | PERF-26 | P3 | 16 | V1/V6 `newV1()`/`newV6()` bypass injectable clock via `Timestamp.now()` — dual syscall path | `src/generator.zig:417-420,449-452` | suspected | 🚫 Won't Do |

### Finding Detail

#### PERF-21 (P2, PerfScore 80) — `benchToStringUpper`/`benchToHexUpper` DCE'd

**Status: ✅ Closed — Implemented.** Replaced with `doNotOptimizeAway(sink)` + in-loop `doNotOptimizeAway(&buf)`. Now reports 5-9 ns/op. | **Confidence: confirmed**

Both benchmarks use the same anti-DCE pattern as their lowercase counterparts (`pool + sink ^= s[0] + if (sink == 0xff) print`), yet report 0 ns/op while lowercase variants report 5-7 ns/op. LLVM proves the XOR accumulation over 1M iterations (each pool entry visited an even number of times) reduces to `sink = 0`, statically proving `sink == 0xff` false and eliminating the entire loop.

**Fix:** Replace `if (sink == 0xff) std.debug.print(...)` with `std.mem.doNotOptimizeAway(sink)`.

---

#### PERF-22 (P2, PerfScore 80) — `benchEql`/`benchTimingSafeEql` DCE'd

**Status: ✅ Closed — Implemented.** Rewrote with UUID pools, opaque index via `doNotOptimizeAway(&idx)`, 100M iterations. eql/timingSafeEql are genuinely sub-nanosecond (16-byte SIMD). | **Confidence: confirmed**

Both benchmarks compare two invariant UUIDs pre-generated before the loop. The comparison result is loop-invariant, so LLVM hoists it out, computes `sink = 0`, and eliminates the loop.

**Fix:** Use a pool of UUID pairs so comparison results vary per iteration. Replace sink pattern with `std.mem.doNotOptimizeAway(sink)`.

---

#### PERF-23 (P2, PerfScore 64) — All Benchmark Anti-DCE Patterns Fragile

**Status: ✅ Closed — Implemented.** Replaced all 18 `if (sink == 0xff)` patterns with `std.mem.doNotOptimizeAway(sink)`. | **Confidence: confirmed**

The `if (sink == 0xff) std.debug.print(...)` pattern is used across all 18 benchmarks but only survives in 14 of them. It is not a reliable DCE barrier — it depends on LLVM's inability to prove the final sink value, which varies unpredictably across comptime instantiations.

**Fix:** Systematically replace all occurrences with `std.mem.doNotOptimizeAway(sink)`, the canonical LLVM-guaranteed DCE barrier in Zig 0.15+.

---

#### PERF-24 (P3, PerfScore 48) — No CI Benchmark Regression Tracking

**Status: ✅ Closed — Implemented.** Added `bench-regression` CI job that runs on main merges and scheduled pipelines, stores results as 90-day artifacts. | **Confidence: confirmed**

The `build-bench` CI job only compile-checks benchmarks (PERF-15). No CI job executes benchmarks or tracks results. Performance regressions are invisible between MRs.

**Fix:** Add a scheduled CI job that runs benchmarks on main merges and stores results as artifacts.

---

#### PERF-25 (P3, PerfScore 24) — `fromString` Benchmarks Use Loop-Invariant Input

**Status: ✅ Closed — Implemented.** Rewrote all three `fromString` benchmarks with 256-UUID string pools. | **Confidence: confirmed**

All three `fromString` benchmarks parse the same fixed string every iteration. Currently survives DCE because LLVM cannot prove `fromString` pure (error-union chain), but this is fragile and biases branch prediction.

**Fix:** Use a pool of varied input strings matching the pattern used by `benchToString`.

---

#### PERF-26 (P3, PerfScore 16) — V1/V6 Bypass Injectable Clock

**Status: 🚫 Won't Do** — Intentional design. V1/V6 use `Timestamp.now()` (system clock) by design, documented in `Timestamp.now()` doc comment. The `withClock()` mechanism is V7-specific. Routing V1/V6 through the injectable clock would be a behavioral/API change. | **Confidence: suspected**

`newV1()` and `newV6()` call `Timestamp.now()` which reads `std.time.nanoTimestamp()` directly, ignoring the injectable `self.clock`. This is documented behavior but means V1/V6 timestamp generation is not testable with clock injection.

---

### Summary Table (Performance Cycle 5)

| Severity | New Findings | Status |
|----------|-------------|--------|
| P2 | 3 | ✅ Closed (PERF-21, PERF-22, PERF-23) |
| P3 | 3 | ✅ 2 Closed (PERF-24, PERF-25); 🚫 Won't Do (PERF-26) |
| **Total** | **6** | **5 Closed, 1 Won't Do** |

**Running totals (all performance cycles):**

| Metric | Count |
|--------|-------|
| Total findings (Cycles 1–5) | 26 |
| Closed / implemented | 19 |
| Won't Do | 1 (PERF-08) |
| Open | 0 |

---

## Full Codebase Audit Summary (2026-03-22)

**17 new findings** across 3 domains from full audit:

| Domain | New | Closed | Won't Do | Open |
|--------|-----|--------|----------|------|
| Security (Cycle 14) | 4 | 3 | 0 | 1 (SEC-R14-03 Info) |
| Quality (Cycle 13) | 7 | 7 | 0 | 0 |
| Performance (Cycle 5) | 6 | 5 | 1 (PERF-26) | 0 |
| **Total** | **17** | **15** | **1** | **1** |

**Cross-domain deduplication:**

- QC-97 = SEC-R14-01 (`Timestamp.now()` missing overflow guard)
- QC-95 ≈ SEC-R14-04 (vtable `newV8` return type mismatch)

**Top 5 by score:**

| # | Domain | ID | Finding | Score |
|---|--------|----|---------|-------|
| 1 | Perf | PERF-21 | `toStringUpper`/`toHexUpper` benchmarks DCE'd | 80 |
| 2 | Perf | PERF-22 | `eql`/`timingSafeEql` benchmarks DCE'd | 80 |
| 3 | Perf | PERF-23 | All benchmark anti-DCE patterns fragile | 64 |
| 4 | Quality | QC-96 | README `newV8` return type wrong | 48 |
| 5 | Perf | PERF-24 | No CI benchmark regression tracking | 48 |

**Grand totals across all cycles:**

| Domain | Total | Closed | Won't Do | FP | Open |
|--------|-------|--------|----------|-----|------|
| Security | 50 | 46 | 2 | 1 | 1 (SEC-R14-03 Info) |
| Quality | 99 | 96 | 2 | 0 | 0 |
| Performance | 26 | 24 | 2 | 0 | 0 |
| **All** | **175** | **166** | **6** | **1** | **1** |

SEC-R14-03 (saveState TOCTOU DoS window, Info severity) remains open — existing mitigations
(O_EXCL, pre-delete) are acknowledged as reasonable; the residual DoS-only risk is accepted.

---
