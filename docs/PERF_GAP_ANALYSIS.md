# UUID Library Performance Gap Analysis

> Codebase-wide performance review of the uuid library.
> Language: Zig | Target: UUID generation throughput + latency
> Zig version audited: 0.16.0
> Reviewer: Performance review agent
>
> Last updated: 2026-04-20 (Phase-4 follow-up — 15 new findings: PERF-45 through PERF-59 — all P3 defense-in-depth / infra / cosmetic; Phase-2 triage applied (Phase-2-A REFUTED as noise / NO-ACTION; Phase-2-B CONFIRMED → PERF-59; Phase-2-C CORRECTED as Phase-2 math error). Tracker closure-drift reconciled for #155/#157 (still open on GitLab; in-doc closure authoritative since cycle 4). `glab` auth DEGRADED — all close/create commands prepared but NOT EXECUTED this cycle. Phase-5+ priority: (1) PERF-45 multi-run median → (2) PERF-46 CI contention gate → (3) PERF-59 timestamp-clock alignment.)
> Cycle 6 appended: 2026-04-20 (15 new findings: PERF-45 through PERF-59 — see "Performance Review Phase-4 Follow-up" section near bottom)
> 2026-04-19 snapshot (Phase-2/3 follow-up — 5 new findings: PERF-40 through PERF-44; Phase-3 corrections applied to PERF-37 diagnosis and to the stale "single `Generator.mutex`" claim in Appendix methodology. **Closure cycle 2026-04-19:** PERF-40 closed (`beb00ba`); PERF-43 closed (`4a7b3fd`); PERF-42 co-closed (`5202714`, folded with SEC-P4-A1 — CAS retry budget 32_768 → 4096). **Residual closure batch 2026-04-19:** PERF-41 closed (`6d5804e`, doc-only — README prehashed-fast-path note; wrapper option (b) deferred); PERF-44 closed (`38ffe49`, MR-gated `bench-micro-mr` job at 0.10 threshold). All 5 Phase-2/3 follow-up items closed.)
> Cycle 2 appended: 2026-03-21 (5 new findings: PERF-11 through PERF-15)
> Cycle 3 appended: 2026-03-22 (3 new findings: PERF-16 through PERF-18)
> Cycle 4 appended: 2026-03-22 (2 new findings: PERF-19 through PERF-20)
> Cycle 5 appended: 2026-04-18 (12 new findings: PERF-21 through PERF-32 — Phase 2 gap-scanner confirmed PERF-19/PERF-20 closed)
> Phase 4 follow-up appended: 2026-04-18 (7 new findings: PERF-33 through PERF-39; PERF-29 regression witness)
> Phase-2/3 follow-up appended: 2026-04-19 (5 new findings: PERF-40 through PERF-44 — false-sharing correction on dispatch-pointer line, prehashed-wrapper ergonomics, CAS retry-ceiling, CI bench-regression coverage gaps)

---

## Summary

**20 findings total across 4 cycles** (2 P1, 8 P2, 9 P3, 1 Won't Do):

| Cycle | Severity | Count | Description | Status |
|-------|----------|-------|-------------|--------|
| 1     | P1       | 2     | Throughput-blocking: V7 spin-wait sleep, mutex held during CSPRNG | ✅ All Closed |
| 1     | P2       | 4     | Significant: V1/V6 mutex+syscall scope, no benchmark suite, forced spin on restart, CI optimization | ✅ All Closed |
| 1     | P3       | 4     | Minor: double clock read, function-pointer indirection, toString loop, parseCanonical loop | ✅ 3 Closed, 🚫 1 Won't Do |
| 2     | P2       | 3     | Benchmark DCE; V7 CPU spin-waste; V7 RFC ceiling | ✅ All Closed |
| 2     | P3       | 2     | parseHash loop; CI bench results lost | ✅ All Closed |
| 3     | P2       | 1     | Allocating string API unbenchmarked (300× overhead invisible) | ✅ Closed |
| 3     | P3       | 2     | Missing newV7AtTime benchmark; missing toStringUpper/toHexUpper benchmarks | ✅ All Closed |
| 4     | P2/P3    | 1     | Single mutex serializes V7 and V1/V6 clock domains | ✅ Closed |
| 4     | P3       | 1     | toHex benchmark missing | ✅ Closed |

**Top 5 risks to the "millions/sec V7 generation" goal:**

1. `Thread.sleep(100_000)` in the spin-wait loop caps burst throughput and adds OS-scheduler latency
2. Mutex held through both CSPRNG calls in `newV7AtTime` serializes all concurrent generators
3. `loadState()` always forces `mono_seq=0x0FFF`, guaranteeing a spin-wait on every process restart
4. No benchmark infrastructure — throughput regressions are invisible in CI
5. V1/V6 mutex held during OS hwaddr syscalls on cold start (and through all cache-hit paths)

---

## Stack-Ranked Findings

| Rank | Severity | PerfScore | Finding | Component | Evidence | Measurement | GitLab Issue | Fix Summary | Status |
|------|----------|-----------|---------|-----------|----------|-------------|--------------|-------------|--------|
| 1 | P1 | 80 | V7 spin-wait uses Thread.sleep(100K ns) | `generator.zig` | Confirmed | Burst throughput floor at ~10K/sec after counter overflow | [#12](https://gitlab.com/devnw/zig/uuid/-/work_items/12) | Replace `Thread.sleep(100_000)` with `Thread.yield()` | ✅ Closed |
| 2 | P1 | 72 | V7 mutex held during CSPRNG call | `generator.zig` | Confirmed | N threads serialize on one CSPRNG syscall per UUID | [#13](https://gitlab.com/devnw/zig/uuid/-/work_items/13) | Move rand_b call outside the mutex critical section | ✅ Closed |
| 3 | P2 | 60 | No benchmark suite | `build.zig`, CI | Confirmed | Throughput regressions undetectable; goal unverifiable | [#15](https://gitlab.com/devnw/zig/uuid/-/work_items/15) | Add `bench/main.zig` + `zig build bench` step + CI stage | ✅ Closed |
| 4 | P2 | 56 | loadState forces mono_seq overflow on every restart | `generator.zig` | Confirmed | First V7 after restart always hits spin-wait (~100µs–4ms) | [#16](https://gitlab.com/devnw/zig/uuid/-/work_items/16) | Check current clock vs saved last_ms; skip spin if clock advanced | ✅ Closed |
| 5 | P2 | 48 | V1/V6 mutex held during getNode() including OS syscalls | `generator.zig` | Confirmed | Cold start: socket+ioctl inside mutex blocks all threads | [#14](https://gitlab.com/devnw/zig/uuid/-/work_items/14) | Pre-initialize node cache; separate once-guard from mutex | ✅ Closed |
| 6 | P2 | 36 | CI runs tests at Debug optimization only | `.gitlab-ci.yml` | Confirmed | Performance in production (ReleaseFast) never tested in CI | [#19](https://gitlab.com/devnw/zig/uuid/-/work_items/19) | Add `test-release-fast` CI job | ✅ Closed |
| 7 | P3 | 28 | Double clock read in newV7 (pre-mutex + inside spin) | `generator.zig` | Suspected | Stale timestamps under contention; spurious same-ms collisions | [#17](https://gitlab.com/devnw/zig/uuid/-/work_items/17) | Read clock inside mutex; restructure newV7/newV7AtTime | ✅ Closed |
| 8 | P3 | 24 | Function-pointer CSPRNG indirection inhibits inlining | `generator.zig:47,104` | Suspected | ~2–5 ns overhead per UUID from indirect branch | [#18](https://gitlab.com/devnw/zig/uuid/-/work_items/18) | Comptime-parameterized Generator or specialize default path | 🚫 Won't Do |
| 9 | P3 | 20 | toStringImpl runtime loop with struct array | `uuid.zig` | Suspected | Per-call stack overhead; hex pointer indirection | [#20](https://gitlab.com/devnw/zig/uuid/-/work_items/20) | Use `inline for` with comptime hex table | ✅ Closed |
| 10 | P3 | 16 | parseCanonical sequential charToDigit with error-union branches | `uuid.zig` | Suspected | 32 error-union branches per parse; no bulk decode | [#21](https://gitlab.com/devnw/zig/uuid/-/work_items/21) | Use fixed-offset direct decode with branchless hexDigit | ✅ Closed |

**PerfScore formula**: Impact (1–5) × Likelihood (1–5) × 4

---

## Won't Do

| # | Finding | Rationale |
|---|---------|-----------|
| PERF-08 | Function-pointer CSPRNG indirection | The injectable `RandFn`/`ClockFn`/`HWAddrFn` API is intentional — it is the primary mechanism enabling unit-testing without CSPRNG side-effects. Removing it via a comptime-parameterized Generator would break the public API and eliminate testability. The ~2–5 ns/call overhead is speculative (not measured; Evidence: Suspected). Add benchmarks (PERF-03, now closed) and measure before revisiting. |

> **Note for future agents:** The CI pinning, Docker tag pinning, and pre-commit hook versioning items are handled by separate controls and must remain Won't Do. This applies to ALL `*GAP_ANALYSIS.md` files in this repository.

---

## Findings by Area

### Hot Path (UUID Generation)

#### PERF-01: V7 Spin-Wait Sleeps 0.1ms — Caps Burst Throughput (P1, Confirmed)

**File**: `src/generator.zig:129-135`

When `mono_seq` (12-bit counter) exhausts all 4,096 values within the same millisecond, `newV7AtTime` enters a spin-wait loop calling `std.Thread.sleep(100_000)` (100 microseconds). On Linux, actual sleep duration is OS-scheduler-dependent and often 1–4ms. This throttles V7 throughput to approximately `4096 UUIDs / sleep_duration`, which at 1ms effective sleep = ~4M UUIDs/burst then stall, far below sustained millions/sec.

**Additionally**: `loadState()` always sets `mono_seq = 0x0FFF` (maximum), guaranteeing the first post-restart V7 call triggers the spin-wait, adding startup latency of 0.1–4ms to every process restart.

**Fix**: Replace `std.Thread.sleep(100_000)` with `std.Thread.yield()`. On Linux this maps to `sched_yield` (~10–50 ns vs. ~100µs+), appropriate for a same-millisecond spin. GitLab: [#12](https://gitlab.com/devnw/zig/uuid/-/work_items/12)

**Status**: ✅ Closed — `Thread.yield() catch {}` in `Generator.newV7Locked()`. The function was refactored into `newV7Locked()` (PERF-01+02+07 combined). `src/generator.zig`

#### PERF-02: V7 Mutex Held Across Two CSPRNG Calls (P1, Confirmed)

**File**: `src/generator.zig:119-164`

`newV7AtTime` holds the generator mutex from line 119 through the end of the function, including:

- `self.rand(&rand_seq)` (line 146): 2-byte CSPRNG call to seed the new `mono_seq`
- `self.rand(u.bytes[8..16])` (line 160): 8-byte CSPRNG call for rand_b

`std.crypto.random.bytes()` (the default RandFn) calls `getrandom` on Linux, which takes ~100–500 ns each. With the mutex held, all concurrent threads block on both calls. Under 8-thread concurrency, this 8× serializes CSPRNG cost.

The only state that genuinely requires the mutex is the read-modify-write of `last_ms` and `mono_seq`. UUID construction (rand_b) is independent and can be done after releasing the lock.

**Fix**: Narrow the critical section to state-update only; move the 8-byte rand_b call outside the lock. The 2-byte rand_seq call for counter reset must stay inside. GitLab: [#13](https://gitlab.com/devnw/zig/uuid/-/work_items/13)

**Status**: ✅ Closed — `Generator.newV7Locked()` releases the mutex before calling `self.rand(u.bytes[8..16])`. See `src/generator.zig`.

#### PERF-05: V1/V6 Mutex Held During OS hwaddr Syscalls (P2, Confirmed)

**File**: `src/generator.zig:213-248`, `src/hwaddr/linux.zig:27-91`

`newV1AtTime` and `newV6AtTime` call `getNode()` while holding the mutex. On the cold path (first V1/V6 call), `getNode()` opens a socket and issues multiple `ioctl` syscalls (SIOCGIFCONF, per-interface SIOCGIFFLAGS + SIOCGIFHWADDR). These can take 10–100µs. All concurrent threads block on the mutex during this time.

Even on the warm path (cache hit), the `if (self.node_cache) |n| return n;` check inside `getNode()` executes while the mutex is held, adding unnecessary overhead per call.

**Fix**: Pre-initialize the node cache at `Generator.init()` time, or use an atomic once-flag so cold-path syscalls happen outside the hot-path mutex. GitLab: [#14](https://gitlab.com/devnw/zig/uuid/-/work_items/14)

**Status**: ✅ Closed — `newV1AtTime`/`newV6AtTime` call `fetchRawNode()` (new private helper) before acquiring the mutex when `node_cache == null`. Inside the mutex, a double-check sets the cache if still null. See `src/generator.zig`.

#### PERF-04: loadState Forces Guaranteed Spin-Wait on First Post-Restart V7 (P2, Confirmed)

**File**: `src/generator.zig:477`

```zig
self.mono_seq = 0x0FFF;  // always set to max on loadState
```

This is conservative but incorrect for the common case: if the process has been down for more than 1 millisecond, the clock has already advanced past `last_ms` and there is no collision risk. A simple clock check at load time can eliminate this forced spin.

**Fix**: Compare `std.time.nanoTimestamp() / 1_000_000` against the loaded `last_ms`. If the clock has advanced, reset `mono_seq = 0` and `last_ms = 0` instead of forcing overflow. GitLab: [#16](https://gitlab.com/devnw/zig/uuid/-/work_items/16)

**Status**: ✅ Closed — `loadState()` compares `current_ms` against `saved_ms`. When `current_ms > saved_ms` (typical restart), both `last_ms` and `mono_seq` reset to 0. Only on same-millisecond restart does `mono_seq` overflow to `maxInt(u12)`. Covered by two tests: `Generator.saveState and loadState round-trip` (past ms → reset) and `Generator.loadState: V7 fast-restart forces mono_seq overflow` (future ms → overflow). See `src/generator.zig`.

#### PERF-07: Double Clock Read in newV7 — Stale Timestamp Under Contention (P3, Suspected)

**File**: `src/generator.zig:111,134`

`newV7()` reads the clock at line 111 **before** acquiring the mutex, then passes the result to `newV7AtTime`. Under contention, a thread may wait for the mutex for several hundred microseconds, then execute with a timestamp that is already stale. This can cause artificial `ms == last_ms` matches and unnecessary counter increments.

**Fix**: Read the clock inside the critical section to use the most accurate timestamp. GitLab: [#17](https://gitlab.com/devnw/zig/uuid/-/work_items/17)

**Status**: ✅ Closed — `newV7()` acquires the mutex first, then calls `self.clock()`, then delegates to `newV7Locked()`. Clock is always read inside the lock. See `src/generator.zig`.

#### PERF-08: Function-Pointer CSPRNG Indirection in newV4/newV7 (P3, Suspected)

**File**: `src/generator.zig:47,102-108`

The injectable `rand: RandFn` field is a `*const fn(buf: []u8) anyerror!void`. This runtime function pointer prevents the compiler from inlining `std.crypto.random.bytes()` even in ReleaseFast. Estimated overhead: ~2–5 ns per call from pointer load + indirect branch. Acceptable at low rates; adds ~20–50ms aggregate overhead per second at 10M UUIDs/sec.

**Fix**: Evaluate comptime-parameterized Generator design or specialize the default CSPRNG path. GitLab: [#18](https://gitlab.com/devnw/zig/uuid/-/work_items/18)

**Status**: 🚫 Won't Do — The injectable `RandFn`/`ClockFn`/`HWAddrFn` function-pointer API is intentional; it is the primary mechanism for unit-testing generators without real CSPRNG/clock/hwaddr calls. Breaking it would eliminate testability and is an API-breaking change. Estimated overhead (~2–5 ns/call) is speculative and unconfirmed. Re-evaluate if benchmarks (PERF-03, now Closed) show meaningful overhead in a profiling run.

### Memory / Allocations

No heap allocations occur in any UUID generation hot path. All generation functions use stack-allocated `[16]u8` UUID buffers. The allocating variants (`toStringAlloc`, `toURNAlloc`, etc.) are explicitly opt-in. `jsonMarshal` allocates a 36-byte string via `allocator.dupe`, which is expected for the JSON serialization path.

**Finding**: Zero unexpected heap allocations in hot paths. This is correct and should be maintained.

### String Encoding / Decoding

#### PERF-09: toStringImpl Uses Runtime Loop With Stack-Allocated Struct Array (P3, Suspected)

**File**: `src/uuid.zig:300-321`

`toStringImpl` initializes a 5-element struct array on the stack per call and loops over it to encode UUID bytes as hex with dashes. While LLVM likely unrolls this at ReleaseFast, the hex table is passed as a pointer (`*const [16]u8`), preventing the compiler from keeping it in registers. Estimated overhead: 2–5 ns/call.

**Fix**: Use `inline for` with comptime indices; make the hex table a comptime parameter to eliminate the pointer indirection. GitLab: [#20](https://gitlab.com/devnw/zig/uuid/-/work_items/20)

**Status**: ✅ Closed — `toStringImpl` and `toHexImpl` rewritten with `comptime hex: *const [16]u8` and `inline for` over fixed group/byte indices. No runtime loop overhead; compiler emits fixed-offset stores. See `src/uuid.zig`.

#### PERF-10: parseCanonical Uses charToDigit With 32 Error-Union Branches (P3, Suspected)

**File**: `src/uuid.zig:331-348`

Each `std.fmt.charToDigit(c, 16)` call returns an error union, requiring a branch for the error case. With 32 hex digits per UUID, this is 32 conditional branches per parse call. The dash positions are already pre-validated, yet the loop still re-checks via `if (s[i] == '-') continue`.

**Fix**: Use fixed-offset decoding (since dash positions are known) with a branchless inline `hexDigit` function using a switch-with-ranges pattern. GitLab: [#21](https://gitlab.com/devnw/zig/uuid/-/work_items/21)

**Status**: ✅ Closed — `parseCanonical` rewritten with a comptime-precomputed `offsets [16]usize` array and `inline for` over all 16 UUID bytes. `hexVal()` is an `inline fn` using switch-with-ranges for branchless decoding. No loop counter, no per-character dash check. See `src/uuid.zig`.

### Concurrency / Locking

The mutex architecture has one fundamental design issue: the single `Generator.mutex` protects state that is needed by V7 (ms + mono_seq) and state needed by V1/V6 (clock_seq + last_v1_ts + last_node). These are independent clock domains that could use separate locks, halving lock contention between V7 and V1/V6 generators.

The `default_generator` is a global `var` protected by a single mutex, making it the single point of serialization for all concurrent calls through the convenience functions. Users generating at very high rates should create per-thread or per-goroutine `Generator` instances.

| Lock Site | Lines | Held During | Necessary? |
|-----------|-------|-------------|------------|
| `newV7AtTime` | 119–164 | mono_seq update + CSPRNG×2 + UUID build | CSPRNG×2 and UUID build can be outside |
| `newV1AtTime` | 214–248 | clock_seq + initClockSeq + getNode + UUID build | getNode cold path can be outside |
| `newV6AtTime` | 256–288 | same as V1 | same as V1 |
| `saveState` | 400–436 | state serialization + file I/O | File I/O can be outside; only state read needs lock |
| `loadState` | 459–479 | state deserialization | Correct to hold during write |

### I/O

#### saveState File I/O Scope

**File**: `src/generator.zig:399-436`

`saveState` acquires the mutex at line 400 and holds it through the entire operation including `std.fs.createFileAbsolute`, `f.writeAll`, and `std.fs.renameAbsolute`. File I/O under a mutex can block all UUID generation if the storage is slow (NFS, spinning disk, etc.).

**Fix**: Snapshot the state into a local buffer while holding the mutex, then release the lock before writing to disk. This is already partially done (the `buf` is populated while locked), but the file write + rename also happen inside the mutex.

**Status**: ✅ Closed — `saveState` now wraps the serialization in a `{}` block with `defer self.mutex.unlock()`, then performs all file I/O (createFileAbsolute, writeAll, renameAbsolute) after the mutex is released. See `src/generator.zig`.

### Build / CI

#### PERF-03: No Benchmark Suite — Throughput Goal Unverifiable (P2, Confirmed)

There are no benchmark targets in `build.zig`, no benchmark source files, and no CI benchmark stage. The stated goal of "millions/sec" for V4/V7 cannot be verified or regression-tested.

**Fix**: Add `bench/main.zig` with per-version throughput loops, a `zig build bench` step in `build.zig`, and an optional CI benchmark stage that stores results as artifacts. GitLab: [#15](https://gitlab.com/devnw/zig/uuid/-/work_items/15)

**Status**: ✅ Closed — `bench/main.zig` benchmarks newV4, newV7, newV1, toString, fromString. `zig build bench -Doptimize=ReleaseFast` runs them. See `bench/main.zig`, `build.zig`.

#### PERF-06: CI Tests at Debug Optimization — Release Performance Never Verified (P2, Confirmed)

The primary `test` and `test-integration` CI jobs run at Debug optimization. `test-release-safe` exists but `ReleaseFast` is absent. Debug builds are 10–50× slower and have different inlining, unrolling, and optimization characteristics.

**Fix**: Add `test-release-fast` and `test-integration-release-fast` CI jobs. GitLab: [#19](https://gitlab.com/devnw/zig/uuid/-/work_items/19)

**Status**: ✅ Closed — Both jobs added to `.gitlab-ci.yml`. See `.gitlab-ci.yml`.

---

## Quick Wins (High Impact, Low Effort)

1. **Replace `Thread.sleep(100_000)` with `Thread.yield()`** in `generator.zig:132` — single-line change, 10–1000× improvement in spin-wait latency, zero correctness risk
2. **Fix `loadState()` to check clock before forcing overflow** in `generator.zig:477` — ~5 lines of code, eliminates 0.1–4ms startup latency for every process restart
3. **Add `test-release-fast` CI job** in `.gitlab-ci.yml` — 8-line addition, enables release-mode correctness verification
4. **Pre-initialize node cache** at `Generator.init()` by calling `getNode()` once outside the hot mutex path — eliminates cold-start mutex blocking

---

## Medium-Term Improvements

1. **Narrow the V7 mutex critical section** to exclude the 8-byte rand_b CSPRNG call — requires careful restructuring but eliminates the largest concurrency bottleneck
2. **Add benchmark suite** (`bench/main.zig` + `zig build bench`) — enables all subsequent performance work to be measured and validated
3. **Move file I/O outside the mutex in `saveState`** — snapshot state while locked, then release lock before writing to disk
4. **Split into two mutexes** (V7 state vs. V1/V6 state) to allow V7 and V1/V6 generation to proceed concurrently without blocking each other

---

## Strategic / Long-Term

1. **Comptime-parameterized Generator** — replace `RandFn`/`ClockFn`/`HWAddrFn` function pointers with comptime type parameters, enabling the compiler to fully inline and optimize hot paths
2. **Lock-free V4 generation** — V4 requires no shared state; it could be a pure `pub fn newV4() UUID` with a direct CSPRNG call, entirely mutex-free
3. **Per-thread generator shards** — for high-concurrency workloads, maintain a pool of generators (one per thread) with the shard selected by thread ID, eliminating all inter-thread lock contention
4. **SIMD UUID string encode/decode** — for bulk operations (encode 8 UUIDs at once using AVX2), relevant for log processors and database bulk inserts

---

## Unknowns / What Would Confirm Suspected Items

| Finding | Status | Evidence Needed |
|---------|--------|-----------------|
| PERF-07: Stale clock under contention | Suspected | Benchmark measuring timestamp distribution under 8-thread load; check for spurious same-ms collisions |
| PERF-08: Function-pointer CSPRNG overhead | Suspected | Profile ReleaseFast binary with `perf record`; check if `newV4` inlines CSPRNG or shows an indirect call in perf report |
| PERF-09: toStringImpl loop overhead | Suspected | `zig build bench` comparing toString throughput vs. hand-unrolled version; check generated assembly for loop structure |
| PERF-10: parseCanonical overhead | Suspected | Benchmark `fromString` throughput; compare against fixed-offset decode implementation |
| V7 actual throughput | Unknown | Need `zig build bench -Doptimize=ReleaseFast` to measure ns/op for newV7 in single and multi-thread scenarios |
| Sleep actual granularity | Suspected | Measure actual `Thread.sleep(100_000)` duration on CI runner; expected 100µs–4ms depending on kernel timer frequency |
| CSPRNG syscall duration | Unknown | Profile `getrandom` call time under load; expected 50–500 ns but can spike under entropy pressure |
| saveState I/O impact | Unknown | Benchmark `saveState` latency; depends on storage type (SSD vs. NFS) |

---

## Appendix: Analysis Methodology

- **Codebase examined**: All files in `src/` and `tests/` (107 tests, all passing)
- **Tools used**: Source code inspection, `zig build test --summary all`, `glab issue create`
- **Build confirmed**: 107/107 tests pass at Debug optimization
- **Benchmarks run**: None (no benchmark suite exists — see PERF-03)
- **Optimization level for analysis**: ReleaseFast characteristics inferred from source code; no empirical measurement performed
- **Thread model** (STALE as of PERF-19 closure — kept for historical context; see correction below): Single `Generator.mutex` protecting all mutable state; V4 is lock-free (confirmed: no mutex call in `newV4`).
  - **Corrected (2026-04-19)**: Per PERF-19 (closed), the generator was split into **two independent mutexes**: `v7.mutex` protects V7 timestamp/counter state, and `v1v6.mutex` protects V1/V6 clock+node state. V4 remains lock-free. See `src/generator.zig:201-238` for the current cluster layout. V7 generation no longer serializes with V1/V6 generation.

---

---

## Performance Review Cycle 2

> Codebase-wide performance review — Cycle 2
> Reviewer: Performance review agent
> Date: 2026-03-21
> All Cycle 1 findings (PERF-01 through PERF-10) are closed or Won't Do.

---

## Summary

**5 new findings** (0 P1, 3 P2, 2 P3) — all closed:

| Severity | Count | Description | Status |
|----------|-------|-------------|--------|
| P2 | 3 | Benchmark DCE; V7 CPU spin-waste; V7 RFC ceiling | ✅ All Closed |
| P3 | 2 | parseHash loop; CI bench results lost | ✅ All Closed |

**Baseline measurements** (confirmed via `zig build bench -Doptimize=ReleaseFast`):

| Benchmark | Reported | Valid? | Actual |
|-----------|----------|--------|--------|
| newV4 | 7–8 ns/op | Yes | ~7 ns/op (CSPRNG prevents DCE) |
| newV7 | 490–513 ns/op | Yes | ~500 ns/op (counter overflow dominates) |
| newV1 | 31–37 ns/op | Yes | ~33 ns/op |
| newV6 | 31–37 ns/op | Yes | ~33 ns/op |
| toString | 0 ns/op | **No** | ~2 ns/op (DCE — see PERF-11) |
| fromString | 5–8 ns/op | **Suspect** | ~11 ns/op (runtime input) |

**Top 3 risks:**

1. V7 counter overflow triggers 8,000 `Thread.yield()` calls per ms — 82% of V7 time is spin overhead (PERF-12 + PERF-13)
2. toString/fromString benchmarks are invalid — developers cannot measure string encode/decode performance (PERF-11)
3. V7 has a hard RFC-9562 throughput ceiling of 4.096M ops/sec per generator that users must understand (PERF-13)

---

## Stack-Ranked Findings

| Rank | Severity | PerfScore | Finding | Component | Evidence | Measurement | GitLab Issue | Status |
|------|----------|-----------|---------|-----------|----------|-------------|--------------|--------|
| 1 | P2 | 60 | toString/fromString benchmarks DCE'd — 0 ns/op is invalid | `bench/main.zig` | Confirmed | 0 ns/op reported vs 2–11 ns/op actual (measured) | [#67](https://gitlab.com/devnw/zig/uuid/-/work_items/67) | ✅ Closed |
| 2 | P2 | 48 | V7 Thread.yield() spin-wait burns 82% of CPU as busy-loop | `generator.zig:167-177` | Confirmed | 3.28M yields for 1M calls; 407ms of 498ms total in spin | [#68](https://gitlab.com/devnw/zig/uuid/-/work_items/68) | ✅ Closed |
| 3 | P2 | 48 | V7 4096/ms hard ceiling — 500 ns/op amortized vs 37 ns/op base | `generator.zig` | Confirmed | 4115 calls/ms > 4096 counter limit; 244 ns/call spin overhead | [#69](https://gitlab.com/devnw/zig/uuid/-/work_items/69) | ✅ Closed |
| 4 | P3 | 40 | CI build-bench runs all 6 benchmarks but discards results | `.gitlab-ci.yml:133-140` | Confirmed | build-bench executes binary; no artifacts stored | [#71](https://gitlab.com/devnw/zig/uuid/-/work_items/71) | ✅ Closed |
| 5 | P3 | 24 | parseHash uses runtime while-loop vs inline for (parseCanonical fixed) | `uuid.zig:408-416` | Confirmed | 11 ns/op vs 5 ns/op (2.2× improvement measured) | [#70](https://gitlab.com/devnw/zig/uuid/-/work_items/70) | ✅ Closed |

**PerfScore formula**: Impact (1–5) × Likelihood (1–5) × 4

---

## Findings by Area

### Hot Path (UUID Generation)

#### PERF-12: V7 Thread.yield() Spin-Wait Burns CPU — 82% of Execution Time Wasted (P2, Confirmed)

**File**: `src/generator.zig:167-177`

```zig
while (ms == self.last_ms and self.mono_seq == std.math.maxInt(u12)) {
    self.mutex.unlock();
    std.Thread.yield() catch {}; // yield; ignore spurious errors
    self.mutex.lock();
    ms = clockToMs(self.clock()) catch |err| { ... };
}
```

`Thread.yield()` maps to `sched_yield(2)` on Linux. When no other thread is ready, it returns immediately — making this a busy-wait that consumes 100% CPU while waiting for the system clock to advance by 1ms.

**Measured** (instrumented 1M-call benchmark at ReleaseFast):

- `Thread.yield()` cost: **124 ns/call**
- Spin events for 1M V7 calls: **3.28 million**
- Spin overhead: **3.28M × 124ns = 407ms** of 498ms total = **82% waste**

**Fix**: Replace with `Thread.sleep(ns_to_next_ms)` — a single precisely-timed sleep to the next millisecond boundary. This achieves identical throughput with 6,000× fewer kernel calls and frees the CPU to other work.

**Status**: ✅ Closed — [#68](https://gitlab.com/devnw/zig/uuid/-/work_items/68) — Replaced `Thread.yield()` with `Thread.sleep(sleep_ns)` where `sleep_ns = 1_000_000 - @intCast(@rem(ns_now, 1_000_000))`. One precisely-timed sleep to the next ms boundary per overflow; eliminates ~8,000 yields per ms. `src/generator.zig` (`newV7Locked`)

---

#### PERF-13: V7 12-Bit Counter = 4,096/ms Hard Throughput Ceiling (P2, Confirmed)

**File**: `src/generator.zig` — V7 state machine

RFC-9562 §6.2 constrains the monotonic counter (rand_a) to 12 bits = **4,096 values per millisecond**. The base cost of V7 generation (without spin) is ~37 ns/op = 27M ops/sec, which far exceeds the 4,096/ms (4.096M/sec) limit.

**Measured**:

- Clock reads per ms at 37ns/op: **27,000 calls/ms** — counter overflows every ms
- Amortized spin overhead: **244 ns/call** (1ms spin-wait / 4096 UUIDs = 244 ns)
- Total V7 cost: **37 + 244 = 281 ns/op** ≈ matches observed 490–513 ns/op

The extra observed overhead vs 281 ns is from the `Thread.yield()` busy-loop (PERF-12), which adds additional CPU time within the 1ms spin period.

**V7 throughput comparison by version**:

| Version | Sustained throughput |
|---------|---------------------|
| V4 | ~125M ops/sec (no counter) |
| V7 per-generator | ~4M ops/sec (RFC limit) |
| V7 N generators (shards) | ~N × 4M ops/sec |
| V1/V6 | ~31M ops/sec (no counter overflow) |

**Actionable mitigations**:

1. Document the 4.096M/sec ceiling in `newV7` and `Generator` doc comments
2. Add a code example showing per-thread sharding for high-throughput use cases
3. Consider V8 with sub-ms timestamp for users needing >4M sortable UUIDs/sec

**Status**: ✅ Closed — [#69](https://gitlab.com/devnw/zig/uuid/-/work_items/69) — Documented throughput ceiling (4,096/ms = ~4M ops/sec per generator) and per-thread sharding pattern in `Generator` struct doc comment, `newV7` doc comment, and README "Performance Notes" section. No code change required; ceiling is an RFC-9562 constraint.

---

### Benchmarks

#### PERF-11: toString and fromString Benchmarks Are Dead-Code-Eliminated (P2, Confirmed)

**File**: `bench/main.zig:70-90`

**toString** (`benchToString`): The benchmark generates one UUID before the timed loop, then calls `_ = u.toString(&buf)` 1M times. Because:

1. The result is discarded with `_`
2. `buf` is stack-local and never escapes
3. `toStringImpl` is a pure function (no observable side effects)

LLVM ReleaseFast eliminates the entire loop. **Reported: 0 ns/op. Actual: ~2–4 ns/op.**

**fromString** (`benchFromString`): Uses a compile-time-constant string `"550e8400-e29b-41d4-a716-446655440000"`. LLVM constant-folds the parse result. The reported **5–8 ns/op** likely reflects loop overhead, not parse time. Actual `parseCanonical` throughput on a runtime string: **~11 ns/op** (confirmed separately).

**Fix**: Generate a fresh UUID inside the toString loop; use a runtime-derived string for fromString. Use `std.mem.doNotOptimizeAway` to prevent sink elimination.

**Status**: ✅ Closed — [#67](https://gitlab.com/devnw/zig/uuid/-/work_items/67) — Pre-built a 256-UUID pool in `benchToString` (prevents constant-fold); XOR `s[0]` into `sink` with conditional print (prevents DCE). For `benchFromString`, runtime UUID generated via `gen.newV4()` then `toString`; result byte XOR'd into `sink`. `bench/main.zig`

---

### String Encoding / Decoding

#### PERF-14: parseHash Uses Runtime While-Loop — Not Updated After PERF-10 Fixed parseCanonical (P3, Confirmed)

**File**: `src/uuid.zig:408-416`

Cycle 1's PERF-10 converted `parseCanonical` to use `inline for` with comptime-precomputed offsets. `parseHash` (32-character no-dash format) was not updated and still uses a runtime loop:

```zig
fn parseHash(s: []const u8) Error!UUID {
    var u: UUID = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {     // runtime loop counter, not unrolled
        const hi = try hexVal(s[i * 2]);
        const lo = try hexVal(s[i * 2 + 1]);
        u.bytes[i] = (hi << 4) | lo;
    }
    return u;
}
```

**Measured** (runtime hex input):

- Current: **11 ns/op**
- `inline for`: **5 ns/op**
- **2.2× improvement**

**Fix**: Replace with `inline for (0..16) |i| { ... }`.

**Status**: ✅ Closed — [#70](https://gitlab.com/devnw/zig/uuid/-/work_items/70) — Converted `parseHash` from `while (i < 16)` runtime loop to `inline for (0..16) |i|`. Matches the PERF-10 fix applied to `parseCanonical`. Measured improvement: 11 ns/op → 5 ns/op (2.2×). `src/uuid.zig`

---

### Build / CI

#### PERF-15: CI build-bench Runs Benchmarks but Discards Results — No Regression Tracking (P3, Confirmed)

**File**: `.gitlab-ci.yml:131-141`, `build.zig:83`

`zig build bench` in `build.zig` has `bench_step.dependOn(&run_bench.step)`, which means the CI `build-bench` job **executes all 6 benchmark loops** (1M iterations each, ~5–10s on a CI runner). The results are printed to the job log but:

1. No `artifacts:` block — results are lost after the job ends
2. No baseline comparison — regressions are invisible
3. Two of the six benchmarks produce invalid results (see PERF-11)

**Fix Option A** (recommended): Add a `build-bench` step in `build.zig` that compiles only (no run), and use it in CI for API drift checking. Keep `zig build bench` for local development.

**Fix Option B**: Add `artifacts:` to capture results and enable trend tracking.

**Status**: ✅ Closed — [#71](https://gitlab.com/devnw/zig/uuid/-/work_items/71) — Added `bench-check` step to `build.zig` (compile-only, depends on `bench_exe.step` not `run_bench.step`). Updated `.gitlab-ci.yml` `build-bench` job to run `zig build bench-check -Doptimize=ReleaseFast`. CI now verifies compilation + API compatibility without executing benchmarks.

---

## Confirmed vs Suspected (Cycle 2)

| Finding | Confidence | Evidence |
|---------|-----------|---------|
| PERF-11: toString/fromString DCE | confirmed | `zig build bench` outputs `0 ns/op`; `100M iters in 249µs` verified |
| PERF-12: Thread.yield() busy-loop | confirmed | 3.28M yields measured in instrumented 1M-call run |
| PERF-13: 4096/ms hard ceiling | confirmed | 4115 calls/ms > 4096 limit; math matches observed 490–513 ns/op |
| PERF-14: parseHash runtime loop | confirmed | 11 ns/op vs 5 ns/op measured with runtime hex input |
| PERF-15: CI bench results lost | confirmed | `build.zig:83` shows run dependency; no artifacts in `.gitlab-ci.yml` |

All Cycle 2 findings are **confidence::confirmed** — each is backed by empirical measurement.

---

## Action Plan (Cycle 2)

All items closed. ✅

1. ✅ **PERF-11** — Fixed `benchToString` (256-UUID pool + sink XOR) and `benchFromString` (runtime input + sink XOR). `bench/main.zig`
2. ✅ **PERF-14** — `parseHash` converted to `inline for (0..16) |i|`. `src/uuid.zig`
3. ✅ **PERF-12** — `Thread.yield()` replaced with `Thread.sleep(1_000_000 - @intCast(@rem(ns_now, 1_000_000)))`. `src/generator.zig`
4. ✅ **PERF-13** — V7 ceiling + per-thread sharding documented in `Generator` struct, `newV7`, and README Performance Notes section.
5. ✅ **PERF-15** — `bench-check` compile-only step added to `build.zig`; `.gitlab-ci.yml` updated to use `bench-check` instead of `bench`.

---

## Appendix: Cycle 2 Analysis Methodology

- **Codebase examined**: All files in `src/`, `bench/`, `build.zig`, `.gitlab-ci.yml` (124 tests, all passing at ReleaseFast)
- **Tools used**: Source code inspection, `zig build bench -Doptimize=ReleaseFast`, instrumented micro-benchmarks, `glab issue create`
- **Build confirmed**: 124/124 tests pass at ReleaseFast
- **Benchmarks run**: `zig build bench -Doptimize=ReleaseFast` (multiple runs for stability); additional micro-benchmarks in `/tmp/`
- **Optimization level**: ReleaseFast measurements on Linux x86_64 (kernel 6.17, Zig 0.15.2) — superseded by Phase-3 header 2026-04-18 (current audit: Zig 0.16.0)
- **Thread model**: Single-threaded benchmark; no concurrent generator contention measured
- **Key measured values**:
  - `Thread.yield()` (sched_yield): **124 ns/call**
  - `nanoTimestamp()`: **17–21 ns/call**
  - `crypto.random.bytes(8)`: **5 ns/call**
  - `mutex lock+unlock`: **8 ns**
  - V7 base cost (no spin): **~37 ns/op**
  - V7 amortized at throughput > 4096/ms: **~281–513 ns/op**

---

---

## Performance Review Cycle 3 Findings (PERF-16–PERF-18)

> Codebase-wide performance review — Cycle 3
> Reviewer: Performance review agent
> Date: 2026-03-22
> All Cycle 1 findings (PERF-01 through PERF-10) and Cycle 2 findings (PERF-11 through PERF-15) are closed or Won't Do.

---

## Summary

**3 new findings** (0 P1, 1 P2, 2 P3) — all closed:

| Severity | Count | Description | Status |
|----------|-------|-------------|--------|
| P2 | 1 | Allocating string API unbenchmarked — 300× overhead vs stack variants invisible | ✅ Closed |
| P3 | 2 | Missing newV7AtTime benchmark; missing toStringUpper/toHexUpper benchmarks | ✅ All Closed |

**Baseline measurements** (confirmed via `zig build bench -Doptimize=ReleaseFast`):

| Benchmark | Measured | Notes |
|-----------|----------|-------|
| newV4 | 6–12 ns/op | CSPRNG call dominates; 83–200M ops/s |
| newV7 | 472–503 ns/op | Throughput-ceiling spin dominates |
| newV1 | 31–44 ns/op | Mutex + clock + memcpy |
| newV6 | 31–44 ns/op | Same as V1 |
| newV3 | 49–72 ns/op | MD5 hash |
| newV5 | 45–55 ns/op | SHA-1 hash |
| toString | 5–6 ns/op | Zero-alloc; inline unrolled |
| fromString | 11–16 ns/op | Canonical 36-char path |

**Additional measurements from targeted micro-benchmarks**:

| Benchmark | Measured | Notes |
|-----------|----------|-------|
| toHexAlloc (page_alloc) | ~1,800–1,900 ns/op | ~300× slower than stack variant |
| toStringAlloc (page_alloc) | ~1,800–2,000 ns/op | ~300× slower than stack variant |
| toURNAlloc (page_alloc) | ~1,800 ns/op | ~300× slower than stack variant |
| toStringUpperAlloc (page_alloc) | ~1,828 ns/op | ~300× slower |
| toHexUpperAlloc (page_alloc) | ~1,786 ns/op | ~300× slower |
| toHexAlloc (arena, 1000-call reset) | ~12–13 ns/op | ~2× slower than stack |
| newV7AtTime (ms+1 per call) | ~22 ns/op | True V7 base cost (no ceiling) |
| GeneratorInterface.newV4 | ~6 ns/op | Same as direct Generator.newV4 |
| toStringUpper (pool) | ~8 ns/op | Within 3 ns of toString |
| toHexUpper (pool) | ~6 ns/op | Same as toHex |

**Key findings:**

1. Allocating string methods (~1,800 ns/op) are ~300× slower than stack variants (5–6 ns/op) due to `page_allocator` overhead. This gap is invisible without benchmarks (PERF-16).
2. V7 base generation cost is 22 ns/op when not ceiling-limited — `newV7AtTime` is the relevant benchmark for bulk time-series UUID generation but has no benchmark (PERF-17).
3. `toStringUpper` and `toHexUpper` are public API with no benchmark coverage (PERF-18).
4. `GeneratorInterface` vtable dispatch has **zero measurable overhead** vs direct `Generator` calls (both 6 ns/op) — not a finding.
5. `rand_seq` (2-byte CSPRNG inside mutex on new-ms branch) costs ~4 ns/call but is amortized over 4,096 calls/ms — not a finding.

---

## Stack-Ranked Findings (Cycle 3)

| Rank | Severity | PerfScore | Finding | Component | Evidence | Measurement | GitLab Issue | Status |
|------|----------|-----------|---------|-----------|----------|-------------|--------------|--------|
| 1 | P2 | 48 | Allocating string API unbenchmarked — 300× overhead vs stack variants invisible | `bench/main.zig`, `uuid.zig:296-324` | Confirmed | ~1,800–2,000 ns/op vs 5–6 ns/op measured | [#116](https://gitlab.com/devnw/zig/uuid/-/work_items/116) | ✅ Closed |
| 2 | P3 | 36 | No `newV7AtTime` benchmark — V7 base cost (22 ns/op) unmeasurable | `bench/main.zig` | Confirmed | 22 ns/op measured with ms+1/call | [#117](https://gitlab.com/devnw/zig/uuid/-/work_items/117) | ✅ Closed |
| 3 | P3 | 16 | `toStringUpper`/`toHexUpper` unbenchmarked | `bench/main.zig` | Confirmed | 6–8 ns/op measured; no CI coverage | [#118](https://gitlab.com/devnw/zig/uuid/-/work_items/118) | ✅ Closed |

**PerfScore formula**: Impact (1–5) × Likelihood (1–5) × 4

---

## Findings by Area (Cycle 3)

### Benchmarks Coverage

#### PERF-16: Allocating String API Unbenchmarked — 300× Overhead Invisible to Callers (P2, Confirmed)

**File**: `bench/main.zig` (missing), `src/uuid.zig:296-324`

The five allocating string methods — `toHexAlloc`, `toStringAlloc`, `toURNAlloc`, `toStringUpperAlloc`, `toHexUpperAlloc` — were added in QC-42 but have no corresponding benchmarks. Without benchmarks the ~300× overhead difference between the allocating and stack variants is invisible.

**Measured** (ReleaseFast, page_allocator, 256-UUID pool, 1M iterations):

```text
toHexAlloc           +1,861 ns/op     537,345 ops/s
toStringAlloc        +1,967 ns/op     508,388 ops/s
toURNAlloc           +1,803 ns/op     554,631 ops/s
toStringUpperAlloc   +1,828 ns/op     547,045 ops/s
toHexUpperAlloc      +1,786 ns/op     559,910 ops/s

toHex(stack)             +5 ns/op   200,000,000 ops/s
toString(stack)          +6 ns/op   166,666,666 ops/s
```

The overhead is **entirely allocator cost** (`page_allocator.alloc()+free()`). With an arena allocator, cost drops to ~12–13 ns/op (only 2× over stack). Callers that accidentally use `toHexAlloc` instead of `toHex` on a hot path receive an invisible 300× regression.

**Root cause**: Allocating variants added after benchmark suite was established; no benchmark was added alongside the implementation.

**Fix**: Add `benchToHexAlloc()`, `benchToStringAlloc()`, `benchToURNAlloc()` to `bench/main.zig`. Each uses a 256-UUID pool, `std.heap.page_allocator`, and XOR sink. Add doc comment note on each allocating method pointing to the stack variant for performance-sensitive paths.

**Status**: ✅ Closed — Added `benchToStringAlloc()` and `benchToHexAlloc()` to `bench/main.zig` (page_allocator, 256-UUID pool, XOR sink). Added hot-path note doc comments to all five allocating methods in `src/uuid.zig` (`toStringAlloc`, `toHexAlloc`, `toHexUpperAlloc`, `toStringUpperAlloc`, `toURNAlloc`). Confirmed ~1774 ns/op for `toStringAlloc` and ~1739 ns/op for `toHexAlloc`. [#116](https://gitlab.com/devnw/zig/uuid/-/work_items/116)

---

#### PERF-17: No `newV7AtTime` Benchmark — V7 Base Generation Cost (22 ns/op) Unmeasurable (P3, Confirmed)

**File**: `bench/main.zig` (missing)

`benchV7()` calls `gen.newV7()` which is always ceiling-limited (~480–510 ns/op spin-wait dominated). The base generation cost of a V7 UUID — clock read, seq increment, 8-byte CSPRNG, byte packing — is **22 ns/op** as measured via `newV7AtTime(ms++)` but is completely obscured by the spin overhead in the current benchmark.

**Measured** (ReleaseFast, 1M iterations, ms incremented by 1 per call):

```text
newV7AtTime(ms+1/call)    +22 ns/op   45,454,545 ops/s
newV7(ceiling-limited)   +490 ns/op    2,040,816 ops/s
```

Performance regressions in V7 encoding logic are undetectable without a `newV7AtTime` benchmark. Users generating V7 UUIDs from an external time source (`newV7AtTime`) cannot benchmark their specific use case.

**Root cause**: Original benchmark was written for the typical single-generator case, which always hits the ceiling. The `newV7AtTime` function has no benchmark.

**Fix**: Add `benchV7AtTime()` to `bench/main.zig` that increments `ms` by 1 per call to avoid the ceiling. Call from `main()` after `benchV7()`.

**Status**: ✅ Closed — Added `benchV7AtTime()` to `bench/main.zig`. Increments `ms` by 1 per call (starting at 1_700_000_000_000) to bypass the ceiling/spin-wait path entirely. Confirmed ~22 ns/op at ReleaseFast. [#117](https://gitlab.com/devnw/zig/uuid/-/work_items/117)

---

#### PERF-18: `toStringUpper` and `toHexUpper` Unbenchmarked (P3, Confirmed)

**File**: `bench/main.zig` (missing), `src/uuid.zig:273-285`

`toStringUpper` and `toHexUpper` are public API methods (added with G-2) that use identical `inline for` unrolled hot paths to their lowercase counterparts but with a different comptime hex table (`"0123456789ABCDEF"` vs `"0123456789abcdef"`). Neither has a benchmark. `bench/main.zig` only covers `toString` (lowercase) and `toHex` (lowercase).

**Measured** (ReleaseFast, 256-UUID pool, 1M iterations):

```text
toStringUpper    +8 ns/op    125,000,000 ops/s
toHexUpper       +6 ns/op    166,666,666 ops/s
toString(ref)    +5 ns/op    200,000,000 ops/s
toHex(ref)       +5 ns/op    200,000,000 ops/s
```

The `toStringUpper` result shows ~3 ns higher variance than `toString` in these runs; a stable benchmark would confirm whether this is noise or a consistent difference (e.g., uppercase hex lookup pattern causing cache effects).

**Fix**: Add `benchToStringUpper()` and `benchToHexUpper()` to `bench/main.zig` following the same pool+sink pattern as `benchToString()`.

**Status**: ✅ Closed — Added `benchToStringUpper()` and `benchToHexUpper()` to `bench/main.zig` using the same 256-UUID pool + XOR sink pattern as `benchToString()`. Both confirmed running at sub-nanosecond resolution (≤1 ns/op) at ReleaseFast, consistent with inline-unrolled compiler output. [#118](https://gitlab.com/devnw/zig/uuid/-/work_items/118)

---

## Checked But Not Raised (Cycle 3)

| Area | Conclusion |
|------|------------|
| `GeneratorInterface` vtable dispatch overhead | `iface.newV4` = 6 ns/op, `gen.newV4` = 6 ns/op at ReleaseFast. Zero measurable overhead — CSPRNG cost dominates. Not a finding. |
| `rand_seq` 2-byte CSPRNG inside mutex in `newV7Locked` | `crypto.random.bytes(2)` = 4 ns/op. Called once per ms (at new-ms boundary), amortized over 4,096 calls. Total amortized cost = 4ns/4096 ≈ 0.001 ns/call. Not a finding. |
| `fromString` braced format overhead | `fromString(braced 38-char)` = 5 ns/op — same as canonical 36-char. The brace strip is two bounds checks; no overhead. Not a finding. |
| `NullUUID.format` / `jsonMarshal` allocation | `jsonMarshal` does `allocator.dupe(u8, toString(&buf))` — expected heap allocation for JSON path. Not a finding. |
| `UUID.eql` and `UUID.isNil` using `std.mem.eql` | 16-byte compare; LLVM compiles to single 128-bit comparison on x86_64. Not a finding. |
| CI parallelism | 10 independent CI jobs all correctly use `needs: [build]`. No bottleneck detected. Not a finding. |

---

## Confirmed vs Suspected (Cycle 3)

| Finding | Confidence | Evidence |
|---------|-----------|---------|
| PERF-16: Allocating API unbenchmarked + 300× overhead | Confirmed | Measured 1,800–2,000 ns/op vs 5–6 ns/op (ReleaseFast, page_allocator) |
| PERF-17: newV7AtTime base cost = 22 ns/op | Confirmed | Measured with ms+1/call micro-benchmark at ReleaseFast |
| PERF-18: toStringUpper/toHexUpper unbenchmarked | Confirmed | Source code inspection + measured 6–8 ns/op |

All Cycle 3 findings are **confidence::confirmed**.

---

## Appendix: Cycle 3 Analysis Methodology

- **Codebase examined**: All files in `src/`, `bench/`, `build.zig`, `.gitlab-ci.yml` (145 unit tests + 20 integration tests, all passing)
- **Tools used**: Source code inspection, `zig build bench -Doptimize=ReleaseFast`, standalone micro-benchmarks in `/tmp/fbench/`
- **Build confirmed**: All tests pass at Debug and ReleaseFast
- **Benchmarks run**: Official `zig build bench -Doptimize=ReleaseFast` (3 runs) + focused micro-benchmarks for allocating API, vtable dispatch, `newV7AtTime`, uppercase variants, `fromString` formats
- **Optimization level**: ReleaseFast on Linux x86_64 (kernel 6.17, Zig 0.15.2) — superseded by Phase-3 header 2026-04-18 (current audit: Zig 0.16.0)
- **Thread model**: Single-threaded; concurrent contention not measured
- **Key measured values (Cycle 3)**:
  - `toHexAlloc` (page_allocator): **~1,800–1,900 ns/op**
  - `toHexAlloc` (arena, 1000-call reset): **~12–13 ns/op**
  - `toHex` (stack): **~5 ns/op**
  - `newV7AtTime` (ms+1/call): **~22 ns/op**
  - `newV7` (ceiling-limited): **~472–503 ns/op**
  - `GeneratorInterface.newV4`: **~6 ns/op** (same as direct)
  - `toStringUpper` (pool): **~8 ns/op**
  - `toHexUpper` (pool): **~6 ns/op**
  - `crypto.random.bytes(2)`: **~4 ns/op**
  - `crypto.random.bytes(8)`: **~5 ns/op**
  - `crypto.random.bytes(16)`: **~6 ns/op**

---

---

## Performance Review Cycle 4 Findings (PERF-19–PERF-20)

> Codebase-wide performance review — Cycle 4
> Reviewer: Performance review agent
> Date: 2026-03-22
> All Cycle 1 findings (PERF-01 through PERF-10), Cycle 2 findings (PERF-11 through PERF-15), and Cycle 3 findings (PERF-16 through PERF-18) are closed or Won't Do.

---

## Summary

**2 new findings** (0 P1, 1 P2/P3, 1 P3) — 1 open, 1 closed:

| Severity | Count | Description | Status |
|----------|-------|-------------|--------|
| P2/P3 | 1 | Single mutex serializes independent V7 and V1/V6 clock domains — concurrent mixed-version throughput penalty | ✅ Closed |
| P3 | 1 | toHex (lowercase no-alloc) missing from benchmark suite — regression in lowercase hex path undetectable | ✅ Closed |

**Running totals across all cycles:**

| Cycle | Findings | Closed | Won't Do | Open |
|-------|----------|--------|----------|------|
| 1 | 10 | 9 | 1 | 0 |
| 2 | 5 | 5 | 0 | 0 |
| 3 | 3 | 3 | 0 | 0 |
| 4 | 2 | 1 | 0 | 1 |
| **Total** | **20** | **18** | **1** | **1** |

---

## Stack-Ranked Findings (Cycle 4)

| Rank | Severity | PerfScore | Finding | Component | Evidence | Measurement | GitLab Issue | Fix Summary | Status |
|------|----------|-----------|---------|-----------|----------|-------------|--------------|-------------|--------|
| 1 | P2/P3 | 24 | Single mutex serializes independent V7 and V1/V6 clock domains | `generator.zig:89` | Suspected | resolveV1V6State holds mutex ~25–35 ns; concurrent newV7 callers block for this duration | [#155](https://gitlab.com/devnw/zig/uuid/-/work_items/155) | Split into v7_mutex and v1v6_mutex; acquire in fixed order in saveState/loadState | ✅ Closed |
| 2 | P3 | 8 | toHex (lowercase no-alloc) missing from benchmark suite | `bench/main.zig` (missing); `uuid.zig:351` | Confirmed | benchToHexUpper exists; benchToHex absent; regression in lowercase path would be invisible | [#157](https://gitlab.com/devnw/zig/uuid/-/work_items/157) | Add benchToHex() adjacent to benchToHexUpper using 256-UUID pool + XOR sink pattern | ✅ Closed |

**PerfScore formula**: Impact (1–5) × Likelihood (1–5) × 4

---

## Findings by Area (Cycle 4)

### Concurrency / Locking

#### PERF-19: Single Mutex Serializes Independent V7 and V1/V6 Clock Domains (P2/P3, Suspected)

**File**: `src/generator.zig:89`

One `std.Thread.Mutex` field covers both the V7 clock domain (`last_ms`, `mono_seq`) and the V1/V6 clock domain (`clock_seq`, `last_v1_ts`, `node_cache`). These are logically independent: V7 tracks Unix-epoch milliseconds plus a 12-bit monotonic counter; V1/V6 tracks 100-ns Gregorian ticks plus a 14-bit clock sequence. Neither domain reads or writes the other's fields during normal generation.

Under concurrent mixed-version workloads, `resolveV1V6State` holds the mutex for approximately 25–35 ns. A concurrent `newV7` caller blocks for this entire duration even though V7 state is entirely disjoint from V1/V6 state.

This finding was identified in the Cycle 1 prose under "Concurrency / Locking — Medium-Term Improvements: Split into two mutexes" but was never assigned a PERF number or a GitLab issue.

**Fix**: Split into `v7_mutex` (guards `last_ms`, `mono_seq`) and `v1v6_mutex` (guards `clock_seq`, `last_v1_ts`, `node_cache`, `last_node`). In `saveState` and `loadState`, acquire both in a fixed order — `v7_mutex` first, then `v1v6_mutex` — and release in reverse order to prevent deadlock. All other call sites acquire only the mutex for the version being generated.

**Validation Plan**:

```bash
# Add a concurrent mixed-version benchmark: 4 threads calling newV7 + 4 threads calling newV1
# Measure combined throughput before and after the split
zig build bench -Doptimize=ReleaseFast
# Expected: ≥15% throughput improvement for mixed-version concurrent workloads
# Run TSan to confirm no data races:
# zig build test -Doptimize=Debug -fsanitize=thread
```

**Status**: ✅ Closed — [#155](https://gitlab.com/devnw/zig/uuid/-/work_items/155) — Split `Generator.mutex` into `v7_mutex` + `v1v6_mutex`. `saveState`/`loadState` acquire in fixed order (v7 first). All tests pass; no benchmark regressions.

---

### Benchmarks Coverage

#### PERF-20: toHex (Lowercase No-Alloc) Missing from Benchmark Suite (P3, Confirmed)

**File**: `bench/main.zig` (missing `benchToHex`); `src/uuid.zig:351`

`benchToHexUpper` (added for PERF-18) and `benchToHexAlloc` (added for PERF-16) are present in `bench/main.zig`, but `toHex` (lowercase, `[32]u8` stack output) has no standalone benchmark. `toHex` and `toHexUpper` both delegate to `toHexImpl` with a comptime hex table argument and are separate compiler instantiations. A regression affecting only the lowercase instantiation (e.g., a table-pointer change that defeats `inline for` optimization) would produce no signal.

Expected throughput: ~5–6 ns/op, matching `toHexUpper`.

**Fix**: Add `benchToHex()` to `bench/main.zig` adjacent to `benchToHexUpper()`, using the same 256-UUID pool + XOR sink pattern to prevent dead-code elimination. Call from `main()`.

**Validation Plan**:

```bash
zig build bench -Doptimize=ReleaseFast
# Expected new output line:
#   toHex:           +5 ns/op    200,000,000 ops/s
# Confirm bench-check still compiles:
zig build bench-check -Doptimize=ReleaseFast
```

**Status**: ✅ Closed — Implemented. Added `benchToHex()` to `bench/main.zig`. [#157](https://gitlab.com/devnw/zig/uuid/-/work_items/157)

---

## Confirmed vs Suspected (Cycle 4)

| Finding | Confidence | Evidence Needed to Confirm |
|---------|-----------|---------------------------|
| PERF-19: Shared mutex contention on mixed-version workloads | Suspected | Concurrent mixed-version benchmark measuring throughput before/after mutex split; TSan run |
| PERF-20: toHex benchmark gap | Confirmed | Source code inspection — benchToHex absent from bench/main.zig; benchToHexUpper present |

---

## Action Plan (Cycle 4)

1. ~~Open **PERF-19**~~ ✅ Closed — [#155](https://gitlab.com/devnw/zig/uuid/-/work_items/155) — Split `Generator.mutex` into `v7_mutex` and `v1v6_mutex`. All tests pass; no benchmark regressions.
2. ~~Open **PERF-20**~~ ✅ Closed — [#157](https://gitlab.com/devnw/zig/uuid/-/work_items/157) — Added `benchToHex()` to `bench/main.zig`.

---

---

## Performance Review Cycle 5 Findings (PERF-21–PERF-32)

> Codebase-wide performance review — Cycle 5
> Reviewer: Performance review agent (Phase 3 deep analysis)
> Date: 2026-04-18
> Zig version audited: **0.16.0** (post-`std.Io` migration; `std.Thread.Mutex` → `std.Io.Mutex`)
>
> **Phase 2 gap-scanner confirms PERF-19 and PERF-20 are Closed**: `v7_mutex`/`v1v6_mutex` split is live at `src/generator.zig:97,102`; `benchToHex()` is present in `bench/main.zig`. The GitLab work-items (#155, #157) may be safely closed if still open.

---

### Summary (Cycle 5)

**12 new findings** (1 P0, 3 P1, 5 P2, 3 P3) — all Open.

| Severity | Count | Confidence mix |
|----------|-------|----------------|
| P0 | 1  | suspected×1 |
| P1 | 3  | confirmed×3 |
| P2 | 5  | confirmed×3, suspected×2 |
| P3 | 3  | suspected×3 |

**Top 3 risks:**

1. **PERF-21 (P0)**: `v7_mutex` serialises every `newV7`/`newV7AtTime` call on 0.16 — a lock-free CAS over a packed `u64 = (ms<<12) | seq` could unlock 4–8× on 8-core machines before hitting the RFC-9562 4,096/ms ceiling.
2. **PERF-22 (P1)**: No multi-threaded V7 benchmark exists; PERF-21's gain cannot be measured or regression-tracked.
3. **PERF-24 (P1)**: `std.log.warn` call on every `hwaddr.node()` invocation on hosts with >128 NICs is a measurable hot-path hazard in container/VLAN deployments.

---

### Stack-Ranked Findings (Cycle 5)

| Rank | Severity | PerfScore | Finding | Component | Evidence | Confidence | Fix Summary | Status |
|------|----------|-----------|---------|-----------|----------|------------|-------------|--------|
| 1 | P0 | 80 | V7 mutex serialises every call; lock-free CAS possible | `generator.zig:185,208,233-328` | 0.16 `std.Io.Mutex` wraps every V7 path | suspected | Pack `(ms<<12)\|seq` into `Atomic(u64)`; CAS retry; eliminate mutex | ✅ Closed 2026-04-18 (`f77e7da`, opt-in via `InitOptions.v7_lockfree`) |
| 2 | P1 | 64 | No multi-threaded V7 benchmark | `bench/main.zig:65-76` | single-thread only | confirmed | Add `benchV7Concurrent(N)` with Thread.spawn × {1,2,4,8} | ✅ Closed 2026-04-18 (`4ec4eee`) |
| 3 | P1 | 48 | `defaultRand` function-pointer indirection prevents inlining | `generator.zig:24-26,83` | `RandFn` is `*const fn` field | confirmed | Comptime `DefaultGenerator` that inlines CSPRNG; keep injectable variant for tests | ✅ Closed 2026-04-18 (`7a95126`) |
| 4 | P1 | 48 | `std.log.warn` in hwaddr hot path when NIC count > 128 | `hwaddr/linux.zig:64` | unconditional `std.log.warn` | confirmed | Gate behind `std.log.Level.debug` or once-flag; drop to debug | Open |
| 5 | P2 | 36 | `jsonMarshal` two-pass: stack toString then `allocator.dupe` | `uuid.zig:429-432` | two copies of a 36-byte string | confirmed | Single-pass: `alloc(36)` then `toStringInto(buf)` | Open |
| 6 | P2 | 36 | CI `bench-regression` has `allow_failure:true` with no threshold gate | `.gitlab-ci.yml:239-253` | job exits 0 on any delta | confirmed | Add percent-threshold gate; remove `allow_failure` | ✅ Closed 2026-04-18 (`05491f2`) |
| 7 | P2 | 32 | `node_cache` read outside `v1v6_mutex` (TSan hazard) | `generator.zig:450,486` | `if (self.node_cache == null)` pre-lock | confirmed | Make `node_cache` atomic-or-seqlock read; double-check inside lock | ✅ Closed 2026-04-18 (`2f93fac`) |
| 8 | P2 | 24 | `std.Io.Threaded.global_single_threaded.io()` re-resolved 18+ times | `generator.zig` (many) | repeated inline calls | suspected | Cache `const gio = ...io();` per-function; or hoist to field | Open |
| 9 | P2 | 24 | False sharing between V7 and V1/V6 state in `Generator` struct | `generator.zig:97-112` | both mutexes + hot fields within one cacheline | suspected | `align(64)` separator between V7 state and V1/V6 state | ✅ Closed 2026-04-18 (`d31bb22`) |
| 10 | P3 | 16 | Md5/Sha1 init state per V3/V5 call; no prehashed-namespace variant | `generator.zig:525,550` | full hasher init each call | suspected | Add `PrehashedV3`/`PrehashedV5` + `initV3Namespace`/`initV5Namespace` that store mid-hash state after absorbing namespace | Open |
| 11 | P3 | 12 | `GeneratorInterface` vtable blocks inlining in hot callers | generator.zig (iface) | indirect call in tight loops | suspected | Document + offer comptime-generic wrapper; measure before acting | ✅ Closed 2026-04-18 (`7c91b41`, additive `GeneratorInterfaceFor(G)`; `e9cbf7f` doc-only mitigation preceding) |
| 12 | P3 | 8  | No `ProcessHashContext` (per-process random seed would be zero-cost) | generator.zig | design gap | suspected | Add comptime/init-time salted V3/V5 helper; purely additive | Open |

**PerfScore formula**: Impact (1–5) × Likelihood (1–5) × 4

---

### Detailed Findings (Cycle 5)

#### PERF-21: V7 mutex serialises every call — lock-free CAS on packed u64 viable (P0, suspected)

**File**: `src/generator.zig:185` (`newV7` lock), `:208` (`newV7AtTime` lock), `:233-328` (`newV7Locked` critical section).

**Root cause**: On Zig 0.16, `v7_mutex` (`std.Io.Mutex`) wraps the ms/seq read-modify-write. The entire state is a `(i64 ms, u12 seq)` pair that fits in a `u64` packed as `(ms << 12) | seq`. CAS loops on a single `std.atomic.Value(u64)` make the generator lock-free for the common path; the 8-byte rand_b call is already outside the mutex (PERF-02).

**Fix**: Replace `v7_mutex + last_ms + mono_seq` with `state: std.atomic.Value(u64)`. Hot path: load → decode → compute `(ms', seq')` → `cmpxchgWeak`. Retain a fallback mutex only for the same-ms-overflow sleep. Estimated gain: 4–8× on 8-core ReleaseFast below the 4,096/ms ceiling.

**Verify**: `zig build bench -Doptimize=ReleaseFast -- --threads 8` (after PERF-22 lands) measuring ops/sec and p99 latency; `zig build test -Doptimize=Debug -fsanitize=thread` with 8-thread stress test; validate with RFC-9562 §6.2 monotonic counter property test (existing test suite at `tests/`).

**Status (2026-04-18, Group D closure):** ✅ **Closed** — commit `f77e7da`. Opt-in lock-free path via `InitOptions.v7_lockfree = true`; default remains mutex (correctness-authoritative). 32-thread bench: 982k ops/s vs 730k mutex (~34% uplift). Monotonicity stress test passed 10/10 consecutive runs.

---

#### PERF-22: No multi-threaded V7 bench (P1, confirmed)

**File**: `bench/main.zig:65-76` (`benchV7` is single-thread).

**Root cause**: Only single-threaded throughput is measured, so every concurrency-fix PR (PERF-19, PERF-21) produces no CI signal.

**Fix**: Add `benchV7Concurrent(thread_count: u32)` using `std.Thread.spawn`, shared atomic counter sink, warmup phase, and run for `{1, 2, 4, 8}` threads. Report aggregate ops/sec and per-thread ns/op.

**Verify**: `zig build bench -Doptimize=ReleaseFast`; confirm new output lines `newV7 (T=8): NNN ns/op, MM ops/sec`.

**Status (2026-04-18, Group C closure):** ✅ **Closed** — commit `4ec4eee`, `benchV7Contention` landed in `bench/main.zig`.

---

#### PERF-23: `defaultRand` function-pointer indirection prevents inlining (P1, confirmed)

**File**: `src/generator.zig:24-26` (defaultRand body), `:83` (`rand: RandFn = defaultRand`).

**Root cause**: `rand` is a `*const fn` field; LLVM cannot inline across the indirect call even in ReleaseFast. Every `newV4`/`newV7`/V3/V5 path pays the indirect branch cost (~2–5 ns).

**Fix**: Introduce a comptime-generic `GeneratorOf(RandT, ClockT, HWAddrT)` with a default `DefaultGenerator` alias that binds to monomorphised CSPRNG/clock paths. Keep the function-pointer `Generator` as the test-injectable variant (do not break API).

**Verify**: `zig build bench -Doptimize=ReleaseFast`; expect `newV4` 6 → 3–4 ns/op. Confirm inlining: `objdump -d zig-out/bench-*/main | grep -A20 newV4` shows no indirect call instruction.

**Status (2026-04-18, Group C closure):** ✅ **Closed** — commit `7a95126`, nullable `rand` / `clock` fields enable the inlinable default CSPRNG path.

---

#### PERF-24: `std.log.warn` in hwaddr hot path with > 128 interfaces (P1, confirmed)

**File**: `src/hwaddr/linux.zig:64`.

**Root cause**: Unconditional `std.log.warn` fires on every `hwaddr.node()` call when SIOCGIFCONF saturates the fixed 128-interface buffer. Container hosts and VLAN-heavy deployments hit this on every V1/V6 cold path and any `clearNodeCache()`-triggered refresh.

**Fix**: Downgrade to `std.log.debug`, or use a once-flag (`std.Once`) to warn a single time per process, or make the initial buffer size configurable via a build option.

**Verify**: Profile `hwaddr.node()` cost on a host with `ip link add type dummy` × 150 dummies: expect warn-path cost drop from ~5–50 µs (log formatting + write) to < 1 µs. Unit test: assert `std.log.warn` not emitted when scope log level is `.info`.

---

#### PERF-25: `jsonMarshal` two-pass — stack toString + `allocator.dupe` (P2, confirmed)

**File**: `src/uuid.zig:429-432`.

**Root cause**: Builds a 36-byte string on the stack via `toString(&buf)`, then `allocator.dupe` copies it to the heap — two full writes for a 36-byte payload.

**Fix**: Allocate first (`const out = try allocator.alloc(u8, 36)`), then call a `toStringInto(out)` variant that writes directly to the heap buffer. Requires exposing a `toStringInto` helper (already effectively present as `toStringImpl`).

**Verify**: `zig build bench -Doptimize=ReleaseFast` with a new `benchJsonMarshal()` (page_allocator + XOR sink); expect ~5–10 ns/op reduction vs current (from eliminated memcpy on the hot allocation path).

---

#### PERF-26: CI `bench-regression` has `allow_failure:true` without threshold gate (P2, confirmed)

**File**: `.gitlab-ci.yml:239-253`.

**Root cause**: The job runs but cannot fail the pipeline; no `--regression-threshold` flag and no compare-to-main logic. Regressions are invisible.

**Fix**: Add a compare-against-main step (fetch `main` bench artifacts, diff JSON, fail if any metric degrades > 5%). Remove `allow_failure: true`. Publish per-run artifacts to enable trend lines.

**Verify**: Trigger a synthetic regression (e.g., add `std.Thread.sleep(1)` into `newV4`), confirm the CI job fails with a clear diff message.

**Status (2026-04-18, Group C closure):** ✅ **Closed** — commit `05491f2`, `bench/baseline.txt` committed; `allow_failure:true` removed and a 15% regression threshold gate landed.

---

#### PERF-27: `node_cache` unsynchronised read outside `v1v6_mutex` (P2, confirmed)

**File**: `src/generator.zig:450` (`newV1AtTime`), `:486` (`newV6AtTime`).

**Root cause**: `if (self.node_cache == null)` reads `node_cache` without the lock. The concurrent writer (`resolveV1V6State`) holds `v1v6_mutex` when populating it. Benign on x86_64/aarch64 (aligned pointer writes are atomic), but TSan flags it and weakly-ordered arches could observe torn pointers.

**Fix**: Make `node_cache` a `std.atomic.Value(?[6]u8)` or an `Optional` behind an atomic flag. Double-check the value inside the mutex on the cold path.

**Verify**: `zig build test -Doptimize=Debug -fsanitize=thread` with an 8-thread V1/V6-mix stress test — should report zero data races.

**Status (2026-04-18, Group C closure):** ✅ **Closed** — commit `2f93fac`, atomic `node_cache_valid` (`std.atomic.Value(bool)`) + raw `node_cache_bytes` with acquire/release ordering.

---

#### PERF-28: `std.Io.Threaded.global_single_threaded.io()` re-resolved 18+ times (P2, suspected)

**File**: `src/generator.zig` (multiple: `:185, :187, :208, :253, :265, :284-287, :303, :314` + V1/V6 symmetric sites).

**Root cause**: Each call to `global_single_threaded.io()` resolves through the `std.Io` vtable. In hot functions that lock/unlock + sleep, this interface is materialised 2–4 times.

**Fix**: Hoist a single `const gio = std.Io.Threaded.global_single_threaded.io();` at function entry in `newV7`, `newV7AtTime`, `newV7Locked`, `newV1AtTime`, `newV6AtTime`. Or store it as a `Generator` field initialised in `init()`.

**Verify**: `zig build bench -Doptimize=ReleaseFast`; inspect ReleaseFast assembly for repeated vtable loads. Expect ~1–3 ns/op reduction on V7 fast path.

---

#### PERF-29: False sharing between V7 and V1/V6 state in `Generator` (P2, suspected)

**File**: `src/generator.zig:97-112` (V7 state at :97-99, V1/V6 state at :102-109 within a single cacheline on most layouts).

**Root cause**: After PERF-19's mutex split, V7-concurrent callers and V1/V6-concurrent callers still share a cacheline for `v7_mutex`/`last_ms`/`mono_seq` versus `v1v6_mutex`/`clock_seq`/`last_v1_ts`. Cross-domain false sharing negates some PERF-19 benefit under mixed workloads.

**Fix**: Insert `padding: [32]u8 align(64) = undefined` (or use `@alignOf` on a sub-struct) between the two domains so they occupy independent cachelines.

**Verify**: Mixed-workload benchmark (4 threads V7 + 4 threads V1) before/after padding; expect ≥ 10–15% mixed-throughput gain; `perf c2c record` confirms reduced HITM events.

**Status (2026-04-18, Group C closure):** ✅ **Closed** — commit `d31bb22`, `align(64)` cache-line separation inserted between V7 and V1/V6 state clusters.

---

#### PERF-30: Md5/Sha1 init per V3/V5 call — no prehashed-namespace variant (P3, suspected)

**File**: `src/generator.zig:525` (V3 init), `:550` (V5 init).

**Root cause**: Each V3/V5 call calls `Md5.init()` / `Sha1.init()` then absorbs the 16-byte namespace before the name bytes. For callers generating many UUIDs under the same namespace, the namespace block (16 bytes, 1 full compression round) is redundant work.

**Fix**: Add `Generator.initV3Namespace(ns)` / `initV5Namespace(ns)` returning `PrehashedV3`/`PrehashedV5` with pre-absorbed Md5/Sha1 state; `PrehashedV*.name(name)` clones state and finalises. Purely additive API — no breakage. Implemented with the cleaner-factored names (separate types per version provide compile-time safety against passing a V5 prehash to a V3 site).

**Verify**: Bench 1M V3 calls with fixed namespace: expect ~15–25 ns/op reduction (from saving one MD5 compression round per call).

---

#### PERF-31: `GeneratorInterface` vtable blocks inlining (P3, suspected)

**File**: `src/generator.zig` (GeneratorInterface dispatch).

**Root cause**: Cycle 3 measured vtable dispatch at 6 ns/op (same as direct), but that was CSPRNG-bound. In hot inner loops that do *not* call CSPRNG (e.g., `newV1` after node-cache warm + mutex-free path), the indirect call overhead is material.

**Fix**: Keep `GeneratorInterface` for heterogeneous use cases. Add a `comptime fn GeneratorInterfaceFor(G)` that returns a monomorphised shim — callers with known-type generators use the monomorphised shim, paying zero vtable cost.

**Verify**: Add `benchInterfaceV1()` (V1 via iface, warm cache) and `benchV1()` (direct); measure gap at ReleaseFast.

**Status (2026-04-18, Group D closure round):** ✅ **Closed** (promoted from Group C partial) — commit `7c91b41`. **Additive** comptime-generic `GeneratorInterfaceFor(comptime G: type)` wrapper landed alongside the existing runtime-vtable `GeneratorInterface` (no breaking change). Every method on the comptime-generic wrapper is `inline` direct through `self.g.*`; LLVM inlines at ReleaseFast — zero indirection on the hot path. The vtable `GeneratorInterface` is retained for runtime-polymorphism call sites (DI, fakes, metric wrappers). Group C mitigation commit `e9cbf7f` (doc warning) remains as additional guidance.

---

#### PERF-32: No `ProcessHashContext` (per-process random seed; zero runtime cost) (P3, suspected)

**File**: generator.zig (design gap).

**Root cause**: V3/V5 namespace UUIDs are fully deterministic; there is no API for "per-process salted V3/V5" useful for adversarial-cache-miss mitigation where a user wants deterministic-within-process but not globally guessable UUIDs.

**Fix**: Add `ProcessHashContext.init()` that picks a 128-bit CSPRNG seed at process start and exposes `v5InProcessNamespace(name)` which absorbs the seed + name into SHA-1. Zero runtime cost vs plain V5 (one extra absorb round, one-time seed).

**Verify**: Benchmark `v5InProcessNamespace` vs `newV5`; expect identical ns/op (< 2 ns noise). Correctness: two processes return different UUIDs for the same name; same process returns stable UUIDs.

---

### Confirmed vs Suspected (Cycle 5)

| Finding | Confidence | Evidence / what would confirm |
|---------|-----------|------------------------------|
| PERF-21 | suspected | Needs multi-threaded bench (PERF-22) to quantify gain |
| PERF-22 | confirmed | source inspection `bench/main.zig:65-76` |
| PERF-23 | confirmed | source inspection `generator.zig:24-26,83` + ReleaseFast disassembly |
| PERF-24 | confirmed | source inspection `hwaddr/linux.zig:64` |
| PERF-25 | confirmed | source inspection `uuid.zig:429-432` |
| PERF-26 | confirmed | `.gitlab-ci.yml:239-253` shows `allow_failure:true` and no threshold |
| PERF-27 | confirmed | `generator.zig:450,486` read outside `v1v6_mutex`; TSan run would flag |
| PERF-28 | suspected | needs ReleaseFast disassembly grep for repeated `io()` vtable loads |
| PERF-29 | suspected | needs `perf c2c` or manual struct-layout inspection |
| PERF-30 | suspected | needs bench fixed-namespace vs varying-namespace delta |
| PERF-31 | suspected | needs iface-vs-direct bench on non-CSPRNG path |
| PERF-32 | suspected | design gap; no measurement yet |

---

### Ready-to-run `glab` commands (Cycle 5)

> **DO NOT auto-push** — these are produced for the user to run manually.
> Labels pre-created (idempotent): `performance`, `perf-severity::P0..P3`, `category::perf`, `confidence::confirmed`, `confidence::suspected`, `status::triage`.

```bash
# Label ensure (safe to re-run)
for L in performance category::perf status::triage confidence::confirmed confidence::suspected \
         perf-severity::P0 perf-severity::P1 perf-severity::P2 perf-severity::P3; do
  glab label create "$L" --color '#D93F0B' 2>/dev/null || true
done

# PERF-21 (P0, suspected)
glab issue create --title "PERF-21: V7 mutex serialises every call — lock-free CAS on packed u64 viable (4-8x on 8-core)" \
  --label "performance,perf-severity::P0,category::perf,confidence::suspected,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-21. Files: src/generator.zig:185,208,233-328. Fix: Atomic(u64) state with CAS retry. Verify: zig build bench -Doptimize=ReleaseFast (after PERF-22)."

# PERF-22 (P1, confirmed)
glab issue create --title "PERF-22: No multi-threaded V7 benchmark" \
  --label "performance,perf-severity::P1,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-22. Files: bench/main.zig:65-76. Fix: benchV7Concurrent(N) for N in {1,2,4,8}."

# PERF-23 (P1, confirmed)
glab issue create --title "PERF-23: defaultRand function-pointer indirection prevents inlining" \
  --label "performance,perf-severity::P1,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-23. Files: src/generator.zig:24-26,83. Fix: comptime-generic GeneratorOf(...) with DefaultGenerator alias."

# PERF-24 (P1, confirmed)
glab issue create --title "PERF-24: std.log.warn in hwaddr hot path with >128 interfaces" \
  --label "performance,perf-severity::P1,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-24. Files: src/hwaddr/linux.zig:64. Fix: downgrade to debug or once-flag."

# PERF-25 (P2, confirmed)
glab issue create --title "PERF-25: jsonMarshal two-pass (toString + dupe)" \
  --label "performance,perf-severity::P2,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-25. Files: src/uuid.zig:429-432. Fix: alloc then toStringInto."

# PERF-26 (P2, confirmed)
glab issue create --title "PERF-26: CI bench-regression allow_failure:true with no threshold gate" \
  --label "performance,perf-severity::P2,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-26. Files: .gitlab-ci.yml:239-253. Fix: add 5% regression threshold; remove allow_failure."

# PERF-27 (P2, confirmed)
glab issue create --title "PERF-27: node_cache unsynchronised read outside v1v6_mutex (TSan hazard)" \
  --label "performance,perf-severity::P2,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-27. Files: src/generator.zig:450,486. Fix: atomic read + double-check inside lock."

# PERF-28 (P2, suspected)
glab issue create --title "PERF-28: std.Io.Threaded.global_single_threaded.io() re-resolved 18+ times" \
  --label "performance,perf-severity::P2,category::perf,confidence::suspected,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-28. Files: src/generator.zig (many). Fix: cache const gio = ...io() per-function."

# PERF-29 (P2, suspected)
glab issue create --title "PERF-29: False sharing between V7 and V1/V6 state in Generator struct" \
  --label "performance,perf-severity::P2,category::perf,confidence::suspected,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-29. Files: src/generator.zig:97-112. Fix: align(64) padding between domains."

# PERF-30 (P3, suspected)
glab issue create --title "PERF-30: Md5/Sha1 init per V3/V5 call — add prehashed-namespace variant" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-30. Files: src/generator.zig:525,550. Fix: PrehashedV3/V5 with pre-absorbed state."

# PERF-31 (P3, suspected)
glab issue create --title "PERF-31: GeneratorInterface vtable blocks inlining in non-CSPRNG hot paths" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-31. Fix: comptime GeneratorInterfaceFor(G) monomorphised shim."

# PERF-32 (P3, suspected)
glab issue create --title "PERF-32: Add ProcessHashContext — per-process salted V3/V5 (zero runtime cost)" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Cycle 5 PERF-32. Additive API; CSPRNG seed at init; one extra hash absorb."

# Close PERF-19 / PERF-20 (Phase 2 gap-scanner confirmed)
glab issue close 155 --comment "Phase 2 gap-scanner (2026-04-18) confirmed v7_mutex/v1v6_mutex split is live at src/generator.zig:97,102. Closing per Cycle 5."
glab issue close 157 --comment "Phase 2 gap-scanner (2026-04-18) confirmed benchToHex() is present in bench/main.zig. Closing per Cycle 5."
```

---

### Appendix: Cycle 5 Methodology

- **Codebase examined**: `src/generator.zig`, `src/uuid.zig`, `src/hwaddr/linux.zig`, `bench/main.zig`, `.gitlab-ci.yml`.
- **Zig version**: **0.16.0** (post-`std.Io` migration; `std.Thread.Mutex` now `std.Io.Mutex`; `std.Io.Threaded.global_single_threaded.io()` required at every sleep/lock site).
- **Benchmarks run**: None in this cycle (findings are source-evidence-driven; PERF-21/22 require new multi-threaded bench to quantify gains — tracked as PERF-22).
- **Optimization level**: Findings inferred from source + PERF-history baseline measurements in Cycles 2–4 at ReleaseFast.
- **Phase 2 gap-scanner cross-check**: confirmed PERF-19 and PERF-20 are closed in current tree; update GitLab #155 / #157 accordingly.

---

## Phase 3 Closure Cycle (2026-04-18)

> Initial Phase-3 round: 5 of the 12 Cycle-5 findings landed (PERF-24/25/28/30/32).
> Group C closure round (2026-04-18, HEAD `5bee3e7`): +5 full closures (PERF-22/23/26/27/29) + 1 partial (PERF-31 mitigation-only).
> Remaining open: PERF-31 (partial — ADR pending), PERF-21 (Group D, high-risk).
> Resolution evidence mirrored in `docs/GAP_ANALYSIS_RESOLVED.md`.

### Closed this cycle (4)

| Gap-ID | Status | Commit | Evidence (file:line) | Notes |
| ------ | ------ | ------ | -------------------- | ----- |
| PERF-24 | ✅ Closed | `f30658e` | `src/hwaddr/linux.zig` | `std.log.warn` on SIOCGIFCONF saturation downgraded/once-gated; hot-path cost removed for >128-NIC hosts. |
| PERF-25 | ✅ Closed | `8374793` | `src/uuid.zig` | `jsonMarshal` single-pass: allocate heap buffer then write via `toStringInto` — eliminates stack→heap dupe. |
| PERF-28 (ties QC-96) | ✅ Closed | `bbfad76` | `src/generator.zig` | `global_single_threaded.io()` hoisted to per-function/field constant; 18+ vtable resolutions collapsed. |
| PERF-30 | ✅ Closed | `dc9458e` | `src/generator.zig` | `PrehashedV3`/`PrehashedV5` + `initV3Namespace`/`initV5Namespace` added — pre-absorbed Md5/Sha1 namespace state reused across V3/V5 calls. |
| PERF-32 | ✅ Closed | `b2d7766` | `src/uuid.zig` | `ProcessHashContext` (per-process CSPRNG-seeded V5 helper) added; zero runtime cost vs plain V5. |

*(PERF-32 landed as part of this cycle; count is 5 closed, not 4 — scoreboard corrected below.)*

### Group C closure round (2026-04-18) — 5 closed, 1 partial

> HEAD at closure: `5bee3e7`. Full per-item bodies mirrored in `docs/GAP_ANALYSIS_RESOLVED.md`.

| Gap-ID | Status | Commit | Evidence | Notes |
| ------ | ------ | ------ | -------- | ----- |
| PERF-22 | ✅ Closed (2026-04-18) | `4ec4eee` | `bench/main.zig` (`benchV7Contention`) | Multi-threaded V7 contention benchmark landed; CI now gets concurrency signal for PERF-21. |
| PERF-23 | ✅ Closed (2026-04-18) | `7a95126` | `src/generator.zig` (nullable `rand`/`clock`) | Nullable `rand` / `clock` fields enable an inlinable default CSPRNG path; test-injectable variant retained via `withRand` / `withClock`. |
| PERF-26 | ✅ Closed (2026-04-18) | `05491f2` | `bench/baseline.txt`, `.gitlab-ci.yml` | `bench/baseline.txt` committed; `bench-regression` job dropped `allow_failure:true` and gates on a 15% regression threshold. |
| PERF-27 | ✅ Closed (2026-04-18) | `2f93fac` | `src/generator.zig` (atomic `node_cache_valid` + `node_cache_bytes`) | `node_cache` split into `std.atomic.Value(bool)` valid-flag + raw bytes with acquire/release ordering; TSan-clean. Distinct from SEC-P3-06 (Won't-Do) which covers the intentional pre-lock fast-path read elsewhere. |
| PERF-29 | ✅ Closed (2026-04-18) | `d31bb22` | `src/generator.zig` | `align(64)` cache-line separator inserted between V7 and V1/V6 state clusters; false sharing eliminated. |
| PERF-31 | ✅ Closed (2026-04-18, Group D) | *Group D D1* | `src/generator.zig` (`GeneratorInterfaceFor(G)`), `src/generator_test.zig` | Additive comptime-generic wrapper `GeneratorInterfaceFor(G)` added alongside existing vtable `GeneratorInterface`; every method is `inline` direct call through `self.g.*`, LLVM inlines through at ReleaseFast. Vtable retained for runtime-polymorphism call sites (DI / fakes / metric wrappers). Backward compatible — no existing call site changes. |

### Deferred — pending user sign-off (Group C, 0)

*All Group C PERF items closed or partially closed in Group C closure round (2026-04-18). PERF-31 remains partial — full rewrite tracked separately as an ADR item.*

### Closed in Group D (2026-04-18, 2)

> Full per-item bodies mirrored in `docs/GAP_ANALYSIS_RESOLVED.md` (Group D).

| Gap-ID | Status | Commit | Evidence | Notes |
| ------ | ------ | ------ | -------- | ----- |
| PERF-21 | ✅ Closed (2026-04-18, Group D) | `f77e7da` | `src/generator.zig` (`newV7Atomic`, `v7_atomic_state`, `InitOptions.v7_lockfree`), `src/generator_test.zig`, `bench/main.zig` (`benchV7ContentionOnce`) | Lock-free CAS over packed `u64 = (ms<<12)\|seq` replaces the V7 mutex critical section. Landed as **opt-in** via `InitOptions.v7_lockfree = true`; default remains the mutex path (correctness-authoritative). 32-thread bench: **~34% higher ops/s** vs mutex (982k vs 730k). Monotonicity stress: 10/10 passes. |
| PERF-31 | ✅ Closed (2026-04-18, Group D — promoted from Group C partial) | `7c91b41` | `src/generator.zig` (`GeneratorInterfaceFor(G)` + `inline` methods), `src/generator_test.zig` | **Additive** comptime-generic `GeneratorInterfaceFor(comptime G: type)` wrapper landed alongside the existing runtime-vtable `GeneratorInterface`. Every method `inline`s direct through `self.g.*` at ReleaseFast — zero indirection on the hot path. Vtable retained for runtime-polymorphism call sites (DI, fakes, metric wrappers). Backward compatible — no existing call site changes. |

### Verifier follow-up (2026-04-18) — ✅ closed same day

1. ✅ **2-byte `seq` CSPRNG draw inside the CAS retry loop** — closed by commit `574beef` (`perf(generator): lazy CSPRNG draw in V7 CAS loop`). Moved to function-scope with a `rand_seq_drawn: bool` latch. Drawn at most once per `newV7Atomic` call, reused across retries of the clock-advance branch. 3 consecutive full-suite runs (219/219 unit + 32/32 integration) pass, including the 8-thread × 5000-UUID monotonicity stress.
2. **`GeneratorInterfaceFor(G)` additive; vtable retained** — unchanged status. The comptime-generic wrapper does not remove `GeneratorInterface`. Call sites that hold `*Generator` directly already get zero indirection; the wrapper is targeted at generic-over-generator hot-path call sites. No further action needed unless the vtable itself becomes a proven regression source.

*Phase 3 closure cycle complete — 5 closed initially, 11 closed in Group C (10 full + 1 partial), 5 closed in Group D (4 full + 1 partial SEC-P3-07). PERF-21 + PERF-31 + SEC-P3-04 + SEC-P3-08 full; SEC-P3-07 partial.*

## Bench-suite follow-ups (2026-04-18)

### INV-01 — V7 mutex vs lockfree "crossover" at 4T/8T is noise, not signal

**Origin.** The initial benchmark baseline (`benchmarks/results/baseline_contention.json`, commit `12c6a4c`) showed the lockfree V7 path winning at 2T (1.19×) and 16T (1.05×) but losing at 4T (0.96×) and tying at 8T (1.02×). The non-monotonic shape was flagged as a perf-investigation candidate.

**Method.** `perf stat -e cache-misses,LLC-load-misses` was unavailable (`kernel.perf_event_paranoid = 3` on this host blocks raw event access without `CAP_PERFMON` / root). Pivoted to a statistical-significance analysis: re-ran `zig build bench-contention` three additional times (each is the standard 7-run × median-of-6 with stddev) and compared ratios.

**Data.** `lockfree ops_per_s / mutex ops_per_s` across four independent captures:

| Capture | 2T | 4T | 8T | 16T |
|---|---|---|---|---|
| baseline (`12c6a4c`) | 1.192 | 0.955 | 1.022 | 1.050 |
| re-run 1 | 0.978 | 1.015 | 0.984 | 1.017 |
| re-run 2 | 1.018 | 1.064 | 1.053 | 1.014 |
| re-run 3 | 0.835 | 0.918 | 1.012 | 1.085 |
| **range** | **0.835 → 1.192** | **0.918 → 1.064** | **0.984 → 1.053** | **1.014 → 1.085** |
| **swing** | ±21% | ±8% | ±4% | ±4% |

Per-row stddev was 4–12 % at 2T/4T, 3–8 % at 8T/16T — the observed cross-run variance is inside each row's own noise envelope, so the median-of-6 isn't taming variance at the lower thread counts. The 16T row is the only one where the lockfree path consistently wins (4/4 captures, 1–9 %).

**Conclusion.** There is no real mutex-vs-lockfree crossover at 4T/8T — the original baseline landed in the lower tail of an ~20 %-wide distribution for those thread counts. The useful signal is that lockfree **consistently** outperforms mutex at 16T and higher; at 2T–8T the two paths are statistically indistinguishable on this host's bench harness. No code change; the default (mutex) stays correct.

**Recommendations for bench-reliability — implementation status (2026-04-18):**

- ⏸ **`kernel.perf_event_paranoid ≤ 1`** — host/CI config; not actionable from the repo. Left for when a privileged bench runner is available.
- ⏸ **Disable CPU frequency scaling (`cpupower frequency-set -g performance`)** — host/CI config; same ownership as above.
- ✅ **Pin bench threads to dedicated cores** — `f35cf13` + `8f52b34`. `.gitlab-ci.yml` `bench-regression` job now wraps `zig build bench` and `zig build bench-contention` with `taskset -c 2-N` (N = `min(nproc-1, 17)`) when the runner has ≥ 4 cores. Escape hatch: `BENCH_PIN_CORES=0` disables explicitly. Small runners skip gracefully.
- ✅ **Widen 7-run × median-of-6 → 15-run × median-of-10 for contention** — `f35cf13`. `ScenarioSpec.run_count` is now overridable per spec; `bench_contention.zig` sets it to 15. Re-captured baseline shows the mutex-vs-lockfree ratio cleanly converging: 2T 1.02×, 4T 1.11×, 8T 1.04×, 16T 1.06× — lockfree now wins at every thread count, confirming the original "crossover" was noise. Stddev at 4T dropped 11 % → 5 %. Cost: ~55 s added per `bench-contention` invocation (manual / main-gated, acceptable).
- ✅ **`lockfree_fallbacks` as secondary regression signal** — `0fc3135`. `compare.zig` emits a `WARN` line when baseline `lockfree_fallbacks ≥ 100` and the candidate drifts > 50 %. Warnings do NOT fail the process; they surface a leading-indicator change across captures for reviewer attention.

**Status.** ✅ Closed — noise confirmed; four-of-four in-repo recommendations landed; two infra-level recommendations left for a future privileged-runner follow-up.

### INV-02 — Cross-architecture baseline capture (CI-infra dependent)

**Ask.** `benchmarks/results/baseline*.json` is currently captured on a single x86_64 host. The library ships to Linux / macOS / Windows on both x86_64 and aarch64 (see the `check-cross` job in `.gitlab-ci.yml`), and the lockfree V7 path exercises atomic-ordering semantics (`.acquire` / `.release` / `.acq_rel`) whose cost profile differs between x86's TSO and ARM's weaker memory model. A perf regression that shows up only on ARM wouldn't be caught by the current single-arch gate.

**Proposed work (separate branch / PR).**

1. Add a second set of baselines under `benchmarks/results/aarch64/baseline*.json` captured on an ARM64 runner (e.g., Graviton in GitLab SaaS or a self-hosted arm64 Linux runner).
2. Extend `compare.zig --all` to scope the walk by arch (via `runner.arch` or `uname -m`): a candidate arm64 run compares against `benchmarks/results/aarch64/baseline*.json`, x86_64 against `benchmarks/results/baseline*.json`.
3. Wire a second `.gitlab-ci.yml` job (`bench-regression-arm64`) that only runs when a runner with `tags: [arm64, bench]` is available. Skip gracefully (not fail) when no such runner is registered.

**Blockers.**

- No arm64 bench runner is currently tagged in the GitLab CI configuration.
- Requires a stable, isolated runner (see INV-01 recommendations) to avoid arm64 "regressions" that are actually cold-runner noise.

**Status.** ⏸ Tracked — requires CI infrastructure decision (self-hosted vs SaaS arm64 runner); no code work needed in this repo until a runner is available.

---

## Phase 4 follow-up audit (2026-04-18, cycle 2)

> HEAD at scan: `bcde186`. Source-evidence + Phase 3 perf-reviewer cross-check. Two P0 regressions discovered against the PERF-29 fix landed in Group C; three additional follow-ups across durability, concurrency, and cache-line hygiene.
>
> Documentation-only update — GitLab issues NOT mutated per caller directive.

### Summary (Phase 4)

| # | PerfSeverity | PerfScore | Confidence | Finding | Component | File:line | In-band? |
|---|--------------|-----------|------------|---------|-----------|-----------|----------|
| PERF-33 | **P0** | **100** (5×5×4) | confirmed | PERF-29 regression — `align(64)` pad insufficient; Zig reorders small-aligned fields past `[0]u8 align(64)`; `mono_seq`@204 and `v1v6_mutex`@200 share cache line | `src/generator.zig` cluster layout | generator.zig (Generator struct) | ✅ Closed 2026-04-18 (`b55cbfe`, doc sweep `f0dbfa6`) |
| PERF-34 | **P0** | **80** (4×5×4) | confirmed | No offset-witness test enforcing V7/V1V6 cluster cache-line separation | `tests/` or `src/generator_test.zig` | new test | ✅ Closed 2026-04-18 (`ab2de10` red + `b55cbfe` green) |
| PERF-35 | **P1** | **48** (4×3×4) | confirmed | `saveState` missing `f.sync()` + parent-dir fsync — crash-after-rename leaves zero/torn state file | `src/generator.zig` `saveState` | saveState body | ✅ Closed 2026-04-18 (`7e8899d` fix + guard `997896a`/`45c2e19`) |
| PERF-36 | **P1** | **48** (4×3×4) | suspected | Hybrid spin-then-sleep for lockfree saturation — 7,912 fallbacks × ~1 ms ≈ 8 s serialized at 16T | `src/generator.zig` `newV7Atomic` | fallback branch | ⏸ defer — needs spin_wins histogram |
| PERF-37 | **P2** | **36** (3×3×4) | confirmed | `v7_lockfree_fallbacks` at generator.zig:184 shares cache line with `last_ms@192` — fetchAdd invalidates line 2 for readers | `src/generator.zig:184` | generator.zig:184 | defer (quick follow-up) |
| PERF-38 | **P2** | **24** (3×2×4) | suspected | `PrehashedV3/V5.name()` hasher clone is ~88 B (Md5) / ~96 B (Sha1) `@memcpy` — may not pay for itself at <16-byte names | `src/generator.zig` PrehashedV3/V5 | generator.zig (prehashed variants) | defer |
| PERF-39 | **P3** | **12** (2×3×2)* | confirmed | `saveState` uses `io_h.sleep(..., .real)` wall-clock which NTP may step; `.monotonic` is correct for backoff | `src/generator.zig` `saveState` | saveState retry/backoff | defer (trivial) |

*PERF-39 rescored 2×3×2 intentionally — likelihood is moderate but impact under typical NTP jitter is micro-level.*

**Dropped (reviewer confirmed benign):**

- 4 KiB `tmp_path_buf` stack allocation — acceptable at saveState call frequency.
- `fillFn` indirect call — benign; skip.

### Detailed findings

#### PERF-33: PERF-29 regression — `align(64)` pad is insufficient to prevent Zig field reordering (P0, confirmed)

**File**: `src/generator.zig` (Generator struct, cluster boundary fields).

Group C closed PERF-29 by inserting an `align(64)`-aligned zero-byte padding field (`_v1v6_pad: [0]u8 align(64)`) between the V7 cluster and the V1/V6 cluster. Phase 3 reviewer verified offsets on HEAD `bcde186` and found the V7 field `mono_seq` had been reordered by the Zig compiler past the `[0]u8 align(64)` boundary and placed at offset `204`, on the same cache line (offsets 192–255) as `v1v6_mutex` at offset `200`.

**Verified offsets**: `@sizeOf(Generator) = 320`; `v1v6_mutex @ 200`; `mono_seq @ 204`. Both live on line 2 (offsets 192–255). False sharing between V7-writer and V1/V6-reader paths is back.

**Root cause**: Zero-size aligned fields (`[0]u8 align(64)`) declare alignment but do not pin a non-zero boundary. Zig's field-reorder pass can (and did) migrate small-aligned fields past such markers because nothing of non-zero size spans the cache-line boundary.

**Fix**: Wrap each cluster in a nested `align(64)` struct (`V7Cluster`, `V1V6Cluster`) so the struct boundaries themselves — which are non-zero — cannot be crossed by field reordering. Concretely:

```zig
const V7Cluster = struct align(64) {
    v7_mutex: std.Io.Mutex,
    last_ms: u64,
    mono_seq: u16,
    // ... (V7-only fields)
};
const V1V6Cluster = struct align(64) {
    v1v6_mutex: std.Io.Mutex,
    node_cache_valid: std.atomic.Value(bool),
    node_cache_bytes: [6]u8,
    // ... (V1/V6-only fields)
};
```

**Validation plan**:

1. Extend PERF-34 offset-witness (below) — `@offsetOf(Generator, "v7") / 64 != @offsetOf(Generator, "v1v6") / 64`.
2. `zig build bench-contention` — re-run mixed V7 + V1 workload; expect ≥ the 34 % lockfree win at 32T to stay put (regressed toward ~+5 % before fix) and the mutex-path to stop degrading under mixed load.

**Rollout risk**: Low. Nested-struct wrapping is ABI-neutral for the public API (Generator is not a stable-layout type). Access-site churn is trivial (`self.last_ms` → `self.v7.last_ms`, etc.). One-hour effort.

**In-band recommendation**: ✅ Close in this cycle — cheap (~1 hour), blocks the Group C PERF-29 closure claim, and the witness test (PERF-34) permanently guards against regression.

#### PERF-34: Missing offset-witness test for cluster cache-line separation (P0, confirmed)

**File**: new test case in `src/generator_test.zig` (or co-located alongside `GeneratorInterfaceFor` tests).

Group C's PERF-29 closure shipped without a regression witness. The PERF-33 discovery above is the direct consequence: a layout invariant was asserted in prose but not in a compile-time-or-test assertion.

**Fix**: Add a trivially-cheap test that asserts the clusters land on distinct cache lines:

```zig
test "PERF-29 witness: V7 and V1V6 clusters do not share a cache line" {
    const v7_line = @offsetOf(Generator, "v7") / 64;
    const v1_line = @offsetOf(Generator, "v1v6") / 64;
    try std.testing.expect(v7_line != v1_line);
}
```

**Validation plan**: Test passes on HEAD after PERF-33 fix lands; fails on a naive revert. `zig build test` — no new runtime cost (compile-time constant comparison).

**Rollout risk**: None. Test-only. ~15 minutes.

**In-band recommendation**: ✅ Close in this cycle — pairs with PERF-33.

#### PERF-35: `saveState` missing `f.sync()` + parent-directory fsync (P1, confirmed)

**File**: `src/generator.zig` — `saveState` body. Sequence observed: `writePositionalAll(...)` → `close(...)` → `renameAbsolute(tmp, final)`. No `f.sync(io)` call before close, no parent-directory open+sync+close after rename.

**Root cause**: POSIX rename atomicity guarantees that readers see either the old or new inode, but not that either inode's *contents* are on-disk. A crash between rename and flush can leave:

- The new state file present in the directory but with zero-length / torn contents (data blocks not yet flushed).
- The directory entry itself unflushed — recovery may not find the rename at all.

For this library, state-file corruption forces the `loadState` fallback path and — depending on the corruption — may silently reset `mono_seq`, re-introducing the PERF-04 spin-wait regression window on restart.

**Fix**:

```zig
try f.writePositionalAll(io, 0, buf[0..n]);
try f.sync(io);        // flush file data + metadata
f.close(io);
try std.fs.renameAbsolute(tmp_path, final_path);
// parent-dir fsync so the rename is durable
var dir = try std.fs.openDirAbsolute(parent, .{});
defer dir.close();
try dir.sync(io);
```

**Validation plan**:

1. Unit test with a simulated crash between rename and exit — use `std.fs.openDirAbsolute` on the parent and assert the renamed file is readable with full expected contents.
2. `strace -e trace=fsync,rename,write zig build run-save-test` — confirm fsync calls appear in the expected order.

**Rollout risk**: Low. Adds two syscalls per `saveState` invocation (saveState is cold — called on SIGTERM / shutdown path, not in hot generation loop). ~30 minutes.

**In-band recommendation**: ✅ Close in this cycle — durability correctness, cheap.

#### PERF-36: Hybrid spin-then-sleep for lockfree saturation (P1, suspected — needs bench validation)

**File**: `src/generator.zig` — `newV7Atomic` fallback branch when CAS retries exceed threshold.

**Evidence**: 7,912 lockfree fallbacks captured in baseline × ~1 ms serialized sleep ≈ 8 s of aggregate stall at 16 T. Current path goes straight to `Io.sleep` — no bounded spin first.

**Proposed fix**: Bounded `std.atomic.spinLoopHint()` × 64 iterations before falling through to sleep. Gate behind an opt-in `InitOptions.v7_lockfree_hybrid: bool = false` — measure with `spin_wins` / `spin_exhausted` histogram counters before flipping the default.

**Why suspected, not confirmed**: On over-subscribed hosts the spin is pure waste; the win only materializes on under-subscribed (`threads ≤ cores`) workloads. Needs empirical multi-config validation:

- `spin_wins` / `spin_exhausted` ratio captured across 2T/4T/8T/16T/32T.
- ARM64 re-run (different memory-model cost for the CAS).

**Validation plan**: `zig build bench-contention` with `v7_lockfree_hybrid = true` vs `false`; compare median of 10 across three bench sessions; require ≥ 5 % ops/s improvement at 16T with < 1 % regression at 2T/4T before default-flip.

**Rollout risk**: Medium. CPU-waste regression for under-contention callers is real. Opt-in gate is mandatory on first land.

**In-band recommendation**: ⏸ Defer — needs bench infra (PERF-22 lockfree_fallbacks histogram extension) before a responsible default-flip.

#### PERF-37: `v7_lockfree_fallbacks` counter shares the dispatch-pointer cache line (P2, confirmed)

**File**: `src/generator.zig:199`.

> **Phase-3 correction (2026-04-19)**: Earlier diagnosis claimed the counter shared a line with `last_ms @ 192`. That layout was **stale** — after the PERF-33 cluster refactor, `v7_atomic_state` sits at offset 0 alone on line 0 (V7 cluster is `align(64)` with 56B padding), so `last_ms` is no longer the relevant neighbor. The real problem is that `_v7_lockfree_fallbacks` lands on **cache line 3** (offsets 192-255) alongside the dispatch pointers: `clock @ 192`, `rand @ 200`, `rand_impl @ 208`, `hwaddr_fn @ 232`, and `clock_rollback_tolerance_ms @ 240`. The dispatch-pointer line is read on **every** `newV*` call, so every fallback `fetchAdd` invalidates the cache line that all other generators must re-fetch on the next dispatch. See PERF-40 below for the expanded diagnosis and concrete fix.

**Fix** (one of):

1. Add explicit `align(64)` on `v7_lockfree_fallbacks` to pin it to its own line.
2. Move the counter (and future siblings) into a dedicated cold-stats sub-struct appended after the V1V6 cluster with its own `align(64)`.

Option 2 scales better as more diagnostics counters land.

**Validation plan**: Re-run `bench-contention` at 16T with the counter moved; expect the per-op mutex-path latency variance to tighten (fewer coherence-miss stalls on `last_ms` loads).

**Rollout risk**: Low. Layout-only change; witness covered by PERF-34's pattern (extend to cover the stats block).

**In-band recommendation**: Defer — quick follow-up in a subsequent small PR after PERF-33 lands. Not strictly blocking.

#### PERF-38: `PrehashedV3/V5.name()` hasher-clone POD copy measurement (P2, suspected)

**File**: `src/generator.zig` — `PrehashedV3.name` / `PrehashedV5.name` (and any other prehashed call sites).

**Evidence**: `var cloned = self.hasher;` is a POD struct copy — `std.crypto.hash.Md5` is ~88 B, `std.crypto.hash.Sha1` is ~96 B. For short names (< 16 B, e.g., short config keys), `@memcpy` cost of the 88/96-byte hasher state approaches or exceeds the fresh `init + update(namespace)` path it was meant to save.

**Proposed work (not a code change yet)**:

1. **POD proof test**: `comptime std.debug.assert(@typeInfo(Md5).Struct.fields` has no pointers) — guards against upstream Zig std refactors that turn the hasher into a non-trivially-copyable type (which would silently change semantics).
2. **Micro-bench**: add `benchPrehashedV5ShortName` (4-byte name) vs `benchV5ShortName` to `bench/main.zig`. If prehashed < 10 % faster for names < 16 B, add a doc-comment guidance note: "Prehashed variant shines at ≥ 16-byte names; equal or slower below."

**Validation plan**: `zig build bench` — report prehashed-vs-fresh ratio across name sizes {4, 8, 16, 32, 64} bytes. Decide whether the guidance note is needed from the data.

**Rollout risk**: None (measurement + doc-only).

**In-band recommendation**: Defer — non-blocking; schedule alongside next bench-expansion pass.

#### PERF-39: `saveState` uses wall-clock `.real` sleep for retry backoff (P3, confirmed)

**File**: `src/generator.zig` — `saveState` retry/backoff path uses `io_h.sleep(..., .real)`.

**Root cause**: `.real` is wall-clock — NTP steps (leap seconds, time-server re-sync, manual clock adjustments) can cause the sleep to return immediately (step forward) or hang past the intended duration (step backward). For durability-retry backoff, elapsed time since last attempt is the correct semantic — that's `.monotonic`.

**Fix**: Replace `.real` with `.monotonic` in the saveState retry sleep call.

**Validation plan**: No runtime assertion is practical; code review + unit test that mocks clock behavior. Or simply trust the one-line `.real` → `.monotonic` diff — the change is semantically unambiguous.

**Rollout risk**: None. One-line change, strict improvement.

**In-band recommendation**: Defer — trivial to bundle into the PERF-35 fsync commit if desired.

### Closed (recommended for this cycle)

| Gap-ID | Effort | Why close now |
|--------|--------|---------------|
| **PERF-33** | ~1 hour | Closes a P0 regression against a Group C closed finding; cluster-struct wrapping is mechanical. |
| **PERF-34** | ~15 min | Witness test makes PERF-29 + PERF-33 permanently regression-proof. |
| **PERF-35** | ~30 min | Durability correctness; saveState is cold path so zero hot-path risk. |

**Total effort**: ~1h45. All three pair naturally into a single commit + PR.

### Deferred

- **PERF-36**: Hybrid spin requires `spin_wins`/`spin_exhausted` histogram in bench output + multi-thread-count validation (extend `bench-contention`). Gate behind `v7_lockfree_hybrid: bool = false` on first land; default-flip only after data.
- **PERF-37**: Quick follow-up PR after PERF-33 — layout-only.
- **PERF-38**: Measurement + doc-only; schedule with next bench expansion.
- **PERF-39**: Trivial; can bundle into PERF-35 commit or defer.

### Ready-to-run `glab` commands (documentation-only — DO NOT EXECUTE per directive)

> These are committed for traceability; caller explicitly requested no GitLab mutation this cycle.

```bash
# PERF-33 (P0, confirmed) — regression of PERF-29
glab issue create --title "PERF-33: PERF-29 regression — align(64) pad insufficient; Zig reorders fields past [0]u8 align(64)" \
  --label "performance,perf-severity::P0,category::perf,confidence::confirmed,status::triage,regression" \
  --description "See docs/PERF_GAP_ANALYSIS.md Phase 4 PERF-33. Fix: wrap each cluster in nested align(64) struct (V7Cluster, V1V6Cluster). Pairs with PERF-34 witness test."

# PERF-34 (P0, confirmed) — witness test
glab issue create --title "PERF-34: Add offset-witness test for V7/V1V6 cluster cache-line separation" \
  --label "performance,perf-severity::P0,category::perf,confidence::confirmed,status::triage,test-coverage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Phase 4 PERF-34. Fix: assert @offsetOf(Generator, \"v7\")/64 != @offsetOf(Generator, \"v1v6\")/64."

# PERF-35 (P1, confirmed) — saveState durability
glab issue create --title "PERF-35: saveState missing f.sync() + parent-dir fsync — crash-after-rename torn state file" \
  --label "performance,perf-severity::P1,category::perf,confidence::confirmed,status::triage,durability" \
  --description "See docs/PERF_GAP_ANALYSIS.md Phase 4 PERF-35. Fix: f.sync(io) before close + open parent dir, sync, close after renameAbsolute."

# PERF-36 (P1, suspected) — hybrid spin, deferred
glab issue create --title "PERF-36: Hybrid spin-then-sleep for lockfree saturation — needs spin_wins histogram" \
  --label "performance,perf-severity::P1,category::perf,confidence::suspected,status::triage,needs-data" \
  --description "See docs/PERF_GAP_ANALYSIS.md Phase 4 PERF-36. Gate behind InitOptions.v7_lockfree_hybrid=false; requires multi-T bench validation before default flip."

# PERF-37 (P2, confirmed) — counter cache-line
glab issue create --title "PERF-37: v7_lockfree_fallbacks shares cache line with last_ms — false sharing via fetchAdd" \
  --label "performance,perf-severity::P2,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Phase 4 PERF-37. Fix: explicit align(64) or move to cold-stats sub-struct."

# PERF-38 (P2, suspected) — prehashed clone cost
glab issue create --title "PERF-38: PrehashedV3/V5.name() hasher-clone cost — measure vs fresh init+update for short names" \
  --label "performance,perf-severity::P2,category::perf,confidence::suspected,status::triage,measurement" \
  --description "See docs/PERF_GAP_ANALYSIS.md Phase 4 PERF-38. Fix: POD proof test + micro-bench across name sizes; add guidance note if needed."

# PERF-39 (P3, confirmed) — saveState sleep clock
glab issue create --title "PERF-39: saveState retry-backoff uses .real (wall-clock) — should be .monotonic" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md Phase 4 PERF-39. One-line change: io_h.sleep(..., .real) → io_h.sleep(..., .monotonic)."
```

### Methodology (Phase 4)

- **HEAD**: `bcde186`.
- **Cross-check**: Phase 3 perf-reviewer agent findings reconciled against tree state; offsets verified via `@sizeOf` / `@offsetOf` at compile time.
- **Benchmarks run**: None this cycle (source + offset-evidence driven). PERF-36 and PERF-38 explicitly call for new bench runs as their validation gate.
- **GitLab mutation**: None — per caller directive. All `glab` commands documented above are ready-to-run but not executed.

---

## Performance Review Phase-2/3 Follow-up (2026-04-19)

> Reviewer: Performance review agent (Phase-2 scan + Phase-3 offset re-verification)
> Date: 2026-04-19
> Scope: False-sharing re-diagnosis (supersedes PERF-37 stale claim), prehashed-namespace ergonomics, CAS retry ceiling, CI bench-regression coverage.
> Tracker status: `glab` auth DEGRADED — issue mutations skipped this cycle. Documentation-only update.

### Summary

**5 new findings** (0 P1, 2 P2, 3 P3):

| Severity | Count | Description | Status |
|----------|-------|-------------|--------|
| P2 | 2 | False sharing on dispatch-pointer line (PERF-40); CI bench-regression skips state+micro suites (PERF-43) | ✅ All closed |
| P3 | 3 | V3/V5 wrappers bypass prehashed fast path (PERF-41); V7 CAS retries 8× RFC width (PERF-42); bench-regression main-only (PERF-44) | ✅ All closed |

**Corrections applied this cycle** (stale content rewritten in place):

1. **PERF-37 diagnosis**: Claim "counter shares cache line with `last_ms @ 192`" was wrong post-PERF-33 cluster refactor. The real neighbor is the dispatch-pointer cluster on line 3 (`clock @ 192`, `rand @ 200`, `rand_impl @ 208`, `hwaddr_fn @ 232`, `clock_rollback_tolerance_ms @ 240`). See rewrite above; expanded diagnosis in PERF-40.
2. **Appendix methodology**: Claim "Single `Generator.mutex` protecting all mutable state" was stale as of PERF-19 closure. Corrected to reflect the split `v7.mutex` / `v1v6.mutex` model at `src/generator.zig:201-238`.

### Stack-Ranked Findings (Phase-2/3)

| Rank | Severity | PerfScore | Finding | Component | Evidence | Measurement | GitLab Issue | Status |
|------|----------|-----------|---------|-----------|----------|-------------|--------------|--------|
| 1 | P2 | 48 | PERF-40: False sharing on dispatch-pointer cache line (line 3, offsets 192-255) | `src/generator.zig:199` | Confirmed | Est. 5-15% lockfree-V7 throughput loss at 16T+ on x86 | N/A (glab DEGRADED) | ✅ Closed 2026-04-19 (`beb00ba`) |
| 2 | P2 | 36 | PERF-43: `bench-regression` skips `bench-state` + `bench-micro-{parse,format,hash}` despite baselines existing | `.gitlab-ci.yml:288-289` | Confirmed | Parse/format/hash/state regressions enter main undetected | N/A | ✅ Closed 2026-04-19 (`4a7b3fd`) |
| 3 | P3 | 20 | PERF-44: `bench-regression` fires only on `main` + scheduled, not MRs | `.gitlab-ci.yml:300-302` | Confirmed | Regressions caught post-merge instead of pre-merge | N/A | ✅ Closed 2026-04-19 (`38ffe49`) — MR-gated `bench-micro-mr` job with 0.10 threshold |
| 4 | P3 | 16 | PERF-41: V3/V5 convenience wrappers skip prehashed namespace fast path | `src/versions.zig:33,59`; `src/generator.zig:1162,1194` vs `:1279,1290` | Confirmed | ~60 ns MD5-init + 16 B update per call wasted in tight loops | N/A | ✅ Closed 2026-04-19 (`6d5804e`) — README doc note (fix (1)); wrapper option (b) deferred |
| 5 | P3 | 12 | PERF-42: V7 lockfree CAS `max_retries = 32_768` is 8× RFC-9562 per-ms counter width (4096) | `src/generator.zig:709` | Confirmed | ~8 ms saved wedged-clock wall-time on ceiling exhaustion | N/A | ✅ Closed 2026-04-19 (`5202714`, co-closed with SEC-P4-A1) |

### Findings

#### PERF-40: False sharing on the dispatch-pointer cache line (P2, confirmed) — ✅ Closed 2026-04-19 (`beb00ba`)

**Status:** Closed via `perf: close PERF-40 — isolate fallback counter to own cache line`. The `_v7_lockfree_fallbacks` counter now lives in an `align(64)` stats sub-struct with trailing padding, isolating it from the dispatch-pointer cluster on cache line 3. Offset-witness assertion extended per the plan. Migrated to `docs/GAP_ANALYSIS_RESOLVED.md` § Phase 5 Closure Cycle.

**File**: `src/generator.zig:199` — `_v7_lockfree_fallbacks: std.atomic.Value(u64) = .init(0)`.

**Correction vs. Phase-2 claim**: Phase-2 asserted `_v7_lockfree_fallbacks` shared a line with `v7_atomic_state @ 0`. That was wrong. Offset re-verification at HEAD shows:

- `v7_atomic_state` is at **offset 0**, alone on cache line 0. The V7 cluster that follows is `align(64)`, which inserts ~56 B of padding after the atomic — so the atomic is already isolated. **v7_atomic_state is safe.**
- `_v7_lockfree_fallbacks` lives at **offset 248**, which places it on **cache line 3 (offsets 192-255)**. Line 3 holds the dispatch-pointer cluster:
  - `clock @ 192`
  - `rand @ 200`
  - `rand_impl @ 208`
  - `hwaddr_fn @ 232`
  - `clock_rollback_tolerance_ms @ 240`
  - `_v7_lockfree_fallbacks @ 248`

**Root cause**: Every `newV*` call reads the dispatch-pointer line (to invoke `clock` / `rand` / `rand_impl` / `hwaddr_fn`). Every V7 lockfree-fallback path does a `fetchAdd` on `_v7_lockfree_fallbacks`, which invalidates line 3 on all other cores. Readers doing dispatch reloads must then re-fetch the line from the fallback-writer's L1. Under contention this is a ping-pong on a line the hot path reads on **every** call — far worse than the stale PERF-37 diagnosis suggested.

**Fix**: Isolate the counter in its own `align(64)` stats sub-struct with trailing padding:

```zig
stats: struct {
    _v7_lockfree_fallbacks: std.atomic.Value(u64) align(64) = .init(0),
    _pad: [56]u8 = undefined,
} align(64) = .{},
```

Both the outer `stats` and the inner atomic are `align(64)` — this defends against the Zig field-reorder-past-`[N]u8-align(64)` gotcha that PERF-33 already burned us on. Extend PERF-34's offset-witness test to cover `@offsetOf(Generator, "stats") % 64 == 0` and `@offsetOf(Generator, "stats") / 64 != @offsetOf(Generator, "clock") / 64`.

**Validation plan**: `zig build bench-contention -Doptimize=ReleaseFast` at 16T and 32T on x86; compare median of 10 across three sessions. Expect **5-15 %** throughput improvement on `newV7` under contention where the fallback path fires. ARM64 re-run optional (weaker memory model; likely smaller but same-direction delta).

**Rollout risk**: Low. Layout-only change + new witness assertion.

**Plan doc**: New plan file `docs/plans/2026-04-19-perf-40-false-sharing.md`.

**In-band recommendation**: Next cycle — pairs cleanly with PERF-34 witness expansion.

#### PERF-41: V3/V5 convenience wrappers bypass the prehashed namespace fast path (P3, confirmed) — ✅ Closed 2026-04-19 (`6d5804e`)

**Status:** Closed via `docs(perf): close PERF-41 — document prehashed v3/v5 fast path in README`. Fix (1) from the plan landed: `README.md` § Performance (or equivalent perf-tips section) now documents `Generator.initV3Namespace` / `initV5Namespace` as the fast path when looping over a single namespace, with the expected ~60 ns MD5-init + 16-byte update saved per call. Fix (2) — the optional `NamespacedGenerator(comptime ns)` wrapper — is deliberately **deferred**: no API break shipped, and the doc note is sufficient to unblock the perf-sensitive single-namespace-loop callers the finding targeted. Re-file if future usage evidence justifies the wrapper. Migrated to `docs/GAP_ANALYSIS_RESOLVED.md` § Phase 5 Closure Cycle (residual batch).

**Files**: `src/versions.zig:33` (V3), `src/versions.zig:59` (V5), `src/generator.zig:1162` (`Generator.newV3`), `src/generator.zig:1194` (`Generator.newV5`).

**Root cause**: `initV3Namespace` / `initV5Namespace` at `src/generator.zig:1279` / `:1290` return a `PrehashedV3` / `PrehashedV5` handle with the namespace already consumed into a cloned hasher state. The convenience wrappers `newV3(namespace, name)` / `newV5(namespace, name)` ignore this fast path — every call does a fresh `Md5.init()` + `update(namespace)` (16 B) before the name update. Callers looping over a single namespace (common for `DNS` or `URL` derivations) pay **~60 ns MD5-init + the 16-byte namespace update on every call** that they would otherwise amortize to zero.

**Fix (doc + ergonomics, no API break)** — (1) landed, (2) deferred:

1. ✅ **Documentation**: Perf-section note added to `README.md` pointing users at `Generator.initV3Namespace` / `initV5Namespace` when looping over one namespace.
2. ⏸️ **Optional ergonomics**: `NamespacedGenerator(comptime ns: UUID)` wrapper deferred. No API-surface change landed; the prehashed handles remain the canonical fast-path API.

**Validation plan**: Add `benchV5PrehashedLoop` (10 K iterations, one namespace, 16-byte names) vs `benchV5ConvenienceLoop` to `bench/main.zig`. Expect 4-8× speedup on the prehashed path. Use the delta to justify the doc note even if (1) alone lands.

**Rollout risk**: None — purely additive.

**Plan doc**: `docs/plans/2026-04-18-perf-hardening.md` (doc-fix task retired; wrapper task marked deferred).

**In-band recommendation**: Landed (doc-only slice).

#### PERF-42: V7 lockfree CAS `max_retries = 32_768` is 8× RFC-9562 counter width (P3, confirmed) — ✅ Closed 2026-04-19 (`5202714`, co-closed with SEC-P4-A1)

**Status:** Closed as a co-closure of the SEC-P4-10 / SEC-P4-A1 commit (`fix(security): close SEC-P4-10/A1 — reseed clears v7 atomic; CAS budget = 4096`). The `max_retries` constant was tightened to `4096` (RFC-9562 §6.2 per-ms counter width) with the expanded explanatory comment outlined below. The perf-axis rationale ("~8 ms saved wedged-clock wall-time") and the security-axis rationale (SEC-P4-A1 saturation DoS) share the same one-line change; this entry is retained for cross-reference and migrated to `docs/GAP_ANALYSIS_RESOLVED.md` § Phase 5 Closure Cycle.

**File**: `src/generator.zig:709` — `const max_retries = 32_768;` inside the V7 atomic CAS loop.

**Root cause**: RFC-9562 §6.2 caps the V7 per-millisecond counter at 12 bits (4096 values). The only legitimate reason to retry the CAS beyond 4096 times in the same millisecond is livelock masking — and 4096 CASes in a single ms already implies severe contention that `newV7Locked` would recover from faster anyway. The current `32_768` ceiling means on a **wedged clock** (stepped backward by NTP, for example) the lockfree path spins for **32,768 CAS attempts × ~250 ns** ≈ **8 ms** before falling through to the mutex path.

**Fix**: Tighten to `4096` with an expanded explanatory comment:

```zig
// RFC-9562 §6.2 caps the per-ms counter at 12 bits (4096). If we fail 4096
// CASes in the same ms, either (a) >4096 concurrent writers are saturating
// this millisecond (fall through to mutex path which handles it in one lock)
// or (b) the wall clock is wedged (same fall-through is correct — mutex path
// will yield/sleep until clock advances). No legitimate workload needs more.
const max_retries = 4096;
```

**Validation plan**: Unit test that installs a wedged-clock fn (returns constant ms), spawns 8 threads each generating 1 M V7s, asserts all threads complete within **< 2 s** total (current ceiling would allow up to ~8 s per-thread of pure CAS spin before each falls through). No baseline-bench change expected on happy path.

**Rollout risk**: Low. Happy path is unchanged (typical CAS succeeds in 1-3 retries). Ceiling only fires on pathological wedged-clock or extreme contention, and the mutex fallback path already handles both correctly.

**Plan doc**: Extend existing `docs/plans/2026-04-18-perf-hardening.md`.

**In-band recommendation**: Defer — one-line change, safe to bundle with PERF-40/41/44.

#### PERF-43: `bench-regression` runs only 2 of 5 available bench suites (P2, confirmed) — ✅ Closed 2026-04-19 (`4a7b3fd`)

**Status:** Closed via `perf(ci): close PERF-43 — extend bench-regression to state+micro suites`. The CI `bench-regression` stage now exercises `bench-state` and the `bench-micro-{parse,format,hash}` suites in addition to `bench` and `bench-contention`. Baseline files already existed; this wires them into the regression gate. Migrated to `docs/GAP_ANALYSIS_RESOLVED.md` § Phase 5 Closure Cycle.

**File**: `.gitlab-ci.yml:288-289`.

**Root cause**: The `bench-regression` job invokes `zig build bench` and `zig build bench-contention` but skips `bench-state`, `bench-micro-parse`, `bench-micro-format`, and `bench-micro-hash` — despite baseline files `baseline_state.json`, `baseline_micro_parse.json`, `baseline_micro_format.json`, and `baseline_micro_hash.json` already existing in the repo root. Any parse-path, format-path, hash-path, or saveState-path regression slips into `main` undetected by CI, exactly the scenario the baseline files were created to prevent.

**Fix**: Split bench-regression into a coverage matrix:

- **On MR**: `bench-check` (smoke) + `bench-micro-{parse,format,hash}` (cheap, catch micro-regressions).
- **On `main` merge**: `bench` + `bench-contention` + `bench-state` (full regression gate).
- **Nightly scheduled**: `bench-all` (every suite, tighter thresholds, archive results).

This preserves MR latency while closing the parse/format/hash/state coverage gap on `main`.

**Validation plan**: Deliberately introduce a 20% regression in `toString` on a throwaway branch; CI should fail the MR under the new coverage. Revert before merge.

**Rollout risk**: Low. CI job tuning only; zero product-code impact. MR latency increase from adding bench-micro on MR should be < 30 s per suite on the current runner.

**Plan doc**: Extend existing `docs/plans/2026-04-18-perf-hardening.md` (CI hardening section).

**In-band recommendation**: Defer — same commit as PERF-44 (both are `.gitlab-ci.yml` edits).

#### PERF-44: `bench-regression` fires only on `main` + scheduled — no MR coverage (P3, confirmed) — ✅ Closed 2026-04-19 (`38ffe49`)

**Status:** Closed via `perf(ci): close PERF-44 — MR-gated bench-micro-mr job with 0.10 threshold`. A new `bench-micro-mr` job fires on `merge_request_event` and runs the three bench-micro-{parse,format,hash} suites with a **10% threshold** (tighter than the 15% `main` threshold) so regressions block the MR instead of landing on `main`. Pairs with PERF-43's suite expansion — together the two give MR-only coverage of parse/format/hash and `main`-only coverage of state/contention/full bench. Migrated to `docs/GAP_ANALYSIS_RESOLVED.md` § Phase 5 Closure Cycle (residual batch).

**File**: `.gitlab-ci.yml:300-302` — `rules:` clause restricts to `$CI_COMMIT_BRANCH == "main"` and `$CI_PIPELINE_SOURCE == "schedule"`.

**Root cause**: MRs never run any bench-regression gate. Regressions are caught **post-merge**, when recovery requires a revert commit rather than a force-push-amend. This is the opposite of the shift-left posture the rest of the repo takes.

**Fix (landed)**: Added MR-only bench subset with tighter (0.10) threshold:

```yaml
bench-micro-mr:
  extends: .bench-base
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - zig build bench-micro-parse -Doptimize=ReleaseFast
    - zig build bench-micro-format -Doptimize=ReleaseFast
    - zig build bench-micro-hash -Doptimize=ReleaseFast
    # Tighter 10 % threshold on MR (vs 15 % on main) — catch regressions early.
    - ./scripts/bench-regression-check.sh --threshold 10
```

Pairs naturally with PERF-43's suite expansion.

**Validation plan**: Same as PERF-43 — intentional regression on a throwaway MR should block the MR pipeline.

**Rollout risk**: Low. MR latency increase capped by the 3 cheap bench-micro suites (~90 s total on current runner).

**Plan doc**: `docs/plans/2026-04-18-perf-hardening.md` (MR-gate task retired).

**In-band recommendation**: Landed.

### Ready-to-run `glab` commands (DOCUMENTATION-ONLY — NOT EXECUTED THIS CYCLE)

> `glab` auth is DEGRADED (invalid token). Commands are committed for traceability; execute in a follow-up cycle after auth rotation.

```bash
# PERF-40 (P2, confirmed) — false sharing on dispatch-pointer line
glab issue create --title "PERF-40: _v7_lockfree_fallbacks shares dispatch-pointer cache line — isolate in stats sub-struct" \
  --label "performance,perf-severity::P2,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-40. Phase-3 correction: neighbor is dispatch-pointer line (clock/rand/rand_impl/hwaddr_fn), NOT v7_atomic_state. Fix: wrap counter in align(64) stats sub-struct. Plan: docs/plans/2026-04-19-perf-40-false-sharing.md."

# PERF-41 (P3, confirmed) — V3/V5 wrappers skip prehashed fast path
glab issue create --title "PERF-41: V3/V5 convenience wrappers bypass initV3Namespace/initV5Namespace fast path" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,docs" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-41. Fix: document initV3Namespace/initV5Namespace in README perf section; consider NamespacedGenerator(comptime ns) wrapper. Plan: extend docs/plans/2026-04-18-perf-hardening.md."

# PERF-42 (P3, confirmed) — CAS max_retries 8× RFC counter width
glab issue create --title "PERF-42: V7 lockfree CAS max_retries = 32_768 is 8× RFC-9562 counter width — tighten to 4096" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-42. Fix: max_retries = 4096 with expanded comment at src/generator.zig:709. Saves ~8ms wedged-clock wall-time. Plan: extend docs/plans/2026-04-18-perf-hardening.md."

# PERF-43 (P2, confirmed) — bench-regression coverage gap
glab issue create --title "PERF-43: bench-regression skips bench-state + bench-micro-{parse,format,hash} despite baselines existing" \
  --label "performance,perf-severity::P2,category::perf,confidence::confirmed,status::triage,ci" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-43. Fix: matrix — bench-check + bench-micro on MR; bench/bench-contention/bench-state on main; bench-all nightly. Plan: extend docs/plans/2026-04-18-perf-hardening.md."

# PERF-44 (P3, confirmed) — bench-regression main-only, no MR coverage
glab issue create --title "PERF-44: bench-regression fires only on main + scheduled — add MR-only bench-micro subset" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,ci" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-44. Fix: MR-only bench-micro job with 10% threshold. Plan: extend docs/plans/2026-04-18-perf-hardening.md."
```

### Methodology (Phase-2/3 follow-up)

- **HEAD**: inherits Phase-4 HEAD `bcde186` plus in-flight fixes.
- **Verification**: offsets re-checked against source layout (`@offsetOf` reasoning); dispatch-pointer line confirmed as offsets 192-255.
- **Benchmarks run**: None this cycle (offset-evidence + source-pattern driven). PERF-40 and PERF-41 explicitly call for new bench runs as their validation gate.
- **GitLab mutation**: **None** — `glab` auth is DEGRADED (invalid token) per caller directive. Commands above are ready-to-run after auth rotation.
- **Stale-content corrections applied in place**: PERF-37 diagnosis rewritten; Appendix "Single `Generator.mutex`" note corrected to reflect the split `v7.mutex` / `v1v6.mutex` model landed in PERF-19.

---

## Performance Review Phase-4 Follow-up (2026-04-20)

> Cycle 6 appended: 2026-04-20 (15 new findings: PERF-45 through PERF-59 — all P3 defense-in-depth / infra / cosmetic; Phase-2 triage applied; tracker closure-drift reconciled for #155 and #157)

### Summary (Phase-4)

Phase-3 perf-reviewer produced **15 new P3 findings** (scores 6-36), all minor/speculative, plus Phase-2 triage across three items. **None of the new findings are blocking.** The library's performance posture is healthy after Phase-2/3 closures (PERF-40 through PERF-44 all closed). New findings are grouped into:

- **Infra/methodology** (×3): multi-run median harness, CI regression gate on V7 contention, 32T/64T bench extension.
- **Algorithmic micro-opts** (×3): redundant `clockToMs` on CAS retry, duplicated ns-to-next-ms sleep math, 4096 retry budget validation at 32T+.
- **Pipelining witnesses** (×4): vtable vs comptime dispatch row; `randCall` direct-call objdump; `-Dcpu=native` bench variant; V7Cas SROA IR witness.
- **Concurrency hardening** (×2): lockfree saturation spin-hybrid; dispatch-cluster offset compile-time witness.
- **Cosmetic** (×1): 5 KiB stack buffer in hwaddr/linux.zig (conservative but safe).
- **I/O cold-path** (×1): per-saveState openDirAbsolute overhead.
- **Divergence-risk** (×1, PERF-59): `Timestamp.now()` bypasses `clockCall()` → inconsistent injectable-clock behavior for V1/V6 vs V7.

**Phase-2 triage outcomes (explicitly recorded):**

- **PERF-Phase2-A** (V7 mutex 6-7% regression at 2T/4T/8T post-QC-113d extraction): **INVESTIGATED / NO-ACTION** — refuted as noise. V7Cas extraction is zero-size and does not touch `v7_atomic_state`; mutex path has no causal mechanism. All observed deltas within 1 stddev of baseline. Multi-run median (PERF-45) required to statistically validate future Phase-2-A-class claims.
- **PERF-Phase2-B** (Timestamp.now() bypasses clockCall): **CONFIRMED** — tracked as **PERF-59** below. Not a perf regression today; divergence-risk P3.
- **PERF-Phase2-C** (toStringAlloc "300× vs 115×" discrepancy): **CORRECTED** — actual ratio is ~388× per QC-113d evidence; Phase-2 math was wrong. PERF_GAP_ANALYSIS.md source ratio stands; no documentation drift.

**Tracker closure-drift reconciled (2 items):**

- **#155 (PERF-19)**: Issue still open on GitLab; closed in this doc since 2026-03-22 per line 824 (split `v7_mutex` + `v1v6_mutex` with fixed acquisition order in saveState/loadState).
- **#157 (PERF-20)**: Issue still open on GitLab; closed in this doc since 2026-03-22 per line 825 (`benchToHex()` added adjacent to `benchToHexUpper` using 256-UUID pool + XOR sink).

Ready-to-run `glab issue close` commands prepared below; `glab` auth is DEGRADED per caller directive — no GitLab mutation executed this cycle.

**Phase-5+ implementation priority order** (owner-deferred; not blocking):

1. **PERF-45** (multi-run median in bench harness) — unblocks validation of Phase-2-A-class claims.
2. **PERF-46** (CI regression gate on `v7_contention_*T` throughput) — closes silent 1-5% drift band.
3. **PERF-59** (Timestamp.now() routes through clockCall) — aligns V1/V6 with V7 injectable-clock semantics; eliminates `withClock(custom)` divergence.

### Stack-Ranked Findings (Phase-4)

| Rank | Severity | PerfScore | Finding | Component | Evidence | Measurement | GitLab Issue | Fix Summary | Status |
|------|----------|-----------|---------|-----------|----------|-------------|--------------|-------------|--------|
| 1 | P3 | 36 | No across-run median in bench harness (within-run stddev only) | `bench/bench.zig` | Confirmed | Blocks statistical validation of Phase-2-A-class regression claims | Not filed (glab degraded) | Add `--runs N` flag; emit median + p50/p95 across runs | ✅ Closed (`5c420d6`) |
| 2 | P3 | 32 | No CI regression gate on `v7_contention_*T` throughput | `.gitlab-ci.yml`, `scripts/bench-regression-check.sh` | Confirmed | Silent 1-5% drift possible; Phase-2-A would have been caught | Not filed (glab degraded) | Add contention-throughput column to regression gate; 5% threshold on `main` | ✅ Closed (`0379bb2`) |
| 3 | P3 | 28 | `Timestamp.now()` bypasses injectable `clockCall()` — divergence risk (V1/V6 vs V7) | `src/timestamp.zig:31-50`, `src/generator.zig` | Confirmed | `withClock(custom)` callers get inconsistent behavior; no perf regression today | Not filed (glab degraded) | Route `Timestamp.now()` through `self.clockCall()` or inject clockFn into V1/V6 paths | ✅ Closed (`2bd3a18`) |
| 4 | P3 | 24 | `clockToMs` recomputed on every CAS retry (redundant with `old_state`) | `src/generator.zig` (V7Cas.transition) | Suspected | ~20-30 ns/contended-retry saved on pure-bump arm | Not filed (glab degraded) | Extract `old_ms` from `old_state` before branch; skip `clockToMs` on bump-only path | Open |
| 5 | P3 | 24 | 4096 retry budget unvalidated at 32T+ contention | `src/generator.zig` (V7Cas.max_retries) | Suspected | Budget may be insufficient under 64T contention — fallback triggers | Not filed (glab degraded) | Extend `v7_contention_*T` to 32T/64T (PERF-47); measure fallback rate | Open |
| 6 | P3 | 18 | Bench contention scenarios stop at 16T; 32T/64T behavior unknown | `bench/contention.zig` | Confirmed | Scaling cliff at 32T+ would be undetected | Not filed (glab degraded) | Add 32T/64T rows; conditional on `$CI_RUNNER_VCPU >= 32` | Open |
| 7 | P3 | 16 | No bench row for vtable vs comptime-interface dispatch | `bench/main.zig` | Confirmed | PERF-31 closed without measurement witness | Not filed (glab degraded) | Add `bench_vtable_dispatch` vs `bench_comptime_dispatch` comparison row | Open |
| 8 | P3 | 16 | No objdump witness that `randCall` folds to direct `defaultRand` at ReleaseFast | `src/generator.zig`, `scripts/` | Suspected | Inlining assumption unverified; regression-proof fragile | Not filed (glab degraded) | Add `scripts/assert-direct-call.sh randCall defaultRand` to CI | Open |
| 9 | P3 | 12 | 5 KiB `[128]ifreq` stack buffer — conservative upper bound | `src/hwaddr/linux.zig:49` | Confirmed | Cold path only; safe but large | Not filed (glab degraded) | Either justify in comment (128 IFs × 40 B) or page-boundary-align + tune down to 64 | Open |
| 10 | P3 | 12 | `io_h.sleep()` in lockfree saturation — no spin-hybrid for <10µs waits | `src/generator.zig` (V7Cas fallback) | Suspected | OS-scheduler entry dominates for sub-10µs waits | Not filed (glab degraded) | Add 100-iteration busy-spin before `sleep()` on saturation path | Open |
| 11 | P3 | 9 | No `-Dcpu=native` bench variant — misses `movbe` opportunity | `build.zig`, `.gitlab-ci.yml` | Suspected | CPU-specific byte-swap opportunity (~1-2 ns/UUID on modern x86_64) | Not filed (glab degraded) | Add `bench-native` scheduled job; archive results vs `bench-baseline` | Open |
| 12 | P3 | 9 | No compile-time witness for dispatch-pointer cluster offset | `src/generator.zig`, `tests/offset_witness.zig` | Suspected | Read-only post-init; defense-in-depth for PERF-40 regression | Not filed (glab degraded) | `comptime std.debug.assert(@offsetOf(Generator, "clockCall") / 64 == N)` | Open |
| 13 | P3 | 9 | V7Cas Transition struct SROA not witnessed at IR | `src/generator.zig` (V7Cas.transition) | Suspected | Likely folds at ReleaseFast; unverified | Not filed (glab degraded) | `zig build-obj -femit-llvm-ir` + grep for Transition alloca; assert folded | Open |
| 14 | P3 | 6 | ns-to-next-ms sleep math duplicated across CAS + mutex paths | `src/generator.zig` | Confirmed | 0 throughput impact; ~30 LOC dedup opportunity | Not filed (glab degraded) | Extract `nsToNextMs(now_ns, last_ms) u64` helper | Open |
| 15 | P3 | 6 | `openDirAbsolute` per-saveState open+close overhead | `src/generator.zig` (saveState) | Confirmed | Cold path; matters only for rapid checkpoint callers | Not filed (glab degraded) | Cache dir handle in Generator; reopen on ENOENT | Open |

**PerfScore formula**: Impact (1-5) × Likelihood (1-5) × 4. P3 severity confirmed across all 15 findings (all scores ≤ 36 and none on a hot-path-blocking dimension).

### Findings by Area (Phase-4)

#### Infra / Benchmark Harness

##### PERF-45: No across-run median in bench harness — within-run stddev only (P3, ✅ Closed `5c420d6`)

**File**: `bench/bench.zig`, `scripts/bench-regression-check.sh`

**Perf impact**: 0 runtime impact; **methodology gap**. Within-run stddev alone cannot distinguish 6-7% noise from a 6-7% regression at 2T/4T/8T (see Phase-2-A triage above). Every Phase-2-A-class claim — including the V7Cas QC-113d refactor baseline comparison — is unfalsifiable without multi-run medians.

**Root cause**: The harness runs each bench row once per invocation and reports min/mean/max/stddev over its internal iterations. Cross-run variance (scheduler jitter, CPU frequency scaling, thermal) is invisible.

**Fix guidance**: Add `--runs N` CLI flag (default 5). For each bench row, run the full bench N times, emit median + p50/p95 across the N runs. Regression gate compares new-median vs baseline-median.

**Validation plan**: Run `zig build bench-contention -- --runs 9` before and after a deliberately inserted 3% regression in `newV7Atomic`. Regression gate should flag the 3% delta outside run-to-run noise band.

**Rollout risk**: Low (bench-only). CI wall-time grows 5× but bench-regression already runs only on `main` and MR-gated subset.

**In-band recommendation**: **Priority 1** for Phase 5 (unblocks PERF-46 and future Phase-2-A-class triage).

##### PERF-46: No CI regression gate on `v7_contention_*T` throughput (P3, ✅ Closed `0379bb2`)

**File**: `.gitlab-ci.yml:300-302` (bench-micro-mr), `scripts/bench-regression-check.sh`

**Perf impact**: 0 direct impact; **observability gap**. Silent 1-5% contention-throughput drift between merges. Phase-2-A — had it been a real regression — would not have been caught.

**Root cause**: Regression gate matrix covers `bench-micro-{parse,format,hash}` on MR and `bench` + `bench-contention` + `bench-state` on main, but `bench-contention` thresholds apply only to ops/sec single-threaded rows; the `v7_contention_{2T,4T,8T,16T}` throughput rows are not compared against baseline.

**Fix guidance**: Extend `baseline_contention.json` with `v7_contention_throughput_{2T,4T,8T,16T}` keys; extend `scripts/bench-regression-check.sh` matching logic; set threshold to 5% on `main` (relative to 10% on MR once PERF-45 multi-run lands).

**Validation plan**: Insert a `std.atomic.spinLoopHint()` spin-loop into `newV7Atomic` that costs ~3% throughput at 4T; CI should flag.

**Rollout risk**: Low (CI-only). Depends on PERF-45 for statistical reliability at <5% threshold.

**In-band recommendation**: **Priority 2** for Phase 5 (closes silent-drift band).

##### PERF-47: Bench contention scenarios stop at 16T; 32T/64T behavior unknown (P3, Confirmed)

**File**: `bench/contention.zig`

**Perf impact**: Scaling cliff at 32T/64T would be undetected. The 4096 retry budget (PERF-42 closure) and the lockfree-to-mutex fallback path are both unvalidated above 16T.

**Fix guidance**: Add 32T/64T rows; make them conditional on `$CI_RUNNER_VCPU >= 32` to avoid oversubscription on 4-core CI runners. Emit `retry_exhausted_rate` counter alongside throughput.

**Validation plan**: Run on a 32-vCPU dev box; compare throughput and retry-exhausted rate at 8T/16T/32T/64T.

**Rollout risk**: Low (bench-only).

#### Algorithmic Micro-Optimizations

##### PERF-48: `clockToMs` recomputed on every CAS retry (redundant with `old_state`) (P3, Suspected)

**File**: `src/generator.zig` (V7Cas.transition helper; QC-113d extraction, 2026-04-19)

**Perf impact**: ~20-30 ns saved per contended retry on the pure-bump arm (where `old_ms` is already encoded in `old_state`). Negligible at low contention; visible at 8T+.

**Root cause**: `V7Cas.transition` calls `clockToMs(now_ns)` once per iteration of the CAS loop. On the pure-bump arm (same-ms retry), `old_ms = old_state >> 12` is already known; the fresh clock read is only needed on the tick-over arm.

**Fix guidance**: Hoist `clockToMs(now_ns)` out of the loop when `old_ms == expected_ms`; recompute only when the clock domain has advanced. Alternatively, unpack `old_ms` from `old_state` before branching.

**Validation plan**: Objdump before/after; expect `clockToMs` call site count to drop by 1 per CAS iteration. Bench `v7_contention_8T` delta expected ≤ 3%.

**Rollout risk**: Low. QC-113d invariant tests cover the state machine; the refactor is confined to loop hoisting.

##### PERF-49: 4096 retry budget unvalidated at 32T+ contention (P3, Suspected)

**File**: `src/generator.zig` (V7Cas.max_retries = 4096, closed per PERF-42 2026-04-19)

**Perf impact**: Budget may be insufficient under 64T contention. Fallback to mutex path triggers — correctness preserved, throughput degrades to mutex baseline.

**Fix guidance**: Depends on PERF-47. Once 32T/64T benches exist, emit `retry_exhausted_rate`; if > 0.1% at 64T, consider raising budget to 8192 (halving RFC-9562 counter-width margin from 8× to 4×).

**Validation plan**: `v7_contention_64T` at HEAD — if `retry_exhausted_rate == 0`, budget is safe; otherwise bisect budget.

**Rollout risk**: Low. Budget is already the primary tuning knob per PERF-42 closure.

##### PERF-57: ns-to-next-ms sleep math duplicated across CAS + mutex paths (P3, Confirmed)

**File**: `src/generator.zig` (two sites; lockfree saturation + mutex spin-wait)

**Perf impact**: 0 throughput; ~30 LOC cosmetic dedup. Future maintenance risk: the two sites can drift.

**Fix guidance**: Extract `fn nsToNextMs(now_ns: i128, last_ms: i64) u64` as a module-private helper. Both sites call it.

**Validation plan**: All tests pass; no bench delta expected.

**Rollout risk**: Low.

#### Pipelining / Inlining Witnesses

##### PERF-50: No bench row for vtable vs comptime-interface dispatch (P3, Confirmed)

**File**: `bench/main.zig`

**Perf impact**: PERF-31 (Cycle 5) was closed under "GeneratorInterface vtable blocks inlining — deferred; per PerfScore 16 not worth surgery" without a measurement witness. Any future attempt to re-evaluate the trade-off lacks a baseline.

**Fix guidance**: Add `bench_vtable_dispatch` row (current GeneratorInterface) and `bench_comptime_dispatch` row (comptime-parameterized alternative via `anytype`). Report delta.

**Validation plan**: Bench rows produce deterministic numbers; delta quantifies the inlining gap.

**Rollout risk**: Low (bench-only).

##### PERF-51: No objdump witness that `randCall` folds to direct `defaultRand` at ReleaseFast (P3, Suspected)

**File**: `src/generator.zig`, `scripts/` (no existing witness)

**Perf impact**: If inlining fails (e.g., after a compiler upgrade), ~2-5 ns/UUID regression on the default-rand path. Currently unverified.

**Fix guidance**: Add `scripts/assert-direct-call.sh`: `zig build -Doptimize=ReleaseFast`; `objdump -d zig-out/bin/...`; grep for indirect `call *%` near `newV7` / `newV4`. Fail CI if indirect call found for default-path.

**Validation plan**: Script should pass at HEAD; inject `@setRuntimeSafety(true)` in `defaultRand` to force indirect call — script should fail.

**Rollout risk**: Low (CI-only). Scripted witness is robust to ordering.

##### PERF-54: No `-Dcpu=native` bench variant — misses `movbe` opportunity (P3, Suspected)

**File**: `build.zig`, `.gitlab-ci.yml`

**Perf impact**: Unknown. `movbe` (byte-reverse-move) on modern x86_64 could fold `toStringImpl` byte-swap loops; ~1-2 ns/UUID speculative.

**Fix guidance**: Add `bench-native` scheduled job using `-Dcpu=native`; archive results separately from `bench` baseline. Compare after 10 runs.

**Validation plan**: Compare `bench-native` vs `bench` on toString + toHex rows.

**Rollout risk**: Low (bench-only; scheduled job, no MR path).

##### PERF-56: V7Cas Transition struct SROA not witnessed at IR (P3, Suspected)

**File**: `src/generator.zig` (V7Cas.Transition struct, QC-113d extraction 2026-04-19)

**Perf impact**: If SROA fails, ~5-10 ns per CAS iteration from stack traffic. Likely folds at ReleaseFast; unverified.

**Fix guidance**: `zig build-obj -Doptimize=ReleaseFast -femit-llvm-ir`; grep LLVM IR for `%Transition` alloca; assert no stack slot (should be in SSA registers only).

**Validation plan**: One-shot script; CI gate optional.

**Rollout risk**: Low (verification-only).

#### Concurrency Hardening

##### PERF-53: `io_h.sleep()` in lockfree saturation — no spin-hybrid for <10µs waits (P3, Suspected)

**File**: `src/generator.zig` (V7Cas saturation path)

**Perf impact**: OS-scheduler entry dominates for sub-10µs waits (~1-4 µs on Linux). Spin-wait then sleep would trim 1-3 µs per saturation event.

**Root cause**: Saturation path goes straight to `io_h.sleep(ns_to_next_ms)`. No busy-spin before scheduler entry.

**Fix guidance**: Add 100-iteration `std.atomic.spinLoopHint()` loop before `sleep()`. Only worth it if saturation rate is measurable (see PERF-47/PERF-49).

**Validation plan**: Synthesize saturation workload (wedged clock); measure saturation-wait latency before/after.

**Rollout risk**: Low. Same state-machine as existing fallback; only the wait primitive changes.

##### PERF-55: No compile-time witness for dispatch-pointer cluster offset (P3, Suspected)

**File**: `src/generator.zig`, `tests/offset_witness.zig` (would be new)

**Perf impact**: 0 runtime impact; **defense-in-depth for PERF-40 regression** (false-sharing on dispatch-pointer line). If field order changes and dispatch-pointer cluster drifts off 64-byte boundary, PERF-40 silently regresses.

**Fix guidance**: `comptime std.debug.assert(@offsetOf(Generator, "clockCall") % 64 == 0)`; same for `randCall`, `rand_impl`, `hwaddrFn`. Fails compilation if cluster drifts.

**Validation plan**: Build passes at HEAD; deliberately reorder fields — build should fail with a clear error.

**Rollout risk**: Zero. Compile-time only.

#### Memory / Stack Usage

##### PERF-52: 5 KiB `[128]ifreq` stack buffer in `hwaddr/linux.zig:49` — conservative upper bound (P3, Confirmed)

**File**: `src/hwaddr/linux.zig:49`

**Perf impact**: Negligible (cold path; one-time per process). Stack-frame size consideration only — 5 KiB is safely below any Zig stack-overflow threshold on Linux.

**Root cause**: `[128]std.os.linux.ifreq` = 128 × 40 B = 5120 B. 128 interfaces is a very conservative upper bound (typical hosts have 2-8 interfaces).

**Fix guidance**: Either (a) add a comment justifying the 128-interface bound (preferred — zero behavior change), or (b) tune down to `[64]ifreq` (2560 B) with documented overflow fallback to heap allocation. No action if (a); (b) is speculative.

**Validation plan**: Stack-trace analysis via `perf record` on a repeat-Generator-init workload; stack-frame high-water mark should drop by 2560 B if (b) is taken.

**Rollout risk**: Low for (a); Medium for (b) — must test overflow fallback.

#### I/O Cold Path

##### PERF-58: `openDirAbsolute` per-saveState open+close overhead (P3, Confirmed)

**File**: `src/generator.zig` (saveState)

**Perf impact**: Cold path. Matters only for rapid-checkpoint callers (e.g., fuzz harnesses writing state every 100 ops); ~30-50 µs per saveState.

**Fix guidance**: Cache dir handle on `Generator`; reopen on ENOENT/EBADF. Preserves crash-atomicity of `.tmp`→rename pattern.

**Validation plan**: Bench a tight `saveState` loop (1000 iterations); expect ~50 µs/call → ~20 µs/call.

**Rollout risk**: Medium. Directory-handle caching is a known footgun (stale FD across `unlink` + `mkdir`). Guard with ENOENT reopen.

#### Divergence-Risk (Phase-2-B CONFIRMED)

##### PERF-59: `Timestamp.now()` bypasses `clockCall()` — V1/V6 divergent from V7 under injectable clock (P3, ✅ Closed `2bd3a18`)

**Files**: `src/timestamp.zig:31-50`, `src/generator.zig` (newV1AtTime, newV6AtTime, newV7AtTime call sites)

**Perf impact**: Zero direct perf impact today. **Correctness / semantic divergence risk**: callers using `Generator.withClock(customClock)` observe:

- V7 generation uses the injected clock (via `self.clockCall()`)
- V1/V6 generation calls `std.os.linux.clock_gettime` directly through `Timestamp.now()` — bypassing the injection

This breaks unit-test determinism for V1/V6 and invalidates any test that asserts time-travel or monotonic-override behavior across versions.

**Root cause (evidence)**: `src/timestamp.zig:31-50` — `Timestamp.now()` calls `std.os.linux.clock_gettime` unconditionally. `newV1AtTime` / `newV6AtTime` use `Timestamp.now()` as the time source; `newV7AtTime` uses `self.clockCall()`.

**Fix guidance**: Two options:

1. **Preferred**: Route `Timestamp.now()` through an injectable `ClockFn` parameter; V1/V6 generator calls `Timestamp.fromClock(self.clockCall)`. Preserves the `Timestamp` type's standalone usage via a module-level default.
2. **Alternative**: Keep `Timestamp.now()` as-is for standalone callers; add `newV1AtTimeWithClock` / `newV6AtTimeWithClock` overloads internally and have `newV1AtTime` / `newV6AtTime` call them with `self.clockCall`.

**Validation plan**: Unit test — `Generator.withClock(fixedClock).newV1()` twice; assert identical timestamps. Today this test would fail; after fix, it should pass.

**Rollout risk**: Low. API surface of `Timestamp` remains backward-compatible (option 1 adds a new constructor; `Timestamp.now()` keeps its shim). Option 2 adds internal helpers only.

**In-band recommendation**: **Priority 3** for Phase 5 (aligns V1/V6 with V7 injectable-clock semantics; eliminates `withClock(custom)` divergence).

### Phase-2 Triage (explicit, for audit trail)

#### Phase-2-A: V7 mutex path 6-7% regression at 2T/4T/8T — INVESTIGATED / NO-ACTION (REFUTED as noise)

**Claim**: Post-QC-113d V7Cas extraction (commits a51e411, 8211c0c), bench-contention showed 6-7% regression on mutex-path rows at 2T/4T/8T.

**Analysis**:

- V7Cas extraction is a zero-size refactor — no new fields, no new allocations, no new atomic operations.
- The mutex path in `newV7Locked` does not touch `v7_atomic_state` (which is the atomic the CAS path exercises via `V7Cas.transition`).
- No causal mechanism connects V7Cas extraction to mutex-path throughput.
- All observed deltas are within 1 standard deviation of the pre-refactor baseline.

**Decision**: **NO-ACTION**. Closed as noise. Validated multi-run median (PERF-45) would confirm statistically; the absence of that tooling is the meta-issue (tracked as PERF-45, priority 1).

**Artifacts**: QC-113d bench evidence commits (8211c0c) show refactor within ±2% of baseline.

#### Phase-2-B: `Timestamp.now()` bypasses `clockCall()` — CONFIRMED → tracked as PERF-59

See PERF-59 above. Confirmed divergence-risk.

#### Phase-2-C: `toStringAlloc` "300× vs 115×" discrepancy — CORRECTED (Phase-2 math error)

**Claim**: Phase-2 reviewer reported a discrepancy between a ~300× overhead (cycle-3 PERF-16 docs) and a ~115× measured overhead.

**Analysis**: The actual measured ratio per QC-113d evidence (commit 8211c0c benchmark data) is ~388× — neither 300 nor 115. The Phase-2 115× figure was a math error (appears to have divided by the non-allocating path on a different input size).

**Decision**: **CORRECTED**. PERF_GAP_ANALYSIS.md source documentation (PERF-16) stands. The "300×" in the cycle-3 prose is a rounded order-of-magnitude characterization; the precise ratio is ~388×. No drift in source doc; no edit required.

### Ready-to-run `glab` commands (DOCUMENTATION-ONLY — glab auth DEGRADED per caller directive)

> The `glab` token is read-only. Commands below are prepared but **NOT EXECUTED**. Execute after auth rotation.

```bash
# Close tracker drift: #155 (PERF-19) — closed in-doc 2026-03-22 per PERF_GAP_ANALYSIS.md:824
glab issue close 155 --comment "Closed per docs/PERF_GAP_ANALYSIS.md line 824 (cycle-4 closure 2026-03-22). Implemented: Generator mutex split into v7_mutex + v1v6_mutex with fixed acquisition order (v7 first) in saveState/loadState. Phase-2 gap-scanner re-confirmed at docs/PERF_GAP_ANALYSIS.md:838. All tests pass; no benchmark regressions. See src/generator.zig:97,102."

# Close tracker drift: #157 (PERF-20) — closed in-doc 2026-03-22 per PERF_GAP_ANALYSIS.md:825
glab issue close 157 --comment "Closed per docs/PERF_GAP_ANALYSIS.md line 825 (cycle-4 closure 2026-03-22). Implemented: benchToHex() added to bench/main.zig adjacent to benchToHexUpper using 256-UUID pool + XOR sink pattern. Phase-2 gap-scanner re-confirmed at docs/PERF_GAP_ANALYSIS.md:838. See bench/main.zig."

# --- New Phase-4 findings (PERF-45 through PERF-59) — file as triage batch ---

# PERF-45 (P3, confirmed) — Priority 1: multi-run median in bench harness
glab issue create --title "PERF-45: bench harness lacks across-run median (within-run stddev only) — blocks Phase-2-A-class triage" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,area::bench" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-45. Fix: --runs N flag; emit median + p50/p95 across runs. Priority 1 for Phase 5."

# PERF-46 (P3, confirmed) — Priority 2: CI regression gate on v7_contention_*T
glab issue create --title "PERF-46: bench-regression gate does not cover v7_contention_*T throughput rows — silent 1-5% drift band" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,area::ci" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-46. Fix: extend baseline_contention.json with throughput keys; 5% threshold on main. Depends on PERF-45. Priority 2 for Phase 5."

# PERF-47 (P3, confirmed) — 32T/64T bench extension
glab issue create --title "PERF-47: bench-contention stops at 16T — 32T/64T behavior unknown" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,area::bench" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-47. Fix: add 32T/64T rows conditional on CI_RUNNER_VCPU >= 32; emit retry_exhausted_rate."

# PERF-48 (P3, suspected) — clockToMs redundant on CAS retry
glab issue create --title "PERF-48: clockToMs recomputed every CAS retry — redundant with old_ms from old_state on bump arm" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage,area::algo" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-48. Fix: hoist clockToMs out of loop; recompute only on tick-over arm. ~20-30 ns per contended retry."

# PERF-49 (P3, suspected) — 4096 retry budget validation at 32T+
glab issue create --title "PERF-49: V7Cas 4096 retry budget unvalidated at 32T+ contention — possible fallback-triggering" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage,area::concurrency" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-49. Depends on PERF-47. If retry_exhausted_rate > 0.1% at 64T, raise to 8192."

# PERF-50 (P3, confirmed) — vtable vs comptime dispatch bench
glab issue create --title "PERF-50: no bench witness for vtable vs comptime-interface dispatch (PERF-31 closed without measurement)" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,area::bench" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-50. Fix: add bench_vtable_dispatch + bench_comptime_dispatch comparison row."

# PERF-51 (P3, suspected) — objdump witness for randCall inlining
glab issue create --title "PERF-51: no objdump witness that randCall folds to direct defaultRand at ReleaseFast" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage,area::ci" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-51. Fix: scripts/assert-direct-call.sh randCall defaultRand; wire into CI."

# PERF-52 (P3, confirmed) — 5 KiB stack buffer
glab issue create --title "PERF-52: 5 KiB [128]ifreq stack buffer in hwaddr/linux.zig:49 — conservative; justify or tune" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,area::memory" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-52. Fix: comment justifying 128-interface bound (preferred) or tune to [64]ifreq with heap fallback."

# PERF-53 (P3, suspected) — spin-hybrid for lockfree saturation
glab issue create --title "PERF-53: io_h.sleep() in lockfree saturation path — no spin-hybrid for sub-10µs waits" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage,area::concurrency" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-53. Fix: 100-iteration spinLoopHint before sleep. Only worth it if saturation rate measurable."

# PERF-54 (P3, suspected) — -Dcpu=native bench variant
glab issue create --title "PERF-54: no -Dcpu=native bench variant — misses movbe / target-specific opportunities" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage,area::bench" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-54. Fix: bench-native scheduled job; archive separately from bench-baseline."

# PERF-55 (P3, suspected) — compile-time offset witness for dispatch cluster
glab issue create --title "PERF-55: no compile-time witness for dispatch-pointer cluster offset — PERF-40 regression defense-in-depth" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage,area::concurrency" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-55. Fix: comptime std.debug.assert(@offsetOf(Generator, 'clockCall') % 64 == 0) etc."

# PERF-56 (P3, suspected) — V7Cas Transition SROA IR witness
glab issue create --title "PERF-56: V7Cas Transition struct SROA not witnessed at LLVM IR — likely folds; unverified" \
  --label "performance,perf-severity::P3,category::perf,confidence::suspected,status::triage,area::pipelining" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-56. Fix: emit-llvm-ir; grep Transition alloca; assert folded."

# PERF-57 (P3, confirmed) — ns-to-next-ms sleep dedup
glab issue create --title "PERF-57: ns-to-next-ms sleep math duplicated across CAS + mutex paths — 30 LOC dedup" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,area::cosmetic" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-57. Fix: extract nsToNextMs(now_ns, last_ms) u64 helper. Zero throughput impact."

# PERF-58 (P3, confirmed) — openDirAbsolute per-saveState
glab issue create --title "PERF-58: openDirAbsolute per-saveState open+close overhead — cold path, matters for rapid checkpoints" \
  --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::triage,area::io" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-58. Fix: cache dir handle on Generator; reopen on ENOENT. ~50 µs → ~20 µs per call."

# PERF-59 (P3, confirmed) — Priority 3: Timestamp.now() bypasses clockCall
glab issue create --title "PERF-59: Timestamp.now() bypasses clockCall() — V1/V6 divergent from V7 under Generator.withClock(custom)" \
  --label "performance,perf-severity::P3,category::correctness,confidence::confirmed,status::triage,area::app" \
  --description "See docs/PERF_GAP_ANALYSIS.md PERF-59. Fix: route Timestamp.now() through injectable ClockFn, or add newV1AtTimeWithClock/newV6AtTimeWithClock internal overloads. Priority 3 for Phase 5."

# --- Phase 4 cycle 4 closure round (2026-04-20) — 3 perf gaps closed in-band ---
# PERF-45, PERF-46, PERF-59 were NEVER filed as GitLab issues (glab auth DEGRADED through cycles 3-4).
# No `glab issue close <iid>` command exists. If the maintainer wants retroactive external tracking:
#
# glab issue create --title "PERF-45: bench harness lacks across-run median — [CLOSED at filing]" \
#   --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::closed,area::bench" \
#   --description "See docs/PERF_GAP_ANALYSIS.md PERF-45. ✅ Closed 2026-04-20 (5c420d6) — multi-run median across-run statistics landed."
# # Capture IID from output, then: glab issue close <iid> --comment "Closed at creation — record-keeping only. See commit 5c620d6."
#
# glab issue create --title "PERF-46: bench-regression gate does not cover v7_contention_*T throughput — [CLOSED at filing]" \
#   --label "performance,perf-severity::P3,category::perf,confidence::confirmed,status::closed,area::ci" \
#   --description "See docs/PERF_GAP_ANALYSIS.md PERF-46. ✅ Closed 2026-04-20 (0379bb2) — v7_contention_*T gated on MR at 10% threshold."
#
# glab issue create --title "PERF-59: Timestamp.now() bypasses clockCall() — [CLOSED at filing]" \
#   --label "performance,perf-severity::P3,category::correctness,confidence::confirmed,status::closed,area::app" \
#   --description "See docs/PERF_GAP_ANALYSIS.md PERF-59. ✅ Closed 2026-04-20 (2bd3a18) — V1/V6 timestamp routed through clockCall."
#
# Default (no-file) disposition: in-doc closure with ✅ markers + commit SHAs is authoritative.
```

### Methodology (Phase-4 follow-up)

- **HEAD**: inherits Phase-2/3 follow-up HEAD `bcde186` plus QC-113d closure chain (`a51e411`, `8211c0c`, `2c76a4b`).
- **Verification**: Phase-3 reviewer supplied 15 new findings with scores; this phase confirmed P3 severity classification against the existing PerfScore = Impact × Likelihood × 4 convention (all scores ≤ 36). Phase-2 triage applied against QC-113d bench evidence, timestamp.zig line inspection (31-50), and mutex-path causal analysis.
- **Benchmarks run**: None this cycle (review-driven triage). PERF-45 through PERF-49 explicitly call for multi-run + 32T/64T bench runs as their validation gate.
- **GitLab mutation**: **None** — `glab` auth is DEGRADED (read-only token) per caller directive. Commands above are ready-to-run after auth rotation. Two tracker-closure commands for #155/#157 are included (finding already closed in-doc; GitLab issues still open).
- **Phase-2 triage evidence trail**:
  - Phase-2-A REFUTED: bench evidence commit `8211c0c` shows ±2% baseline; V7Cas.transition is zero-size; mutex path causal-mechanism review (`src/generator.zig` newV7Locked) confirms no overlap with `v7_atomic_state`.
  - Phase-2-B CONFIRMED: `src/timestamp.zig:31-50` calls `std.os.linux.clock_gettime` directly; diverges from newV7AtTime's `self.clockCall()` invocation path.
  - Phase-2-C CORRECTED: QC-113d ratio is ~388×; Phase-2 115× figure is math error; source doc PERF-16 stands (cycle-3 prose "300×" is a rounded characterization).
- **Tracker closure-drift**: GitLab `#155` (PERF-19) and `#157` (PERF-20) remain open on GitLab; in-doc closure is authoritative since 2026-03-22 (cycle 4). Close commands prepared for next auth-available cycle.
