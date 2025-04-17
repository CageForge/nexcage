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

    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("types", types_module);
    exe.root_module.addImport("logger", logger_module);
    exe.root_module.addImport("error", error_module);
    exe.root_module.addImport("config", config_module);
    exe.root_module.addImport("proxmox", proxmox_module);

    exe.linkSystemLibrary("grpc");
    exe.linkSystemLibrary("protobuf");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

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

    test_lxc.linkSystemLibrary("grpc");
    test_lxc.linkSystemLibrary("protobuf");

    const test_lxc_run = b.addRunArtifact(test_lxc);
    const test_lxc_step = b.step("test-lxc", "Run LXC test");
    test_lxc_step.dependOn(&test_lxc_run.step);
}

