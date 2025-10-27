# Sprint 7.1: Immediate Actions for v0.7.0

**Date**: 2025-10-23  
**Status**: 🚀 READY TO START  
**Duration**: 1 week  
**Priority**: CRITICAL  

## 🎯 **Sprint 7.1 Goals**

Address the most critical issues blocking production readiness for v0.7.0.

## 🚨 **Critical Issues (P0 - Blocking)**

### **1. Memory Leaks Fix (CRITICAL)**
**Issue**: Memory leaks in config.zig causing production instability
**Impact**: High - Production crashes possible
**Effort**: 2-3 days

**Tasks**:
- [ ] **Analyze remaining memory leaks** in config.zig
- [ ] **Fix double-free errors** in deinit functions
- [ ] **Implement proper cleanup** for all dynamic allocations
- [ ] **Add memory leak detection** in CI/CD pipeline
- [ ] **Test memory stability** over extended periods

**Success Criteria**:
- Zero memory leaks in production
- Memory usage stable over 24+ hours
- No segfaults or crashes

### **2. OCI Bundle Mounts Fix (CRITICAL)**
**Issue**: ConfigFileNotFound error when applying mounts
**Impact**: High - Core functionality broken
**Effort**: 2-3 days

**Tasks**:
- [ ] **Debug OCI bundle parsing** in applyMountsToLxcConfig
- [ ] **Fix config.json path resolution** for OCI bundles
- [ ] **Implement proper mount handling** for LXC config
- [ ] **Add validation** for OCI bundle structure
- [ ] **Test with various OCI bundle formats**

**Success Criteria**:
- OCI bundle mounts work end-to-end
- No ConfigFileNotFound errors
- Mounts properly applied to LXC config

### **3. Proxmox LXC Error Handling Enhancement (HIGH)**
**Issue**: pct create required args & error mapping (Issue #90)
**Impact**: Medium - User experience and debugging
**Effort**: 1-2 days

**Tasks**:
- [ ] **Fix pct create required arguments** handling
- [ ] **Improve error mapping** for pct commands
- [ ] **Enhance error messages** for better debugging
- [ ] **Add validation** for pct command arguments
- [ ] **Test error scenarios** thoroughly

**Success Criteria**:
- All pct command arguments properly handled
- Clear error messages for pct command issues
- Robust error mapping and validation

## 🔧 **Immediate Actions (This Week)**

### **Day 1-2: Memory Leaks**
```bash
# Priority 1: Fix memory leaks
- Analyze config.zig memory allocation patterns
- Fix double-free errors in deinit functions
- Add proper cleanup for all dynamic allocations
- Test memory stability
```

### **Day 3-4: OCI Bundle Fixes**
```bash
# Priority 2: Fix OCI bundle mounts
- Debug applyMountsToLxcConfig function
- Fix config.json path resolution
- Implement proper mount handling
- Test with sample OCI bundles
```

### **Day 5: Proxmox LXC Error Handling**
```bash
# Priority 3: Enhance pct error handling
- Fix pct create required arguments
- Improve error mapping
- Test error scenarios
- Update error messages
```

## 📋 **Detailed Task Breakdown**

### **Memory Leaks Fix**
1. **Analyze current leaks**:
   - Run valgrind or similar tool
   - Identify specific allocation patterns
   - Document leak sources

2. **Fix deinit functions**:
   - Review all deinit functions
   - Ensure proper cleanup order
   - Add conditional checks for dynamic vs static allocations

3. **Add memory testing**:
   - Create memory leak detection in CI
   - Add long-running memory tests
   - Monitor memory usage patterns

### **OCI Bundle Mounts Fix**
1. **Debug current implementation**:
   - Trace applyMountsToLxcConfig execution
   - Identify where ConfigFileNotFound occurs
   - Check OCI bundle structure parsing

2. **Fix path resolution**:
   - Ensure proper config.json path handling
   - Add validation for bundle structure
   - Handle edge cases (missing files, etc.)

3. **Test with real bundles**:
   - Create test OCI bundles
   - Test various bundle formats
   - Verify mount application

### **Template Support Enhancement**
1. **Improve path resolution**:
   - Handle various template path formats
   - Add support for remote templates
   - Improve error messages

2. **Add validation**:
   - Validate template existence
   - Check template compatibility
   - Provide helpful error messages

## 🧪 **Testing Strategy**

### **Memory Testing**
```bash
# Long-running memory test
./nexcage list
# Run for 24+ hours, monitor memory usage
# Should not grow over time
```

### **OCI Bundle Testing**
```bash
# Test with sample OCI bundle
./nexcage create --name test-oci --image /path/to/oci-bundle
# Should not get ConfigFileNotFound error
# Mounts should be applied correctly
```

### **Template Testing**
```bash
# Test with various templates
./nexcage create --name test-template --image local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst
# Should work without errors
# Should provide clear error messages for invalid templates
```

## 📊 **Success Metrics**

### **Memory Leaks**
- **Target**: 0 memory leaks
- **Measurement**: Valgrind/AddressSanitizer
- **Duration**: 24+ hour stability test

### **OCI Bundle Support**
- **Target**: 100% success rate for valid bundles
- **Measurement**: Automated testing
- **Coverage**: All standard OCI bundle formats

### **Template Support**
- **Target**: All Proxmox template formats supported
- **Measurement**: Manual testing
- **Coverage**: Common template types

## 🎯 **Definition of Done**

### **Memory Leaks**
- [ ] Zero memory leaks detected by tools
- [ ] 24+ hour stability test passes
- [ ] Memory usage stable over time
- [ ] CI/CD pipeline includes memory testing

### **OCI Bundle Support**
- [ ] ConfigFileNotFound error eliminated
- [ ] Mounts properly applied to LXC config
- [ ] All test OCI bundles work
- [ ] Error messages are helpful

### **Template Support**
- [ ] All common template formats supported
- [ ] Clear error messages for invalid templates
- [ ] Template validation working
- [ ] Documentation updated

## 🚀 **Next Steps**

1. **Start with memory leaks** - Most critical issue
2. **Fix OCI bundle mounts** - Core functionality
3. **Enhance template support** - User experience
4. **Test thoroughly** - Ensure stability
5. **Prepare for Sprint 7.2** - Next phase of v0.7.0

---

**Sprint 7.1 ready to begin. Focus on critical stability issues.**
