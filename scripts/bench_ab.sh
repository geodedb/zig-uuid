#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Same-runner A/B benchmark run for the bench-regression gate.
#
# Builds and runs every benchmark suite twice in one job, on one machine:
# once for a reference release (written as baseline*.json) and once for
# HEAD (written as latest*.json). `zig build bench-compare-all -- --dir <out>`
# then gates HEAD against a reference measured on the same hardware, minutes
# apart, instead of against committed numbers from an unknown machine.
#
# usage: scripts/bench_ab.sh <out-dir>
#
# Environment:
#   BENCH_REF       reference to compare against. Default: the newest v* tag
#                   reachable from HEAD^, i.e. the previous release (so a
#                   tagged HEAD is still compared with the release before it).
#   BENCH_RUNS      --runs value for suites that support across-run medians
#                   (bench, bench-contention). Default 3.
#   TASKSET_PREFIX  optional CPU-pinning prefix (see INV-01 in .gitlab-ci.yml).
#
# Each suite runs reference-then-HEAD back to back so both sides see the same
# machine state. The reference is measured with its own benchmark harness.
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <out-dir>" >&2
    exit 2
fi

root=$(git rev-parse --show-toplevel)
mkdir -p "$1"
out=$(cd "$1" && pwd)
runs=${BENCH_RUNS:-3}
taskset_prefix=${TASKSET_PREFIX:-}

ref=${BENCH_REF:-$(git -C "$root" describe --tags --abbrev=0 --match 'v[0-9]*' HEAD^)}
ref_sha=$(git -C "$root" rev-parse --verify "${ref}^{commit}")
head_sha=$(git -C "$root" rev-parse HEAD)

ref_dir=$(mktemp -d "${TMPDIR:-/tmp}/bench-ref.XXXXXX")
cleanup() {
    git -C "$root" worktree remove --force "$ref_dir" >/dev/null 2>&1 || rm -rf "$ref_dir"
}
trap cleanup EXIT
git -C "$root" worktree add --quiet --detach "$ref_dir" "$ref_sha"

printf 'reference %s (%s)\nhead      %s\nhost      %s, nproc=%s\n' \
    "$ref" "$ref_sha" "$head_sha" \
    "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || uname -m)" \
    "$(nproc)" | tee "$out/REFS"

# step : output suffix : extra args
suites=(
    "bench::--runs $runs"
    "bench-contention:_contention:--runs $runs"
    "bench-state:_state:"
    "bench-micro-parse:_micro_parse:"
    "bench-micro-format:_micro_format:"
    "bench-micro-hash:_micro_hash:"
)

run_suite() {
    local dir=$1 step=$2 output=$3 extra=$4
    # shellcheck disable=SC2086 # taskset_prefix and extra are word lists
    (cd "$dir" && $taskset_prefix zig build "$step" -Doptimize=ReleaseFast -- --output "$output" $extra)
}

for entry in "${suites[@]}"; do
    IFS=: read -r step suffix extra <<<"$entry"
    if ! (cd "$ref_dir" && zig build -l 2>/dev/null | grep -qE "^  $step( |$)"); then
        echo "== $step: not defined at $ref; skipped (no baseline$suffix.json)"
        continue
    fi
    echo "== $step: $ref"
    run_suite "$ref_dir" "$step" "$out/baseline$suffix.json" "$extra"
    echo "== $step: HEAD"
    run_suite "$root" "$step" "$out/latest$suffix.json" "$extra"
done
