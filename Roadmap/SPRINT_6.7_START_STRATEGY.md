# Sprint 6.7: Start Strategy

**Date**: 2025-10-27  
**Status**: 🚀 STARTING

## 📋 Current State Analysis

### ✅ What Already Exists
- **ZFS CLI Integration**: `src/integrations/zfs/client.zig` uses `zfs` command
- **Basic Operations**: Dataset existence check, snapshot creation
- **Error Handling**: ZFSError types defined
- **Logger Support**: Integrated with logging system

### ❌ What Needs to be Done

#### Task A1: Enhance ZFS Integration
**Current**: Uses `zfs` command via CLI  
**Goal**: Use native OpenZFS library via ABI (or keep CLI approach but enhance it)

**Recommendation**: 
Since we already have CLI integration working, we should:
1. **Enhance existing ZFS client** with more operations
2. Add dataset creation/destruction for containers
3. Add snapshot management for container state
4. Add rollback operations
5. Document the approach (CLI vs native ABI)

#### Task A2: Container Storage on ZFS
**Dependency**: Task A1 must be enhanced first  
**Goal**: Store containers on ZFS datasets instead of regular filesystem

#### Task B1: Enhanced OCI Template Creation
**Goal**: 
- Use ZFS snapshots for template creation
- Extract ENTRYPOINT from metadata.json
- Replace ENTRYPOINT in lxc.init

#### Task B2: Template Management
**Dependency**: Task B1  
**Goal**: Implement template caching and lifecycle

## 🚀 Recommended Starting Point

### For Developer 1 (Track A)
**Start with**: Enhance existing ZFS client

**Files to Modify**:
1. `src/integrations/zfs/client.zig` - Add more operations
2. `src/integrations/zfs/types.zig` - Add more types

**Tasks**:
1. Add `createDataset()` function
2. Add `destroyDataset()` function
3. Add `listDatasets()` function
4. Add snapshot rollback support
5. Add dataset property management

### For Developer 2 (Track B)
**Start with**: Review current OCI conversion

**Files to Review**:
1. `src/backends/proxmox-lxc/image_converter.zig`
2. `src/backends/proxmox-lxc/oci_bundle.zig`

**Tasks**:
1. Analyze current metadata extraction
2. Plan ENTRYPOINT extraction
3. Plan lxc.init replacement logic

## 📝 Decision: CLI vs Native ABI

### Option 1: Keep CLI Approach (Recommended)
**Pros**:
- Already working
- Simpler implementation
- No external library dependencies
- Good for initial implementation

**Cons**:
- Requires `zfs` command to be installed
- Process overhead for each operation

### Option 2: Native ABI (More Complex)
**Pros**:
- Direct library access
- Better performance
- No shell command overhead

**Cons**:
- Complex bindings required
- Library version compatibility
- More maintenance burden

**Recommendation**: Start with CLI approach, document the decision. If needed, native ABI can be added later.

## 🎯 First Day Plan

### Developer 1 (Track A):
1. Review `src/integrations/zfs/client.zig`
2. Add missing ZFS operations (create, destroy, list datasets)
3. Test operations
4. Document approach

### Developer 2 (Track B):
1. Review `src/backends/proxmox-lxc/image_converter.zig`
2. Review `src/backends/proxmox-lxc/oci_bundle.zig`
3. Find where metadata.json is parsed
4. Plan ENTRYPOINT extraction logic

## 📚 References

- Existing ZFS client: `src/integrations/zfs/client.zig`
- ZFS types: `src/integrations/zfs/types.zig`
- Task A1: Issue #116
- Task B1: Issue #118

---

**Start with enhancing existing ZFS client (Task A1) as it's the foundation for everything else.**

