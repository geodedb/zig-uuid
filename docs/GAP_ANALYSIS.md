# UUID Library Gap Analysis

> Audit against [RFC-9562](https://www.rfc-editor.org/rfc/rfc9562) and
> [gofrs/uuid](https://github.com/gofrs/uuid) (the reference Go implementation).
>
> Date: 2026-03-21
> Last updated: 2026-03-21 — all actionable items implemented (including security findings from adversarial review).

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
