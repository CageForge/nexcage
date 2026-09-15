# Architecture Overview

nexcage is a single binary that runs on a Proxmox VE host. It turns CLI
commands into `pct` and `pvesh` calls and keeps a small amount of state under
`/run/nexcage`.

```mermaid
flowchart TD
  user([User or script]) -->|nexcage command| main["main.zig<br/>parse arguments, report errors"]
  main --> registry["cli/registry.zig"]
  registry --> cmd["cli/COMMAND.zig"]
  cmd --> router["cli/router.zig"]
  cfg[("config.json")] --> router
  router --> lxc["Proxmox LXC backend"]
  router -.->|opt-in builds| other["crun, runc, VM backends"]
  lxc -->|pct, pvesh| pve[("Proxmox VE")]
```

A `start`, end to end:

```mermaid
sequenceDiagram
  participant U as User
  participant C as nexcage start
  participant R as Router
  participant D as ProxmoxLxcDriver
  participant P as pct

  U->>C: nexcage start web-1
  C->>R: route web-1
  R->>D: start(web-1)
  D->>P: pct list
  P-->>D: web-1 is VMID 101
  D->>P: pct start 101
  P-->>D: exit 0
  D-->>C: ok, state.json says running
  C-->>U: exit 0
```

[MODULES.md](MODULES.md) shows the Zig modules; [BACKENDS.md](BACKENDS.md)
lists what each backend runs.
