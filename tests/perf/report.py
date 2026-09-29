#!/usr/bin/env python3
"""Summarise the samples tests/perf/*.sh write, and compare two labels.

    report.py SAMPLES.tsv...                      a table per label
    report.py SAMPLES.tsv... --compare BASE HEAD  HEAD against BASE; exit 1
                                                  on a regression
    report.py ... --json FILE                     the summary as JSON too

A sample is "label suite op metric value", tab-separated. What counts as a
regression of HEAD against BASE:

  calls      any increase. It is the number of pct/pvesh/pvesm runs, which does
             not vary between runs, and on a real node each one is a Perl
             process costing 0.3-1 s.
  wall_us    the median rose by more than --threshold percent AND by more than
             --min-delta-us, AND HEAD's lower quartile is above BASE's median,
             so that most of HEAD's samples are slower rather than a few. Time
             on a shared machine is noisy; this asks for a shift, not a blip.
  maxrss_kb  rose by more than --threshold percent and 512 KB.

Where one label has both the nexcage-crun and crun suites, the overhead of
nexcage over crun's own binary is shown per operation.
"""
import argparse
import json
import statistics
import sys
from collections import defaultdict


def quantile(xs, q):
    xs = sorted(xs)
    if len(xs) == 1:
        return float(xs[0])
    pos = (len(xs) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (pos - lo)


def load(paths):
    data = defaultdict(list)  # (label, suite, op, metric) -> [values]
    order = []                # (suite, op) in first-seen order, for display
    for path in paths:
        with open(path) as f:
            for n, line in enumerate(f, 1):
                line = line.rstrip("\n")
                if not line:
                    continue
                parts = line.split("\t")
                if len(parts) != 5:
                    sys.exit(f"{path}:{n}: expected 5 tab-separated fields, got {len(parts)}")
                label, suite, op, metric, value = parts
                try:
                    v = float(value)
                except ValueError:
                    sys.exit(f"{path}:{n}: value '{value}' is not a number")
                data[(label, suite, op, metric)].append(v)
                if (suite, op) not in order:
                    order.append((suite, op))
    return data, order


def summarise(data):
    out = defaultdict(dict)  # label -> "suite/op" -> metric -> stats
    for (label, suite, op, metric), xs in data.items():
        out[label].setdefault(f"{suite}/{op}", {})[metric] = {
            "n": len(xs),
            "min": min(xs),
            "q25": quantile(xs, 0.25),
            "median": statistics.median(xs),
            "q75": quantile(xs, 0.75),
            "p95": quantile(xs, 0.95),
            "max": max(xs),
        }
    return out


def ms(us):
    return f"{us / 1000:.2f}"


def table(rows, header):
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    line = lambda r: "  ".join(str(c).ljust(w) if i == 0 else str(c).rjust(w)
                               for i, (c, w) in enumerate(zip(r, widths)))
    print(line(header))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print(line(r))


def show_label(label, summ, order):
    print(f"\n== {label} ==")
    rows = []
    for suite, op in order:
        m = summ.get(f"{suite}/{op}")
        if not m:
            continue
        w = m.get("wall_us")
        rows.append([
            f"{suite}/{op}",
            w["n"] if w else "-",
            ms(w["median"]) if w else "-",
            ms(w["p95"]) if w else "-",
            ms(w["min"]) if w else "-",
            int(m["calls"]["median"]) if "calls" in m else "-",
            int(m["maxrss_kb"]["max"]) if "maxrss_kb" in m else "-",
        ])
    table(rows, ["suite/op", "n", "median ms", "p95 ms", "min ms", "calls", "maxrss KB"])

    pairs = []
    for suite, op in order:
        if suite != "nexcage-crun":
            continue
        a, b = summ.get(f"nexcage-crun/{op}"), summ.get(f"crun/{op}")
        if a and b and "wall_us" in a and "wall_us" in b:
            na, nb = a["wall_us"]["median"], b["wall_us"]["median"]
            pairs.append([op, ms(na), ms(nb), f"{(na - nb) / 1000:+.2f}", f"{na / nb:.2f}x"])
    if pairs:
        print("\nnexcage over crun's own binary (medians):")
        table(pairs, ["op", "nexcage ms", "crun ms", "delta ms", "ratio"])


def compare(base, head, summ, order, threshold, min_delta_us):
    b, h = summ.get(base), summ.get(head)
    if b is None or h is None:
        sys.exit(f"no samples labelled '{base if b is None else head}'")
    print(f"\n== {head} against {base} ==")
    rows, regressions = [], []
    for suite, op in order:
        key = f"{suite}/{op}"
        mb, mh = b.get(key), h.get(key)
        if not mb or not mh:
            continue
        verdict = "ok"
        cells = [key]
        if "wall_us" in mb and "wall_us" in mh:
            wb, wh = mb["wall_us"], mh["wall_us"]
            d = wh["median"] - wb["median"]
            pct = 100.0 * d / wb["median"] if wb["median"] else 0.0
            cells += [ms(wb["median"]), ms(wh["median"]), f"{pct:+.1f}%"]
            if d > min_delta_us and pct > threshold and wh["q25"] > wb["median"]:
                verdict = "SLOWER"
                regressions.append(f"{key}: median {ms(wb['median'])} -> {ms(wh['median'])} ms ({pct:+.1f}%)")
            elif -d > min_delta_us and -pct > threshold and wh["q75"] < wb["median"]:
                verdict = "faster"
        else:
            cells += ["-", "-", "-"]
        if "calls" in mb and "calls" in mh:
            cb, ch = int(mb["calls"]["median"]), int(mh["calls"]["median"])
            cells.append(f"{cb} -> {ch}" if cb != ch else str(ch))
            if ch > cb:
                verdict = "MORE CALLS"
                regressions.append(f"{key}: {cb} -> {ch} pct/pvesh/pvesm calls")
        else:
            cells.append("-")
        if "maxrss_kb" in mb and "maxrss_kb" in mh:
            rb, rh = mb["maxrss_kb"]["max"], mh["maxrss_kb"]["max"]
            cells.append(f"{int(rb)} -> {int(rh)}" if rb != rh else str(int(rh)))
            if rh - rb > 512 and 100.0 * (rh - rb) / rb > threshold:
                verdict = "MORE MEMORY"
                regressions.append(f"{key}: peak RSS {int(rb)} -> {int(rh)} KB")
        else:
            cells.append("-")
        rows.append(cells + [verdict])
    table(rows, ["suite/op", f"{base} ms", f"{head} ms", "change", "calls", "maxrss KB", ""])
    print(f"\n(time: slower only if the median rose > {threshold:g}% and > {ms(min_delta_us)} ms,"
          f" and three quarters of {head}'s samples are above {base}'s median)")
    return regressions


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("samples", nargs="+")
    ap.add_argument("--compare", nargs=2, metavar=("BASE", "HEAD"))
    ap.add_argument("--threshold", type=float, default=10.0, help="percent (default 10)")
    ap.add_argument("--min-delta-us", type=float, default=500.0,
                    help="smallest change in a median that counts, in microseconds (default 500)")
    ap.add_argument("--json", metavar="FILE", help="write the summary here")
    args = ap.parse_args()

    data, order = load(args.samples)
    if not data:
        sys.exit("no samples")
    summ = summarise(data)
    for label in summ:
        show_label(label, summ[label], order)
    regressions = []
    if args.compare:
        regressions = compare(*args.compare, summ, order, args.threshold, args.min_delta_us)
    if args.json:
        with open(args.json, "w") as f:
            json.dump({"summary": summ, "regressions": regressions}, f, indent=2, sort_keys=True)
    if regressions:
        print("\nREGRESSIONS:")
        for r in regressions:
            print(f"  {r}")
        sys.exit(1)


if __name__ == "__main__":
    main()
