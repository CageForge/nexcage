#!/usr/bin/env python3
"""critest's results, checked against tests/cri/critest-known-failures.

    critest_check.py <report.json> <known-failures> [<reference.json>]

The reports are ginkgo's --ginkgo.json-report: nexcage's, and optionally the
same suite through another runtime, whose result is printed beside each
failure. A spec that fails and is not listed is a regression; a listed spec
that does not fail is stale. Either is exit 1, and so is a failure outside any
spec, such as the suite's setup, which leaves every spec skipped.
"""
import json
import sys

FAILED = ("failed", "panicked", "timedout", "aborted", "interrupted")


def first_line(text):
    return (text or "").strip().splitlines()[0][:300] if (text or "").strip() else ""


def results(path):
    specs, setup = {}, []
    for suite in json.load(open(path)):
        for s in suite.get("SpecReports") or []:
            message = (s.get("Failure") or {}).get("Message")
            if s["LeafNodeType"] != "It":
                if s["State"] in FAILED:
                    setup.append(f"{s['LeafNodeType']}: {first_line(message)}")
                continue
            name = " ".join((s.get("ContainerHierarchyTexts") or []) + [s["LeafNodeText"]])
            specs[name] = (s["State"], message)
    return specs, setup


def known_failures(path):
    """A spec's full name on one line, the reason on the indented lines after
    it. `~name` is printed but not checked."""
    known, either, name = {}, {}, None
    for line in open(path):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[0].isspace():
            if name is None:
                sys.exit(f"{path}: a reason with no spec before it: {line.strip()}")
            target = either if name in either else known
            target[name] = (target[name] + " " + line.strip()).strip()
        else:
            name = line.strip()
            if name.startswith("~"):
                name = name[1:].strip()
                either[name] = ""
            else:
                known[name] = ""
    return known, either


def main(report, known_path, reference=None):
    specs, setup = results(report)
    known, either = known_failures(known_path)
    other = results(reference)[0] if reference else {}

    def crun_says(name):
        if not reference:
            return ""
        state = other.get(name, ("not run", None))[0]
        return " (crun: " + ("fails too" if state in FAILED else state) + ")"

    bad = 0
    print("=== against tests/cri/critest-known-failures")
    for line in setup:
        bad += 1
        print(f"SETUP       {line}")
    for name, (state, message) in sorted(specs.items()):
        if name in either:
            continue
        if state in FAILED and name not in known:
            bad += 1
            print(f"REGRESSION  {name}{crun_says(name)}\n            {first_line(message)}")
        elif state not in FAILED and name in known:
            bad += 1
            print(f"STALE       {name}: listed as a known failure, and {state}: take it off the list")
    for name in sorted({**known, **either}):
        if name not in specs:
            bad += 1
            print(f"STALE       {name}: listed, but critest has no such spec")

    def tally(results):
        count = {}
        for state, _ in results.values():
            count[state] = count.get(state, 0) + 1
        return ", ".join(f"{n} {s}" for s, n in sorted(count.items())) + f", of {len(results)}"

    print("critest through nexcage: " + tally(specs))
    if reference:
        print("critest through crun:    " + tally(other))
    for name in sorted(known):
        if name in specs and specs[name][0] in FAILED:
            print(f"known       {name}{crun_says(name)}\n            {known[name]}")
    for name in sorted(either):
        if name in specs:
            print(f"unchecked   {name}: {specs[name][0]} this time\n            {either[name]}")
    for name, (state, message) in sorted(specs.items()):
        if state == "skipped" and first_line(message):
            print(f"skipped     {name}\n            {first_line(message)}")
    if bad:
        print(f"{bad} result(s) differ from critest-known-failures")
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
