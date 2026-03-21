# UUID Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully RFC-9562-compliant Zig UUID library with V1/V3/V4/V5/V6/V7/V8 support, injectable generator, cross-platform MAC resolution, and JSON serialization.

**Architecture:** Feature-based modules — each concern in its own focused file (`< 800` lines), all re-exported from `src/root.zig`. Generator holds injectable function pointers (clock/rand/`hwaddr_fn`) and mutex-protected V7 monotonicity + V1/V6 clock_seq state. Platform MAC resolution uses comptime OS dispatch.

> **Naming note:** The spec names the hwaddr function-pointer field `hwaddr`, but the plan uses `hwaddr_fn` to avoid shadowing the `hwaddr` module import inside `generator.zig`. This is intentional and correct — the spec field name was ambiguous. Use `hwaddr_fn` throughout the implementation.

**Tech Stack:** Zig 0.15.1+, `gitlab.com/devnw/zig/json` for JSON marshaling, `std.crypto.hash.Md5`/`Sha1` for V3/V5, `std.Thread.Mutex` for thread safety, `std.posix` / `std.os.windows` for platform MAC.

---

## Spec Reference

`docs/superpowers/specs/2026-03-21-uuid-library-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `build.zig` | Modify | Add json dep module, cross-compile `check-cross` step |
| `build.zig.zon` | Modify | Add json dependency |
| `.pre-commit-config.yaml` | Modify | Align with geode (v6.0.0 hooks, move zig-build to pre-push, add cross-compile-check) |
| `Makefile` | Modify | Add `cross-compile-required`, `cross-compile` targets; update `fmt` |
| `src/root.zig` | Rewrite | Public API surface — re-export all public symbols |
| `src/uuid.zig` | Create | UUID type, Error set, Version/Variant enums, parse/format/inspect |
| `src/namespace.zig` | Create | `nil`, `max`, `namespace_dns/url/oid/x500` comptime constants |
| `src/timestamp.zig` | Create | `Timestamp` (Gregorian epoch), `timestampFromV1/V6/V7` |
| `src/generator.zig` | Create | `Generator` struct — all version generators, monotonicity, clock_seq |
| `src/versions.zig` | Create | Package-level `newV1()…newV8()` delegating to `default_generator` |
| `src/null_uuid.zig` | Create | `NullUUID` with `jsonMarshal`/`jsonUnmarshal` |
| `src/hwaddr/hwaddr.zig` | Create | Comptime OS dispatch + GUID interop helpers |
| `src/hwaddr/linux.zig` | Create | `SIOCGIFCONF`/`SIOCGIFHWADDR` via `std.posix` |
| `src/hwaddr/macos.zig` | Create | `getifaddrs` + `AF_LINK` via `std.posix` |
| `src/hwaddr/windows.zig` | Create | `GetAdaptersAddresses` + GUID endian conversion |
| `tests/integration.zig` | Rewrite | Cross-module round-trip, NullUUID JSON, concurrent generation |
| `examples/basic.zig` | Modify | Show all UUID versions in use |

---

## Task 0: Pre-commit Install & Tooling Setup

**Files:**

- Modify: `build.zig`
- Modify: `build.zig.zon`
- Modify: `.pre-commit-config.yaml`
- Modify: `Makefile`

> **Do this before writing any code or making any commits.**
> All subsequent commits and pushes are gated by these hooks passing.

- [ ] **Step 1: Install pre-commit hooks**

```bash
cd /home/benji/src/gl/devnw/zig/uuid
make pre-commit-install
```

Expected: output shows hooks installed for pre-commit, commit-msg, and pre-push stages.

- [ ] **Step 2: Update `.pre-commit-config.yaml`** — align with geode

Replace the file entirely:

```yaml
---
# Pre-commit configuration
# https://pre-commit.com/

default_stages: [pre-commit]
fail_fast: false

repos:
  # Standard pre-commit hooks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
        args: [--markdown-linebreak-ext=md]
        exclude: ^(zig-out/|\.zig-cache/)
      - id: end-of-file-fixer
        exclude: ^(zig-out/|\.zig-cache/)
      - id: mixed-line-ending
        args: [--fix=lf]
      - id: check-yaml
        args: [--unsafe]
      - id: check-json
      - id: check-toml
      - id: check-xml
      - id: check-added-large-files
        args: [--maxkb=1024]
      - id: check-merge-conflict
      - id: check-case-conflict
      - id: check-symlinks
      - id: destroyed-symlinks
      - id: check-executables-have-shebangs
      - id: check-shebang-scripts-are-executable
      - id: detect-private-key

  # Shell linting
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.11.0.1
    hooks:
      - id: shellcheck
        args: [--severity=error, --shell=bash]

  # Markdown linting
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.47.0
    hooks:
      - id: markdownlint
        args: [--fix, --disable, MD013, MD033, MD041, MD024, MD060, MD036, MD051, MD052, MD055, --]
        exclude: ^CHANGELOG\.md$

  # YAML formatting
  - repo: https://github.com/macisamuele/language-formatters-pre-commit-hooks
    rev: v2.16.0
    hooks:
      - id: pretty-format-yaml
        args: [--autofix, --indent, "2"]
        exclude: ^\.gitlab-ci\.yml$

  # Conventional commits
  - repo: https://github.com/commitizen-tools/commitizen
    rev: v4.12.1
    hooks:
      - id: commitizen
        stages: [commit-msg]

  # Local Zig hooks
  - repo: local
    hooks:
      - id: zig-fmt
        name: zig fmt (check)
        entry: zig fmt --check
        language: system
        files: \.zig$
        pass_filenames: false
        args: [src/, tests/, examples/, build.zig]
        exclude: ^(zig-out/|\.zig-cache/)

      - id: check-todos
        name: check TODOs
        entry: bash
        args:
          - -c
          - |
            git diff --cached --name-only | xargs grep -l -E "(TODO|FIXME|XXX|HACK)" 2>/dev/null \
              && echo "Warning: Found TODO/FIXME markers in staged files" && exit 0 || exit 0
        language: system
        pass_filenames: false
        verbose: true

      - id: zig-build
        name: zig build (check)
        entry: zig build check
        language: system
        pass_filenames: false
        files: \.(zig|zon)$
        exclude: ^(zig-out/|\.zig-cache/)
        stages: [pre-push]

      - id: zig-test
        name: zig test
        entry: zig build test
        language: system
        pass_filenames: false
        files: \.(zig|zon)$
        exclude: ^(zig-out/|\.zig-cache/)
        stages: [pre-push]

      - id: cross-compile-check
        name: cross-compile (required targets)
        entry: bash
        args:
          - -c
          - make cross-compile-required 2>&1 | tail -20
        language: system
        files: \.(zig|zon)$
        exclude: ^(zig-out/|\.zig-cache/)
        pass_filenames: false
        stages: [pre-push]

ci:
  autofix_prs: true
  autofix_commit_msg: "[pre-commit.ci] auto fixes"
  autoupdate_schedule: weekly
  skip: [zig-fmt, zig-build, zig-test, cross-compile-check]
```

- [ ] **Step 3: Update `Makefile`** — add cross-compile targets, update fmt

Add after the existing `test-all-optimizations` target and update `fmt`:

```makefile
# Cross-compilation (zig build check for required targets)
CROSS_TARGETS = x86_64-linux aarch64-linux x86_64-macos aarch64-macos x86_64-windows

cross-compile-required:
 @echo "🔀 Cross-compile check for required targets..."
 @for target in $(CROSS_TARGETS); do \
  echo "  Checking $$target..."; \
  zig build check-cross -Dtarget=$$target || exit 1; \
 done
 @echo "✅ All cross-compile targets pass"

cross-compile: cross-compile-required
```

Also update the existing `fmt` target to include `examples/`:

```makefile
fmt:
 @echo "📝 Formatting code..."
 @zig fmt src/ tests/ examples/ build.zig
```

Update `.PHONY` to include new targets:

```makefile
.PHONY: ... cross-compile-required cross-compile
```

Update `help` target to document the new targets.

- [ ] **Step 4: Add json dependency to `build.zig.zon`**

Add inside `.dependencies`:

```zig
.json = .{
    .url = "git+https://gitlab.com/devnw/zig/json.git#4c2032be31443f4504427c205419fced275d4263",
    .hash = "json-0.1.0-tOue4fSoCwDuFpNLxdd4yUQyL3g9o3su9jiX5W08e3x5",
},
```

Also add `"examples"` and `"docs"` to `.paths`.

- [ ] **Step 5: Update `build.zig`** — add json module, cross-compile step

Replace `build.zig` entirely:

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const json_dep = b.dependency("json", .{ .target = target, .optimize = optimize });
    const json_module = json_dep.module("json");

    // Main library module
    const module = b.addModule("uuid", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "json", .module = json_module },
        },
    });

    // Unit tests
    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "json", .module = json_module },
            },
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests
    const integration_step = b.step("test-integration", "Run integration tests");
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uuid", .module = module },
                .{ .name = "json", .module = json_module },
            },
        }),
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    integration_step.dependOn(&run_integration_tests.step);

    // Check step (fast syntax validation)
    const check_step = b.step("check", "Check for compilation errors");
    const check = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "json", .module = json_module },
            },
        }),
    });
    check_step.dependOn(&check.step);

    // Cross-compile check step — one check artifact per target triple.
    // The Makefile calls `zig build check-cross -Dtarget=<triple>` per target,
    // which works because standardTargetOptions picks up -Dtarget from the CLI.
    // Per-target artifacts are wired here matching the spec's build.zig design.
    const cross_step = b.step("check-cross", "Cross-compile check for the active -Dtarget");
    const cross_targets = [_][]const u8{
        "x86_64-linux",
        "aarch64-linux",
        "x86_64-macos",
        "aarch64-macos",
        "x86_64-windows",
    };
    for (cross_targets) |triple| {
        const cross_target = b.resolveTargetQuery(
            std.Target.Query.parse(.{ .arch_os_abi = triple }) catch unreachable,
        );
        const cross_check = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = cross_target,
                .optimize = .Debug,
                .imports = &.{
                    .{ .name = "json", .module = json_module },
                },
            }),
        });
        cross_step.dependOn(&cross_check.step);
    }
}
```

- [ ] **Step 6: Verify tooling compiles**

```bash
zig build check
```

Expected: compiles with no errors (root.zig is still a stub).

- [ ] **Step 7: Commit tooling changes**

```bash
zig fmt build.zig
git add build.zig build.zig.zon .pre-commit-config.yaml Makefile
git commit -m "chore: update build tooling — add json dep, cross-compile step, align pre-commit with geode"
```

---

## Task 1: Error Set, Version & Variant Enums

**Files:**

- Create: `src/uuid.zig`

These are the foundational types everything else depends on. Start here.

- [ ] **Step 1: Write the failing test** in `src/uuid.zig`

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

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
    RandomError,
};

pub const Version = enum(u8) {
    v1 = 1,
    v3 = 3,
    v4 = 4,
    v5 = 5,
    v6 = 6,
    v7 = 7,
    v8 = 8,
};

pub const Variant = enum(u8) {
    ncs,
    rfc9562,
    microsoft,
    future,
};

test "Version enum values" {
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Version.v1));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(Version.v7));
}

test "Variant enum" {
    const v = Variant.rfc9562;
    try std.testing.expect(v == .rfc9562);
}
```

- [ ] **Step 2: Run test to confirm it passes** (enums are pure declarations)

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: both tests PASS.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/uuid.zig
git add src/uuid.zig
git commit -m "feat: add UUID Error set and Version/Variant enums"
```

---

## Task 2: UUID Core Type — Sentinels, Inspection, Mutation

**Files:**

- Modify: `src/uuid.zig`

- [ ] **Step 1: Write failing tests** — add after the enum tests

```zig
pub const UUID = struct {
    bytes: [16]u8,

    pub const nil: UUID = .{ .bytes = [_]u8{0x00} ** 16 };
    pub const max: UUID = .{ .bytes = [_]u8{0xFF} ** 16 };

    pub fn version(self: UUID) Version {
        return @enumFromInt(self.bytes[6] >> 4);
    }

    pub fn variant(self: UUID) Variant {
        const b = self.bytes[8];
        if (b & 0x80 == 0x00) return .ncs;
        if (b & 0xC0 == 0x80) return .rfc9562;
        if (b & 0xE0 == 0xC0) return .microsoft;
        return .future;
    }

    pub fn isNil(self: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &nil.bytes);
    }

    pub fn setVersion(self: *UUID, v: Version) void {
        self.bytes[6] = (self.bytes[6] & 0x0F) | (@as(u8, @intFromEnum(v)) << 4);
    }

    pub fn setVariant(self: *UUID, v: Variant) void {
        switch (v) {
            .rfc9562   => self.bytes[8] = (self.bytes[8] & 0x3F) | 0x80,
            .ncs       => self.bytes[8] = self.bytes[8] & 0x7F,
            .microsoft => self.bytes[8] = (self.bytes[8] & 0x1F) | 0xC0,
            .future    => self.bytes[8] = (self.bytes[8] & 0x0F) | 0xE0,
        }
    }

    pub fn eql(self: UUID, other: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn order(self: UUID, other: UUID) std.math.Order {
        return std.mem.order(u8, &self.bytes, &other.bytes);
    }

    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: UUID) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(&key.bytes);
            return hasher.final();
        }
        pub fn eql(_: HashContext, a: UUID, b: UUID) bool {
            return a.eql(b);
        }
    };
};

test "UUID nil sentinel" {
    const u = UUID.nil;
    try std.testing.expect(u.isNil());
    try std.testing.expect(!UUID.max.isNil());
}

test "UUID setVersion and version()" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVersion(.v4);
    try std.testing.expectEqual(Version.v4, u.version());
    u.setVersion(.v7);
    try std.testing.expectEqual(Version.v7, u.version());
}

test "UUID setVariant and variant()" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVariant(.rfc9562);
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "UUID eql and order" {
    const a = UUID.nil;
    const b = UUID.max;
    try std.testing.expect(a.eql(UUID.nil));
    try std.testing.expect(!a.eql(b));
    try std.testing.expectEqual(std.math.Order.lt, a.order(b));
}

test "UUID HashContext" {
    const ctx = UUID.HashContext{};
    const h1 = ctx.hash(UUID.nil);
    const h2 = ctx.hash(UUID.nil);
    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(ctx.hash(UUID.max) != ctx.hash(UUID.nil));
}
```

- [ ] **Step 2: Run tests**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: all 5 new tests PASS.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/uuid.zig
git add src/uuid.zig
git commit -m "feat: add UUID core type with sentinels, inspection, and mutation"
```

---

## Task 3: UUID Parsing — All Six Formats

**Files:**

- Modify: `src/uuid.zig`

The spec requires: canonical, braced canonical, hash (no dashes), braced hash, URN canonical, URN hash.

- [ ] **Step 1: Write the failing tests first**

Add these tests to `src/uuid.zig` (they will fail until `fromString`/`fromBytes` are implemented):

```zig
test "fromString: canonical format" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xc8), u.bytes[15]);
}

test "fromString: braced canonical" {
    const u = try UUID.fromString("{6ba7b810-9dad-11d1-80b4-00c04fd430c8}");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: hash (no dashes)" {
    const u = try UUID.fromString("6ba7b8109dad11d180b400c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: braced hash" {
    const u = try UUID.fromString("{6ba7b8109dad11d180b400c04fd430c8}");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: URN canonical" {
    const u = try UUID.fromString("urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: URN hash" {
    const u = try UUID.fromString("urn:uuid:6ba7b8109dad11d180b400c04fd430c8");
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
}

test "fromString: nil UUID" {
    const u = try UUID.fromString("00000000-0000-0000-0000-000000000000");
    try std.testing.expect(u.isNil());
}

test "fromString: error on bad format" {
    try std.testing.expectError(Error.InvalidDashes,
        UUID.fromString("6ba7b8109dad-11d1-80b4-00c04fd430c8"));
    try std.testing.expectError(Error.InvalidLength,
        UUID.fromString("6ba7b810-9dad-11d1-80b4"));
    try std.testing.expectError(Error.InvalidURNPrefix,
        UUID.fromString("urn:bad:6ba7b8109dad11d180b400c04fd430c8"));
}

test "fromBytes: 16-byte slice" {
    const b = [_]u8{0x6b,0xa7,0xb8,0x10,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8};
    const u = try UUID.fromBytes(&b);
    try std.testing.expectEqual(@as(u8, 0x6b), u.bytes[0]);
    try std.testing.expectError(Error.IncorrectByteLength, UUID.fromBytes(b[0..8]));
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
zig build test --summary all 2>&1 | grep -E "FAIL|error"
```

Expected: compilation error — `fromString` and `fromBytes` undefined.

- [ ] **Step 3: Implement `fromString` and `fromBytes`**

Add to the `UUID` struct body:

```zig
pub fn fromBytes(b: []const u8) Error!UUID {
    if (b.len != 16) return Error.IncorrectByteLength;
    var u: UUID = undefined;
    @memcpy(&u.bytes, b);
    return u;
}

pub fn fromString(s: []const u8) Error!UUID {
    // Detect and strip URN prefix
    var rest = s;
    if (std.mem.startsWith(u8, rest, "urn:uuid:")) {
        rest = rest[9..];
    } else if (rest.len > 4 and std.mem.startsWith(u8, rest, "urn:")) {
        return Error.InvalidURNPrefix;
    }

    // Detect and strip braces
    var braced = false;
    if (rest.len > 0 and rest[0] == '{') {
        if (rest[rest.len - 1] != '}') return Error.InvalidBraces;
        rest = rest[1 .. rest.len - 1];
        braced = true;
    }
    _ = braced;

    return switch (rest.len) {
        36 => parseCanonical(rest),  // with dashes
        32 => parseHash(rest),       // no dashes
        else => Error.InvalidLength,
    };
}

fn parseCanonical(s: []const u8) Error!UUID {
    // Validate dash positions: 8-4-4-4-12
    if (s[8] != '-' or s[13] != '-' or s[18] != '-' or s[23] != '-')
        return Error.InvalidDashes;
    var u: UUID = undefined;
    var out: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '-') continue;
        const hi = std.fmt.charToDigit(s[i], 16) catch return Error.InvalidFormat;
        i += 1;
        const lo = std.fmt.charToDigit(s[i], 16) catch return Error.InvalidFormat;
        u.bytes[out] = (hi << 4) | lo;
        out += 1;
    }
    if (out != 16) return Error.InvalidFormat;
    return u;
}

fn parseHash(s: []const u8) Error!UUID {
    var u: UUID = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const hi = std.fmt.charToDigit(s[i * 2], 16) catch return Error.InvalidFormat;
        const lo = std.fmt.charToDigit(s[i * 2 + 1], 16) catch return Error.InvalidFormat;
        u.bytes[i] = (hi << 4) | lo;
    }
    return u;
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: all parsing tests PASS.

- [ ] **Step 5: Format and commit**

```bash
zig fmt src/uuid.zig
git add src/uuid.zig
git commit -m "feat: implement UUID parsing for all six RFC formats"
```

---

## Task 4: UUID Output — toString, toStringAlloc, format

**Files:**

- Modify: `src/uuid.zig`

- [ ] **Step 1: Write failing tests**

```zig
test "toString: canonical format" {
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", s);
}

test "toString round-trip" {
    const input = "6ba7b810-9dad-11d1-80b4-00c04fd430c8";
    const u = try UUID.fromString(input);
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(input, u.toString(&buf));
}

test "toStringAlloc" {
    const alloc = std.testing.allocator;
    const u = UUID.nil;
    const s = try u.toStringAlloc(alloc);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", s);
}

test "format via std.fmt" {
    const u = UUID.nil;
    const s = try std.fmt.allocPrint(std.testing.allocator, "{}", .{u});
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", s);
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
zig build test --summary all 2>&1 | grep -E "FAIL|error"
```

- [ ] **Step 3: Implement `toString`, `toStringAlloc`, `format`**

Add to the `UUID` struct body:

```zig
pub fn toString(self: UUID, buf: *[36]u8) []u8 {
    const hex = "0123456789abcdef";
    const groups = [_]struct { start: usize, len: usize }{
        .{ .start = 0,  .len = 4  },
        .{ .start = 4,  .len = 2  },
        .{ .start = 6,  .len = 2  },
        .{ .start = 8,  .len = 2  },
        .{ .start = 10, .len = 6  },
    };
    var pos: usize = 0;
    for (groups, 0..) |g, gi| {
        if (gi > 0) {
            buf[pos] = '-';
            pos += 1;
        }
        for (self.bytes[g.start .. g.start + g.len]) |byte| {
            buf[pos]     = hex[byte >> 4];
            buf[pos + 1] = hex[byte & 0x0F];
            pos += 2;
        }
    }
    return buf[0..36];
}

pub fn toStringAlloc(self: UUID, alloc: std.mem.Allocator) ![]u8 {
    var buf: [36]u8 = undefined;
    return alloc.dupe(u8, self.toString(&buf));
}

pub fn format(
    self: UUID,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    var buf: [36]u8 = undefined;
    try writer.writeAll(self.toString(&buf));
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

- [ ] **Step 5: Format and commit**

```bash
zig fmt src/uuid.zig
git add src/uuid.zig
git commit -m "feat: implement UUID toString, toStringAlloc, and fmt.format"
```

---

## Task 5: Namespace Constants

**Files:**

- Create: `src/namespace.zig`

- [ ] **Step 1: Create `src/namespace.zig` with tests**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;

/// All-zero UUID (RFC-9562 nil UUID)
pub const nil = UUID{ .bytes = [_]u8{0x00} ** 16 };

/// All-ones UUID (RFC-9562 max UUID)
pub const max = UUID{ .bytes = [_]u8{0xFF} ** 16 };

/// DNS namespace UUID: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
pub const namespace_dns = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// URL namespace UUID: 6ba7b811-9dad-11d1-80b4-00c04fd430c8
pub const namespace_url = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// OID namespace UUID: 6ba7b812-9dad-11d1-80b4-00c04fd430c8
pub const namespace_oid = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x12, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

/// X.500 namespace UUID: 6ba7b814-9dad-11d1-80b4-00c04fd430c8
pub const namespace_x500 = UUID{ .bytes = .{
    0x6b, 0xa7, 0xb8, 0x14, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
} };

test "namespace_dns canonical string" {
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        namespace_dns.toString(&buf),
    );
}

test "namespace constants are distinct" {
    try std.testing.expect(!namespace_dns.eql(namespace_url));
    try std.testing.expect(!namespace_dns.eql(namespace_oid));
    try std.testing.expect(!namespace_dns.eql(namespace_x500));
}

test "nil and max are correct" {
    try std.testing.expect(nil.isNil());
    for (max.bytes) |b| try std.testing.expectEqual(@as(u8, 0xFF), b);
}
```

- [ ] **Step 2: Run tests**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: all namespace tests PASS.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/namespace.zig
git add src/namespace.zig
git commit -m "feat: add namespace constants (nil, max, DNS, URL, OID, X500)"
```

---

## Task 6: Timestamp Type

**Files:**

- Create: `src/timestamp.zig`

The Gregorian epoch (1582-10-15) is 122,192,928,000,000,000 100-ns intervals before Unix epoch.
`Timestamp` covers V1/V6 only. V7 uses bare `i64` Unix ms.

- [ ] **Step 1: Write failing tests**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const Error = @import("uuid.zig").Error;

/// 100-nanosecond intervals since 1582-10-15 (Gregorian epoch).
/// Used exclusively by V1 and V6. V7 uses bare i64 Unix milliseconds.
pub const Timestamp = struct {
    value: u60,

    /// Offset between Gregorian epoch (1582-10-15) and Unix epoch (1970-01-01)
    /// in 100-ns intervals.
    pub const gregorian_offset: u64 = 122_192_928_000_000_000;

    /// Current time as a Gregorian Timestamp.
    pub fn now() Timestamp {
        const ns: i128 = std.time.nanoTimestamp();
        const intervals_since_unix: u64 = @intCast(@divTrunc(ns, 100));
        return .{ .value = @truncate(intervals_since_unix + gregorian_offset) };
    }

    /// Convert to Unix nanoseconds for interop with std.time.
    pub fn toUnixNano(self: Timestamp) i128 {
        const intervals: i128 = @as(i128, self.value) - gregorian_offset;
        return intervals * 100;
    }

    /// Create from Unix nanoseconds.
    pub fn fromUnixNano(ns: i128) Timestamp {
        const intervals_since_unix: u64 = @intCast(@divTrunc(ns, 100));
        return .{ .value = @truncate(intervals_since_unix + gregorian_offset) };
    }
};

/// Extract Gregorian timestamp from a V1 UUID.
/// V1 layout: time_low(32)|time_mid(16)|ver(4)|time_high(12) in bytes 0-7.
pub fn timestampFromV1(u: UUID) Error!Timestamp {
    if (u.version() != .v1) return Error.InvalidVersion;
    const low:  u64 = std.mem.readInt(u32, u.bytes[0..4], .big);
    const mid:  u64 = std.mem.readInt(u16, u.bytes[4..6], .big);
    const high: u64 = std.mem.readInt(u16, u.bytes[6..8], .big) & 0x0FFF; // mask version nibble
    const ts: u60 = @truncate((high << 48) | (mid << 32) | low);
    return .{ .value = ts };
}

/// Extract Gregorian timestamp from a V6 UUID.
/// V6 layout: time_high(32)|time_mid(16)|ver(4)|time_low(12) in bytes 0-7.
pub fn timestampFromV6(u: UUID) Error!Timestamp {
    if (u.version() != .v6) return Error.InvalidVersion;
    const hi:  u64 = std.mem.readInt(u32, u.bytes[0..4], .big);
    const mid: u64 = std.mem.readInt(u16, u.bytes[4..6], .big);
    const low: u64 = std.mem.readInt(u16, u.bytes[6..8], .big) & 0x0FFF; // mask version nibble
    // Reassemble: V6 stores bits 28-59 in hi, bits 12-27 in mid, bits 0-11 in low
    const ts: u60 = @truncate((hi << 28) | (mid << 12) | low);
    return .{ .value = ts };
}

/// Extract Unix millisecond timestamp from a V7 UUID.
/// Returns i64 (not Timestamp) — V7 uses Unix epoch, not Gregorian epoch.
pub fn timestampFromV7(u: UUID) Error!i64 {
    if (u.version() != .v7) return Error.InvalidVersion;
    // unix_ts_ms is in bytes 0-5 (48 bits, big-endian)
    const hi: u64 = std.mem.readInt(u32, u.bytes[0..4], .big);
    const lo: u64 = std.mem.readInt(u16, u.bytes[4..6], .big);
    return @intCast((hi << 16) | lo);
}

test "Timestamp now() is after Unix epoch" {
    const ts = Timestamp.now();
    try std.testing.expect(ts.value > Timestamp.gregorian_offset);
}

test "Timestamp round-trip through Unix nanoseconds" {
    const ts = Timestamp.now();
    const ns = ts.toUnixNano();
    const ts2 = Timestamp.fromUnixNano(ns);
    // Allow 1 interval (100ns) of rounding error
    const diff = if (ts.value > ts2.value) ts.value - ts2.value else ts2.value - ts.value;
    try std.testing.expect(diff <= 1);
}

test "timestampFromV1: RFC Appendix B vector" {
    // RFC-9562 Appendix B V1 test vector: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
    // This is the DNS namespace UUID which happens to be a valid V1 UUID
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const ts = try timestampFromV1(u);
    // time_low=0x6ba7b810, time_mid=0x9dad, time_high=0x11d1&0x0FFF=0x1d1
    // ts = (0x1d1 << 48) | (0x9dad << 32) | 0x6ba7b810
    const expected: u60 = (@as(u60, 0x1d1) << 48) | (@as(u60, 0x9dad) << 32) | 0x6ba7b810;
    try std.testing.expectEqual(expected, ts.value);
}

test "timestampFromV6: bit reassembly is correct" {
    // Build a V6 UUID with a known 60-bit Gregorian timestamp value.
    // ts = 0x1d19dad6ba7b810 (same bit pattern as DNS namespace V1 reassembled to V6)
    // Encode it manually: hi=bits28-59, mid=bits12-27, low=bits0-11
    const ts_known: u60 = 0x1d19dad6ba7b810;
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    std.mem.writeInt(u32, u.bytes[0..4], @truncate(ts_known >> 28), .big);
    std.mem.writeInt(u16, u.bytes[4..6], @truncate((ts_known >> 12) & 0xFFFF), .big);
    std.mem.writeInt(u16, u.bytes[6..8], @truncate(ts_known & 0x0FFF), .big);
    u.setVersion(.v6);
    u.setVariant(.rfc9562);
    const ts = try timestampFromV6(u);
    try std.testing.expectEqual(ts_known, ts.value);
}

test "timestampFromV7: extracts Unix ms" {
    // Build a V7 UUID with known timestamp (1000 ms = 0x3E8)
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    const ms: u64 = 1000;
    std.mem.writeInt(u32, u.bytes[0..4], @truncate(ms >> 16), .big);
    std.mem.writeInt(u16, u.bytes[4..6], @truncate(ms), .big);
    u.setVersion(.v7);
    u.setVariant(.rfc9562);
    const extracted = try timestampFromV7(u);
    try std.testing.expectEqual(@as(i64, 1000), extracted);
}

test "timestampFromV1: error on wrong version" {
    var u = UUID{ .bytes = [_]u8{0} ** 16 };
    u.setVersion(.v4);
    try std.testing.expectError(Error.InvalidVersion, timestampFromV1(u));
}
```

- [ ] **Step 2: Run tests to confirm they pass**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: all timestamp tests PASS.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/timestamp.zig
git add src/timestamp.zig
git commit -m "feat: add Timestamp type with V1/V6/V7 extraction"
```

---

## Task 7: Hardware Address — Linux

**Files:**

- Create: `src/hwaddr/linux.zig`

Uses `SIOCGIFCONF` (get interface list) then `SIOCGIFHWADDR` per interface via `std.posix`.
Skip loopback (`IFF_LOOPBACK`) and zero-MAC interfaces.

- [ ] **Step 1: Create `src/hwaddr/linux.zig`**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const builtin = @import("builtin");
const Error = @import("../uuid.zig").Error;

const linux = std.os.linux;

const SIOCGIFCONF  = 0x8912;
const SIOCGIFHWADDR = 0x8927;
const SIOCGIFFLAGS  = 0x8913;
const IFF_LOOPBACK  = 0x8;
const ARPHRD_ETHER  = 1;

const ifreq = extern struct {
    ifr_name: [16]u8,
    // union: we read different fields depending on the ioctl
    ifr_data: [24]u8,
};

const ifconf = extern struct {
    ifc_len: c_int,
    ifc_buf: ?[*]ifreq,
};

pub fn getHWAddr() Error![6]u8 {
    const sock = std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM,
        0,
    ) catch return Error.NoHWAddressFound;
    defer std.posix.close(sock);

    // Get interface list
    var ifreqs: [64]ifreq = undefined;
    var ifc = ifconf{
        .ifc_len = @intCast(@sizeOf(ifreq) * ifreqs.len),
        .ifc_buf = &ifreqs,
    };
    const ifc_ret = linux.syscall3(
        .ioctl,
        @as(usize, @intCast(sock)),
        SIOCGIFCONF,
        @intFromPtr(&ifc),
    );
    if (ifc_ret != 0) return Error.NoHWAddressFound;

    const count: usize = @intCast(@divTrunc(ifc.ifc_len, @sizeOf(ifreq)));

    for (ifreqs[0..count]) |*ifr| {
        // Get flags to skip loopback
        var flags_req = ifr.*;
        const flags_ret = linux.syscall3(
            .ioctl,
            @as(usize, @intCast(sock)),
            SIOCGIFFLAGS,
            @intFromPtr(&flags_req),
        );
        if (flags_ret != 0) continue;
        const flags = std.mem.readInt(u16, flags_req.ifr_data[0..2], .little);
        if (flags & IFF_LOOPBACK != 0) continue;

        // Get hardware address
        var hw_req = ifr.*;
        const hw_ret = linux.syscall3(
            .ioctl,
            @as(usize, @intCast(sock)),
            SIOCGIFHWADDR,
            @intFromPtr(&hw_req),
        );
        if (hw_ret != 0) continue;

        // sa_family is first 2 bytes; MAC is bytes 2-7
        const family = std.mem.readInt(u16, hw_req.ifr_data[0..2], .little);
        if (family != ARPHRD_ETHER) continue;

        const mac = hw_req.ifr_data[2..8];
        // Skip zero MAC
        if (std.mem.allEqual(u8, mac, 0)) continue;

        var result: [6]u8 = undefined;
        @memcpy(&result, mac);
        return result;
    }
    return Error.NoHWAddressFound;
}
```

- [ ] **Step 2: Test by building for Linux target (from any platform)**

```bash
zig build check -Dtarget=x86_64-linux
```

Expected: compiles cleanly.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/hwaddr/linux.zig
git add src/hwaddr/linux.zig
git commit -m "feat: add Linux hardware address resolution via SIOCGIFHWADDR"
```

---

## Task 8: Hardware Address — macOS

**Files:**

- Create: `src/hwaddr/macos.zig`

Uses `getifaddrs()` + `AF_LINK` sockaddr to find the first non-loopback Ethernet interface.

- [ ] **Step 1: Create `src/hwaddr/macos.zig`**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const Error = @import("../uuid.zig").Error;

const c = struct {
    pub extern "c" fn getifaddrs(ifap: **ifaddrs) c_int;
    pub extern "c" fn freeifaddrs(ifp: *ifaddrs) void;

    pub const AF_LINK: u8 = 18;
    pub const IFF_LOOPBACK: u32 = 0x8;
    pub const IFF_UP: u32 = 0x1;

    pub const sockaddr = extern struct {
        sa_len: u8,
        sa_family: u8,
        sa_data: [14]u8,
    };

    pub const sockaddr_dl = extern struct {
        sdl_len: u8,
        sdl_family: u8,
        sdl_index: u16,
        sdl_type: u8,
        sdl_nlen: u8,
        sdl_alen: u8,
        sdl_slen: u8,
        sdl_data: [12]u8,
    };

    pub const ifaddrs = extern struct {
        ifa_next: ?*ifaddrs,
        ifa_name: [*:0]const u8,
        ifa_flags: u32,
        ifa_addr: ?*sockaddr,
        ifa_netmask: ?*sockaddr,
        ifa_dstaddr: ?*sockaddr,
        ifa_data: ?*anyopaque,
    };
};

pub fn getHWAddr() Error![6]u8 {
    var ifap: *c.ifaddrs = undefined;
    if (c.getifaddrs(&ifap) != 0) return Error.NoHWAddressFound;
    defer c.freeifaddrs(ifap);

    var it: ?*c.ifaddrs = ifap;
    while (it) |ifa| : (it = ifa.ifa_next) {
        // Skip loopback and down interfaces
        if (ifa.ifa_flags & c.IFF_LOOPBACK != 0) continue;
        if (ifa.ifa_flags & c.IFF_UP == 0) continue;

        const addr = ifa.ifa_addr orelse continue;
        if (addr.sa_family != c.AF_LINK) continue;

        const sdl: *c.sockaddr_dl = @ptrCast(addr);
        if (sdl.sdl_alen != 6) continue;

        // MAC follows the interface name in sdl_data
        const mac_offset: usize = sdl.sdl_nlen;
        if (mac_offset + 6 > sdl.sdl_data.len) continue;
        const mac = sdl.sdl_data[mac_offset .. mac_offset + 6];
        if (std.mem.allEqual(u8, mac, 0)) continue;

        var result: [6]u8 = undefined;
        @memcpy(&result, mac);
        return result;
    }
    return Error.NoHWAddressFound;
}
```

- [ ] **Step 2: Build check for macOS**

```bash
zig build check -Dtarget=aarch64-macos
```

Expected: compiles cleanly.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/hwaddr/macos.zig
git add src/hwaddr/macos.zig
git commit -m "feat: add macOS hardware address resolution via getifaddrs"
```

---

## Task 9: Hardware Address — Windows + GUID Interop

**Files:**

- Create: `src/hwaddr/windows.zig`

Uses `GetAdaptersAddresses` (Vista+). MAC is in `PhysicalAddress[0..PhysicalAddressLength]`
(plain byte array, no GUID). Also exposes `guidToUUID`/`uuidToGUID` for application GUID interop.

- [ ] **Step 1: Create `src/hwaddr/windows.zig`**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const Error = @import("../uuid.zig").Error;
const UUID = @import("../uuid.zig").UUID;

const windows = std.os.windows;

// IP_ADAPTER_ADDRESSES (simplified — only fields we use)
const IP_ADAPTER_ADDRESSES = extern struct {
    Length: windows.ULONG,
    IfIndex: windows.DWORD,
    Next: ?*IP_ADAPTER_ADDRESSES,
    AdapterName: [*:0]windows.CHAR,
    FirstUnicastAddress: ?*anyopaque,
    FirstAnycastAddress: ?*anyopaque,
    FirstMulticastAddress: ?*anyopaque,
    FirstDnsServerAddress: ?*anyopaque,
    DnsSuffix: [*:0]windows.WCHAR,
    Description: [*:0]windows.WCHAR,
    FriendlyName: [*:0]windows.WCHAR,
    PhysicalAddress: [8]u8,
    PhysicalAddressLength: windows.DWORD,
    Flags: windows.DWORD,
    Mtu: windows.DWORD,
    IfType: windows.DWORD,
    OperStatus: windows.DWORD,
    // ... additional fields omitted; Length field ensures safe iteration
};

const IF_TYPE_SOFTWARE_LOOPBACK: windows.DWORD = 24;
const GAA_FLAG_NONE: windows.ULONG = 0;
const AF_UNSPEC: windows.ULONG = 0;

extern "iphlpapi" fn GetAdaptersAddresses(
    Family: windows.ULONG,
    Flags: windows.ULONG,
    Reserved: ?*anyopaque,
    AdapterAddresses: ?*IP_ADAPTER_ADDRESSES,
    SizePointer: *windows.ULONG,
) callconv(windows.WINAPI) windows.DWORD;

const ERROR_BUFFER_OVERFLOW: windows.DWORD = 111;
const NO_ERROR: windows.DWORD = 0;

pub fn getHWAddr() Error![6]u8 {
    // Use a stack buffer; 16KB is sufficient for most systems
    var buf: [16384]u8 align(@alignOf(IP_ADAPTER_ADDRESSES)) = undefined;
    var buf_size: windows.ULONG = buf.len;

    const ret = GetAdaptersAddresses(
        AF_UNSPEC, GAA_FLAG_NONE, null,
        @ptrCast(&buf), &buf_size,
    );
    if (ret != NO_ERROR) return Error.NoHWAddressFound;

    var it: ?*IP_ADAPTER_ADDRESSES = @ptrCast(&buf);
    while (it) |adapter| : (it = adapter.Next) {
        // Skip loopback
        if (adapter.IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
        const mac_len = adapter.PhysicalAddressLength;
        if (mac_len != 6) continue;
        const mac = adapter.PhysicalAddress[0..6];
        if (std.mem.allEqual(u8, mac, 0)) continue;
        var result: [6]u8 = undefined;
        @memcpy(&result, mac);
        return result;
    }
    return Error.NoHWAddressFound;
}

// =============================================================================
// Application-level GUID interop helpers
//
// Windows GUID stores Data1/Data2/Data3 in little-endian; RFC UUIDs are
// fully big-endian. These helpers convert at the boundary. UUID.bytes is
// always network byte order internally.
// =============================================================================

pub const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

/// Convert a Windows GUID to an RFC UUID.
/// Handles the Data1/Data2/Data3 little-endian → big-endian conversion.
pub fn guidToUUID(guid: GUID) UUID {
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4], guid.Data1, .big); // LE → BE
    std.mem.writeInt(u16, bytes[4..6], guid.Data2, .big); // LE → BE
    std.mem.writeInt(u16, bytes[6..8], guid.Data3, .big); // LE → BE
    @memcpy(bytes[8..16], &guid.Data4);                   // already BE
    return UUID{ .bytes = bytes };
}

/// Convert an RFC UUID to a Windows GUID.
/// Handles the big-endian → Data1/Data2/Data3 little-endian conversion.
pub fn uuidToGUID(u: UUID) GUID {
    return .{
        .Data1 = std.mem.readInt(u32, u.bytes[0..4], .big), // BE → LE
        .Data2 = std.mem.readInt(u16, u.bytes[4..6], .big),
        .Data3 = std.mem.readInt(u16, u.bytes[6..8], .big),
        .Data4 = u.bytes[8..16].*,
    };
}

test "guidToUUID and uuidToGUID round-trip" {
    const guid = GUID{
        .Data1 = 0x6ba7b810,
        .Data2 = 0x9dad,
        .Data3 = 0x11d1,
        .Data4 = .{ 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8 },
    };
    const u = guidToUUID(guid);
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        u.toString(&buf),
    );
    const guid2 = uuidToGUID(u);
    try std.testing.expectEqual(guid.Data1, guid2.Data1);
    try std.testing.expectEqual(guid.Data2, guid2.Data2);
    try std.testing.expectEqual(guid.Data3, guid2.Data3);
}
```

- [ ] **Step 2: Build check for Windows**

```bash
zig build check -Dtarget=x86_64-windows
```

Expected: compiles cleanly.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/hwaddr/windows.zig
git add src/hwaddr/windows.zig
git commit -m "feat: add Windows hardware address via GetAdaptersAddresses and GUID interop helpers"
```

---

## Task 10: Hardware Address — Dispatch

**Files:**

- Create: `src/hwaddr/hwaddr.zig`

Comptime dispatch. Each platform file is `@import`ed only in its own branch so
cross-compilation works: Zig evaluates only the taken branch.

- [ ] **Step 1: Create `src/hwaddr/hwaddr.zig`**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const builtin = @import("builtin");
const Error = @import("../uuid.zig").Error;
const UUID = @import("../uuid.zig").UUID;

/// Get a hardware (MAC) address from the first suitable network interface.
/// Returns Error.NoHWAddressFound if no interface is available.
/// Cross-compiled safely: each platform branch is only evaluated for its target.
pub fn get() Error![6]u8 {
    if (builtin.os.tag == .linux) return @import("linux.zig").getHWAddr();
    if (builtin.os.tag == .macos or builtin.os.tag == .ios) return @import("macos.zig").getHWAddr();
    if (builtin.os.tag == .windows) return @import("windows.zig").getHWAddr();
    return Error.NoHWAddressFound;
}

// Re-export GUID interop helpers (Windows only — guarded at call site via comptime)
pub const guidToUUID = if (builtin.os.tag == .windows)
    @import("windows.zig").guidToUUID
else
    @compileError("guidToUUID is only available on Windows");

pub const uuidToGUID = if (builtin.os.tag == .windows)
    @import("windows.zig").uuidToGUID
else
    @compileError("uuidToGUID is only available on Windows");

test "hwaddr.get() returns 6-byte array or NoHWAddressFound" {
    const result = get();
    if (result) |mac| {
        try @import("std").testing.expectEqual(@as(usize, 6), mac.len);
    } else |err| {
        try @import("std").testing.expectEqual(Error.NoHWAddressFound, err);
    }
}
```

- [ ] **Step 2: Run cross-compile check for all targets**

```bash
make cross-compile-required
```

Expected: all 5 targets pass.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/hwaddr/hwaddr.zig
git add src/hwaddr/hwaddr.zig
git commit -m "feat: add comptime hwaddr platform dispatch"
```

---

## Task 11: Generator — Core, V4, V7

**Files:**

- Create: `src/generator.zig`

Build the `Generator` struct with injectable functions, then implement V4 (simplest: pure
random) and V7 (Unix ms + monotonicity). Get these working and tested before V1/V6.

- [ ] **Step 1: Write failing tests first**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const Version = @import("uuid.zig").Version;
const Variant = @import("uuid.zig").Variant;
const Error = @import("uuid.zig").Error;
const hwaddr = @import("hwaddr/hwaddr.zig");
const Timestamp = @import("timestamp.zig").Timestamp;

pub const ClockFn  = *const fn () i128;
pub const RandFn   = *const fn (buf: []u8) anyerror!void;
pub const HWAddrFn = *const fn () Error![6]u8;

fn defaultClock() i128 {
    return std.time.nanoTimestamp();
}

fn defaultRand(buf: []u8) anyerror!void {
    std.crypto.random.bytes(buf);
}

pub const Generator = struct {
    clock:  ClockFn  = defaultClock,
    rand:   RandFn   = defaultRand,
    hwaddr_fn: HWAddrFn = hwaddr.get,

    // V7 monotonicity state (all protected by mutex)
    mutex:    std.Thread.Mutex = .{},
    last_ms:  i64 = 0,
    mono_seq: u12 = 0,

    // V1/V6 state
    clock_seq: u14 = 0,
    clock_seq_initialized: bool = false,

    pub fn init() Generator {
        return .{};
    }

    pub fn withClock(f: ClockFn) Generator {
        var g = Generator.init();
        g.clock = f;
        return g;
    }

    pub fn withRand(f: RandFn) Generator {
        var g = Generator.init();
        g.rand = f;
        return g;
    }

    pub fn withHWAddr(f: HWAddrFn) Generator {
        var g = Generator.init();
        g.hwaddr_fn = f;
        return g;
    }

    pub fn newV4(self: *Generator) Error!UUID {
        var u: UUID = undefined;
        self.rand(&u.bytes) catch return Error.RandomError;
        u.setVersion(.v4);
        u.setVariant(.rfc9562);
        return u;
    }

    pub fn newV7(self: *Generator) Error!UUID {
        const now_ms: i64 = @intCast(@divTrunc(self.clock(), 1_000_000));
        return self.newV7AtTime(now_ms);
    }

    pub fn newV7AtTime(self: *Generator, ts: i64) Error!UUID {
        self.mutex.lock();
        defer self.mutex.unlock();

        var ms = ts;
        // seq is always set before use in every branch below — declared here for scope.
        var seq: u12 = 0;

        if (ms == self.last_ms) {
            // Same ms: increment sequence counter
            if (self.mono_seq == std.math.maxInt(u12)) {
                // Overflow: yield briefly then spin until the clock advances.
                // A brief sleep avoids burning 100% CPU on a tight spin —
                // the spec calls this a "spin-wait strategy" (brief yield is acceptable).
                while (ms == self.last_ms) {
                    self.mutex.unlock();
                    std.Thread.sleep(100_000); // 0.1ms yield — avoids busy-spin
                    self.mutex.lock();
                    ms = @intCast(@divTrunc(self.clock(), 1_000_000));
                }
                // ms has advanced — fall through to random reset below
            } else {
                self.mono_seq += 1;
                seq = self.mono_seq;
                // seq is set; skip the new-ms branch
                // (use a goto-equivalent: we return directly after building the UUID)
            }
        }

        if (ms != self.last_ms) {
            // New ms (either first call, or after spin overflow above):
            // reset mono_seq to a random 12-bit value for maximum entropy.
            var rand_seq: [2]u8 = undefined;
            self.rand(&rand_seq) catch return Error.RandomError;
            self.mono_seq = @truncate(std.mem.readInt(u16, &rand_seq, .little) & 0x0FFF);
            seq = self.mono_seq;
            self.last_ms = ms;
        }

        var u: UUID = undefined;
        // unix_ts_ms: 48 bits big-endian in bytes 0-5
        const ms_u: u64 = @intCast(ms);
        std.mem.writeInt(u32, u.bytes[0..4], @truncate(ms_u >> 16), .big);
        std.mem.writeInt(u16, u.bytes[4..6], @truncate(ms_u), .big);
        // rand_a: 12-bit monotonic counter in low 12 bits of bytes 6-7
        std.mem.writeInt(u16, u.bytes[6..8], seq, .big);
        // rand_b: 62 bits random in bytes 8-15
        self.rand(u.bytes[8..16]) catch return Error.RandomError;
        u.setVersion(.v7);
        u.setVariant(.rfc9562);
        return u;
    }
};

pub var default_generator: Generator = Generator.init();

test "Generator.newV4: version=4, variant=rfc9562" {
    var gen = Generator.init();
    const u = try gen.newV4();
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.newV4: two calls return distinct UUIDs" {
    var gen = Generator.init();
    const a = try gen.newV4();
    const b = try gen.newV4();
    try std.testing.expect(!a.eql(b));
}

test "Generator.newV7: version=7, variant=rfc9562" {
    var gen = Generator.init();
    const u = try gen.newV7();
    try std.testing.expectEqual(Version.v7, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.newV7AtTime: timestamp round-trips" {
    const ts_mod = @import("timestamp.zig");
    var gen = Generator.init();
    const ms: i64 = 1_700_000_000_000; // some Unix ms
    const u = try gen.newV7AtTime(ms);
    const extracted = try ts_mod.timestampFromV7(u);
    try std.testing.expectEqual(ms, extracted);
}

test "Generator.newV7: monotone within same ms" {
    // Use deterministic clock that always returns the same ms
    const fixed_clock = struct {
        fn clock() i128 { return 1_000 * 1_000_000; } // 1000ms in ns
    };
    var gen = Generator.withClock(fixed_clock.clock);
    const a = try gen.newV7();
    const b = try gen.newV7();
    // b should be greater than a (monotone counter)
    try std.testing.expect(a.order(b) == .lt);
}

test "Generator injectable rand" {
    // All-zero rand for determinism
    const zero_rand = struct {
        fn rand(buf: []u8) anyerror!void {
            @memset(buf, 0);
        }
    };
    var gen = Generator.withRand(zero_rand.rand);
    const u = try gen.newV4();
    // bytes should be zero except version/variant bits
    try std.testing.expectEqual(Version.v4, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}
```

- [ ] **Step 2: Run tests to confirm they pass**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: all Generator V4/V7 tests PASS.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/generator.zig
git add src/generator.zig
git commit -m "feat: add Generator with injectable clock/rand/hwaddr, V4 and V7 generation"
```

---

## Task 12: Generator — V1, V6, V3, V5, V8

**Files:**

- Modify: `src/generator.zig`

- [ ] **Step 1: Write failing tests for V1, V6, V3, V5, V8**

Add these tests to `src/generator.zig`:

```zig
test "Generator.newV1: version=1, variant=rfc9562" {
    const mock_hwaddr = struct {
        fn getHW() Error![6]u8 { return .{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55 }; }
    };
    var gen = Generator.withHWAddr(mock_hwaddr.getHW);
    const u = try gen.newV1();
    try std.testing.expectEqual(Version.v1, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
    // Node bytes (10-15) should match our mock MAC
    try std.testing.expectEqualSlices(u8, &.{0x00,0x11,0x22,0x33,0x44,0x55}, u.bytes[10..16]);
}

test "Generator.newV6: version=6, variant=rfc9562, sorts after V1 with same ts" {
    const mock_hwaddr = struct {
        fn getHW() Error![6]u8 { return .{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }; }
    };
    var gen = Generator.withHWAddr(mock_hwaddr.getHW);
    const u = try gen.newV6();
    try std.testing.expectEqual(Version.v6, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
}

test "Generator.newV6AtTime: timestamp round-trips" {
    const ts_mod = @import("timestamp.zig");
    const mock_hwaddr = struct {
        fn getHW() Error![6]u8 { return .{ 0,1,2,3,4,5 }; }
    };
    const fixed_clock = struct {
        fn clock() i128 { return 1_000_000_000 * 1_000; } // 1,000 seconds in ns
    };
    var gen = Generator{ .clock = fixed_clock.clock, .hwaddr_fn = mock_hwaddr.getHW };
    const ts = Timestamp.now();
    const u = try gen.newV6AtTime(ts);
    const extracted = try ts_mod.timestampFromV6(u);
    try std.testing.expectEqual(ts.value, extracted.value);
}

test "Generator.newV3: RFC Appendix B — DNS namespace + 'www.example.com'" {
    // RFC-9562 Appendix B V3 vector:
    // name=www.example.com, ns=DNS → 5df41881-3aed-3515-88a7-2f4a814cf09e
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV3(ns_mod.namespace_dns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        u.toString(&buf),
    );
}

test "Generator.newV5: RFC Appendix B — DNS namespace + 'www.example.com'" {
    // RFC-9562 Appendix B V5 vector:
    // name=www.example.com, ns=DNS → 2ed6657d-e927-568b-95e3-af9b26a12f30
    const ns_mod = @import("namespace.zig");
    var gen = Generator.init();
    const u = gen.newV5(ns_mod.namespace_dns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2ed6657d-e927-568b-95e3-af9b26a12f30",
        u.toString(&buf),
    );
}

test "Generator.newV1: clock_seq increments on clock regression" {
    // Supply a clock that moves backward between calls to trigger clock_seq increment
    const State = struct {
        var call: usize = 0;
        fn clock() i128 {
            call += 1;
            // First call: future time; second call: past time (regression)
            return if (call == 1) 2_000_000_000 * std.time.ns_per_s
                   else          1_000_000_000 * std.time.ns_per_s;
        }
    };
    const mock_hw = struct {
        fn getHW() Error![6]u8 { return .{0,1,2,3,4,5}; }
    };
    var gen = Generator{ .clock = State.clock, .hwaddr_fn = mock_hw.getHW };
    // Initialize clock_seq by calling newV1 once at "future" time
    const u1 = try gen.newV1();
    const seq1 = std.mem.readInt(u16, u1.bytes[8..10], .big) & 0x3FFF;
    // Reinitialize State.call so next call uses "past" time to simulate regression
    State.call = 1; // next clock() call will return past time
    // Force a clock regression by calling newV1AtTime with an earlier timestamp
    const past_ts = Timestamp{ .value = @truncate(@as(u64, 0)) };
    const u2 = try gen.newV1AtTime(past_ts);
    const seq2 = std.mem.readInt(u16, u2.bytes[8..10], .big) & 0x3FFF;
    // clock_seq must change (increment mod 2^14) on regression
    try std.testing.expect(seq1 != seq2);
}

test "Generator.newV8: version=8, variant=rfc9562" {
    var gen = Generator.init();
    const a: [6]u8 = .{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const b_data: [2]u8 = .{ 0x07, 0x08 };
    const c_data: [8]u8 = .{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const u = try gen.newV8(a, b_data, c_data);
    try std.testing.expectEqual(Version.v8, u.version());
    try std.testing.expectEqual(Variant.rfc9562, u.variant());
    // custom_a: bytes 0-5 should match a
    try std.testing.expectEqualSlices(u8, &a, u.bytes[0..6]);
}
```

- [ ] **Step 2: Run tests to confirm they fail** (functions not yet implemented)

```bash
zig build test --summary all 2>&1 | grep -E "FAIL|error"
```

- [ ] **Step 3: Implement V1, V6, V3, V5, V8 methods** on `Generator`

Add to the `Generator` struct body:

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

fn getNode(self: *Generator) Error![6]u8 {
    if (self.hwaddr_fn()) |mac| return mac else |_| {
        // Random node ID with multicast bit set (RFC-9562 §6.10)
        var node: [6]u8 = undefined;
        self.rand(&node) catch return Error.RandomError;
        node[0] |= 0x01; // set multicast bit
        return node;
    }
}

pub fn newV1(self: *Generator) Error!UUID {
    const ts = Timestamp.now();
    return self.newV1AtTime(ts);
}

pub fn newV1AtTime(self: *Generator, ts: Timestamp) Error!UUID {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.initClockSeq();
    const node = try self.getNode();
    var u: UUID = undefined;
    const t = ts.value;
    // time_low: bits 0-31
    std.mem.writeInt(u32, u.bytes[0..4], @truncate(t), .big);
    // time_mid: bits 32-47
    std.mem.writeInt(u16, u.bytes[4..6], @truncate(t >> 32), .big);
    // time_high: bits 48-59 (version nibble set below)
    std.mem.writeInt(u16, u.bytes[6..8], @truncate(t >> 48), .big);
    // clock_seq: 14 bits in bytes 8-9 (variant set below)
    std.mem.writeInt(u16, u.bytes[8..10], self.clock_seq, .big);
    @memcpy(u.bytes[10..16], &node);
    u.setVersion(.v1);
    u.setVariant(.rfc9562);
    return u;
}

pub fn newV6(self: *Generator) Error!UUID {
    const ts = Timestamp.now();
    return self.newV6AtTime(ts);
}

pub fn newV6AtTime(self: *Generator, ts: Timestamp) Error!UUID {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.initClockSeq();
    const node = try self.getNode();
    var u: UUID = undefined;
    const t = ts.value;
    // V6: reorder timestamp for lexicographic sort
    // bytes 0-3: bits 28-59 (high 32 bits)
    std.mem.writeInt(u32, u.bytes[0..4], @truncate(t >> 28), .big);
    // bytes 4-5: bits 12-27
    std.mem.writeInt(u16, u.bytes[4..6], @truncate((t >> 12) & 0xFFFF), .big);
    // bytes 6-7: bits 0-11 (version nibble set below)
    std.mem.writeInt(u16, u.bytes[6..8], @truncate(t & 0x0FFF), .big);
    // bytes 8-9: clock_seq (variant set below)
    std.mem.writeInt(u16, u.bytes[8..10], self.clock_seq, .big);
    @memcpy(u.bytes[10..16], &node);
    u.setVersion(.v6);
    u.setVariant(.rfc9562);
    return u;
}

pub fn newV3(self: *Generator, ns: UUID, name: []const u8) UUID {
    _ = self;
    var md5 = std.crypto.hash.Md5.init(.{});
    md5.update(&ns.bytes);
    md5.update(name);
    var digest: [16]u8 = undefined;
    md5.final(&digest);
    var u = UUID{ .bytes = digest };
    u.setVersion(.v3);
    u.setVariant(.rfc9562);
    return u;
}

pub fn newV5(self: *Generator, ns: UUID, name: []const u8) UUID {
    _ = self;
    var sha1 = std.crypto.hash.Sha1.init(.{});
    sha1.update(&ns.bytes);
    sha1.update(name);
    var digest: [20]u8 = undefined;
    sha1.final(&digest);
    var u = UUID{ .bytes = digest[0..16].* };
    u.setVersion(.v5);
    u.setVariant(.rfc9562);
    return u;
}

pub fn newV8(self: *Generator, a: [6]u8, b: [2]u8, c: [8]u8) Error!UUID {
    _ = self;
    var u: UUID = undefined;
    // custom_a: bits 0-47 → bytes 0-5
    @memcpy(u.bytes[0..6], &a);
    // custom_b: lower 12 bits used → bytes 6-7 (version nibble will overlay high 4 bits)
    @memcpy(u.bytes[6..8], &b);
    // custom_c: lower 62 bits used → bytes 8-15 (variant bits will overlay high 2 bits)
    @memcpy(u.bytes[8..16], &c);
    u.setVersion(.v8);
    u.setVariant(.rfc9562);
    return u;
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: all V1/V3/V5/V6/V8 tests PASS, including RFC Appendix B name-hash vectors.

- [ ] **Step 5: Format and commit**

```bash
zig fmt src/generator.zig
git add src/generator.zig
git commit -m "feat: add V1, V3, V5, V6, V8 UUID generation with clock_seq and MAC fallback"
```

---

## Task 13: Package-Level Convenience Functions

**Files:**

- Create: `src/versions.zig`

- [ ] **Step 1: Create `src/versions.zig`**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const Error = @import("uuid.zig").Error;
const Generator = @import("generator.zig").Generator;
const Timestamp = @import("timestamp.zig").Timestamp;
pub const default_generator = &@import("generator.zig").default_generator;

pub fn newV1() Error!UUID { return default_generator.newV1(); }
pub fn newV1AtTime(ts: Timestamp) Error!UUID { return default_generator.newV1AtTime(ts); }
pub fn newV3(ns: UUID, name: []const u8) UUID { return default_generator.newV3(ns, name); }
pub fn newV4() Error!UUID { return default_generator.newV4(); }
pub fn newV5(ns: UUID, name: []const u8) UUID { return default_generator.newV5(ns, name); }
pub fn newV6() Error!UUID { return default_generator.newV6(); }
pub fn newV6AtTime(ts: Timestamp) Error!UUID { return default_generator.newV6AtTime(ts); }
pub fn newV7() Error!UUID { return default_generator.newV7(); }
pub fn newV7AtTime(ts: i64) Error!UUID { return default_generator.newV7AtTime(ts); }
pub fn newV8(a: [6]u8, b: [2]u8, c: [8]u8) Error!UUID {
    return default_generator.newV8(a, b, c);
}

test "top-level newV4 delegates to default_generator" {
    const u = try newV4();
    try std.testing.expectEqual(@import("uuid.zig").Version.v4, u.version());
}

test "top-level newV7 delegates to default_generator" {
    const u = try newV7();
    try std.testing.expectEqual(@import("uuid.zig").Version.v7, u.version());
}

test "top-level newV3 with DNS namespace" {
    const ns = @import("namespace.zig").namespace_dns;
    const u = newV3(ns, "www.example.com");
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "5df41881-3aed-3515-88a7-2f4a814cf09e",
        u.toString(&buf),
    );
}
```

- [ ] **Step 2: Run tests**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: all pass.

- [ ] **Step 3: Format and commit**

```bash
zig fmt src/versions.zig
git add src/versions.zig
git commit -m "feat: add package-level UUID convenience functions (newV1-newV8)"
```

---

## Task 14: NullUUID with JSON Serialization

**Files:**

- Create: `src/null_uuid.zig`
- Modify: `src/uuid.zig` (add `jsonMarshal`/`jsonUnmarshal` to `UUID`)

- [ ] **Step 1: Add json marshal methods to `UUID` in `src/uuid.zig`**

Add to the `UUID` struct body:

```zig
const json = @import("json");

pub fn jsonMarshal(self: UUID, allocator: std.mem.Allocator) !json.Value {
    var buf: [36]u8 = undefined;
    return .{ .str = try allocator.dupe(u8, self.toString(&buf)) };
}

/// allocator parameter exists for interface conformance; UUID.fromString is zero-alloc.
pub fn jsonUnmarshal(allocator: std.mem.Allocator, v: json.Value) !UUID {
    _ = allocator;
    if (v != .str) return Error.InvalidFormat;
    return fromString(v.str);
}
```

- [ ] **Step 2: Create `src/null_uuid.zig`**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");
const json = @import("json");
const UUID = @import("uuid.zig").UUID;

/// A nullable UUID wrapper with JSON marshaling support.
/// Serializes to null JSON or "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".
pub const NullUUID = struct {
    uuid:  UUID = UUID.nil,
    valid: bool = false,

    /// Wrap an existing UUID as a valid NullUUID.
    pub fn from(u: UUID) NullUUID {
        return .{ .uuid = u, .valid = true };
    }

    /// Return null if not valid, or the UUID value.
    pub fn value(self: NullUUID) ?UUID {
        return if (self.valid) self.uuid else null;
    }

    /// json library custom marshaler.
    /// Emits JSON null (invalid) or "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" (valid).
    pub fn jsonMarshal(self: NullUUID, allocator: std.mem.Allocator) !json.Value {
        if (!self.valid) return .null;
        var buf: [36]u8 = undefined;
        return .{ .str = try allocator.dupe(u8, self.uuid.toString(&buf)) };
    }

    /// json library custom unmarshaler.
    /// allocator parameter exists for interface conformance; UUID.fromString is zero-alloc.
    pub fn jsonUnmarshal(allocator: std.mem.Allocator, v: json.Value) !NullUUID {
        _ = allocator;
        return switch (v) {
            .null => .{},
            .str  => |s| .{ .uuid = try UUID.fromString(s), .valid = true },
            else  => error.InvalidFormat,
        };
    }
};

test "NullUUID.from and value()" {
    const u = UUID.nil;
    const nu = NullUUID.from(u);
    try std.testing.expect(nu.valid);
    try std.testing.expect((nu.value() orelse unreachable).eql(u));
}

test "NullUUID zero value is invalid" {
    const nu = NullUUID{};
    try std.testing.expect(!nu.valid);
    try std.testing.expect(nu.value() == null);
}

test "NullUUID.jsonMarshal: null when invalid" {
    const alloc = std.testing.allocator;
    const nu = NullUUID{};
    const v = try nu.jsonMarshal(alloc);
    try std.testing.expect(v == .null);
}

test "NullUUID.jsonMarshal: string when valid" {
    const alloc = std.testing.allocator;
    const u = try UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const nu = NullUUID.from(u);
    const v = try nu.jsonMarshal(alloc);
    defer alloc.free(v.str);
    try std.testing.expect(v == .str);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", v.str);
}

test "NullUUID.jsonUnmarshal: null input → invalid NullUUID" {
    const nu = try NullUUID.jsonUnmarshal(std.testing.allocator, .null);
    try std.testing.expect(!nu.valid);
}

test "NullUUID.jsonUnmarshal: string input → valid NullUUID" {
    const v = json.Value{ .str = "6ba7b810-9dad-11d1-80b4-00c04fd430c8" };
    const nu = try NullUUID.jsonUnmarshal(std.testing.allocator, v);
    try std.testing.expect(nu.valid);
    var buf: [36]u8 = undefined;
    try std.testing.expectEqualStrings(
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        nu.uuid.toString(&buf),
    );
}
```

- [ ] **Step 3: Run tests**

```bash
zig build test --summary all 2>&1 | grep -E "(PASS|FAIL|error)"
```

Expected: all NullUUID and UUID json tests PASS.

- [ ] **Step 4: Format and commit**

```bash
zig fmt src/uuid.zig src/null_uuid.zig
git add src/uuid.zig src/null_uuid.zig
git commit -m "feat: add NullUUID with JSON marshal/unmarshal and UUID jsonMarshal/jsonUnmarshal"
```

---

## Task 15: Public API Surface (`src/root.zig`)

**Files:**

- Rewrite: `src/root.zig`

- [ ] **Step 1: Rewrite `src/root.zig`**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # uuid
//!
//! A fully RFC-9562-compliant UUID library for Zig.
//!
//! Supports UUID versions V1, V3, V4, V5, V6, V7, V8 with:
//! - Injectable generator (clock, random, hardware address)
//! - Cross-platform MAC resolution (Linux, macOS, Windows)
//! - Multiple parse formats (canonical, braced, hash, URN)
//! - JSON serialization via gitlab.com/devnw/zig/json
//!
//! ## Quick Start
//!
//! ```zig
//! const uuid = @import("uuid");
//!
//! const u = try uuid.newV7();          // k-sortable timestamp UUID
//! const u4 = try uuid.newV4();         // random UUID
//! const v3 = uuid.newV3(uuid.namespace_dns, "example.com");
//!
//! var buf: [36]u8 = undefined;
//! std.debug.print("{s}\n", .{u.toString(&buf)});
//! ```

const builtin = @import("builtin");

// Core types
pub const UUID       = @import("uuid.zig").UUID;
pub const Version    = @import("uuid.zig").Version;
pub const Variant    = @import("uuid.zig").Variant;
pub const Error      = @import("uuid.zig").Error;
pub const NullUUID   = @import("null_uuid.zig").NullUUID;

// Timestamp
pub const Timestamp         = @import("timestamp.zig").Timestamp;
pub const timestampFromV1   = @import("timestamp.zig").timestampFromV1;
pub const timestampFromV6   = @import("timestamp.zig").timestampFromV6;
pub const timestampFromV7   = @import("timestamp.zig").timestampFromV7;

// Namespace constants
pub const nil            = @import("namespace.zig").nil;
pub const max            = @import("namespace.zig").max;
pub const namespace_dns  = @import("namespace.zig").namespace_dns;
pub const namespace_url  = @import("namespace.zig").namespace_url;
pub const namespace_oid  = @import("namespace.zig").namespace_oid;
pub const namespace_x500 = @import("namespace.zig").namespace_x500;

// Generator
pub const Generator        = @import("generator.zig").Generator;
pub const default_generator = @import("generator.zig").default_generator;

// Package-level convenience functions
pub const newV1       = @import("versions.zig").newV1;
pub const newV1AtTime = @import("versions.zig").newV1AtTime;
pub const newV3       = @import("versions.zig").newV3;
pub const newV4       = @import("versions.zig").newV4;
pub const newV5       = @import("versions.zig").newV5;
pub const newV6       = @import("versions.zig").newV6;
pub const newV6AtTime = @import("versions.zig").newV6AtTime;
pub const newV7       = @import("versions.zig").newV7;
pub const newV7AtTime = @import("versions.zig").newV7AtTime;
pub const newV8       = @import("versions.zig").newV8;

// Windows GUID interop (only available on Windows builds)
pub const guidToUUID = if (builtin.os.tag == .windows)
    @import("hwaddr/hwaddr.zig").guidToUUID
else
    @compileError("guidToUUID is only available on Windows");

pub const uuidToGUID = if (builtin.os.tag == .windows)
    @import("hwaddr/hwaddr.zig").uuidToGUID
else
    @compileError("uuidToGUID is only available on Windows");

pub const version = "0.1.0";

test {
    _ = @import("uuid.zig");
    _ = @import("namespace.zig");
    _ = @import("timestamp.zig");
    _ = @import("generator.zig");
    _ = @import("versions.zig");
    _ = @import("null_uuid.zig");
    _ = @import("hwaddr/hwaddr.zig");
}
```

- [ ] **Step 2: Run full test suite**

```bash
zig build test --summary all
```

Expected: all tests PASS with no errors.

- [ ] **Step 3: Run cross-compile check**

```bash
make cross-compile-required
```

Expected: all 5 targets pass.

- [ ] **Step 4: Format and commit**

```bash
zig fmt src/root.zig
git add src/root.zig
git commit -m "feat: wire public API surface in root.zig"
```

---

## Task 16: Integration Tests

**Files:**

- Rewrite: `tests/integration.zig`

- [ ] **Step 1: Rewrite `tests/integration.zig`**

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Integration tests — cross-module round-trips, JSON, and concurrent generation.

const std = @import("std");
const uuid = @import("uuid");
const json = @import("json");

// =============================================================================
// Round-trip: generate → toString → fromString → eql
// =============================================================================

test "integration: V4 round-trip" {
    const u = try uuid.newV4();
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const u2 = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(u2));
}

test "integration: V7 round-trip" {
    const u = try uuid.newV7();
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const u2 = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(u2));
}

test "integration: V3 round-trip" {
    const u = uuid.newV3(uuid.namespace_dns, "www.example.com");
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const u2 = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(u2));
}

test "integration: V5 round-trip" {
    const u = uuid.newV5(uuid.namespace_url, "https://example.com");
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const u2 = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(u2));
}

test "integration: V1 round-trip" {
    const u = try uuid.newV1();
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    const u2 = try uuid.UUID.fromString(s);
    try std.testing.expect(u.eql(u2));
    // Version and variant preserved
    try std.testing.expectEqual(uuid.Version.v1, u2.version());
    try std.testing.expectEqual(uuid.Variant.rfc9562, u2.variant());
}

// =============================================================================
// NullUUID JSON round-trip
// =============================================================================

test "integration: NullUUID null JSON round-trip" {
    const alloc = std.testing.allocator;
    const nu = uuid.NullUUID{};
    const v = try nu.jsonMarshal(alloc);
    try std.testing.expect(v == .null);
    const nu2 = try uuid.NullUUID.jsonUnmarshal(alloc, v);
    try std.testing.expect(!nu2.valid);
}

test "integration: NullUUID string JSON round-trip" {
    const alloc = std.testing.allocator;
    const u = try uuid.newV4();
    const nu = uuid.NullUUID.from(u);
    const v = try nu.jsonMarshal(alloc);
    defer alloc.free(v.str);
    const nu2 = try uuid.NullUUID.jsonUnmarshal(alloc, v);
    try std.testing.expect(nu2.valid);
    try std.testing.expect(nu2.uuid.eql(u));
}

test "integration: UUID in struct encoded with json.encode" {
    const alloc = std.testing.allocator;
    const MyStruct = struct {
        id: uuid.UUID,
        name: []const u8,
    };
    const s = MyStruct{
        .id   = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8"),
        .name = "test",
    };
    const encoded = try json.encode(alloc, s, .{ .allocator = alloc });
    defer alloc.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "6ba7b810-9dad-11d1-80b4-00c04fd430c8") != null);
}

// =============================================================================
// Concurrent V7 generation: no duplicates, strictly monotone per goroutine
// =============================================================================

const ConcurrentResult = struct {
    uuids: [100]uuid.UUID = undefined,
    err: ?anyerror = null,
};

fn generateV7s(gen: *uuid.Generator, result: *ConcurrentResult) void {
    for (&result.uuids) |*u| {
        u.* = gen.newV7() catch |e| {
            result.err = e;
            return;
        };
    }
}

test "integration: concurrent V7 generation — no duplicates" {
    var gen = uuid.Generator.init();
    var results: [4]ConcurrentResult = .{.{}} ** 4;
    var threads: [4]std.Thread = undefined;

    for (&threads, &results) |*t, *r| {
        t.* = try std.Thread.spawn(.{}, generateV7s, .{ &gen, r });
    }
    for (&threads) |*t| t.join();

    for (&results) |*r| {
        try std.testing.expect(r.err == null);
    }

    // Collect all UUIDs and check for duplicates
    var all: [400]uuid.UUID = undefined;
    var idx: usize = 0;
    for (&results) |r| {
        for (r.uuids) |u| {
            all[idx] = u;
            idx += 1;
        }
    }
    // Sort and check adjacent for equality
    std.mem.sort(uuid.UUID, &all, {}, struct {
        pub fn lt(_: void, a: uuid.UUID, b: uuid.UUID) bool {
            return a.order(b) == .lt;
        }
    }.lt);
    for (0..all.len - 1) |i| {
        try std.testing.expect(!all[i].eql(all[i + 1]));
    }
}

// =============================================================================
// All parse formats produce the same UUID
// =============================================================================

test "integration: all six parse formats produce identical UUID" {
    const canonical      = "6ba7b810-9dad-11d1-80b4-00c04fd430c8";
    const braced         = "{6ba7b810-9dad-11d1-80b4-00c04fd430c8}";
    const hash           = "6ba7b8109dad11d180b400c04fd430c8";
    const braced_hash    = "{6ba7b8109dad11d180b400c04fd430c8}";
    const urn_canonical  = "urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8";
    const urn_hash       = "urn:uuid:6ba7b8109dad11d180b400c04fd430c8";

    const base = try uuid.UUID.fromString(canonical);
    const inputs = [_][]const u8{ braced, hash, braced_hash, urn_canonical, urn_hash };
    for (inputs) |s| {
        const u = try uuid.UUID.fromString(s);
        try std.testing.expect(base.eql(u));
    }
}
```

- [ ] **Step 2: Run integration tests**

```bash
zig build test-integration --summary all
```

Expected: all integration tests PASS.

- [ ] **Step 3: Format and commit**

```bash
zig fmt tests/integration.zig
git add tests/integration.zig
git commit -m "test: add integration tests — round-trips, JSON, concurrent V7 generation"
```

---

## Task 17: Update Examples

**Files:**

- Modify: `examples/basic.zig`

- [ ] **Step 1: Update `examples/basic.zig`** to demonstrate all UUID versions

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Basic usage examples for the uuid library.

const std = @import("std");
const uuid = @import("uuid");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var buf: [36]u8 = undefined;

    try stdout.print("uuid library — RFC-9562 examples\n", .{});
    try stdout.print("=================================\n\n", .{});

    // V4: random
    const v4 = try uuid.newV4();
    try stdout.print("V4 (random):            {s}\n", .{v4.toString(&buf)});

    // V7: Unix-ms timestamp + monotonic counter
    const v7 = try uuid.newV7();
    try stdout.print("V7 (timestamp+random):  {s}\n", .{v7.toString(&buf)});

    // V7 at a historical timestamp (1,700,000,000,000 ms = 2023-11-14)
    const v7_hist = try uuid.newV7AtTime(1_700_000_000_000);
    try stdout.print("V7 (historical ts):     {s}\n", .{v7_hist.toString(&buf)});

    // V3: MD5 namespace hash
    const v3 = uuid.newV3(uuid.namespace_dns, "www.example.com");
    try stdout.print("V3 (MD5/DNS):           {s}\n", .{v3.toString(&buf)});

    // V5: SHA-1 namespace hash
    const v5 = uuid.newV5(uuid.namespace_dns, "www.example.com");
    try stdout.print("V5 (SHA1/DNS):          {s}\n", .{v5.toString(&buf)});

    // V1: time + MAC
    const v1 = uuid.newV1() catch |e| blk: {
        try stdout.print("V1: skipped ({s})\n", .{@errorName(e)});
        break :blk uuid.UUID.nil;
    };
    if (!v1.isNil()) try stdout.print("V1 (time+MAC):          {s}\n", .{v1.toString(&buf)});

    // V6: k-sortable time + MAC
    const v6 = uuid.newV6() catch |e| blk: {
        try stdout.print("V6: skipped ({s})\n", .{@errorName(e)});
        break :blk uuid.UUID.nil;
    };
    if (!v6.isNil()) try stdout.print("V6 (k-sortable time):   {s}\n", .{v6.toString(&buf)});

    // Parse formats
    try stdout.print("\nParse formats (all produce the same UUID):\n", .{});
    const formats = [_][]const u8{
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        "{6ba7b810-9dad-11d1-80b4-00c04fd430c8}",
        "6ba7b8109dad11d180b400c04fd430c8",
        "urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    };
    for (formats) |s| {
        const u = try uuid.UUID.fromString(s);
        try stdout.print("  parse({s})\n         → {s}\n", .{ s, u.toString(&buf) });
    }

    // Timestamp extraction
    const ts = try uuid.timestampFromV7(v7);
    try stdout.print("\nV7 timestamp (Unix ms): {d}\n", .{ts});

    // NullUUID
    const nu_valid = uuid.NullUUID.from(v4);
    const nu_null  = uuid.NullUUID{};
    try stdout.print("\nNullUUID valid: {any}\n", .{nu_valid.value()});
    try stdout.print("NullUUID null:  {any}\n", .{nu_null.value()});

    try stdout.print("\nAll examples completed successfully!\n", .{});
}
```

- [ ] **Step 2: Format and verify it compiles**

```bash
zig fmt examples/basic.zig
zig build check
```

- [ ] **Step 3: Commit**

```bash
git add examples/basic.zig
git commit -m "docs: update basic.zig example to demonstrate all UUID versions"
```

---

## Task 18: Final Validation

- [ ] **Step 1: Run full test suite**

```bash
make test
```

Expected: all unit and integration tests PASS.

- [ ] **Step 2: Run all optimization levels**

```bash
make test-all-optimizations
```

Expected: all PASS at Debug, ReleaseSafe, ReleaseFast, ReleaseSmall.

- [ ] **Step 3: Run cross-compile check**

```bash
make cross-compile-required
```

Expected: all 5 targets compile cleanly.

- [ ] **Step 4: Run pre-commit on all files**

```bash
make pre-commit
```

Expected: all hooks PASS.

- [ ] **Step 5: Confirm test coverage** — all version bit layouts tested, RFC Appendix B vectors verified, concurrent test passes, NullUUID JSON round-trip passes.

- [ ] **Step 6: Tag completion commit if all pass**

```bash
git add -A
git commit -m "feat: complete RFC-9562 UUID library — V1/V3/V4/V5/V6/V7/V8 with full test suite"
```

---

## Appendix: Test Vector Reference

### RFC-9562 Appendix B Name-Based Vectors

| Version | Namespace | Name | Expected UUID |
|---|---|---|---|
| V3 (MD5) | DNS | <www.example.com> | `5df41881-3aed-3515-88a7-2f4a814cf09e` |
| V5 (SHA-1) | DNS | <www.example.com> | `2ed6657d-e927-568b-95e3-af9b26a12f30` |

### Namespace UUID Byte Values

| Name | Value |
|---|---|
| `namespace_dns` | `6ba7b810-9dad-11d1-80b4-00c04fd430c8` |
| `namespace_url` | `6ba7b811-9dad-11d1-80b4-00c04fd430c8` |
| `namespace_oid` | `6ba7b812-9dad-11d1-80b4-00c04fd430c8` |
| `namespace_x500` | `6ba7b814-9dad-11d1-80b4-00c04fd430c8` |

### Version Bit Rules (setVersion / setVariant)

| Op | Byte | Mask | Set |
|---|---|---|---|
| setVersion(v) | 6 | `& 0x0F` | `\| (v << 4)` |
| setVariant(.rfc9562) | 8 | `& 0x3F` | `\| 0x80` |
| setVariant(.microsoft) | 8 | `& 0x1F` | `\| 0xC0` |
