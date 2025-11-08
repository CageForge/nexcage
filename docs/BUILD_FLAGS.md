# Build Configuration Flags

Nexcage supports comprehensive build-time configuration through Zig build flags. This allows you to customize which backends, integrations, and features are compiled into your binary, reducing size and dependencies.

## Usage

Build flags are passed to `zig build` using the `-D` prefix:

```bash
zig build -D<flag-name>=<value>
```

All boolean flags default to their specified default values and can be set to `true` or `false`.

## Backend Flags

Control which container/VM backends are compiled into the binary.

### `-Denable-backend-proxmox-lxc=<bool>`
- **Default:** `true`
- **Description:** Enable Proxmox LXC container backend
- **Dependencies:** None
- **Features:** Full Proxmox VE integration, ZFS support, image conversion, VMID management

### `-Denable-backend-proxmox-vm=<bool>`
- **Default:** `true`
- **Description:** Enable Proxmox VM (QEMU) backend
- **Dependencies:** None
- **Features:** QEMU virtual machine management via Proxmox VE

### `-Denable-backend-crun=<bool>`
- **Default:** `true`
- **Description:** Enable Crun OCI container runtime backend
- **Dependencies:** crun binary (runtime) or libcrun (if using ABI mode)
- **Features:** Fast, lightweight OCI-compliant container runtime

### `-Denable-backend-runc=<bool>`
- **Default:** `true`
- **Description:** Enable Runc OCI container runtime backend
- **Dependencies:** runc binary (runtime)
- **Features:** Standard OCI-compliant container runtime

## Integration Flags

Control which external system integrations are compiled into the binary.

### `-Denable-zfs=<bool>`
- **Default:** `true`
- **Description:** Enable ZFS filesystem integration
- **Dependencies:** ZFS utilities (runtime)
- **Features:** ZFS snapshot and volume management for containers

### `-Denable-bfc=<bool>`
- **Default:** `true`
- **Description:** Enable BFC (Binary Format Converter) integration
- **Dependencies:** BFC library
- **Features:** Container image format conversion and manipulation

### `-Denable-proxmox-api=<bool>`
- **Default:** `true`
- **Description:** Enable Proxmox API client integration
- **Dependencies:** None
- **Features:** Direct interaction with Proxmox VE API

## Feature Flags

Control specific runtime features and behaviors.

### `-Denable-libcrun-abi=<bool>`
- **Default:** `false`
- **Description:** Enable direct libcrun ABI integration (instead of CLI driver)
- **Dependencies:**
  - libcrun (build & runtime)
  - libsystemd (build & runtime)
- **Features:**
  - Direct library calls to libcrun instead of subprocess execution
  - Potentially better performance
  - More complex dependencies
- **Note:** When enabled, automatically links libcrun and systemd libraries

### `-Denable-plugins=<bool>`
- **Default:** `true`
- **Description:** Enable plugin system support
- **Dependencies:** None
- **Features:** Dynamic plugin loading and lifecycle management

## Legacy Flags

These flags are maintained for backward compatibility but may be deprecated in future versions.

### `-Dlink-libcrun=<bool>`
- **Default:** Value of `enable-libcrun-abi`
- **Description:** Manually link libcrun and systemd libraries
- **Deprecated:** Use `-Denable-libcrun-abi=true` instead

## Build Examples

### Full Build (Default)
Build with all features enabled:
```bash
zig build
```

### Minimal Build
Build with only Runc backend, no integrations:
```bash
zig build \
  -Denable-backend-proxmox-lxc=false \
  -Denable-backend-proxmox-vm=false \
  -Denable-backend-crun=false \
  -Denable-zfs=false \
  -Denable-bfc=false \
  -Denable-proxmox-api=false \
  -Denable-plugins=false
```

### Proxmox-Only Build
Build for Proxmox environments only:
```bash
zig build \
  -Denable-backend-crun=false \
  -Denable-backend-runc=false
```

### OCI-Only Build
Build for OCI runtimes only (no Proxmox):
```bash
zig build \
  -Denable-backend-proxmox-lxc=false \
  -Denable-backend-proxmox-vm=false \
  -Denable-proxmox-api=false
```

### Crun with Direct ABI
Build with Crun using direct library calls:
```bash
zig build -Denable-libcrun-abi=true
```

### Lightweight Container Build
Build with only Crun and Runc, minimal integrations:
```bash
zig build \
  -Denable-backend-proxmox-lxc=false \
  -Denable-backend-proxmox-vm=false \
  -Denable-proxmox-api=false \
  -Denable-plugins=false
```

## Programmatic Access

You can check which backends and integrations are enabled at compile time using the helper functions:

```zig
const backends = @import("backends");
const integrations = @import("integrations");

// Check if backends are enabled
if (backends.isProxmoxLxcEnabled()) {
    // Use Proxmox LXC backend
}

if (backends.isCrunEnabled()) {
    // Use Crun backend
}

// Check if integrations are enabled
if (integrations.isZfsEnabled()) {
    // Use ZFS features
}

if (integrations.isBfcEnabled()) {
    // Use BFC features
}
```

## Runtime Behavior

Disabling a backend or integration at build time will:
1. Remove all related code from the binary (reducing size)
2. Remove compile-time dependencies
3. Make the backend/integration unavailable at runtime
4. Cause runtime errors if configuration attempts to use disabled backends

**Important:** If you disable a backend that is set as the default runtime in your configuration, you must either:
- Change the default runtime in your config.json
- Explicitly specify a different runtime via `--runtime` flag
- Keep at least one backend enabled

## Build Size Impact

Approximate binary size reduction when disabling features (varies by architecture):

- Each backend: ~200-500KB
- ZFS integration: ~50KB
- BFC integration: ~100KB
- Proxmox API: ~150KB
- Plugin system: ~80KB
- libcrun ABI (when enabled): Adds ~1-2MB due to library linking

A minimal build (single backend, no integrations) can be ~70% smaller than a full build.

## Troubleshooting

### Build Errors

**Error:** Undefined symbols when enabling libcrun ABI
```
Solution: Ensure libcrun-dev and libsystemd-dev are installed:
  - Ubuntu/Debian: apt-get install libcrun-dev libsystemd-dev
  - Fedora: dnf install crun-devel systemd-devel
```

**Error:** Backend not found at runtime
```
Solution: The backend was disabled at build time. Rebuild with:
  zig build -Denable-backend-<name>=true
```

### Runtime Errors

**Error:** "Runtime type 'crun' not available"
```
Cause: Crun backend was disabled at build time
Solution: Either rebuild with -Denable-backend-crun=true or use a different runtime
```

## See Also

- [Build System Documentation](build-system.md)
- [Configuration Guide](configuration.md)
- [Backend Documentation](backends.md)
- [Contributing Guide](../CONTRIBUTING.md)
