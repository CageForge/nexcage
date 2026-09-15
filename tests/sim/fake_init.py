#!/usr/bin/env python3
"""Stands in for a container's init in tests/sim.

Fake `pct start` runs this in the background and records its PID, which fake
`pct status --verbose` reports as the init's host PID. Every signal it catches
is appended by name to the file given as the argument, so run.sh can check
which signal nexcage sent. SIGKILL cannot be caught: the process ends, and
fake pct then reports the container as stopped.
"""
import signal
import sys

log = sys.argv[1]


def record(signum, _frame):
    with open(log, "a") as f:
        f.write(signal.Signals(signum).name + "\n")


for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT, signal.SIGUSR1, signal.SIGUSR2, signal.SIGCONT):
    signal.signal(sig, record)

# Fake pct start waits for this line, so no signal arrives before the handlers
with open(log, "a") as f:
    f.write("READY\n")

while True:
    signal.pause()
