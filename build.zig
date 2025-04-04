const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create modules without dependencies first
    const proxmox_module = b.addModule("proxmox", .{
        .root_source_file = .{ .cwd_relative = "src/proxmox_new.zig" },
    });

    const proxmox_fix_module = b.addModule("proxmox_fix", .{
        .root_source_file = .{ .cwd_relative = "src/proxmox_fix.zig" },
    });

    const config_module = b.addModule("config", .{
        .root_source_file = .{ .cwd_relative = "src/config.zig" },
    });

    const types_module = b.addModule("types", .{
        .root_source_file = .{ .cwd_relative = "src/types.zig" },
    });

    // Create logger module with config dependency
    const logger_module = b.addModule("logger", .{
        .root_source_file = .{ .cwd_relative = "src/logger.zig" },
        .imports = &.{
            .{ .name = "config", .module = config_module },
        },
    });

    // Create cri module with its dependencies
    const cri_module = b.addModule("cri", .{
        .root_source_file = .{ .cwd_relative = "src/cri.zig" },
        .imports = &.{
            .{ .name = "proxmox", .module = proxmox_module },
            .{ .name = "types", .module = types_module },
            .{ .name = "fix", .module = proxmox_fix_module },
        },
    });

    // Create grpc_service module with its dependencies
    const grpc_service_module = b.addModule("grpc_service", .{
        .root_source_file = .{ .cwd_relative = "src/grpc_service.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
        },
    });

    // Create the executable
    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });

    // Add library path
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });

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

    // Add all modules as dependencies
    exe.root_module.addImport("proxmox", proxmox_module);
    exe.root_module.addImport("proxmox_fix", proxmox_fix_module);
    exe.root_module.addImport("config", config_module);
    exe.root_module.addImport("logger", logger_module);
    exe.root_module.addImport("cri", cri_module);
    exe.root_module.addImport("grpc_service", grpc_service_module);
    exe.root_module.addImport("types", types_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
