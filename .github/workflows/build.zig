const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Отримуємо залежність protobuf
    const protobuf_dep = b.dependency("protobuf", .{});
    const protobuf_module = protobuf_dep.module("protobuf");

    // Створюємо виконуваний файл protoc-gen-zig
    const zig_plugin = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .path = "protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    zig_plugin.root_module.addImport("protobuf", protobuf_module);
    b.installArtifact(zig_plugin);

    // Створюємо виконуваний файл protoc-gen-grpc-zig
    const grpc_plugin = b.addExecutable(.{
        .name = "protoc-gen-grpc-zig",
        .root_source_file = .{ .path = "protoc-gen-grpc-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    grpc_plugin.root_module.addImport("protobuf", protobuf_module);
    b.installArtifact(grpc_plugin);
}
