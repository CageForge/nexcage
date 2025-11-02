# Test Results: Resources and Namespaces on Proxmox Server

**Server:** mgr.cp.if.ua (root@mgr.cp.if.ua)  
**Date:** 2025-11-02  
**Test:** OCI Bundle Resources and Namespaces

## Test Environment

- **Server:** mgr.cp.if.ua (144.76.18.89)
- **Proxmox Version:** Available (pct command works)
- **ZFS Pools:** rpool, bpool (tank pool does not exist)
- **Test Bundle:** `/tmp/nexcage-bundles/test-bundle/`

## Test Progress

### ✅ Successful Steps

1. **Connection:** SSH connection successful
2. **Bundle Transfer:** Test bundle transferred and validated
3. **Bundle Validation:** JSON syntax valid, structure correct
4. **Path Validation:** Bundle path validated successfully with `/tmp/nexcage-bundles/` prefix
5. **VMID Generation:** VMID allocated successfully (259943, 571976, 478865)
6. **ZFS Configuration:** rpool/containers dataset created
7. **Resource Parsing:** Bundle config.json parsed (memory: 256MB, CPU: 512 shares)

### ⚠️ Issues Encountered

1. **Template Conversion Issue:**
   - OCI bundle conversion creates very small templates (~810-868 bytes)
   - Template files exist but appear incomplete
   - Error: `got unexpected ostype (unmanaged != ubuntu)`

2. **Memory Leak:**
   - Memory leak detected in `template_manager.zig:218`
   - Related to TemplateInfo initialization

3. **Operation Failed:**
   - `pct create` command fails during template extraction
   - Error occurs after VMID allocation and before container creation

### Test Output Analysis

```
[DRIVER] create: VMID allocated: 259943
[DRIVER] create: VMID is unique
[DRIVER] create: Building pct create command arguments
error(gpa): memory address leaked (template_manager.zig:218)
error: OperationFailed
```

**Command that would be executed:**
```bash
pct create 259943 local:vztmpl/test-final-run-1762093751.tar.zst \
  --hostname test-final-run \
  --memory 256 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr50,ip=dhcp \
  --ostype ubuntu \
  --unprivileged 0
```

## Findings

### Resource Configuration ✅

- Memory limit correctly parsed: **256 MB** (268435456 bytes)
- CPU shares correctly parsed: **512** (converts to ~0.5 cores → 1 core)
- Resources are properly extracted from `linux.resources` in config.json

### Namespace Configuration ✅

- Namespaces correctly parsed from `linux.namespaces` array
- All 6 namespaces detected: pid, network, ipc, uts, mount, user
- User namespace detected (will trigger nesting=1, keyctl=1 features)

### Issues to Address

1. **Template Conversion:**
   - OCI bundle → Proxmox template conversion needs review
   - Generated templates are too small (corrupted or incomplete)
   - Need to verify `ImageConverter.convertOciToProxmoxTemplate()` logic

2. **Memory Management:**
   - Memory leak in TemplateInfo initialization
   - Need to add proper cleanup/deinit

3. **Error Handling:**
   - Better error messages needed for template conversion failures
   - Should validate template size before using

## Recommendations

1. **Use Existing Templates for Testing:**
   - Use pre-existing Proxmox templates (e.g., alpine-3.22) for initial testing
   - Verify resource and namespace application separately

2. **Fix Template Conversion:**
   - Review `src/backends/proxmox-lxc/image_converter.zig`
   - Ensure rootfs is properly packaged into template
   - Verify template format (tar.zst compression)

3. **Memory Leak Fix:**
   - Add proper cleanup in TemplateInfo
   - Ensure all allocated memory is freed

4. **Alternative Testing Approach:**
   - Test resource/namespace parsing separately (unit tests ✅)
   - Test with manually created templates
   - Verify features application after manual container creation

## Next Steps

1. ✅ **Unit Tests:** Resources and namespaces parsing works correctly
2. ⚠️ **Template Conversion:** Needs debugging/fixing
3. ⏳ **Integration Test:** Complete end-to-end test pending template fix

## Status Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Bundle Parsing | ✅ PASS | Resources and namespaces correctly parsed |
| Path Validation | ✅ PASS | Bundle path validation works |
| VMID Generation | ✅ PASS | Unique VMIDs generated |
| Resource Extraction | ✅ PASS | Memory and CPU correctly extracted |
| Namespace Parsing | ✅ PASS | All namespaces detected |
| Template Conversion | ❌ FAIL | Templates too small/corrupted |
| Container Creation | ⏳ PENDING | Blocked by template issue |
| Features Application | ⏳ PENDING | Blocked by container creation |

## Conclusion

The implementation of resource limits and namespaces **parsing is working correctly**. The issue preventing full testing is in the template conversion process, which is a separate concern. The core functionality for resources and namespaces is implemented and ready once template conversion is fixed.

