# Sprint 6.7: v0.7.0 Release Plan

**Date**: 2025-10-27  
**Status**: 🚀 READY TO START  
**Version**: v0.7.0  
**Duration**: 2-3 weeks  
**Priority**: HIGH

## 🎯 **Sprint Goals**

Enhance Proxmox LXC integration with native ZFS support and improved OCI image conversion.

## 📋 **Epic #103 Decomposition**

### **Main Epic: OCI Runtime Implementation**
**Issue #103**: Implement 'create' command for Proxmox LXC containers

### **Sub-tasks for Parallel Development**

#### **Track A: ZFS Integration (Developer 1)**
1. **Task A1: Native ZFS Library Integration** (P1 - HIGH)
   - Integrate OpenZFS library via ABI
   - Implement ZFS dataset operations
   - Add ZFS snapshot support
   - Update container file storage to use ZFS

2. **Task A2: Container Storage on ZFS** (P1 - HIGH)
   - Review current container file storage
   - Implement ZFS dataset creation for containers
   - Store container configs on ZFS
   - Implement ZFS snapshots for container state

#### **Track B: OCI Image Conversion (Developer 2)**
1. **Task B1: Enhanced OCI Image Template Creation** (P1 - HIGH)
   - Review current OCI image conversion
   - Implement ZFS snapshot for container templates
   - Extract ENTRYPOINT and IMAGE from metadata.json
   - Replace ENTRYPOINT in lxc.init

2. **Task B2: Template Management** (P2 - MEDIUM)
   - Implement template lifecycle
   - Add template caching
   - Support multiple image formats
   - Template validation

## 🔧 **Detailed Task Breakdown**

### **Task A1: Native ZFS Library Integration**
**Priority**: P1 - HIGH  
**Effort**: 3-4 days  
**Assigned**: Developer 1

**Objective**: Integrate OpenZFS library natively via ABI

**Tasks**:
1. Research OpenZFS ABI and available functions
2. Create OpenZFS bindings in Zig
3. Implement ZFS dataset operations (create, destroy, list)
4. Implement ZFS snapshot operations (create, destroy, rollback)
5. Add ZFS property management
6. Add error handling for ZFS operations

**Files to Create/Modify**:
- `src/integrations/zfs.zig` - Native ZFS bindings
- `deps/openzfs/` - OpenZFS library or ABI definitions
- `build.zig` - Add OpenZFS dependency

**Success Criteria**:
- [ ] OpenZFS library integrated via ABI
- [ ] Basic ZFS operations working (create, destroy, list)
- [ ] Snapshot operations working
- [ ] Error handling implemented
- [ ] Tests pass

### **Task A2: Container Storage on ZFS**
**Priority**: P1 - HIGH  
**Effort**: 2-3 days  
**Assigned**: Developer 1

**Objective**: Store container files on ZFS instead of regular filesystem

**Tasks**:
1. Review current container storage implementation
2. Implement ZFS dataset creation for new containers
3. Store container configs on ZFS
4. Implement ZFS snapshots for container state
5. Add rollback functionality for containers

**Files to Modify**:
- `src/backends/proxmox-lxc/driver.zig` - Update create/delete operations
- `src/backends/proxmox-lxc/state_manager.zig` - Use ZFS for state storage
- `src/integrations/zfs.zig` - ZFS operations

**Success Criteria**:
- [ ] Containers stored on ZFS datasets
- [ ] Configs stored on ZFS
- [ ] Snapshot support working
- [ ] Rollback functionality working
- [ ] Tests pass

### **Task B1: Enhanced OCI Image Template Creation**
**Priority**: P1 - HIGH  
**Effort**: 4-5 days  
**Assigned**: Developer 2

**Objective**: Improve OCI image to LXC template conversion with ZFS snapshots

**Tasks**:
1. Review current OCI image conversion
2. Implement ZFS snapshot for template creation
3. Extract ENTRYPOINT from metadata.json
4. Extract IMAGE information from metadata.json
5. Replace ENTRYPOINT in lxc.init script
6. Store template on ZFS with snapshot

**Files to Modify**:
- `src/backends/proxmox-lxc/image_converter.zig` - Enhanced conversion
- `src/backends/proxmox-lxc/oci_bundle.zig` - Extract metadata
- `src/backends/proxmox-lxc/driver.zig` - Use enhanced templates

**Success Criteria**:
- [ ] Templates created with ZFS snapshots
- [ ] ENTRYPOINT extracted and applied to lxc.init
- [ ] IMAGE metadata preserved
- [ ] Template storage on ZFS
- [ ] Tests pass

### **Task B2: Template Management**
**Priority**: P2 - MEDIUM  
**Effort**: 2-3 days  
**Assigned**: Developer 2

**Objective**: Implement template lifecycle and caching

**Tasks**:
1. Implement template caching
2. Add template validation
3. Support multiple image formats
4. Add template cleanup

**Files to Modify**:
- `src/backends/proxmox-lxc/template_manager.zig` (new)
- `src/backends/proxmox-lxc/image_converter.zig`

**Success Criteria**:
- [ ] Template caching implemented
- [ ] Template validation working
- [ ] Multiple image formats supported
- [ ] Template cleanup working
- [ ] Tests pass

## 🔄 **Parallel Development Strategy**

### **Week 1-2: Core Features**
**Developer 1** (ZFS Track):
- Days 1-4: Task A1 - Native ZFS Integration
- Days 5-7: Task A2 - Container Storage on ZFS

**Developer 2** (OCI Track):
- Days 1-5: Task B1 - Enhanced OCI Image Template
- Days 6-7: Task B2 - Template Management (if time permits)

### **Week 3: Integration & Testing**
- Both developers: Integration testing
- Bug fixes
- Documentation updates
- Release preparation

## 📊 **Dependencies**

### **Critical Dependencies**
- OpenZFS library availability
- Proxmox VE environment for testing
- OCI image samples for testing

### **Risk Mitigation**
- Early OpenZFS integration testing
- Parallel ZFS and OCI development where possible
- Regular integration checkpoints

## 🎯 **Success Criteria**

### **v0.7.0 Release Must Have**:
- [ ] Native ZFS integration working
- [ ] Container storage on ZFS
- [ ] OCI image template conversion with snapshots
- [ ] ENTRYPOINT extracted and applied correctly
- [ ] All tests passing
- [ ] Documentation updated

### **Nice to Have**:
- [ ] Template caching
- [ ] Multiple image format support
- [ ] Performance optimization

## 📝 **Next Steps**

1. Create GitHub issues for each task
2. Label issues appropriately
3. Assign to developers
4. Set up sprint board
5. Start development

---

**Sprint 6.7 ready to begin. Focus on ZFS integration and enhanced OCI conversion for v0.7.0.**

