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
        .hash = "...",
    },
},
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

    // Parse any supported format (canonical, braced, hash, URN)
    const parsed = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    std.debug.print("parsed: {s}\n", .{parsed.toString(&buf)});
}
```

## Requirements

- Zig 0.15.1 or later

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

See the [docs](docs/) directory for detailed documentation.

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY.md](SECURITY.md) for security policy and vulnerability reporting.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
