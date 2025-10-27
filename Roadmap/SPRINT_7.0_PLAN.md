# Sprint 7.0: Next Release Planning v0.7.0

**Date**: 2025-10-21  
**Status**: 📋 PLANNING  
**Duration**: 2-3 weeks  

## 🎯 **Sprint Goals for v0.7.0**

Based on current open issues and project needs, define priorities for the next major release.

## 📋 **Current Open Issues Analysis**

### **High Priority Issues (Must Fix)**
- **Issue #113**: System integrity checks
- **Issue #103**: OCI Runtime: Implement 'create' command for Proxmox LXC containers
- **Issue #90**: LXC: pct create required args & error mapping
- ~~**Issue #87**: LXC: pct CLI for all ops~~ ✅ **COMPLETED in v0.6.0**

### **Medium Priority Issues (Should Fix)**
- **Issue #108**: OCI backends: minimal lifecycle parity (jail on FreeBSD)
- **Issue #88**: OCI backends: minimal lifecycle parity (crun/runc)
- **Issue #91**: LXC lifecycle E2E on self-hosted Proxmox
- **Issue #92**: OCI: bundle generator (rootfs + minimal config.json)

### **Low Priority Issues (Nice to Have)**
- **Issue #97**: Onboarding: walkthrough DEV_QUICKSTART & dev_guide
- **Issue #96**: Docs: keep README, DEV_QUICKSTART, CLI_REFERENCE current
- **Issue #94**: CI: keep all workflows green on Zig 0.15.1
- **Issue #89**: Architecture conformance report
- **Issue #85**: Architecture: review ADR-001 vs implementation

## 🎯 **Proposed v0.7.0 Goals**

### **1. Memory Management & Stability (Critical)**
- **Fix remaining memory leaks** in config.zig
- **Improve error handling** and recovery
- **Add system integrity checks** (Issue #113)
- **Performance optimization** for large-scale deployments

### **2. OCI Bundle Support (High Priority)**
- **Fix OCI bundle mounts** (ConfigFileNotFound error)
- **Implement OCI bundle generator** (Issue #92)
- **Complete OCI lifecycle parity** for crun/runc (Issue #88)
- **Add FreeBSD jail support** (Issue #108)

### **3. Proxmox LXC Enhancements (High Priority)**
- ~~**Complete pct CLI integration** (Issue #87)~~ ✅ **COMPLETED in v0.6.0**
- **Fix pct create required args** (Issue #90)
- **Implement OCI Runtime create command** (Issue #103)
- **Improve error mapping** for pct commands

### **4. Testing & CI/CD (Medium Priority)**
- **E2E testing on self-hosted Proxmox** (Issue #91)
- **Keep CI workflows green** on Zig 0.15.1 (Issue #94)
- **Add automated testing** for all backends
- **Performance benchmarking**

### **5. Documentation & Onboarding (Low Priority)**
- **Update documentation** (Issue #96)
- **Create onboarding walkthrough** (Issue #97)
- **Architecture conformance report** (Issue #89)
- **Review ADR-001 implementation** (Issue #85)

## 🚀 **Proposed Sprint 7.0 Timeline**

### **Week 1: Core Stability**
- Fix memory leaks in config.zig
- Implement system integrity checks
- Improve error handling

### **Week 2: OCI Bundle Support**
- Fix OCI bundle mounts
- Implement OCI bundle generator
- Complete OCI lifecycle parity

### **Week 3: Proxmox LXC Enhancements**
- Complete pct CLI integration
- Fix pct create required args
- Implement OCI Runtime create command

### **Week 4: Testing & Documentation**
- E2E testing on Proxmox
- Update documentation
- Performance testing

## 📊 **Success Metrics**

### **Technical Metrics**
- **Memory leaks**: 0 critical leaks
- **Test coverage**: >80% for core functionality
- **Performance**: <2s for container operations
- **Error rate**: <1% for standard operations

### **Feature Metrics**
- **OCI bundle support**: 100% functional
- **Proxmox LXC**: All pct operations working
- **Multi-backend**: crun/runc/FreeBSD jail support
- **Documentation**: Complete and up-to-date

## 🎯 **Release Criteria for v0.7.0**

### **Must Have (Blocking)**
- ✅ Memory leaks fixed
- ✅ OCI bundle mounts working
- ✅ All pct CLI operations functional
- ✅ System integrity checks implemented

### **Should Have (Important)**
- ✅ OCI bundle generator working
- ✅ Multi-backend support (crun/runc)
- ✅ E2E testing on Proxmox
- ✅ Performance benchmarks

### **Nice to Have (Optional)**
- ✅ FreeBSD jail support
- ✅ Complete documentation
- ✅ Onboarding walkthrough
- ✅ Architecture conformance

## 🔄 **Next Steps**

1. **Review and approve** this plan
2. **Assign issues** to team members
3. **Set up project board** for Sprint 7.0
4. **Begin implementation** starting with critical issues
5. **Regular progress reviews** and adjustments

---

**Sprint 7.0 planning ready for review and approval.**
