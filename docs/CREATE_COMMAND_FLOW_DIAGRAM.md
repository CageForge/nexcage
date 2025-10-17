# Create Command Flow Diagram

## Complete Architecture Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                USER COMMAND                                     │
│  nexcage create --name my-container --image /path/to/oci-bundle                │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CLI LAYER                                          │
│  src/cli/create.zig                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ CreateCommand.execute()                                                 │   │
│  │ ├─ Validate --name and --image                                          │   │
│  │ ├─ Create network config with default bridge                           │   │
│  │ └─ Call BackendRouter.routeAndExecute()                                │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            ROUTER LAYER                                         │
│  src/cli/router.zig                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ BackendRouter.routeAndExecute()                                         │   │
│  │ ├─ Determine backend type (proxmox_lxc)                                │   │
│  │ ├─ Create SandboxConfig                                                │   │
│  │ ├─ Initialize ProxmoxLxcDriver                                         │   │
│  │ └─ Call driver.create()                                                │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            DRIVER LAYER                                         │
│  src/backends/proxmox-lxc/driver.zig                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ ProxmoxLxcDriver.create()                                              │   │
│  │ ├─ Check if config.image exists                                        │   │
│  │ ├─ Call processOciBundle() if bundle found                             │   │
│  │ ├─ Generate VMID from container name                                   │   │
│  │ ├─ Resolve template (existing or converted)                           │   │
│  │ ├─ Execute pct create command                                         │   │
│  │ ├─ Apply mounts to LXC config                                         │   │
│  │ └─ Verify configuration                                               │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        OCI BUNDLE PROCESSING                                    │
│  processOciBundle()                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Parse OCI bundle config.json                                        │   │
│  │ 2. Check for existing template                                          │   │
│  │ 3. If no template exists:                                               │   │
│  │    ├─ Generate unique template name                                     │   │
│  │    ├─ Call ImageConverter.convertOciToProxmoxTemplate()                │   │
│  │    └─ Return template name                                              │   │
│  │ 4. If template exists:                                                  │   │
│  │    └─ Return existing template name                                     │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        IMAGE CONVERTER                                          │
│  src/backends/proxmox-lxc/image_converter.zig                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ ImageConverter.convertOciToProxmoxTemplate()                           │   │
│  │ ├─ convertOciToLxcRootfs()                                             │   │
│  │ │  ├─ Parse OCI bundle configuration                                   │   │
│  │ │  ├─ Extract rootfs (tar.zst/tar.gz/tar)                             │   │
│  │ │  ├─ Copy directory contents                                          │   │
│  │ │  └─ Apply LXC configurations                                         │   │
│  │ │     ├─ Create essential directories                                  │   │
│  │ │     ├─ Set hostname                                                  │   │
│  │ │     ├─ Configure network interfaces                                  │   │
│  │ │     └─ Set up init system                                            │   │
│  │ ├─ createProxmoxTemplate()                                             │   │
│  │ │  ├─ Create template archive (tar.zst)                               │   │
│  │ │  └─ Upload to /var/lib/vz/template/cache/                           │   │
│  │ └─ cleanupDirectory()                                                  │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        CONTAINER CREATION                                       │
│  pct create command execution                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ 1. pct create <vmid> <template>                                        │   │
│  │ 2. Apply mounts to /etc/pve/lxc/<vmid>.conf                           │   │
│  │ 3. pct config <vmid> (validation)                                      │   │
│  │ 4. Container ready for start                                           │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Decision Flow for Template Resolution

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           OCI BUNDLE INPUT                                     │
│  /path/to/oci-bundle/                                                          │
│  ├── config.json                                                               │
│  └── rootfs/                                                                   │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        PARSE CONFIG.JSON                                       │
│  Extract annotations["org.opencontainers.image.ref.name"]                      │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    CHECK FOR EXISTING TEMPLATE                                 │
│  pveam list local | grep <image_ref>                                           │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                    ┌─────┴─────┐
                    │           │
                    ▼           ▼
┌─────────────────────────┐ ┌─────────────────────────────────────────────────────┐
│    TEMPLATE EXISTS     │ │           TEMPLATE NOT FOUND                        │
│                        │ │                                                     │
│ Use existing template  │ │ 1. Generate unique name:                           │
│ local:vztmpl/<name>    │ │    <container_name>-<timestamp>                    │
│                        │ │ 2. Convert OCI → LXC rootfs                        │
│                        │ │ 3. Apply LXC configurations                        │
│                        │ │ 4. Create template archive                         │
│                        │ │ 5. Upload to template storage                      │
│                        │ │ 6. Use new template                                │
└─────────────────────────┘ └─────────────────────────────────────────────────────┘
                    │           │
                    └─────┬─────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        CREATE CONTAINER                                         │
│  pct create <vmid> <template>                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## File System Operations During Conversion

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        OCI BUNDLE STRUCTURE                                    │
│  /path/to/bundle/                                                              │
│  ├── config.json          # OCI configuration                                  │
│  ├── rootfs/              # Container filesystem                               │
│  │   ├── bin/                                                                  │
│  │   ├── etc/                                                                  │
│  │   ├── usr/                                                                  │
│  │   └── ...                                                                   │
│  └── (other OCI files)                                                         │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        TEMPORARY ROOTFS                                        │
│  /tmp/lxc-rootfs-<template_name>/                                              │
│  ├── bin/              # Copied from OCI rootfs                                │
│  ├── etc/              # Enhanced with LXC configs                             │
│  │   ├── hostname      # Set from bundle config                                │
│  │   ├── network/      # LXC network configuration                             │
│  │   │   └── interfaces                                                         │
│  │   └── ...                                                                   │
│  ├── sbin/             # LXC init system                                       │
│  │   └── init          # Custom LXC init script                                │
│  ├── dev/              # Essential LXC directories                             │
│  ├── proc/                                                                     │
│  ├── sys/                                                                      │
│  └── ...                                                                       │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        TEMPLATE ARCHIVE                                         │
│  /var/lib/vz/template/cache/<template_name>.tar.zst                            │
│  └── Compressed LXC rootfs ready for Proxmox                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Error Handling Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           ERROR SCENARIOS                                      │
│                                                                                 │
│ 1. Bundle Not Found                                                             │
│    └─ Return: core.Error.FileNotFound                                          │
│                                                                                 │
│ 2. Invalid Bundle Structure                                                     │
│    └─ Return: core.Error.InvalidConfig                                         │
│                                                                                 │
│ 3. Conversion Failure                                                           │
│    ├─ Archive extraction fails                                                  │
│    ├─ LXC configuration fails                                                  │
│    ├─ Template creation fails                                                  │
│    └─ Storage upload fails                                                     │
│                                                                                 │
│ 4. Container Creation Failure                                                   │
│    ├─ pct create fails                                                          │
│    ├─ Mount configuration fails                                                │
│    └─ Validation fails                                                          │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Performance Characteristics

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        PERFORMANCE METRICS                                     │
│                                                                                 │
│ Template Resolution:                                                            │
│ ├─ Existing template: ~100ms                                                   │
│ └─ New conversion: ~30-60s (depending on bundle size)                          │
│                                                                                 │
│ Resource Usage:                                                                 │
│ ├─ Disk: ~2x bundle size (temporary extraction)                                │
│ ├─ CPU: Archive compression/decompression                                      │
│ ├─ Memory: File operations and parsing                                         │
│ └─ Network: None (local operations only)                                       │
│                                                                                 │
│ Optimization:                                                                   │
│ ├─ Template caching (reuse existing)                                           │
│ ├─ Parallel processing during create                                           │
│ ├─ Incremental updates (only when needed)                                      │
│ └─ Proper cleanup of temporary files                                           │
└─────────────────────────────────────────────────────────────────────────────────┘
```

This flow diagram shows the complete architecture from user command to container creation, highlighting the automatic OCI bundle conversion process that happens transparently during the create operation.
