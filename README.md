# uuid

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.15.2+-orange.svg)](https://ziglang.org/)

A fully RFC-9562-compliant UUID library for Zig.

## Features

- **RFC-9562 Compliant**: Full V1, V3, V4, V5, V6, V7, V8 support
- **Memory Safe**: Proper allocation patterns with no leaks
- **Cross-Platform**: Linux, macOS, Windows support
- **Well Tested**: Comprehensive unit and integration tests
- **Injectable**: Clock, random, and hardware-address functions are swappable

## Installation

### Using Zig Package Manager

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .uuid = .{
        .url = "https://gitlab.com/devnw/zig/uuid/-/archive/v0.1.0/uuid-v0.1.0.tar.gz",
        // Run: zig fetch https://gitlab.com/devnw/zig/uuid/-/archive/v0.1.0/uuid-v0.1.0.tar.gz
        // and paste the printed hash here.
        .hash = "<hash printed by zig fetch>",
    },
},
```

Or use `zig fetch --save` to add it automatically:

```bash
zig fetch --save https://gitlab.com/devnw/zig/uuid/-/archive/v0.1.0/uuid-v0.1.0.tar.gz
```

Then in your `build.zig`:

```zig
const uuid = b.dependency("uuid", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("uuid", uuid.module("uuid"));
```

## Quick Start

```zig
const std = @import("std");
const uuid = @import("uuid");

pub fn main() !void {
    // Generate a V7 UUID (recommended: Unix-ms timestamp + monotonic counter)
    const v7 = try uuid.newV7();
    var buf: [36]u8 = undefined;
    std.debug.print("V7: {s}\n", .{v7.toString(&buf)});

    // Generate a V4 UUID (random)
    const v4 = try uuid.newV4();
    std.debug.print("V4: {s}\n", .{v4.toString(&buf)});

    // Zero-alloc: no buffer needed (Zig 0.15+ {f} specifier)
    std.debug.print("{f}\n", .{v7});

    // Parse any supported format (canonical, braced, hash, URN)
    const parsed = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    std.debug.print("parsed: {s}\n", .{parsed.toString(&buf)});
}
```

## API Reference

### Generation

| Function | Description |
|----------|-------------|
| `newV1() !UUID` | Time-based + random node (RFC-9562 §5.1) |
| `newV1AtTime(ts: Timestamp) !UUID` | V1 at a specific Gregorian timestamp |
| `newV3(ns: UUID, name: []const u8) UUID` | MD5 name-based (deterministic) |
| `newV4() !UUID` | Cryptographically random |
| `newV5(ns: UUID, name: []const u8) UUID` | SHA-1 name-based (deterministic) |
| `newV6() !UUID` | k-sortable time + random node |
| `newV6AtTime(ts: Timestamp) !UUID` | V6 at a specific Gregorian timestamp |
| `newV7() !UUID` | Unix-ms timestamp + random (recommended) |
| `newV7AtTime(ms: i64) !UUID` | V7 at a specific Unix-ms timestamp |
| `newV8(a, b, c) UUID` | Custom 128-bit payload with V8 markers (infallible) |

### UUID type

| Method | Description |
|--------|-------------|
| `UUID.fromString(s) !UUID` | Parse canonical, braced, hash, URN (6 formats) |
| `UUID.fromBytes(b) !UUID` | Parse 16-byte raw slice |
| `UUID.fromStringOrNil(s) UUID` | Parse or return nil UUID on error |
| `UUID.fromBytesOrNil(b) UUID` | Parse bytes or return nil UUID on error |
| `uuid.toString(buf: *[36]u8) []u8` | Lowercase with dashes |
| `uuid.toStringUpper(buf: *[36]u8) []u8` | Uppercase with dashes |
| `uuid.toHex(buf: *[32]u8) []u8` | Lowercase hex, no dashes |
| `uuid.toHexUpper(buf: *[32]u8) []u8` | Uppercase hex, no dashes |
| `uuid.toURN(buf: *[45]u8) []u8` | `urn:uuid:...` format |
| `uuid.toStringAlloc(alloc) ![]u8` | Heap-allocated lowercase with dashes; caller frees |
| `uuid.toStringUpperAlloc(alloc) ![]u8` | Heap-allocated uppercase with dashes; caller frees |
| `uuid.toHexAlloc(alloc) ![]u8` | Heap-allocated lowercase hex; caller frees |
| `uuid.toHexUpperAlloc(alloc) ![]u8` | Heap-allocated uppercase hex; caller frees |
| `uuid.toURNAlloc(alloc) ![]u8` | Heap-allocated URN string; caller frees |
| `uuid.format(w)` | `{f}` specifier support — no buffer needed |
| `uuid.toBytes() [16]u8` | Raw 16-byte representation |
| `uuid.version() Version` | Extract version nibble |
| `uuid.variant() Variant` | Extract variant bits |
| `uuid.isNil() bool` | True if all bytes are zero |
| `uuid.isZero() bool` | Alias for `isNil` |
| `uuid.isMax() bool` | True if all bytes are 0xFF |
| `uuid.isValid() bool` | True if variant is RFC-9562 and version is 1–8 |
| `uuid.validate() !void` | Returns error if not valid RFC-9562 UUID |
| `uuid.eql(other) bool` | Byte-wise equality (not constant-time — see `timingSafeEql`) |
| `uuid.timingSafeEql(other) bool` | Constant-time equality for secret UUIDs (CWE-208) |
| `uuid.order(other) Order` | Lexicographic comparison |

### Timestamp extraction

| Function | Description |
|----------|-------------|
| `timestampFromV1(u) !Timestamp` | Extract Gregorian timestamp from V1 UUID |
| `timestampFromV6(u) !Timestamp` | Extract Gregorian timestamp from V6 UUID |
| `timestampFromV7(u) !Timestamp` | Extract Unix-ms timestamp from V7 UUID |
| `ts.toUnixNano() i128` | Convert Timestamp to Unix nanoseconds |
| `ts.toUnixMs() i64` | Convert Timestamp to Unix milliseconds |
| `ts.toUnixSec() i64` | Convert Timestamp to Unix seconds |
| `Timestamp.fromUnixNano(ns) !Timestamp` | Create Timestamp from Unix nanoseconds |
| `Timestamp.fromUnixMs(ms) !Timestamp` | Create Timestamp from Unix milliseconds |

### NullUUID

| Method | Description |
|--------|-------------|
| `NullUUID.from(u) NullUUID` | Wrap a UUID value (valid = true) |
| `nu.value() ?UUID` | Returns `?UUID` — null if not valid |
| `nu.format(w) !void` | Format as canonical UUID string or `"null"` via `{f}` specifier |
| `nu.jsonMarshal(alloc) !json.Value` | Marshal to JSON string or `json.Value.null` |
| `NullUUID.jsonUnmarshal(alloc, v) !NullUUID` | Unmarshal from JSON string or null value |

### Generator

| Method | Description |
|--------|-------------|
| `Generator.init() Generator` | Default generator (CSPRNG, random node) |
| `Generator.withClock(f) Generator` | Inject a custom clock function |
| `Generator.withRand(f) Generator` | Inject a custom random-bytes function (e.g. for testing) |
| `Generator.withHWAddr(f) Generator` | Opt in to real MAC address embedding |
| `gen.clearNodeCache()` | Force re-sample of node ID |
| `gen.saveState(path) !void` | Persist clock state to file (mode 0o600) |
| `gen.loadState(path) !void` | Restore clock state from file |
| `GeneratorInterface.fromGenerator(&gen)` | Obtain a type-erased generator interface |

### HashMap contexts

| Type | Description |
|------|-------------|
| `UUID.HashContext` | Wyhash with fixed seed — use for trusted UUID keys only |
| `UUID.SecureHashContext` | CSPRNG-seeded hash — use when UUID keys are untrusted |

### Namespace constants

`namespace_dns`, `namespace_url`, `namespace_oid`, `namespace_x500`

The nil and max UUIDs are available via both `uuid.nil`/`uuid.max` (top-level
re-exports) and `uuid.UUID.nil`/`uuid.UUID.max` (struct-scoped constants).
Both refer to the same values; prefer the shorter `uuid.nil`/`uuid.max` form.

### Library metadata

| Constant | Description |
|----------|-------------|
| `uuid.version` | Library version string (e.g. `"0.1.0"`) |

## Requirements

- Zig 0.15.2 or later

## Building

```bash
# Build the library
make build

# Run tests
make test

# Quick development iteration
make dev

# Full CI pipeline
make ci
```

## Documentation

API documentation is generated by `zig doc` from the source-level `///` doc
comments.  The `docs/` directory contains internal review notes (quality, security,
performance gap analyses) and is not user-facing documentation.

## Security Considerations

### UUID Version Security Properties

**V4 (Random):** Cryptographically strong — uses `std.crypto.random` (CSPRNG). Suitable for
all security-sensitive contexts where sortability is not required.

**V7 (Timestamp + Random):** Suitable for security-sensitive contexts. The 48-bit Unix ms
timestamp is public information; the 74 bits of randomness (`rand_a` + `rand_b`) come from
CSPRNG. The 12-bit monotonic counter (`rand_a`) is seeded randomly on each new millisecond
and is predictable within a single millisecond, but this does not affect collision resistance
(the 62-bit `rand_b` field remains fully random).

**V1/V6 (Gregorian Timestamp + Node):** By default, V1 and V6 use a **random multicast node
ID** (multicast bit set per RFC-9562 §6.10), protecting host identity. Calling
`Generator.withHWAddr(hwaddr.get)` opts in to embedding the real hardware (MAC) address in
every V1/V6 UUID — **MAC addresses are then visible to all UUID recipients**. Only use
`withHWAddr` when MAC embedding is intentional and recipients are trusted.

**V3 (MD5) and V5 (SHA-1):** These versions use **cryptographically broken algorithms**.

- V3 uses MD5: collisions are trivially engineered. Do **not** use V3 where collision
  resistance matters (surrogate keys, deduplication over untrusted input, auth tokens).
- V5 uses SHA-1: weakened by the SHAttered attack (2017). Safer than V3 but still not
  collision-resistant against a determined adversary.
- **Prefer V8** with a modern hash (SHA-256 / BLAKE3) for new name-based UUID deployments.
  Use V3/V5 only for backward compatibility with existing systems.

### HashMap Security: HashContext vs SecureHashContext

`UUID.HashContext` uses Wyhash with a **fixed seed of zero**. An adversary who controls
which UUIDs are inserted into a map can engineer O(n²) worst-case hash-map behaviour
(HashDoS).

- **Use `HashContext`** only when UUID keys are fully trusted (internally generated,
  compile-time constants, or values from a controlled datastore).
- **Use `SecureHashContext`** when UUID keys arrive from untrusted sources (user input,
  external APIs, network messages). `SecureHashContext.init()` samples a random seed from
  CSPRNG at construction time.

### Persistent State Security

`Generator.saveState()` creates the state file with mode `0o600` (owner read/write only),
protecting the stored clock state and cached node ID from other local users. The file is
written atomically (write-then-rename) to prevent torn state on crash or signal. Do not
store the state file in a world-readable directory.

## Performance Notes

### V7 Throughput Ceiling (PERF-13)

RFC-9562 §6.2 limits the `rand_a` field to 12 bits = **4,096 values per millisecond** per
generator. At the ceiling, the generator sleeps to the next millisecond boundary before
issuing the next UUID. Sustained throughput is therefore capped at **~4 million V7
UUIDs/sec per Generator instance**.

To exceed this limit while preserving sort order, shard across multiple generators — one
per thread or per tenant — since each generator has its own independent counter:

```zig
// One generator per OS thread; no lock contention, no per-generator ceiling.
threadlocal var tl_gen: uuid.Generator = uuid.Generator.init();

pub fn nextV7() !uuid.UUID {
    return tl_gen.newV7();
}
```

Each per-thread generator maintains its own counter; all generators share the same
millisecond timestamp field, so UUIDs remain monotonically sortable across threads. For
rates exceeding 4 M/sec with strict per-generator monotonicity, use `newV7AtTime` with V8
for the extra sub-millisecond bits.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY.md](SECURITY.md) for security policy and vulnerability reporting.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
