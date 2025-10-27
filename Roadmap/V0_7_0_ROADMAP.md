# Roadmap v0.7.0: Enhanced Stability & OCI Support

**Target Release Date**: 2025-11-15  
**Status**: 📋 PLANNING  
**Priority**: HIGH  

## 🎯 **Release Theme: "Stability & OCI Excellence"**

v0.7.0 focuses on fixing critical stability issues and completing OCI bundle support for production readiness.

## 🚨 **Critical Issues to Address**

### **1. Memory Management (CRITICAL)**
**Current State**: Memory leaks present in config.zig
**Impact**: Production stability concerns
**Priority**: P0 - Blocking

**Tasks**:
- [ ] Fix remaining memory leaks in `config.deinit()`
- [ ] Implement proper cleanup for all dynamic allocations
- [ ] Add memory leak detection in CI/CD
- [ ] Performance testing for memory usage

**Success Criteria**:
- Zero memory leaks in production
- Memory usage stable over time
- No segfaults or crashes

### **2. OCI Bundle Support (HIGH)**
**Current State**: ConfigFileNotFound error, mounts not working
**Impact**: Core functionality broken
**Priority**: P0 - Blocking

**Tasks**:
- [ ] Fix OCI bundle parsing and validation
- [ ] Implement proper mount handling
- [ ] Add OCI bundle generator
- [ ] Support for directory-based rootfs
- [ ] Template conversion from OCI bundles

**Success Criteria**:
- OCI bundles work end-to-end
- Mounts properly applied to LXC config
- Template conversion functional

### **3. Proxmox LXC Integration (HIGH)**
**Current State**: ✅ pct CLI integration completed in v0.6.0, some edge cases remain
**Impact**: Core backend functionality
**Priority**: P1 - Important

**Tasks**:
- [x] ~~Complete pct CLI integration for all operations~~ ✅ **COMPLETED in v0.6.0**
- [ ] Fix pct create required arguments
- [ ] Improve error mapping and handling
- [ ] Add support for all pct configuration options
- [ ] Implement proper VMID management

**Success Criteria**:
- All pct operations working
- Proper error handling and reporting
- Full configuration support

## 🔧 **Enhancement Features**

### **4. Multi-Backend Support (MEDIUM)**
**Current State**: Proxmox LXC working, others need completion
**Impact**: Broader platform support
**Priority**: P2 - Nice to have

**Tasks**:
- [ ] Complete crun backend implementation
- [ ] Complete runc backend implementation
- [ ] Add FreeBSD jail support
- [ ] Implement backend routing logic
- [ ] Add backend-specific configuration

**Success Criteria**:
- Multiple backends functional
- Proper routing between backends
- Platform-specific optimizations

### **5. Testing & Quality Assurance (MEDIUM)**
**Current State**: Basic testing, needs comprehensive coverage
**Impact**: Production confidence
**Priority**: P2 - Important

**Tasks**:
- [ ] E2E testing on self-hosted Proxmox
- [ ] Automated testing for all backends
- [ ] Performance benchmarking
- [ ] Load testing for large deployments
- [ ] CI/CD pipeline improvements

**Success Criteria**:
- >80% test coverage
- All tests passing in CI
- Performance benchmarks established

### **6. Documentation & Developer Experience (LOW)**
**Current State**: Basic documentation, needs improvement
**Impact**: Developer adoption
**Priority**: P3 - Nice to have

**Tasks**:
- [ ] Complete API documentation
- [ ] Create onboarding walkthrough
- [ ] Update CLI reference
- [ ] Architecture documentation
- [ ] Troubleshooting guides

**Success Criteria**:
- Complete documentation
- Easy onboarding process
- Clear troubleshooting guides

## 📅 **Timeline & Milestones**

### **Week 1-2: Critical Fixes**
- **Week 1**: Memory leak fixes, OCI bundle parsing
- **Week 2**: OCI bundle mounts, template conversion

### **Week 3-4: Proxmox Enhancements**
- **Week 3**: Complete pct CLI integration
- **Week 4**: Error handling, configuration support

### **Week 5-6: Testing & Quality**
- **Week 5**: E2E testing, performance testing
- **Week 6**: CI/CD improvements, documentation

### **Week 7: Release Preparation**
- **Week 7**: Final testing, release notes, documentation

## 🎯 **Release Criteria**

### **Must Have (Blocking Release)**
- ✅ Zero memory leaks
- ✅ OCI bundle support working
- ✅ All pct CLI operations functional
- ✅ Basic testing coverage

### **Should Have (Important)**
- ✅ Multi-backend support
- ✅ Performance benchmarks
- ✅ E2E testing
- ✅ Error handling improvements

### **Nice to Have (Optional)**
- ✅ Complete documentation
- ✅ FreeBSD jail support
- ✅ Advanced configuration options
- ✅ Performance optimizations

## 📊 **Success Metrics**

### **Technical Metrics**
- **Memory Usage**: <50MB baseline, no growth over time
- **Performance**: <2s for container operations
- **Reliability**: >99% success rate for standard operations
- **Test Coverage**: >80% for core functionality

### **Feature Metrics**
- **OCI Support**: 100% functional for standard bundles
- **Proxmox LXC**: All pct operations working
- **Multi-Backend**: At least 2 backends fully functional
- **Documentation**: Complete API and user guides

## 🔄 **Risk Mitigation**

### **High Risk Items**
- **Memory leaks**: Could cause production instability
- **OCI bundle parsing**: Complex format, many edge cases
- **pct CLI integration**: External dependency, version compatibility

### **Mitigation Strategies**
- **Early testing**: Continuous testing during development
- **Incremental fixes**: Small, testable changes
- **Fallback options**: Graceful degradation for unsupported features
- **Community feedback**: Early beta testing with users

## 🎉 **Expected Outcomes**

### **For Users**
- Stable, production-ready container management
- Full OCI bundle support
- Better error messages and troubleshooting
- Improved performance and reliability

### **For Developers**
- Clean, well-documented codebase
- Comprehensive testing framework
- Easy contribution process
- Clear architecture and design patterns

### **For the Project**
- Production-ready release
- Strong foundation for future features
- Active community engagement
- Clear roadmap for v0.8.0

---

**v0.7.0 Roadmap ready for implementation. Focus on stability and OCI support.**
