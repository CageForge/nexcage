#!/bin/bash

# Update imports for files moved to common/
find src -type f -name "*.zig" -exec sed -i \
    -e 's/@import("types")/@import("common\/types")/g' \
    -e 's/@import("types.zig")/@import("common\/types.zig")/g' \
    -e 's/@import("config")/@import("common\/config")/g' \
    -e 's/@import("config.zig")/@import("common\/config.zig")/g' \
    -e 's/@import("error")/@import("common\/error")/g' \
    -e 's/@import("error.zig")/@import("common\/error.zig")/g' \
    -e 's/@import("logger")/@import("common\/logger")/g' \
    -e 's/@import("logger.zig")/@import("common\/logger.zig")/g' \
    -e 's/@import("custom_json_parser")/@import("common\/custom_json_parser")/g' \
    -e 's/@import("custom_json_parser.zig")/@import("common\/custom_json_parser.zig")/g' \
    -e 's/@import("json_helper")/@import("common\/json_helper")/g' \
    -e 's/@import("json_helper.zig")/@import("common\/json_helper.zig")/g' {} \;

# Update imports for image_manager.zig
find src -type f -name "*.zig" -exec sed -i \
    -e 's/@import("image_manager")/@import("container\/image_manager")/g' \
    -e 's/@import("image_manager.zig")/@import("container\/image_manager.zig")/g' {} \;

# Update imports from common/ to short names (because modules are connected via build.zig)
find src -type f -name "*.zig" -exec sed -i \
    -e 's/@import("common\/\([a-zA-Z0-9_\.]*\)")/@import("\1")/g' {} \; 