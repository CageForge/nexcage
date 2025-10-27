# Issue #90 Analysis: LXC: pct create required args & error mapping

**Date**: 2025-10-21  
**Status**: 🔍 ANALYZED  
**Priority**: HIGH  

## 🎯 **Issue Status: PARTIALLY IMPLEMENTED**

Issue #90 is **partially implemented** in v0.6.0. Basic functionality works, but advanced validation and error mapping are missing.

## ✅ **What's Already Implemented**

### **1. Basic Required Args**
```zig
const args = [_][]const u8{
    "pct",
    "create",
    vmid,           // ✅ Required: VMID (auto-generated)
    template,       // ✅ Required: ostemplate (validated)
    "--hostname", config.name,
    "--memory", "512",
    "--cores", "1",
    "--net0", "name=eth0,bridge=vmbr0,ip=dhcp",
    "--ostype", "ubuntu",
    "--unprivileged", "0",
};
```

### **2. VMID Generation**
```zig
// Generate VMID from name (Proxmox requires numeric vmid)
var hasher = std.hash.Wyhash.init(0);
hasher.update(config.name);
const vmid_num: u32 = @truncate(hasher.final());
const vmid_calc: u32 = (vmid_num % 900000) + 100; // 100..900099
const vmid = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid_calc});
```

### **3. Basic Error Mapping**
```zig
fn mapPctError(self: *Self, exit_code: u8, stderr: []const u8) core.Error {
    const s = stderr;
    if (std.mem.indexOf(u8, s, "No such file or directory") != null) {
        return core.Error.NotFound;
    }
    if (std.mem.indexOf(u8, s, "Permission denied") != null) {
        return core.Error.PermissionDenied;
    }
    // ... more mappings
    return core.Error.OperationFailed;
}
```

## ❌ **What's Missing (Required for Completion)**

### **1. Argument Validation**
- ❌ **VMID uniqueness check** - No validation if VMID already exists
- ❌ **Template existence validation** - No check if template exists
- ❌ **Hostname format validation** - No validation of hostname format
- ❌ **Memory/cores validation** - No validation of numeric values
- ❌ **Network configuration validation** - No validation of network settings

### **2. Enhanced Error Mapping**
- ❌ **pct-specific errors** - "not enough arguments", "unable to parse option"
- ❌ **Validation errors** - "invalid vmid", "template not found"
- ❌ **Conflict errors** - "vmid already exists", "hostname already in use"
- ❌ **Configuration errors** - "invalid memory value", "invalid network config"

### **3. Dynamic Arguments**
- ❌ **Configurable values** - Memory, cores, network from config
- ❌ **Conditional arguments** - Different args for different container types
- ❌ **Configuration validation** - Check argument compatibility

## 🎯 **Required Implementation**

### **1. Add Argument Validation**
```zig
fn validateCreateArgs(self: *Self, vmid: []const u8, template: []const u8, config: *const core.types.ProxmoxLxcBackendConfig) !void {
    // Validate VMID uniqueness
    try self.validateVmidUnique(vmid);
    
    // Validate template existence
    try self.validateTemplateExists(template);
    
    // Validate hostname format
    try self.validateHostname(config.name);
    
    // Validate memory/cores values
    try self.validateResourceValues(config);
}
```

### **2. Enhanced Error Mapping**
```zig
fn mapPctError(self: *Self, exit_code: u8, stderr: []const u8) core.Error {
    const s = stderr;
    
    // pct-specific errors
    if (std.mem.indexOf(u8, s, "not enough arguments") != null) {
        return core.Error.InvalidArgument;
    }
    if (std.mem.indexOf(u8, s, "unable to parse option") != null) {
        return core.Error.InvalidArgument;
    }
    
    // Validation errors
    if (std.mem.indexOf(u8, s, "invalid vmid") != null) {
        return core.Error.InvalidArgument;
    }
    if (std.mem.indexOf(u8, s, "template not found") != null) {
        return core.Error.NotFound;
    }
    
    // Conflict errors
    if (std.mem.indexOf(u8, s, "vmid already exists") != null) {
        return core.Error.AlreadyExists;
    }
    if (std.mem.indexOf(u8, s, "hostname already in use") != null) {
        return core.Error.AlreadyExists;
    }
    
    // ... existing mappings
}
```

### **3. Dynamic Argument Building**
```zig
fn buildCreateArgs(self: *Self, vmid: []const u8, template: []const u8, config: *const core.types.ProxmoxLxcBackendConfig) ![][]const u8 {
    var args = std.ArrayList([]const u8).init(self.allocator);
    defer args.deinit();
    
    try args.append("pct");
    try args.append("create");
    try args.append(vmid);
    try args.append(template);
    
    // Required args
    try args.append("--hostname");
    try args.append(config.name);
    
    // Configurable args
    try args.append("--memory");
    try args.append(try std.fmt.allocPrint(self.allocator, "{d}", .{config.memory}));
    
    try args.append("--cores");
    try args.append(try std.fmt.allocPrint(self.allocator, "{d}", .{config.cores}));
    
    // Network configuration
    try args.append("--net0");
    try args.append(try self.buildNetworkConfig(config));
    
    // Optional args based on config
    if (config.ostype) |ostype| {
        try args.append("--ostype");
        try args.append(ostype);
    }
    
    if (config.unprivileged) |unpriv| {
        try args.append("--unprivileged");
        try args.append(if (unpriv) "1" else "0");
    }
    
    return args.toOwnedSlice();
}
```

## 📋 **Implementation Plan**

### **Phase 1: Argument Validation (2-3 days)**
1. **Add VMID uniqueness check**
2. **Add template existence validation**
3. **Add hostname format validation**
4. **Add resource value validation**

### **Phase 2: Enhanced Error Mapping (1-2 days)**
1. **Add pct-specific error mappings**
2. **Add validation error mappings**
3. **Add conflict error mappings**
4. **Test error scenarios**

### **Phase 3: Dynamic Arguments (2-3 days)**
1. **Implement configurable argument building**
2. **Add conditional argument logic**
3. **Add configuration validation**
4. **Test with various configurations**

## 🧪 **Testing Strategy**

### **Validation Testing**
```bash
# Test VMID uniqueness
./nexcage create --name test1 --image template1
./nexcage create --name test1 --image template2  # Should fail

# Test template validation
./nexcage create --name test --image nonexistent-template  # Should fail

# Test hostname validation
./nexcage create --name "invalid@hostname" --image template  # Should fail
```

### **Error Mapping Testing**
```bash
# Test various error scenarios
./nexcage create --name test --image template  # Valid
./nexcage create --name test --image template  # Should fail with AlreadyExists
./nexcage create --name test --image invalid   # Should fail with NotFound
```

## 🎯 **Success Criteria**

### **Must Have**
- ✅ All required args validated
- ✅ pct-specific errors properly mapped
- ✅ Clear error messages for validation failures
- ✅ Dynamic argument building from config

### **Should Have**
- ✅ Configurable resource values
- ✅ Conditional argument logic
- ✅ Comprehensive error coverage
- ✅ Performance optimization

## 📊 **Current Status**

- **Basic Implementation**: ✅ 60% complete
- **Argument Validation**: ❌ 0% complete
- **Enhanced Error Mapping**: ❌ 20% complete
- **Dynamic Arguments**: ❌ 0% complete

**Overall Progress**: 🟡 **40% Complete**

## 🚀 **Next Steps**

1. **Implement argument validation** - Start with VMID uniqueness
2. **Enhance error mapping** - Add pct-specific errors
3. **Add dynamic arguments** - Configurable values
4. **Test thoroughly** - All error scenarios
5. **Update documentation** - Error handling guide

---

**Issue #90 requires additional implementation to be fully complete.**
