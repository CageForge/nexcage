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

    // BFC (Binary File Container) library
    const bfc_lib = b.addStaticLibrary(.{
        .name = "bfc",
        .target = target,
        .optimize = optimize,
    });
    
    // Add BFC source files
    bfc_lib.addCSourceFiles(.{
        .files = &.{
            "deps/bfc/src/lib/bfc_compress.c",
            "deps/bfc/src/lib/bfc_crc32c.c",
            "deps/bfc/src/lib/bfc_encrypt.c",
            "deps/bfc/src/lib/bfc_format.c",
            "deps/bfc/src/lib/bfc_iter.c",
            "deps/bfc/src/lib/bfc_os.c",
            "deps/bfc/src/lib/bfc_reader.c",
            "deps/bfc/src/lib/bfc_util.c",
            "deps/bfc/src/lib/bfc_writer.c",
        },
        .flags = &.{
            "-std=c17",
            "-Wall",
            "-Wextra",
            "-O3",
            "-DNDEBUG",
        },
    });
    
    // Add BFC include path
    bfc_lib.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });
    
    // Link system libraries for BFC
    bfc_lib.linkSystemLibrary("c");
    // bfc_lib.linkSystemLibrary("zstd");
    // bfc_lib.linkSystemLibrary("sodium");
    
    // Install BFC library
    b.installArtifact(bfc_lib);

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

    // Performance monitor module
    const perf_monitor_mod = b.addModule("performance_monitor", .{
        .root_source_file = b.path("src/common/performance_monitor.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Configuration validator module
    const config_validator_mod = b.addModule("config_validator", .{
        .root_source_file = b.path("src/common/config_validator.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Test utilities module
    const test_utilities_mod = b.addModule("test_utilities", .{
        .root_source_file = b.path("tests/test_utilities.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Error recovery module
    const error_recovery_mod = b.addModule("error_recovery", .{
        .root_source_file = b.path("src/common/error_recovery.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "performance_monitor", .module = perf_monitor_mod },
        },
    });

    // Security audit module
    const security_audit_mod = b.addModule("security_audit", .{
        .root_source_file = b.path("src/common/security_audit.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "performance_monitor", .module = perf_monitor_mod },
        },
    });

    // Advanced container manager module
    const advanced_container_mod = b.addModule("advanced_container_manager", .{
        .root_source_file = b.path("src/oci/advanced_container_manager.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "performance_monitor", .module = perf_monitor_mod },
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
        .root_source_file = b.path("src/zfs/mod.zig"),
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

    // CLI args module (disabled - file removed)
    // const cli_args_mod = b.addModule("cli_args", .{
    //     .root_source_file = b.path("src/common/cli_args.zig"),
    //     .imports = &.{
    //         .{ .name = "logger", .module = logger_mod },
    //     },
    // });

    // OCI Image module
    const image_mod = b.addModule("image", .{
        .root_source_file = b.path("src/oci/image/mod.zig"),
        .imports = &.{
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
        },
    });

    // Performance monitoring and optimization module
    const performance_mod = b.addModule("performance", .{
        .root_source_file = b.path("src/performance/mod.zig"),
        .imports = &.{
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "types", .module = types_mod },
        },
    });

    // Registry module
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

    // BFC (Binary File Container) module
    const bfc_mod = b.addModule("bfc", .{
        .root_source_file = b.path("src/bfc/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // OCI runtime module
    const oci_mod = b.addModule("oci", .{
        .root_source_file = b.path("src/oci/mod.zig"),
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
            // .{ .name = "cli_args", .module = cli_args_mod }, // disabled - file removed
            .{ .name = "image", .module = image_mod },
            .{ .name = "registry", .module = registry_mod },
            .{ .name = "raw", .module = raw_mod },
            .{ .name = "bfc", .module = bfc_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add system libraries for crun support
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("cap");
    exe.linkSystemLibrary("seccomp");
    exe.linkSystemLibrary("yajl");
    
    // Link BFC library
    exe.linkLibrary(bfc_lib);
    // exe.linkSystemLibrary("zstd");
    // exe.linkSystemLibrary("sodium");
    
    // Add include paths for crun headers
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src" });
    exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src/libcrun" });
    
    // Add BFC include path
    exe.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });

    // Add dependencies
    exe.root_module.addImport("types", types_mod);
    exe.root_module.addImport("error", error_mod);
    exe.root_module.addImport("config", config_mod);
    exe.root_module.addImport("logger", logger_mod);
    exe.root_module.addImport("performance_monitor", perf_monitor_mod);
    exe.root_module.addImport("config_validator", config_validator_mod);
    exe.root_module.addImport("error_recovery", error_recovery_mod);
    exe.root_module.addImport("security_audit", security_audit_mod);
    exe.root_module.addImport("advanced_container_manager", advanced_container_mod);
    exe.root_module.addImport("network", network_mod);
    exe.root_module.addImport("proxmox", proxmox_mod);
    exe.root_module.addImport("oci", oci_mod);
    exe.root_module.addImport("zig_json", zigJsonDep.module("zig-json"));
    exe.root_module.addImport("zfs", zfs_mod);
    exe.root_module.addImport("json_helpers", json_mod);
    // exe.root_module.addImport("cli_args", cli_args_mod); // disabled - file removed
    exe.root_module.addImport("image", image_mod);
    exe.root_module.addImport("registry", registry_mod);
    exe.root_module.addImport("raw", raw_mod);
    exe.root_module.addImport("bfc", bfc_mod);

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
    config_test.root_module.addImport("zig_json", zigJsonDep.module("zig-json"));
    config_test.root_module.addImport("oci", oci_mod);

    const run_config_test = b.addRunArtifact(config_test);
    
    // Crun module test
    const crun_test = b.addTest(.{
        .root_source_file = b.path("tests/oci/crun_simple_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    crun_test.root_module.addImport("oci", oci_mod);
    crun_test.root_module.addImport("types", types_mod);
    crun_test.root_module.addImport("error", error_mod);
    crun_test.root_module.addImport("logger", logger_mod);

    const run_crun_test = b.addRunArtifact(crun_test);
    
    // Crun integration test
    const crun_integration_test = b.addTest(.{
        .root_source_file = b.path("tests/crun_integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    crun_integration_test.root_module.addImport("oci", oci_mod);
    crun_integration_test.root_module.addImport("types", types_mod);
    crun_integration_test.root_module.addImport("error", error_mod);
    crun_integration_test.root_module.addImport("logger", logger_mod);

    const run_crun_integration_test = b.addRunArtifact(crun_integration_test);
    
    // Performance module test
    const performance_test = b.addTest(.{
        .root_source_file = b.path("tests/performance_simple_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    performance_test.root_module.addImport("performance", performance_mod);
    performance_test.root_module.addImport("types", types_mod);
    performance_test.root_module.addImport("logger", logger_mod);

    const run_performance_test = b.addRunArtifact(performance_test);
    
    // Edge cases test
    const edge_cases_test = b.addTest(.{
        .root_source_file = b.path("tests/edge_cases_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    edge_cases_test.root_module.addImport("types", types_mod);
    edge_cases_test.root_module.addImport("error", error_mod);
    edge_cases_test.root_module.addImport("logger", logger_mod);
    edge_cases_test.root_module.addImport("config", config_mod);
    edge_cases_test.root_module.addImport("oci", oci_mod);

    const run_edge_cases_test = b.addRunArtifact(edge_cases_test);
    
    // Container lifecycle integration test
    const container_lifecycle_test = b.addTest(.{
        .root_source_file = b.path("tests/integration/container_lifecycle_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    container_lifecycle_test.root_module.addImport("types", types_mod);
    container_lifecycle_test.root_module.addImport("error", error_mod);
    container_lifecycle_test.root_module.addImport("logger", logger_mod);
    container_lifecycle_test.root_module.addImport("config", config_mod);
    container_lifecycle_test.root_module.addImport("oci", oci_mod);

    const run_container_lifecycle_test = b.addRunArtifact(container_lifecycle_test);
    
    // Property-based tests
    const property_based_test = b.addTest(.{
        .root_source_file = b.path("tests/property_based_tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    property_based_test.root_module.addImport("types", types_mod);
    property_based_test.root_module.addImport("error", error_mod);
    property_based_test.root_module.addImport("logger", logger_mod);
    property_based_test.root_module.addImport("config", config_mod);
    property_based_test.root_module.addImport("test_utilities", test_utilities_mod);

    const run_property_based_test = b.addRunArtifact(property_based_test);
    
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_config_test.step);
    test_step.dependOn(&run_crun_test.step);
    test_step.dependOn(&run_crun_integration_test.step);
    test_step.dependOn(&run_performance_test.step);
    test_step.dependOn(&run_edge_cases_test.step);
    test_step.dependOn(&run_container_lifecycle_test.step);
    test_step.dependOn(&run_property_based_test.step);
    
    // Separate step for crun integration test
    const crun_integration_step = b.step("crun_integration", "Run crun integration tests");
    crun_integration_step.dependOn(&run_crun_integration_test.step);
}
