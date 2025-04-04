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
    const cri_module = b.addModule("cri", .{
        .root_source_file = .{ .cwd_relative = "src/cri.zig" },
        .imports = &.{},
    });

    const proxmox_module = b.addModule("proxmox", .{
        .root_source_file = .{ .cwd_relative = "src/proxmox_new.zig" },
        .imports = &.{},
    });

    const fix_module = b.addModule("fix", .{
        .root_source_file = .{ .cwd_relative = "src/fix.zig" },
        .imports = &.{},
    });

    const proxmox_fix_module = b.addModule("proxmox_fix", .{
        .root_source_file = .{ .cwd_relative = "src/proxmox_fix.zig" },
        .imports = &.{},
    });

    exe.root_module.addImport("cri", cri_module);
    exe.root_module.addImport("proxmox", proxmox_module);
    exe.root_module.addImport("fix", fix_module);
    exe.root_module.addImport("proxmox_fix", proxmox_fix_module);

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
