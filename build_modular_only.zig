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
            "src/crun/crun_stub.c",
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

    // Modular architecture modules
    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core/mod.zig"),
    });

    const backends_mod = b.addModule("backends", .{
        .root_source_file = b.path("src/backends/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/cli/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "backends", .module = backends_mod },
        },
    });

    const integrations_mod = b.addModule("integrations", .{
        .root_source_file = b.path("src/integrations/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // Modular executable
    const exe = b.addExecutable(.{
        .name = "nexcage",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add libraries
    exe.linkLibrary(bfc_lib);
    exe.linkLibrary(crun_lib);

    // Link system libraries
    exe.linkSystemLibrary("cap");
    exe.linkSystemLibrary("seccomp");
    exe.linkSystemLibrary("yajl");
    exe.linkSystemLibrary("c");

    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/src/libcrun" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });

    // Add modules
    exe.root_module.addImport("core", core_mod);
    exe.root_module.addImport("cli", cli_mod);
    exe.root_module.addImport("backends", backends_mod);
    exe.root_module.addImport("integrations", integrations_mod);
    exe.root_module.addImport("utils", utils_mod);

    // Install
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
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
        .root_source_file = b.path("src/main.zig"),
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
