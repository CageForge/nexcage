# Sprint 6.3: OCI Bundle Generator

## Task: OCI bundle generator (rootfs + minimal config.json)

**Objective:** Implement minimal bundle generator and verify with local smoke tests.

## Acceptance Criteria
- [ ] Bundle generator creates valid OCI bundle structure (rootfs/ + config.json)
- [ ] Minimal config.json includes required OCI runtime spec fields
- [ ] Local smoke tests verify bundle creation and basic validation
- [ ] Integration with existing OCI workflow

## Implementation Plan

### 1. Core Bundle Generator Module
**File:** `src/oci/bundle_generator.zig`

**Features:**
- Create bundle directory structure
- Generate minimal config.json with:
  - OCI version
  - Process configuration (args, env, cwd)
  - Root filesystem path
  - Linux namespace configuration
  - Basic resource limits
- Validate bundle structure

### 2. Rootfs Management
**File:** `src/oci/rootfs.zig`

**Features:**
- Create rootfs directory
- Copy/extract base filesystem
- Set proper permissions
- Validate rootfs structure

### 3. Config.json Generator
**File:** `src/oci/config_generator.zig`

**Features:**
- Generate OCI runtime spec compliant config.json
- Support minimal required fields
- Extensible for future additions
- JSON serialization

### 4. CLI Integration
**File:** `src/cli/bundle.zig`

**Commands:**
- `proxmox-lxcri bundle create <path>` - Create new bundle
- `proxmox-lxcri bundle validate <path>` - Validate existing bundle
- Options:
  - `--rootfs <path>` - Source rootfs
  - `--config <file>` - Custom config template

### 5. Tests
**Files:** `tests/bundle_*.zig`

**Coverage:**
- Bundle creation
- Config.json generation and validation
- Rootfs setup
- Error handling

### 6. Documentation
**File:** `docs/OCI_BUNDLE_GENERATOR.md`

**Content:**
- Usage examples
- Bundle structure
- Config.json format
- Integration guide

## Technical Details

### OCI Bundle Structure
```
bundle/
├── config.json
└── rootfs/
    ├── bin/
    ├── etc/
    ├── lib/
    ├── proc/
    ├── sys/
    └── ...
```

### Minimal config.json Fields
```json
{
  "ociVersion": "1.0.2",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh"],
    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
    "cwd": "/"
  },
  "root": {
    "path": "rootfs",
    "readonly": false
  },
  "hostname": "container",
  "linux": {
    "namespaces": [
      {"type": "pid"},
      {"type": "network"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"}
    ]
  }
}
```

## Dependencies
- OCI runtime spec 1.0.2+
- JSON library (std.json)
- Filesystem operations (std.fs)

## Timeline
- Implementation: 2-3 hours
- Testing: 1 hour
- Documentation: 30 minutes
- **Total estimated:** ~4 hours

## Success Metrics
- Bundle generator creates valid OCI bundles
- Local smoke tests pass
- Code coverage > 80%
- Documentation complete

## Next Steps After Completion
1. Integration with container runtime
2. Advanced config.json features (mounts, capabilities, etc.)
3. Template system for common configurations
4. Bundle import/export functionality
