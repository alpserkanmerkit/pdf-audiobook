#!/usr/bin/env bash
# DEMO start-up proof (headless): builds the Linux desktop binary, opens it under xvfb,
# captures the root window to a PNG and catches a BLANK or BROKEN start.
#
#   bash scripts/demo-shot.sh [out.png]      # default: docs/demo/acilis.png
#   bash scripts/demo-shot.sh --build-only     # build only (so the CI build step shows up separately)
#   DEMO_SHOT_NO_BUILD=1 bash scripts/demo-shot.sh [out.png]   # skip the build (run --build-only first; RED if no binary)
# Env: DEMO_SHOT_WAIT (s, upper limit; default 15), FLUTTER.
# Wait is NOT fixed: the window is captured every second; if two consecutive captures are IDENTICAL and not blank
# (UI settled), that frame becomes the PNG and no more waiting is done. If it never settles (continuous animation),
# the last frame at the upper limit is taken. In every case the app must still be running when a frame is captured.
# With CI=true and pub get done, `--no-pub` is used; in CI, if a cached build is broken, the cache is deleted and a COLD build is tried ONCE.
# Exit 0 = app opened, did not crash, no uncaught exception in the log, PNG not blank.
# Requires: xvfb, ImageMagick (import/identify), Linux toolchain (scripts/e2e-apt.txt).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BUILD_ONLY=0
if [ "${1:-}" = "--build-only" ]; then BUILD_ONLY=1; shift; fi
OUT="${1:-docs/demo/acilis.png}"
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
WAIT="${DEMO_SHOT_WAIT:-15}"
FLUTTER="${FLUTTER:-flutter}"
GEO=1280x720

if [ "$BUILD_ONLY" -eq 0 ]; then
  for c in xvfb-run import identify; do
    command -v "$c" >/dev/null 2>&1 || { echo "demo-shot: '$c' not found (apt: xvfb imagemagick) -> RED" >&2; exit 1; }
  done
fi
mkdir -p "$(dirname "$OUT")"

started=$(date +%s)
NOPUB=()
if [ -n "${CI:-}" ] && [ -f .dart_tool/package_config.json ]; then NOPUB=(--no-pub); fi
if [ "${DEMO_SHOT_NO_BUILD:-0}" = "1" ]; then
  echo "demo-shot: build skipped (DEMO_SHOT_NO_BUILD=1)"
else
  echo "demo-shot: building (linux debug, lib/main_demo.dart)"
  had_build=0; { [ -d build/linux ] || [ -d .dart_tool/flutter_build ]; } && had_build=1
  if ! "$FLUTTER" build linux --debug -t lib/main_demo.dart ${NOPUB[@]+"${NOPUB[@]}"}; then
    # Only in CI and only if build/ or .dart_tool/flutter_build came from the cache: possibly broken/incompatible cache -> clean and try cold once.
    if [ -n "${CI:-}" ] && [ "$had_build" -eq 1 ]; then
      echo "demo-shot: cached build FAILED -> deleting build/ and .dart_tool/flutter_build, retrying cold" >&2
      rm -rf build .dart_tool/flutter_build
      "$FLUTTER" build linux --debug -t lib/main_demo.dart ${NOPUB[@]+"${NOPUB[@]}"}
    else
      exit 1
    fi
  fi
  echo "demo-shot: build done ($(( $(date +%s) - started )) s)"
fi
[ "$BUILD_ONLY" -eq 0 ] || exit 0
BIN="$ROOT/build/linux/x64/debug/bundle/sesli_kitap"
[ -x "$BIN" ] || { echo "demo-shot: binary not found: $BIN -> RED" >&2; exit 1; }

LOG="$(mktemp "${TMPDIR:-/tmp}/demo_shot_log.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
export LIBGL_ALWAYS_SOFTWARE=1

# The app runs inside xvfb; it must still be alive when a frame is captured.
set +e
xvfb-run -a -s "-screen 0 ${GEO}x24" bash -c '
  BIN=$0; LOG=$1; OUT=$2; WAIT=$3
  "$BIN" >"$LOG" 2>&1 &
  APP=$!
  prev=""
  t0=$(date +%s)
  while :; do
    now=$(( $(date +%s) - t0 ))
    if ! kill -0 "$APP" 2>/dev/null; then echo "demo-shot: app CRASHED/CLOSED while waiting" >&2; exit 3; fi
    import -window root "$OUT" || exit 4
    # Settled = colored (not blank) and pixel-identical to the previous frame (%# = pixel signature; PNG metadata/timestamps are ignored).
    sig="$(identify -format "%k %#" "$OUT")"
    if [ "$sig" = "$prev" ] && [ "${sig%% *}" -gt 50 ]; then
      echo "demo-shot: UI settled after $now s"; break
    fi
    [ "$now" -ge "$WAIT" ] && { echo "demo-shot: UI did not settle within $WAIT s; last frame taken"; break; }
    prev="$sig"
    sleep 1
  done
  if ! kill -0 "$APP" 2>/dev/null; then echo "demo-shot: app CRASHED/CLOSED while capturing a frame" >&2; exit 3; fi
  kill "$APP" 2>/dev/null; wait "$APP" 2>/dev/null
  exit 0
' "$BIN" "$LOG" "$OUT" "$WAIT"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "demo-shot: RED (exit $rc). App log:" >&2
  tail -40 "$LOG" >&2
  exit "$rc"
fi

# Any uncaught exception / crash trace?
if grep -E "Unhandled Exception|EXCEPTION CAUGHT|Another exception was thrown|Segmentation fault|FlutterError" "$LOG" >/dev/null; then
  echo "demo-shot: exception in log -> RED" >&2
  grep -E -B2 -A8 "Unhandled Exception|EXCEPTION CAUGHT|Another exception" "$LOG" | head -60 >&2
  exit 1
fi

# PNG not blank: unique color count + mean brightness.
colors="$(identify -format '%k' "$OUT")"
mean="$(identify -format '%[fx:mean]' "$OUT")"
python3 -I - "$colors" "$mean" <<'PY' || { echo "demo-shot: PNG looks blank/black -> RED" >&2; exit 1; }
import sys
colors, mean = int(sys.argv[1]), float(sys.argv[2])
sys.exit(0 if colors > 50 and mean > 0.02 else 1)
PY
size="$(wc -c <"$OUT")"
echo "demo-shot: OK $OUT (${colors} colors, mean brightness ${mean}, ${size} bytes, $(( $(date +%s) - started )) s)"
