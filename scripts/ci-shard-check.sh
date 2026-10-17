#!/usr/bin/env bash
# CI shard partition check (Flutter NOT required, takes seconds; runs in the analyze job).
#  1) every *_test.dart under test/ falls into EXACTLY ONE shard (missing = silently never run, duplicate = run twice),
#     and no shard is empty (checked on the output of scripts/ci-test-shard.sh).
#  2) Partitioning is deterministic (the same output when generated twice).
#  3) The `test` matrix in ci.yml (shard: [0..N-1]) and `total` state the same N (the matrix and the count cannot diverge).
# Usage: bash scripts/ci-shard-check.sh [workflow=.github/workflows/ci.yml]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
WF="${1:-.github/workflows/ci.yml}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export CI_SHARD_OUT="$T/out.dart"

fail() { echo "ci-shard-check: $* -> RED" >&2; exit 1; }

# matrix: the `shard: [0, 1, 2]` and `total: [3]` lines
shards_line="$(grep -E '^[[:space:]]+shard:[[:space:]]*\[' "$WF" | head -n 1)" || fail "$WF: shard matrix missing"
total_line="$(grep -E '^[[:space:]]+total:[[:space:]]*\[' "$WF" | head -n 1)" || fail "$WF: total matrix missing"
mapfile -t idx < <(printf '%s' "$shards_line" | sed -E 's/.*\[(.*)\].*/\1/' | tr ',' '\n' | tr -d ' ')
N="$(printf '%s' "$total_line" | sed -E 's/.*\[[[:space:]]*([0-9]+)[[:space:]]*\].*/\1/')"
case "$N" in ''|*[!0-9]*) fail "$WF: could not read total";; esac
[ "${#idx[@]}" -eq "$N" ] || fail "$WF: matrix has ${#idx[@]} shards, total=$N"
for ((i = 0; i < N; i++)); do [ "${idx[$i]}" = "$i" ] || fail "$WF: shard list must be 0..$((N - 1)) (found: ${idx[*]})"; done

all="$(cd test && find . -name '*_test.dart' ! -name '_ci_shard_test.dart' | sed 's#^\./##' | LC_ALL=C sort)"
[ -n "$all" ] || fail "no test files under test/"

partition() { # -> $T/$1/<i>.txt
  mkdir -p "$T/$1"
  for ((i = 0; i < N; i++)); do CI_SHARD_LIST="$T/$1/$i.txt" bash scripts/ci-test-shard.sh "$i" "$N" > /dev/null; done
}
partition a
partition b
for ((i = 0; i < N; i++)); do
  [ -s "$T/a/$i.txt" ] || fail "shard $i is empty"
  cmp -s "$T/a/$i.txt" "$T/b/$i.txt" || fail "shard $i is not deterministic"
done
ran="$(cat "$T"/a/*.txt | LC_ALL=C sort)"
dups="$(printf '%s\n' "$ran" | uniq -d)"
[ -z "$dups" ] || fail "file(s) run in more than one shard: $dups"
[ "$ran" = "$all" ] || fail "run file set != test/ file set ($(printf '%s\n' "$ran" | wc -l | tr -d ' ') vs $(printf '%s\n' "$all" | wc -l | tr -d ' '))"
echo "ci-shard-check: OK -- $(printf '%s\n' "$all" | wc -l | tr -d ' ') test files, $N shards, every file in exactly 1 shard, deterministic"
