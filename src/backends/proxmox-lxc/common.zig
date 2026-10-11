const std = @import("std");
const builtin = @import("builtin");
const core = @import("core");
const posix = std.posix;
const linux = std.os.linux;

pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

pub fn runCommand(allocator: std.mem.Allocator, logger: ?*core.LogContext, args: []const []const u8) !CommandResult {
    return runCommandMax(allocator, logger, args, 1024 * 1024);
}

/// What nexcage reads from a listing of the whole cluster. /cluster/resources
/// has an entry of a few hundred bytes for every guest on every node, so a
/// cluster of a few thousand outgrew the 1 MiB every other call is read with
/// -- and what did not fit was taken for "the cluster cannot be asked".
pub const cluster_max_output = 64 * 1024 * 1024;

/// runCommand with a cap of the caller's on each of stdout and stderr.
/// Output past it is an error that says so, never a short answer.
pub fn runCommandMax(allocator: std.mem.Allocator, logger: ?*core.LogContext, args: []const []const u8, max_output_bytes: usize) !CommandResult {
    const result = runBound(.{
        .allocator = allocator,
        .argv = args,
        .max_output_bytes = max_output_bytes,
    }) catch |err| {
        // A missing pct/pvesh means this is not a Proxmox host; say so rather
        // than "Failed to run command: error.FileNotFound".
        if (err == error.FileNotFound) {
            if (logger) |log| log.err("'{s}' not found in PATH; nexcage must run on a Proxmox VE host", .{args[0]}) catch {};
            return core.Error.UnsupportedOperation;
        }
        if (err == error.StdoutStreamTooLong or err == error.StderrStreamTooLong) {
            if (logger) |log| log.err("'{s}' printed more than the {d} bytes nexcage reads from it", .{ args[0], max_output_bytes }) catch {};
            return core.Error.OperationFailed;
        }
        if (logger) |log| log.err("Failed to run '{s}': {s}", .{ args[0], @errorName(err) }) catch {};
        return core.Error.OperationFailed;
    };

    const exit_code = switch (result.term) {
        .Exited => |code| @as(u8, @intCast(@abs(code))),
        else => 1,
    };

    return CommandResult{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = exit_code,
    };
}

pub const NetDeviceRuntimeInfo = struct {
    alias: []const u8,
    bridge: []const u8,
    host_name: ?[]const u8 = null,
};

test "the cluster's listing is read whole: 2 MiB is within its cap" {
    const a = std.testing.allocator;
    const res = try runCommandMax(a, null, &.{ "head", "-c", "2097152", "/dev/zero" }, cluster_max_output);
    defer {
        a.free(res.stdout);
        a.free(res.stderr);
    }
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqual(@as(usize, 2 * 1024 * 1024), res.stdout.len);
}

test "output past the cap is an error, not a short answer" {
    try std.testing.expectError(core.Error.OperationFailed, runCommandMax(std.testing.allocator, null, &.{ "head", "-c", "2048", "/dev/zero" }, 1024));
}

/// The signal a child gets when nexcage dies under it.
///
/// TERM, not KILL, because of what `pct create` is. pct does the work in a
/// task worker of its own session (PVE::RESTEnvironment::fork_worker, which
/// calls setsid when stdin is not a terminal, and nexcage's is /dev/null) and
/// waits for it. A TERM to pct is passed on to that worker's process group
/// (tee_worker's handler), and the worker dies through create's own error
/// path, which removes what it had made. A KILL reaches pct alone: the worker
/// carries on creating the container until it next writes to the pipe pct
/// held, and then dies of SIGPIPE half-way, leaving a CT locked in "create".
/// Every other child -- tar, pvesm, pvesh get, zfs -- ends on TERM as on KILL.
const parent_death_signal = posix.SIG.TERM;

/// What can stop a child before its program runs, reported from the child.
const StartError = posix.ExecveError || error{
    /// prctl(PR_SET_PDEATHSIG) was refused.
    ParentDeathSignal,
    /// nexcage died between fork and prctl, before there was a signal to send.
    ParentGone,
    /// stdin, stdout or stderr could not be put in place.
    StdioSetup,
};

/// std.process.Child.run, with the one thing it cannot do: the child is bound
/// to nexcage's life, through PR_SET_PDEATHSIG set between fork and exec,
/// where Child has no hook.
///
/// nexcage installs no signal handlers. A wrapper that kills it -- Python's
/// subprocess.run(timeout=), Go's exec.CommandContext, a systemd unit with
/// KillMode=process -- signals nexcage alone, and a child ran on without it:
/// a `pct create` whose caller was killed still made the container, later,
/// with no state.json and none of the bundle's mounts or features, under a
/// name a retry was then refused. Otherwise this runs the program as Child.run
/// does: the same arguments and environment, stdin on /dev/null, and stdout
/// and stderr collected up to `max_output_bytes`.
fn runBound(args: struct {
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    max_output_bytes: usize,
}) !std.process.Child.RunResult {
    const allocator = args.allocator;

    // Everything the child needs is made before fork: between fork and exec
    // it may not allocate, as Child does not.
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const argv_z = try arena.allocSentinel(?[*:0]const u8, args.argv.len, null);
    for (args.argv, 0..) |arg, i| argv_z[i] = (try arena.dupeZ(u8, arg)).ptr;
    const envp: [*:null]const ?[*:0]const u8 = if (builtin.link_libc) std.c.environ else @ptrCast(std.os.environ.ptr);

    // CLOEXEC on everything, so the program inherits only what dup2 puts in
    // place, and the report pipe closes by itself when exec succeeds.
    const null_fd = try posix.openZ("/dev/null", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    defer posix.close(null_fd);
    const out_pipe = try posix.pipe2(.{ .CLOEXEC = true });
    defer posix.close(out_pipe[0]);
    var out_w: ?posix.fd_t = out_pipe[1];
    defer if (out_w) |fd| posix.close(fd);
    const err_pipe = try posix.pipe2(.{ .CLOEXEC = true });
    defer posix.close(err_pipe[0]);
    var err_w: ?posix.fd_t = err_pipe[1];
    defer if (err_w) |fd| posix.close(fd);
    const report = try posix.pipe2(.{ .CLOEXEC = true });
    defer posix.close(report[0]);
    var report_w: ?posix.fd_t = report[1];
    defer if (report_w) |fd| posix.close(fd);

    const parent = linux.getpid();
    const pid = try posix.fork();
    if (pid == 0) {
        const failure: StartError = start: {
            if (linux.E.init(linux.prctl(@intFromEnum(linux.PR.SET_PDEATHSIG), parent_death_signal, 0, 0, 0)) != .SUCCESS)
                break :start error.ParentDeathSignal;
            // The signal is sent when the parent dies; one that died before
            // prctl ran sends nothing, and this process now belongs to init
            // or a subreaper. Nobody is left to read what the program does.
            if (linux.getppid() != parent) break :start error.ParentGone;
            posix.dup2(null_fd, posix.STDIN_FILENO) catch break :start error.StdioSetup;
            posix.dup2(out_pipe[1], posix.STDOUT_FILENO) catch break :start error.StdioSetup;
            posix.dup2(err_pipe[1], posix.STDERR_FILENO) catch break :start error.StdioSetup;
            break :start posix.execvpeZ(argv_z[0].?, argv_z.ptr, envp);
        };
        const code: u16 = @intFromError(failure);
        _ = linux.write(report[1], std.mem.asBytes(&code), @sizeOf(u16));
        // _exit, not exit: atexit handlers are the parent's, not this child's
        if (builtin.link_libc) std.c._exit(127);
        linux.exit(127);
    }

    // Only the child holds the write ends now, so each read below ends when
    // the child closes them: at exec for the report, at exit for the output.
    posix.close(out_w.?);
    out_w = null;
    posix.close(err_w.?);
    err_w = null;
    posix.close(report_w.?);
    report_w = null;

    var reaped = false;
    errdefer if (!reaped) {
        posix.kill(pid, posix.SIG.KILL) catch {};
        _ = posix.waitpid(pid, 0);
    };

    var code: u16 = 0;
    if (try posix.read(report[0], std.mem.asBytes(&code)) == @sizeOf(u16)) {
        _ = posix.waitpid(pid, 0);
        reaped = true;
        const failure: StartError = @errorCast(@errorFromInt(code));
        return failure;
    }

    var poller = std.Io.poll(allocator, enum { stdout, stderr }, .{
        .stdout = std.fs.File{ .handle = out_pipe[0] },
        .stderr = std.fs.File{ .handle = err_pipe[0] },
    });
    defer poller.deinit();
    while (try poller.poll()) {
        if (poller.reader(.stdout).bufferedLen() > args.max_output_bytes) return error.StdoutStreamTooLong;
        if (poller.reader(.stderr).bufferedLen() > args.max_output_bytes) return error.StderrStreamTooLong;
    }

    const stdout = try poller.toOwnedSlice(.stdout);
    errdefer allocator.free(stdout);
    const stderr = try poller.toOwnedSlice(.stderr);
    errdefer allocator.free(stderr);

    const status = posix.waitpid(pid, 0).status;
    reaped = true;
    const term: std.process.Child.Term = if (posix.W.IFEXITED(status))
        .{ .Exited = posix.W.EXITSTATUS(status) }
    else if (posix.W.IFSIGNALED(status))
        .{ .Signal = posix.W.TERMSIG(status) }
    else
        .{ .Unknown = status };
    return .{ .term = term, .stdout = stdout, .stderr = stderr };
}

/// Replace `<dir_path>/<name>` with `bytes`, so that whoever reads it sees the
/// old file or the new one and never part of either.
///
/// The bytes go to a new file beside it, which is synced and then renamed over
/// the old one; a rename within a directory is atomic. Rewriting the file in
/// place -- truncate, then write -- let a reader find it empty, and a write
/// that failed half-way (/run full, an I/O error) or a nexcage killed in
/// between left it empty for good. The new file is made with O_EXCL and
/// O_NOFOLLOW, so it is nexcage's own whatever was put under its name, and
/// with the mode a plain create gives, as the file had before.
pub fn writeFileAtomic(dir_path: []const u8, name: []const u8, bytes: []const u8) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{});
    defer dir.close();

    var tmp_buf: [std.fs.max_name_bytes]u8 = undefined;
    const tmp_name = try std.fmt.bufPrint(&tmp_buf, ".{s}.{x:0>16}", .{ name, std.crypto.random.int(u64) });
    const fd = try posix.openat(dir.fd, tmp_name, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .EXCL = true,
        .NOFOLLOW = true,
        .CLOEXEC = true,
    }, std.fs.File.default_mode);
    const file = std.fs.File{ .handle = fd };
    var renamed = false;
    defer if (!renamed) dir.deleteFile(tmp_name) catch {};
    {
        defer file.close();
        try file.writeAll(bytes);
        try file.sync();
    }
    try posix.renameat(dir.fd, tmp_name, dir.fd, name);
    renamed = true;
}

test "runCommand: output, status and a missing program, as Child.run gave them" {
    const allocator = std.testing.allocator;

    const ok = try runCommand(allocator, null, &.{ "sh", "-c", "echo out; echo err >&2; exit 3" });
    defer allocator.free(ok.stdout);
    defer allocator.free(ok.stderr);
    try std.testing.expectEqualStrings("out\n", ok.stdout);
    try std.testing.expectEqualStrings("err\n", ok.stderr);
    try std.testing.expectEqual(@as(u8, 3), ok.exit_code);

    // stdin is /dev/null: a program that reads it ends rather than waiting
    const cat = try runCommand(allocator, null, &.{"cat"});
    defer allocator.free(cat.stdout);
    defer allocator.free(cat.stderr);
    try std.testing.expectEqual(@as(u8, 0), cat.exit_code);
    try std.testing.expectEqualStrings("", cat.stdout);

    const killed = try runCommand(allocator, null, &.{ "sh", "-c", "kill -9 $$" });
    defer allocator.free(killed.stdout);
    defer allocator.free(killed.stderr);
    try std.testing.expectEqual(@as(u8, 1), killed.exit_code);

    try std.testing.expectError(core.Error.UnsupportedOperation, runCommand(allocator, null, &.{"nexcage-no-such-program"}));
}

/// Whether this process has a child left, running or a zombie.
fn hasChild() bool {
    var status: u32 = 0;
    return linux.E.init(linux.waitpid(-1, &status, linux.W.NOHANG)) != .CHILD;
}

test "runBound: output past the limit is an error, and the child is reaped" {
    try std.testing.expectError(error.StdoutStreamTooLong, runBound(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "head", "-c", "100000", "/dev/zero" },
        .max_output_bytes = 1000,
    }));
    try std.testing.expect(!hasChild());
}

test "runBound: the child is sent parent_death_signal when its parent dies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir);
    const script = try std.fmt.allocPrint(allocator, "echo $$ > {s}/pid.tmp && mv {s}/pid.tmp {s}/pid && exec sleep 30", .{ dir, dir, dir });
    defer allocator.free(script);

    // A process standing in for nexcage runs the command and is killed under it.
    const caller = try posix.fork();
    if (caller == 0) {
        _ = runBound(.{ .allocator = std.heap.page_allocator, .argv = &.{ "sh", "-c", script }, .max_output_bytes = 1024 }) catch {};
        linux.exit(0);
    }
    var buf: [512]u8 = undefined;
    const grandchild: posix.pid_t = for (0..200) |_| {
        const text = tmp.dir.readFile("pid", &buf) catch {
            std.Thread.sleep(25 * std.time.ns_per_ms);
            continue;
        };
        break try std.fmt.parseInt(posix.pid_t, std.mem.trim(u8, text, " \n"), 10);
    } else {
        posix.kill(caller, posix.SIG.KILL) catch {};
        _ = posix.waitpid(caller, 0);
        return error.CommandNeverStarted;
    };
    try posix.kill(caller, posix.SIG.KILL);
    _ = posix.waitpid(caller, 0);

    // The command is reparented, so this process cannot wait for it: /proc
    // says whether it is gone, or a zombie its new parent has yet to reap.
    const stat_path = try std.fmt.allocPrint(allocator, "/proc/{d}/stat", .{grandchild});
    defer allocator.free(stat_path);
    const gone = for (0..200) |_| {
        const stat = std.fs.cwd().readFile(stat_path, &buf) catch break true;
        const paren = std.mem.lastIndexOfScalar(u8, stat, ')') orelse break true;
        if (stat.len > paren + 2 and stat[paren + 2] == 'Z') break true;
        std.Thread.sleep(25 * std.time.ns_per_ms);
    } else false;
    if (!gone) posix.kill(grandchild, posix.SIG.KILL) catch {};
    try std.testing.expect(gone);
}

test "writeFileAtomic: a reader keeps a whole file, and a failed write keeps the old one" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir);

    try writeFileAtomic(dir, "state.json", "{\"status\": \"created\"}\n");
    // Someone reading the file while it is replaced
    const reader = try tmp.dir.openFile("state.json", .{});
    defer reader.close();
    try writeFileAtomic(dir, "state.json", "{\"status\": \"running\"}\n");

    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("{\"status\": \"created\"}\n", buf[0..try reader.readAll(&buf)]);
    try std.testing.expectEqualStrings("{\"status\": \"running\"}\n", try tmp.dir.readFile("state.json", &buf));

    // The mode a plain create gives, as before
    const reference = try tmp.dir.createFile("reference", .{});
    reference.close();
    try std.testing.expectEqual((try tmp.dir.statFile("reference")).mode, (try tmp.dir.statFile("state.json")).mode);
    try tmp.dir.deleteFile("reference");

    // A write that fails, as on a full /run: with SIGXFSZ ignored, a file
    // size limit of 0 makes write(2) fail with EFBIG.
    const old_limit = try posix.getrlimit(.FSIZE);
    const ignore = posix.Sigaction{ .handler = .{ .handler = posix.SIG.IGN }, .mask = posix.sigemptyset(), .flags = 0 };
    var old_action: posix.Sigaction = undefined;
    posix.sigaction(posix.SIG.XFSZ, &ignore, &old_action);
    try posix.setrlimit(.FSIZE, .{ .cur = 0, .max = old_limit.max });
    const failed = writeFileAtomic(dir, "state.json", "{\"status\": \"stopped\"}\n");
    try posix.setrlimit(.FSIZE, old_limit);
    posix.sigaction(posix.SIG.XFSZ, &old_action, null);
    try std.testing.expectError(error.FileTooBig, failed);

    try std.testing.expectEqualStrings("{\"status\": \"running\"}\n", try tmp.dir.readFile("state.json", &buf));
    // and no temporary file is left beside it
    var it = tmp.dir.iterate();
    var names: usize = 0;
    while (try it.next()) |entry| {
        try std.testing.expectEqualStrings("state.json", entry.name);
        names += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), names);
}
