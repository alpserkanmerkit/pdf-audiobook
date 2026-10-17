#!/usr/bin/env bash
# DEMO mode: runs WITHOUT an API key, with canned (pre-written) replies + silent audio.
# Single command: `make demo` (= this script) -- entry point lib/main_demo.dart.
#
#   bash scripts/demo.sh                 # device is picked from the OS
#   DEMO_DEVICE=windows bash scripts/demo.sh
#   SESLI_DEMO_CPS=30 bash scripts/demo.sh   # fake speech rate (characters/s, default 45)
# Extra arguments are passed to `flutter run`. For headless (CI/server): `make demo-shot`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FLUTTER="${FLUTTER:-flutter}"
if ! command -v "$FLUTTER" >/dev/null 2>&1; then
  echo "demo: '$FLUTTER' not found. Install Flutter 3.35.7 (Dart 3.9.2) and add it to PATH." >&2
  exit 127
fi

DEVICE="${DEMO_DEVICE:-}"
if [ -z "$DEVICE" ]; then
  case "$(uname -s)" in
    Linux) DEVICE=linux ;;
    Darwin) DEVICE=macos ;;
    MINGW* | MSYS* | CYGWIN*) DEVICE=windows ;;
    *)
      echo "demo: OS not recognized; set DEMO_DEVICE=linux|windows|macos." >&2
      exit 2
      ;;
  esac
fi

if [ "$DEVICE" = linux ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "demo: no display (DISPLAY). Run in a desktop session, or use 'make demo-shot' for headless proof." >&2
  exit 2
fi

echo "demo: device=$DEVICE entry=lib/main_demo.dart (FAKE replies, no audio)"
exec "$FLUTTER" run -d "$DEVICE" -t lib/main_demo.dart "$@"
