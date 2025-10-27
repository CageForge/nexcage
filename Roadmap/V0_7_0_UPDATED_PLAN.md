# Updated Plan v0.7.0: After v0.6.0 Release

**Date**: 2025-10-23  
**Status**: 📋 UPDATED  
**Previous Release**: v0.6.0 (✅ COMPLETED)  

## 🎉 **v0.6.0 Achievements**

### ✅ **Completed in v0.6.0:**
- **Full container lifecycle management** (create/start/stop/delete/list)
- **Proxmox LXC backend integration** with pct CLI
- **Advanced logging system** with debug mode
- **Configuration system** with priority support
- **Proxmox template support** in create command
- **Comprehensive CLI interface** with help support
- **Memory leaks partially fixed** (segfault resolved)
- **Full cycle tested** on Proxmox server

### 🎯 **Key Success:**
- **Issue #87: LXC: pct CLI for all ops** ✅ **COMPLETED**
- All basic pct operations working (create, start, stop, delete, list)
- Template support functional
- CLI interface complete

## 🚨 **Remaining Critical Issues for v0.7.0**

### **P0 - Blocking (CRITICAL)**
1. **Memory Leaks** - Still present in config.zig (non-critical but should fix)
2. **OCI Bundle Mounts** - ConfigFileNotFound error when applying mounts
3. **System Integrity Checks** - Need to implement (Issue #113)

### **P1 - Important (HIGH)**
1. **pct Error Handling** - Fix required args & error mapping (Issue #90)
2. **OCI Runtime Create** - Implement create command (Issue #103)
3. **OCI Bundle Generator** - Create rootfs + config.json (Issue #92)

### **P2 - Nice to Have (MEDIUM)**
1. **Multi-Backend Support** - crun/runc/FreeBSD jail (Issues #88, #108)
2. **E2E Testing** - Self-hosted Proxmox testing (Issue #91)
3. **Documentation** - Keep docs current (Issues #96, #97)

## 🎯 **Updated v0.7.0 Goals**

### **Primary Focus: OCI Excellence**
Since pct CLI integration is complete, focus shifts to:
1. **Complete OCI bundle support** (mounts, parsing, generation)
2. **Fix remaining memory leaks** (stability)
3. **Improve error handling** (user experience)
4. **Add system integrity checks** (reliability)

### **Secondary Focus: Multi-Backend**
1. **Complete crun/runc backends** (OCI runtime parity)
2. **Add FreeBSD jail support** (platform diversity)
3. **Implement backend routing** (intelligent selection)

## 📅 **Updated Timeline**

### **Week 1: OCI Bundle Support**
- Fix OCI bundle mounts (ConfigFileNotFound)
- Implement OCI bundle generator
- Test with various OCI bundle formats

### **Week 2: Memory & Stability**
- Fix remaining memory leaks
- Implement system integrity checks
- Add comprehensive error handling

### **Week 3: Multi-Backend Support**
- Complete crun backend
- Complete runc backend
- Add FreeBSD jail support

### **Week 4: Testing & Polish**
- E2E testing on Proxmox
- Performance testing
- Documentation updates

## 🎯 **Updated Success Criteria**

### **Must Have (Blocking v0.7.0)**
- ✅ OCI bundle mounts working
- ✅ OCI bundle generator functional
- ✅ Memory leaks fixed
- ✅ System integrity checks implemented

### **Should Have (Important)**
- ✅ Multi-backend support (crun/runc)
- ✅ Improved error handling
- ✅ E2E testing coverage
- ✅ Performance benchmarks

### **Nice to Have (Optional)**
- ✅ FreeBSD jail support
- ✅ Complete documentation
- ✅ Advanced configuration options

## 🚀 **Immediate Next Steps**

### **Sprint 7.1 (This Week)**
1. **Fix OCI bundle mounts** - ConfigFileNotFound error
2. **Fix memory leaks** - Complete config.zig cleanup
3. **Improve pct error handling** - Better error messages

### **Sprint 7.2 (Next Week)**
1. **Implement OCI bundle generator** - rootfs + config.json
2. **Add system integrity checks** - Reliability improvements
3. **Complete crun backend** - OCI runtime support

## 📊 **Updated Metrics**

### **Technical Goals**
- **Memory Usage**: 0 leaks, stable over 24+ hours
- **OCI Support**: 100% functional for standard bundles
- **Error Rate**: <1% for standard operations
- **Test Coverage**: >80% for core functionality

### **Feature Goals**
- **OCI Bundles**: Full lifecycle support
- **Multi-Backend**: 3+ backends functional
- **Error Handling**: Clear, actionable error messages
- **Documentation**: Complete and current

## 🎉 **v0.7.0 Vision**

**"OCI Excellence & Multi-Backend Support"**

v0.7.0 will complete the OCI ecosystem support and add multi-backend capabilities, making nexcage a truly versatile container runtime interface that works across multiple platforms and container formats.

---

**Updated plan reflects v0.6.0 achievements and focuses on remaining critical issues.**
