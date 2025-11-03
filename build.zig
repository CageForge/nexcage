const std = @import("std");
const Build = std.Build;
const fs = std.fs;

// Helper to collect .c files recursively with simple filters
fn collectC(dir_path: []const u8, list: *std.ArrayListUnmanaged([]const u8), allocator: std.mem.Allocator) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |e| {
        const child_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, e.name });
        defer allocator.free(child_path);
        if (e.kind == .file) {
            if (std.mem.endsWith(u8, e.name, ".c") and std.mem.indexOf(u8, e.name, "test") == null) {
                try list.append(allocator, try allocator.dupe(u8, child_path));
            }
        } else if (e.kind == .directory) {
            try collectC(child_path, list, allocator);
        }
    }
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
    
    // Vendored libcrun build (system libcrun linking removed)
    const use_vendored_libcrun = b.option(bool, "use-vendored-libcrun", "Build and link vendored libcrun from deps/crun (default: false)") orelse false;

    var vendored_enabled = false;
    if (use_vendored_libcrun) {
        // Check system deps (pkg-config) and generate headers if missing
        const deps_check = b.addSystemCommand(&.{ "bash", "-lc", "pkg-config --exists libseccomp yajl libcap libsystemd" });
        exe.step.dependOn(&deps_check.step);
        var need_gen: bool = false;
        if (std.fs.cwd().access("deps/crun/config.h", .{})) |_| { } else |_| { need_gen = true; }
        if (std.fs.cwd().access("deps/crun/git-version.h", .{})) |_| { } else |_| { need_gen = true; }
        const gen_headers = b.addSystemCommand(&.{ "bash", "scripts/gen_crun_headers_local.sh" });
        if (need_gen) exe.step.dependOn(&gen_headers.step);

        // Build static library from deps/crun sources
        var c_files: std.ArrayListUnmanaged([]const u8) = .{};
        defer {
            // free duplicated paths
            if (c_files.items.len > 0) {
                for (c_files.items) |p| b.allocator.free(p);
                b.allocator.free(c_files.items);
            }
        }

        // Collect libcrun core and libocispec sources (exclude tests via name filter)
        collectC("deps/crun/src/libcrun", &c_files, b.allocator) catch |err| {
            std.debug.print("[build] warn: failed collecting libcrun sources: {s}\n", .{@errorName(err)});
        };
        collectC("deps/crun/libocispec/src", &c_files, b.allocator) catch |err| {
            std.debug.print("[build] warn: failed collecting libocispec sources: {s}\n", .{@errorName(err)});
        };

        const c_files_slice = c_files.toOwnedSlice(b.allocator) catch @panic("alloc failed");
        defer b.allocator.free(c_files_slice);
        exe.addIncludePath(.{ .cwd_relative = "deps/crun" }); // for generated config.h
        exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
        exe.addIncludePath(.{ .cwd_relative = "deps/crun/src/libcrun" });
        exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
        exe.addCSourceFiles(.{ .files = c_files_slice, .flags = &[_][]const u8{ "-std=gnu11", "-D_GNU_SOURCE", "-Wno-macro-redefined", "-DLIBCRUN_PUBLIC=", "-include", "seccomp.h", "-include", "sys/syscall.h" } });
        exe.linkSystemLibrary("yajl");
        exe.linkSystemLibrary("cap");
        exe.linkSystemLibrary("seccomp");
        exe.linkLibC();
        vendored_enabled = true;
    }
    // System libcrun linking removed by project policy

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

    // Prepare vendored crun headers and check system deps explicitly
    const deps_check_step = b.addSystemCommand(&.{ "bash", "-lc", "pkg-config --exists libseccomp yajl libcap libsystemd" });
    const gen_headers_step = b.addSystemCommand(&.{ "bash", "scripts/gen_crun_headers_local.sh" });
    const prepare_step = b.step("prepare-crun", "Generate crun headers and verify system dependencies");
    prepare_step.dependOn(&deps_check_step.step);
    prepare_step.dependOn(&gen_headers_step.step);

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
    
    // Optional: Link libcrun and systemd only if requested (reuse link_libcrun from above)
    if (vendored_enabled) {
        // tests use Zig-only path; ABI exercised in integration tests
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