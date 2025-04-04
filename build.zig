const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies
    exe.addModule("cri", b.createModule(.{
        .source_file = .{ .path = "src/cri.zig" },
        .dependencies = &.{},
    }));

    exe.addModule("proxmox", b.createModule(.{
        .source_file = .{ .path = "src/proxmox.zig" },
        .dependencies = &.{},
    }));

    // Add system libraries
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("grpc");
    exe.linkSystemLibrary("protobuf");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
