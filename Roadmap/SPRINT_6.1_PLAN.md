# Sprint 6.1: Stabilization Release

**Date**: 2025-10-27  
**Status**: 🚀 READY TO START  
**Version**: v0.6.1  
**Duration**: 3-5 days  
**Priority**: CRITICAL STABILIZATION

## 🎯 **Sprint 6.1 Goals**

Release a stable v0.6.1 with critical fixes and improvements from v0.6.0.

## ✅ **Completed in v0.6.0**

- ✅ Memory leaks fixed in config.zig (default_runtime, log_file, routing_rules)
- ✅ OCI bundle mounts fixed (ConfigFileNotFound error resolved)
- ✅ System integrity checks implemented (`nexcage health` command)
- ✅ Code cleanup (unused files removed, test files organized)
- ✅ Comprehensive documentation and roadmap updates

## 🚀 **Sprint 6.1 Tasks**

### **1. Improve pct Error Handling (HIGH PRIORITY)**
**Effort**: 2-3 days  
**Impact**: User experience and debugging

**Current Issues**:
- Basic error mapping from pct commands
- Unclear error messages for common failures
- Missing validation for pct create required arguments
- VMID uniqueness not checked before creation

**Tasks**:
- [ ] Analyze current pct error handling in `src/backends/proxmox-lxc/driver.zig`
- [ ] Implement comprehensive error mapping for all pct commands
- [ ] Add VMID validation (check uniqueness before create)
- [ ] Add template existence validation
- [ ] Improve error messages with actionable feedback
- [ ] Add tests for error scenarios

**Success Criteria**:
- Clear error messages for all pct command failures
- VMID validation prevents duplicate containers
- Template validation prevents invalid template usage
- Robust error mapping for all scenarios

### **2. OCI Bundle Generator Implementation (MEDIUM PRIORITY)**
**Effort**: 3-4 days  
**Impact**: OCI support completeness

**Current Issues**:
- No OCI bundle generator for creating bundles from rootfs
- Limited OCI bundle format support

**Tasks**:
- [ ] Design OCI bundle generator API
- [ ] Implement rootfs extraction and packaging
- [ ] Implement config.json generation with proper structure
- [ ] Add support for annotations and metadata
- [ ] Add validation for generated bundles
- [ ] Add tests for bundle generation

**Success Criteria**:
- OCI bundle generator functional
- Generated bundles pass validation
- Support for standard OCI formats
- Proper config.json structure

## 📋 **Detailed Task Breakdown**

### **Task 1: Improve pct Error Handling**

#### **Step 1: Analyze Current Error Handling**
```bash
# Review driver.zig error handling
grep -n "pct" src/backends/proxmox-lxc/driver.zig
# Analyze error mapping patterns
```

**Actions**:
1. Review `executePctCommand` function in `driver.zig`
2. Identify current error mapping logic
3. Document all pct command error codes
4. Analyze common error scenarios

#### **Step 2: Implement Error Mapping**
```zig
// Proposed error mapping structure
pub const PctError = enum {
    AlreadyExists,
    NotFound,
    InvalidArgument,
    PermissionDenied,
    ResourceExhausted,
    Unsupported,
    Unknown,
};

pub fn mapPctError(stderr: []const u8, exit_code: i32) PctError {
    // Comprehensive error mapping logic
}
```

**Actions**:
1. Create comprehensive error mapping function
2. Parse pct stderr for specific error patterns
3. Map exit codes to specific error types
4. Add detailed error context

#### **Step 3: Add Validation**
```zig
// Validate VMID before create
pub fn validateVmid(self: *Self, vmid: u32) !void {
    if (self.vmidExists(vmid)) {
        return Error.AlreadyExists;
    }
}

// Validate template exists
pub fn validateTemplate(self: *Self, template: []const u8) !void {
    // Check template exists in Proxmox storage
}
```

**Actions**:
1. Add VMID existence check before create
2. Add template existence validation
3. Add storage validation
4. Add network validation (if applicable)

#### **Step 4: Improve Error Messages**
```zig
// Enhanced error message with context
pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
    // Check if container exists
    if (try self.containerExists(config.name)) {
        const err_msg = try std.fmt.allocPrint(
            self.allocator,
            "Container '{s}' (VMID: {d}) already exists. Use --force to replace.",
            .{ config.name, vmid }
        );
        // ...
    }
}
```

**Actions**:
1. Add contextual error messages
2. Include VMID, name, and other relevant context
3. Provide actionable suggestions
4. Add error logging

### **Task 2: OCI Bundle Generator**

#### **Step 1: Design API**
```zig
// Proposed OCI bundle generator API
pub const OciBundleGenerator = struct {
    allocator: std.mem.Allocator,
    
    pub fn generate(
        self: *Self,
        source_path: []const u8,
        output_path: []const u8,
        annotations: ?std.StringHashMap([]const u8),
    ) !void {
        // Generate OCI bundle
    }
};
```

**Tasks**:
1. Design OCI bundle generator interface
2. Define input/output formats
3. Plan config.json structure
4. Plan rootfs handling

#### **Step 2: Implement Generator**
```zig
// Bundle generation implementation
pub fn generate(self: *Self, ...) !void {
    // 1. Create bundle directory structure
    try std.fs.cwd().makePath(output_path);
    try std.fs.cwd().makePath(output_path ++ "/rootfs");
    
    // 2. Extract/copy rootfs
    try self.copyRootfs(source_path, output_path ++ "/rootfs");
    
    // 3. Generate config.json
    try self.generateConfigJson(output_path, annotations);
    
    // 4. Add annotations
    if (annotations) |ann| {
        try self.writeAnnotations(output_path, ann);
    }
}
```

**Tasks**:
1. Implement rootfs handling
2. Implement config.json generation
3. Implement annotations support
4. Add validation

#### **Step 3: Add Validation**
```zig
// Validate generated bundle
pub fn validateBundle(self: *Self, bundle_path: []const u8) !void {
    // 1. Check bundle structure
    try self.checkBundleStructure(bundle_path);
    
    // 2. Validate config.json
    try self.validateConfigJson(bundle_path);
    
    // 3. Check rootfs
    try self.checkRootfs(bundle_path);
}
```

**Tasks**:
1. Validate bundle structure
2. Validate config.json format
3. Check rootfs integrity
4. Add comprehensive error reporting

## 🧪 **Testing Strategy**

### **Error Handling Tests**
```bash
# Test various error scenarios
./nexcage create --name test1 --image template  # Success
./nexcage create --name test1 --image template  # Should fail with AlreadyExists
./nexcage create --name test2 --image invalid   # Should fail with NotFound
./nexcage create --name test3                   # Should fail with InvalidArgument
```

### **OCI Bundle Generator Tests**
```bash
# Test bundle generation
./nexcage bundle create --source /path/to/rootfs --output /path/to/bundle
# Validate generated bundle
./nexcage bundle validate --path /path/to/bundle
# Test with sample bundle
./nexcage create --name test-bundle --image /path/to/bundle
```

## 📊 **Success Metrics**

### **Error Handling**
- **Target**: 100% error coverage for pct commands
- **Measurement**: Comprehensive test suite
- **Coverage**: All error scenarios documented and tested

### **OCI Bundle Generator**
- **Target**: Successfully generate valid OCI bundles
- **Measurement**: Bundle validation tests
- **Coverage**: All OCI bundle formats supported

## 🎯 **Definition of Done**

### **Error Handling**
- [ ] Comprehensive error mapping implemented
- [ ] VMID validation working
- [ ] Template validation working
- [ ] Clear error messages for all scenarios
- [ ] Tests pass for all error scenarios
- [ ] Documentation updated

### **OCI Bundle Generator**
- [ ] OCI bundle generator implemented
- [ ] Generated bundles pass validation
- [ ] Support for standard OCI formats
- [ ] Tests pass for bundle generation
- [ ] Documentation updated

## 🚀 **Release Process**

1. **Complete Sprint 6.1 Tasks**
   - Improve pct error handling
   - Implement OCI bundle generator (if time permits)

2. **Testing**
   - Run comprehensive test suite
   - Run memory leak detection
   - Run integration tests

3. **Documentation**
   - Update CHANGELOG.md
   - Update README.md
   - Update CLI documentation

4. **Release**
   - Create v0.6.1 tag
   - Create GitHub release
   - Push to main branch

5. **Post-Release**
   - Update roadmap progress
   - Plan Sprint 6.2

## 📝 **Sprint 6.1 Deliverables**

- ✅ Enhanced pct error handling with clear messages
- ✅ VMID and template validation
- ✅ OCI bundle generator (if completed)
- ✅ Comprehensive test suite
- ✅ Updated documentation
- ✅ v0.6.1 release

## ⏱️ **Time Estimation**

- **Error Handling**: 2-3 days
- **OCI Bundle Generator**: 3-4 days (optional if time permits)
- **Testing & Documentation**: 1 day
- **Release Process**: 0.5 day

**Total**: 3-5 days for Sprint 6.1

## 🎯 **Next Steps After Sprint 6.1**

1. **Sprint 6.2 Planning**: Focus on additional stabilizations
2. **Sprint 7.0 Planning**: Full refactor to modular architecture
3. **Community Feedback**: Gather user feedback on v0.6.1
4. **Issue Tracking**: Monitor GitHub issues and prioritize

---

**Sprint 6.1 ready to begin. Focus on critical error handling improvements for stable v0.6.1 release.**

