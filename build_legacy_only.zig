const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a default, which means the user must explicitly select an optimization
    // mode.
    const optimize = b.standardOptimizeOption(.{});

    // Version information
    _ = "0.4.0";
    _ = 0;
    _ = 4;
    _ = 0;

    // BFC library
    const bfc_lib = b.addStaticLibrary(.{
        .name = "bfc",
        .target = target,
        .optimize = optimize,
    });

    bfc_lib.addCSourceFiles(.{
        .files = &.{
            "deps/bfc/src/lib/bfc_compress.c",
            "deps/bfc/src/lib/bfc_crc32c.c",
            "deps/bfc/src/lib/bfc_encrypt.c",
            "deps/bfc/src/lib/bfc_format.c",
            "deps/bfc/src/lib/bfc_iter.c",
            "deps/bfc/src/lib/bfc_os.c",
            "deps/bfc/src/lib/bfc_reader.c",
            "deps/bfc/src/lib/bfc_util.c",
            "deps/bfc/src/lib/bfc_writer.c",
        },
        .flags = &.{
            "-std=c99",
            "-Wall",
            "-Wextra",
            "-O3",
            "-DNDEBUG",
        },
    });

    bfc_lib.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });
    bfc_lib.linkLibC();

    // Install BFC library
    b.installArtifact(bfc_lib);

    // Crun library
    const crun_lib = b.addStaticLibrary(.{
        .name = "crun",
        .target = target,
        .optimize = optimize,
    });

    // Add a simple C file to make the library valid
    crun_lib.addCSourceFiles(.{
        .files = &.{
            "legacy/src/crun/crun_stub.c",
        },
        .flags = &.{
            "-std=c99",
            "-Wall",
            "-Wextra",
            "-O3",
            "-DNDEBUG",
        },
    });

    crun_lib.linkSystemLibrary("c");

    // Install crun library
    b.installArtifact(crun_lib);

    // Legacy modules
    const types_mod = b.addModule("types", .{
        .root_source_file = b.path("legacy/src/common/types.zig"),
    });

    const error_mod = b.addModule("error", .{
        .root_source_file = b.path("legacy/src/common/error.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const logger_mod = b.addModule("logger", .{
        .root_source_file = b.path("legacy/src/common/logger.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
        },
    });

    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("legacy/src/common/config.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    // Add zig-json dependency
    const zigJsonDep = b.dependency("zig-json", .{});
    
    const json_mod = b.addModule("json_helpers", .{
        .root_source_file = b.path("legacy/src/common/custom_json_parser.zig"),
        .imports = &.{
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
        },
    });

    const zfs_mod = b.addModule("zfs", .{
        .root_source_file = b.path("legacy/src/zfs/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const network_mod = b.addModule("network", .{
        .root_source_file = b.path("legacy/src/network/network.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const proxmox_mod = b.addModule("proxmox", .{
        .root_source_file = b.path("legacy/src/proxmox/proxmox.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const image_mod = b.addModule("image", .{
        .root_source_file = b.path("legacy/src/oci/image/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
        },
    });

    const raw_mod = b.addModule("raw", .{
        .root_source_file = b.path("legacy/src/raw/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const bfc_mod = b.addModule("bfc", .{
        .root_source_file = b.path("legacy/src/bfc/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const crun_mod = b.addModule("crun", .{
        .root_source_file = b.path("legacy/src/crun/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const oci_mod = b.addModule("oci", .{
        .root_source_file = b.path("legacy/src/oci/mod.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "error", .module = error_mod },
            .{ .name = "logger", .module = logger_mod },
            .{ .name = "proxmox", .module = proxmox_mod },
            .{ .name = "json_helpers", .module = json_mod },
            .{ .name = "zig_json", .module = zigJsonDep.module("zig-json") },
            .{ .name = "zfs", .module = zfs_mod },
            .{ .name = "network", .module = network_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "image", .module = image_mod },
            .{ .name = "raw", .module = raw_mod },
            .{ .name = "bfc", .module = bfc_mod },
            .{ .name = "crun", .module = crun_mod },
        },
    });

    // Legacy executable
    const exe_legacy = b.addExecutable(.{
        .name = "proxmox-lxcri-legacy",
        .root_source_file = b.path("legacy/src/main_legacy.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add libraries
    exe_legacy.linkLibrary(bfc_lib);
    exe_legacy.linkLibrary(crun_lib);

    // Link system libraries
    exe_legacy.linkSystemLibrary("cap");
    exe_legacy.linkSystemLibrary("seccomp");
    exe_legacy.linkSystemLibrary("yajl");
    exe_legacy.linkSystemLibrary("c");

    // Add include paths
    exe_legacy.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "deps/crun/src/libcrun" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    exe_legacy.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });

    // Add modules
    exe_legacy.root_module.addImport("types", types_mod);
    exe_legacy.root_module.addImport("error", error_mod);
    exe_legacy.root_module.addImport("config", config_mod);
    exe_legacy.root_module.addImport("logger", logger_mod);
    exe_legacy.root_module.addImport("json_helpers", json_mod);
    exe_legacy.root_module.addImport("zig_json", zigJsonDep.module("zig-json"));
    exe_legacy.root_module.addImport("zfs", zfs_mod);
    exe_legacy.root_module.addImport("network", network_mod);
    exe_legacy.root_module.addImport("proxmox", proxmox_mod);
    exe_legacy.root_module.addImport("oci", oci_mod);
    exe_legacy.root_module.addImport("image", image_mod);
    exe_legacy.root_module.addImport("raw", raw_mod);
    exe_legacy.root_module.addImport("bfc", bfc_mod);
    exe_legacy.root_module.addImport("crun", crun_mod);

    // Install
    b.installArtifact(exe_legacy);

    // Run step
    const run_cmd = b.addRunArtifact(exe_legacy);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("legacy/src/main_legacy.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
