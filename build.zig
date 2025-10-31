const std = @import("std");
const Build = std.Build;
const fs = std.fs;

// Version information is sourced from VERSION file at build time

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zig-json dependency removed for Zig 0.15.1 compatibility

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

    // Backends module
    const backends_mod = b.addModule("backends", .{
        .root_source_file = b.path("src/backends/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
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

    // Read VERSION file and pass to modules via options
    const version_bytes = std.fs.cwd().readFileAlloc(b.allocator, "VERSION", 64) catch @panic("Failed to read VERSION file");
    const app_version = std.mem.trim(u8, version_bytes, " \n\r\t");

    // Build options shared across modules
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "app_version", app_version);

    // Main executable
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_mod.addOptions("build_options", build_options);
    
    const exe = b.addExecutable(.{
        .name = "nexcage",
        .root_module = main_mod,
    });

    // Link system libraries
    exe.linkSystemLibrary("c");
    
    // Required system libraries
    exe.linkSystemLibrary("cap");
    exe.linkSystemLibrary("seccomp");
    exe.linkSystemLibrary("yajl");
    
    // Optional: Link libcrun and systemd only if libcrun ABI is enabled
    // Check if libcrun ABI is enabled by checking the feature flag
    // Note: We can't directly check the flag from build.zig, so we'll use a workaround:
    // Try to link them, but since USE_LIBCRUN_ABI defaults to false, they won't be used at runtime
    // The linking will only succeed if the libraries are installed, which is fine
    // If they're not available, we'll skip linking them (requires build option)
    const link_libcrun = b.option(bool, "link-libcrun", "Link libcrun and systemd libraries (default: false)") orelse false;
    if (link_libcrun) {
        exe.linkSystemLibrary("crun");
        exe.linkSystemLibrary("systemd");
    }

    // No additional static Zig libraries linked to avoid duplicate start symbol

    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src" });
    exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src/libcrun" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/src/libcrun" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });
    exe.addIncludePath(.{ .cwd_relative = "src/backends/crun" }); // For libcrun_wrapper.h

    // Add module dependencies
    exe.root_module.addImport("core", core_mod);
    exe.root_module.addImport("cli", cli_mod);
    exe.root_module.addImport("backends", backends_mod);
    exe.root_module.addImport("integrations", integrations_mod);
    exe.root_module.addImport("utils", utils_mod);
    // zig-json import removed for Zig 0.15.1 compatibility

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
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addOptions("build_options", build_options);
    
    const test_exe = b.addTest(.{
        .name = "test",
        .root_module = test_mod,
    });

    test_exe.linkSystemLibrary("c");
    
    // Required system libraries for tests
    test_exe.linkSystemLibrary("cap");
    test_exe.linkSystemLibrary("seccomp");
    test_exe.linkSystemLibrary("yajl");
    
    // Optional: Link libcrun and systemd only if requested
    const link_libcrun = b.option(bool, "link-libcrun", "Link libcrun and systemd libraries (default: false)") orelse false;
    if (link_libcrun) {
        test_exe.linkSystemLibrary("crun");
        test_exe.linkSystemLibrary("systemd");
    }
    // No additional static Zig libraries linked into tests

    test_exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src/libcrun" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/src/libcrun" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "src/backends/crun" }); // For libcrun_wrapper.h

    test_exe.root_module.addImport("core", core_mod);
    test_exe.root_module.addImport("cli", cli_mod);
    test_exe.root_module.addImport("backends", backends_mod);
    test_exe.root_module.addImport("integrations", integrations_mod);
    test_exe.root_module.addImport("utils", utils_mod);
    // zig-json import removed for Zig 0.15.1 compatibility

    const run_test = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}