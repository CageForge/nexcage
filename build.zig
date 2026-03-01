const std = @import("std");
const Build = std.Build;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Read VERSION file
    const version_bytes = std.fs.cwd().readFileAlloc(b.allocator, "VERSION", 64) catch "0.0.0";
    const app_version = std.mem.trim(u8, version_bytes, " \n\r\t");

    const core_build_options = b.addOptions();
    core_build_options.addOption([]const u8, "app_version", app_version);

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_zfs", true);
    build_options.addOption(bool, "enable_proxmox_lxc", true);

    const build_options_mod = build_options.createModule();

    // Modules
    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core/mod.zig"),
    });
    core_mod.addOptions("core_build_options", core_build_options);

    const oci_spec_mod = b.addModule("oci_spec", .{
        .root_source_file = b.path("deps/oci-spec-zig/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "oci_spec", .module = oci_spec_mod },
        },
    });

    const backends_mod = b.addModule("backends", .{
        .root_source_file = b.path("src/backends/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "oci_spec", .module = oci_spec_mod },
        },
    });
    backends_mod.addImport("build_options", build_options_mod);

    const config_integration_mod = b.addModule("config_integration", .{
        .root_source_file = b.path("src/core/enhanced_config.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/cli/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "backends", .module = backends_mod },
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "config_integration", .module = config_integration_mod },
        },
    });

    const integrations_mod = b.addModule("integrations", .{
        .root_source_file = b.path("src/integrations/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "backends", .module = backends_mod },
        },
    });
    integrations_mod.addImport("build_options", build_options_mod);

    // Main executable
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "nexcage",
        .root_module = main_mod,
    });

    exe.linkSystemLibrary("c");
    exe.root_module.addImport("core", core_mod);
    exe.root_module.addImport("cli", cli_mod);
    exe.root_module.addImport("backends", backends_mod);
    exe.root_module.addImport("integrations", integrations_mod);
    exe.root_module.addImport("utils", utils_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const test_exe = b.addTest(.{
        .name = "test",
        .root_module = main_mod,
    });
    test_exe.linkSystemLibrary("c");
    test_exe.root_module.addImport("core", core_mod);
    test_exe.root_module.addImport("cli", cli_mod);
    test_exe.root_module.addImport("backends", backends_mod);
    test_exe.root_module.addImport("integrations", integrations_mod);
    test_exe.root_module.addImport("utils", utils_mod);

    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}
