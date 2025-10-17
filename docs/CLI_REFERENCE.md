# CLI Reference

All commands support `--help` for detailed usage.

## Global
- `--config <path>` use specific config file
- `--debug`, `--verbose` enable logging

## Commands

### version
Show version info.
```bash
nexcage version
```

### help
Show global help.
```bash
nexcage --help
```

### create
Create a new container (backend is auto-selected by routing rules; LXC by default).
```bash
nexcage create --name <id> --image <bundle_dir> [--runtime lxc|crun|runc|vm]
```
- `<bundle_dir>` must contain `config.json` (OCI bundle)
- If `config.json` contains `annotations.org.opencontainers.image.ref.name` (or `image`), the value is treated as LXC template name and validated against `pveam list/available`. If available, it will be used as `local:vztmpl/<image>` for `pct create`.
- If no valid image is found, a fallback template is auto-selected from `pveam available`.

Examples:
```bash
# Create from bundle with image reference inside config.json
nexcage create --name web-01 --image /tmp/mybundle

# Explicitly route to LXC backend (if needed)
nexcage create --name api-01 --image /tmp/mybundle --runtime lxc
```

### start
Start a container.
```bash
nexcage start --name <id>
```

### stop
Stop a container.
```bash
nexcage stop --name <id>
```

### delete
Delete a container.
```bash
nexcage delete --name <id>
```

### list
List containers across all backends with a unified schema (id, name, status, backend, runtime).
```bash
nexcage list
```
- For Proxmox LXC, uses `pct list`
- Output aggregates results across supported backends and includes `backend_type` and `runtime` fields

Notes:
- E2E requires running on Proxmox host with necessary tools
- See docs/DEV_QUICKSTART.md for setup and docs/architecture/ for details
