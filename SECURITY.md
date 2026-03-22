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

## Contact

For non-security issues, see [SUPPORT.md](SUPPORT.md).
