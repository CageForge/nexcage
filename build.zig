const std = @import("std");

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

    const runtime_service_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/grpc/runtime_service.zig" },
        .imports = &.{
            .{ .name = "types", .module = types_module },
            .{ .name = "logger", .module = logger_module },
            .{ .name = "error", .module = error_module },
            .{ .name = "config", .module = config_module },
            .{ .name = "proxmox", .module = proxmox_module },
            .{ .name = "cri", .module = cri_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(.{ .cwd_relative = "include" });
    exe.addIncludePath(.{ .cwd_relative = "src/grpc/proto" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/google" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/grpc++" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include/google" });

    exe.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.pb.cc" },
        .flags = &[_][]const u8{
            "-std=c++14",
            "-DPROTOBUF_USE_DLLS",
            "-DNOMINMAX",
        },
    });
    exe.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.grpc.pb.cc" },
        .flags = &[_][]const u8{
            "-std=c++14",
            "-DPROTOBUF_USE_DLLS",
            "-DNOMINMAX",
        },
    });

    exe.root_module.addImport("types", types_module);
    exe.root_module.addImport("logger", logger_module);
    exe.root_module.addImport("error", error_module);
    exe.root_module.addImport("config", config_module);
    exe.root_module.addImport("proxmox", proxmox_module);
    exe.root_module.addImport("runtime_service", runtime_service_module);

    exe.linkSystemLibrary("grpc");
    exe.linkSystemLibrary("grpc++");
    exe.linkSystemLibrary("gpr");
    exe.linkSystemLibrary("protobuf");
    exe.linkSystemLibrary("absl_strings");
    exe.linkSystemLibrary("absl_str_format_internal");
    exe.linkSystemLibrary("absl_cord");
    exe.linkSystemLibrary("absl_bad_optional_access");
    exe.linkSystemLibrary("absl_cordz_info");
    exe.linkSystemLibrary("absl_cord_internal");
    exe.linkSystemLibrary("absl_cordz_functions");
    exe.linkSystemLibrary("absl_exponential_biased");
    exe.linkSystemLibrary("absl_cordz_handle");
    exe.linkSystemLibrary("absl_raw_hash_set");
    exe.linkSystemLibrary("absl_hashtablez_sampler");
    exe.linkSystemLibrary("absl_synchronization");
    exe.linkSystemLibrary("absl_stacktrace");
    exe.linkSystemLibrary("absl_symbolize");
    exe.linkSystemLibrary("absl_malloc_internal");
    exe.linkSystemLibrary("absl_debugging_internal");
    exe.linkSystemLibrary("absl_demangle_internal");
    exe.linkSystemLibrary("absl_time");
    exe.linkSystemLibrary("absl_civil_time");
    exe.linkSystemLibrary("absl_time_zone");
    exe.linkSystemLibrary("absl_bad_variant_access");
    exe.linkSystemLibrary("absl_base");
    exe.linkSystemLibrary("absl_spinlock_wait");
    exe.linkSystemLibrary("absl_int128");
    exe.linkSystemLibrary("absl_throw_delegate");
    exe.linkSystemLibrary("absl_raw_logging_internal");
    exe.linkSystemLibrary("absl_log_severity");
    exe.linkLibCpp();

    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });

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

    unit_tests.addIncludePath(.{ .cwd_relative = "include" });
    unit_tests.addIncludePath(.{ .cwd_relative = "src/grpc/proto" });
    unit_tests.addIncludePath(.{ .cwd_relative = "/usr/include" });
    unit_tests.addIncludePath(.{ .cwd_relative = "/usr/include/google" });
    unit_tests.addIncludePath(.{ .cwd_relative = "/usr/include/grpc++" });
    unit_tests.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    unit_tests.addIncludePath(.{ .cwd_relative = "/usr/local/include/google" });

    unit_tests.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.pb.cc" },
        .flags = &[_][]const u8{"-std=c++14"},
    });
    unit_tests.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service.grpc.pb.cc" },
        .flags = &[_][]const u8{"-std=c++14"},
    });

    unit_tests.root_module.addImport("types", types_module);
    unit_tests.root_module.addImport("logger", logger_module);
    unit_tests.root_module.addImport("error", error_module);
    unit_tests.root_module.addImport("config", config_module);
    unit_tests.root_module.addImport("proxmox", proxmox_module);
    unit_tests.root_module.addImport("runtime_service", runtime_service_module);

    unit_tests.linkSystemLibrary("grpc");
    unit_tests.linkSystemLibrary("protobuf");
    unit_tests.linkSystemLibrary("grpc++");
    unit_tests.linkLibCpp();

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    const test_lxc = b.addExecutable(.{
        .name = "test-lxc",
        .root_source_file = .{ .cwd_relative = "tests/test_lxc.zig" },
        .target = target,
        .optimize = optimize,
    });

    test_lxc.root_module.addImport("types", types_module);
    test_lxc.root_module.addImport("logger", logger_module);
    test_lxc.root_module.addImport("error", error_module);
    test_lxc.root_module.addImport("config", config_module);
    test_lxc.root_module.addImport("proxmox", proxmox_module);
    test_lxc.root_module.addImport("runtime_service", runtime_service_module);

    test_lxc.linkSystemLibrary("grpc");
    test_lxc.linkSystemLibrary("protobuf");

    const test_lxc_run = b.addRunArtifact(test_lxc);
    const test_lxc_step = b.step("test-lxc", "Run LXC test");
    test_lxc_step.dependOn(&test_lxc_run.step);
}

