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
nexcage create --name <id> --image <image> [--runtime lxc|crun|runc|vm]
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
List containers (for LXC this uses pct/lxc tools).
```bash
nexcage list --runtime lxc
```

Notes:
- E2E requires running on Proxmox host with necessary tools
- See docs/DEV_QUICKSTART.md for setup and docs/architecture/ for details
