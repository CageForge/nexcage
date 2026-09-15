# Testing

## Unit tests

```bash
zig build test --summary all
```

`build.zig` walks `tests/` and `src/` and adds one test step per `.zig` file
that declares a `test "…"` block. A file that fails to compile fails as its own
step, by name, instead of hiding the files after it. There is no list to
maintain: a new test file is picked up automatically.

Tests that exercise real code live next to it:

| File | Covers |
|---|---|
| `src/backends/proxmox-lxc/pve.zig` | `pct list` parsing (locks, header, name matching), Proxmox VE version parsing |
| `src/core/config.zig` | The `proxmox` and `network` config sections, bounds, defaults |
| `src/core/constants.zig` | Defaults (bridge, memory, rootfs size) |
| `tests/oci/*_simple_test.zig`, `tests/simple_*.zig` | Self-contained checks of OCI types and validation |

## Running against fake Proxmox tools

Most of nexcage's behaviour is the command lines it gives `pct`, `pvesh` and
`pvesm` and how it reads their output. `tests/sim/run.sh` checks that for every
command without a Proxmox host:

```bash
zig build && tests/sim/run.sh     # or: make sim
```

`tests/sim/bin` holds scripts named `pct`, `pvesh`, `pvesm`, `pveversion`,
`pveam`, `zfs` and `zpool`. They keep a small container database, log their
arguments and print what the real tools print (`pct list` uses
`printf "%-10s %-10s %-12s %-20s\n"` for VMID, Status, Lock and Name). Like the
real pct, the fake refuses a template volume that does not exist, and it lists
the archive nexcage packs from an OCI bundle so the run can check what went
into it. Files named `fail_*`, `no_kill` and `lock.<vmid>` in the scratch
directory make the tools fail or report a lock.

nexcage runs as uid 0 in a user and mount namespace, with `/run` and
`/tmp/nexcage-bundles` bound to `zig-out/sim` and a tmpfs over `/tmp`, so it
writes `/run/nexcage` without root and without touching the host. The run
checks the arguments passed, exit codes, stdout, state files, option parsing,
`--runtime`, OCI bundles and failures such as `pct list` refusing to run. An
allocator leak report, panic or invalid free in any command fails it.

CI runs it in `ci.yml`. Ubuntu 24.04 does not allow mounts in an unprivileged
user namespace by default; there, run
`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` first.

## Proxmox E2E

`.github/workflows/proxmox_e2e.yml` runs on a self-hosted Proxmox VE runner:

1. builds nexcage and runs `--help` / `version`
2. writes `./config.json` with the runner's bridge and storage
3. `create` from a template → `state` is `stopped` → `pct config` shows the
   hostname, the bridge and a 2 GB rootfs on the configured storage
4. a duplicate `create` exits 1; an invalid name and an unknown `--runtime`
   exit 2; `list` shows the container, and `list` without root exits 1
5. `start` → `running`; `state --log-level warn <name>` (an option after the
   command) reports the right container; `kill <name> SIGCONT` succeeds and the
   container keeps running (skipped with a warning when `pct exec` itself fails
   on the runner); a malformed signal exits 2
6. `stop` → `stopped`; `kill` on it exits 1; `delete` → pct no longer lists it;
   `state` and `start` on it exit 1
7. `run` → `running` → `stop` → `delete`
8. an OCI bundle under `/var/lib/nexcage/bundles/` whose `rootfs/` is the
   extracted template: `create` → `stopped`, and the template packed from it is
   gone from storage `local` → `start` → `running` → `stop` → `delete`

A cleanup trap destroys the containers and the bundle if any step fails, and a
final step removes anything named `gh-e2e-*` a cancelled run left behind.
Runner requirements are in [docs/CI_CD_SETUP.md](docs/CI_CD_SETUP.md).

To run the same sequence by hand on a Proxmox VE host, as root:

```bash
nexcage create --name e2e-1 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
nexcage state e2e-1
nexcage start e2e-1 && nexcage state e2e-1
nexcage stop e2e-1 && nexcage state e2e-1
nexcage delete e2e-1
nexcage state e2e-1; echo "exit $?"   # 1
```

## Memory checks

`memory_leak_check.yml` runs basic commands under Valgrind. Debug builds also
use Zig's GeneralPurposeAllocator, which reports leaks on exit.
