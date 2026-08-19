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

fn collectCFiles(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    list: *std.ArrayListUnmanaged([]const u8),
) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        const entry_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".c")) {
                    if (std.mem.startsWith(u8, entry.name, "basic_test") or std.mem.eql(u8, entry.name, "validate.c")) {
                        allocator.free(entry_path);
                    } else {
                        try list.append(allocator, entry_path);
                    }
                } else {
                    allocator.free(entry_path);
                }
            },
            .directory => {
                try collectCFiles(allocator, entry_path, list);
                allocator.free(entry_path);
            },
            else => allocator.free(entry_path),
        }
    }
}

fn gatherLibcrunSources(b: *Build) ![]const []const u8 {
    var files = std.ArrayListUnmanaged([]const u8){};
    defer files.deinit(b.allocator);
    try collectCFiles(b.allocator, "deps/crun/src/libcrun", &files);
    try collectCFiles(b.allocator, "deps/crun/libocispec/src", &files);
    return files.toOwnedSlice(b.allocator);
}

// Version information is sourced from VERSION file at build time

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Read VERSION file early for build options
    const version_bytes = std.fs.cwd().readFileAlloc(b.allocator, "VERSION", 64) catch @panic("Failed to read VERSION file");
    const app_version = std.mem.trim(u8, version_bytes, " \n\r\t");

    // Create separate build options to avoid module conflicts
    // core_build_options: for core module (version info)
    const core_build_options = b.addOptions();
    core_build_options.addOption([]const u8, "app_version", app_version);

    // build_options: for backends and integrations (feature flags)
    const build_options = b.addOptions();

    // feature_options: for crun backend (libcrun ABI flags)
    const feature_options = b.addOptions();

    // Feature flags
    // Check for systemd availability to set default
    const systemd_exists = pkgConfigExists(b, "libsystemd");
    const enable_libcrun_abi = b.option(bool, "enable-libcrun-abi", "Enable libcrun ABI (requires libcrun and systemd, default: auto-detected)") orelse systemd_exists;

    var libcrun_abi_active = false;
    var libsystemd_available = false;

    // Backend feature flags (most enabled by default)
    const enable_backend_proxmox_lxc = b.option(bool, "enable-backend-proxmox-lxc", "Enable Proxmox LXC backend (default: true)") orelse true;
    const enable_backend_proxmox_vm = b.option(bool, "enable-backend-proxmox-vm", "Enable Proxmox VM backend (default: false)") orelse false;
    const enable_backend_crun = b.option(bool, "enable-backend-crun", "Enable Crun OCI backend (default: true)") orelse true;
    const enable_backend_runc = b.option(bool, "enable-backend-runc", "Enable Runc OCI backend (default: true)") orelse true;

    build_options.addOption(bool, "enable_backend_proxmox_lxc", enable_backend_proxmox_lxc);
    build_options.addOption(bool, "enable_backend_proxmox_vm", enable_backend_proxmox_vm);
    build_options.addOption(bool, "enable_backend_crun", enable_backend_crun);
    build_options.addOption(bool, "enable_backend_runc", enable_backend_runc);

    // Integration feature flags (selective defaults)
    const enable_zfs = b.option(bool, "enable-zfs", "Enable ZFS integration (default: true)") orelse true;
    const enable_bfc = b.option(bool, "enable-bfc", "Enable BFC integration (default: false)") orelse false;
    const enable_proxmox_api = b.option(bool, "enable-proxmox-api", "Enable Proxmox API integration (default: false)") orelse false;

    build_options.addOption(bool, "enable_zfs", enable_zfs);
    build_options.addOption(bool, "enable_bfc", enable_bfc);
    build_options.addOption(bool, "enable_proxmox_api", enable_proxmox_api);
    build_options.addOption(bool, "enable_libcrun_abi", enable_libcrun_abi);

    // Create shared build options module
    const build_options_mod = build_options.createModule();

    // Core module
    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core/mod.zig"),
    });
    core_mod.addOptions("core_build_options", core_build_options);

    // Use local oci-spec-zig from deps/
    const oci_spec_mod = b.addModule("oci_spec", .{
        .root_source_file = b.path("deps/oci-spec-zig/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Utils module
    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "oci_spec", .module = oci_spec_mod },
        },
    });

    // Backends module
    const backends_mod = b.addModule("backends", .{
        .root_source_file = b.path("src/backends/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "oci_spec", .module = oci_spec_mod },
        },
    });
    backends_mod.addImport("build_options", build_options_mod);
    backends_mod.addOptions("feature_options", feature_options);

    // Config integration module
    const config_integration_mod = b.addModule("config_integration", .{
        .root_source_file = b.path("src/core/enhanced_config.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // CLI module
    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/cli/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "backends", .module = backends_mod },
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "config_integration", .module = config_integration_mod },
        },
    });

    // Integrations module
    // Note: integrations_mod uses build_options through backends_mod to avoid module conflicts
    const integrations_mod = b.addModule("integrations", .{
        .root_source_file = b.path("src/integrations/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "backends", .module = backends_mod },
        },
    });
    integrations_mod.addImport("build_options", build_options_mod);

    var libcrun_lib: ?*std.Build.Step.Compile = null;

    if (enable_libcrun_abi) {
        libsystemd_available = pkgConfigExists(b, "libsystemd");
        if (!libsystemd_available) {
            std.debug.print("[build] error: libsystemd not detected; libcrun ABI backend requires libsystemd development files.\n", .{});
            @panic("libsystemd not available");
        }
        const libcrun_sources = gatherLibcrunSources(b) catch |err| {
            std.debug.print("[build] error: failed collecting libcrun sources: {}\n", .{err});
            @panic("libcrun sources missing");
        };
        const libcrun_module = b.createModule(.{
            .root_source_file = b.path("src/backends/crun/libcrun_stub.zig"),
            .target = target,
            .optimize = optimize,
        });
        libcrun_module.addCSourceFiles(.{
            .files = libcrun_sources,
            .flags = &[_][]const u8{
                "-std=gnu11",
                "-D_GNU_SOURCE",
                "-Wno-macro-redefined",
                "-DLIBCRUN_STATIC",
                "-DLIBCRUN_PUBLIC=",
            },
        });
        libcrun_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src/libcrun" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "deps/crun" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "src/backends/crun" });
        const libcrun_compile = b.addLibrary(.{
            .name = "libcrun_vendor",
            .root_module = libcrun_module,
            .linkage = .static,
        });
        libcrun_compile.linkSystemLibrary("c");
        libcrun_compile.linkSystemLibrary("pthread");
        libcrun_compile.linkSystemLibrary("dl");
        libcrun_compile.linkSystemLibrary("rt");
        libcrun_compile.root_module.linkSystemLibrary("systemd", .{ .use_pkg_config = .no, .needed = true });
        libcrun_lib = libcrun_compile;
        libcrun_abi_active = true;
    }

    feature_options.addOption(bool, "libcrun_abi_requested", enable_libcrun_abi);
    feature_options.addOption(bool, "libcrun_abi_active", libcrun_abi_active);
    feature_options.addOption(bool, "libsystemd_available", libsystemd_available);

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

    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src" });
    exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src/libcrun" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });
    exe.addIncludePath(.{ .cwd_relative = "src/backends/crun" }); // For libcrun_wrapper.h

    if (libcrun_lib) |lib| {
        exe.root_module.linkLibrary(lib);
        exe.root_module.linkSystemLibrary("systemd", .{ .use_pkg_config = .no, .needed = true });
        exe.linkSystemLibrary("cap");
        exe.linkSystemLibrary("seccomp");
        exe.linkSystemLibrary("yajl");
        exe.linkSystemLibrary("systemd");
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("dl");
        exe.linkSystemLibrary("rt");
    }

    // Add module dependencies
    exe.root_module.addImport("core", core_mod);
    exe.root_module.addImport("cli", cli_mod);
    exe.root_module.addImport("backends", backends_mod);
    exe.root_module.addImport("integrations", integrations_mod);
    exe.root_module.addImport("utils", utils_mod);

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

    if (libcrun_lib) |lib| {
        test_exe.root_module.linkLibrary(lib);
        test_exe.root_module.linkSystemLibrary("systemd", .{ .use_pkg_config = .no, .needed = true });
        test_exe.linkSystemLibrary("cap");
        test_exe.linkSystemLibrary("seccomp");
        test_exe.linkSystemLibrary("yajl");
        test_exe.linkSystemLibrary("systemd");
        test_exe.linkSystemLibrary("pthread");
        test_exe.linkSystemLibrary("dl");
        test_exe.linkSystemLibrary("rt");
    }

    test_exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "./crun-1.23.1/src/libcrun" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "src/backends/crun" });

    test_exe.root_module.addImport("core", core_mod);
    test_exe.root_module.addImport("cli", cli_mod);
    test_exe.root_module.addImport("backends", backends_mod);
    test_exe.root_module.addImport("integrations", integrations_mod);
    test_exe.root_module.addImport("utils", utils_mod);

    const run_test = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);

    // `zig build test` reported success in 1ms for 304 tests, because the
    // test module's root is src/main.zig and main.zig declares no tests.
    // Zig only compiles what the root file reaches, and nothing in that
    // graph leads to the test files — so the suite had never run at all.
    //
    // One addTest per file rather than one aggregate root: a file that fails
    // to compile then takes only itself down, and the failure names the file.
    // With a single root, the first broken import hides every other result.
    const walker_dirs = [_][]const u8{ "tests", "src" };
    for (walker_dirs) |dir_name| {
        var dir = b.build_root.handle.openDir(dir_name, .{ .iterate = true }) catch continue;
        defer dir.close();
        var walker = dir.walk(b.allocator) catch continue;
        defer walker.deinit();
        while (walker.next() catch null) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;

            const rel = b.pathJoin(&.{ dir_name, entry.path });
            const source = b.build_root.handle.readFileAlloc(b.allocator, rel, 4 * 1024 * 1024) catch continue;

            // Files that import source by relative path (@import("../src/..."))
            // escape their own module and cannot be rooted where they live.
            // They are compiled together from test_root_relative.zig instead;
            // see the comment there for why they are not all merged.
            if (std.mem.indexOf(u8, source, "@import(\"../") != null) continue;
            // only files that actually declare tests; compiling the rest
            // would add build time and no signal
            if (std.mem.indexOf(u8, source, "\ntest \"") == null and
                !std.mem.startsWith(u8, source, "test \"")) continue;

            const file_mod = b.createModule(.{
                .root_source_file = b.path(rel),
                .target = target,
                .optimize = optimize,
            });
            file_mod.addImport("core", core_mod);
            file_mod.addImport("cli", cli_mod);
            file_mod.addImport("backends", backends_mod);
            file_mod.addImport("integrations", integrations_mod);
            file_mod.addImport("utils", utils_mod);

            const file_test = b.addTest(.{ .name = entry.basename, .root_module = file_mod });
            file_test.linkSystemLibrary("c");
            file_test.addIncludePath(.{ .cwd_relative = "/usr/include" });
            file_test.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
            file_test.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });

            test_step.dependOn(&b.addRunArtifact(file_test).step);
        }
    }

    // The twelve relative-path importers, rooted at the repository root so
    // tests/ and src/ are inside one module.
    const rel_mod = b.createModule(.{
        .root_source_file = b.path("test_root_relative.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Deliberately no named module imports here. These tests reach into src/
    // by relative path, so the same file would belong to both this module and
    // `backends` — which Zig rejects outright: "file exists in modules 'root'
    // and 'backends'". A test that wants the named modules should import
    // through them instead of relative paths, and then it no longer belongs
    // in this aggregate at all.

    const rel_test = b.addTest(.{ .name = "relative-imports", .root_module = rel_mod });
    rel_test.linkSystemLibrary("c");
    rel_test.addIncludePath(.{ .cwd_relative = "/usr/include" });
    rel_test.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    rel_test.addIncludePath(.{ .cwd_relative = "deps/bfc/include" });
    test_step.dependOn(&b.addRunArtifact(rel_test).step);
}
