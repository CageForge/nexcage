#!/usr/bin/env python3
"""The runtime-spec validation suite's results, and what they are checked against.

    validate.py run <out.json> <test.t>...      RUNTIME names the runtime
    validate.py check <nexcage.json> <crun.json> <known-failures>

runtime-tools writes TAP 13 whose diagnostics are JSON objects, which Perl's
prove cannot parse, and upstream expects node-tap; this reads the lines it
needs and nothing else. A test passes when it exits 0 with no `not ok`: the
`*_fail` tests print no plan at all when the runtime refuses what it should.
"""
import json
import os
import re
import subprocess
import sys

LINE = re.compile(r"^(not ok|ok) (\d+)(?: - (.*?))?(?:\s+# (SKIP|TODO)\b.*)?$")


def run(out_json, tests):
    timeout = int(os.environ.get("RT_TIMEOUT", "300"))
    results = {}
    for path in tests:
        name = os.path.basename(os.path.dirname(path))
        try:
            p = subprocess.run([path], capture_output=True, text=True, timeout=timeout)
            out, rc, err = p.stdout, p.returncode, p.stderr
        except subprocess.TimeoutExpired:
            out, rc, err = "", "timeout", ""
        ok = skip = 0
        failed = []
        for line in out.splitlines():
            m = LINE.match(line)
            if not m:
                continue
            if m.group(4):
                skip += 1
            elif m.group(1) == "ok":
                ok += 1
            else:
                failed.append(m.group(3) or "#" + m.group(2))
        passed = rc == 0 and not failed
        results[name] = {"pass": passed, "ok": ok, "skip": skip, "rc": rc, "failed": failed}
        print(f"{'PASS' if passed else 'FAIL'}  {name}  ok={ok} skip={skip} rc={rc}", flush=True)
        for f in failed:
            print(f"        not ok: {f}", flush=True)
        if not passed and not failed:
            # Died before reporting: show why, which is on stdout or stderr.
            for l in (out + "\n" + err).strip().splitlines()[-4:]:
                print(f"        {l[:300]}", flush=True)
    with open(out_json, "w") as f:
        json.dump(results, f, indent=1, sort_keys=True)


def check(nexcage_json, crun_json, known_path):
    nx = json.load(open(nexcage_json))
    crun = json.load(open(crun_json))
    known = {}
    for line in open(known_path):
        line = line.split("#", 1)[0].strip()
        if line:
            name, _, why = line.partition(" ")
            known[name] = why.strip()

    def crun_says(name):
        r = crun.get(name)
        return "not run" if r is None else ("passes" if r["pass"] else "fails too")

    bad = 0
    print("=== against tests/runtime-tools/known-failures")
    for name in sorted(nx):
        r = nx[name]
        if not r["pass"] and name not in known:
            bad += 1
            print(f"REGRESSION  {name}: fails with nexcage; crun {crun_says(name)}")
        elif r["pass"] and name in known:
            bad += 1
            print(f"STALE       {name}: listed as a known failure, and passes now: take it off the list")
    for name in sorted(known):
        if name not in nx:
            bad += 1
            print(f"STALE       {name}: listed, but the suite has no such test")
    passed = sum(1 for r in nx.values() if r["pass"])
    print(f"nexcage: {passed} of {len(nx)} tests pass; crun: "
          f"{sum(1 for r in crun.values() if r['pass'])} of {len(crun)}")
    for name in sorted(known):
        if name in nx and not nx[name]["pass"]:
            print(f"known       {name}: {known[name]} (crun {crun_says(name)})")
    if bad:
        print(f"{bad} result(s) differ from known-failures")
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "run":
        run(sys.argv[2], sys.argv[3:])
    elif len(sys.argv) == 5 and sys.argv[1] == "check":
        sys.exit(check(*sys.argv[2:]))
    else:
        sys.exit(__doc__)
