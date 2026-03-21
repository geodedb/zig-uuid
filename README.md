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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY.md](SECURITY.md) for security policy and vulnerability reporting.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
