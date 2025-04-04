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
