# Issue #56: Fix CreateContainer Implementation

## 🎯 Issue Overview
- **Назва**: Fix CreateContainer Implementation
- **Тип**: Bug Fix & Feature Implementation
- **Статус**: 🚀 **PLANNING** - Ready to Start
- **Пріоритет**: Critical
- **Effort**: 16 hours
- **Dependencies**: Sprint 3 completion

## 🚀 Objectives

### Primary Goals
- Fix CreateContainer command according to technical requirements
- Implement proper CRI integration
- Add runtime selection logic (crun vs Proxmox LXC)
- Fix OCI bundle generation

### Success Criteria
- [ ] CreateContainer command working correctly
- [ ] CRI integration properly implemented
- [ ] Runtime selection logic working
- [ ] OCI bundle generation correct

## 🔧 Technical Requirements

### CRI Integration
- **CreateContainerRequest**: Handle CRI request properly
- **PodSandbox Validation**: Validate existing sandbox
- **ContainerConfig**: Parse and validate container configuration
- **SandboxConfig**: Parse and validate sandbox configuration

### Runtime Selection
- **Algorithm Logic**: Implement runtime selection algorithm
- **crun Support**: Standard container runtime support
- **Proxmox LXC**: Special case LXC container support
- **Image Pattern Matching**: Match image names to runtime type

### OCI Bundle Generation
- **Directory Structure**: Proper bundle directory layout
- **rootfs Preparation**: Container filesystem setup
- **config.json**: OCI Runtime Spec generation
- **Mount Configuration**: Volume and secret mounts

## 🏗️ Implementation Plan

### Phase 1: Current Implementation Analysis (4 hours)

#### 1.1 Code Review
- **File**: `src/oci/create.zig`
- **Current Issues**: Identify problems in existing implementation
- **Missing Features**: Identify missing CRI integration
- **Architecture Review**: Review current architecture

#### 1.2 Technical Requirements Analysis
- **CRI Specification**: Review CRI protocol requirements
- **OCI Specification**: Review OCI Runtime Spec requirements
- **Runtime Selection**: Understand runtime selection requirements
- **Integration Points**: Identify integration points

#### 1.3 Gap Analysis
- **Missing Components**: Identify missing components
- **Incorrect Implementation**: Identify incorrect implementations
- **Integration Issues**: Identify integration problems
- **Testing Gaps**: Identify testing gaps

### Phase 2: CRI Integration Implementation (6 hours)

#### 2.1 CRI Request Handling
```zig
// CRI CreateContainerRequest structure
pub const CreateContainerRequest = struct {
    pod_sandbox_id: []const u8,
    config: ContainerConfig,
    sandbox_config: SandboxConfig,
    
    pub fn validate(self: *const Self) !void {
        // Validate request parameters
    }
};

// CRI response structure
pub const CreateContainerResponse = struct {
    container_id: []const u8,
    
    pub fn init(container_id: []const u8) CreateContainerResponse {
        return .{ .container_id = container_id };
    }
};
```

#### 2.2 PodSandbox Validation
```zig
// PodSandbox validation
pub fn validatePodSandbox(pod_sandbox_id: []const u8) !PodSandbox {
    // Check if PodSandbox exists
    // Validate PodSandbox state
    // Return PodSandbox information
}

// PodSandbox structure
pub const PodSandbox = struct {
    id: []const u8,
    state: PodSandboxState,
    network: NetworkConfig,
    namespaces: []Namespace,
    
    pub fn isReady(self: *const Self) bool {
        return self.state == .Ready;
    }
};
```

#### 2.3 Configuration Validation
```zig
// Container configuration validation
pub fn validateContainerConfig(config: ContainerConfig) !void {
    // Validate image specification
    // Validate command and arguments
    // Validate environment variables
    // Validate resource limits
    // Validate security context
}

// Sandbox configuration validation
pub fn validateSandboxConfig(config: SandboxConfig) !void {
    // Validate network configuration
    // Validate namespace configuration
    // Validate hostname
    // Validate security context
}
```

### Phase 3: Runtime Selection Logic (6 hours)

#### 3.1 Runtime Selection Algorithm
```zig
// Runtime selection algorithm
pub fn selectRuntime(image_name: []const u8) RuntimeType {
    // Check image name patterns
    if (std.mem.startsWith(u8, image_name, "lxc/")) {
        return .proxmox_lxc;
    }
    
    if (std.mem.startsWith(u8, image_name, "db-")) {
        return .proxmox_lxc;
    }
    
    if (std.mem.startsWith(u8, image_name, "vm-")) {
        return .proxmox_lxc;
    }
    
    // Default to crun
    return .crun;
}

// Runtime type enumeration
pub const RuntimeType = enum {
    crun,
    proxmox_lxc,
    
    pub fn getCommand(self: RuntimeType) []const u8 {
        return switch (self) {
            .crun => "crun",
            .proxmox_lxc => "pct",
        };
    }
};
```

#### 3.2 Runtime-Specific Implementation
```zig
// Runtime interface
pub const Runtime = struct {
    runtime_type: RuntimeType,
    
    pub fn createContainer(self: *Self, config: ContainerConfig) !void {
        switch (self.runtime_type) {
            .crun => try self.createCrunContainer(config),
            .proxmox_lxc => try self.createLxcContainer(config),
        }
    }
    
    fn createCrunContainer(self: *Self, config: ContainerConfig) !void {
        // Create container using crun
        // Generate OCI bundle
        // Execute crun create command
    }
    
    fn createLxcContainer(self: *Self, config: ContainerConfig) !void {
        // Create container using Proxmox LXC API
        // Generate LXC configuration
        // Call Proxmox API
    }
};
```

## 📊 Current Implementation Analysis

### 🔍 **Issues Found in Current Code**

#### 1. **Missing CRI Integration**
- **Problem**: No CRI CreateContainerRequest handling
- **Impact**: Cannot receive CRI requests from kubelet
- **Solution**: Implement CRI request/response structures

#### 2. **Incorrect Runtime Selection**
- **Problem**: No runtime selection logic
- **Impact**: Always uses same runtime regardless of image
- **Solution**: Implement runtime selection algorithm

#### 3. **Incomplete OCI Bundle**
- **Problem**: OCI bundle structure not following specification
- **Impact**: Invalid container configuration
- **Solution**: Fix OCI bundle generation

#### 4. **Missing Validation**
- **Problem**: No PodSandbox validation
- **Impact**: Cannot ensure PodSandbox exists
- **Solution**: Add PodSandbox validation

### 🔧 **Files to Modify**

#### Primary Files
- `src/oci/create.zig` - Main CreateContainer implementation
- `src/oci/mod.zig` - OCI module exports
- `src/common/types.zig` - CRI data structures

#### New Files to Create
- `src/cri/` - CRI protocol implementation
- `src/runtime/` - Runtime selection and management
- `src/oci/bundle.zig` - OCI bundle generation

## 🧪 Testing Strategy

### Unit Testing
- **CRI Request Handling**: Test CRI request parsing and validation
- **Runtime Selection**: Test runtime selection algorithm
- **Configuration Validation**: Test configuration validation logic
- **OCI Bundle Generation**: Test OCI bundle creation

### Integration Testing
- **End-to-End Workflow**: Test complete CreateContainer workflow
- **Runtime Integration**: Test crun and LXC integration
- **CRI Integration**: Test CRI protocol integration
- **Error Handling**: Test error scenarios and recovery

### Performance Testing
- **Container Creation Time**: Measure container creation performance
- **Resource Usage**: Monitor resource usage during creation
- **Concurrent Creation**: Test multiple concurrent container creations
- **Memory Usage**: Monitor memory usage and leaks

## 📈 Success Metrics

### Functional Metrics
- **CreateContainer Success**: 100% successful container creation
- **CRI Integration**: Proper CRI request handling
- **Runtime Selection**: Correct runtime selection logic
- **OCI Bundle**: Valid OCI bundle generation

### Performance Metrics
- **Container Creation Time**: < 5 seconds for standard containers
- **LXC Creation Time**: < 10 seconds for LXC containers
- **Bundle Generation**: < 2 seconds for OCI bundle
- **Response Time**: < 100ms for CRI operations

### Quality Metrics
- **Test Coverage**: > 90% for CreateContainer components
- **Error Handling**: Comprehensive error handling
- **Validation**: Proper input validation
- **Integration**: End-to-end workflow working

## 🚨 Risk Assessment

### High Risk
- **CRI Integration Complexity**: CRI protocol implementation challenges
- **Runtime Selection Logic**: Complex runtime selection algorithm
- **OCI Bundle Generation**: OCI specification compliance

### Medium Risk
- **Proxmox LXC Integration**: LXC API integration complexity
- **Error Handling**: Comprehensive error handling implementation
- **Testing Coverage**: End-to-end testing complexity

### Low Risk
- **Basic Container Creation**: Core container creation already implemented
- **Testing Framework**: Existing testing infrastructure available
- **Code Quality**: High code quality from previous sprints

## 🔧 Mitigation Strategies

### High Risk Mitigation
- **CRI Integration**: Start with basic CRI request handling
- **Runtime Selection**: Implement simple runtime selection first
- **OCI Bundle**: Use existing OCI bundle structure as base

### Medium Risk Mitigation
- **LXC Integration**: Start with basic LXC API calls
- **Error Handling**: Implement basic error handling first
- **Testing**: Focus on core functionality testing first

## 📅 Timeline

### Day 1 (August 25): Analysis & Planning (4 hours)
- **Morning**: Current implementation review
- **Afternoon**: Technical requirements analysis
- **Evening**: Gap analysis and planning

### Day 2 (August 26): CRI Integration (6 hours)
- **Morning**: CRI request handling implementation
- **Afternoon**: PodSandbox validation
- **Evening**: Configuration validation

### Day 3 (August 27): Runtime Selection (6 hours)
- **Morning**: Runtime selection algorithm
- **Afternoon**: Runtime-specific implementation
- **Evening**: Integration testing

## 🎯 Deliverables

### Code Deliverables
- [ ] `src/cri/create_container.zig` - CRI CreateContainer implementation
- [ ] `src/runtime/selector.zig` - Runtime selection logic
- [ ] `src/oci/bundle.zig` - OCI bundle generation
- [ ] `src/oci/create.zig` - Updated CreateContainer implementation

### Documentation Deliverables
- [ ] `docs/cri_integration.md` - CRI integration guide
- [ ] `docs/runtime_selection.md` - Runtime selection guide
- [ ] `docs/oci_bundle.md` - OCI bundle generation guide

### Testing Deliverables
- [ ] `tests/cri/create_container_test.zig` - CRI integration tests
- [ ] `tests/runtime/selector_test.zig` - Runtime selection tests
- [ ] `tests/oci/bundle_test.zig` - OCI bundle tests

## 🔄 Next Steps

### Immediate Actions
1. **Code Review**: Review current CreateContainer implementation
2. **Requirements Analysis**: Analyze technical requirements
3. **Architecture Design**: Design new architecture
4. **Implementation Plan**: Create detailed implementation plan

### Preparation Tasks
1. **CRI Tools**: Set up CRI testing tools
2. **OCI Tools**: Prepare OCI bundle validation tools
3. **Testing Environment**: Set up testing environment
4. **Documentation**: Review CRI and OCI specifications

---

**Issue #56 Status**: 🚀 **PLANNING** - Ready to Start

**Next Action**: Current implementation review and technical requirements analysis
**Start Date**: August 25, 2025
**Target Completion**: August 27, 2025
