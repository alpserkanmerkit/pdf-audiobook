#!/usr/bin/env bash
# Produces ONE entry file for a CI test shard. WHY NOT `flutter test --shard-index`: that flag splits the tests
# INSIDE the files, not the test FILES (measured: each of 4 shards compiles ~140 of 154 files), so the compile cost
# is multiplied by the shard count. Here each shard compiles only its own files, once, in a single entry file.
# Tests are NOT changed: each file's main() is called as-is inside a group named after its path.
# Usage: bash scripts/ci-test-shard.sh <shard-index> <total-shards>  -> test/_ci_shard_test.dart
#
# BALANCING: files are split across shards by TIME (LPT: heaviest file first, each to the least-loaded shard so far).
# Weight = scripts/ci-test-weights.txt ("<ms> <path>"); missing file = average of the known ones, +BASE_MS per file
# (import/compile overhead). Missing or empty weights file -> round-robin (i % N). The split is DETERMINISTIC (every
# shard computes the same result from the same input) and EVERY file lands in exactly one shard (checked by
# scripts/ci-shard-check.sh, which runs in the analyze job), so the gate is not weakened.
#
# Environment variables (all optional):
#   CI_SHARD_OUT      generated entry file (default test/_ci_shard_test.dart)
#   CI_SHARD_LIST     file where this shard's file list (paths relative to test/) is written
#   CI_SHARD_WEIGHTS  weights file (default scripts/ci-test-weights.txt)
#   CI_SHARD_TESTDIR  test directory (default test)
set -euo pipefail

INDEX="${1:?shard-index}"
TOTAL="${2:?total-shards}"
OUT="${CI_SHARD_OUT:-test/_ci_shard_test.dart}"
TESTDIR="${CI_SHARD_TESTDIR:-test}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEIGHTS="${CI_SHARD_WEIGHTS:-$HERE/ci-test-weights.txt}"
BASE_MS=30

case "$INDEX$TOTAL" in *[!0-9]*) echo "ci-test-shard: index/total must be numbers -> RED" >&2; exit 1;; esac
[ "$TOTAL" -ge 1 ] && [ "$INDEX" -lt "$TOTAL" ] || { echo "ci-test-shard: index $INDEX, total $TOTAL invalid -> RED" >&2; exit 1; }

mapfile -t files < <(cd "$TESTDIR" && find . -name '*_test.dart' ! -name '_ci_shard_test.dart' | sed 's#^\./##' | LC_ALL=C sort)
[ "${#files[@]}" -gt 0 ] || { echo "ci-test-shard: no test files -> RED" >&2; exit 1; }

# assign[i] = shard of the i-th file. Input: sorted file list (stdin) + weights file.
declare -a assign
if [ -s "$WEIGHTS" ] && grep -qE '^[0-9]+ ' "$WEIGHTS"; then
  mapfile -t assign < <(
    printf '%s\n' "${files[@]}" | awk -v W="$WEIGHTS" -v BASE="$BASE_MS" '
      BEGIN {
        while ((getline line < W) > 0) {
          if (line ~ /^[0-9]+ /) { ms = line; sub(/ .*/, "", ms); p = line; sub(/^[0-9]+ /, "", p); w[p] = ms + 0 }
        }
      }
      { name[NR] = $0; if ($0 in w) { sum += w[$0]; known++ } }
      END {
        avg = known ? sum / known : 0
        for (i = 1; i <= NR; i++) printf "%d %d %s\n", ((name[i] in w) ? w[name[i]] : avg) + BASE, i - 1, name[i]
      }' |
    LC_ALL=C sort -k1,1nr -k3,3 |
    awk -v N="$TOTAL" '
      BEGIN { for (s = 0; s < N; s++) load[s] = 0 }
      { best = 0; for (s = 1; s < N; s++) if (load[s] < load[best]) best = s
        load[best] += $1; out[$2] = best; n++ }
      END { for (i = 0; i < n; i++) print out[i] }'
  )
else
  for i in "${!files[@]}"; do assign[i]=$(( i % TOTAL )); done
fi
[ "${#assign[@]}" -eq "${#files[@]}" ] || { echo "ci-test-shard: partition ${#assign[@]} != ${#files[@]} files -> RED" >&2; exit 1; }

selected=()
{
  echo "// GENERATED (scripts/ci-test-shard.sh $INDEX/$TOTAL) -- do not commit."
  echo "import 'package:flutter_test/flutter_test.dart';"
  for i in "${!files[@]}"; do
    if [ "${assign[$i]}" -eq "$INDEX" ]; then echo "import '${files[$i]}' as t$i;"; selected+=("${files[$i]}"); fi
  done
  echo
  echo "void main() {"
  for i in "${!files[@]}"; do
    [ "${assign[$i]}" -eq "$INDEX" ] && echo "  group('${files[$i]}', t$i.main);"
  done
  echo "}"
} > "$OUT"

[ "${#selected[@]}" -gt 0 ] || { echo "ci-test-shard: shard $INDEX/$TOTAL is empty (${#files[@]} files, $TOTAL shards) -> RED" >&2; exit 1; }
if [ -n "${CI_SHARD_LIST:-}" ]; then printf '%s\n' "${selected[@]}" > "$CI_SHARD_LIST"; fi

echo "ci-test-shard: $INDEX/$TOTAL -> ${#selected[@]} files (total ${#files[@]})"
