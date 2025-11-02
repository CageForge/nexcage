# Template Conversion Debug Analysis

## Problem Summary

Template conversion creates very small archives (~868 bytes) instead of proper templates with rootfs content.

## Investigation Results

### 1. Rootfs Source Verification ✅

- **Bundle rootfs path:** `/tmp/nexcage-bundles/test-bundle/rootfs`
- **Rootfs size:** 3.0K (contains `/bin/sh` file)
- **Rootfs structure:** Valid, single file `bin/sh` exists

### 2. Temporary Rootfs Directories ⚠️

**Observation:** Old temp directories are **empty**:
```bash
$ find /tmp/lxc-rootfs-test-conversion-* -type f
# Returns: 0 files
$ du -sh /tmp/lxc-rootfs-test-conversion-*
# Returns: 1.0K (just directory, no files)
```

This indicates that either:
- Files are not being copied correctly
- Files are being deleted before archive creation
- Copy logic has a bug

### 3. Copy Logic Analysis

The `copyDirectoryRecursive` function (lines 165-194 in `image_converter.zig`):

```zig
fn copyDirectoryRecursive(self: *Self, source_dir: std.fs.Dir, dest_path: []const u8) !void {
    var iterator = source_dir.iterate();
    while (try iterator.next()) |entry| {
        const source_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dest_path, entry.name });
        // ... copy logic
    }
}
```

**Potential Issues:**
1. Directory iteration might miss files if not done correctly
2. Error handling might silently fail
3. File permissions might not be preserved

### 4. Archive Creation

The `createTemplateArchive` function (lines 431-449):

```zig
const args = [_][]const u8{ "tar", "--zstd", "-cf", archive_path, "-C", rootfs_dir, "." };
```

**If `rootfs_dir` is empty or missing files, tar will create an empty archive.**

### 5. Test Results

**Manual archive creation test:**
```bash
$ cd /tmp/test-debug-rootfs
$ tar --zstd -cf /tmp/test-debug-archive.tar.zst .
$ ls -lh /tmp/test-debug-archive.tar.zst
-rw-r--r-- 1 root root 125 Nov  2 14:49 /tmp/test-debug-archive.tar.zst
```

When rootfs has content (`bin/sh`), archive is **125 bytes** (still very small, but valid).

**Current generated templates:** ~868 bytes (7x larger than expected empty archive)

This suggests:
- Some files ARE being copied (template is larger than empty archive)
- But most content is missing
- Possibly only directory structure or metadata files are included

### 6. Root Cause Hypothesis

**Most likely cause:** The `copyDirectoryRecursive` function is **not copying all files correctly**. Possible reasons:

1. **Iterator issue:** The directory iterator might not traverse all entries
2. **Path construction issue:** Dest path might be constructed incorrectly
3. **Error handling:** Errors during copy might be silently ignored
4. **Timing issue:** Cleanup might happen before archive is fully created

### 7. Specific Issues Found

#### Issue 1: Empty Temp Directories
All old temp directories are empty, suggesting copy operation consistently fails.

#### Issue 2: Small Archive Size
Generated archives are ~868 bytes when they should be at least several KB (even for minimal rootfs).

#### Issue 3: No Error Logs
The conversion process doesn't log copy failures, making debugging difficult.

### 8. Code Flow Analysis

```zig
pub fn convertOciToProxmoxTemplate(...) !void {
    const temp_rootfs = "/tmp/lxc-rootfs-{template_name}";
    
    // Step 1: Convert OCI to LXC rootfs
    try self.convertOciToLxcRootfs(oci_bundle_path, temp_rootfs);
    // ↑ This calls extractRootfs → copyDirectoryRecursive
    
    // Step 2: Create Proxmox template
    try self.createProxmoxTemplate(temp_rootfs, template_name, storage);
    // ↑ This calls createTemplateArchive → tar command
    
    // Step 3: Cleanup
    try self.cleanupDirectory(temp_rootfs);
    // ↑ Removes temp directory
}
```

**Problem:** If `copyDirectoryRecursive` fails silently, `createTemplateArchive` will create an archive from an empty directory.

### 9. Recommended Fixes

1. **Add logging to copyDirectoryRecursive:**
   - Log each file being copied
   - Log total files copied
   - Log any errors

2. **Add validation before archive creation:**
   - Check if temp_rootfs has files
   - Verify at least some expected files exist
   - Fail early with clear error if rootfs is empty

3. **Fix copyDirectoryRecursive:**
   - Ensure iterator handles all entry types correctly
   - Add explicit error handling for each copy operation
   - Verify files exist after copy

4. **Add debug mode checks:**
   - Keep temp directories in debug mode
   - Don't cleanup immediately for inspection

5. **Improve error messages:**
   - Report which files failed to copy
   - Show source and destination paths on errors

### 10. Next Steps

1. Add debug logging to `copyDirectoryRecursive`
2. Add validation before archive creation
3. Test with a minimal but valid rootfs
4. Verify archive contents before uploading
5. Keep temp directories for inspection during debugging

### 11. Test Cases

**Test 1: Minimal rootfs (current)**
- Source: `/tmp/nexcage-bundles/test-bundle/rootfs` (1 file: `bin/sh`)
- Expected: Archive with at least `bin/sh`
- Actual: Empty temp directories

**Test 2: Manual copy verification**
- Direct `cp -a` works correctly
- Zig copy logic needs verification

**Test 3: Archive content verification**
- Generated archives should be extractable
- Should contain rootfs files

## Conclusion

The root cause is likely in the `copyDirectoryRecursive` function which fails to copy files from source to destination. The function needs:
1. Better error handling
2. Debug logging
3. Validation
4. Possibly a rewrite using a more reliable copy method

