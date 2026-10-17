#!/usr/bin/env bash
# DEMO smoke test (headless, xvfb): 0 = the demo opens and the main flows work
# with canned replies; non-0 = red. The three steps can also be run on their own:
#
#   bash scripts/demo-smoke.sh [unit|shot|e2e|all]      (default: all)
#
#   unit   flutter test test/demo        unit/widget tests (fake server, router, audio, seed)
#   shot   scripts/demo-shot.sh          REAL Linux binary opens, PNG (startup proof): acilis.png
#   e2e    e2e flow 7 (Linux, xvfb)      library -> reader+play -> discussion -> quiz -> private lesson;
#                                        PNGs at the main steps (DEMO_SHOT_DIR): kutuphane/okuyucu/tartisma/ozel_ders.png
#   all    unit, shot, e2e SEQUENTIALLY (local one-command run; old behavior)
#
# In CI (.github/workflows/ci.yml) shot and e2e run as SEPARATE parallel jobs; `unit` is NOT a separate CI job
# (test/demo already runs in the `flutter test` shards); it is used only locally and in `all`.
# PNGs are written to the SMOKE_OUT dir (default build/demo-smoke); for doc images:
# SMOKE_OUT=docs/demo bash scripts/demo-smoke.sh
# Screenshots are taken with `import` (ImageMagick); without it e2e fails RED with no PNG.
# Exit codes: 0 green; 1 red (test/build/PNG); 2 wrong usage (unknown mode).
# With CI=true and pub get done, --no-pub is added to the flutter commands (skips a hidden ~4 s pub get each).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODE="${1:-all}"
case "$MODE" in
  unit|shot|e2e|all) ;;
  -h|--help|help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "demo-smoke: unknown mode '$MODE' (unit|shot|e2e|all) -> RED" >&2; exit 2 ;;
esac

OUT="${SMOKE_OUT:-build/demo-smoke}"
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
FLUTTER="${FLUTTER:-flutter}"
mkdir -p "$OUT"
started=$(date +%s)

NOPUB=()
if [ -n "${CI:-}" ] && [ -f .dart_tool/package_config.json ]; then NOPUB=(--no-pub); fi

step() { echo; echo "=== demo-smoke: $* ==="; }

# PNG exists and is not blank (unique colors > 50).
check_png() {
  local p="$OUT/$1.png" colors
  [ -s "$p" ] || { echo "demo-smoke: missing PNG: $p -> RED" >&2; exit 1; }
  colors="$(identify -format '%k' "$p")"
  [ "$colors" -gt 50 ] || { echo "demo-smoke: $1.png looks blank ($colors colors) -> RED" >&2; exit 1; }
}

run_unit() {
  step "unit: flutter test test/demo"
  "$FLUTTER" test ${NOPUB[@]+"${NOPUB[@]}"} test/demo
}

run_shot() {
  step "shot: startup proof (demo-shot)"
  rm -f "$OUT/acilis.png"
  bash scripts/demo-shot.sh "$OUT/acilis.png"
  check_png acilis
}

run_e2e() {
  step "e2e: demo flow (flow 7, linux+xvfb)"
  for f in kutuphane okuyucu tartisma ozel_ders; do rm -f "$OUT/$f.png"; done
  DEMO_SHOT_DIR="$OUT" bash scripts/e2e.sh --linux --plain-name 'flow 7' ${NOPUB[@]+"${NOPUB[@]}"}
  for f in kutuphane okuyucu tartisma ozel_ders; do check_png "$f"; done
}

case "$MODE" in
  unit) run_unit ;;
  shot) run_shot ;;
  e2e) run_e2e ;;
  all) run_unit; run_shot; run_e2e ;;
esac

echo
echo "demo-smoke: OK mode=$MODE time=$(( $(date +%s) - started )) s; PNG: $OUT"
ls -l "$OUT"/*.png 2>/dev/null || true
