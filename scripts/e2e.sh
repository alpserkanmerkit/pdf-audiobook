#!/usr/bin/env bash
# End-to-end SMOKE tests (integration_test/): one command, locally and in CI.
#
#   bash scripts/e2e.sh                 # default: deviceless flutter_tester VM (no build/GUI)
#   bash scripts/e2e.sh --linux         # full real platform: Linux desktop build + xvfb
#   bash scripts/e2e.sh --plain-name 'flow 3'   # extra arguments are passed to flutter test
#   E2E_MODE=linux bash scripts/e2e.sh  # same as --linux
#
# TWO PATHS:
#   vm    (-d flutter-tester)  MAIN PATH. REAL main()/SesliKitapApp/AppShell, real
#                              PagePipeline/PDF/prefs logic/HTTP client run; only
#                              platform plugins (audio, file picker, OCR) are not native.
#                              Linux/GTK/xvfb NOT needed. Build = Dart kernel only.
#   linux (-d linux + xvfb)    "Full real platform": the app is built as a native Linux binary and
#                              runs in a REAL window under xvfb. Plugins unsupported on Linux
#                              (just_audio, google_mlkit, pdfx,
#                              just_audio_windows) do not register on Linux; tests already inject audio/OCR/
#                              picker seams. Requires: scripts/e2e-apt.txt
#
# Hermetic: fake server on loopback (NO live API/keys); shared_preferences in memory;
# documents dir is temporary (XDG_DOCUMENTS_DIR + fake `xdg-user-dir`, because on Linux
# path_provider asks that tool for the documents dir; otherwise main() throws).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${E2E_MODE:-vm}"
EXTRA=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --linux) MODE=linux ;;
    --vm) MODE=vm ;;
    *) EXTRA+=("$1") ;;
  esac
  shift
done

FLUTTER="${FLUTTER:-flutter}"
TARGET="${E2E_TARGET:-integration_test}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sesli_e2e.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs" "$WORK/bin" "$WORK/data" "$WORK/cache" "$WORK/config"

# Fake xdg-user-dir: for path_provider_linux getApplicationDocumentsDirectory.
cat > "$WORK/bin/xdg-user-dir" <<'SH'
#!/bin/sh
echo "${XDG_DOCUMENTS_DIR:-/tmp}"
SH
chmod +x "$WORK/bin/xdg-user-dir"

export PATH="$WORK/bin:$PATH"
export XDG_DOCUMENTS_DIR="$WORK/docs"
export XDG_DATA_HOME="$WORK/data"
export XDG_CACHE_HOME="$WORK/cache"
export XDG_CONFIG_HOME="$WORK/config"

started=$(date +%s)
case "$MODE" in
  vm)
    echo "e2e: mode=vm (flutter_tester, deviceless) target=$TARGET"
    "$FLUTTER" test -d flutter-tester "$TARGET" ${EXTRA[@]+"${EXTRA[@]}"}
    ;;
  linux)
    echo "e2e: mode=linux (xvfb + native Linux build) target=$TARGET"
    command -v xvfb-run >/dev/null || { echo "e2e: xvfb-run not found (apt: xvfb) -> RED" >&2; exit 1; }
    [ -d linux ] || { echo "e2e: linux/ missing -> needs 'flutter create --platforms=linux .' -> RED" >&2; exit 1; }
    # -s: screen 1280x1024x24 (the default 640x480 is too narrow for the app layout).
    xvfb-run -a -s "-screen 0 1280x1024x24" \
      "$FLUTTER" test -d linux "$TARGET" ${EXTRA[@]+"${EXTRA[@]}"}
    ;;
  *)
    echo "e2e: unknown mode '$MODE' (vm|linux) -> RED" >&2
    exit 2
    ;;
esac
echo "e2e: OK mode=$MODE time=$(( $(date +%s) - started )) s"
