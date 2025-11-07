const std = @import("std");
const Build = std.Build;
const fs = std.fs;

fn pkgConfigExists(b: *Build, package: []const u8) bool {
    var child = std.process.Child.init(&[_][]const u8{ "pkg-config", "--exists", package }, b.allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch {
        std.debug.print("[build] warn: pkg-config unavailable while checking {s}\n", .{package});
        return false;
    };
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

// Version information is sourced from VERSION file at build time

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zig-json dependency removed for Zig 0.15.1 compatibility

    // Read VERSION file early for build options
    const version_bytes = std.fs.cwd().readFileAlloc(b.allocator, "VERSION", 64) catch @panic("Failed to read VERSION file");
    const app_version = std.mem.trim(u8, version_bytes, " \n\r\t");

    // Create build options (one instance shared across all modules)
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "app_version", app_version);
    const feature_options = b.addOptions();

    const legacy_link_libcrun = b.option(bool, "link-libcrun", "(deprecated) Link libcrun/systemd");
    if (legacy_link_libcrun) |value| {
        if (value) {
            std.debug.print("[build] warn: -Dlink-libcrun is deprecated; libcrun ABI is always enabled.\n", .{});
        }
    }
    const enable_libcrun_abi = b.option(bool, "enable-libcrun-abi", "Enable libcrun ABI support (requires libsystemd)") orelse true;
    if (!enable_libcrun_abi) {
        std.debug.print("[build] error: libcrun CLI backend has been removed; libcrun ABI must remain enabled.\n", .{});
        @panic("libcrun ABI disabled");
    }
    var libcrun_abi_active = false;
    var libsystemd_available = false;

    // Core module
    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core/mod.zig"),
    });
    core_mod.addOptions("build_options", build_options);

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
    backends_mod.addOptions("feature_options", feature_options);

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

    // Main executable
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Note: build_options are NOT added to main_mod to avoid conflicts
    // Version is accessed via core.version.getVersion() instead

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

    if (enable_libcrun_abi) {
        const libcrun_available = pkgConfigExists(b, "libcrun");
        if (!libcrun_available) {
            std.debug.print("[build] error: libcrun not detected via pkg-config. Install libcrun development files or enable vendored libcrun.\n", .{});
            @panic("libcrun not available");
        }
        libsystemd_available = pkgConfigExists(b, "libsystemd");
        if (!libsystemd_available) {
            std.debug.print("[build] error: libsystemd not detected; libcrun ABI backend requires libsystemd development files.\n", .{});
            @panic("libsystemd not available");
        }
        exe.linkSystemLibrary("crun");
        exe.linkSystemLibrary("systemd");
        libcrun_abi_active = true;
    }

    feature_options.addOption(bool, "libcrun_abi_requested", enable_libcrun_abi);
    feature_options.addOption(bool, "libcrun_abi_active", libcrun_abi_active);
    feature_options.addOption(bool, "libsystemd_available", libsystemd_available);

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
    // Note: build_options are NOT added to test_mod to avoid conflicts
    // Version is accessed via core.version.getVersion() instead

    const test_exe = b.addTest(.{
        .name = "test",
        .root_module = test_mod,
    });

    test_exe.linkSystemLibrary("c");

    // Required system libraries for tests
    test_exe.linkSystemLibrary("cap");
    test_exe.linkSystemLibrary("seccomp");
    test_exe.linkSystemLibrary("yajl");

    // Optional: Link libcrun/systemd for tests when ABI active
    if (libcrun_abi_active) {
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
