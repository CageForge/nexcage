const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Legacy executable (deprecated)
    const exe = b.addExecutable(.{
        .name = "nexcage-legacy",
        .root_source_file = b.path("src/main_legacy.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add system libraries
    exe.linkSystemLibrary("c");

    // Install
    b.installArtifact(exe);
}
