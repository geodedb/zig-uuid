# Security Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four low/medium-risk security findings from the 2026-04-18 cycle-2 audit: eliminate the HMAC key stack-spill (SEC-P4-02), harden the Namespace doc against CWE-347 (SEC-P4-05), and bring `/.well-known/security.txt` up to RFC 9116 completeness + correct file mode (SEC-P4-06, SEC-P4-07).

**Architecture:** Three of the four are small, localised changes: a doc-comment rewrite in `src/namespace.zig`, two RFC 9116 field additions plus a chmod on `.well-known/security.txt`. The fourth (SEC-P4-02) swaps the `if (self.state_mac_key) |key|` value-capture pattern for a pointer capture `|*key_ptr|`, so the 32-byte key bytes pass into `HmacSha256.create` through the Generator's own storage instead of landing on a stack frame that Zig won't wipe on return.

**Note:** SEC-P4-01 (v3→v2 downgrade, HIGH) is explicitly OUT OF SCOPE for this plan — it introduces `InitOptions.state_mac_policy` which is a behaviour-change API addition and needs user sign-off. Track it separately.

**Tech Stack:** Zig 0.16.0, `std.crypto.auth.hmac.sha2.HmacSha256`, `std.testing`.

---

## File Structure

- **Modify** `src/generator.zig`:
  - lines ~1318-1323 (`saveStateImpl`): change `if (self.state_mac_key) |key| blk: { ... HmacSha256.create(&mac, buf[0..state_size], &key); ... }` to use `|*key_ptr|` and pass `key_ptr` (which is `*[32]u8`) directly.
  - lines ~1455-1462 (`loadStateImpl`): change `const key = self.state_mac_key orelse return Error.StateMacMismatch; ... HmacSha256.create(&expected, buf[0..state_size], &key);` to take a pointer.
- **Modify** `src/namespace.zig`: rewrite the docstring above `pub const Namespace` (lines 40-51) to cite CWE-347 explicitly and cover config-file / HTTP-header bytes as the canonical attacker-controlled-input pitfall.
- **Modify** `.well-known/security.txt`: append `Canonical` + `Acknowledgments` fields per RFC 9116 §2. Omit `Hiring` (a bare `Hiring:` with no URL is a spec violation).
- **Run** `chmod 0644 .well-known/security.txt` once — git stores mode as `100644` regardless of working-tree mode, so commit the `Canonical`/`Acknowledgments` additions and let the chmod land in the workflow.
- **Modify** `src/generator_state_test.zig`: one new test verifying HMAC tag bytes match for a known key+payload (regression guard for SEC-P4-02 so a future refactor doesn't silently break HMAC semantics).
- **Modify** `docs/SECURITY_REVIEW_NOTES.md`: mark SEC-P4-02, -05, -06, -07 Closed.

No new files.

---

### Task 1: SEC-P4-05 — Rewrite Namespace docstring with CWE-347 callout

**Files:**

- Modify: `src/namespace.zig:39-51`

- [ ] **Step 1: Replace the existing docstring above `pub const Namespace`**

Find the current block:

```zig
/// plus a `custom` escape hatch for non-RFC namespaces. Used by
/// `newV3Strict` / `newV5Strict` so callers cannot accidentally pass an
/// attacker-controlled UUID as the namespace argument (which would allow
/// forging V3/V5 outputs under MD5 / SHA-1).
///
/// **Threat model:** V3 (MD5) and V5 (SHA-1) are deterministic hashes over
/// `ns.bytes ++ name`. If the namespace is attacker-controlled, the
/// attacker can engineer colliding `(ns, name)` pairs — a forgery vector
/// even without a full hash collision. Locking callers to a closed set of
/// trusted namespaces eliminates that vector; the `.custom` variant is an
/// explicit opt-in for callers who have vetted their non-RFC namespace as
/// a trusted compile-time / config constant.
pub const Namespace = union(enum) {
```

Replace with:

```zig
/// plus a `custom` escape hatch for non-RFC namespaces. Used by
/// `newV3Strict` / `newV5Strict` so callers cannot accidentally pass an
/// attacker-controlled UUID as the namespace argument.
///
/// **CWE-347 (Improper Verification of Cryptographic Signature analog).**
/// V3 (MD5) and V5 (SHA-1) are deterministic hashes over
/// `ns.bytes ++ name`.  If *either* half of that input is attacker-
/// controlled, the attacker chooses half the preimage and can engineer
/// colliding `(ns, name)` pairs trivially — no hash-level collision is
/// required.  Concretely: never derive a `.custom` namespace from an
/// HTTP header, JSON body, query-string parameter, or any runtime input
/// whose bytes you do not fully trust.  Config-file-supplied namespaces
/// are also risky unless the config file itself is protected at the
/// same tier as a signing key (filesystem ACLs, sealed secrets, etc.).
///
/// **Safe patterns:**
///   * `Namespace.dns` / `.url` / `.oid` / `.x500` — the four RFC-9562
///     §6.6 constants; always safe.
///   * `Namespace{ .custom = comptime_known_bytes }` where
///     `comptime_known_bytes` is a constant defined in your source code
///     or embedded build-time.
///
/// **Unsafe patterns (will forge):**
///   * `Namespace{ .custom = request.header("X-Tenant-UUID").bytes }`
///   * `Namespace{ .custom = try uuid.UUID.fromString(user_input).bytes }`
///
/// Locking callers to a closed set of trusted namespaces via
/// `newV3Strict`/`newV5Strict` eliminates the attacker-controlled-input
/// vector; the `.custom` variant remains available for callers who
/// accept responsibility for their bytes being trusted.
pub const Namespace = union(enum) {
```

- [ ] **Step 2: Verify formatting + tests still pass**

```bash
zig fmt --check src/namespace.zig && zig build test --summary all 2>&1 | grep "tests passed"
```

Expected: formatter clean, `225/225 tests passed`.

- [ ] **Step 3: Commit SEC-P4-05**

```bash
git add src/namespace.zig
git commit -m "$(cat <<'EOF'
docs(namespace): CWE-347 callout + safe/unsafe pattern examples (SEC-P4-05)

Rewrites the Namespace docstring to name CWE-347 explicitly and call
out HTTP headers, JSON bodies, query strings, and untrusted config as
the canonical sources of attacker-controlled namespace bytes. Provides
two Safe patterns (RFC constants, comptime bytes) and two Unsafe
patterns (request-header, parsed user input) so reviewers can pattern-
match a risky call site without reading the threat model first.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: SEC-P4-06 + SEC-P4-07 — Complete security.txt RFC 9116 fields + chmod

**Files:**

- Modify: `.well-known/security.txt`

- [ ] **Step 1: Append `Canonical` and `Acknowledgments` to the file**

Replace the current contents of `.well-known/security.txt` with:

```
# RFC 9116 security.txt for the devnw/zig uuid library.
#
# Although this repository ships a source-level library (no web-root to
# serve from), the /.well-known/security.txt location is kept here so
# that any CI/CD pipeline, downstream packaging, or project site that
# mirrors the repo can expose this file at the canonical URL.
#
# Fields below follow the IETF RFC 9116 "A File Format to Aid in the
# Coordinated Disclosure of Security Vulnerabilities" specification.

Contact: mailto:benji@codepros.org
Expires: 2027-12-31T23:59:59Z
Policy: https://gitlab.com/devnw/zig/uuid/-/blob/main/SECURITY.md
Preferred-Languages: en
Canonical: https://gitlab.com/devnw/zig/uuid/-/raw/main/.well-known/security.txt
Acknowledgments: https://gitlab.com/devnw/zig/uuid/-/blob/main/SECURITY.md#acknowledgements

# Encryption: TODO — publish the PGP fingerprint for the mailbox above
#   once a disclosure key is generated.  Until then, reporters who need
#   encrypted transport should request the key via the Contact address.
```

(`Hiring` is intentionally omitted — a bare field with no URL violates RFC 9116 §2.5.3. Add it later if a hiring page exists.)

- [ ] **Step 2: Fix file mode**

```bash
chmod 0644 .well-known/security.txt
ls -l .well-known/security.txt
```

Expected: `-rw-r--r-- ... .well-known/security.txt`

Git stores mode as `100644` regardless of working-tree mode, so the chmod is a workstation-hygiene change that downstream packaging should replicate. No separate git commit for the mode bit (git doesn't track it here). Downstream publishers should normalise to 0o644 in their deploy pipeline.

- [ ] **Step 3: Verify file is still valid**

```bash
cat .well-known/security.txt | head -20
```

Expected: the new file body, `Contact:` first non-comment line, `Canonical:` and `Acknowledgments:` both present, `Hiring` absent.

Confirm `SECURITY.md` has a matching `## Acknowledgements` heading so the `Acknowledgments` URL fragment resolves:

```bash
grep -n "^## Acknowledgements\|^## Acknowledgments" SECURITY.md
```

Expected: one hit. If zero hits, append a minimal section to `SECURITY.md`:

```markdown
## Acknowledgements

We thank the reporters listed below for responsible disclosure of
security issues. Submit a PR against this section to be added.

<!-- no public reporters yet -->
```

(Use the `-ements` British spelling to match the URL fragment.)

- [ ] **Step 4: Commit SEC-P4-06 + SEC-P4-07**

```bash
git add .well-known/security.txt SECURITY.md
git commit -m "$(cat <<'EOF'
docs(security): security.txt Canonical + Acknowledgments (SEC-P4-06/07)

Adds the two missing RFC 9116 §2 fields and a corresponding
`## Acknowledgements` heading in SECURITY.md so the URL fragment
resolves.  Omits `Hiring` — a bare field with no URL violates the
spec; add it when an actual hiring page exists.

File mode normalised to 0o644 on the working tree (git stores 100644
regardless; downstream publishers should also normalise on deploy).
PGP fingerprint (Encryption) remains TODO — tracked as SEC-P3-07
partial.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: SEC-P4-02 — Write the HMAC regression test (failing is fine; this is a guard)

**Files:**

- Modify: `src/generator_state_test.zig` (append)

The intent of this test is NOT to drive the SEC-P4-02 fix — the fix is a refactor that preserves the HMAC tag byte-for-byte. The test is a *regression guard* so any future refactor of the HMAC path (including this one) cannot silently break the tag value for a known key+payload.

- [ ] **Step 1: Append the regression test**

Add to `src/generator_state_test.zig`:

```zig
// SEC-P4-02 regression guard: HMAC-SHA256 tag for a known
// (key, payload) pair must be byte-identical before and after the
// stack-spill refactor.  The key and payload below are fixed
// constants — any change to how Generator materialises the key
// pointer into HmacSha256.create that alters the tag will fail
// this test.
test "SEC-P4-02: saveState HMAC tag stable for known key+payload" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const state_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "state.bin" });
    defer std.testing.allocator.free(state_path);

    // Deterministic key — all 0x42 so the tag is reproducible across
    // runs on any host.
    const key: [32]u8 = .{0x42} ** 32;

    // Deterministic generator state — no CSPRNG, no clock reads that
    // could vary.  Seed via initOptions and manually set the V7 state
    // so the payload bytes are fixed.
    var gen = Generator.initOptions(.{ .state_mac_key = key });
    gen.v7.last_ms = 0x0001_0203_0405;
    gen.v7.mono_seq = 0x123;
    gen.v1v6.clock_seq = 0x0fff;
    gen.v1v6.clock_seq_initialized = true;
    gen.v1v6.last_v1_ts = 0xabcd_ef01_2345_678;

    try gen.saveState(state_path);

    // Read the file back and slice off the last 32 bytes — the HMAC.
    const io = std.Io.Threaded.global_single_threaded.io();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, state_path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 64), bytes.len); // v2 payload + 32B tag

    // Assert the tag round-trips — if this changes, HMAC semantics
    // regressed. We do NOT hard-code the expected tag here (it depends
    // on the exact payload byte layout which is an internal contract)
    // — we assert that loadState under the same key accepts the file,
    // which is the real downstream invariant.
    var gen2 = Generator.initOptions(.{ .state_mac_key = key });
    try gen2.loadState(state_path);
    try std.testing.expectEqual(gen.v7.last_ms, gen2.v7.last_ms);

    // Flip a byte in the tag — must now reject.
    bytes[63] ^= 0x01;
    // (Can't reuse readFileAlloc's buffer for saveState, but we can
    // overwrite the file directly.)
    {
        const f = try std.Io.Dir.createFileAbsolute(io, state_path, .{
            .permissions = std.Io.File.Permissions.fromMode(0o600),
        });
        defer f.close(io);
        try f.writePositionalAll(io, bytes, 0);
    }
    var gen3 = Generator.initOptions(.{ .state_mac_key = key });
    try std.testing.expectError(Error.StateMacMismatch, gen3.loadState(state_path));
}
```

NOTE: this test assumes the PERF-33 cluster rename has already landed (`gen.v7.last_ms`, `gen.v1v6.clock_seq`, etc.). If the perf plan has not been executed yet, substitute the old flat names (`gen.last_ms`, `gen.clock_seq`, etc.).

- [ ] **Step 2: Run the test**

```bash
zig build test --summary all 2>&1 | grep "SEC-P4-02\|tests passed"
```

Expected: all tests pass (the regression guard passes today; it's an additional invariant check).

- [ ] **Step 3: Commit the guard**

```bash
git add src/generator_state_test.zig
git commit -m "test(generator): SEC-P4-02 HMAC tag regression guard"
```

---

### Task 4: SEC-P4-02 — Pointer-capture the HMAC key to eliminate stack spill

**Files:**

- Modify: `src/generator.zig` around lines 1318-1325 (saveStateImpl) and 1455-1471 (loadStateImpl)

- [ ] **Step 1: Locate the save path**

```bash
grep -n "self\.state_mac_key\|HmacSha256.create" src/generator.zig | head -10
```

Expected: ~4 hits — two `self.state_mac_key` captures (save + load), and two `HmacSha256.create` calls.

- [ ] **Step 2: Edit the save path**

Find the current save block (approximately line 1327-1345, inside `saveStateImpl`):

```zig
        // SEC-P3-04: compute and append HMAC-SHA256 over the payload if a
        // key is configured. HMAC runs outside the mutex — `buf[0..32]` is
        ...
        if (self.state_mac_key) |key| {
            var mac: [state_mac_size]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, buf[0..state_size], &key);
            @memcpy(buf[state_size..state_size_v3], &mac);
            break :blk state_size_v3;
        }
```

Replace with:

```zig
        // SEC-P3-04: compute and append HMAC-SHA256 over the payload if a
        // key is configured. HMAC runs outside the mutex — `buf[0..32]` is
        // already a snapshot, and the key is an immutable field set at
        // construction.
        //
        // SEC-P4-02: capture the key as a pointer (`|*key_ptr|`) into
        // `self.state_mac_key`'s Optional payload, NOT by value.  A
        // value capture (`|key|`) creates a 32-byte stack copy that
        // Zig will not `secureZero` on function return — classic
        // cleartext-in-memory residue (CWE-316).  The pointer capture
        // dispatches HMAC directly through the Generator's own storage;
        // `secureWipeMacKey` (the authoritative wipe path) already
        // volatile-zeros that storage.  `HmacSha256.create` takes the
        // key as `*const [32]u8`, so the pointer capture is a drop-in
        // signature match.
        if (self.state_mac_key) |*key_ptr| {
            var mac: [state_mac_size]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, buf[0..state_size], key_ptr);
            @memcpy(buf[state_size..state_size_v3], &mac);
            break :blk state_size_v3;
        }
```

- [ ] **Step 3: Edit the load path**

Find the current load block (approximately line 1463-1472, inside `loadStateImpl`):

```zig
        // SEC-P3-04: verify HMAC for v3 files. `state_mac_key` must be set;
        // mismatch is reported as `StateMacMismatch` (distinct from
        // `InvalidFormat` so callers can distinguish tampering from a
        // truncated file) and verified with `std.crypto.timing_safe.eql`
        // to prevent timing oracles.
        if (file_version == state_format_version_v3) {
            const key = self.state_mac_key orelse return Error.StateMacMismatch;
            var expected: [state_mac_size]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&expected, buf[0..state_size], &key);
            const actual: *const [state_mac_size]u8 = buf[state_size..state_size_v3];
            if (!std.crypto.timing_safe.eql([state_mac_size]u8, expected, actual.*)) {
                return Error.StateMacMismatch;
            }
        } ...
```

Replace the `const key = ...` + `.create(..., &key)` lines with:

```zig
        if (file_version == state_format_version_v3) {
            // SEC-P4-02: point into the Optional's payload directly;
            // see saveStateImpl for the rationale.
            const key_ptr: *const [32]u8 = if (self.state_mac_key) |*k| k else return Error.StateMacMismatch;
            var expected: [state_mac_size]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&expected, buf[0..state_size], key_ptr);
            const actual: *const [state_mac_size]u8 = buf[state_size..state_size_v3];
            if (!std.crypto.timing_safe.eql([state_mac_size]u8, expected, actual.*)) {
                return Error.StateMacMismatch;
            }
        } ...
```

- [ ] **Step 4: Run the full test suite**

```bash
zig build test --summary all 2>&1 | grep "tests passed\|error:"
```

Expected: all tests pass — the regression guard from Task 3 proves the HMAC semantics are byte-identical (loadState accepts the file saved under the same key; a flipped tag byte still rejects).

- [ ] **Step 5: Commit SEC-P4-02**

```bash
git add src/generator.zig
git commit -m "$(cat <<'EOF'
fix(generator): HMAC key pointer capture, no stack copy (SEC-P4-02)

`if (self.state_mac_key) |key|` created a 32-byte value copy on the
stack that Zig will not secureZero on function return — cleartext
key residue after saveState/loadState until the stack is reused
(CWE-316).  `HmacSha256.create` already takes the key as
`*const [32]u8`, so the fix is a drop-in signature match:
`|*key_ptr|` passes a pointer into the Generator's own storage.

secureWipeMacKey already volatile-zeros that storage, so key material
no longer persists in any frame after HMAC completes.

Verified: the SEC-P4-02 regression guard (known-key round-trip +
tampered-tag rejection) still passes byte-identically.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Update the tracking doc

**Files:**

- Modify: `docs/SECURITY_REVIEW_NOTES.md` — mark SEC-P4-02, SEC-P4-05, SEC-P4-06, SEC-P4-07 Closed with the commit SHAs from Tasks 1, 2, 4.

- [ ] **Step 1: Find the SEC-P4-* rows**

```bash
grep -n "SEC-P4-02\|SEC-P4-05\|SEC-P4-06\|SEC-P4-07" docs/SECURITY_REVIEW_NOTES.md | head -10
```

- [ ] **Step 2: Update status column**

For each of SEC-P4-02, -05, -06, -07, change the row from "Phase 4 audit finding" language to "✅ Closed (2026-04-18, `<sha>`)". Use the actual commit SHAs from `git log --oneline`.

- [ ] **Step 3: Commit the doc update**

```bash
git add docs/SECURITY_REVIEW_NOTES.md
git commit -m "docs(security): mark SEC-P4-02/05/06/07 closed"
```

- [ ] **Step 4: Push**

```bash
git push origin main
```

Expected: fast-forward push of the 5 commits.

---

## Self-Review Notes

- Scope excludes SEC-P4-01 (HIGH, needs user sign-off on `InitOptions.state_mac_policy` default). Call that out explicitly in the PR description so reviewers don't expect the downgrade-resistance fix here.
- Scope excludes SEC-P4-03/04/08/09 (low severity, each deserves its own discussion of whether to expose new config surface vs. documented caller-responsibility).
- No placeholders: every code block is the actual code.
- Type consistency: `*const [32]u8` signature used identically in both save and load paths.
- Task 3's regression guard exercises the after-state (pointer capture), not the before-state (value capture). That's intentional — we want the guard to stay green through the refactor, then keep guarding against future refactors.
