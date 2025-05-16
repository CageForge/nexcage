const std = @import("std");
const Build = std.Build;
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigJsonDep = b.dependency("zig-json", .{
        .target = target,
        .optimize = optimize,
    });

    // Core modules
    const types_mod = b.addModule("types", .{
        .root_source_file = b.path("src/types.zig"),
    });

    const error_mod = b.addModule("error", .{
        .root_source_file = b.path("src/error.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const logger_mod = b.addModule("logger", .{
        .root_source_file = b.path("src/logger.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    // Common module
    const common_mod = b.addModule("common", .{
        .root_source_file = b.path("src/common/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    // Image management
    const image_mod = b.addModule("image", .{
        .root_source_file = b.path("src/image/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // ZFS management
    const zfs_mod = b.addModule("zfs", .{
        .root_source_file = b.path("src/zfs/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // LXC management
    const lxc_mod = b.addModule("lxc", .{
        .root_source_file = b.path("src/lxc/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Network subsystem
    const network_mod = b.addModule("network", .{
        .root_source_file = b.path("src/network/network.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Pod management
    const pod_mod = b.addModule("pod", .{
        .root_source_file = b.path("src/pod/pod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "network", .module = network_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "common", .module = common_mod },
        },
    });

    // Proxmox integration
    const proxmox_mod = b.addModule("proxmox", .{
        .root_source_file = b.path("src/proxmox/proxmox.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "pod", .module = pod_mod },
            .{ .name = "common", .module = common_mod },
        },
    });

    // JSON parser module
    const json_mod = b.addModule("json", .{
        .root_source_file = b.path("src/json_parser.zig"),
        .imports = &.{
            .{ .name = "json", .module = zigJsonDep.module("zig-json") },
        },
    });

    // Pause container module
    const pause_mod = b.addModule("pause", .{
        .root_source_file = b.path("src/pause/pause.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "image", .module = image_mod },
            .{ .name = "zfs", .module = zfs_mod },
        },
    });

    // Container management
    const container_mod = b.addModule("container", .{
        .root_source_file = b.path("src/container/container.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const lxc_container_mod = b.addModule("lxc_container", .{
        .root_source_file = b.path("src/container/lxc.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "container", .module = container_mod },
        },
    });

    const crun_container_mod = b.addModule("crun_container", .{
        .root_source_file = b.path("src/container/crun.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "container", .module = container_mod },
        },
    });

    // OCI runtime
    const oci_mod = b.addModule("oci", .{
        .root_source_file = b.path("src/oci/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "pod", .module = pod_mod },
            .{ .name = "proxmox", .module = proxmox_mod },
            .{ .name = "json", .module = zigJsonDep.module("zig-json") },
            .{ .name = "common", .module = common_mod },
            .{ .name = "image", .module = image_mod },
            .{ .name = "zfs", .module = zfs_mod },
            .{ .name = "lxc", .module = lxc_mod },
            .{ .name = "network", .module = network_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "json", .module = json_mod },
            .{ .name = "pause", .module = pause_mod },
            .{ .name = "container", .module = container_mod },
            .{ .name = "lxc_container", .module = lxc_container_mod },
            .{ .name = "crun_container", .module = crun_container_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies
    exe.root_module.addImport("types", types_mod);
    exe.root_module.addImport("error", error_mod);
    exe.root_module.addImport("logger", logger_mod);
    exe.root_module.addImport("network", network_mod);
    exe.root_module.addImport("pod", pod_mod);
    exe.root_module.addImport("proxmox", proxmox_mod);
    exe.root_module.addImport("oci", oci_mod);
    exe.root_module.addImport("json", zigJsonDep.module("zig-json"));
    exe.root_module.addImport("common", common_mod);
    exe.root_module.addImport("image", image_mod);
    exe.root_module.addImport("zfs", zfs_mod);
    exe.root_module.addImport("lxc", lxc_mod);
    exe.root_module.addImport("json", json_mod);
    exe.root_module.addImport("pause", pause_mod);
    exe.root_module.addImport("container", container_mod);
    exe.root_module.addImport("lxc_container", lxc_container_mod);
    exe.root_module.addImport("crun_container", crun_container_mod);

    // Install
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
