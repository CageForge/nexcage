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

Tests for code that no longer exists are in `archive/tests/`; see
[archive/README.md](archive/README.md) for why and how to bring one back.

## Running against fake Proxmox tools

Most of nexcage's behaviour is the command lines it gives `pct` and `pvesh`
and how it reads their output. That can be checked without a Proxmox host by
putting small scripts named `pct`, `pvesh` and `pveversion` first in `PATH`
that log their arguments and print what the real tools print — `pct list`
uses `printf "%-10s %-10s %-12s %-20s\n"` for VMID, Status, Lock and Name.

Run as a normal user, `create` stops after `pct create` because it cannot
write `/run/nexcage`; the arguments it passed are what matter.

## Proxmox E2E

`.github/workflows/proxmox_e2e.yml` runs on a self-hosted Proxmox VE runner:

1. builds nexcage and runs `--help` / `version`
2. writes `./config.json` with the runner's bridge and storage
3. `create` from a template → `state` is `stopped` → a duplicate `create` fails
4. `list` shows the container → `start` → `state` is `running`
5. `stop` → `state` is `stopped` → `delete` → pct no longer lists it
6. `state` and `start` on the deleted container fail

A cleanup trap destroys the container if any step fails. Runner requirements
are in [docs/CI_CD_SETUP.md](docs/CI_CD_SETUP.md).

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
