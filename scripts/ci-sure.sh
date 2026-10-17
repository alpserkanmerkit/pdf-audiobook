#!/usr/bin/env bash
# Reads the job and STEP times of a CI run, prints a table + summary, and checks the 3 min (180 s) budget.
#
#   bash scripts/ci-sure.sh <run-id> [owner/repo] [--butce N]     (--bütçe N also works; default 180)
#
# Data: `gh api repos/<repo>/actions/runs/<id>/jobs` (job + step times) and
#       `gh api repos/<repo>/actions/runs/<id>` (run start).
# Wall-clock total = max(job end) - run start (queue wait INCLUDED).
# Exit: 0 = within budget; 1 = budget exceeded; 2 = usage/data error (run not finished, gh error...).
# Parser: jq if available, otherwise python3 (force with CI_SURE_ARAC=jq|python; for tests).
# Output is deterministic (same JSON -> byte-identical output; no clock or locale dependence).
set -euo pipefail
export LC_ALL=C

BUTCE=180
RUN_ID=""
REPO=""

kullanim() {
  cat >&2 <<'USG'
Usage: bash scripts/ci-sure.sh <run-id> [owner/repo] [--butce N]
  run-id        GitHub Actions run number (digits only)
  owner/repo    if omitted: $GITHUB_REPOSITORY, otherwise `gh repo view`
  --butce N     wall-clock budget, s (default 180; --bütçe is also accepted)
Exit: 0 within budget, 1 budget exceeded, 2 usage/data error.
USG
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --butce|--bütçe|--budget)
      [ "$#" -ge 2 ] || { echo "ci-sure: no value for $1" >&2; kullanim; exit 2; }
      BUTCE="$2"; shift 2 ;;
    --butce=*|--bütçe=*|--budget=*) BUTCE="${1#*=}"; shift ;;
    -h|--help|--yardim) kullanim; exit 0 ;;
    -*) echo "ci-sure: unknown flag: $1" >&2; kullanim; exit 2 ;;
    *)
      if [ -z "$RUN_ID" ]; then RUN_ID="$1"
      elif [ -z "$REPO" ]; then REPO="$1"
      else echo "ci-sure: extra argument: $1" >&2; kullanim; exit 2; fi
      shift ;;
  esac
done

[[ "$RUN_ID" =~ ^[0-9]+$ ]] || { echo "ci-sure: run-id must be a number (got: '${RUN_ID}')" >&2; kullanim; exit 2; }
[[ "$BUTCE" =~ ^[1-9][0-9]*$ ]] || { echo "ci-sure: budget must be a positive integer (s) (got: '${BUTCE}')" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "ci-sure: 'gh' not found" >&2; exit 2; }

if [ -z "$REPO" ]; then REPO="${GITHUB_REPOSITORY:-}"; fi
if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || REPO=""
fi
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || {
  echo "ci-sure: could not determine owner/repo (pass the second argument: bash scripts/ci-sure.sh $RUN_ID owner/repo)" >&2; exit 2; }

ARAC="${CI_SURE_ARAC:-}"
if [ -z "$ARAC" ]; then
  if command -v jq >/dev/null 2>&1; then ARAC=jq; else ARAC=python; fi
fi
case "$ARAC" in
  jq) command -v jq >/dev/null 2>&1 || { echo "ci-sure: jq not found" >&2; exit 2; } ;;
  python) command -v python3 >/dev/null 2>&1 || { echo "ci-sure: neither jq nor python3 found" >&2; exit 2; } ;;
  *) echo "ci-sure: CI_SURE_ARAC must be jq|python" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ci-sure.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

gh api "repos/$REPO/actions/runs/$RUN_ID/jobs?per_page=100" --paginate >"$TMP/jobs.json" 2>"$TMP/err" \
  || { echo "ci-sure: gh api (jobs) failed: $(head -c 300 "$TMP/err")" >&2; exit 2; }
gh api "repos/$REPO/actions/runs/$RUN_ID" >"$TMP/run.json" 2>"$TMP/err" \
  || { echo "ci-sure: gh api (run) failed: $(head -c 300 "$TMP/err")" >&2; exit 2; }

# --- Normalization: JSON -> TSV (epoch seconds; missing/null = -1) ---------------------------------
#   J <job> <created> <started> <completed> <conclusion>        S <job> <no> <step> <started> <completed> <conclusion>
#   R <run-start> <status> <conclusion>
norm_jq() {
  jq -r -s '
    def ep: if . == null then -1 else (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) end;
    def ad: gsub("[\t\n\r]"; " ");
    [.[] | (.jobs // [])[]] | sort_by([.started_at // "", .name]) | .[] |
    ( ["J", (.name|ad), (.created_at|ep), (.started_at|ep), (.completed_at|ep), (.conclusion // .status // "?")]
      | map(tostring) | join("\t") ),
    ( (.name|ad) as $n | (.steps // [])[] |
      ["S", $n, .number, (.name|ad), (.started_at|ep), (.completed_at|ep), (.conclusion // .status // "?")]
      | map(tostring) | join("\t") )
  ' "$TMP/jobs.json"
  jq -r '
    def ep: if . == null then -1 else (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) end;
    ["R", ((.run_started_at // .created_at)|ep), (.status // "?"), (.conclusion // "-")] | map(tostring) | join("\t")
  ' "$TMP/run.json"
}

norm_python() {
  python3 -I - "$TMP/jobs.json" "$TMP/run.json" <<'PY'
import json, re, sys
from datetime import datetime, timezone

def ep(v):
    if v is None:
        return -1
    v = re.sub(r"\.[0-9]+Z$", "Z", v)
    return int(datetime.strptime(v, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())

def ad(v):
    return re.sub(r"[\t\n\r]", " ", str(v))

text = open(sys.argv[1], encoding="utf-8").read()
dec, pos, jobs = json.JSONDecoder(), 0, []
while True:
    while pos < len(text) and text[pos].isspace():
        pos += 1
    if pos >= len(text):
        break
    obj, pos = dec.raw_decode(text, pos)
    jobs.extend(obj.get("jobs") or [])
jobs.sort(key=lambda j: ((j.get("started_at") or ""), j.get("name")))
for j in jobs:
    sonuc = j.get("conclusion") or j.get("status") or "?"
    print("\t".join(["J", ad(j["name"]), str(ep(j.get("created_at"))), str(ep(j.get("started_at"))),
                     str(ep(j.get("completed_at"))), sonuc]))
    for s in j.get("steps") or []:
        print("\t".join(["S", ad(j["name"]), str(s["number"]), ad(s["name"]), str(ep(s.get("started_at"))),
                         str(ep(s.get("completed_at"))), s.get("conclusion") or s.get("status") or "?"]))
run = json.load(open(sys.argv[2], encoding="utf-8"))
print("\t".join(["R", str(ep(run.get("run_started_at") or run.get("created_at"))),
                 run.get("status") or "?", run.get("conclusion") or "-"]))
PY
}

if [ "$ARAC" = jq ]; then norm_jq >"$TMP/norm.tsv"; else norm_python >"$TMP/norm.tsv"; fi \
  || { echo "ci-sure: JSON could not be parsed (tool=$ARAC)" >&2; exit 2; }

grep -q '^J' "$TMP/norm.tsv" || { echo "ci-sure: run has no jobs (check run-id/repo)" >&2; exit 2; }

# --- Analysis + output (awk; byte-based, deterministic) --------------------------------------------
set +e
awk -F'\t' -v repo="$REPO" -v run="$RUN_ID" -v butce="$BUTCE" -v tmp="$TMP" '
  function sure(b, e) { return (b < 0 || e < 0) ? 0 : e - b }
  $1 == "R" { rbas = $2; rdurum = $3; rsonuc = $4; next }
  $1 == "J" {
    nj++; jad[nj] = $2; jcre[nj] = $3; jbas[nj] = $4; jbit[nj] = $5; json[nj] = $6; next
  }
  $1 == "S" {
    ns++; sj[ns] = $2; sno[ns] = $3; sad[ns] = $4; sbas[ns] = $5; sbit[ns] = $6; sson[ns] = $7; next
  }
  END {
    bitmemis = 0; basarisiz = ""; sonbit = -1; sonbitad = ""; ymax = -1; ymaxad = ""
    minc = -1
    for (i = 1; i <= nj; i++) {
      if (json[i] == "skipped") continue
      if (jbit[i] < 0) { bitmemis++; continue }
      if (jbit[i] > sonbit) { sonbit = jbit[i]; sonbitad = jad[i] }
      d = sure(jbas[i], jbit[i]); jsure[i] = d
      if (d > ymax) { ymax = d; ymaxad = jad[i] }
      if (json[i] == "failure" || json[i] == "cancelled" || json[i] == "timed_out") basarisiz = basarisiz (basarisiz == "" ? "" : ", ") jad[i] " (" json[i] ")"
      if (minc < 0 || (jcre[i] >= 0 && jcre[i] < minc)) minc = jcre[i]
    }
    if (bitmemis > 0) {
      printf "ci-sure: run %s not finished (%d job(s) not completed, status=%s) -> cannot measure time\n", run, bitmemis, rdurum > "/dev/stderr"
      exit 2
    }
    if (rbas < 0) rbas = minc
    duvar = sonbit - rbas

    printf "ci-sure: run %s (%s)  status=%s conclusion=%s\n", run, repo, rdurum, rsonuc
    printf "%-44s | %-52s | %s\n", "JOB", "STEP", "TIME (s)"
    for (i = 1; i <= nj; i++) {
      if (json[i] == "skipped") {
        printf "%-44s | %-52s | %s\n", jad[i], "* job skipped", "-"; continue
      }
      kuyruk = sure(jcre[i], jbas[i])
      printf "%-44s | %-52s | %9d\n", jad[i], "* job total (queue " kuyruk " s, " json[i] ")", jsure[i]
      for (k = 1; k <= ns; k++) {
        if (sj[k] != jad[i]) continue
        d = sure(sbas[k], sbit[k])
        ad = sad[k]; if (sson[k] == "skipped") ad = ad " (skipped)"
        printf "%-44s | %-52s | %9d\n", jad[i], ad, d
        rec = d "\t" jad[i] " / " sad[k]
        print rec > (tmp "/adimlar.tsv")
      }
    }
    close(tmp "/adimlar.tsv")
    print duvar > (tmp "/duvar"); close(tmp "/duvar")
    print ymax "\t" ymaxad > (tmp "/yavasis"); close(tmp "/yavasis")
    print sonbitad > (tmp "/sonbit"); close(tmp "/sonbit")
    print basarisiz > (tmp "/basarisiz"); close(tmp "/basarisiz")
  }
' "$TMP/norm.tsv"
rc=$?
set -e
[ "$rc" -eq 0 ] || exit 2

DUVAR="$(cat "$TMP/duvar")"
IFS=$'\t' read -r YSURE YAD <"$TMP/yavasis"
SONBIT="$(cat "$TMP/sonbit")"
BASARISIZ="$(cat "$TMP/basarisiz")"

echo
echo "Slowest 5 steps:"
if [ -s "$TMP/adimlar.tsv" ]; then
  sort -t$'\t' -k1,1nr -k2,2 "$TMP/adimlar.tsv" | sed -n '1,5p' | awk -F'\t' '{ printf "  %5d s  %s\n", $1, $2 }'
fi
EN_ADIM="-"
if [ -s "$TMP/adimlar.tsv" ]; then
  EN_ADIM="$(sort -t$'\t' -k1,1nr -k2,2 "$TMP/adimlar.tsv" | sed -n '1p' | awk -F'\t' '{ printf "%s (%d s)", $2, $1 }')"
fi
echo
echo "SUMMARY"
printf '  total wall time    : %d s  (run start -> last finished job, queue included)\n' "$DUVAR"
printf '  last finished job  : %s\n' "$SONBIT"
printf '  slowest job        : %s (%d s)\n' "$YAD" "$YSURE"
printf '  slowest step       : %s\n' "$EN_ADIM"
[ -z "$BASARISIZ" ] || printf '  WARNING failed job : %s (time measured anyway)\n' "$BASARISIZ"
if [ "$DUVAR" -le "$BUTCE" ]; then
  printf '  budget             : %d s -> OK (%d s to spare)\n' "$BUTCE" "$((BUTCE - DUVAR))"
  exit 0
fi
printf '  budget             : %d s -> EXCEEDED (+%d s) RED\n' "$BUTCE" "$((DUVAR - BUTCE))"
exit 1
