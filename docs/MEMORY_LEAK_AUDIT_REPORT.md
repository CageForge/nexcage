# Memory Leak Audit Report

**Date**: 2025-10-31  
**Status**: In Progress  
**Scope**: Core modules memory management review

---

## Executive Summary

Audited **299 allocator operations** across the codebase. Identified potential memory leak patterns and areas for improvement.

**Status**: 🟡 **Good** - Most allocations are properly managed, but some improvements needed.

---

## Findings

### ✅ Well-Managed Areas

1. **SandboxConfig lifecycle** - Properly cleaned up via `deinit()` and `defer`
2. **Config deinit** - Most config allocations freed in `deinit()`
3. **Error context** - ErrorContext properly manages its own memory

### ⚠️ Areas Needing Improvement

#### 1. `src/core/router.zig`

**Issue**: `createSandboxConfig()` allocates memory that's returned in struct, relying on caller cleanup.

**Current**:
```zig
const name_buf = try self.allocator.dupe(u8, container_id);
return types.SandboxConfig{ .name = name_buf, ... };
```

**Status**: ✅ **Safe** - Memory is managed by SandboxConfig.deinit() and cleanupSandboxConfig()

**Recommendation**: Add explicit errdefer for clarity:
```zig
const name_buf = try self.allocator.dupe(u8, container_id);
errdefer self.allocator.free(name_buf);
```

#### 2. `src/core/config.zig`

**Issues Found**:
- Multiple `allocator.dupe()` calls in update functions without explicit error cleanup
- Pattern allocations without immediate defer (but freed in deinit())

**Line 85**: `config.default_runtime = try self.allocator.dupe(u8, default_str);`
- ✅ **Safe** - Freed in config.deinit()

**Line 221**: `config.log_file = try self.allocator.dupe(u8, file_str);`
- ✅ **Safe** - Old value freed before assignment (line 219)

**Recommendation**: Consider using arena allocators for temporary parsing operations.

#### 3. `src/core/errors.zig`

**Line 153**: `self.allocator.dupe(u8, message) catch return`
- ⚠️ **Potential issue** - If dupe fails, context is partially initialized
- **Fix**: Use errdefer or fail-safe initialization

**Line 193**: `self.context.source = try self.allocator.dupe(u8, source);`
- ✅ **Safe** - ErrorContextBuilder properly manages memory in deinit()

#### 4. `src/core/validation.zig`

**Line 16**: `return try allocator.dupe(u8, resolved);`
- ⚠️ **Need context** - Need to verify caller manages this memory
- **Recommendation**: Document memory ownership

---

## Recommendations

### High Priority

1. **Add errdefer to router.zig**
   - Add errdefer for name_buf allocations
   - Improve error handling clarity

2. **Error context safety in errors.zig**
   - Use errdefer for partial initializations
   - Ensure fail-safe behavior

### Medium Priority

3. **Use arena allocators**
   - For temporary config parsing operations
   - For string formatting operations

4. **Document memory ownership**
   - Add comments for functions that return allocated memory
   - Document which allocator owns returned memory

### Low Priority

5. **Memory profiling**
   - Add long-running tests with memory tracking
   - Profile memory usage patterns

---

## Validation

### Automated Checks

- ✅ Valgrind workflow created (`.github/workflows/memory_leak_check.yml`)
- ✅ Audit script created (`scripts/memory_leak_audit.sh`)

### Manual Review Needed

- [ ] Review all `allocator.dupe()` calls in config.zig
- [ ] Verify SandboxConfig cleanup in all error paths
- [ ] Test long-running operations for memory stability

---

## Conclusion

Overall memory management is **good**, with most allocations properly tracked and freed. The main improvements are:

1. Adding explicit errdefer statements for clarity
2. Using arena allocators for temporary operations
3. Adding long-running memory leak tests

**Risk Level**: 🟡 **Low-Medium** - No critical leaks found, but improvements recommended.

---

## Next Steps

1. Implement errdefer improvements in router.zig
2. Add arena allocator usage in config parsing
3. Run long-running memory leak tests
4. Document memory ownership patterns

