const std = @import("std");

fn addCommonConfig(artifact: *std.Build.Step.Compile) void {
    const include_paths = [_][]const u8{
        "src/grpc/proto",
        "/usr/local/include",
    };

    for (include_paths) |path| {
        artifact.addIncludePath(.{ .cwd_relative = path });
    }

    const C_FLAGS = [_][]const u8{
        "-DNOMINMAX",
        "-DABSL_ATTRIBUTE_LIFETIME_BOUND=",
        "-DABSL_ASSUME(x)=",
        "-DABSL_INTERNAL_CORDZ_ENABLED=0",
        "-DABSL_INTERNAL_CORD_INTERNAL_MAX_FLAT_SIZE=0x7FFF'FFFF",
        "-U linux",
        "-fPIC",
    };

    const CXX_FLAGS = [_][]const u8{
        "-std=c++14",
        "-DNOMINMAX",
        "-DABSL_ATTRIBUTE_LIFETIME_BOUND=",
        "-DABSL_ASSUME(x)=",
        "-DABSL_INTERNAL_CORDZ_ENABLED=0",
        "-DABSL_INTERNAL_CORD_INTERNAL_MAX_FLAT_SIZE=0x7FFF'FFFF",
        "-U linux",
        "-fPIC",
    };

    artifact.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.pb-c.c" },
        .flags = &C_FLAGS,
    });
    artifact.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.pb.cc" },
        .flags = &CXX_FLAGS,
    });
    artifact.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.grpc.pb.cc" },
        .flags = &CXX_FLAGS,
    });

    artifact.linkLibCpp();
    artifact.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    artifact.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
    artifact.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    artifact.addRPath(.{ .cwd_relative = "/usr/local/lib" });

    artifact.linkSystemLibrary("protobuf-c");
    artifact.linkSystemLibrary("protobuf");
    artifact.linkSystemLibrary("grpc++");
    artifact.linkSystemLibrary("grpc");
    artifact.linkSystemLibrary("gpr");
    artifact.linkSystemLibrary("z");
    artifact.linkSystemLibrary("pthread");
    artifact.linkSystemLibrary("dl");

    const absl_libs = [_][]const u8{
        "absl_strings",
        "absl_str_format_internal",
        "absl_cord",
        "absl_bad_optional_access",
        "absl_cordz_info",
        "absl_cord_internal",
        "absl_cordz_functions",
        "absl_exponential_biased",
        "absl_cordz_handle",
        "absl_raw_hash_set",
        "absl_hashtablez_sampler",
        "absl_synchronization",
        "absl_stacktrace",
        "absl_symbolize",
        "absl_malloc_internal",
        "absl_debugging_internal",
        "absl_demangle_internal",
        "absl_time",
        "absl_civil_time",
        "absl_time_zone",
        "absl_bad_variant_access",
        "absl_base",
        "absl_spinlock_wait",
        "absl_int128",
        "absl_throw_delegate",
        "absl_raw_logging_internal",
        "absl_log_severity",
        "absl_status",
        "absl_statusor",
        "absl_strerror",
    };

    for (absl_libs) |lib| {
        artifact.linkSystemLibrary(lib);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const types_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/types.zig" },
    });

    const logger_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/logger.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
        },
    });

    const error_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/error.zig" },
    });

    const config_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/config.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
            .{ .name = "logger", .module = logger_module },
        },
    });

    const proxmox_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/proxmox.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
            .{ .name = "logger", .module = logger_module },
            .{ .name = "error", .module = error_module },
        },
    });

    const cri_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/cri.zig" },
    });

    const oci_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/oci/mod.zig" },
    });

    const runtime_service_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/grpc/runtime_service.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
            .{ .name = "logger", .module = logger_module },
            .{ .name = "error", .module = error_module },
            .{ .name = "config", .module = config_module },
            .{ .name = "proxmox", .module = proxmox_module },
            .{ .name = "cri", .module = cri_module },
            .{ .name = "oci", .module = oci_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    addCommonConfig(exe);

    exe.root_module.addImport("types", types_module);
    exe.root_module.addImport("logger", logger_module);
    exe.root_module.addImport("error", error_module);
    exe.root_module.addImport("config", config_module);
    exe.root_module.addImport("proxmox", proxmox_module);
    exe.root_module.addImport("runtime_service", runtime_service_module);
    exe.root_module.addImport("oci", oci_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "tests/test_runtime_service.zig" },
        .target = target,
        .optimize = optimize,
    });

    addCommonConfig(unit_tests);

    unit_tests.root_module.addImport("types", types_module);
    unit_tests.root_module.addImport("logger", logger_module);
    unit_tests.root_module.addImport("error", error_module);
    unit_tests.root_module.addImport("config", config_module);
    unit_tests.root_module.addImport("proxmox", proxmox_module);
    unit_tests.root_module.addImport("runtime_service", runtime_service_module);
    unit_tests.root_module.addImport("oci", oci_module);

    unit_tests.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&unit_tests.step);
}

