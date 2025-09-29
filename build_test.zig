const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core/mod.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "test_parse_config_only",
        .root_source_file = b.path("test_parse_config_only.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("core", core_mod);

    b.installArtifact(exe);
}
