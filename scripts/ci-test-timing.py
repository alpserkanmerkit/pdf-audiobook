#!/usr/bin/env python3
"""CI shard time report: reads the output of `flutter test --file-reporter json:<file>`,
prints a per-test-file time summary + a weight table in the scripts/ci-test-weights.txt format
(added to the GitHub step summary; to measure shard balance / refresh the weights).

Usage: python3 -I scripts/ci-test-timing.py <report.json> [<test-dir=test>]

OBSERVE ONLY: does not affect the gate decision; always exits 0 on any error (does not break CI).
"""
import json
import os
import sys


def main() -> int:
    report = sys.argv[1]
    testdir = sys.argv[2] if len(sys.argv) > 2 else "test"
    files = []
    for root, _dirs, names in os.walk(testdir):
        for n in names:
            if n.endswith("_test.dart") and n != "_ci_shard_test.dart":
                files.append(os.path.relpath(os.path.join(root, n), testdir).replace(os.sep, "/"))
    files.sort(key=len, reverse=True)  # longest prefix first (io/x_test.dart before x_test.dart)

    start, name, dur = {}, {}, {}
    last_time = 0
    with open(report, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith("{"):
                continue
            ev = json.loads(line)
            t = ev.get("type")
            last_time = max(last_time, ev.get("time", 0))
            if t == "testStart":
                start[ev["test"]["id"]] = ev["time"]
                name[ev["test"]["id"]] = ev["test"]["name"]
            elif t == "testDone" and ev["testID"] in start:
                dur[ev["testID"]] = ev["time"] - start[ev["testID"]]

    per = {}
    loading = 0
    for tid, d in dur.items():
        n = name[tid]
        if n.startswith("loading "):
            loading += d
            continue
        for f in files:
            if n.startswith(f + " "):
                per[f] = per.get(f, 0) + d
                break
    body = sum(per.values())
    print("### Test time summary (compile/load reported separately)")
    print(f"- load+compile: {loading / 1000:.1f} s; test body: {body / 1000:.1f} s; "
          f"total: {last_time / 1000:.1f} s; files: {len(per)}")
    print()
    print("| ms | file |")
    print("|---|---|")
    for f, ms in sorted(per.items(), key=lambda kv: -kv[1])[:10]:
        print(f"| {ms} | {f} |")
    print()
    print("<details><summary>weight table (scripts/ci-test-weights.txt format)</summary>")
    print()
    print("```")
    for f in sorted(per):
        print(f"{per[f]} {f}")
    print("```")
    print("</details>")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # observe-only tool: never break the gate
        print(f"ci-test-timing: skipped ({exc})")
        sys.exit(0)
