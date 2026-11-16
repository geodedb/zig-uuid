#!/usr/bin/env python3
"""SONNY-6660: the bench-regression A/B gate must not be decided by noise.

Two layers:

* Synthetic tests (always run, a few milliseconds): feed hand-built
  per-round result documents to scripts/bench_ab_gate.py and check the
  verdicts. A one-off slow round on identical code must pass; a consistent
  slowdown must fail even with an outlier round.

* End-to-end tests (opt-in with BENCH_AB_E2E=1, minutes): run the real
  scripts/bench_ab.sh + gate on this checkout while CPU burners contend for
  the benchmark cores. Identical trees must pass; a tree with a slowdown
  injected into UUID.fromString must fail on the parse scenarios.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import bench_ab_gate as gate


def row(name, ops, variant="default", threads=1):
    return {
        "scenario_name": name,
        "variant": variant,
        "thread_count": threads,
        "throughput_ops_per_sec": float(ops),
        "throughput_stddev_ops_per_sec": 0.0,
    }


def write_rounds(directory, suffix, ref_rounds, head_rounds):
    """ref_rounds/head_rounds: list (one entry per round) of {name: ops}."""
    rounds = Path(directory) / "rounds"
    rounds.mkdir(parents=True, exist_ok=True)
    for i, (ref, head) in enumerate(zip(ref_rounds, head_rounds), start=1):
        for side, data in (("baseline", ref), ("latest", head)):
            doc = {
                "generated_at_unix_s": 0,
                "rows": [row(n, v) for n, v in data.items()],
            }
            (rounds / f"{side}{suffix}.r{i}.json").write_text(json.dumps(doc))


def scaled(base, factors):
    """One round per factor: every scenario in `base` multiplied by it."""
    return [{n: v * f for n, v in base.items()} for f in factors]


BASE = {"parse_invalid_reject": 25_000_000.0, "parse_canonical_latency": 21_000_000.0}
SAME = [1.0] * 5


class SyntheticGate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="bench-ab-gate-")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def evaluate(self, threshold=0.15, warn_only=("state",)):
        return gate.evaluate_dir(
            Path(self.tmp), threshold=threshold, warn_only=list(warn_only)
        )

    def verdict(self, report, scenario):
        [res] = [r for r in report.results if r.scenario == scenario]
        return res

    def test_identical_trees_with_one_disturbed_round_pass(self):
        # The two noise failures seen on main: one round of HEAD at -15% and -52%.
        head = scaled(BASE, [1.0, 1.0, 0.48, 1.0, 1.0])
        head[1]["parse_canonical_latency"] *= 0.845
        write_rounds(self.tmp, "_micro_parse", scaled(BASE, SAME), head)
        report = self.evaluate()
        self.assertFalse(report.failed, report.render())
        self.assertEqual(self.verdict(report, "parse_invalid_reject").status, "PASS")

    def test_consistent_regression_fails(self):
        head = scaled(BASE, [0.80, 0.79, 0.81, 0.80, 0.78])
        write_rounds(self.tmp, "_micro_parse", scaled(BASE, SAME), head)
        report = self.evaluate()
        self.assertTrue(report.failed)
        res = self.verdict(report, "parse_invalid_reject")
        self.assertEqual(res.status, "FAIL")
        self.assertAlmostEqual(res.median_delta, -0.20, places=2)

    def test_consistent_regression_with_an_outlier_round_still_fails(self):
        head = scaled(BASE, [0.80, 0.79, 0.81, 1.40, 0.80])
        write_rounds(self.tmp, "_micro_parse", scaled(BASE, SAME), head)
        self.assertEqual(
            self.verdict(self.evaluate(), "parse_invalid_reject").status, "FAIL"
        )

    def test_threshold_boundary(self):
        write_rounds(
            self.tmp,
            "_micro_parse",
            scaled(BASE, SAME),
            scaled(BASE, [0.84, 0.84, 0.84, 0.84, 0.84]),
        )
        self.assertEqual(
            self.verdict(self.evaluate(), "parse_invalid_reject").status, "FAIL"
        )
        shutil.rmtree(self.tmp)
        os.mkdir(self.tmp)
        write_rounds(
            self.tmp,
            "_micro_parse",
            scaled(BASE, SAME),
            scaled(BASE, [0.86, 0.86, 0.86, 0.86, 0.86]),
        )
        self.assertEqual(
            self.verdict(self.evaluate(), "parse_invalid_reject").status, "PASS"
        )

    def test_zero_mean_noise_passes(self):
        head = scaled(BASE, [0.72, 1.25, 0.95, 1.12, 0.86])
        write_rounds(self.tmp, "_micro_parse", scaled(BASE, SAME), head)
        self.assertFalse(self.evaluate().failed)

    def test_wide_dispersion_widens_the_gate_and_is_flagged(self):
        # Median -18% but the rounds disagree wildly: inconclusive, not a FAIL.
        head = scaled(BASE, [0.60, 0.75, 0.82, 0.90, 1.30])
        write_rounds(self.tmp, "_micro_parse", scaled(BASE, SAME), head)
        res = self.verdict(self.evaluate(), "parse_invalid_reject")
        self.assertEqual(res.status, "PASS")
        self.assertTrue(res.noisy)
        self.assertGreater(res.gate, 0.15)

    def test_improvement_passes(self):
        write_rounds(
            self.tmp, "_micro_parse", scaled(BASE, SAME), scaled(BASE, [1.5] * 5)
        )
        self.assertFalse(self.evaluate().failed)

    def test_reference_noise_is_paired_out(self):
        # Load hits both sides of each round equally: paired deltas stay ~0.
        ref = scaled(BASE, [1.0, 0.5, 1.0, 0.6, 1.0])
        head = scaled(BASE, [1.01, 0.5, 0.99, 0.6, 1.0])
        write_rounds(self.tmp, "_micro_parse", ref, head)
        self.assertFalse(self.evaluate().failed)

    def test_warn_only_suite_never_fails(self):
        write_rounds(self.tmp, "_state", scaled(BASE, SAME), scaled(BASE, [0.5] * 5))
        report = self.evaluate()
        self.assertFalse(report.failed)
        self.assertEqual(self.verdict(report, "parse_invalid_reject").status, "WARN")

    def test_matches_rows_on_variant_and_thread_count(self):
        rounds = Path(self.tmp) / "rounds"
        rounds.mkdir()
        for i in range(1, 6):
            for side, slow in (("baseline", 1.0), ("latest", 0.5)):
                doc = {
                    "generated_at_unix_s": 0,
                    "rows": [
                        row("v7_contention", 100.0, "mutex", 2),
                        row("v7_contention", 100.0 * slow, "mutex", 16),
                    ],
                }
                (rounds / f"{side}_contention.r{i}.json").write_text(json.dumps(doc))
        report = self.evaluate()
        by_key = {(r.variant, r.threads): r.status for r in report.results}
        self.assertEqual(by_key, {("mutex", 2): "PASS", ("mutex", 16): "FAIL"})

    def test_prefers_across_run_median_when_present(self):
        rounds = Path(self.tmp) / "rounds"
        rounds.mkdir()
        for i in range(1, 6):
            for side, med in (("baseline", 100.0), ("latest", 50.0)):
                r = row("x", 100.0)  # single-invocation number is equal...
                r["across_run_median_ops_per_sec"] = (
                    med  # ...the across-run median is not
                )
                (rounds / f"{side}.r{i}.json").write_text(
                    json.dumps({"generated_at_unix_s": 0, "rows": [r]})
                )
        self.assertTrue(self.evaluate().failed)

    def test_too_few_rounds_is_an_error(self):
        write_rounds(
            self.tmp, "_micro_parse", scaled(BASE, [1.0, 1.0]), scaled(BASE, [1.0, 1.0])
        )
        with self.assertRaises(gate.GateError):
            self.evaluate()

    def test_missing_round_file_is_an_error(self):
        write_rounds(self.tmp, "_micro_parse", scaled(BASE, SAME), scaled(BASE, SAME))
        (Path(self.tmp) / "rounds" / "latest_micro_parse.r3.json").unlink()
        with self.assertRaises(gate.GateError):
            self.evaluate()

    def test_no_rounds_is_an_error(self):
        with self.assertRaises(gate.GateError):
            self.evaluate()

    def test_cli_exit_codes(self):
        write_rounds(
            self.tmp, "_micro_parse", scaled(BASE, SAME), scaled(BASE, [0.7] * 5)
        )
        cmd = [
            sys.executable,
            str(ROOT / "scripts/bench_ab_gate.py"),
            "--dir",
            self.tmp,
            "--threshold",
            "0.15",
        ]
        failed = subprocess.run(cmd, capture_output=True, text=True, check=False)
        self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
        self.assertIn("FAIL", failed.stdout)
        shutil.rmtree(self.tmp)
        os.mkdir(self.tmp)
        write_rounds(self.tmp, "_micro_parse", scaled(BASE, SAME), scaled(BASE, SAME))
        passed = subprocess.run(cmd, capture_output=True, text=True, check=False)
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)


# --------------------------------------------------------------------------
# End-to-end: real benchmarks, real contention.
# --------------------------------------------------------------------------

E2E = os.environ.get("BENCH_AB_E2E") == "1"
E2E_SUITES = os.environ.get(
    "BENCH_AB_E2E_SUITES", "bench-micro-parse bench-micro-format"
)

# Spin injected at the top of UUID.fromString for the slowdown case. The
# volatile store keeps the loop from being optimised out.
SLOWDOWN = (
    "        { var spin: u32 = 0; while (spin < 16) : (spin += 1) "
    "std.mem.doNotOptimizeAway(&spin); }\n"
)


def burner_cores():
    prefix = os.environ.get("TASKSET_PREFIX", "")
    if "-c" in prefix.split():
        spec = prefix.split()[prefix.split().index("-c") + 1]
        lo, _, hi = spec.partition("-")
        return list(range(int(lo), int(hi or lo) + 1))
    return sorted(os.sched_getaffinity(0))


def cgroup_cpu_quota():
    """CPUs granted by a cgroup v2 `cpu.max` quota, or None when unlimited."""
    try:
        quota, period = Path("/sys/fs/cgroup/cpu.max").read_text().split()
    except (OSError, ValueError):
        return None
    if quota == "max":
        return None
    return int(quota) / int(period)


class CpuLoad:
    """Bursty CPU burners pinned to the benchmark cores.

    Up to two burners per core, each spinning ~2 s then idling ~1 s with
    staggered phases, so benchmark runs land in contended windows unevenly on
    base and HEAD, like a shared runner. Under a cgroup CPU quota the burner
    count stays below the quota: past it, CFS throttling would stall the
    whole container (benchmarks included) instead of contending with it."""

    PER_CORE = 2
    SCRIPT = (
        "import os, sys, time\n"
        "os.sched_setaffinity(0, {int(sys.argv[1])})\n"
        "time.sleep(float(sys.argv[2]))\n"
        "while True:\n"
        "    end = time.monotonic() + 2.0\n"
        "    while time.monotonic() < end: pass\n"
        "    time.sleep(1.0)\n"
    )

    def __init__(self, cores):
        self.cores = cores
        self.procs = []
        count = self.PER_CORE * len(cores)
        quota = cgroup_cpu_quota()
        if quota is not None:
            count = min(count, max(1, int(quota) - 1))
        self.count = count
        print(
            f"\nCpuLoad: {count} burners on cores {cores[0]}-{cores[-1]} "
            f"(cgroup quota: {'none' if quota is None else f'{quota:g} CPUs'})",
            flush=True,
        )

    def __enter__(self):
        for i in range(self.count):
            core = self.cores[i % len(self.cores)]
            phase = (0.37 * i) % 3.0
            self.procs.append(
                subprocess.Popen(
                    [sys.executable, "-c", self.SCRIPT, str(core), str(phase)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            )
        return self

    def __exit__(self, *exc):
        for p in self.procs:
            p.kill()
        for p in self.procs:
            p.wait()


def run_ab(tree, ref, out, rounds):
    """Measure `tree` (as HEAD) against `ref` with this checkout's bench_ab.sh,
    with CPU load running during the measurement rounds only.

    The script takes HEAD from its working directory, so running it with
    cwd=tree benchmarks that tree's working copy. It touches the ready file
    once both sides are built; the load starts then, not during compilation."""
    ready = Path(out).parent / f"{Path(out).name}.ready"
    env = dict(
        os.environ,
        BENCH_REF=ref,
        BENCH_SUITES=E2E_SUITES,
        BENCH_ROUNDS=str(rounds),
        BENCH_READY_FILE=str(ready),
    )
    proc = subprocess.Popen(
        ["bash", str(ROOT / "scripts/bench_ab.sh"), str(out)], cwd=tree, env=env
    )
    try:
        while not ready.exists() and proc.poll() is None:
            time.sleep(0.5)
        if proc.poll() is None:
            with CpuLoad(burner_cores()):
                proc.wait()
        else:
            proc.wait()
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, proc.args)
    return gate.evaluate_dir(out, threshold=0.15, warn_only=["state"])


@unittest.skipUnless(E2E, "set BENCH_AB_E2E=1 to run the benchmark end-to-end tests")
class EndToEnd(unittest.TestCase):
    rounds = int(os.environ.get("BENCH_AB_E2E_ROUNDS", "5"))

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="bench-ab-e2e-"))
        self.head = subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_identical_trees_pass_under_cpu_load(self):
        report = run_ab(ROOT, self.head, self.tmp / "out", self.rounds)
        print("\n" + report.render(), flush=True)
        self.assertFalse(report.failed, report.render())

    def test_injected_slowdown_fails_under_cpu_load(self):
        slow = self.tmp / "slow-tree"
        subprocess.run(
            [
                "git",
                "-C",
                str(ROOT),
                "worktree",
                "add",
                "--quiet",
                "--detach",
                str(slow),
                self.head,
            ],
            check=True,
        )
        try:
            src = slow / "src/uuid.zig"
            text = src.read_text()
            anchor = "    pub fn fromString(s: []const u8) Error!UUID {\n"
            self.assertEqual(
                text.count(anchor),
                1,
                "fromString signature moved; update the e2e anchor",
            )
            src.write_text(text.replace(anchor, anchor + SLOWDOWN))
            report = run_ab(slow, self.head, self.tmp / "out", self.rounds)
        finally:
            subprocess.run(
                ["git", "-C", str(ROOT), "worktree", "remove", "--force", str(slow)],
                check=False,
            )
        print("\n" + report.render(), flush=True)
        self.assertTrue(report.failed, report.render())
        failed = {r.scenario for r in report.results if r.status == "FAIL"}
        self.assertTrue(any(s.startswith("parse_") for s in failed), failed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
