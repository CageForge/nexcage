# Developer Quickstart

## Requirements

- Linux, amd64
- Zig 0.15.1
- A Proxmox VE 9.x host to run containers; building and unit tests work
  anywhere

The default build links only libc. `oci-spec-zig` is vendored in
`deps/oci-spec-zig`, so the build downloads nothing.

## Everything in one command

`scripts/dev.sh` checks the tools, builds, runs every test that works without
Proxmox — the simulator, the crun backend, a pod through containerd — runs the
CI jobs through act, and times the lifecycle commands. See
[LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md).

```bash
scripts/dev.sh doctor     # what is missing, and how to get it
scripts/dev.sh check      # zig fmt, unit tests, the simulator
scripts/dev.sh all        # what a pull request runs, minus Proxmox
```

## Build, test, run

```bash
zig build                      # Debug binary in zig-out/bin/nexcage
zig build test --summary all   # every test step and its result
zig build -Doptimize=ReleaseSafe

./zig-out/bin/nexcage --help
./zig-out/bin/nexcage version
```

Without Proxmox tools, operations fail cleanly — useful for checking error
paths:

```bash
./zig-out/bin/nexcage list; echo "exit $?"
# ERROR nexcage: 'pvesh' not found in PATH; nexcage must run on a Proxmox VE host
# ERROR nexcage: the cluster's listing of its containers (pvesh get /cluster/resources) could not be read
# nexcage: list: not supported on this host or by this build
# exit 1
```

A command on one container stops before that: `start web-1` says that no
backend has a record of `web-1`, which only a `create` writes.

## Build options

| Option | Default | Effect |
|---|---|---|
| `-Denable-backend-crun` | `false` | crun backend; links vendored libcrun |
| `-Denable-libcrun-abi` | follows crun | Compile `deps/crun`; needs the submodules and generated headers |

The Proxmox LXC backend is always built. A compiled-out crun backend is
refused at run time with `UnsupportedOperation`.

### crun backend

Easiest through Docker, which clones the pinned dependencies and generates the
headers:

```bash
docker build --build-arg BUILD_FLAGS=-Denable-backend-crun=true -t nexcage:crun .
docker run --rm nexcage:crun version
```

Locally, mirror the Dockerfile: `git submodule update --init --recursive`,
`bash scripts/gen_crun_headers_local.sh`, generate `libocispec` headers with
`generate.py`, then `zig build -Denable-backend-crun=true`.

## Where things live

| Path | Contents |
|---|---|
| `src/main.zig` | Argument parsing, error reporting, exit codes |
| `src/cli/` | Commands and the backend router |
| `src/backends/proxmox-lxc/` | pct/pvesh driver (`driver.zig`, `pve.zig`) |
| `src/core/` | Config, logging, shared types |
| `deps/oci-spec-zig/` | OCI runtime/image types and the bundle parser |

## Proxmox E2E

The "Proxmox E2E (Self-Hosted)" workflow drives create → state → start → stop
→ delete through the built binary on a self-hosted runner with the `pve9`
label. Runner requirements are in [CI_CD_SETUP.md](CI_CD_SETUP.md).

## Next

- [CLI_REFERENCE.md](CLI_REFERENCE.md)
- [../TESTING.md](../TESTING.md)
- [architecture/OVERVIEW.md](architecture/OVERVIEW.md)
