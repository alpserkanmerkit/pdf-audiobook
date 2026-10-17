# CI layout and time budget

Target: a full CI run for one code change takes **wall clock ≤ 180 s** (3 min). Wall clock = run start → last job to finish
(including runner queueing). Jobs run in parallel; the **slowest job** sets the time.

## Job layout

`.github/workflows/ci.yml` — jobs do not wait for each other (no chain); all use the same shared setup:

| Job | What it does | `flutter-setup` inputs |
|-----|--------------|------------------------|
| `analyze` | `flutter analyze` | `apt: false` |
| `test` (shards) | `flutter test`, parallel slices | `apt: false` |
| `smoke-unit`, `smoke-shot`, `smoke-e2e` | `scripts/demo-smoke.sh` steps (xvfb + Linux build) | `apt: true` |

The shared top part (`name`, `on`, `concurrency`, `permissions`, `env`) is at the top of this file; job blocks have their own sections.
Trigger: push to `main` and `gece/**`, every PR, and manually (`workflow_dispatch`). An older run for the same branch/PR is cancelled.

## Shared setup: `.github/actions/flutter-setup`

Interface (fixed): `flutter-version` (default `3.35.7`), `cache` (`true`), `apt` (`false`), `pub-get` (`true`).

```yaml
- uses: actions/checkout@v6
- uses: ./.github/actions/flutter-setup
  with:
    apt: true        # smoke jobs only
```

Order: (if any) start apt **in the background** → Flutter SDK (cached) → `~/.pub-cache` cache →
`flutter pub get --enforce-lockfile` → (if any) wait for apt to finish. apt overlaps with the SDK/pub steps; an error or
timeout (script 480 s, 240 s per attempt, 2 attempts, dpkg lock wait 60 s) makes the job **red**.

### Cache keys

| Cache | Key | Fallback (`restore-keys`) |
|-------|-----|---------------------------|
| Flutter SDK (`subosito/flutter-action@v2`, `cache: true`) | `flutter-<os>-stable-<version>-<arch>-<SDK commit hash>` | none |
| `~/.pub-cache` (`actions/cache@v5`) | `pub-<os>-<flutter-version>-<hash(pubspec.lock)>` | `pub-<os>-<flutter-version>-` |

- The SDK key is **not tied to `pubspec.lock`**: a dependency change does not re-save the 1+ GB SDK.
- The pub key changes with the lock; when the lock changes, the nearest older cache is restored and `pub get` downloads only the diff.
- `.dart_tool` is **not cached**: in measurement, `pub get` time did not change with a cached `.dart_tool` (see below).
- A cache is saved only if the full key does not exist, at the end of the job; of parallel jobs one wins, the others log a "reserve" warning
  (harmless). A new branch can read the default branch's cache; the first run is cold (see below).

### apt list (`scripts/e2e-apt.txt`)

Only **xvfb, libgtk-3-dev, imagemagick**. The ubuntu-24.04 runner image (runner-images `20260927.320.1`) already ships clang, cmake,
ninja, pkg-config and xvfb, so they were removed; `liblzma-dev`, `libegl1`, `libgl1-mesa-dri` come with the `libgtk-3-dev`
dependency tree; `xdotool` is not used by any script. The toolchain is checked by command (installed if missing in the image).
If nothing is missing, no apt call is made at all (not even `apt-get update`). Actually installed: `libgtk-3-dev` (+ dependencies) and `imagemagick`.

## Reading the time from a run number

```bash
bash scripts/ci-sure.sh <run-id> [owner/repo]          # default budget 180 s
bash scripts/ci-sure.sh <run-id> owner/repo --butce 150
```

Requires `gh` (authenticated) and `jq` (or `python3` if missing). Output: job | step | duration (s) table, the 5 slowest steps,
summary (total wall clock, last job to finish, slowest job/step). If the budget is exceeded, exit code is **1**; on data/usage errors **2**.
Run number: the `…/actions/runs/<run-id>` address on the Actions page. Self-test: `bash scripts/ci-sure-selftest.sh`.

## Running on a second account

This repo can be run in a copy under a second GitHub account (private repo, `ubuntu-latest` = 2 vCPU / 7 GB):

1. Create the copy and push a branch (`main` or `gece/**`), or start it manually with Actions → CI → *Run workflow*.
2. When the run finishes, take its number; read the times with `bash scripts/ci-sure.sh <run-id> <owner>/<repo>`.
3. The first run has a **cold** cache (SDK is downloaded and saved); use the **second** run for the budget measurement
   (an empty commit on the same branch is enough). After a lock change, the first run partly refreshes the pub cache.

## Measurements (local, `taskset -c 0,1`; 2 vCPU simulation, throttled environment — RELATIVE values)

| Measurement | Result |
|-------------|--------|
| `flutter pub get`, empty `PUB_CACHE` (cold) | 44.3 s (network: environment proxy; should be faster on the runner) |
| `flutter pub get`, warm `PUB_CACHE` | 8.5 – 11.7 s (includes tool startup; `flutter --version` 1.8 s) |
| warm `PUB_CACHE` + `.dart_tool` present | 12.6 s → caching `.dart_tool` gives **no** gain |
| SDK extraction: `tar.xz` (download archive format) vs gzip -1 (upper bound for zstd) | ≈ 12 MB/s vs ≈ 51 MB/s output → restoring from cache is ≥ 4× cheaper in CPU |
| pub cache size | 191 MB |

Not measurable locally (to be verified with the run number of the second-account run): SDK cache hit/extraction time, apt time
(`libgtk-3-dev` + `imagemagick` install and the gain from background overlap), total wall clock.
