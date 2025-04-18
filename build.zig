const std = @import("std");
const Build = std.Build;

fn addCommonConfig(exe: *std.Build.Step.Compile) void {
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
    
    // Add standard C++ library paths
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/bits" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/ext" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/debug" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/c++/12/limits" });

    // Add library paths
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/gcc/x86_64-linux-gnu/12" });
    exe.linkLibC();
    exe.linkLibCpp();
    
    // Add C flags
    const c_flags = &[_][]const u8{
        "-fPIC",
        "-DNDEBUG",
        "-D_GNU_SOURCE",
        "-DGRPC_POSIX_FORK_ALLOW_PTHREAD_ATFORK=1",
    };

    // C++ flags
    const cpp_flags = &[_][]const u8{
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
        "-I/usr/include/c++/12",
        "-I/usr/include/x86_64-linux-gnu/c++/12",
        "-I/usr/include/c++/12/backward",
        "-I/usr/local/include",
        "-fexceptions",
        "-frtti",
    };

    // Add C source files
    exe.addCSourceFile(.{
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
    exe.linkSystemLibrary("protobuf");
    exe.linkSystemLibrary("grpc++");
    exe.linkSystemLibrary("grpc");
    exe.linkSystemLibrary("gpr");
    exe.linkSystemLibrary("upb");
    exe.linkSystemLibrary("address_sorting");
    exe.linkSystemLibrary("re2");
    exe.linkSystemLibrary("cares");
    exe.linkSystemLibrary("ssl");
    exe.linkSystemLibrary("crypto");
    exe.linkSystemLibrary("atomic");
    exe.linkSystemLibrary("pthread");
    exe.linkSystemLibrary("dl");
    exe.linkSystemLibrary("rt");
    exe.linkSystemLibrary("z");

    // Link Abseil libraries
    exe.linkSystemLibrary("absl_base");
    exe.linkSystemLibrary("absl_throw_delegate");
    exe.linkSystemLibrary("absl_raw_logging_internal");
    exe.linkSystemLibrary("absl_log_severity");
    exe.linkSystemLibrary("absl_spinlock_wait");
    exe.linkSystemLibrary("absl_malloc_internal");
    exe.linkSystemLibrary("absl_time");
    exe.linkSystemLibrary("absl_civil_time");
    exe.linkSystemLibrary("absl_time_zone");
    exe.linkSystemLibrary("absl_strings");
    exe.linkSystemLibrary("absl_strings_internal");
    exe.linkSystemLibrary("absl_status");
    exe.linkSystemLibrary("absl_cord");
    exe.linkSystemLibrary("absl_str_format_internal");
    exe.linkSystemLibrary("absl_synchronization");
    exe.linkSystemLibrary("absl_stacktrace");
    exe.linkSystemLibrary("absl_symbolize");
    exe.linkSystemLibrary("absl_debugging_internal");
    exe.linkSystemLibrary("absl_demangle_internal");
    exe.linkSystemLibrary("absl_graphcycles_internal");
    exe.linkSystemLibrary("absl_hash");
    exe.linkSystemLibrary("absl_city");
    exe.linkSystemLibrary("absl_low_level_hash");
    exe.linkSystemLibrary("absl_raw_hash_set");
    exe.linkSystemLibrary("absl_hashtablez_sampler");
    exe.linkSystemLibrary("absl_exponential_biased");
    exe.linkSystemLibrary("absl_statusor");
    exe.linkSystemLibrary("absl_bad_optional_access");
    exe.linkSystemLibrary("absl_bad_variant_access");
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
            .{ .name = "config", .module = config_module },
        },
    });

    const cri_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/cri.zig" },
    });

    const oci_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/oci/mod.zig" },
    });

    const crio_module = b.addModule("crio", .{
        .root_source_file = .{ .cwd_relative = "src/crio/mod.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
            .{ .name = "oci", .module = oci_module },
        },
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

    const test_step = b.step("test", "Run library tests");
    const main_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "tests/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    main_tests.root_module.addImport("types", types_module);
    main_tests.root_module.addImport("logger", logger_module);
    main_tests.root_module.addImport("error", error_module);
    main_tests.root_module.addImport("config", config_module);
    main_tests.root_module.addImport("proxmox", proxmox_module);
    main_tests.root_module.addImport("oci", oci_module);
    main_tests.root_module.addImport("crio", crio_module);

    addCommonConfig(main_tests);
    main_tests.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    
    const run_tests = b.addRunArtifact(main_tests);
    test_step.dependOn(&run_tests.step);
}

