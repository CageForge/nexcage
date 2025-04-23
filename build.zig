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
    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "src/grpc/proto" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/grpc" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/google/protobuf-c" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/lib/gcc/x86_64-linux-gnu/12/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/x86_64-linux-gnu" });
   
    // Add library paths
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/gcc/x86_64-linux-gnu/12" });

    exe.linkLibC();
    
    // C flags
    const c_flags = [_][]const u8{
        "-fPIC",
        "-DNDEBUG",
        "-D_GNU_SOURCE",
        "-DGRPC_POSIX_FORK_ALLOW_PTHREAD_ATFORK=1",
    };


    exe.addCSourceFiles(.{
        .files = &.{
            "src/grpc/proto/runtime_service-c.h",
        },
        .flags = &c_flags,
    });
    
    exe.addCSourceFiles(.{
        .files = &.{
            "src/grpc/proto/runtime_service.pb-c.c",
        },
        .flags = &c_flags,
    });

    exe.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/proto/runtime_service-c.c" },
        .flags = &c_flags,
    });

    exe.addCSourceFile(.{
        .file = .{ .cwd_relative = "src/grpc/server.c" },
        .flags = &c_flags,
    });

    // Link system libraries
    const system_libs = [_][]const u8{
        "protobuf-c",
        "grpc",
        "gpr",
        "upb",
        "address_sorting",
        "cares",
        "ssl",
        "crypto",
        "atomic",
        "pthread",
        "dl",
        "rt",
        "z",
        "grpc_unsecure",
    };

    for (system_libs) |lib| {
        exe.linkSystemLibrary(lib);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Створюємо кастомну команду для генерації протоколів
    const proto_gen = b.addSystemCommand(&[_][]const u8{
        "protoc",
        "--c_out=src/grpc/proto",
        "--plugin=protoc-gen-c=/usr/bin/protoc-gen-c",
        "proto/oci_runtime.proto",
    });

    const grpc_gen = b.addSystemCommand(&[_][]const u8{
        "protoc",
        "--grpc-c_out=src/grpc/proto",
        "--plugin=protoc-gen-grpc-c=/usr/bin/grpc_c_plugin",
        "proto/oci_runtime.proto",
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

    // OCI runtime
    const oci_mod = b.addModule("oci", .{
        .root_source_file = b.path("src/oci/runtime.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "pod", .module = pod_mod },
        },
    });

    // gRPC сервіс
    const grpc_mod = b.addModule("grpc", .{
        .root_source_file = b.path("src/grpc/oci_runtime.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "oci", .module = oci_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Додаємо залежність від генерації протоколів
    exe.step.dependOn(&proto_gen.step);
    exe.step.dependOn(&grpc_gen.step);

    // Додаємо залежності
    exe.root_module.addImport("types", types_mod);
    exe.root_module.addImport("error", error_mod);
    exe.root_module.addImport("logger", logger_mod);
    exe.root_module.addImport("network", network_mod);
    exe.root_module.addImport("pod", pod_mod);
    exe.root_module.addImport("proxmox", proxmox_mod);
    exe.root_module.addImport("oci", oci_mod);
    exe.root_module.addImport("grpc", grpc_mod);

    // Додаємо згенеровані файли до компіляції
    const c_flags = [_][]const u8{
        "-fPIC",
        "-DNDEBUG",
        "-D_GNU_SOURCE",
        "-DGRPC_POSIX_FORK_ALLOW_PTHREAD_ATFORK=1",
    };

    exe.addCSourceFile(.{
        .file = b.path("src/grpc/proto/oci_runtime.pb-c.c"),
        .flags = &c_flags,
    });
    exe.addCSourceFile(.{
        .file = b.path("src/grpc/proto/oci_runtime.grpc-c.c"),
        .flags = &c_flags,
    });

    // Додаємо шляхи для включення
    exe.addIncludePath(.{ .cwd_relative = "src/grpc/proto" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/grpc" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/google/protobuf-c" });

    // Лінкуємо необхідні бібліотеки
    exe.linkSystemLibrary("grpc");
    exe.linkSystemLibrary("protobuf-c");
    exe.linkSystemLibrary("c");
    exe.linkLibC();

    // Встановлюємо
    b.installArtifact(exe);

    // Команда для запуску
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Тести
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
