# Scripts

| Script | Used by | Purpose |
|---|---|---|
| `build_deb_local.sh` | `release.yml`, `make deb` | Build `dist/nexcage-<version>-amd64.deb` with `dpkg-deb` |
| `ci/check_version.sh` | `version-check.yml` | Check that `VERSION` is semver and appears in `nexcage --help` |
| `gen_crun_headers_local.sh` | Dockerfile, crun build notes | Generate vendored crun `config.h` and `git-version.h` |
| `gen_crun_headers_docker.sh` | `make crun-headers` | The same, inside Docker |
| `sync_crun_vendor.sh` | `crun_vendor_sync.yml` | Check for crun updates and sync the vendored copy |
| `mkdocs_build.sh`, `mkdocs_serve.sh` | `make docs-build`, `make docs-serve` | Build or serve the documentation site |
| `setup_secure_runner.sh` | `docs/SECURITY_SELF_HOSTED_RUNNER.md` | Install a hardened self-hosted GitHub Actions runner |
| `fix_runner_service.sh` | run by hand on the runner | Repair the runner's systemd service |
| `manage_github_runner.sh` | run by hand | Start, stop or restart the runner over SSH |
