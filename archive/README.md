# Archive

Kept for reference, not built. `zig build`, `zig build test` and GitHub Actions
do not look in this directory.

## tests/

Tests that could not compile when the suite was first actually wired into
`zig build test` (#239, #240). None of them had ever run. They import modules
that were removed or rewritten — `src/oci/*`, `src/common/*`, the `types`,
`oci`, `image`, `layer` and `performance` modules, local copies of
`vmid_manager.zig` / `state_manager.zig` — or standard library APIs from before
Zig 0.15 (`std.rand`, `std.mem.split`, `ArrayList.init`).

`tests/backends/proxmox-lxc/oci_registry_test.zig` did compile, but it
re-implemented the driver's logic inline instead of calling it, so it tested
copies. The first time it ran, two of its eight tests crashed on bugs in those
copies (a slice with a relative end index, an invalid free). Version parsing
now has real tests in `src/backends/proxmox-lxc/pve.zig`.

Paths mirror their original location under `tests/`. To bring one back, move it
into `tests/` and make it compile against the current modules (`core`,
`backends`, `cli`, `utils`, `integrations`); `zig build test` picks it up
automatically.

Current coverage of the Proxmox LXC path lives next to the code, e.g.
`src/backends/proxmox-lxc/pve.zig` (`pct list` parsing) and
`src/core/config.zig` (the `proxmox` config section).

## src/backend_plugins.zig

A plugin wrapper around the crun and runc drivers. Nothing imports it, and its
tests failed to compile (`file exists in modules 'root' and 'core'`).

## src/cli/example_usage.zig

Usage examples written against an older CLI API. Nothing imports it; it
reached outside its module with relative imports and did not compile.

## workflows/

- `crun_e2e.yml` — invalid YAML, so GitHub rejected it on every push. It tests
  the crun backend, which is opt-in (`-Denable-backend-crun=true`).
- `crun_abi_e2e.yml` — calls build steps that do not exist (`prepare-crun`,
  `-Duse-vendored-libcrun`) on a runner label no runner has.

The crun backend is built in CI by `.github/workflows/crun_build.yml`, through
the Dockerfile.
