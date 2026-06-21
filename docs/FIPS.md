<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2024-2026 CodePros -->

# FIPS-140-3 Mode (`-Dfips`)

## Flag semantics

`uuid` builds with a `-Dfips` flag (default `false`). When **off**, the
security-relevant crypto routes through `src/std_shim.zig` (pure `std.crypto`)
with **zero overhead, no `fips` dependency, and no OpenSSL link** — the seam's
fips branch is comptime-dead. When **on** (`-Dfips=true -Dopenssl_path=<prefix>`),
the same call sites route through the linked OpenSSL 3.x FIPS-140-3 provider via
the lazily-resolved `fips` package, and `crypto_backend.assertActive()` hard-fails
at startup if the validated provider is not loaded and self-tested.

Build/test both modes:

```sh
zig build test --summary all
OPENSSL_CONF=/usr/local/ssl/ssl/openssl.cnf zig build test -Dfips=true -Dopenssl_path=/usr/local/ssl --summary all
# or:  make test-dual   (OPENSSL_PREFIX overrides the default /usr/local/ssl)
```

The seam is the canonical `src/crypto_backend.zig`, backed by `src/std_shim.zig`

+ `src/policy.zig` (the three CANONICAL copy-verbatim files) and the
`src/link.zig` OpenSSL build helper.

## Routed (security) call sites

| Site | Primitive | Seam call |
|------|-----------|-----------|
| `src/generator.zig` `defaultRand` | V4/V7 entropy + V1/V6 clock-seq CSPRNG | `crypto_backend.Csprng.bytes` |
| `src/generator.zig` save-side (state-file trailer) | persisted-state authentication | `crypto_backend.Mac.hmac(.sha256, …)` |
| `src/generator.zig` verify-side (state-file trailer) | persisted-state verification | `crypto_backend.Mac.hmac(.sha256, …)` |

## `fips-exempt` (allow-listed non-security) uses

| Site | Reason |
|------|--------|
| `src/uuid.zig` `process_seed` Wyhash seed | HashDoS-resistance seed for an in-memory HashMap, never a key |
| `src/uuid.zig` `SecureHashContext.init` seed | same — per-context HashMap seed |
| `src/uuid.zig` `timingSafeEql` | constant-time compare, no algorithm choice |
| `src/generator.zig` state-MAC compare | constant-time MAC compare, no algorithm choice |
| `src/generator.zig` `newV3` / `initV3Namespace` MD5 | RFC 9562 V3 deterministic namespace UUID (MD5 spec-mandated); no secret |
| `src/generator.zig` `newV5` / `initV5Namespace` SHA-1 | RFC 9562 V5 deterministic namespace UUID (SHA-1 spec-mandated); no secret |

## Behavior changes / removals under `-Dfips=true`

None. V3 (MD5) and V5 (SHA-1) name-based UUIDs are RFC-9562-mandated deterministic
identifiers with no secret and no adversary-integrity claim; they remain as
non-approved-but-exempt non-security primitives. The byte output of every routed
site is identical under both modes.
