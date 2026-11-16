#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Interleaved same-runner A/B benchmark run for the bench-regression gate.
#
# Builds every benchmark suite for a reference release and for HEAD, then
# runs each suite for BENCH_ROUNDS rounds. Every round measures both sides
# back to back and alternates which side goes first (ref,HEAD / HEAD,ref ...),
# so contention from a shared runner lands on both sides instead of deciding
# the result. `scripts/bench_ab_gate.py --dir <out>` gates on the median of
# the per-round paired deltas (SONNY-6660).
#
# usage: scripts/bench_ab.sh <out-dir>
#
# Output: <out-dir>/REFS and
#   <out-dir>/rounds/baseline<suffix>.r<N>.json   reference, round N
#   <out-dir>/rounds/latest<suffix>.r<N>.json     HEAD, round N
#
# Environment:
#   BENCH_REF       reference to compare against. Default: the newest v* tag
#                   reachable from HEAD^, i.e. the previous release (so a
#                   tagged HEAD is still compared with the release before it).
#   BENCH_ROUNDS    rounds per suite, at least 3. Default 5.
#   BENCH_SUITES    space-separated subset of build steps to run. Default all.
#   BENCH_READY_FILE  optional path touched once both sides are built, just
#                   before round 1 (lets a caller start work alongside the
#                   measurements only, e.g. the self-test's CPU load).
#   TASKSET_PREFIX  optional CPU-pinning prefix (see INV-01 in .gitlab-ci.yml).
#
# HEAD is the working tree, so uncommitted edits are measured. The reference
# is measured with its own benchmark harness.
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <out-dir>" >&2
    exit 2
fi

root=$(git rev-parse --show-toplevel)
mkdir -p "$1/rounds"
out=$(cd "$1" && pwd)
rounds=${BENCH_ROUNDS:-5}
taskset_prefix=${TASKSET_PREFIX:-}
if ! [ "$rounds" -ge 3 ] 2>/dev/null; then
    echo "BENCH_ROUNDS must be an integer >= 3 (got '$rounds')" >&2
    exit 2
fi

ref=${BENCH_REF:-$(git -C "$root" describe --tags --abbrev=0 --match 'v[0-9]*' HEAD^)}
ref_sha=$(git -C "$root" rev-parse --verify "${ref}^{commit}")
head_sha=$(git -C "$root" rev-parse HEAD)

ref_dir=$(mktemp -d "${TMPDIR:-/tmp}/bench-ref.XXXXXX")
cleanup() {
    git -C "$root" worktree remove --force "$ref_dir" >/dev/null 2>&1 || rm -rf "$ref_dir"
}
trap cleanup EXIT
# bash skips the EXIT trap when a signal kills it (e.g. a cancelled CI job).
trap 'exit 130' INT
trap 'exit 143' TERM
git -C "$root" worktree add --quiet --detach "$ref_dir" "$ref_sha"

printf 'reference %s (%s)\nhead      %s\nhost      %s, nproc=%s\nrounds    %s\n' \
    "$ref" "$ref_sha" "$head_sha" \
    "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || uname -m)" \
    "$(nproc)" "$rounds" | tee "$out/REFS"

# step : output suffix
suites=(
    "bench:"
    "bench-contention:_contention"
    "bench-state:_state"
    "bench-micro-parse:_micro_parse"
    "bench-micro-format:_micro_format"
    "bench-micro-hash:_micro_hash"
)

selected() {
    [ -z "${BENCH_SUITES:-}" ] && return 0
    case " $BENCH_SUITES " in *" $1 "*) return 0 ;; esac
    return 1
}

run_suite() {
    local dir=$1 step=$2 output=$3
    # shellcheck disable=SC2086 # taskset_prefix is a word list
    (cd "$dir" && $taskset_prefix zig build "$step" -Doptimize=ReleaseFast -- --output "$output")
}

has_step() {
    (cd "$1" && zig build -l 2>/dev/null | grep -qE "^  $2( |$)")
}

# Compile every benchmark executable for both sides up front, so round 1
# doesn't include a cold build and the rounds reuse cached binaries.
for dir in "$ref_dir" "$root"; do
    if has_step "$dir" bench-check; then
        echo "== build: $([ "$dir" = "$root" ] && echo HEAD || echo "$ref")"
        (cd "$dir" && zig build bench-check -Doptimize=ReleaseFast)
    fi
done
if [ -n "${BENCH_READY_FILE:-}" ]; then
    touch "$BENCH_READY_FILE"
fi

for entry in "${suites[@]}"; do
    IFS=: read -r step suffix <<<"$entry"
    selected "$step" || continue
    if ! has_step "$ref_dir" "$step"; then
        echo "== $step: not defined at $ref; skipped"
        continue
    fi
    for n in $(seq 1 "$rounds"); do
        ref_out=$out/rounds/baseline$suffix.r$n.json
        head_out=$out/rounds/latest$suffix.r$n.json
        if [ $((n % 2)) -eq 1 ]; then
            echo "== $step round $n/$rounds: $ref, HEAD"
            run_suite "$ref_dir" "$step" "$ref_out"
            run_suite "$root" "$step" "$head_out"
        else
            echo "== $step round $n/$rounds: HEAD, $ref"
            run_suite "$root" "$step" "$head_out"
            run_suite "$ref_dir" "$step" "$ref_out"
        fi
    done
done
