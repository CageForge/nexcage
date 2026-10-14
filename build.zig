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

    // build_options: backend feature flags
    const build_options = b.addOptions();

    // feature_options: for crun backend (libcrun ABI flags)
    const feature_options = b.addOptions();

    // Backend feature flags. Proxmox LXC is always built: the CLI calls its
    // driver directly, and it is the backend nexcage exists for. crun needs
    // vendored libcrun (git submodules plus generated headers), so it is opt-in.
    const enable_backend_crun = b.option(bool, "enable-backend-crun", "Enable crun OCI backend, links vendored libcrun (default: false)") orelse false;

    // The libcrun ABI follows the crun backend. It used to default to "is
    // libsystemd installed", so a plain `zig build` on any machine with
    // libsystemd-dev demanded submodules that a fresh clone does not have.
    const enable_libcrun_abi = b.option(bool, "enable-libcrun-abi", "Link vendored libcrun (default: follows enable-backend-crun)") orelse enable_backend_crun;
    if (enable_backend_crun and !enable_libcrun_abi) {
        std.debug.print("[build] error: the crun backend is implemented on libcrun; -Denable-backend-crun=true requires -Denable-libcrun-abi=true.\n", .{});
        @panic("crun backend without libcrun ABI");
    }

    var libcrun_abi_active = false;
    var libsystemd_available = false;

    build_options.addOption(bool, "enable_backend_crun", enable_backend_crun);

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

    // Backends module
    const backends_mod = b.addModule("backends", .{
        .root_source_file = b.path("src/backends/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "oci_spec", .module = oci_spec_mod },
        },
    });
    backends_mod.addImport("build_options", build_options_mod);
    backends_mod.addOptions("feature_options", feature_options);

    // CLI module
    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/cli/mod.zig"),
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "backends", .module = backends_mod },
        },
    });

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
        // ReleaseSafe, which every release is built with, compiles this C
        // with UBSan in trap mode: Zig's default for C in a safe build, and
        // kept on purpose. Undefined behaviour in libcrun then stops the root
        // process instead of carrying on with a value nobody chose -- built
        // the usual way, crun turns a memory limit that overflows into "max",
        // no limit at all. The cost is that it stops with SIGILL, and a
        // SIGILL whose frames are in libcrun is such a trap, not a CPU
        // without AVX2 (that one is -Dcpu=baseline). Values known to reach
        // such arithmetic are refused before libcrun sees them
        // (libcrun_driver.zig, checkMemory).
        const libcrun_flags = [_][]const u8{
            "-std=gnu11",
            "-D_GNU_SOURCE",
            "-Wno-macro-redefined",
            "-DLIBCRUN_STATIC",
            "-DLIBCRUN_PUBLIC=",
        };
        // linux.c ends in `__attribute__ ((constructor)) static void
        // libcrun_rexec (void)`, crun's CVE-2019-5736 protection: before main,
        // on every run of the binary, it re-executes from a sealed copy of
        // itself, and exits 1 -- or dies of a seccomp filter's SIGSYS without
        // a word -- where /proc, open_tree, a bind mount or an executable
        // memfd is missing. In crun every command needs it; in nexcage only
        // the ones that make or join a container's process do, and `version`,
        // `--help` and every Proxmox LXC command died of it all the same.
        // So that one file is compiled with `constructor` defined to
        // `unused`: the function is left an unused static and dropped, and
        // the crun driver calls ensure_cloned_binary itself for create and
        // exec (libcrun_driver.zig, runFromSealedCopy). Preprocessed, linux.c
        // differs from the plain compile in that one line and no other; the
        // word appearing anywhere else in the file stops the build here, so a
        // pin bump cannot widen what the define touches unseen.
        const linux_c = "deps/crun/src/libcrun/linux.c";
        const linux_src = std.fs.cwd().readFileAlloc(b.allocator, linux_c, 4 * 1024 * 1024) catch @panic("cannot read " ++ linux_c);
        if (std.mem.count(u8, linux_src, "constructor") != 1) {
            std.debug.print("[build] error: {s} uses the word `constructor` {d} times, and build.zig defines it away for that file assuming one: libcrun_rexec. Check what the vendored crun changed before adjusting this.\n", .{ linux_c, std.mem.count(u8, linux_src, "constructor") });
            @panic("libcrun's rexec constructor has changed");
        }
        var other_sources = std.ArrayListUnmanaged([]const u8){};
        for (libcrun_sources) |path| {
            if (!std.mem.eql(u8, path, linux_c)) other_sources.append(b.allocator, path) catch @panic("OOM");
        }
        if (other_sources.items.len + 1 != libcrun_sources.len) @panic(linux_c ++ " is not among the libcrun sources");
        libcrun_module.addCSourceFiles(.{ .files = other_sources.items, .flags = &libcrun_flags });
        libcrun_module.addCSourceFile(.{ .file = b.path(linux_c), .flags = &(libcrun_flags ++ [_][]const u8{"-Dconstructor=unused"}) });
        libcrun_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "deps/crun" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
        libcrun_module.addIncludePath(.{ .cwd_relative = "src/backends/crun" });
        // Linked into a PIE (exe.pie below), so compiled as position-
        // independent code rather than relying on the default for a library.
        libcrun_module.pic = true;
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

        // src/backends/crun/mod.zig compares libcrun_ffi.zig's hand-written
        // mirrors of libcrun's structs with the vendored header through
        // @cImport, which looks in the backends module's include paths.
        backends_mod.addIncludePath(.{ .cwd_relative = "deps/crun" });
        backends_mod.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
        backends_mod.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
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
    // Position-independent, so the kernel loads it at a random address. The
    // binary runs as root and links libcrun and libocispec, C code that
    // parses a bundle's config.json; without this their code and data sit at
    // the same fixed address in every run, and a memory-safety bug in them
    // needs no address leak to be exploited. Zig's default for a Linux
    // executable is not PIE.
    exe.pie = true;

    // Link system libraries
    exe.linkSystemLibrary("c");

    // Add include paths
    exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    exe.addIncludePath(.{ .cwd_relative = "src/backends/crun" }); // For libcrun_wrapper.h

    if (libcrun_lib) |lib| {
        exe.root_module.linkLibrary(lib);
        exe.root_module.linkSystemLibrary("systemd", .{ .use_pkg_config = .no, .needed = true });
        exe.linkSystemLibrary("cap");
        exe.linkSystemLibrary("seccomp");
        // json-c, not yajl: crun 1.28 replaced it, libocispec included.
        exe.linkSystemLibrary("json-c");
        exe.linkSystemLibrary("systemd");
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("dl");
        exe.linkSystemLibrary("rt");
    }

    // Add module dependencies
    exe.root_module.addImport("core", core_mod);
    exe.root_module.addImport("cli", cli_mod);
    exe.root_module.addImport("backends", backends_mod);

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
        test_exe.linkSystemLibrary("json-c");
        test_exe.linkSystemLibrary("systemd");
        test_exe.linkSystemLibrary("pthread");
        test_exe.linkSystemLibrary("dl");
        test_exe.linkSystemLibrary("rt");
    }

    test_exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "deps/crun/libocispec/src" });
    test_exe.addIncludePath(.{ .cwd_relative = "src/backends/crun" });

    test_exe.root_module.addImport("core", core_mod);
    test_exe.root_module.addImport("cli", cli_mod);
    test_exe.root_module.addImport("backends", backends_mod);

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

            // A file that imports source by relative path (@import("../src/..."))
            // escapes its module and fails here, by name. That is deliberate:
            // skipping such files is how a test could go unnoticed. The ones
            // that did it tested code that no longer exists.
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
            // The Proxmox backend's bundle translation imports the parser
            file_mod.addImport("oci_spec", oci_spec_mod);

            const file_test = b.addTest(.{ .name = entry.basename, .root_module = file_mod });
            file_test.linkSystemLibrary("c");
            file_test.addIncludePath(.{ .cwd_relative = "/usr/include" });
            file_test.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
            // With the crun backend on, a test that reaches its driver --
            // tests/declarations_test.zig reaches all of it -- calls into
            // libcrun, and links it as the binary does.
            if (libcrun_lib) |lib| {
                file_test.root_module.linkLibrary(lib);
                file_test.root_module.linkSystemLibrary("systemd", .{ .use_pkg_config = .no, .needed = true });
                file_test.linkSystemLibrary("cap");
                file_test.linkSystemLibrary("seccomp");
                file_test.linkSystemLibrary("json-c");
                file_test.linkSystemLibrary("pthread");
                file_test.linkSystemLibrary("dl");
                file_test.linkSystemLibrary("rt");
            }

            test_step.dependOn(&b.addRunArtifact(file_test).step);
        }
    }
}
