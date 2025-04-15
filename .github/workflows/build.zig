const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "protobuf/module.zig" },
    });

    const zig_plugin = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .cwd_relative = "protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    zig_plugin.root_module.addImport("protobuf", protobuf_module);
    b.installArtifact(zig_plugin);

    const grpc_plugin = b.addExecutable(.{
        .name = "protoc-gen-grpc-zig",
        .root_source_file = .{ .cwd_relative = "protoc-gen-grpc-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    grpc_plugin.root_module.addImport("protobuf", protobuf_module);
    b.installArtifact(grpc_plugin);
}
