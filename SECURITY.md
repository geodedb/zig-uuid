# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: <security@codepros.dev>

**Encrypted reporting:** If you need to encrypt your report, contact us at the
email above to request our PGP public key. We will provide the key and
fingerprint for verification.

Please include:

1. **Description** of the vulnerability
2. **Steps to reproduce** the issue
3. **Potential impact** assessment
4. **Suggested fix** (if you have one)

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 1 week
- **Resolution Timeline**: Depends on severity
  - Critical: 24-72 hours
  - High: 1-2 weeks
  - Medium: 2-4 weeks
  - Low: Next release cycle

### Disclosure Policy

- We follow responsible disclosure practices
- Security advisories will be published after fixes are available
- Credit will be given to reporters (unless anonymity is requested)

## Severity Classification (CVSS v3.1)

We assess reported vulnerabilities using [CVSS v3.1](https://www.first.org/cvss/v3-1/):

| Severity | CVSS Score | Response SLA |
|----------|-----------|--------------|
| Critical | 9.0–10.0  | 24–72 hours  |
| High     | 7.0–8.9   | 1–2 weeks    |
| Medium   | 4.0–6.9   | 2–4 weeks    |
| Low      | 0.1–3.9   | Next release |
| Info     | 0.0       | Backlog      |

## Severity Classification (CVSS v4.0)

We also accept reports scored against [CVSS v4.0](https://www.first.org/cvss/v4-0/).
The CVSS v4 score is authoritative when both scores are supplied.  The
response SLA tiers and numeric bands mirror the v3.1 table above;
examples of category fit are provided for reference.

| Severity | CVSS v4.0 Score | Response SLA | Typical example |
|----------|-----------------|--------------|-----------------|
| Critical | 9.0–10.0        | 24–72 hours  | Remote code execution, full CSPRNG compromise, unauthenticated auth bypass via UUID forgery. |
| High     | 7.0–8.9         | 1–2 weeks    | Predictable UUID on an auth-bearing path, state-file tamper leading to collision. |
| Medium   | 4.0–6.9         | 2–4 weeks    | Local information disclosure (e.g. hardware MAC leak on an opt-in config), timing side-channel requiring co-location. |
| Low      | 0.1–3.9         | Next release | Defensive hardening gaps, non-exploitable invariant violations. |
| Info     | 0.0             | Backlog      | Documentation or telemetry improvements. |

## Version Support Policy

| Version | Status             | Security Fixes Until |
|---------|--------------------|---------------------|
| 0.1.x   | :white_check_mark: Active | Current              |

Only the latest minor release receives security patches. When a new minor version
is released, the previous minor version reaches end-of-life 90 days after the new
release. Users should upgrade within that window to continue receiving fixes.

## Security Measures

This project implements:

- **Memory Safety**: Zig's compile-time memory safety checks
- **No Undefined Behavior**: Strict adherence to defined semantics
- **Dependency Scanning**: Automated security scanning in CI
- **Secret Detection**: Gitleaks scanning for leaked credentials

## Library Security Properties

### UUID Version Security

| Version | Algorithm | Collision Resistance | Notes |
|---------|-----------|---------------------|-------|
| V4 | CSPRNG | Strong (122 bits random) | Recommended for non-sorted use cases |
| V7 | Timestamp + CSPRNG | Strong (62 bits random) | Recommended for sorted use cases |
| V1/V6 | Gregorian + Node | Node-dependent | Default uses random multicast node (privacy-safe) |
| V5 | SHA-1 | Weakened (SHAttered) | Use for interop only; prefer V8 for new systems |
| V3 | MD5 | Broken | Avoid; exists for backward compat only |
| V8 | Custom | Caller-defined | Can be strong with modern hash |

### Known Design Trade-offs

1. **V1/V6 MAC disclosure (opt-in):** `Generator.withHWAddr()` embeds the real hardware
   MAC address in every V1/V6 UUID. This is an explicit opt-in; the default uses a random
   node ID. Only enable MAC-based nodes when recipients are trusted and MAC embedding is
   intentional.

2. **V7 monotonic counter predictability:** The 12-bit `rand_a` counter is randomly seeded
   each new millisecond and increments deterministically within the same millisecond. Within
   a single millisecond, generated UUIDs are predictable in their counter field. The 62-bit
   `rand_b` field remains fully random. This does not affect UUID uniqueness or collision
   resistance.

3. **HashDoS via HashContext:** `UUID.HashContext` uses a fixed Wyhash seed. Use
   `UUID.SecureHashContext` for untrusted UUID keys. See README for details.

4. **V3/V5 algorithm weakness:** MD5 (V3) and SHA-1 (V5) are cryptographically broken.
   Do not use for collision-sensitive applications. See README for alternatives.

5. **UUID.eql() is not constant-time (CWE-208):** `UUID.eql()` uses `std.mem.eql`, a
   short-circuit byte comparison that terminates at the first differing byte.  When a UUID
   is used as a secret capability — for example a V4 session token, invite token, or bearer
   credential — comparing it with `eql` leaks timing information that an attacker can use
   to recover the secret byte-by-byte via a remote timing oracle.  Use
   `UUID.timingSafeEql()` instead for any comparison where the UUID value is secret.
   `UUID.timingSafeEql()` wraps `std.crypto.timing_safe.eql` and runs in constant time
   regardless of where bytes first differ.  `UUID.eql()` remains correct and efficient for
   the typical case where UUIDs are public identifiers.

### Random source injection (SEC-P3-08)

The default `Generator.init()` sources UUID entropy from
`std.Io.Threaded.global_single_threaded.io().random()` — the process-global
`std.Io` handle.  For most applications this is correct and efficient.
However, the resolution runs through a module-level var, which means a
library co-resident in the same address space could in principle
substitute that var and poison every consumer of `Generator.init()`.

Callers concerned about this library-composition attack can supply an
explicit `std.Random` via `Generator.initOptions`:

```zig
// Build a CSPRNG bound to an Io handle the caller controls.
var chacha = std.Random.ChaCha.init(seed_bytes);
const csprng = chacha.random();

var gen = uuid.Generator.initOptions(.{ .random = csprng });
const u = try gen.newV4();
```

The injected `std.Random` is used for every V4 / V7 entropy read, bypassing
the global entirely.  `Generator.withRand(fn)` remains available for
callback-style injection; when both are present, `initOptions.random`
wins.

Properties:

- **Default path (`Generator.init()`):** global `std.Io` CSPRNG.
  Fastest, but trusts the process-global module state.
- **Explicit injection (`initOptions(.{ .random = r })`):** no global
  read on the hot path; the supplied `std.Random` is the sole entropy
  source.  Use this for hardened deployments.
- **Backward compatibility:** existing `init()` / `withClock` / `withRand`
  / `withHWAddr` constructors continue to work unchanged.

### Forked processes (SEC-P3-01, CWE-331 / CWE-665)

On POSIX, `fork(2)` duplicates the parent's entire address space, including any cached
CSPRNG-derived state held by a `Generator`:

- `clock_seq` (V1/V6 clock sequence initialised from the CSPRNG on first use)
- `mono_seq` (V7 12-bit monotonic counter seeded from the CSPRNG on each new millisecond)
- `node_cache` (the random multicast node ID when `hwaddr_fn` is unset)
- `last_ms` / `last_v1_ts` (monotonicity high-water marks)

If both the parent and the child continue minting UUIDs from that shared cached state,
they will emit identical or colliding UUIDs until the caches naturally roll over. Zig
0.16's standard library does **not** expose a portable `pthread_atfork` hook, and Windows
has no `fork(2)`, so the library cannot register an automatic post-fork handler.

**Mitigation:** call `Generator.reseed()` from the child process immediately after
`fork()` and before any UUID generation. `reseed()` zeroes `clock_seq`, `mono_seq`,
`last_ms`, `last_v1_ts`, `node_cache`, and `last_node`, and drops
`clock_seq_initialized`, so the next V1/V6/V7 call re-samples CSPRNG output.

```zig
const pid = try std.posix.fork();
if (pid == 0) {
    // Child process: clear stale CSPRNG-derived cache before generating UUIDs.
    my_generator.reseed();
    // ... child work ...
}
```

Applications using the package-level convenience functions (`uuid.newV4()`, `uuid.newV7()`,
...) operate on the shared `default_generator`; retrieve a pointer to it and call
`reseed()` on the returned `*Generator` in the child. Processes that never call
`fork()` can ignore this guidance.

### Dependency Security

The external `json` dependency is pinned to a specific git commit SHA and verified by the
Zig package manager's content hash (stored in `build.zig.zon`). The hash is verified at
build time; a compromised upstream repository cannot substitute different content without
changing the hash.

## Security Best Practices

When using this library:

1. Keep dependencies updated
2. Review security advisories regularly
3. Report any suspicious behavior
4. Follow secure coding guidelines

## Safe Harbor

<!-- TODO: legal review — the text below is derived from the
     https://disclose.io Core Terms template and has NOT been reviewed by
     counsel.  Until that review is complete, this section expresses the
     project's intent but does not waive any legal rights of the
     copyright holders or their successors in interest. -->

We welcome good-faith security research on this library.  Consistent with
the [disclose.io](https://disclose.io) core terms, if you make a good-faith
effort to comply with this policy during your security research, we will:

- **Not pursue or support any legal action against you** related to your
  research, including DMCA claims against technical research.
- **Work with you** to understand and resolve the issue quickly, and
  credit you as the reporter (unless you request anonymity).
- **Recognise your contribution** publicly in the release notes if you are
  the first to report a material issue that we act upon.

In turn, we ask that researchers:

- Make every reasonable effort to **avoid privacy violations, data
  destruction, and service disruption**.
- Only interact with systems and data that you own, or for which the
  owner has given explicit permission.
- Do not perform testing that could degrade service availability for
  other users (DDoS, fork-bomb, resource-exhaustion fuzzing on shared
  infrastructure).
- **Report findings promptly** via the contact channels in this document
  and give us a reasonable window (see the SLA table above) before any
  public disclosure.

This section will be replaced with a version that has been reviewed by
counsel once that review is available; the current text is informational
and aspirational.

## CVE Numbering Authority (CNA)

<!-- TODO: choose a CNA.  Options:
       - MITRE as Root CNA (default; covers open-source projects).
       - GitHub Security Advisories (auto-assigns when the project mirrors
         to GitHub and opts in to private vulnerability reporting).
       - GitLab Security Advisory Database (when hosted on GitLab.com).
       - Become a CNA ourselves (high bar; out of scope for a single
         library of this size).
     The choice determines where reporters should look up the assigned
     CVE ID after coordinated disclosure. -->

Until a CNA is formally chosen, CVE assignment for validated reports
against this library will be requested from **MITRE as the Root CNA**.
Reporters who require an early CVE reservation may also open a
simultaneous report against the CNA of the distribution channel they
encountered the library through (e.g. a downstream package ecosystem's
CNA).

This section will be updated once a permanent CNA is selected.

## Machine-Readable Metadata

A [RFC 9116](https://datatracker.ietf.org/doc/html/rfc9116) `security.txt`
file is published at [`/.well-known/security.txt`](.well-known/security.txt)
with the authoritative contact address, policy URL, expiry, and preferred
languages.  Automated discovery tools and security researchers are
encouraged to consume the machine-readable file; this document remains
the canonical long-form policy.

## Contact

For non-security issues, see [SUPPORT.md](SUPPORT.md).

## Acknowledgements

We thank the reporters listed below for responsible disclosure of
security issues. Submit a PR against this section to be added.

<!-- no public reporters yet -->
