const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf = b.addExecutable(.{
        .root_source_file = .{ .cwd_relative = "protobuf.zig" },
        .target = target,
        .optimize = optimize,
    });

    const protoc_gen_zig = b.addExecutable(.{
        .root_source_file = .{ .cwd_relative = "protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });

    const protoc_gen_grpc_zig = b.addExecutable(.{
        .root_source_file = .{ .cwd_relative = "protoc-gen-grpc-zig.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_protoc_gen_zig = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "test_protoc_gen_zig.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_protoc_gen_grpc_zig = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "test_protoc_gen_grpc_zig.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_protobuf_tests = b.addRunArtifact(test_protoc_gen_zig);
    const run_grpc_tests = b.addRunArtifact(test_protoc_gen_grpc_zig);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_protobuf_tests.step);
    test_step.dependOn(&run_grpc_tests.step);
}
