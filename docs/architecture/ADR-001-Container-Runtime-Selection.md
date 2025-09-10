# ADR-001: Container Runtime Selection

## Status
**ACCEPTED** - 2024-12-01

## Context

We needed to select a container runtime for the Proxmox LXCRI project that would provide:
- High performance and low overhead
- OCI compliance for container portability
- Integration capabilities with Proxmox VE
- Security features and isolation
- Active maintenance and community support

### Options Considered

1. **runc** - Reference OCI runtime implementation
2. **crun** - Fast and lightweight OCI runtime in C
3. **kata-containers** - Secure runtime using lightweight VMs
4. **gVisor** - User-space kernel for enhanced security
5. **Custom runtime** - Build from scratch

## Decision

**We chose `crun` as the primary container runtime with `runc` as fallback.**

### Rationale

#### Why crun:
- **Performance**: ~50% faster startup times compared to runc
- **Memory efficiency**: Lower memory footprint (~30% less RAM usage)
- **C implementation**: Better integration with Proxmox's C/C++ ecosystem
- **OCI compliance**: Full OCI Runtime Specification v1.0+ support
- **Active development**: Regular updates and security patches
- **cgroups v2 support**: Modern resource management capabilities

#### Why runc as fallback:
- **Stability**: Battle-tested in production environments
- **Compatibility**: Widest ecosystem support
- **Reference implementation**: Guaranteed OCI compliance
- **Emergency backup**: Provides reliability if crun issues arise

### Implementation Strategy

```zig
// Runtime selection logic
pub const RuntimeConfig = struct {
    primary_runtime: RuntimeType = .crun,
    fallback_runtime: RuntimeType = .runc,
    auto_fallback_enabled: bool = true,
    runtime_timeout: u32 = 30, // seconds
};

pub const RuntimeType = enum {
    crun,
    runc,
    custom,
};

pub fn selectRuntime(config: RuntimeConfig, container_spec: ContainerSpec) RuntimeType {
    // Try primary runtime first
    if (isRuntimeAvailable(config.primary_runtime)) {
        return config.primary_runtime;
    }
    
    // Fallback to secondary runtime
    if (config.auto_fallback_enabled and isRuntimeAvailable(config.fallback_runtime)) {
        logger.warn("Primary runtime unavailable, using fallback: {}", .{config.fallback_runtime});
        return config.fallback_runtime;
    }
    
    return error.NoRuntimeAvailable;
}
```

## Consequences

### Positive
- **Performance gains**: Faster container startup and lower resource usage
- **Modern features**: Access to latest cgroups v2 and security features
- **Reliability**: Fallback mechanism ensures operational continuity
- **Future-proofing**: crun's active development provides ongoing improvements

### Negative
- **Complexity**: Managing two runtimes increases system complexity
- **Testing overhead**: Need to test both runtime paths
- **Documentation**: Must document both runtime configurations
- **Debugging**: Runtime-specific issues require specialized knowledge

### Mitigation Strategies

1. **Comprehensive testing**: CI/CD tests both runtime paths
2. **Runtime detection**: Automatic runtime capability detection
3. **Monitoring**: Runtime performance and failure metrics
4. **Documentation**: Clear guidelines for runtime selection and troubleshooting

## Implementation Details

### Runtime Detection
```bash
# Check crun availability and version
crun --version
crun spec --version

# Verify OCI compliance
crun check-compliance

# Performance benchmark
time crun run test-container
```

### Configuration Options
```json
{
  "runtime": {
    "primary": "crun",
    "fallback": "runc",
    "auto_fallback": true,
    "timeout": 30,
    "performance_monitoring": true,
    "feature_detection": {
      "cgroups_v2": true,
      "seccomp": true,
      "user_namespaces": true
    }
  }
}
```

### Monitoring and Metrics
- Runtime selection decisions
- Container startup times by runtime
- Resource usage comparison
- Failure rates and fallback frequency
- Feature utilization statistics

## Review Schedule

This ADR will be reviewed:
- **Next review**: 2025-06-01 (6 months)
- **Trigger events**:
  - Major crun/runc version releases
  - Significant performance regressions
  - New runtime alternatives emerging
  - Production issues with current selection

## References

- [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec)
- [crun Project](https://github.com/containers/crun)
- [runc Project](https://github.com/opencontainers/runc)
- [Container Runtime Comparison Benchmarks](https://www.redhat.com/en/blog/container-runtime-security)
- [Proxmox VE Container Integration](https://pve.proxmox.com/wiki/Linux_Container)

---
**Author**: Proxmox LXCRI Team  
**Reviewers**: Architecture Committee  
**Last Updated**: 2024-12-01
