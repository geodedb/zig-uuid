# UUID Library Gap Analysis

> Audit against [RFC-9562](https://www.rfc-editor.org/rfc/rfc9562) and
> [gofrs/uuid](https://github.com/gofrs/uuid) (the reference Go implementation).
>
> Date: 2026-03-21

---

## Table of Contents

1. [RFC-9562 Compliance Gaps](#rfc-9562-compliance-gaps)
2. [Feature Gaps vs gofrs/uuid](#feature-gaps-vs-gofrsuuid)
3. [Prioritized Work Items](#prioritized-work-items)
4. [What Is Correct](#what-is-correct)

---

## RFC-9562 Compliance Gaps

### F-1 — V1/V6 embed real MAC address by default

**Severity:** ❌ SHOULD NOT violated (RFC §8)

**RFC text (§8):**
> "MAC addresses pose inherent security risks around privacy and SHOULD NOT be
> used within a UUID."

**Current behaviour (`src/hwaddr/hwaddr.zig`, `src/generator.zig:138-146`):**

`getNode()` calls `hwaddr_fn()` first and only falls back to a random node ID
when the syscall fails. On any machine with a live network interface (Linux,
macOS, Windows), V1 and V6 UUIDs will embed the host's real hardware address.

```zig
fn getNode(self: *Generator) Error![6]u8 {
    if (self.hwaddr_fn()) |mac| return mac else |_| {
        // Random node ID with multicast bit set (RFC-9562 §6.10)
        var node: [6]u8 = undefined;
        self.rand(&node) catch return Error.RandomError;
        node[0] |= 0x01;
        return node;
    }
}
```

**Required fix:** Reverse the default. Use a random multicast node ID by
default; expose `hwaddr_fn` as an explicit opt-in for callers that need
MAC-based nodes (e.g. distributed systems that rely on node identity for
conflict avoidance).

**Impact:** Privacy, security. Any V1/V6 UUID leaks the generating host's MAC
address to anyone who receives it.

---

### F-2 — `UUID.version()` panics on unknown version nibbles

**Severity:** ⚠️ Safety / correctness

**Location:** `src/uuid.zig:52-54`

```zig
pub fn version(self: UUID) Version {
    return @enumFromInt(self.bytes[6] >> 4);
}
```

`@enumFromInt` in Zig causes a safety-checked panic (Debug/ReleaseSafe) or
undefined behaviour (ReleaseFast) when the value is not a member of the target
enum. The `Version` enum only covers `{1, 3, 4, 5, 6, 7, 8}`. The following
nibble values are not members:

| Nibble | Cause |
|--------|-------|
| `0` | Nil UUID (`UUID.nil`) |
| `2` | DCE Security UUID (V2) |
| `9`–`15` | Future / unassigned versions |

Calling `uuid.UUID.nil.version()` panics unconditionally.

**Required fix:** Return `?Version` (null on unknown), or add an `unknown`
catch-all member to the enum, or rename the function `versionUnchecked` and
add a safe `version() ?Version` wrapper.

---

### F-3 — Clock sequence fallback is not random

**Severity:** ⚠️ MUST edge case (RFC §6.1)

**RFC text (§6.1):**
> "The clock sequence MUST be originally initialized to a random number."

**Location:** `src/generator.zig:127-135`

```zig
fn initClockSeq(self: *Generator) void {
    if (self.clock_seq_initialized) return;
    var buf: [2]u8 = undefined;
    self.rand(&buf) catch {
        buf = .{ 0x12, 0x34 }; // fallback
    };
    self.clock_seq = @truncate(std.mem.readInt(u16, &buf, .little) & 0x3FFF);
    self.clock_seq_initialized = true;
}
```

If `self.rand` fails, `clock_seq` is set to the hardcoded constant `0x1234`
(`4660` decimal). This violates the RFC MUST. In practice CSPRNG failure is
extremely rare and usually indicates a catastrophically broken system, but
the violation is real.

**Required fix:** Propagate the error from `initClockSeq` (making it `!void`)
and return it from `newV1AtTime`/`newV6AtTime` rather than silently using a
fixed value.

---

### F-4 — V1/V6 do not detect node ID changes

**Severity:** ⚠️ SHOULD gap (RFC §6.1)

**RFC text (§6.1):**
> "If the node ID changes (e.g., because a network card has been moved between
> machines), the clock sequence SHOULD be changed."

**Location:** `src/generator.zig:127-203`

The generator tracks `last_v1_ts` for clock regression, but does not record
the last node ID used. If the node ID changes between two calls (e.g., the
injectable `hwaddr_fn` returns a different MAC, or the network interface
changes), `clock_seq` is not incremented.

**Required fix:** Store `last_node: [6]u8` in the `Generator` struct. In
`newV1AtTime` and `newV6AtTime`, compare the new node against `last_node`; if
different, increment `clock_seq` and update `last_node`.

---

### F-5 — No URN output method

**Severity:** ⚠️ Missing feature (RFC §4 / §8 ABNF)

**RFC ABNF (§4):**
> `UUID-URI = "urn:uuid:" UUID`

`fromString` correctly parses `urn:uuid:` input. There is no corresponding
output method. Callers that need URN-format output (XML schemas, LDAP
attributes, certain REST APIs) must manually prepend `"urn:uuid:"`.

**Required fix:** Add `pub fn toURN(self: UUID, buf: *[45]u8) []u8` and
`pub fn toURNAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8`.

---

### F-6 — RFC Appendix A test vectors not fully asserted

**Severity:** ⚠️ Test coverage

**RFC Appendix A test vectors:**

| Vector | Expected UUID | Status |
|--------|--------------|--------|
| A.1 V1 — ts=`0x01EC9414C232AB00`, node=`9F6BDECED846`, seq=`0x33C8` | `C232AB00-9414-11EC-B3C8-9F6BDECED846` | ⚠️ Not asserted |
| A.2 V3 — DNS + `"www.example.com"` | `5df41881-3aed-3515-88a7-2f4a814cf09e` | ✅ Asserted |
| A.3 V4 — random | N/A | ✅ N/A |
| A.4 V5 — DNS + `"www.example.com"` | `2ed6657d-e927-568b-95e1-2665a8aea6a2` | ✅ Asserted |
| A.5 V6 — ts=`0x01EC9414C232AB00`, node=`9F6BDECED846`, seq=`0x33C8` | `1EC9414C-232A-6B00-B3C8-9F6BDECED846` | ⚠️ Not asserted |
| A.6 V7 — ts=`0x017F22E279B0` (Unix ms) | starts `017F22E2-79B0-7...` | ⚠️ Not asserted |

The V1 and V6 layouts have been verified by code analysis to be correct, but
pinning the RFC-specified test vectors in the test suite would make regressions
immediately visible.

**Required fix:** Add deterministic tests to `src/generator.zig` using the
exact RFC Appendix A timestamps, node IDs, and clock sequences via
`newV1AtTime`/`newV6AtTime`/`newV7AtTime` with mock clock and hwaddr functions.

---

### F-7 — `Timestamp.now()` unchecked cast on pre-1970 system clock

**Severity:** ℹ️ Robustness

**Location:** `src/timestamp.zig`

`Timestamp.now()` calls `std.time.nanoTimestamp()` (returns `i128`) and casts
to `u64` via `@intCast`. On a machine whose system clock is set before
1970-01-01 (the Unix epoch), the nanosecond value is negative and `@intCast`
panics in Debug/ReleaseSafe, or wraps to a very large `u64` in ReleaseFast.

**Required fix:** Check for negative values and return `Error.InvalidFormat`
(or a new `Error.InvalidTimestamp`) rather than panicking.

---

### F-8 — Shared V1/V6 clock_seq state is undocumented

**Severity:** ℹ️ Documentation

**Location:** `src/generator.zig:35-37`

```zig
clock_seq: u14 = 0,
clock_seq_initialized: bool = false,
last_v1_ts: u60 = 0,
```

`newV1AtTime` and `newV6AtTime` share `clock_seq` and `last_v1_ts`. Interleaving
V1 and V6 calls on the same generator causes each version to see the other's
timestamp updates. This is architecturally correct (they are both Gregorian-time
UUIDs and share a clock domain), but callers who mix V1 and V6 will observe
unexpected clock_seq increments if they are not aware of this.

**Required fix:** Add a doc comment on `Generator` explaining the shared state,
and document the same in the README.

---

### F-9 — No persistent state across process restarts

**Severity:** ℹ️ Not required (RFC §6.3 SHOULD)

**RFC text (§6.3):**
> "The UUID generation software SHOULD save the state of the generator to stable
> storage when possible."

The generator is entirely in-memory. After a process restart, `clock_seq` is
re-randomized and `last_v1_ts` resets to zero. For V1/V6 generators running on
a fast machine where the clock can regress across a restart window, duplicate
UUIDs are theoretically possible within the same 100-ns interval.

**Required fix (optional):** Provide an optional `Generator.saveState` /
`Generator.loadState` pair for callers that need cross-restart uniqueness
guarantees. Not required for most applications.

---

## Feature Gaps vs gofrs/uuid

### G-1 — No binary marshal / unmarshal

**Severity:** High value — essential for wire protocols

**gofrs equivalent:**

```go
func (u UUID) MarshalBinary() ([]byte, error)       // returns 16-byte slice
func (u *UUID) UnmarshalBinary(data []byte) error   // requires exactly 16 bytes
```

16-byte binary is the most compact UUID encoding. It is used by gRPC, Redis,
PostgreSQL's native UUID type, and most binary serialization formats (protobuf,
MessagePack, CBOR). The current library has `fromBytes` and `.bytes` field
access but no `toBytes()` convenience function that returns a `[16]u8` copy.

**Required additions:**

```zig
// In UUID:
pub fn toBytes(self: UUID) [16]u8 { return self.bytes; }
// fromBytes already exists
```

---

### G-2 — No `fmt`-style format verbs / uppercase output

**Severity:** High value — commonly needed output formats

**gofrs equivalents (via `fmt.Formatter`):**

| Verb | Output |
|------|--------|
| `%s`, `%v` | `6ba7b810-9dad-11d1-80b4-00c04fd430c8` (lowercase, dashes) |
| `%S` | `6BA7B810-9DAD-11D1-80B4-00C04FD430C8` (uppercase, dashes) |
| `%x` | `6ba7b8109dad11d180b400c04fd430c8` (lowercase, no dashes) |
| `%X` | `6BA7B8109DAD11D180B400C04FD430C8` (uppercase, no dashes) |
| `%q` | `"6ba7b810-9dad-11d1-80b4-00c04fd430c8"` (quoted) |

The current library only outputs lowercase with dashes (`toString`, `toStringAlloc`,
`format`).

**Required additions to `UUID`:**

```zig
pub fn toStringUpper(self: UUID, buf: *[36]u8) []u8 { ... }
pub fn toStringUpperAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 { ... }
pub fn toHex(self: UUID, buf: *[32]u8) []u8 { ... }       // no dashes, lower
pub fn toHexUpper(self: UUID, buf: *[32]u8) []u8 { ... }  // no dashes, upper
```

---

### G-3 — No URN output

**Severity:** Medium (also RFC gap F-5)

**gofrs:** No `toURN()` either (same gap). Both libraries parse URN input but
cannot produce it.

**Required addition:**

```zig
pub fn toURN(self: UUID, buf: *[45]u8) []u8 { ... }
pub fn toURNAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 { ... }
```

---

### G-4 — `timestampFromV7` returns `i64` ms, not `Timestamp`

**Severity:** Medium — API inconsistency

**gofrs API:** All three extraction functions return a unified `Timestamp` type
(100-ns intervals since the Gregorian epoch). Callers use `Timestamp.Time()` to
convert to wall clock time.

**Current Zig API:**

```zig
pub fn timestampFromV1(u: UUID) Error!Timestamp  // Gregorian 100-ns value
pub fn timestampFromV6(u: UUID) Error!Timestamp  // Gregorian 100-ns value
pub fn timestampFromV7(u: UUID) Error!i64        // Unix milliseconds — different type!
```

`timestampFromV7` returns a raw `i64` millisecond value, inconsistent with V1
and V6 which return the `Timestamp` struct.

**Required fix:** Either return `Timestamp` from `timestampFromV7` (converting
Unix ms to Gregorian 100-ns), or introduce a `UnixMs` newtype and consistently
use it for all three functions, with explicit conversion helpers.

---

### G-5 — No `Timestamp` → wall clock conversion

**Severity:** Medium — core use case

**gofrs equivalent:**

```go
func (t Timestamp) Time() (time.Time, error)
```

Callers who extract a V1/V6/V7 timestamp typically want a human-readable time
value, not a raw 100-ns integer. There is no `Timestamp.toUnixMs()`,
`Timestamp.toUnixNs()`, or similar conversion in the current library.

**Required additions to `Timestamp`:**

```zig
pub fn toUnixNs(self: Timestamp) i128 { ... }
pub fn toUnixMs(self: Timestamp) i64 { ... }
pub fn toUnixSec(self: Timestamp) i64 { ... }
```

---

### G-6 — MAC address fetched on every V1/V6 generation

**Severity:** Medium — performance

**gofrs behaviour:** The hardware address is fetched once per `*Gen` instance
via `sync.Once` and cached. Subsequent V1/V6 calls reuse the cached value.

**Current behaviour:** `getNode()` calls `self.hwaddr_fn()` on every call to
`newV1AtTime` and `newV6AtTime`. On Linux this invokes `SIOCGIFCONF` +
`SIOCGIFHWADDR` syscalls; on macOS it calls `getifaddrs`; on Windows it calls
`GetAdaptersAddresses`. These are expensive for high-throughput generation.

**Required fix:** Add a `cached_node: ?[6]u8` field to `Generator`. On the
first call, populate it and store. Subsequent calls return the cached value.
Provide a `clearNodeCache()` method for callers whose node ID may change.

---

### G-7 — No `fromStringOrNil` / `fromBytesOrNil` convenience variants

**Severity:** Low — convenience

**gofrs equivalents:**

```go
func FromStringOrNil(input string) UUID  // returns Nil on parse error
func FromBytesOrNil(input []byte) UUID   // returns Nil on wrong length
```

Useful for package-level variable initialization where a parse error is a
programming bug (e.g., known-good UUID literals). The current library requires
callers to handle the error union every time.

**Required additions:**

```zig
pub fn fromStringOrNil(s: []const u8) UUID {
    return UUID.fromString(s) catch UUID.nil;
}
pub fn fromBytesOrNil(b: []const u8) UUID {
    return UUID.fromBytes(b) catch UUID.nil;
}
```

---

### G-8 — No `Generator` interface / abstraction

**Severity:** Low — extensibility

**gofrs design:** `Generator` is an interface. `*Gen` is the concrete
implementation. Callers can pass around `Generator` values and mock them in
tests without touching global state.

**Current design:** `Generator` is a concrete struct. Injectable function
pointers (`clock`, `rand`, `hwaddr_fn`) provide testability, but there is no
way to swap the entire generator implementation behind an interface boundary.

**Required addition:** Define a `GeneratorInterface` that matches the public
method signatures of `Generator`, allowing alternative implementations.

---

### G-9 — No `IsZero()` alias

**Severity:** Low — ecosystem compatibility

**gofrs:** `IsZero()` is identical to `IsNil()` but satisfies the
`bsoncodec.Zeroer` interface for MongoDB BSON `omitzero` struct tag support.

**Required addition:**

```zig
pub fn isZero(self: UUID) bool { return self.isNil(); }
```

---

### G-10 — `version()` unsafe for unknown nibbles (also RFC F-2)

**Severity:** ⚠️ (duplicate of F-2, listed here for feature comparison)

**gofrs behaviour:** `Version()` returns a raw `byte`. No panic on unknown
values. Callers compare against the `V1`–`V8` constants and handle unknown
values with an `else` branch.

**Current behaviour:** Returns a `Version` enum member; panics on unrecognised
nibbles.

---

## Prioritized Work Items

### Priority 1 — Fix now (correctness / safety)

| Item | File(s) | Effort |
|------|---------|--------|
| **F-1** — Default V1/V6 node to random; make MAC opt-in | `generator.zig` | Small |
| **F-2** — Make `version()` safe for unknown nibbles | `uuid.zig` | Small |
| **F-6** — Add RFC Appendix A.1, A.5, A.6 test vectors | `generator.zig` | Small |

### Priority 2 — High value additions

| Item | File(s) | Effort |
|------|---------|--------|
| **G-1** — `toBytes()` convenience method | `uuid.zig` | Trivial |
| **G-2** — Uppercase and no-dash output formats | `uuid.zig` | Small |
| **G-4** — Unify `timestampFromV7` return type with V1/V6 | `timestamp.zig` | Small |
| **G-5** — `Timestamp` → Unix ns/ms/sec conversions | `timestamp.zig` | Small |
| **G-6** — Cache MAC address per generator instance | `generator.zig` | Medium |
| **F-5 / G-3** — URN output (`toURN`, `toURNAlloc`) | `uuid.zig` | Small |

### Priority 3 — Nice to have

| Item | File(s) | Effort |
|------|---------|--------|
| **F-3** — Propagate CSPRNG failure in `initClockSeq` | `generator.zig` | Small |
| **F-4** — Track last node; increment clock_seq on node change | `generator.zig` | Small |
| **F-7** — Guard `Timestamp.now()` against pre-1970 clocks | `timestamp.zig` | Trivial |
| **F-8** — Document shared V1/V6 clock_seq state | `generator.zig`, README | Trivial |
| **G-7** — `fromStringOrNil` / `fromBytesOrNil` | `uuid.zig` | Trivial |
| **G-9** — `isZero()` alias | `uuid.zig` | Trivial |

### Priority 4 — Optional / future

| Item | File(s) | Effort |
|------|---------|--------|
| **G-8** — `Generator` interface / abstraction | `generator.zig`, `root.zig` | Medium |
| **F-9** — Persistent generator state across restarts | new file | Large |

---

## What Is Correct

The following areas were audited and are fully compliant:

- **All version/variant bit placements** — V1, V3, V4, V5, V6, V7, V8 byte
  layouts match the RFC exactly.
- **V3 and V5 test vectors** — `5df41881-...` and `2ed6657d-...` are asserted
  and passing.
- **V7 monotonicity** — Method 1 (RFC §6.2): fixed 12-bit counter in `rand_a`,
  randomly seeded each new millisecond tick, incremented within the same tick,
  mutex-protected, overflow spins until clock advances.
- **Gregorian epoch offset** — `122_192_928_000_000_000` is exact
  (`0x01B21DD213814000`).
- **Namespace UUIDs** — All four RFC §6.6 namespaces (DNS, URL, OID, X.500)
  are byte-for-byte correct.
- **Random multicast fallback** — When MAC unavailable, `node[0] |= 0x01` sets
  the multicast bit per RFC §6.10.
- **CSPRNG usage** — `std.crypto.random` used throughout; meets RFC §6.9.
- **Clock regression handling** — V1 and V6 both increment `clock_seq` on
  regression and share `last_v1_ts`.
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
