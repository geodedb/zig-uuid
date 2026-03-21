# UUID Library Design

**Date:** 2026-03-21
**Status:** Approved
**Reference:** [gofrs/uuid](https://github.com/gofrs/uuid) (RFC-9562 / RFC-4122)

---

## Overview

A fully RFC-9562-compliant UUID library for Zig 0.15.1+, implementing all standard UUID versions
(V1, V3, V4, V5, V6, V7, V8) with cross-platform support, an injectable generator for testability
and timestamp injection, JSON serialization via `gitlab.com/devnw/zig/json`, and a complete test suite.

---

## Goals

- Full RFC-9562 compliance for UUID versions V1, V3, V4, V5, V6, V7, V8
- Cross-platform MAC address resolution (Linux, macOS, Windows) with correct endian handling
- Injectable generator: swappable clock, random, and hardware address sources
- Multiple parse formats: canonical, braced, hash, URN
- NullUUID with JSON marshal/unmarshal via the devnw json library
- 80%+ test coverage with unit, integration, and concurrent tests
- Pre-commit hooks enforced before all commits and pushes

---

## Non-Goals

- UUID V2 (DCE Security) — removed per RFC-9562 and gofrs precedent
- SQL `Scan`/`Value` database interfaces — out of scope for v0.1.0
- A standalone binary or CLI tool

---

## Architecture: Approach B — Feature-Based Modules

Each concern gets its own focused file (`< 800` lines each), all re-exported from `src/root.zig`.

### File Layout

```text
src/
  root.zig          # Public API — re-exports all public symbols
  uuid.zig          # UUID type, parse/format, Version/Variant enums, Error
  versions.zig      # Top-level newV1()…newV8() delegating to default_generator
  generator.zig     # Generator struct with injectable clock/rand/hwaddr + V7 monotonicity
  timestamp.zig     # Timestamp type (Gregorian epoch, V1/V6) + extraction functions
  namespace.zig     # nil, max, namespace_dns/url/oid/x500 constants (snake_case)
  null_uuid.zig     # NullUUID with jsonMarshal/jsonUnmarshal
  hwaddr/
    hwaddr.zig      # Comptime platform dispatch + application-level GUID interop helpers
    linux.zig       # SIOCGIFCONF / SIOCGIFHWADDR ioctls via std.posix
    macos.zig       # getifaddrs() + AF_LINK sockaddr via std.posix
    windows.zig     # GetAdaptersAddresses (Windows Vista+) + GUID endian conversion

tests/
  integration.zig   # Cross-module and concurrent integration tests

examples/
  basic.zig         # (updated) Usage examples for all versions
```

---

## Component Designs

### 1. Core UUID Type (`src/uuid.zig`)

Fixed `[16]u8` array. All operations are pure value semantics — no heap allocation.

```zig
pub const UUID = struct {
    bytes: [16]u8,

    // Sentinels
    pub const nil: UUID = .{ .bytes = [_]u8{0x00} ** 16 };
    pub const max: UUID = .{ .bytes = [_]u8{0xFF} ** 16 };

    // Inspection
    pub fn version(self: UUID) Version { ... }
    pub fn variant(self: UUID) Variant { ... }
    pub fn isNil(self: UUID) bool { ... }

    // Low-level mutation (for generator use only)
    pub fn setVersion(self: *UUID, v: Version) void { ... }
    pub fn setVariant(self: *UUID, v: Variant) void { ... }

    // Parsing — accepts all six formats (see Parse Formats below)
    // UUID.fromString is zero-alloc; no allocator parameter needed.
    pub fn fromString(s: []const u8) Error!UUID { ... }
    pub fn fromBytes(b: []const u8) Error!UUID { ... }

    // Output — zero-alloc buffer + allocating variants
    pub fn toString(self: UUID, buf: *[36]u8) []u8 { ... }
    pub fn toStringAlloc(self: UUID, alloc: Allocator) ![]u8 { ... }

    // std.fmt integration
    pub fn format(self: UUID, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void { ... }

    // Ordering and hashing
    pub fn eql(self: UUID, other: UUID) bool { ... }
    pub fn order(self: UUID, other: UUID) std.math.Order { ... }
    pub const HashContext = struct { ... };  // for std.HashMap

    // json library custom marshaler (UUID.fromString is zero-alloc; allocator
    // parameter in jsonUnmarshal exists for interface conformance only)
    pub fn jsonMarshal(self: UUID, allocator: Allocator) !json.Value { ... }
    pub fn jsonUnmarshal(allocator: Allocator, v: json.Value) !UUID { ... }
};

pub const Version = enum(u8) { v1=1, v3=3, v4=4, v5=5, v6=6, v7=7, v8=8 };
pub const Variant = enum(u8) { ncs, rfc9562, microsoft, future };
```

**Parse formats supported:**

| Format | Example |
|---|---|
| Canonical | `6ba7b810-9dad-11d1-80b4-00c04fd430c8` |
| Braced canonical | `{6ba7b810-9dad-11d1-80b4-00c04fd430c8}` |
| Hash (no dashes) | `6ba7b8109dad11d180b400c04fd430c8` |
| Braced hash | `{6ba7b8109dad11d180b400c04fd430c8}` |
| URN canonical | `urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8` |
| URN hash | `urn:uuid:6ba7b8109dad11d180b400c04fd430c8` |

**Error set:**

```zig
pub const Error = error{
    InvalidFormat,
    InvalidLength,
    InvalidBraces,
    InvalidURNPrefix,
    InvalidDashes,
    IncorrectByteLength,
    NoHWAddressFound,
    InvalidVersion,
    V8FieldLength,
    RandomError,         // CSPRNG failure from RandFn
};
```

---

### 2. Timestamp Type (`src/timestamp.zig`)

`Timestamp` is exclusively for the **Gregorian epoch** (1582-10-15) 100-ns counter used by V1
and V6. V7 uses a bare `i64` Unix millisecond value — `Timestamp` is never used for V7. This
is intentional and matches the gofrs design.

```zig
/// Count of 100-ns intervals since 1582-10-15 (Gregorian epoch).
/// Used exclusively by V1 and V6. V7 uses bare i64 Unix milliseconds.
pub const Timestamp = struct {
    value: u60,

    pub fn toUnixNano(self: Timestamp) i128 { ... }
    pub fn fromUnixNano(ns: i128) Timestamp { ... }
    pub fn now() Timestamp { ... }
};

/// Extract Gregorian timestamp from a V1 UUID.
pub fn timestampFromV1(u: UUID) Error!Timestamp { ... }

/// Extract Gregorian timestamp from a V6 UUID.
pub fn timestampFromV6(u: UUID) Error!Timestamp { ... }

/// Extract Unix millisecond timestamp from a V7 UUID.
/// Returns i64 (not Timestamp) — V7 uses Unix epoch, not Gregorian epoch.
pub fn timestampFromV7(u: UUID) Error!i64 { ... }
```

Interop uses `i128` nanoseconds (`std.time.nanoTimestamp()`), the natural Zig time unit.

---

### 3. UUID Version Bit Layouts

#### V1 — Time + MAC (RFC-9562 §5.1)

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           time_low                            |  bytes 0-3
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           time_mid            |  ver(4) |     time_high       |  bytes 4-7
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|var(2)|       clock_seq        |           node[0]             |  bytes 8-9, 10
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           node[1-5]                           |  bytes 11-15
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- `time_*`: 60-bit Gregorian 100-ns timestamp, split as low(32)/mid(16)/high(12)
- `ver`: 4-bit version = 0x1
- `var`: 2-bit RFC variant = 0b10
- `clock_seq`: 14-bit counter (see Generator clock_seq field below)
- `node`: 48-bit MAC address or random fallback (RFC-9562 §6.10)

#### V3 — MD5 Name Hash (RFC-9562 §5.3)

Fill all 16 bytes with MD5(namespace_bytes || name_bytes), then:

- `bytes[6]`: `(bytes[6] & 0x0F) | 0x30` (version 3)
- `bytes[8]`: `(bytes[8] & 0x3F) | 0x80` (RFC variant)

#### V4 — Random (RFC-9562 §5.4)

Fill all 16 bytes with CSPRNG output, then:

- `bytes[6]`: `(bytes[6] & 0x0F) | 0x40` (version 4)
- `bytes[8]`: `(bytes[8] & 0x3F) | 0x80` (RFC variant)

#### V5 — SHA-1 Name Hash (RFC-9562 §5.5)

Fill bytes 0–15 with SHA-1[namespace_bytes || name_bytes](0..16), then:

- `bytes[6]`: `(bytes[6] & 0x0F) | 0x50` (version 5)
- `bytes[8]`: `(bytes[8] & 0x3F) | 0x80` (RFC variant)

#### V6 — Reordered Time + MAC (RFC-9562 §5.6)

V6 reorders V1's timestamp fields for lexicographic sortability (most-significant bits first):

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        time_high                              |  bytes 0-3  (bits 28-59 of 60-bit ts)
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           time_mid            |  ver(4) |     time_low        |  bytes 4-7  (bits 12-27, ver, bits 0-11)
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|var(2)|       clock_seq        |           node[0]             |  bytes 8-9, 10  (same as V1)
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           node[1-5]                           |  bytes 11-15
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- `time_high/mid/low`: same 60-bit Gregorian 100-ns timestamp as V1, reordered for sort
- `ver`: 4-bit version = 0x6
- `var`, `clock_seq`, `node`: same semantics as V1

To extract a Gregorian timestamp from V6: reassemble the timestamp bits from their reordered
positions back into the V1 field order before constructing a `Timestamp`.

#### V7 — Unix Millisecond Timestamp (RFC-9562 §5.7)

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         unix_ts_ms (high 32 bits)             |  bytes 0-3
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    unix_ts_ms (low 16 bits)   |  ver(4) |     rand_a (12)     |  bytes 4-7
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|var(2)|              rand_b (62 bits)                           |  bytes 8-15
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- `unix_ts_ms`: 48-bit Unix timestamp in milliseconds (big-endian), bytes 0–5
- `ver`: 4-bit version = 0x7, high nibble of byte 6
- `rand_a`: 12-bit monotonic counter (low 12 bits of bytes 6–7, after version nibble)
- `var`: 2-bit RFC variant = 0b10, high 2 bits of byte 8
- `rand_b`: 62-bit random data (low 62 bits of bytes 8–15, after variant bits)

#### V8 — Custom (RFC-9562 §5.8)

```zig
// Parameters map to RFC-9562 fields as follows:
// a: [6]u8  → custom_a: bits 0–47  (bytes 0–5, all 48 bits used)
// b: [2]u8  → custom_b: bits 52–63 (bytes 6–7; lower 12 bits used, upper 4 masked for version)
// c: [8]u8  → custom_c: bits 66–127 (bytes 8–15; lower 62 bits used, upper 2 masked for variant)
//
// The generator masks version bits into byte 6 and variant bits into byte 8.
// Parameters represent raw application data; the generator applies masks.
```

---

### 4. Generator (`src/generator.zig`)

Runtime-swappable function pointers for clock, randomness, and hardware address.
Thread-safe via `std.Thread.Mutex`.

```zig
pub const ClockFn  = *const fn () i128;
/// RandFn must fill buf with cryptographically secure random bytes.
/// Returns an error if the OS CSPRNG is unavailable (e.g. early boot).
pub const RandFn   = *const fn (buf: []u8) anyerror!void;
pub const HWAddrFn = *const fn () Error![6]u8;

pub const Generator = struct {
    clock:      ClockFn  = defaultClock,
    rand:       RandFn   = defaultRand,
    hwaddr:     HWAddrFn = hwaddr.get,

    // V7 monotonicity state — all fields protected by mutex
    mutex:      std.Thread.Mutex = .{},
    last_ms:    i64 = 0,     // last Unix millisecond seen
    mono_seq:   u12 = 0,     // 12-bit counter within current millisecond

    // V1/V6 state — clock sequence (RFC-9562 §4.2.1)
    // Initialized to a random value on first use; incremented on clock regression.
    clock_seq:  u14 = 0,
    clock_seq_initialized: bool = false,

    pub fn init() Generator { ... }
    pub fn withClock(f: ClockFn) Generator { ... }
    pub fn withRand(f: RandFn) Generator { ... }
    pub fn withHWAddr(f: HWAddrFn) Generator { ... }

    pub fn newV1(self: *Generator) Error!UUID { ... }
    pub fn newV1AtTime(self: *Generator, ts: Timestamp) Error!UUID { ... }
    pub fn newV3(self: *Generator, ns: UUID, name: []const u8) UUID { ... }
    pub fn newV4(self: *Generator) Error!UUID { ... }
    pub fn newV5(self: *Generator, ns: UUID, name: []const u8) UUID { ... }
    pub fn newV6(self: *Generator) Error!UUID { ... }
    pub fn newV6AtTime(self: *Generator, ts: Timestamp) Error!UUID { ... }
    pub fn newV7(self: *Generator) Error!UUID { ... }
    /// ts is Unix milliseconds (i64). newV7AtTime participates in monotonicity:
    /// it updates last_ms and mono_seq so that subsequent newV7() calls remain
    /// monotonic after an injected historical timestamp.
    pub fn newV7AtTime(self: *Generator, ts: i64) Error!UUID { ... }
    pub fn newV8(self: *Generator, a: [6]u8, b: [2]u8, c: [8]u8) Error!UUID { ... }
};

/// Thread-safe package-level default generator.
pub var default_generator: Generator = Generator.init();
```

**V7 monotonicity (spin strategy):** Within the same millisecond, `mono_seq` is incremented
under mutex. On `mono_seq` overflow (all 12 bits exhausted within one ms), the generator
**spins calling the clock function** until `current_ms > last_ms`, then resets `mono_seq` to a
fresh random 12-bit value for maximum entropy. This is a spin-wait strategy, distinct from
RFC-9562 §6.2 Method 1 (which increments the timestamp field rather than spinning). When
`current_ms > last_ms` in the normal case, `mono_seq` is **reset to a random 12-bit value**
(not zero) to maximize entropy per RFC-9562 §6.2 recommendation.

**V1/V6 clock sequence:** `clock_seq` is a 14-bit field (stored in bytes 8–9, after the 2-bit
variant). On first use, it is initialized to a random value via `rand`. It is incremented
(mod 2^14) whenever the clock is observed to have regressed or the node ID changes.
`clock_seq` is protected by the same mutex as `last_ms`/`mono_seq`.

**Node ID selection (V1/V6):** `hwaddr()` is called per-generation. On `NoHWAddressFound`,
the generator falls back to generating a random 48-bit node ID with the multicast bit set
(bit 40 = 1) per RFC-9562 §6.10, ensuring no collision with real MAC addresses.

**Timestamp injection:** `newV1AtTime`, `newV6AtTime`, and `newV7AtTime` accept a caller-
supplied timestamp to support records whose creation time differs from collection time.
`newV7AtTime` updates `last_ms`/`mono_seq` so subsequent `newV7()` calls remain monotonic.

---

### 5. Platform HW Address (`src/hwaddr/`)

Comptime dispatch — no runtime branching, no conditional compilation flags needed.

```zig
// src/hwaddr/hwaddr.zig
pub fn get() Error![6]u8 {
    return switch (builtin.os.tag) {
        .linux   => linux.getHWAddr(),
        .macos   => macos.getHWAddr(),
        .windows => windows.getHWAddr(),
        else     => Error.NoHWAddressFound,
    };
}
```

| File | Mechanism |
|---|---|
| `linux.zig` | `SIOCGIFCONF` / `SIOCGIFHWADDR` ioctls via `std.posix` |
| `macos.zig` | `getifaddrs()` → `AF_LINK` sockaddr via `std.posix` |
| `windows.zig` | `GetAdaptersAddresses` (Vista+) — returns `IP_ADAPTER_ADDRESSES` |

All three platform files skip loopback and zero-MAC interfaces, return the first valid MAC found.

**Windows — `GetAdaptersAddresses`:** The `IP_ADAPTER_ADDRESSES` struct exposes
`PhysicalAddress: [8]u8` (a plain byte array, not a GUID). The first
`PhysicalAddressLength` bytes are the MAC address in network byte order — no endian
conversion needed for the MAC itself.

**Windows GUID interop (application-level):** Windows COM/WinRT APIs use the `GUID` struct
whose first three fields are **little-endian** (`Data1: u32 LE`, `Data2: u16 LE`,
`Data3: u16 LE`) while `Data4: [8]u8` is big-endian (network order). RFC UUIDs are fully
big-endian. The `hwaddr.zig` file exposes conversion helpers for application code that needs
to interop with Windows GUID APIs (distinct from the MAC address extraction):

```zig
// src/hwaddr/hwaddr.zig — application-level GUID interop helpers
pub fn guidToUUID(guid: GUID) UUID {
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4],  guid.Data1, .big);  // LE → BE
    std.mem.writeInt(u16, bytes[4..6],  guid.Data2, .big);  // LE → BE
    std.mem.writeInt(u16, bytes[6..8],  guid.Data3, .big);  // LE → BE
    @memcpy(bytes[8..16], &guid.Data4);                      // already BE
    return UUID{ .bytes = bytes };
}

pub fn uuidToGUID(u: UUID) GUID {
    return .{
        .Data1 = std.mem.readInt(u32, u.bytes[0..4], .big),
        .Data2 = std.mem.readInt(u16, u.bytes[4..6], .big),
        .Data3 = std.mem.readInt(u16, u.bytes[6..8], .big),
        .Data4 = u.bytes[8..16].*,
    };
}
```

These helpers are re-exported from `root.zig` on Windows builds only (comptime-gated).

**Key invariant:** `UUID.bytes` is **always** RFC network byte order (big-endian) on all
platforms. Endian conversion for GUID interop happens only at the `guidToUUID`/`uuidToGUID`
boundary.

---

### 6. Namespace Constants (`src/namespace.zig`)

Comptime constants — no allocation, no initialization. Exported with `snake_case` names
(Zig convention for constants).

```zig
pub const nil         = UUID{ .bytes = [_]u8{0x00} ** 16 };
pub const max         = UUID{ .bytes = [_]u8{0xFF} ** 16 };
pub const namespace_dns  = UUID{ .bytes = .{0x6b,0xa7,0xb8,0x10,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8} };
pub const namespace_url  = UUID{ .bytes = .{0x6b,0xa7,0xb8,0x11,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8} };
pub const namespace_oid  = UUID{ .bytes = .{0x6b,0xa7,0xb8,0x12,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8} };
pub const namespace_x500 = UUID{ .bytes = .{0x6b,0xa7,0xb8,0x14,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8} };
```

---

### 7. NullUUID (`src/null_uuid.zig`)

Nullable UUID wrapper using the `gitlab.com/devnw/zig/json` library's
`jsonMarshal`/`jsonUnmarshal` custom marshaler convention.

```zig
const json = @import("json");

pub const NullUUID = struct {
    uuid:  UUID = UUID.nil,
    valid: bool = false,

    pub fn from(u: UUID) NullUUID { ... }
    pub fn value(self: NullUUID) ?UUID { ... }

    /// Emits null JSON or "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    pub fn jsonMarshal(self: NullUUID, allocator: Allocator) !json.Value {
        if (!self.valid) return .null;
        var buf: [36]u8 = undefined;
        return .{ .str = try allocator.dupe(u8, self.uuid.toString(&buf)) };
    }

    /// Accepts null JSON or a quoted canonical UUID string.
    /// allocator parameter exists for interface conformance; UUID.fromString is zero-alloc.
    pub fn jsonUnmarshal(allocator: Allocator, v: json.Value) !NullUUID {
        _ = allocator;  // UUID.fromString is zero-alloc; parameter for interface conformance
        return switch (v) {
            .null => .{},
            .str  => |s| .{ .uuid = try UUID.fromString(s), .valid = true },
            else  => error.InvalidFormat,
        };
    }
};
```

`UUID` itself also implements `jsonMarshal`/`jsonUnmarshal` for non-nullable struct fields.

---

## Data Flow

```text
Application code
    │
    ├─ newV4() / newV7() / ...          ← top-level convenience functions (versions.zig)
    │       │
    │       └─ default_generator.*      ← Generator struct (mutex-protected)
    │               ├─ clock()          ← injectable ClockFn → i128 Unix ns
    │               ├─ rand(buf)        ← injectable RandFn → anyerror!void
    │               └─ hwaddr()         ← injectable HWAddrFn → Error![6]u8
    │                       │
    │                       └─ hwaddr.get()  ← comptime platform dispatch
    │                           ├─ linux.getHWAddr()   (SIOCGIFHWADDR)
    │                           ├─ macos.getHWAddr()   (getifaddrs AF_LINK)
    │                           └─ windows.getHWAddr() (GetAdaptersAddresses)
    │
    ├─ UUID.fromString(s)               ← parse any of 6 formats (zero-alloc)
    ├─ UUID.toString(&buf)              ← zero-alloc canonical output
    ├─ guidToUUID(guid) / uuidToGUID(u) ← Windows GUID interop (Windows only)
    └─ NullUUID.jsonMarshal/Unmarshal   ← json library integration
```

---

## Error Handling

- All fallible operations return typed errors from `Error` set
- `RandFn` returns `anyerror!void`; all callers propagate the error (maps to `Error.RandomError`)
- No panics in library code; panics only in test helpers
- `NoHWAddressFound` triggers random node ID fallback in V1/V6 generator (RFC-9562 §6.10)
- Parse errors are specific (`InvalidBraces`, `InvalidDashes`, `InvalidURNPrefix`) to enable
  callers to distinguish format issues

---

## Testing Strategy

Test vectors are anchored to **RFC-9562 Appendix B** and the **gofrs/uuid test suite** for
bit-layout correctness. All version-specific tests verify against at least one known-good
UUID string with expected version, variant, and (where applicable) timestamp extracted.

| Layer | Coverage | What's tested |
|---|---|---|
| Unit (inline per file) | Per-module | All 6 parse formats, version/variant bit extraction, timestamp math, endian conversion, hash context, nil/max sentinels, RFC Appendix B vectors |
| Generator unit | Generator | Deterministic clock + rand injection; V1/V6/V7 bit layout; V7 monotonicity within same ms tick; mono_seq random reset on new ms; V3/V5 against RFC Appendix B name hash vectors; clock_seq initialization and increment on regression |
| HW address | hwaddr | Mock `HWAddrFn` for unit; GUID interop round-trip; NoHWAddressFound → random multicast fallback |
| Integration (`tests/integration.zig`) | Cross-module | Round-trip generate→serialize→parse→re-serialize; NullUUID JSON null and non-null; all versions; concurrent generation via `std.Thread` (no duplicates, monotone V7) |
| Cross-compilation | Build only | `zig build check` for `x86_64-linux`, `aarch64-linux`, `x86_64-macos`, `aarch64-macos`, `x86_64-windows` |

---

## Build & Tooling

### Dependencies (`build.zig.zon`)

```zig
.json = .{
    .url = "git+https://gitlab.com/devnw/zig/json.git#4c2032be31443f4504427c205419fced275d4263",
    .hash = "json-0.1.0-tOue4fSoCwDuFpNLxdd4yUQyL3g9o3su9jiX5W08e3x5",
},
```

### Build Steps

| Command | Purpose |
|---|---|
| `zig build` | Compile library |
| `zig build test` | Unit tests |
| `zig build test-integration` | Integration tests |
| `zig build check` | Fast syntax/type check (IDE) |

Cross-compilation targets in `build.zig` are implemented as a loop over target triples using
`b.addTest` with an explicit `-Dtarget=` override, wired to a `check-cross` build step:

```zig
const cross_targets = [_][]const u8{
    "x86_64-linux", "aarch64-linux",
    "x86_64-macos", "aarch64-macos",
    "x86_64-windows",
};
const cross_step = b.step("check-cross", "Cross-compile check for required targets");
for (cross_targets) |triple| {
    const cross_target = b.resolveTargetQuery(
        std.Target.Query.parse(.{ .arch_os_abi = triple }) catch unreachable,
    );
    const cross_check = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = cross_target,
            .optimize = .Debug,
        }),
    });
    cross_step.dependOn(&cross_check.step);
}
```

### Makefile Targets

All existing targets retained. New additions:

| Target | Purpose |
|---|---|
| `cross-compile-required` | `zig build check-cross` |
| `cross-compile` | Alias for `cross-compile-required` |
| `fmt` | Updated to include `examples/` directory |

### Pre-Commit Hooks

Hooks aligned with geode configuration:

| Hook | Stage | Action |
|---|---|---|
| `trailing-whitespace`, `end-of-file-fixer`, `check-case-conflict`, etc. | pre-commit | Standard hygiene |
| `zig-fmt` | pre-commit | `zig fmt --check src/ tests/ examples/ build.zig` |
| `check-todos` | pre-commit | Warning-only TODO/FIXME scan |
| `commitizen` | commit-msg | Conventional commit format |
| `zig-build` | pre-push | `zig build check` |
| `zig-test` | pre-push | `zig build test` |
| `cross-compile-check` | pre-push | `make cross-compile-required` |

**Hook versions:** `pre-commit-hooks v6.0.0`, commitizen `v4.12.1`,
shellcheck `v0.11.0.1`, markdownlint `v0.47.0`, language-formatters `v2.16.0`.

### Implementation Order (Step 0)

```bash
make pre-commit-install
```

This must be the first step before any code is written or committed. All subsequent
commits and pushes are gated by pre-commit hooks passing.

---

## Key Invariants

1. `UUID.bytes` is **always** RFC network byte order (big-endian) regardless of platform
2. GUID endian conversion happens **only** at `guidToUUID`/`uuidToGUID` boundaries
3. `default_generator` is **safe for concurrent use** via internal mutex
4. `Generator` function pointers are **never nil** — defaults always set at construction
5. V7 `mono_seq` overflow causes the generator to **spin until next ms**, then reset to a random value — never wraps silently
6. `clock_seq` (V1/V6) is **randomly initialized** on first use and **incremented on clock regression**
7. `RandFn` failure propagates as `Error.RandomError` — never silently fills with zeros
8. `Timestamp` type covers **Gregorian epoch only** (V1/V6); V7 uses bare `i64` Unix ms
