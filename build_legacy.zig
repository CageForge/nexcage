const std = @import("std");
const Build = std.Build;
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add dependency for zig-json
    const zigJsonDep = b.dependency("zig-json", .{
        .target = target,
        .optimize = optimize,
    });

    // Legacy modules (original architecture)
    const types_mod = b.addModule("types", .{
        .root_source_file = b.path("legacy/src/common/types.zig"),
    });

    const error_mod = b.addModule("error", .{
        .root_source_file = b.path("legacy/src/common/error.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const logger_mod = b.addModule("logger", .{
        .root_source_file = b.path("legacy/src/common/logger.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("legacy/src/common/config.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    const performance_monitor_mod = b.addModule("performance_monitor", .{
        .root_source_file = b.path("legacy/src/common/performance_monitor.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const config_validator_mod = b.addModule("config_validator", .{
        .root_source_file = b.path("legacy/src/common/config_validator.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "performance_monitor", .module = performance_monitor_mod },
        },
    });

    const error_recovery_mod = b.addModule("error_recovery", .{
        .root_source_file = b.path("legacy/src/common/error_recovery.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "performance_monitor", .module = performance_monitor_mod },
        },
    });

    const security_audit_mod = b.addModule("security_audit", .{
        .root_source_file = b.path("legacy/src/common/security_audit.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "performance_monitor", .module = performance_monitor_mod },
        },
    });

    const advanced_container_mod = b.addModule("advanced_container_manager", .{
        .root_source_file = b.path("legacy/src/oci/advanced_container_manager.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const network_mod = b.addModule("network", .{
        .root_source_file = b.path("legacy/src/network/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const proxmox_mod = b.addModule("proxmox", .{
        .root_source_file = b.path("legacy/src/proxmox/proxmox.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "proxmox", .module = proxmox_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
            .{ .name = "zfs", .module = zfs_mod },
            .{ .name = "network", .module = network_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "json_helpers", .module = json_mod },
            .{ .name = "image", .module = image_mod },
            .{ .name = "registry", .module = registry_mod },
            .{ .name = "raw", .module = raw_mod },
            .{ .name = "bfc", .module = bfc_mod },
            .{ .name = "crun", .module = crun_mod },
        },
    });

    const oci_mod = b.addModule("oci", .{
        .root_source_file = b.path("legacy/src/oci/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "proxmox", .module = proxmox_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
            .{ .name = "zfs", .module = zfs_mod },
            .{ .name = "network", .module = network_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "json_helpers", .module = json_mod },
            .{ .name = "image", .module = image_mod },
            .{ .name = "registry", .module = registry_mod },
            .{ .name = "raw", .module = raw_mod },
            .{ .name = "bfc", .module = bfc_mod },
            .{ .name = "crun", .module = crun_mod },
        },
    });

    const zfs_mod = b.addModule("zfs", .{
        .root_source_file = b.path("legacy/src/zfs/mod.zig"),
        .imports = &.{
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
        },
    });

    const json_mod = b.addModule("json_helpers", .{
        .root_source_file = b.path("legacy/src/common/custom_json_parser.zig"),
        .imports = &.{
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
        },
    });

    const image_mod = b.addModule("image", .{
        .root_source_file = b.path("legacy/src/oci/image/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const registry_mod = b.addModule("registry", .{
        .root_source_file = b.path("legacy/src/registry_placeholder.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const raw_mod = b.addModule("raw", .{
        .root_source_file = b.path("legacy/src/raw/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const bfc_mod = b.addModule("bfc", .{
        .root_source_file = b.path("legacy/src/bfc/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const crun_mod = b.addModule("crun", .{
        .root_source_file = b.path("legacy/src/crun/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Legacy executable (deprecated)
    const exe_legacy = b.addExecutable(.{
        .name = "proxmox-lxcri-legacy",
        .root_source_file = b.path("legacy/src/main_legacy.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add system libraries for crun support
    exe_legacy.linkSystemLibrary("c");
    exe_legacy.linkSystemLibrary("cap");
    exe_legacy.linkSystemLibrary("seccomp");

    // Add include paths for crun
    exe_legacy.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "crun-1.23.1/src" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "crun-1.23.1/src/libcrun" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "deps/crun/src/libcrun" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });

    // Add legacy modules to executable
    exe_legacy.root_module.addImport("types", types_mod);
    exe_legacy.root_module.addImport("error", error_mod);
    exe_legacy.root_module.addImport("config", config_mod);
    exe_legacy.root_module.addImport("logger", logger_mod);
    exe_legacy.root_module.addImport("performance_monitor", performance_monitor_mod);
    exe_legacy.root_module.addImport("config_validator", config_validator_mod);
    exe_legacy.root_module.addImport("error_recovery", error_recovery_mod);
    exe_legacy.root_module.addImport("security_audit", security_audit_mod);
    exe_legacy.root_module.addImport("advanced_container_manager", advanced_container_mod);
    exe_legacy.root_module.addImport("network", network_mod);
    exe_legacy.root_module.addImport("proxmox", proxmox_mod);
    exe_legacy.root_module.addImport("oci", oci_mod);
    exe_legacy.root_module.addImport("zig_json", zigJsonDep.module("zig-json"));
    exe_legacy.root_module.addImport("zfs", zfs_mod);
    exe_legacy.root_module.addImport("json_helpers", json_mod);
    exe_legacy.root_module.addImport("image", image_mod);
    exe_legacy.root_module.addImport("registry", registry_mod);
    exe_legacy.root_module.addImport("raw", raw_mod);
    exe_legacy.root_module.addImport("bfc", bfc_mod);
    exe_legacy.root_module.addImport("crun", crun_mod);

    // Install
    b.installArtifact(exe_legacy);
}
