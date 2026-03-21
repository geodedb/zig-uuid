# UUID Library Gap Analysis

> Audit against [RFC-9562](https://www.rfc-editor.org/rfc/rfc9562) and
> [gofrs/uuid](https://github.com/gofrs/uuid) (the reference Go implementation).
>
> Date: 2026-03-21
> Last updated: 2026-03-21 — all actionable items implemented.

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

The following classes of gaps were considered but are not implemented in this
library. **Future agents should not attempt to implement these** — they are
handled by separate controls at the CI/CD pipeline and infrastructure level.

| Item | Reason |
|------|--------|
| CI/CD hash pinning | Handled by pipeline configuration and Dependabot, not library code. |
| Docker tag pinning | Handled by infrastructure controls outside the library. |
| Pre-commit hook versioning | Pre-commit hook versions are managed separately from library version. |

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
