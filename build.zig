const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add protobuf dependency
    const protobuf_dep = b.dependency("protobuf", .{});
    const protobuf_module = protobuf_dep.module("protobuf");

    // Create modules without dependencies first
    const types_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/types.zig" },
    });

    // Create error module
    const error_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/error.zig" },
    });

    // Create logger module with its dependencies
    const logger_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/logger.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
        },
    });

    // Create config module with its dependencies
    const config_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/config.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
            .{ .name = "logger", .module = logger_module },
        },
    });

    // Create proxmox module with its dependencies
    const proxmox_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/proxmox.zig" },
        .imports = &.{
            .{ .name = "logger", .module = logger_module },
            .{ .name = "types", .module = types_module },
            .{ .name = "error", .module = error_module },
        },
    });

    // Create cri module with its dependencies
    const cri_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/cri.zig" },
        .imports = &.{
            .{ .name = "proxmox", .module = proxmox_module },
            .{ .name = "types", .module = types_module },
        },
    });

    // Create grpc_service module with its dependencies
    const grpc_service_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/grpc_service.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
        },
    });

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Create the test connection executable
    const test_exe = b.addExecutable(.{
        .name = "test-connection",
        .root_source_file = .{ .cwd_relative = "tests/test_connection.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Create the test workflow executable
    const test_workflow_exe = b.addExecutable(.{
        .name = "test-workflow",
        .root_source_file = .{ .cwd_relative = "tests/test_workflow.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Create protoc-gen modules with protobuf dependency
    const protoc_gen_zig = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .cwd_relative = ".github/workflows/protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    protoc_gen_zig.root_module.addImport("protobuf", protobuf_module);

    const protoc_gen_grpc_zig = b.addExecutable(.{
        .name = "protoc-gen-grpc-zig",
        .root_source_file = .{ .cwd_relative = ".github/workflows/protoc-gen-grpc-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    protoc_gen_grpc_zig.root_module.addImport("protobuf", protobuf_module);

    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "include" });
    test_exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    test_workflow_exe.addIncludePath(.{ .cwd_relative = "include" });
    test_workflow_exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });

    // Add library path
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    test_exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    test_workflow_exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });

    // Link with gRPC and protobuf libraries
    exe.linkSystemLibrary("grpc");
    exe.linkSystemLibrary("grpc++");
    exe.linkSystemLibrary("protobuf");
    exe.linkSystemLibrary("absl_throw_delegate");
    exe.linkSystemLibrary("absl_raw_logging_internal");
    exe.linkSystemLibrary("absl_raw_hash_set");
    exe.linkSystemLibrary("absl_hashtablez_sampler");
    exe.linkSystemLibrary("absl_hash");
    exe.linkSystemLibrary("absl_city");
    exe.linkSystemLibrary("absl_low_level_hash");
    exe.linkSystemLibrary("absl_random_distributions");
    exe.linkSystemLibrary("absl_random_seed_sequences");
    exe.linkSystemLibrary("absl_random_internal_pool_urbg");
    exe.linkSystemLibrary("absl_random_internal_randen");
    exe.linkSystemLibrary("absl_random_internal_randen_hwaes");
    exe.linkSystemLibrary("absl_random_internal_randen_hwaes_impl");
    exe.linkSystemLibrary("absl_random_internal_randen_slow");
    exe.linkSystemLibrary("absl_random_internal_platform");
    exe.linkSystemLibrary("absl_random_internal_seed_material");
    exe.linkSystemLibrary("absl_random_seed_gen_exception");
    exe.linkSystemLibrary("absl_statusor");
    exe.linkSystemLibrary("absl_status");
    exe.linkSystemLibrary("absl_cord");
    exe.linkSystemLibrary("absl_cordz_info");
    exe.linkSystemLibrary("absl_cord_internal");
    exe.linkSystemLibrary("absl_cordz_functions");
    exe.linkSystemLibrary("absl_exponential_biased");
    exe.linkSystemLibrary("absl_cordz_handle");
    exe.linkSystemLibrary("absl_bad_optional_access");
    exe.linkSystemLibrary("absl_strerror");
    exe.linkSystemLibrary("absl_str_format_internal");
    exe.linkSystemLibrary("absl_synchronization");
    exe.linkSystemLibrary("absl_graphcycles_internal");
    exe.linkSystemLibrary("absl_stacktrace");
    exe.linkSystemLibrary("absl_symbolize");
    exe.linkSystemLibrary("absl_debugging_internal");
    exe.linkSystemLibrary("absl_demangle_internal");
    exe.linkSystemLibrary("absl_malloc_internal");
    exe.linkSystemLibrary("absl_time");
    exe.linkSystemLibrary("absl_civil_time");
    exe.linkSystemLibrary("absl_strings");
    exe.linkSystemLibrary("absl_strings_internal");
    exe.linkSystemLibrary("absl_base");
    exe.linkSystemLibrary("absl_spinlock_wait");
    exe.linkSystemLibrary("absl_int128");
    exe.linkSystemLibrary("absl_time_zone");
    exe.linkSystemLibrary("absl_bad_variant_access");
    exe.linkSystemLibrary("absl_log_severity");
    exe.linkSystemLibrary("address_sorting");
    exe.linkSystemLibrary("re2");
    exe.linkSystemLibrary("upb");
    exe.linkSystemLibrary("cares");
    exe.linkSystemLibrary("z");
    exe.linkSystemLibrary("gpr");
    exe.linkSystemLibrary("ssl");
    exe.linkSystemLibrary("crypto");
    exe.linkSystemLibrary("atomic");

    // Only link against librt on Linux
    if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("rt");
    }

    // Add module dependencies to the executables
    exe.root_module.addImport("types", types_module);
    exe.root_module.addImport("logger", logger_module);
    exe.root_module.addImport("config", config_module);
    exe.root_module.addImport("proxmox", proxmox_module);
    exe.root_module.addImport("cri", cri_module);
    exe.root_module.addImport("grpc_service", grpc_service_module);
    exe.root_module.addImport("error", error_module);

    test_exe.root_module.addImport("types", types_module);
    test_exe.root_module.addImport("logger", logger_module);
    test_exe.root_module.addImport("proxmox", proxmox_module);

    test_workflow_exe.root_module.addImport("types", types_module);
    test_workflow_exe.root_module.addImport("logger", logger_module);

    // Install the executables
    b.installArtifact(exe);
    b.installArtifact(test_exe);
    b.installArtifact(test_workflow_exe);
    b.installArtifact(protoc_gen_zig);
    b.installArtifact(protoc_gen_grpc_zig);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_cmd = b.addRunArtifact(test_exe);
    test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test-connection", "Test Proxmox API connection");
    test_step.dependOn(&test_cmd.step);

    const test_workflow_cmd = b.addRunArtifact(test_workflow_exe);
    test_workflow_cmd.step.dependOn(b.getInstallStep());

    const test_workflow_step = b.step("test-workflow", "Test GitHub workflows locally");
    test_workflow_step.dependOn(&test_workflow_cmd.step);
}
