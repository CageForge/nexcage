# Scripts

| Script | Used by | Purpose |
|---|---|---|
| `dev.sh` | `make doctor`, `dev-setup`, `e2e`, `act`, `local-ci`, `perf`, `dev-shell` | Local development: tools, builds, the simulator, the crun and CRI tests, CI jobs through act, performance ([docs/LOCAL_DEVELOPMENT.md](../docs/LOCAL_DEVELOPMENT.md)) |
| `build_deb_local.sh` | `release.yml`, `make deb` | Build `dist/nexcage-<version>-amd64.deb` with `dpkg-deb` |
| `ci/check_version.sh` | `version-check.yml` | Check that `VERSION` is semver, matches `build.zig.zon` and appears in `nexcage --help` |
| `gen_crun_headers_local.sh` | Dockerfile, crun build notes | Generate vendored crun `config.h` and `git-version.h` |
| `gen_crun_headers_docker.sh` | `make crun-headers` | The same, inside Docker |
| `check_features_abi.sh` | `crun_build.yml`, `dev.sh crun` (also `make e2e`), by hand when bumping deps/crun | Compare the field order of the features structs in the vendored crun `container.h` with the order the Zig mirror in `src/backends/crun/libcrun_ffi.zig` was written for |
| `mkdocs_build.sh`, `mkdocs_serve.sh` | `make docs-build`, `make docs-serve` | Build or serve the documentation site |
| `setup_secure_runner.sh` | `docs/SECURITY_SELF_HOSTED_RUNNER.md` | Install a hardened self-hosted GitHub Actions runner |
| `fix_runner_service.sh` | run by hand on the runner | Repair the runner's systemd service |
| `manage_github_runner.sh` | run by hand | Start, stop or restart the runner over SSH |
| `register_e2e_runner.sh` | run by hand on the E2E node (piped over ssh, token on stdin) | Register the GitHub Actions runner with labels `proxmox,pve9,nexcage-e2e` and install it as a service with `svc.sh` |
