#!/usr/bin/env bash
# Installs ONLY the packages from scripts/e2e-apt.txt that are not installed yet (CI smoke jobs).
# Why: the ubuntu-latest image already has clang/cmake/ninja/pkg-config/xvfb; if nothing is missing,
# NO apt call is made at all, including `apt-get update` (saves time). Inline comments in the file
# (`package   # description`) are stripped -- a raw `$(grep -v '^#' ...)` would treat them as package names.
# The toolchain (clang/cmake/ninja/pkg-config) may NOT be a dpkg package on the image (cmake/ninja come as
# binaries); so they are checked by COMMAND, not dpkg (ARAC_KOMUTLARI) -- if missing, the package is added.
# Usage: bash scripts/e2e-apt-install.sh [--list]   (--list: only print what is missing, do not install)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="${E2E_APT_LIST:-$HERE/e2e-apt.txt}"

mapfile -t wanted < <(sed -E 's/#.*//; s/[[:space:]]+//g; /^$/d' "$LIST")
[ "${#wanted[@]}" -gt 0 ] || { echo "e2e-apt-install: $LIST is empty -> RED" >&2; exit 1; }

missing=()
for p in "${wanted[@]}"; do
  if ! dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok installed$'; then
    missing+=("$p")
  fi
done

# command:package -- if the command is not on PATH, add the package to the install list (self-heals if the image changes).
ARAC_KOMUTLARI=(clang:clang cmake:cmake ninja:ninja-build pkg-config:pkg-config)
for kp in "${ARAC_KOMUTLARI[@]}"; do
  if ! command -v "${kp%%:*}" >/dev/null 2>&1; then missing+=("${kp#*:}"); fi
done

if [ "${1:-}" = "--list" ]; then
  printf '%s\n' ${missing[@]+"${missing[@]}"}
  exit 0
fi

if [ "${#missing[@]}" -eq 0 ]; then
  echo "e2e-apt-install: ${#wanted[@]} packages + toolchain ready -> no apt call"
  exit 0
fi

echo "e2e-apt-install: missing ${#missing[@]}/${#wanted[@]}: ${missing[*]}"
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"
# Hang guard (main run 37693991411: this step hung 12+ min; the 2 previous runs took 26-89 s): each attempt is capped at 240 s,
# 60 s wait for the dpkg lock, 2 attempts. Failure is RED (never silently passed).
apt_retry() {
  local n
  for n in 1 2; do
    if timeout 240 $SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a "$@"; then return 0; fi
    echo "e2e-apt-install: attempt $n failed/timed out: $*" >&2
  done
  return 1
}
apt_retry apt-get -o DPkg::Lock::Timeout=60 -o Acquire::Retries=3 update -qq
apt_retry apt-get -o DPkg::Lock::Timeout=60 -o Acquire::Retries=3 install -y -qq --no-install-recommends "${missing[@]}"
