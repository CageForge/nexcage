# Developer Quickstart

## Requirements

- Linux, amd64
- Zig 0.15.1
- A Proxmox VE 8.x/9.x host to run containers; building and unit tests work
  anywhere

The default build links only libc. The first build may download the pinned
`oci-specs-zig` package from `build.zig.zon`.

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
./zig-out/bin/nexcage start web-1; echo "exit $?"
# ERROR nexcage: 'pct' not found in PATH; nexcage must run on a Proxmox VE host
# nexcage: start: not supported on this host or by this build
# exit 1
```

## Build options

| Option | Default | Effect |
|---|---|---|
| `-Denable-backend-proxmox-lxc` | `true` | Proxmox LXC backend |
| `-Denable-backend-crun` | `false` | crun backend; links vendored libcrun |
| `-Denable-libcrun-abi` | follows crun | Compile `deps/crun`; needs the submodules and generated headers |
| `-Denable-backend-runc` | `false` | runc backend (calls the runc binary) |
| `-Denable-backend-proxmox-vm` | `false` | VM backend (not integrated) |

A compiled-out backend is refused at run time with `UnsupportedOperation`.

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
→ delete through the built binary on a runner with the `proxmox` label. Runner
requirements are in [CI_CD_SETUP.md](CI_CD_SETUP.md).

## Next

- [CLI_REFERENCE.md](CLI_REFERENCE.md)
- [../TESTING.md](../TESTING.md)
- [architecture/OVERVIEW.md](architecture/OVERVIEW.md)
