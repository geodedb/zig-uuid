# uuid

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.16.0+-orange.svg)](https://ziglang.org/)

A fully RFC-9562-compliant UUID library for Zig.

## Features

- **RFC-9562 Compliant**: Full V1, V3, V4, V5, V6, V7, V8 support
- **Memory Safe**: Proper allocation patterns with no leaks
- **Cross-Platform**: Linux, macOS, Windows support
- **Well Tested**: Comprehensive unit and integration tests
- **Injectable**: Clock, random, and hardware-address functions are swappable

## Installation

### Using Zig Package Manager

**Recommended:** use `zig fetch --save` — it downloads the archive, computes
the content hash, and writes a correctly-formed `build.zig.zon` entry for you
in one step:

```bash
zig fetch --save https://gitlab.com/devnw/zig/uuid/-/archive/v0.1.0/uuid-v0.1.0.tar.gz
```

After this runs, your `build.zig.zon` will contain an entry that looks
approximately like the block below. The `.hash` value is **content-addressed**
— `zig fetch` derives it from the downloaded tarball, so you should not
hand-edit it or copy it from documentation. The snippet below is for
reference only:

```zig
.dependencies = .{
    .uuid = .{
        .url = "https://gitlab.com/devnw/zig/uuid/-/archive/v0.1.0/uuid-v0.1.0.tar.gz",
        .hash = "<populated by `zig fetch --save`>",
    },
},
```

> Note: v0.1.0 is unreleased; until the tag is published, point `.url` at a
> specific commit archive (`.../archive/<sha>.tar.gz`) and re-run
> `zig fetch --save` to refresh the hash.

Then in your `build.zig`:

```zig
const uuid = b.dependency("uuid", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("uuid", uuid.module("uuid"));
```

## Quick Start

### Using `toString(&buf)` with `std.debug.print` (simplest)

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

    // Zero-alloc: no buffer needed (Zig 0.16+ {f} specifier)
    std.debug.print("{f}\n", .{v7});

    // Parse any supported format (canonical, braced, hash, URN)
    const parsed = try uuid.UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    std.debug.print("parsed: {s}\n", .{parsed.toString(&buf)});
}
```

### Using `std.Io.Writer` with the `{f}` format specifier (Zig 0.16 idiomatic)

`UUID.format(w: *std.Io.Writer)` lets any `std.Io.Writer` consume a UUID
without a caller-owned buffer. Pair it with `{f}` when you are already
working with a writer (stdout, a log sink, a `std.Io.Writer.Allocating`,
etc.):

```zig
const std = @import("std");
const uuid = @import("uuid");

pub fn main() !void {
    // Set up a buffered writer over stdout (Zig 0.16 std.Io pattern).
    var out_buf: [4096]u8 = undefined;
    const io = std.Io.Threaded.global_single_threaded.io();
    var out = std.Io.File.stdout().writer(io, &out_buf);
    defer out.interface.flush() catch {};
    const w = &out.interface;

    const v7 = try uuid.newV7();
    const v4 = try uuid.newV4();

    // Zero-alloc: UUID.format writes straight into the writer, no stack buffer.
    try w.print("V7: {f}\n", .{v7});
    try w.print("V4: {f}\n", .{v4});

    // Works anywhere std.Io.Writer is expected — std.log, std.fmt.allocPrint,
    // custom sinks, etc.
    std.log.info("generated {f}", .{v7});
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

JSON marshal / unmarshal for `NullUUID` live in the separate `uuid_json`
module as free functions (`nullUuidJsonMarshal` / `nullUuidJsonUnmarshal`)
so the core `uuid` module does not import `json`. See
[JSON Adapter](#json-adapter) below for signatures and usage.

### Generator

| Method | Description |
|--------|-------------|
| `Generator.init() Generator` | Default generator (CSPRNG, random node) |
| `Generator.withClock(f) Generator` | Inject a custom clock function |
| `Generator.withRand(f) Generator` | Inject a custom random-bytes function (e.g. for testing) |
| `Generator.withHWAddr(f) Generator` | Opt in to real MAC address embedding |
| `gen.lockfreeFallbackCount() u64` | Diagnostic counter: V7 lock-free path fallbacks (PERF-21) |
| `Generator.initOptions(opts) Generator` | Single entry point for `{random, clock, hwaddr_fn, state_mac_key, state_mac_policy, v7_lockfree}` (SEC-P3-08) |
| `gen.clearNodeCache()` | Force re-sample of node ID |
| `gen.reseed()` | Fork-safe CSPRNG re-seed; call post-`fork(2)` in the child (SEC-P3-01) |
| `gen.secureWipeMacKey()` | Zero and clear `state_mac_key` (CWE-316); idempotent |
| `gen.saveState(path) !void` | Persist clock state to file (mode 0o600) |
| `gen.loadState(path) !void` | Restore clock state from file |
| `gen.newV3Strict(ns, name) UUID` | V3 name-based UUID; `ns` is a vetted `Namespace` enum (SEC-P3-05) |
| `gen.newV5Strict(ns, name) UUID` | V5 name-based UUID; `ns` is a vetted `Namespace` enum (SEC-P3-05) |
| `gen.newV3Bounded(ns, name, max_len) !UUID` | V3 with hash-DoS cap; returns `NameTooLong` if `name.len > max_len` (SEC-P4-12) |
| `gen.newV5Bounded(ns, name, max_len) !UUID` | V5 with hash-DoS cap; returns `NameTooLong` if `name.len > max_len` (SEC-P4-12) |
| `gen.initV3Namespace(ns) PrehashedV3` | Pre-absorb namespace Md5 state for high-throughput V3-in-namespace loops (PERF-30) |
| `gen.initV5Namespace(ns) PrehashedV5` | Pre-absorb namespace Sha1 state for high-throughput V5-in-namespace loops (PERF-30) |
| `gen.migrateStateToV3(path) !void` | Rewrite a v1/v2 state file as v3 under the current `state_mac_key` (SEC-P4-01) |
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

### JSON Adapter

The JSON adapter ships as a separate `uuid_json` module (see `build.zig`) to
avoid pulling a `json` dependency into the core `uuid` module. Consumers that
need JSON support depend on the `uuid_json` module explicitly and call the
four free functions below (no methods on `UUID` / `NullUUID`):

| Function | Description |
|----------|-------------|
| `uuid_json.uuidJsonMarshal(u, alloc) !json.Value` | Marshal a `UUID` to a canonical lowercase `json.Value.str` (heap-allocated with `alloc`). |
| `uuid_json.uuidJsonUnmarshal(alloc, v) !UUID` | Parse a `UUID` from a `json.Value.str`; returns `Error.InvalidFormat` on any other value. |
| `uuid_json.nullUuidJsonMarshal(nu, alloc) !json.Value` | Marshal a `NullUUID`: canonical string when `valid`, `json.Value.null` otherwise. |
| `uuid_json.nullUuidJsonUnmarshal(alloc, v) !NullUUID` | Accept `json.Value.null` or a canonical UUID string; reject other types with `Error.InvalidFormat`. |

```zig
const uuid_json = @import("uuid_json");

// Marshal: returns a heap-allocated json.Value.str — caller frees the
// backing slice (typically via json.Value.deinit).
const v = try uuid_json.uuidJsonMarshal(my_uuid, allocator);
defer allocator.free(v.str);

// Unmarshal: allocator is unused today (kept for interface conformance).
const parsed = try uuid_json.uuidJsonUnmarshal(allocator, v);
```

## Requirements

- Zig 0.16.0 or later

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

## Generator Lifecycle & Advanced API

The top-level `uuid.newV4()` / `newV7()` / etc. convenience functions
dispatch through a shared `default_generator`. Most callers need
nothing more. The following surface is for callers who need explicit
control — multiple generators, injected clocks/CSPRNGs, authenticated
state persistence, or post-fork hygiene.

### Configuring a Generator

```zig
const uuid = @import("uuid");
const std = @import("std");

var gen = uuid.Generator.initOptions(.{
    // Bypass the global std.Io CSPRNG with a caller-supplied source.
    // Bypass is opt-in (SEC-P3-08); null → default global CSPRNG.
    .random = std.crypto.random,

    // Opt into the lock-free V7 CAS path (PERF-21).  Default false
    // keeps the mutex path authoritative for correctness.  Benchmarks
    // show the lockfree path wins cleanly at ≥ 2 threads; single-
    // threaded workloads gain nothing and should leave this false.
    .v7_lockfree = true,

    // Authenticate the on-disk state file with HMAC-SHA256 (SEC-P3-04).
    // When set, saveState writes wire-format v3; loadState requires
    // the key to verify the HMAC trailer.
    .state_mac_key = some_32_byte_key,
});
```

### Namespace-Locked V3/V5 (SEC-P3-05)

For maximum-safety V3/V5 generation, pass a `Namespace` enum value
instead of a raw `UUID` — the compiler rejects attacker-controlled
namespace bytes at compile time:

```zig
const id = try uuid.newV3Strict(.dns, "example.com");
// .dns | .url | .oid | .x500 — the four RFC-9562 §6.6 constants.
// For a vetted non-RFC namespace, pass `Namespace{ .custom = bytes }`
// where `bytes` is a compile-time constant.  See src/namespace.zig
// for the CWE-347 threat model — never derive `.custom` bytes from
// untrusted input.
```

### Prehashed Namespaces (PERF-30)

For workloads that generate many V3/V5 UUIDs under the same namespace,
amortise the namespace hash once:

```zig
const prehash = uuid.initV3Namespace(uuid.namespace_dns);
for (hostnames) |h| {
    const id = prehash.name(h);
    // ~1.2× faster than newV3(namespace_dns, h) on short names.
}
```

### State Persistence (F-9, SEC-P3-02/03/04)

```zig
try uuid.saveState("/var/lib/myapp/uuid.state");
// Writes 0o600 (umask-proof via fchmod, SEC-P3-03).
// Includes HMAC trailer if state_mac_key is configured.

try uuid.loadState("/var/lib/myapp/uuid.state");
// Rejects future-dated state > 1000 ms beyond current clock
// (SEC-P3-02 clock_rollback_tolerance_ms).
// Rejects HMAC mismatch with Error.StateMacMismatch.
```

### Post-Fork Hygiene (SEC-P3-01)

`fork()` duplicates the in-process CSPRNG state. The child MUST
re-seed before generating UUIDs or it will collide with the parent:

```zig
const pid = try std.posix.fork();
if (pid == 0) {
    uuid.reseed();  // child: re-draws CSPRNG from getrandom(2)
    // generate UUIDs normally...
}
```

### Secure Key Disposal (SEC-P3-04)

Long-lived processes holding a `state_mac_key` should zero it before
the Generator falls out of scope:

```zig
uuid.secureWipeMacKey();
// Volatile-zeroes the 32-byte key and clears the optional.
// Idempotent; safe when no key was configured.
```

### Full Error Set

`uuid.Error` is the library's error set. Members added since v0.1.0:

- `Error.StateMacMismatch` — loadState rejected an HMAC tag mismatch
  (tampered file) or a v3 file when no `state_mac_key` is configured.

### Hash Contexts

Three `HashContext` variants for `std.HashMap(UUID, V, ctx, _)`:

| Variant | Seed | Use |
|---|---|---|
| `UUID.HashContext` | fixed (non-cryptographic) | Untrusted UUIDs in a map where HashDoS is already mitigated upstream. |
| `UUID.ProcessHashContext` | once per process via CSPRNG | Untrusted UUIDs — HashDoS-safe, sub-ns per hash once seeded. |
| `UUID.SecureHashContext` | per-instance via CSPRNG | Multiple independent maps in one process needing separate seeds. |

### Generator Interface for Dependency Injection

Two forms — pick based on call-site needs:

```zig
// Runtime-polymorphic (vtable dispatch) — use in tests or when the
// concrete Generator type must be erased.
const gi: uuid.GeneratorInterface = gen.interface();

// Comptime-generic (inlined direct dispatch) — zero indirection at
// ReleaseFast, use in hot paths that hold a *Generator anyway.
const GIFor = uuid.GeneratorInterfaceFor(uuid.Generator);
const gi_fast = GIFor{ .g = &gen };
```

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

### Forked Processes

After `fork(2)` on POSIX, the child inherits the parent's cached CSPRNG-derived state
(`clock_seq`, `mono_seq`, `node_cache`), which can cause colliding UUIDs. Call
`Generator.reseed()` in the child before generating any UUIDs. See
[SECURITY.md](SECURITY.md) (Forked processes) for the full rationale and example.

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

### V3/V5 Prehashed Namespaces (PERF-30 / PERF-41)

`Generator.initV3Namespace(ns)` and `Generator.initV5Namespace(ns)` return a
`PrehashedV3` / `PrehashedV5` handle that captures the MD5 / SHA-1 hasher
state after the 16-byte namespace has been absorbed. Calling `.name(bytes)`
on the handle clones the hasher, feeds the name, and finalises — skipping
the per-call MD5 / SHA-1 init + namespace update that `newV3(ns, name)`
and `newV5(ns, name)` perform on every invocation.

For repeated generation under the same namespace, prefer the prehashed
helpers — they skip the per-call hasher init + namespace update, which
is the dominant cost on short names. Measured ~1.2x speedup on short
hostnames; the delta grows with call count.

```zig
const uuid = @import("uuid");

// One-time setup: absorb the namespace.
const pre = uuid.initV3Namespace(uuid.namespace_dns);

// Reuse across many names — zero re-hash of the 16-byte namespace.
for (hostnames) |h| {
    const id = pre.name(h);
    _ = id;
}
```

Equivalent V5 helper: `uuid.initV5Namespace(ns)` returning a `PrehashedV5`
with the same `.name(bytes)` contract.

Security: the prehashed handles inherit the same MD5 / SHA-1 collision
caveats as `newV3` / `newV5`. Use `newV5Strict` / `newV5Bounded` at the
call sites where you want the SEC-P3-05 namespace allow-list or the
SEC-P4-12 length cap; there is no prehashed variant of those strict /
bounded wrappers today (considered as option (b) "NamespacedGenerator
wrapper" under PERF-41 and deferred — the raw prehashed handles are
sufficient for the current workload profiles).

## Benchmarks

The repo ships a structured JSON benchmark suite under `benchmarks/`
modelled after the devnw/zig/thread-pool harness. Runs produce
results/latest*.json; committed baselines under
`benchmarks/results/baseline*.json` gate the CI regression job.

### Running benchmarks

```bash
# Single-thread hot-path scenarios (v4, v7, parse, format, eql, …).
# ~90s at ReleaseFast, 23 scenarios.
zig build bench -Doptimize=ReleaseFast -- \
    --output benchmarks/results/latest.json

# Multi-thread V7 contention matrix (mutex vs lockfree × 2/4/8/16 T).
# ~60s at ReleaseFast.  15-run median-of-10 for low noise (INV-01).
zig build bench-contention -Doptimize=ReleaseFast -- \
    --output benchmarks/results/latest_contention.json

# State persistence (saveState/loadState, v2 vs v3-HMAC vs wrong-key).
zig build bench-state -Doptimize=ReleaseFast -- \
    --output benchmarks/results/latest_state.json

# Latency-percentile micro-benchmarks.
zig build bench-micro-parse  -Doptimize=ReleaseFast -- --output ...
zig build bench-micro-format -Doptimize=ReleaseFast -- --output ...
zig build bench-micro-hash   -Doptimize=ReleaseFast -- --output ...

# Everything at once.
zig build bench-all -Doptimize=ReleaseFast
```

### Regression gating

```bash
# Single-pair compare (baseline vs candidate file).
zig build bench-compare -- \
    --baseline benchmarks/results/baseline.json \
    --candidate benchmarks/results/latest.json \
    --threshold 0.15

# Walker mode — auto-pairs every baseline*.json with its latest*.json
# sibling and aggregates failures.  Used by CI.
zig build bench-compare-all -- --threshold 0.15
```

The regression gate uses `max(threshold, 3×stddev)` per-row — so a
noisy row gets a wider effective gate but a quiet row cannot sneak
through below the hard 15% floor. Contention scenarios additionally
emit a `WARN` line (non-fatal) when `lockfree_fallbacks` drifts by
more than 50% from baseline — a leading indicator of real contention
changes that throughput-only gates may miss.

### CI integration

The `bench-regression` job in `.gitlab-ci.yml` pins both `bench` and
`bench-contention` to dedicated cores via `taskset -c 2-N` on runners
with ≥4 cores (INV-01), so CI machinery on cores 0-1 does not perturb
contention scenarios. `BENCH_PIN_CORES=0` disables pinning explicitly.

### Regenerating baselines

When an intentional perf change lands, regenerate baselines and commit:

```bash
zig build bench -Doptimize=ReleaseFast -- --output benchmarks/results/baseline.json
zig build bench-contention -Doptimize=ReleaseFast -- --output benchmarks/results/baseline_contention.json
zig build bench-state -Doptimize=ReleaseFast -- --output benchmarks/results/baseline_state.json
zig build bench-micro-parse -Doptimize=ReleaseFast -- --output benchmarks/results/baseline_micro_parse.json
zig build bench-micro-format -Doptimize=ReleaseFast -- --output benchmarks/results/baseline_micro_format.json
zig build bench-micro-hash -Doptimize=ReleaseFast -- --output benchmarks/results/baseline_micro_hash.json
git add benchmarks/results/baseline*.json && git commit
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY.md](SECURITY.md) for security policy and vulnerability reporting.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
