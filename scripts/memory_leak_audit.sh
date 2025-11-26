#!/bin/bash
# Memory Leak Audit Script
# Finds potential memory leaks by checking for allocator calls without defer/errdefer

set -e

echo "=== Memory Leak Audit ==="
echo ""

# Find all allocator calls
echo "📊 Searching for allocator operations..."
ALLOC_COUNT=$(grep -r "allocator\.\(create\|alloc\|dupe\|print\|allocPrint\)" src/ --include="*.zig" | wc -l)
echo "Found $ALLOC_COUNT allocator operations"

echo ""
echo "🔍 Checking for missing defer/errdefer..."

# Find functions with allocator calls but no corresponding defer
find src/ -name "*.zig" -exec grep -l "allocator\." {} \; | while read file; do
    echo ""
    echo "Checking: $file"
    
    # Check for allocator.dupe without defer on next few lines
    awk '
    /allocator\.(create|alloc|dupe|print|allocPrint)/ {
        line=$0
        lineno=NR
        found=0
        for(i=1; i<=10 && i+NR <= FNR+10; i++) {
            getline next_line
            if (next_line ~ /defer|errdefer/) {
                found=1
                break
            }
        }
        if (!found && line !~ /\/\/.*defer/) {
            print "  ⚠️  Line " lineno ": " line
        }
    }
    ' "$file" || true
done

echo ""
echo "✅ Audit complete"
echo ""
echo "💡 Tips:"
echo "  - Look for allocator.dupe/create/alloc without defer/errdefer"
echo "  - Ensure all allocated memory is freed in deinit() functions"
echo "  - Use arena allocators for temporary operations"

