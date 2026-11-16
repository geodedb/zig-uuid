#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Regression gate over interleaved A/B benchmark rounds (SONNY-6660).

scripts/bench_ab.sh writes one result document per side per round:

    <dir>/rounds/baseline<suffix>.r<N>.json   (reference release)
    <dir>/rounds/latest<suffix>.r<N>.json     (HEAD)

Rounds alternate which side runs first, so each round is a pair measured
seconds apart on the same machine. For every scenario (matched on
scenario_name, variant and thread_count) the gate takes the paired delta of
each round, `head / reference - 1`, and decides on their median:

* FAIL when median < -gate, where gate = max(threshold, 3 * SE) and SE is a
  robust standard error of that median: 1.2533 * 1.4826 * MAD / sqrt(rounds).
  A single disturbed round moves the median by at most one rank, so it can't
  fail the gate on its own; a consistent slowdown fails it.
* NOISY marks scenarios whose spread forced the gate above the threshold:
  the rounds disagree too much to resolve a change of that size.
* Suites whose file name contains a --warn-only substring (e.g. the
  fsync-bound `state` suite) report WARN instead of FAIL.

Throughput is `across_run_median_ops_per_sec` when present, else
`throughput_ops_per_sec`. Exit status: 0 pass, 1 regression, 2 bad input.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path

MIN_ROUNDS = 3
ROUND_FILE = re.compile(r"^(baseline|latest)(.*)\.r(\d+)\.json$")
MAD_TO_SIGMA = 1.4826  # MAD -> standard deviation for normal data
MEDIAN_SE = 1.2533  # standard error of the median, in units of sigma/sqrt(n)
SE_MULTIPLIER = 3.0


class GateError(Exception):
    """Input is missing or inconsistent; the gate can't reach a verdict."""


@dataclass
class Result:
    suite: str
    scenario: str
    variant: str
    threads: int
    deltas: list[float]
    median_delta: float
    gate: float
    noisy: bool
    status: str  # PASS | FAIL | WARN

    def line(self) -> str:
        rounds = " ".join(f"{d * 100:+.1f}" for d in self.deltas)
        flag = "  NOISY" if self.noisy else ""
        return (
            f"  {self.scenario}/{self.variant}/{self.threads}T median {self.median_delta * 100:+.2f}%"
            f"  gate {self.gate * 100:.2f}%  rounds [{rounds}]  {self.status}{flag}"
        )


@dataclass
class Report:
    results: list[Result] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    @property
    def failed(self) -> bool:
        return any(r.status == "FAIL" for r in self.results)

    def render(self) -> str:
        out, suite = [], None
        for r in self.results:
            if r.suite != suite:
                suite = r.suite
                out.append(f"== {suite or '(bench)'} ==")
            out.append(r.line())
        out.extend(self.notes)
        fails = sum(r.status == "FAIL" for r in self.results)
        noisy = sum(r.noisy for r in self.results)
        out.append(
            f"bench-ab-gate: {len(self.results)} scenarios, {fails} FAIL, {noisy} NOISY"
        )
        return "\n".join(out)


def throughput(row: dict) -> float:
    value = row.get("across_run_median_ops_per_sec")
    if value is None:
        value = row["throughput_ops_per_sec"]
    return float(value)


def load_rows(path: Path) -> dict[tuple, float]:
    try:
        rows = json.loads(path.read_text())["rows"]
    except (OSError, ValueError, KeyError) as exc:
        raise GateError(f"{path}: unreadable result document ({exc})") from exc
    return {
        (r["scenario_name"], r["variant"], int(r["thread_count"])): throughput(r)
        for r in rows
    }


def collect(directory: Path) -> dict[str, dict[int, dict[str, Path]]]:
    """suite suffix -> round -> side -> file."""
    rounds_dir = directory / "rounds"
    suites: dict[str, dict[int, dict[str, Path]]] = {}
    for path in sorted(rounds_dir.glob("*.json")) if rounds_dir.is_dir() else []:
        m = ROUND_FILE.match(path.name)
        if m:
            side, suffix, n = m.group(1), m.group(2), int(m.group(3))
            suites.setdefault(suffix, {}).setdefault(n, {})[side] = path
    if not suites:
        raise GateError(f"no round files under {rounds_dir}")
    return suites


def judge(
    deltas: list[float], threshold: float, warn_only: bool
) -> tuple[float, float, bool, str]:
    med = statistics.median(deltas)
    mad = statistics.median(abs(d - med) for d in deltas)
    se = MEDIAN_SE * MAD_TO_SIGMA * mad / math.sqrt(len(deltas))
    gate = max(threshold, SE_MULTIPLIER * se)
    status = "PASS"
    if med < -gate:
        status = "WARN" if warn_only else "FAIL"
    return med, gate, gate > threshold, status


def evaluate_dir(
    directory: Path, threshold: float = 0.15, warn_only: list[str] | None = None
) -> Report:
    warn_only = warn_only or []
    report = Report()
    for suffix, rounds in sorted(collect(Path(directory)).items()):
        numbers = sorted(rounds)
        if numbers != list(range(1, len(numbers) + 1)):
            raise GateError(f"suite '{suffix}': rounds {numbers} are not 1..N")
        if len(numbers) < MIN_ROUNDS:
            raise GateError(
                f"suite '{suffix}': {len(numbers)} rounds, need at least {MIN_ROUNDS}"
            )
        pairs = []
        for n in numbers:
            sides = rounds[n]
            if set(sides) != {"baseline", "latest"}:
                raise GateError(
                    f"suite '{suffix}' round {n}: missing {({'baseline', 'latest'} - set(sides)).pop()}"
                )
            pairs.append((load_rows(sides["baseline"]), load_rows(sides["latest"])))
        common = set.intersection(*(set(b) & set(h) for b, h in pairs))
        every = set.union(*(set(b) | set(h) for b, h in pairs))
        for key in sorted(every - common):
            report.notes.append(
                f"  SKIP {suffix or '(bench)'} {key[0]}/{key[1]}/{key[2]}T: not in every round on both sides"
            )
        is_warn = any(w in f"baseline{suffix}" for w in warn_only)
        for key in sorted(common):
            deltas = [h[key] / b[key] - 1.0 for b, h in pairs]
            med, gate, noisy, status = judge(deltas, threshold, is_warn)
            report.results.append(
                Result(
                    suffix.lstrip("_"),
                    key[0],
                    key[1],
                    key[2],
                    deltas,
                    med,
                    gate,
                    noisy,
                    status,
                )
            )
    return report


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--dir", required=True, type=Path, help="bench_ab.sh output directory"
    )
    ap.add_argument(
        "--threshold",
        type=float,
        default=0.15,
        help="regression threshold (fraction, default 0.15)",
    )
    ap.add_argument(
        "--warn-only",
        action="append",
        default=[],
        metavar="SUBSTR",
        help="suites whose file name contains SUBSTR only WARN (repeatable)",
    )
    args = ap.parse_args(argv)
    try:
        report = evaluate_dir(args.dir, args.threshold, args.warn_only)
    except GateError as exc:
        print(f"bench-ab-gate: error: {exc}", file=sys.stderr)
        return 2
    print(report.render())
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())
