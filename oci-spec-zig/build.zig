const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const oci_spec_mod = b.addModule("oci_spec", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const generate_step = b.step("generate", "Regenerate Zig bindings from OCI schemas");
    generate_step.makeFn = struct {
        pub fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
            _ = step;
            std.debug.print("Schema generator not yet implemented. Place Zig implementation under tools/.\n", .{});
        }
    }.make;

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("oci_spec", oci_spec_mod);

    const unit_tests = b.addTest(.{
        .name = "oci-spec-tests",
        .root_module = test_module,
    });

    const test_step = b.step("test", "Run oci-spec-zig tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
}

