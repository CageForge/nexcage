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

    // Опціональна залежність для crun
    const use_crun = b.option(bool, "crun", "Enable crun runtime support") orelse false;
    const crunDep = if (use_crun) b.dependency("crun", .{
        .target = target,
        .optimize = optimize,
    }) else null;

    // Core modules
    const types_mod = b.addModule("types", .{
        .root_source_file = b.path("src/common/types.zig"),
    });

    // Error module
    const error_mod = b.addModule("error", .{
        .root_source_file = b.path("src/common/error.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    // Logger module
    const logger_mod = b.addModule("logger", .{
        .root_source_file = b.path("src/common/logger.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    // Config module
    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/common/config.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // ZFS management - placeholder for future implementation
    const zfs_mod = b.addModule("zfs", .{
        .root_source_file = b.path("src/zfs_placeholder.zig"),
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

    // Proxmox integration
    const proxmox_mod = b.addModule("proxmox", .{
        .root_source_file = b.path("src/proxmox/proxmox.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // JSON helper module (wraps zig-json)
    const json_mod = b.addModule("json_helpers", .{
        .root_source_file = b.path("src/common/custom_json_parser.zig"),
        .imports = &.{
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
        },
    });

    // Crun container module (опціональний)
    const crun_container_mod = if (use_crun) b.addModule("crun_container", .{
        .root_source_file = b.path("src/container/crun.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "crun", .module = crunDep.?.module("crun") },
        },
    }) else null;

    // CLI args module
    const cli_args_mod = b.addModule("cli_args", .{
        .root_source_file = b.path("src/common/cli_args.zig"),
        .imports = &.{
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Placeholder modules for future implementation
    const image_mod = b.addModule("image", .{
        .root_source_file = b.path("src/image_placeholder.zig"),
        .imports = &.{
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "json", .module = json_mod },
        },
    });

    const lxc_mod = b.addModule("lxc", .{
        .root_source_file = b.path("src/lxc_placeholder.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const crun_mod = b.addModule("crun", .{
        .root_source_file = b.path("src/crun_placeholder.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const registry_mod = b.addModule("registry", .{
        .root_source_file = b.path("src/registry_placeholder.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Raw image module
    const raw_mod = b.addModule("raw", .{
        .root_source_file = b.path("src/raw/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // OCI runtime
    const oci_mod = b.addModule("oci", .{
        .root_source_file = b.path("src/oci/mod.zig"),
        .imports = if (use_crun) &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "proxmox", .module = proxmox_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
            .{ .name = "zfs", .module = zfs_mod },
            .{ .name = "network", .module = network_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "json_helpers", .module = json_mod },
            .{ .name = "crun_container", .module = crun_container_mod.? },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "image", .module = image_mod },
            .{ .name = "lxc", .module = lxc_mod },
            .{ .name = "crun", .module = crun_mod },
            .{ .name = "registry", .module = registry_mod },
        } else &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "proxmox", .module = proxmox_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
            .{ .name = "zfs", .module = zfs_mod },
            .{ .name = "network", .module = network_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "json_helpers", .module = json_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "image", .module = image_mod },
            .{ .name = "lxc", .module = lxc_mod },
            .{ .name = "crun", .module = crun_mod },
            .{ .name = "registry", .module = registry_mod },
            .{ .name = "raw", .module = raw_mod },
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
    exe.root_module.addImport("config", config_mod);
    exe.root_module.addImport("logger", logger_mod);
    exe.root_module.addImport("network", network_mod);
    exe.root_module.addImport("proxmox", proxmox_mod);
    exe.root_module.addImport("oci", oci_mod);
    exe.root_module.addImport("json", zigJsonDep.module("zig-json"));
    exe.root_module.addImport("zfs", zfs_mod);
    exe.root_module.addImport("json_helpers", json_mod);
    if (use_crun) {
        exe.root_module.addImport("crun_container", crun_container_mod.?);
        exe.root_module.addImport("crun", crunDep.?.module("crun"));
    }
    exe.root_module.addImport("cli_args", cli_args_mod);
    exe.root_module.addImport("image", image_mod);
    exe.root_module.addImport("lxc", lxc_mod);
    exe.root_module.addImport("crun", crun_mod);
    exe.root_module.addImport("registry", registry_mod);
    exe.root_module.addImport("raw", raw_mod);

    // Install
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Tests
    const config_test = b.addTest(.{
        .root_source_file = b.path("tests/config_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    config_test.root_module.addImport("types", types_mod);
    config_test.root_module.addImport("error", error_mod);
    config_test.root_module.addImport("logger", logger_mod);
    config_test.root_module.addImport("config", config_mod);
    config_test.root_module.addImport("json", zigJsonDep.module("zig-json"));
    config_test.root_module.addImport("oci", oci_mod);

    const run_config_test = b.addRunArtifact(config_test);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_config_test.step);

    // TODO: Add new tests for remaining functionality
}
