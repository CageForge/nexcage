const std = @import("std");
const Build = std.Build;
const fs = std.fs;

// Version information
const VERSION = "0.5.0";
const VERSION_MAJOR = 0;
const VERSION_MINOR = 5;
const VERSION_PATCH = 0;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add dependency for zig-json
    const zigJsonDep = b.dependency("zig-json", .{
        .target = target,
        .optimize = optimize,
    });

    // Core module
    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core/mod.zig"),
    });

    // Utils module
    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // Proxmox API module
    const proxmox_api_mod = b.addModule("proxmox-api", .{
        .root_source_file = b.path("src/integrations/proxmox-api/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // Backends module
    const backends_mod = b.addModule("backends", .{
        .root_source_file = b.path("src/backends/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "proxmox-api", .module = proxmox_api_mod },
            .{ .name = "utils", .module = utils_mod },
        },
    });

    // CLI module
    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/cli/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "backends", .module = backends_mod },
            .{ .name = "utils", .module = utils_mod },
        },
    });

    // Integrations module
    const integrations_mod = b.addModule("integrations", .{
        .root_source_file = b.path("src/integrations/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // OCI module
    const oci_mod = b.addModule("oci", .{
        .root_source_file = b.path("src/oci/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // Create crun library (empty stub)
    const crun_lib = b.addStaticLibrary(.{
        .name = "crun",
        .target = target,
        .optimize = optimize,
    });

    // Add a simple C file to make the library valid
    crun_lib.addCSourceFiles(.{
        .files = &.{"src/stubs/stub.c"},
        .flags = &.{
            "-std=c99",
            "-Wall",
            "-Wextra",
            "-O3",
        },
    });

    // Create BFC library (empty stub)
    const bfc_lib = b.addStaticLibrary(.{
        .name = "bfc",
        .target = target,
        .optimize = optimize,
    });

    // Add a simple C file to make the library valid
    bfc_lib.addCSourceFiles(.{
        .files = &.{"src/stubs/stub.c"},
        .flags = &.{
            "-std=c99",
            "-Wall",
            "-Wextra",
            "-O3",
        },
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "proxmox-lxcri",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link system libraries
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("cap");
    exe.linkSystemLibrary("seccomp");
    exe.linkSystemLibrary("yajl");

    // Link crun and bfc libraries
    exe.linkLibrary(crun_lib);
    exe.linkLibrary(bfc_lib);

    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src" });
    exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src/libcrun" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/src/libcrun" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });

    // Add module dependencies
    exe.root_module.addImport("core", core_mod);
    exe.root_module.addImport("cli", cli_mod);
    exe.root_module.addImport("backends", backends_mod);
    exe.root_module.addImport("integrations", integrations_mod);
    exe.root_module.addImport("utils", utils_mod);
    exe.root_module.addImport("oci", oci_mod);
    exe.root_module.addImport("zig_json", zigJsonDep.module("zig-json"));

    // Install the executable
    b.installArtifact(exe);

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Add test step
    const test_exe = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_exe.linkSystemLibrary("c");
    test_exe.linkSystemLibrary("cap");
    test_exe.linkSystemLibrary("seccomp");
    test_exe.linkSystemLibrary("yajl");
    test_exe.linkLibrary(crun_lib);
    test_exe.linkLibrary(bfc_lib);

    test_exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src/libcrun" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/src/libcrun" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });

    test_exe.root_module.addImport("core", core_mod);
    test_exe.root_module.addImport("cli", cli_mod);
    test_exe.root_module.addImport("backends", backends_mod);
    test_exe.root_module.addImport("integrations", integrations_mod);
    test_exe.root_module.addImport("utils", utils_mod);
    test_exe.root_module.addImport("oci", oci_mod);
    test_exe.root_module.addImport("zig_json", zigJsonDep.module("zig-json"));

    const run_test = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}