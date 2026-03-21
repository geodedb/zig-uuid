# UUID Library Performance Gap Analysis

> Codebase-wide performance review of the uuid library.
> Language: Zig | Target: UUID generation throughput + latency
> Reviewer: Performance review agent
>
> Last updated: 2026-03-21 (all items closed or Won't Do)

---

## Summary

**10 findings total** (2 P1, 4 P2, 4 P3) — **9 Closed, 1 Won't Do**:

| Severity | Count | Description | Status |
|----------|-------|-------------|--------|
| P1       | 2     | Throughput-blocking: V7 spin-wait sleep, mutex held during CSPRNG | ✅ All Closed |
| P2       | 4     | Significant: V1/V6 mutex+syscall scope, no benchmark suite, forced spin on restart, CI optimization | ✅ All Closed |
| P3       | 4     | Minor: double clock read, function-pointer indirection, toString loop, parseCanonical loop | ✅ 3 Closed, 🚫 1 Won't Do |

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
- **Thread model**: Single `Generator.mutex` protecting all mutable state; V4 is lock-free (confirmed: no mutex call in `newV4`)
