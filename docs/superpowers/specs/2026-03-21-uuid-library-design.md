# UUID Library Design

**Date:** 2026-03-21
**Status:** Approved
**Reference:** [gofrs/uuid](https://github.com/gofrs/uuid) (RFC-9562 / RFC-4122)

---

## Overview

A fully RFC-9562-compliant UUID library for Zig 0.15.1+, implementing all standard UUID versions (V1, V3, V4, V5, V6, V7, V8) with cross-platform support, an injectable generator for testability and timestamp injection, JSON serialization via `gitlab.com/devnw/zig/json`, and a complete test suite.

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

```
src/
  root.zig          # Public API — re-exports all public symbols
  uuid.zig          # UUID type, parse/format, Version/Variant enums, Error
  versions.zig      # Top-level newV1()…newV8() delegating to default_generator
  generator.zig     # Generator struct with injectable clock/rand/hwaddr + V7 monotonicity
  timestamp.zig     # Timestamp type + timestampFromV1/V6/V7 extraction
  namespace.zig     # Nil, Max, NamespaceDNS/URL/OID/X500 constants
  null_uuid.zig     # NullUUID with jsonMarshal/jsonUnmarshal
  hwaddr/
    hwaddr.zig      # Comptime platform dispatch
    linux.zig       # SIOCGIFCONF / SIOCGIFHWADDR ioctls via std.posix
    macos.zig       # getifaddrs + AF_LINK sockaddr via std.posix
    windows.zig     # GetAdaptersInfo + GUID endian conversion

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

    // Low-level mutation (for generator use)
    pub fn setVersion(self: *UUID, v: Version) void { ... }
    pub fn setVariant(self: *UUID, v: Variant) void { ... }

    // Parsing — accepts all six formats (see Parse Formats below)
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

    // Windows GUID interop (handles Data1/Data2/Data3 little-endian)
    pub fn fromWindowsGUID(guid_bytes: [16]u8) UUID { ... }
    pub fn toWindowsGUID(self: UUID) [16]u8 { ... }

    // json library custom marshaler
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
};
```

---

### 2. Timestamp Type (`src/timestamp.zig`)

Gregorian-epoch 100-ns counter for V1/V6; Unix milliseconds for V7.

```zig
/// Count of 100-ns intervals since 1582-10-15 (Gregorian epoch)
pub const Timestamp = struct {
    value: u60,

    pub fn toUnixNano(self: Timestamp) i128 { ... }
    pub fn fromUnixNano(ns: i128) Timestamp { ... }
    pub fn now() Timestamp { ... }
};

pub fn timestampFromV1(u: UUID) Error!Timestamp { ... }
pub fn timestampFromV6(u: UUID) Error!Timestamp { ... }
pub fn timestampFromV7(u: UUID) Error!i64 { ... }  // returns Unix ms
```

Interop uses `i128` nanoseconds (`std.time.nanoTimestamp()`), the natural Zig time unit.

---

### 3. Generator (`src/generator.zig`)

Runtime-swappable function pointers for clock, randomness, and hardware address.
Thread-safe via `std.Thread.Mutex` for V7 monotonicity state.

```zig
pub const ClockFn  = *const fn () i128;
pub const RandFn   = *const fn (buf: []u8) void;
pub const HWAddrFn = *const fn () Error![6]u8;

pub const Generator = struct {
    clock:     ClockFn  = defaultClock,
    rand:      RandFn   = defaultRand,
    hwaddr:    HWAddrFn = hwaddr.get,

    // V7 monotonicity state (RFC-9562 §6.2 Method 1)
    mutex:     std.Thread.Mutex = .{},
    last_ms:   i64 = 0,
    mono_seq:  u12 = 0,

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
    pub fn newV7AtTime(self: *Generator, ts: i64) Error!UUID { ... }
    pub fn newV8(self: *Generator, a: [6]u8, b: [2]u8, c: [8]u8) Error!UUID { ... }
};

/// Thread-safe package-level default
pub var default_generator: Generator = Generator.init();
```

**V7 monotonicity:** Within the same millisecond, `mono_seq` is incremented under mutex.
On overflow, the generator spins until the next millisecond tick — matching RFC-9562 §6.2 Method 1.

**Timestamp injection use case:** Pass a historical timestamp via `newV1AtTime` / `newV6AtTime` / `newV7AtTime` when generating UUIDs for records whose creation time differs from collection time.

---

### 4. Platform HW Address (`src/hwaddr/`)

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
| `windows.zig` | `GetAdaptersInfo` + GUID endian conversion |

**Windows endianness:** Windows `GUID` stores `Data1` (u32), `Data2` (u16), `Data3` (u16) in
little-endian. RFC UUIDs are fully big-endian. Conversion happens at the OS boundary only;
`UUID.bytes` is always network byte order internally.

```zig
pub fn guidToUUID(guid: GUID) UUID {
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4],  guid.Data1, .big);
    std.mem.writeInt(u16, bytes[4..6],  guid.Data2, .big);
    std.mem.writeInt(u16, bytes[6..8],  guid.Data3, .big);
    @memcpy(bytes[8..16], &guid.Data4);
    return UUID{ .bytes = bytes };
}
```

All three platform files skip loopback interfaces and prefer the first non-zero MAC found.

---

### 5. Namespace Constants (`src/namespace.zig`)

Comptime constants — no allocation, no initialization.

```zig
pub const namespace_dns  = UUID{ .bytes = .{0x6b,0xa7,0xb8,0x10,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8} };
pub const namespace_url  = UUID{ .bytes = .{0x6b,0xa7,0xb8,0x11,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8} };
pub const namespace_oid  = UUID{ .bytes = .{0x6b,0xa7,0xb8,0x12,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8} };
pub const namespace_x500 = UUID{ .bytes = .{0x6b,0xa7,0xb8,0x14,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8} };
```

---

### 6. NullUUID (`src/null_uuid.zig`)

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

    /// Accepts null JSON or a quoted canonical UUID string
    pub fn jsonUnmarshal(allocator: Allocator, v: json.Value) !NullUUID {
        _ = allocator;
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

```
Application code
    │
    ├─ newV4() / newV7() / ...          ← top-level convenience functions
    │       │
    │       └─ default_generator.*      ← Generator struct (mutex-protected)
    │               ├─ clock()          ← injectable ClockFn
    │               ├─ rand(buf)        ← injectable RandFn
    │               └─ hwaddr()         ← injectable HWAddrFn
    │                       │
    │                       └─ hwaddr.get()  ← comptime platform dispatch
    │                           ├─ linux.getHWAddr()
    │                           ├─ macos.getHWAddr()
    │                           └─ windows.getHWAddr()  ← GUID endian conversion
    │
    ├─ UUID.fromString(s)               ← parse any of 6 formats
    ├─ UUID.toString(&buf)              ← zero-alloc output
    └─ NullUUID.jsonMarshal/Unmarshal   ← json library integration
```

---

## Error Handling

- All fallible operations return typed errors from `Error` set
- No panics in library code; panics only in test helpers
- Platform HW address failure returns `Error.NoHWAddressFound` — callers can substitute a random node ID per RFC-9562 §6.10
- Parse errors are specific (`InvalidBraces`, `InvalidDashes`, `InvalidURNPrefix`) to enable callers to distinguish format issues

---

## Testing Strategy

| Layer | Coverage | What's tested |
|---|---|---|
| Unit (inline per file) | Per-module | Parse all 6 formats, version/variant bit layout, timestamp math, endian conversion, hash context, nil/max sentinels |
| Generator unit | Generator | Deterministic clock + rand injection, V1/V6/V7 bit layout, V7 monotonicity within same ms tick, V3/V5 namespace hashing against known vectors |
| HW address | hwaddr | Mock `HWAddrFn` for unit tests; real NIC tested via integration |
| Integration (`tests/integration.zig`) | Cross-module | Round-trip generate→serialize→parse→re-serialize; NullUUID JSON null and non-null; all versions; concurrent generation via `std.Thread` |
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

### Makefile Targets

All existing targets retained. New additions:

| Target | Purpose |
|---|---|
| `cross-compile-required` | `zig build check` for 5 required targets |
| `cross-compile` | Alias for `cross-compile-required` |
| `fmt` | Updated to include `examples/` directory |

### Pre-Commit Hooks

Hooks aligned with geode configuration:

| Hook | Stage | Action |
|---|---|---|
| `trailing-whitespace`, `end-of-file-fixer`, etc. | pre-commit | Standard hygiene |
| `zig-fmt` | pre-commit | `zig fmt --check src/ tests/ examples/ build.zig` |
| `check-todos` | pre-commit | Warning-only TODO/FIXME scan |
| `commitizen` | commit-msg | Conventional commit format |
| `zig-build` | pre-push | `zig build check` |
| `zig-test` | pre-push | `zig build test` |
| `cross-compile-check` | pre-push | `make cross-compile-required` |

**Hook versions:** `pre-commit-hooks v6.0.0`, commitizen `v4.12.1`,
shellcheck `v0.11.0.1`, markdownlint `v0.47.0`, language-formatters `v2.16.0`.

### Implementation Order (Step 0)

```
make pre-commit-install
```

This must be the first step before any code is written or committed. All subsequent
commits and pushes are gated by pre-commit hooks passing.

---

## Key Invariants

1. `UUID.bytes` is **always** RFC network byte order (big-endian) regardless of platform
2. Platform-specific endian conversion happens **only** at the OS boundary (`windows.zig`)
3. `default_generator` is **safe for concurrent use** via internal mutex
4. `Generator` function pointers are **never nil** — defaults always set at construction
5. V7 `mono_seq` overflow causes the generator to **spin until next ms tick**, never wraps
