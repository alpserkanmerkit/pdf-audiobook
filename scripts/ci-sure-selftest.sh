#!/usr/bin/env bash
# Self-test of scripts/ci-sure.sh: FAKE `gh` (on PATH) + sample JSON fixture; no network or GitHub needed.
# Scenarios: within budget (green) / budget exceeded (red) / --butce flag / jq and python3 paths give the same output /
#            paginated (--paginate) output / unfinished run / gh error / invalid usage.
# Usage: bash scripts/ci-sure-selftest.sh      (0 = all green)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SURE="$HERE/ci-sure.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/ci-sure-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/fx"
FAIL=0

# --- Fake gh -----------------------------------------------------------------------------------------
cat >"$T/bin/gh" <<'GH'
#!/usr/bin/env bash
# Fake gh: only imitates `gh api <url> [--paginate]` and `gh repo view`.
[ "${FAKE_GH_FAIL:-}" = 1 ] && { echo "HTTP 404: Not Found" >&2; exit 1; }
case "$1" in
  repo) echo "example/repo"; exit 0 ;;
  api)
    case "$2" in
      */jobs*) cat "$FAKE_GH_DIR/jobs.json" ;;
      */actions/runs/*) cat "$FAKE_GH_DIR/run.json" ;;
      *) echo "fake gh: unknown url $2" >&2; exit 1 ;;
    esac ;;
  *) echo "fake gh: unknown command $1" >&2; exit 1 ;;
esac
GH
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" FAKE_GH_DIR="$T/fx"

# --- Fixture generator -------------------------------------------------------------------------------
# Run start 10:00:00. Job ends: analyze 10:01:30, smoke-unit 10:02:25, test(0) = $1 (variable).
# Expected (green, $1=10:02:30): wall 150 s, slowest job "test (0)" 140 s, slowest step test (0) / Tests 100 s.
yaz_fikstur() {
  local test_bitis="$1" durum="${2:-completed}" bitis_alani="${3:-}"
  cat >"$T/fx/jobs.json" <<JSON
{"total_count":4,"jobs":[
 {"id":1,"name":"analyze","status":"completed","conclusion":"success",
  "created_at":"2026-10-08T10:00:02Z","started_at":"2026-10-08T10:00:08Z","completed_at":"2026-10-08T10:01:30Z",
  "steps":[
   {"name":"Set up job","number":1,"status":"completed","conclusion":"success","started_at":"2026-10-08T10:00:08Z","completed_at":"2026-10-08T10:00:10Z"},
   {"name":"Flutter setup","number":2,"status":"completed","conclusion":"success","started_at":"2026-10-08T10:00:10Z","completed_at":"2026-10-08T10:00:40Z"},
   {"name":"Static analysis","number":3,"status":"completed","conclusion":"success","started_at":"2026-10-08T10:00:40Z","completed_at":"2026-10-08T10:01:30Z"}]},
 {"id":2,"name":"smoke-unit","status":"completed","conclusion":"success",
  "created_at":"2026-10-08T10:00:02Z","started_at":"2026-10-08T10:00:12Z","completed_at":"2026-10-08T10:02:25Z",
  "steps":[
   {"name":"Set up job","number":1,"status":"completed","conclusion":"success","started_at":"2026-10-08T10:00:12Z","completed_at":"2026-10-08T10:00:13Z"},
   {"name":"Linux packages","number":2,"status":"completed","conclusion":"skipped","started_at":null,"completed_at":null},
   {"name":"Unit tests","number":3,"status":"completed","conclusion":"success","started_at":"2026-10-08T10:00:13Z","completed_at":"2026-10-08T10:02:25Z"}]}
]}
{"total_count":4,"jobs":[
 {"id":3,"name":"test (0)","status":"completed","conclusion":"success",
  "created_at":"2026-10-08T10:00:02Z","started_at":"2026-10-08T10:00:10Z","completed_at":"$test_bitis",
  "steps":[
   {"name":"Set up job","number":1,"status":"completed","conclusion":"success","started_at":"2026-10-08T10:00:10Z","completed_at":"2026-10-08T10:00:12Z"},
   {"name":"Tests","number":2,"status":"completed","conclusion":"success","started_at":"2026-10-08T10:00:12Z","completed_at":"2026-10-08T10:01:52Z"}]},
 {"id":4,"name":"upload","status":"completed","conclusion":"skipped",
  "created_at":"2026-10-08T10:02:30Z","started_at":"2026-10-08T10:02:30Z","completed_at":"2026-10-08T10:02:30Z","steps":[]}
]}
JSON
  cat >"$T/fx/run.json" <<JSON
{"id":123,"status":"$durum","conclusion":"success","created_at":"2026-10-07T23:59:59Z","run_started_at":"2026-10-08T10:00:00Z"$bitis_alani}
JSON
}

# --- Helpers -----------------------------------------------------------------------------------------
kos() {  # kos <expected-exit> <description> <args...> ; output in $T/out
  local beklenen="$1" aciklama="$2"; shift 2
  local rc=0
  bash "$SURE" "$@" >"$T/out" 2>"$T/err" || rc=$?
  if [ "$rc" -ne "$beklenen" ]; then
    echo "RED: $aciklama (exit $rc, expected $beklenen)"; sed 's/^/    | /' "$T/out" "$T/err"; FAIL=1; return 1
  fi
  echo "ok: $aciklama (exit $rc)"
}
icerir() {  # icerir <file> <pattern> <description>
  if ! grep -q -F -- "$2" "$1"; then echo "RED: '$3' missing -> '$2'"; sed 's/^/    | /' "$1"; FAIL=1; return 1; fi
}

ARACLAR=(python)
command -v jq >/dev/null 2>&1 && ARACLAR=(jq python)

# 1) GREEN: wall 150 s <= 180
yaz_fikstur "2026-10-08T10:02:30Z"
for arac in "${ARACLAR[@]}"; do
  export CI_SURE_ARAC="$arac"
  kos 0 "green, within budget [$arac]" 123 example/repo || true
  icerir "$T/out" "total wall time    : 150 s" "wall" || true
  icerir "$T/out" "last finished job  : test (0)" "last finished job" || true
  icerir "$T/out" "slowest job        : test (0) (140 s)" "slowest job" || true
  icerir "$T/out" "slowest step       : smoke-unit / Unit tests (132 s)" "slowest step" || true
  icerir "$T/out" "OK (30 s to spare)" "budget ok" || true
  icerir "$T/out" "Linux packages (skipped)" "skipped step" || true
  icerir "$T/out" "* job skipped" "skipped job" || true
  icerir "$T/out" "queue 6 s" "queue time" || true
  cp "$T/out" "$T/out-$arac"
done
if [ "${#ARACLAR[@]}" -eq 2 ]; then
  if cmp -s "$T/out-jq" "$T/out-python"; then echo "ok: jq and python3 paths produce byte-identical output"; else
    echo "RED: jq/python3 outputs differ"; diff "$T/out-jq" "$T/out-python" | sed 's/^/    | /'; FAIL=1; fi
fi

# 2) Deterministic: same input twice -> same output
unset CI_SURE_ARAC
kos 0 "repeat 1" 123 example/repo || true; cp "$T/out" "$T/t1"
kos 0 "repeat 2" 123 example/repo || true
if cmp -s "$T/out" "$T/t1"; then echo "ok: output is deterministic"; else echo "RED: output is not deterministic"; FAIL=1; fi

# 3) RED: budget exceeded (last job 10:03:20 -> wall 200 s > 180)
yaz_fikstur "2026-10-08T10:03:20Z"
kos 1 "budget exceeded 200>180 -> exit 1" 123 example/repo || true
icerir "$T/out" "total wall time    : 200 s" "exceeded wall" || true
icerir "$T/out" "EXCEEDED (+20 s) RED" "exceeded message" || true

# 4) --butce flag: 200 s, budget 200 -> green; budget 199 -> red; ASCII and Turkish flag name
kos 0 "--butce 200 -> boundary green" 123 example/repo --butce 200 || true
kos 1 "--bütçe 199 -> red" 123 example/repo --bütçe 199 || true
kos 0 "flag before arguments: --butce=250" --butce=250 123 example/repo || true

# 5) If repo is omitted: $GITHUB_REPOSITORY / gh repo view
GITHUB_REPOSITORY=example/repo kos 1 "repo from environment (GITHUB_REPOSITORY)" 123 || true
env -u GITHUB_REPOSITORY bash "$SURE" 123 >"$T/out" 2>"$T/err" && rc=0 || rc=$?
if [ "$rc" -eq 1 ]; then echo "ok: repo from 'gh repo view' (exit 1)"; else echo "RED: gh repo view path (exit $rc)"; FAIL=1; fi

# 6) Unfinished run -> exit 2
yaz_fikstur "2026-10-08T10:02:30Z" in_progress
sed -i 's/"completed_at":"2026-10-08T10:02:30Z"/"completed_at":null/' "$T/fx/jobs.json"
kos 2 "unfinished job -> exit 2" 123 example/repo || true
icerir "$T/err" "not finished" "unfinished message" || true

# 7) gh error -> exit 2
yaz_fikstur "2026-10-08T10:02:30Z"
FAKE_GH_FAIL=1 kos 2 "gh error -> exit 2" 123 example/repo || true
icerir "$T/err" "failed" "gh error message" || true

# 8) Invalid usage -> exit 2
kos 2 "run-id missing" || true
kos 2 "run-id not a number" abc example/repo || true
kos 2 "budget invalid" 123 example/repo --butce 0 || true
kos 2 "unknown flag" 123 example/repo --x || true
kos 2 "invalid repo format" 123 "example repo" || true

if [ "$FAIL" -eq 0 ]; then echo "ci-sure-selftest: ALL GREEN"; exit 0; fi
echo "ci-sure-selftest: RED" >&2; exit 1
