const std = @import("std");
const Build = std.Build;
const fs = std.fs;

fn findIncludePath(paths: []const []const u8) ?[]const u8 {
    for (paths) |path| {
        if (fs.cwd().access(path, .{})) |_| {
            return path;
        } else |_| {
            continue;
        }
    }
    return null;
}

fn addCommonConfig(exe: *std.Build.Step.Compile) void {
    
    // Add standard C++ library paths
    exe.addIncludePath(.{ .cwd_relative = "/usr/lib/libccx/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/bits" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/ext" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/debug" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/limits" });

    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "src/grpc/proto" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/x86_64-linux-gnu/c++/12" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/google" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/backward" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/lib/gcc/x86_64-linux-gnu/12/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/x86_64-linux-gnu" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/grpc" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/grpc++" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/grpcpp" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/google/protobuf" });
   
    
    // Add library paths
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/gcc/x86_64-linux-gnu/12" });
    exe.linkLibC();
    exe.linkLibCpp();
    
    // C flags
    exe.addCSourceFile(.{
        .file = .{ .path = "src/grpc/proto/runtime_service.pb-c.c" },
        .flags = &[_][]const u8{
            "-fPIC",
            "-DNDEBUG",
            "-D_GNU_SOURCE",
            "-DGRPC_POSIX_FORK_ALLOW_PTHREAD_ATFORK=1",
        },
    });

    // C++ flags
    const cpp_flags = [_][]const u8{
        "-std=c++17",
        "-DNOMINMAX",
        "-fPIC",
        "-DNDEBUG",
        "-D_GNU_SOURCE",
        "-DUSE_ABSL_STATUSOR",
        "-DABSL_USES_STD_STRING_VIEW",
        "-DABSL_ATTRIBUTE_LIFETIME_BOUND=",
        "-DABSL_ASSUME(x)=__builtin_assume(x)",
        "-DABSL_INTERNAL_ASSUME(x)=__builtin_assume(x)",
        "-DABSL_PREDICT_TRUE(x)=__builtin_expect(!!(x), 1)",
        "-DABSL_PREDICT_FALSE(x)=__builtin_expect(!!(x), 0)",
        "-D__STDC_FORMAT_MACROS",
        "-D__STDC_CONSTANT_MACROS",
        "-D__STDC_LIMIT_MACROS",
        "-DGRPC_POSIX_FORK_ALLOW_PTHREAD_ATFORK=1",
        "-DPROTOBUF_NO_BUILTIN_ENDIAN",
        "-I/usr/lib/libccx/include",
        "-I/usr/include/c++/12",
        "-I/usr/include/x86_64-linux-gnu/c++/12",
        "-I/usr/include/c++/12/backward",
        "-I/usr/local/include",
        "-fexceptions",
        "-frtti",
    };

    //exe.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.pb-c.c" },
        .flags = c_flags,
    });

    // Add C++ source files
    exe.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.pb.cc" },
        .flags = cpp_flags,
    });
    exe.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.grpc.pb.cc" },
        .flags = cpp_flags,
    });

    // Link system libraries
    const system_libs = [_][]const u8{
        "protobuf",
        "grpc++",
        "grpc",
        "gpr",
        "upb",
        "address_sorting",
        "re2",
        "cares",
        "ssl",
        "crypto",
        "atomic",
        "pthread",
        "dl",
        "rt",
        "z",
    };

    for (system_libs) |lib| {
        exe.linkSystemLibrary(lib);
    }

    // Link Abseil libraries
    const absl_libs = [_][]const u8{
        "absl_base",
        "absl_throw_delegate",
        "absl_raw_logging_internal",
        "absl_log_severity",
        "absl_spinlock_wait",
        "absl_malloc_internal",
        "absl_time",
        "absl_civil_time",
        "absl_time_zone",
        "absl_strings",
        "absl_strings_internal",
        "absl_status",
        "absl_cord",
        "absl_str_format_internal",
        "absl_synchronization",
        "absl_stacktrace",
        "absl_symbolize",
        "absl_debugging_internal",
        "absl_demangle_internal",
        "absl_graphcycles_internal",
        "absl_hash",
        "absl_city",
        "absl_low_level_hash",
        "absl_raw_hash_set",
        "absl_hashtablez_sampler",
        "absl_exponential_biased",
        "absl_statusor",
        "absl_bad_optional_access",
        "absl_bad_variant_access",
    };

    for (absl_libs) |lib| {
        exe.linkSystemLibrary(lib);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    });

    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    // Network subsystem
    const network_mod = b.addModule("network", .{
        .root_source_file = b.path("src/network/manager.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Pod management
    const pod_mod = b.addModule("pod", .{
        .root_source_file = b.path("src/pod/manager.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "network", .module = network_mod },
            .{ .name = "config", .module = config_mod },
        },
    });

    // Proxmox integration
    const proxmox_mod = b.addModule("proxmox", .{
        .root_source_file = b.path("src/proxmox/api.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // OCI runtime
    const oci_mod = b.addModule("oci", .{
        .root_source_file = b.path("src/oci/runtime.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "pod", .module = pod_mod },
        },
    });

    // CRI implementation
    const cri_mod = b.addModule("cri", .{
        .root_source_file = b.path("src/cri/runtime/service.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "pod", .module = pod_mod },
            .{ .name = "oci", .module = oci_mod },
        },
    });

    // Runtime service
    const runtime_mod = b.addModule("runtime", .{
        .root_source_file = b.path("src/runtime/cri.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "pod", .module = pod_mod },
            .{ .name = "cri", .module = cri_mod },
        },
    });

    // gRPC service
    const grpc_mod = b.addModule("grpc", .{
        .root_source_file = b.path("src/grpc/server.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "runtime", .module = runtime_mod },
        },
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add all modules to executable
    exe.root_module.addImport("types", types_mod);  
    exe.root_module.addImport("error", error_mod);
    exe.root_module.addImport("logger", logger_mod);
    exe.root_module.addImport("config", config_mod);
    exe.root_module.addImport("network", network_mod);
    exe.root_module.addImport("pod", pod_mod);
    exe.root_module.addImport("proxmox", proxmox_mod);
    exe.root_module.addImport("oci", oci_mod);
    exe.root_module.addImport("cri", cri_mod);
    exe.root_module.addImport("runtime", runtime_mod);
    exe.root_module.addImport("grpc", grpc_mod);

    addCommonConfig(exe);
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run all tests");

    // Core tests
    const core_tests = b.addTest(.{
        .root_source_file = b.path("tests/core/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addCommonConfig(core_tests);
    core_tests.root_module.addImport("types", types_mod);
    core_tests.root_module.addImport("error", error_mod);
    core_tests.root_module.addImport("logger", logger_mod);
    core_tests.root_module.addImport("config", config_mod);
    const run_core_tests = b.addRunArtifact(core_tests);
    test_step.dependOn(&run_core_tests.step);

    // CRI tests
    const cri_tests = b.addTest(.{
        .root_source_file = b.path("tests/cri/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addCommonConfig(cri_tests);
    cri_tests.root_module.addImport("types", types_mod);
    cri_tests.root_module.addImport("error", error_mod);
    cri_tests.root_module.addImport("cri", cri_mod);
    const run_cri_tests = b.addRunArtifact(cri_tests);
    test_step.dependOn(&run_cri_tests.step);

    // Network tests
    const network_tests = b.addTest(.{
        .root_source_file = b.path("tests/network/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addCommonConfig(network_tests);
    network_tests.root_module.addImport("types", types_mod);
    network_tests.root_module.addImport("error", error_mod);
    network_tests.root_module.addImport("network", network_mod);
    const run_network_tests = b.addRunArtifact(network_tests);
    test_step.dependOn(&run_network_tests.step);

    // Pod tests
    const pod_tests = b.addTest(.{
        .root_source_file = b.path("tests/pod/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addCommonConfig(pod_tests);
    pod_tests.root_module.addImport("types", types_mod);
    pod_tests.root_module.addImport("error", error_mod);
    pod_tests.root_module.addImport("pod", pod_mod);
    const run_pod_tests = b.addRunArtifact(pod_tests);
    test_step.dependOn(&run_pod_tests.step);
}

