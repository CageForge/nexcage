const std = @import("std");
const core = @import("core");
const common = @import("common.zig");

/// One data row of `pct list`. Slices borrow from the command output.
pub const PctListEntry = struct {
    vmid: []const u8,
    status: []const u8,
    lock: []const u8,
    name: []const u8,
};

/// Parses one line of `pct list`; returns null for the header and blank lines.
///
/// pct prints `"%-10s %-10s %-12s %-20s\n"` for VMID, Status, Lock and Name,
/// and Lock is an empty string unless the container is locked. Splitting on
/// whitespace gives three fields normally and four while a lock is held. The
/// fixed column offsets used before broke as soon as a value outgrew its
/// column (the "snapshot-delete" lock is 15 characters), and whitespace
/// tokenising without that rule read the lock as the name. Hostnames cannot
/// contain whitespace, so the name is always the last field.
pub fn parsePctListLine(line: []const u8) ?PctListEntry {
    var fields: [4][]const u8 = undefined;
    var count: usize = 0;
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    while (it.next()) |field| {
        if (count == fields.len) return null;
        fields[count] = field;
        count += 1;
    }
    if (count < 2) return null;
    // The header ("VMID Status Lock Name") and anything else without a numeric id
    _ = std.fmt.parseInt(u32, fields[0], 10) catch return null;

    return switch (count) {
        2 => .{ .vmid = fields[0], .status = fields[1], .lock = "", .name = "" },
        3 => .{ .vmid = fields[0], .status = fields[1], .lock = "", .name = fields[2] },
        else => .{ .vmid = fields[0], .status = fields[1], .lock = fields[2], .name = fields[3] },
    };
}

/// Returns the VMID of the container named `name` in `pct list` output,
/// borrowing from `output`.
pub fn findVmidByName(output: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const entry = parsePctListLine(line) orelse continue;
        if (std.mem.eql(u8, entry.name, name)) return entry.vmid;
    }
    return null;
}

/// The fields nexcage reads from `pct status <vmid> --verbose`, which prints
/// one "key: value" line per field. `pid` is the host PID of the container's
/// init, which pct takes from `lxc-info -p`; it is present only while the
/// container runs. Slices borrow from the command output.
pub const PctStatus = struct {
    status: ?[]const u8 = null,
    pid: ?std.posix.pid_t = null,
};

pub fn parsePctStatus(output: []const u8) PctStatus {
    var result = PctStatus{};
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = line[0..colon];
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.mem.eql(u8, key, "status")) {
            result.status = value;
        } else if (std.mem.eql(u8, key, "pid")) {
            const pid = std.fmt.parseInt(std.posix.pid_t, value, 10) catch continue;
            if (pid > 0) result.pid = pid;
        }
    }
    return result;
}

/// Whether a cgroup.procs list -- one PID per line -- holds `pid`.
fn listsPid(procs: []const u8, pid: std.posix.pid_t) bool {
    var lines = std.mem.tokenizeScalar(u8, procs, '\n');
    while (lines.next()) |line| {
        const listed = std.fmt.parseInt(std.posix.pid_t, line, 10) catch continue;
        if (listed == pid) return true;
    }
    return false;
}

test "listsPid finds a whole PID in a cgroup.procs list, never a part of one" {
    try std.testing.expect(listsPid("1\n4242\n77\n", 4242));
    try std.testing.expect(listsPid("4242", 4242));
    try std.testing.expect(!listsPid("42420\n", 4242));
    try std.testing.expect(!listsPid("14242\n", 4242));
    try std.testing.expect(!listsPid("", 4242));
    try std.testing.expect(!listsPid("\n\n", 4242));
}

/// What a search of a cgroup tree for a PID found.
const CgroupSearch = struct {
    found: bool = false,
    /// Cgroups passed over because they could not be opened or read
    unread: usize = 0,
    /// Why the first of them could not be
    first_error: ?anyerror = null,

    fn passOver(self: *CgroupSearch, err: anyerror) void {
        if (self.unread == 0) self.first_error = err;
        self.unread += 1;
    }
};

/// Whether a cgroup.procs anywhere under `root` lists `pid`.
///
/// The tree is not nexcage's to trust. ns/ is delegated to the container,
/// whose root can make cgroups there that cannot be read -- a threaded
/// cgroup's cgroup.procs fails with EOPNOTSUPP -- and systemd and nested
/// containers remove theirs while the walk goes on (ENOENT, ENODEV). Failing
/// on one of those made kill fail on a live container, so a tenant could stop
/// an engine's TERM-then-KILL from landing. A cgroup that cannot be opened or
/// read is passed over as one that lists no process instead: a threaded
/// cgroup's processes are listed in its domain's cgroup.procs, which is read
/// too, and a removed one has none. Passing over can only turn a match into
/// "not running"; it never lets a signal reach a process outside the tree.
fn cgroupTreeLists(allocator: std.mem.Allocator, root: std.fs.Dir, pid: std.posix.pid_t) !CgroupSearch {
    var search = CgroupSearch{};
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (true) {
        // The Walker leaves out a directory it could not open and drops one
        // it could not list, so the next call carries on with the rest.
        const entry = walker.next() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                search.passOver(err);
                continue;
            },
        } orelse return search;
        if (entry.kind != .file or !std.mem.eql(u8, entry.basename, "cgroup.procs")) continue;
        const procs = entry.dir.readFileAlloc(allocator, entry.basename, 16 * 1024 * 1024) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                search.passOver(err);
                continue;
            },
        };
        defer allocator.free(procs);
        if (listsPid(procs, pid)) {
            search.found = true;
            return search;
        }
    }
}

test "cgroupTreeLists passes over a cgroup it cannot read, and still finds the PID" {
    const allocator = std.testing.allocator;
    const posix = std.posix;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    // The init's cgroup, as systemd in a container has it
    try tmp.dir.makePath("ns/init.scope");
    try tmp.dir.writeFile(.{ .sub_path = "ns/init.scope/cgroup.procs", .data = "1\n4242\n" });
    // A cgroup.procs whose read fails, as a threaded cgroup's does: here one
    // longer than the walk reads
    try tmp.dir.makePath("ns/t");
    {
        const long = try tmp.dir.createFile("ns/t/cgroup.procs", .{});
        defer long.close();
        try long.setEndPos(16 * 1024 * 1024 + 1);
    }
    // and cgroups that cannot be opened: a chain deeper than the file
    // descriptors left to the walk, which a tenant can make as well
    {
        var chain = std.ArrayListUnmanaged(u8){};
        defer chain.deinit(allocator);
        try chain.appendSlice(allocator, "ns/d");
        for (0..64) |_| try chain.appendSlice(allocator, "/d");
        try tmp.dir.makePath(chain.items);
    }

    // The lowest free descriptor, and a few above it: the walk holds one per
    // level it is in
    const old_limit = try posix.getrlimit(.NOFILE);
    const lowest = try posix.dup(tmp.dir.fd);
    posix.close(lowest);
    try posix.setrlimit(.NOFILE, .{ .cur = @intCast(lowest + 16), .max = old_limit.max });
    const absent = cgroupTreeLists(allocator, tmp.dir, 999);
    const present = cgroupTreeLists(allocator, tmp.dir, 4242);
    try posix.setrlimit(.NOFILE, old_limit);

    // Every cgroup is visited when the PID is in none, whatever the order
    const a = try absent;
    try std.testing.expect(!a.found);
    try std.testing.expect(a.unread >= 2);
    try std.testing.expect((try present).found);
}

pub const PveVersion = struct {
    major: u32,
    minor: u32,
};

/// Reads the Proxmox VE major.minor version from `pveversion -v` output, or
/// from the single `pve-manager/X.Y.Z/...` line plain `pveversion` prints.
pub fn parsePveVersion(output: []const u8) ?PveVersion {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const rest = if (std.mem.startsWith(u8, line, "proxmox-ve:"))
            std.mem.trimLeft(u8, line["proxmox-ve:".len..], " \t")
        else if (std.mem.indexOf(u8, line, "pve-manager/")) |i|
            line[i + "pve-manager/".len ..]
        else
            continue;
        if (parseMajorMinor(rest)) |version| return version;
    }
    return null;
}

/// "9.1.0 (running kernel: ...)", "8.4.1/2a5fa54a" or "9.0-3" -> major, minor
fn parseMajorMinor(text: []const u8) ?PveVersion {
    const end = std.mem.indexOfAny(u8, text, " /(") orelse text.len;
    var parts = std.mem.tokenizeAny(u8, text[0..end], ".-");
    const major = std.fmt.parseInt(u32, parts.next() orelse return null, 10) catch return null;
    const minor = std.fmt.parseInt(u32, parts.next() orelse return null, 10) catch return null;
    return .{ .major = major, .minor = minor };
}

pub const PveClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Get Proxmox VE version using pveversion command
    pub fn getProxmoxVeVersion(self: *const Self) !?[]const u8 {
        const args = [_][]const u8{ "pveversion", "-v" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return null;

        const version = parsePveVersion(res.stdout) orelse return null;
        return try std.fmt.allocPrint(self.allocator, "{d}.{d}", .{ version.major, version.minor });
    }

    /// Check if Proxmox VE version is >= 9.1 (supports OCI Registry pull)
    pub fn supportsOciRegistryPull(self: *const Self) !bool {
        const version_str = try self.getProxmoxVeVersion();
        if (version_str) |ver| {
            defer self.allocator.free(ver);
            const dot_idx = std.mem.indexOfScalar(u8, ver, '.') orelse return false;
            const major_str = ver[0..dot_idx];
            const minor_str = ver[dot_idx + 1 ..];
            const major = std.fmt.parseInt(u32, major_str, 10) catch return false;
            const minor = std.fmt.parseInt(u32, minor_str, 10) catch return false;
            return major > 9 or (major == 9 and minor >= 1);
        }
        return false;
    }

    /// Get Proxmox node name (hostname)
    pub fn getNodeName(self: *const Self) ![]const u8 {
        const args = [_][]const u8{"hostname"};
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        if (res.exit_code != 0) return error.NodeNameDetectionFailed;
        const node_name = std.mem.trim(u8, res.stdout, " \t\r\n");
        return try self.allocator.dupe(u8, node_name);
    }

    /// The volid of the template a pull of `reference` into `storage` writes,
    /// when the storage already holds it; null when it does not. What `create`
    /// asks before it pulls: an image already there is what a container engine
    /// would use too, and `pull` is the explicit fetch.
    ///
    /// Only that exact file counts. This used to take the first template whose
    /// name merely contained the image's last path component and its tag, so
    /// docker.io/library/debian:12 was answered with Proxmox's own
    /// debian-12-standard system template, redis:7 with redis_7.2.4.tar or with
    /// a file someone else had uploaded, and an image from one registry with a
    /// same-named one pulled from another.
    pub fn findTemplate(self: *const Self, allocator: std.mem.Allocator, node: []const u8, storage: []const u8, reference: []const u8) !?[]u8 {
        const volid = try self.pullVolid(allocator, storage, reference, null);
        errdefer allocator.free(volid);
        if (try self.holdsTemplate(allocator, node, storage, volid)) return volid;
        allocator.free(volid);
        return null;
    }

    /// Pull an OCI image into a storage on a node, and answer with the volid
    /// of the template it wrote.
    ///
    /// nexcage names the file rather than leaving it to Proxmox: `filename`
    /// when the caller gave one, else `pulledTemplateName` of the reference,
    /// so the answer is exactly <storage>:vztmpl/<name>.tar once the storage
    /// lists it, and that file or an error. This used to list the storage
    /// before and after the pull and take whatever had appeared. A listing that
    /// failed once made every template already there look new, and a file
    /// another pull, an upload or a bundle create wrote meanwhile was taken
    /// for this one; either way `create` built the container from it and
    /// exited 0.
    ///
    /// There is no credential parameter on this endpoint, so a private registry
    /// cannot be authenticated here. The caller is told rather than left to
    /// wonder why a pull fails.
    pub fn pullTemplate(
        self: *const Self,
        allocator: std.mem.Allocator,
        node: []const u8,
        storage: []const u8,
        reference: []const u8,
        filename: ?[]const u8,
    ) ![]u8 {
        const volid = try self.pullVolid(allocator, storage, reference, filename);
        errdefer allocator.free(volid);
        // The file name pvesh is given: the volid's, without the ".tar"
        // Proxmox adds to it.
        const name = volid[storage.len + ":vztmpl/".len .. volid.len - ".tar".len];

        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage/{s}/oci-registry-pull", .{ node, storage });
        defer self.allocator.free(path);
        const args = [_][]const u8{ "pvesh", "create", path, "--reference", reference, "--filename", name };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        // Proxmox will not write over a file that is there: the handler dies
        // with "refusing to override existing file", and pvesh exits with
        // whatever errno Perl holds at that point (25 in practice). Under the
        // name derived from the reference, that file is this reference pulled
        // before, as far as the storage can say, and it is the answer. A name
        // the caller chose says nothing about what the file holds, so there
        // it is an error, not a pull that quietly did not happen.
        const already_there = res.exit_code != 0 and
            std.mem.indexOf(u8, res.stderr, "refusing to override existing file") != null;
        if (already_there and filename != null) {
            if (self.logger) |log| log.err("{s} is already on {s}, and a pull does not write over it; it may hold any image. Remove it first (nexcage rmi {s}) or give another --filename", .{ volid, storage, volid }) catch {};
            return core.Error.OperationFailed;
        }
        if (res.exit_code != 0 and !already_there) {
            if (self.logger) |log| reportPullFailure(log, reference, storage, node, volid, pullFailureReason(res.stdout, res.stderr));
            return core.Error.OperationFailed;
        }

        if (try self.holdsTemplate(allocator, node, storage, volid)) {
            if (already_there) {
                if (self.logger) |log| log.info("{s} is already on {s} as {s}; not pulled again", .{ reference, storage, volid }) catch {};
            }
            return volid;
        }

        // pvesh exits 0 when the pull task it ran failed (#309): the reason is
        // in its output, and nothing reached the storage.
        if (self.logger) |log| reportPullFailure(log, reference, storage, node, volid, pullFailureReason(res.stdout, res.stderr));
        return core.Error.OperationFailed;
    }

    /// <storage>:vztmpl/<name>.tar, the volid a pull of `reference` writes:
    /// `filename` when one was given, else the name derived from the
    /// reference. The storage goes into pvesh paths, so it is checked here,
    /// before anything is asked of Proxmox (see templateVolidStorage).
    fn pullVolid(self: *const Self, allocator: std.mem.Allocator, storage: []const u8, reference: []const u8, filename: ?[]const u8) ![]u8 {
        if (!isStorageId(storage)) {
            if (self.logger) |log| log.err("'{s}' is not a Proxmox storage name: a letter, then letters, digits, '-', '_' or '.', and a letter or digit last", .{storage}) catch {};
            return core.Error.InvalidInput;
        }
        if (filename) |f| {
            // Proxmox normalises the name it is given (anything outside
            // letters, digits, '.', '_' and '-' becomes '_', and everything up
            // to a '/' goes). A name it would change is refused rather than
            // guessed at, because the volid has to be known exactly.
            if (!isPlainFileName(f)) {
                if (self.logger) |log| log.err("--filename '{s}': letters, digits, '.', '_' and '-' only, not starting with '.' or '-', not ending in '.', without '..', at most {d} characters; Proxmox adds .tar", .{ f, max_pull_name }) catch {};
                return core.Error.InvalidInput;
            }
            // `create` takes the file under a reference's derived name for
            // that reference, so a name of that shape is not given by hand:
            // `pull ghcr.io/someone/redis:7 --filename <the name of
            // docker.io/library/redis:7>` made `create docker.io/library/redis:7`
            // start ghcr.io's image.
            if (hasDerivedShape(f)) {
                if (self.logger) |log| log.err("--filename '{s}' ends in '-' and 16 hex digits, the shape of the name nexcage gives a pull for its reference; leave --filename out to get that name, or choose another", .{f}) catch {};
                return core.Error.InvalidInput;
            }
            return std.fmt.allocPrint(allocator, "{s}:vztmpl/{s}.tar", .{ storage, f });
        }
        const name = try pulledTemplateName(allocator, reference);
        defer allocator.free(name);
        return std.fmt.allocPrint(allocator, "{s}:vztmpl/{s}.tar", .{ storage, name });
    }

    /// Whether `storage` on `node` lists exactly `volid`. A storage that
    /// cannot be listed is an error, never a "no": read as an empty storage,
    /// it once made a pull take a template that was there all along for the
    /// one it had just written.
    fn holdsTemplate(self: *const Self, allocator: std.mem.Allocator, node: []const u8, storage: []const u8, volid: []const u8) !bool {
        var out = std.ArrayListUnmanaged(Template){};
        defer {
            for (out.items) |*t| t.deinit();
            out.deinit(allocator);
        }
        try self.appendTemplatesOf(allocator, &out, node, storage, false, .fail);
        for (out.items) |t| {
            if (std.mem.eql(u8, t.volid, volid)) return true;
        }
        return false;
    }

    /// Remove a template from the storage it is on.
    ///
    /// The volid names its own storage, so there is nothing to guess. Two things
    /// are checked first, because a delete that reports success without deleting
    /// anything is the worst answer this command can give: that the template is
    /// there at all, and whether the storage is shared -- on a shared storage
    /// the file goes for every node at once, and the caller should know that
    /// before it happens rather than after.
    pub fn removeTemplate(self: *const Self, allocator: std.mem.Allocator, node: []const u8, volid: []const u8) !bool {
        // Before any pvesh call: the volid goes into the delete's path whole.
        const storage = templateVolidStorage(volid) orelse {
            if (self.logger) |log| {
                log.err("a template is named <storage>:vztmpl/<file>, the file in letters, digits, '.', '_' and '-' without '..', got '{s}'. A template named otherwise is removed on its node (pveam remove)", .{volid}) catch {};
            }
            return core.Error.InvalidInput;
        };

        // Is it there, and is that storage shared?
        var shared = false;
        var present = false;
        {
            const stores = try self.templateStorages(node);
            defer {
                for (stores) |st| self.allocator.free(st.name);
                self.allocator.free(stores);
            }
            var known_storage = false;
            for (stores) |st| {
                if (!std.mem.eql(u8, st.name, storage)) continue;
                known_storage = true;
                shared = st.shared;
            }
            if (!known_storage) {
                if (self.logger) |log| {
                    log.err("node {s} has no storage called '{s}'", .{ node, storage }) catch {};
                }
                return core.Error.NotFound;
            }

            present = try self.holdsTemplate(allocator, node, storage, volid);
        }

        if (!present) {
            if (self.logger) |log| {
                log.err("node {s} does not have the template '{s}'; nothing was removed", .{ node, volid }) catch {};
            }
            return core.Error.NotFound;
        }

        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage/{s}/content/{s}", .{ node, storage, volid });
        defer self.allocator.free(path);
        const args = [_][]const u8{ "pvesh", "delete", path };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| {
                log.err("removing {s} from {s} on {s} failed: {s}", .{ volid, storage, node, std.mem.trim(u8, res.stderr, " \t\r\n") }) catch {};
            }
            return self.mapPctError(res.stderr);
        }

        return shared;
    }

    /// Ask the cluster for the next free VMID.
    ///
    /// This replaces a hash of the container name, which could land on a VMID
    /// already used by a VM (only `pct list` was checked) or by a container on
    /// another node. Names still resolve through `pct list`, so nothing relied
    /// on the VMID being derivable from the name.
    pub fn nextVmid(self: *const Self) ![]u8 {
        const args = [_][]const u8{ "pvesh", "get", "/cluster/nextid" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| log.err("pvesh get /cluster/nextid failed: {s}", .{std.mem.trim(u8, res.stderr, " \t\r\n")}) catch {};
            return core.Error.OperationFailed;
        }

        const vmid = std.mem.trim(u8, res.stdout, " \t\r\n\"");
        _ = std.fmt.parseInt(u32, vmid, 10) catch {
            if (self.logger) |log| log.err("Unexpected VMID from pvesh: '{s}'", .{vmid}) catch {};
            return core.Error.OperationFailed;
        };
        return try self.allocator.dupe(u8, vmid);
    }

    /// Check if VMID already exists in Proxmox
    pub fn vmidExists(self: *const Self, vmid: []const u8) !bool {
        const args = [_][]const u8{ "pct", "list" };
        const res = common.runCommand(self.allocator, self.logger, &args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return false;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            const entry = parsePctListLine(line) orelse continue;
            if (std.mem.eql(u8, entry.vmid, vmid)) return true;
        }
        return false;
    }

    /// A /cluster/resources entry is a container rather than a virtual machine.
    /// The listing is asked for with `--type vm`, which covers both, and each
    /// entry says which it is.
    fn isLxcEntry(obj: std.json.ObjectMap) bool {
        const t = obj.get("type") orelse return false;
        return t == .string and std.mem.eql(u8, t.string, "lxc");
    }

    /// Where a container is in the cluster, and whether that is this host.
    ///
    /// `pct` only ever sees the node it runs on, so resolving a name through
    /// `pct list` answers for one host and silently says "not found" for a
    /// container that exists on another. The cluster's own view is
    /// /cluster/resources, which any node answers for all of them.
    ///
    /// `local` is what decides how everything else runs: `pct` for a container
    /// here, the API for one elsewhere, and a refusal for the three things that
    /// reach into the container's processes from the host, which no API offers.
    pub const Location = struct {
        allocator: std.mem.Allocator,
        vmid: []u8,
        node: []u8,
        local: bool,
        /// The container's name when it was found, or null when the listing
        /// had none to give -- a container on another node that the cluster
        /// has no report for (Pick.unnamed), which only its VMID can have
        /// found. What `confirm` checks the container against, and the name
        /// nexcage keeps its state under, whatever the caller typed.
        name: ?[]u8,

        /// The node to address through the API, or null when `pct` will do.
        pub fn remote(self: *const Location) ?[]const u8 {
            return if (self.local) null else self.node;
        }

        pub fn deinit(self: *Location) void {
            self.allocator.free(self.vmid);
            self.allocator.free(self.node);
            if (self.name) |n| self.allocator.free(n);
        }
    };

    /// Which of `containers` an identifier names.
    ///
    /// A name is looked for first, across every entry, and a VMID only when no
    /// container has that name. One pass taking the first entry that matched
    /// either let a container *named* 1000 lose to the one with VMID 1000
    /// whenever the listing put that one first -- and Proxmox sorts VMIDs as
    /// strings, so "1000" comes before "150". Two containers with the name is
    /// no answer at all: which of them came first was the listing's choice,
    /// and acting on it destroyed another node's container as readily as the
    /// one meant.
    ///
    /// `unnamed` is nothing matching while the listing has a container it
    /// gives no name, the first of them: that one may be the container asked
    /// for. /cluster/resources takes a container's name from its node's last
    /// report (PVE::API2Tools::extract_vm_stats), which a container made a
    /// few seconds ago does not have yet, and which pmxcfs drops five minutes
    /// after a node goes down, so every container there loses its name. Taken
    /// for `none`, it let delete --force forget nexcage's record of a
    /// container that was still running, unnamed, on another node.
    pub const Pick = union(enum) { none, one: usize, many, unnamed: usize };

    /// What an identifier may be taken for. nexcage's record of a container
    /// proves it made one with that name, and nothing about a VMID: a record
    /// of `250` whose container was destroyed outside nexcage let a lookup
    /// fall through to VMID 250, a container nexcage never made, and delete
    /// --force destroyed it. So a command that found the container through
    /// its record looks for the name alone, and a VMID is looked for only
    /// when the caller asked for the Proxmox backend with --runtime lxc.
    pub const By = enum { name, name_or_vmid };

    pub fn pick(containers: []const core.ContainerInfo, name_or_vmid: []const u8, by: By) Pick {
        // An empty id names nothing. It matched every container the listing
        // had no name for: `--runtime lxc delete --force ''`, an unset shell
        // variable, destroyed one.
        if (name_or_vmid.len == 0) return .none;
        var found: ?usize = null;
        for (containers, 0..) |c, i| {
            if (!std.mem.eql(u8, c.name, name_or_vmid)) continue;
            if (found) |f| {
                if (!std.mem.eql(u8, containers[f].id, c.id)) return .many;
            } else found = i;
        }
        if (found) |f| return .{ .one = f };
        if (by == .name_or_vmid) {
            for (containers, 0..) |c, i| {
                if (std.mem.eql(u8, c.id, name_or_vmid)) return .{ .one = i };
            }
        }
        for (containers, 0..) |c, i| {
            if (c.name.len == 0) return .{ .unnamed = i };
        }
        return .none;
    }

    /// The one container among `containers` that `name_or_vmid` names, or
    /// NotFound when no container has it. A name more than one container has
    /// is refused, and the message names each of them; so is a miss while a
    /// container has no name to compare, which is never NotFound.
    pub fn choose(self: *const Self, containers: []const core.ContainerInfo, name_or_vmid: []const u8, by: By) !usize {
        switch (pick(containers, name_or_vmid, by)) {
            .one => |i| return i,
            .none => return core.Error.NotFound,
            .unnamed => |i| {
                if (self.logger) |log| {
                    var more: usize = 0;
                    for (containers[i + 1 ..]) |c| {
                        if (c.name.len == 0) more += 1;
                    }
                    var buf: [64]u8 = undefined;
                    const others = if (more == 0) "" else std.fmt.bufPrint(&buf, ", and so may {d} more", .{more}) catch "";
                    log.err("no container in the cluster's listing is named '{s}', but CT {s} on {s} has no name there and may be that one{s}. Proxmox names a container from its node's reports, which one made seconds ago does not have yet and a node down for five minutes no longer sends. Nothing was done; try again once the cluster names it", .{ name_or_vmid, containers[i].id, containers[i].node orelse "this host", others }) catch {};
                }
                return core.Error.OperationFailed;
            },
            .many => {
                if (self.logger) |log| {
                    var buf: [512]u8 = undefined;
                    var w = std.Io.Writer.fixed(&buf);
                    var first = true;
                    for (containers) |c| {
                        if (!std.mem.eql(u8, c.name, name_or_vmid)) continue;
                        w.print("{s}VMID {s} on {s}", .{ if (first) "" else ", ", c.id, c.node orelse "this host" }) catch break;
                        first = false;
                    }
                    log.err("'{s}' names more than one container: {s}. Nothing was done; address one by its VMID, with --runtime lxc", .{ name_or_vmid, w.buffered() }) catch {};
                }
                return core.Error.OperationFailed;
            },
        }
    }

    /// Find a container by name or VMID anywhere in the cluster.
    ///
    /// Both sources are read: the cluster's listing, which knows every node,
    /// and `pct list`, which is current for this one -- the listing is a cache
    /// pvestatd refreshes every few seconds, so a container created a moment
    /// ago is missing from it and one whose VMID was just reused can still
    /// carry the old name there. `list` merges the two, this host's word
    /// winning for its own containers. A cluster that cannot be asked is an
    /// error that says why; it used to be a quiet fallback to `pct list`,
    /// which answers for this host alone, so a container on another node was
    /// "not found" and create's cluster-wide check passed a name another node
    /// had.
    pub fn locate(self: *const Self, allocator: std.mem.Allocator, name_or_vmid: []const u8, by: By) !Location {
        const all = try self.list(self.allocator);
        defer {
            for (all) |*c| c.deinit();
            self.allocator.free(all);
        }
        const c = all[try self.choose(all, name_or_vmid, by)];

        const here = self.getNodeName() catch null;
        defer if (here) |h| self.allocator.free(h);
        // `pct list` rows carry this host's name, or none when it is unknown
        const local = if (c.node) |n| (if (here) |h| std.mem.eql(u8, h, n) else false) else true;
        const node = c.node orelse here orelse "localhost";

        const vmid_owned = try allocator.dupe(u8, c.id);
        errdefer allocator.free(vmid_owned);
        const node_owned = try allocator.dupe(u8, node);
        errdefer allocator.free(node_owned);
        return Location{
            .allocator = allocator,
            .vmid = vmid_owned,
            .node = node_owned,
            .local = local,
            .name = if (c.name.len > 0) try allocator.dupe(u8, c.name) else null,
        };
    }

    /// Refuse unless the container at `loc` is still the one that was found.
    ///
    /// A command finds a container by name and acts on its VMID a moment
    /// later -- behind a 60-second shutdown, a minute later -- and Proxmox
    /// hands a destroyed container's VMID to the very next one created:
    /// /cluster/nextid answers the lowest free one. A retried `delete --force
    /// web-old` destroyed web-new that way, which had taken web-old's VMID in
    /// between. So the hostname is read again from the container's own config,
    /// which is current, right before any command acts on the container:
    /// stops, destroys or starts it, signals, freezes or thaws it, runs a
    /// command in it, or changes its limits or its snapshots.
    /// Found by VMID with no name to compare, the VMID is what was asked for.
    pub fn confirm(self: *const Self, loc: *const Location) !void {
        const expected = loc.name orelse return;
        return self.confirmName(loc.vmid, loc.remote(), expected);
    }

    /// confirm, for a container known by its VMID and the name it was made
    /// under rather than by a Location: the one a failed create or run is
    /// undoing. Its VMID can change hands the same way while pct start runs.
    pub fn confirmName(self: *const Self, vmid: []const u8, node: ?[]const u8, expected: []const u8) !void {
        const now = try self.hostnameOf(vmid, node);
        defer self.allocator.free(now);
        if (std.mem.eql(u8, now, expected)) return;
        if (self.logger) |log| log.err("CT {s} is no longer '{s}' but '{s}': the container was replaced after nexcage found it, and nothing was done to it", .{ vmid, expected, now }) catch {};
        return core.Error.NotFound;
    }

    /// A container's hostname, from its config: `pct config` here, the node's
    /// API elsewhere. Proxmox calls a container without one CT<vmid> in its
    /// listings, and so does this.
    fn hostnameOf(self: *const Self, vmid: []const u8, node: ?[]const u8) ![]u8 {
        if (node) |n| {
            const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{s}/config", .{ n, vmid });
            defer self.allocator.free(path);
            const args = [_][]const u8{ "pvesh", "get", path, "--output-format", "json" };
            const res = try common.runCommand(self.allocator, self.logger, &args);
            defer {
                self.allocator.free(res.stdout);
                self.allocator.free(res.stderr);
            }
            if (res.exit_code != 0) {
                if (self.logger) |log| log.err("pvesh get {s} failed: {s}", .{ path, std.mem.trim(u8, res.stderr, " \t\r\n") }) catch {};
                return errorFor(res.stderr);
            }
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch |err| {
                if (err == error.OutOfMemory) return core.Error.OutOfMemory;
                if (self.logger) |log| log.err("the config of CT {s} on {s} is not JSON: {s}", .{ vmid, n, @errorName(err) }) catch {};
                return core.Error.OperationFailed;
            };
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("hostname")) |h| {
                    if (h == .string and h.string.len > 0) return try self.allocator.dupe(u8, h.string);
                }
            }
        } else {
            const args = [_][]const u8{ "pct", "config", vmid };
            const res = try common.runCommand(self.allocator, self.logger, &args);
            defer {
                self.allocator.free(res.stdout);
                self.allocator.free(res.stderr);
            }
            if (res.exit_code != 0) return self.mapPctError(res.stderr);
            var lines = std.mem.splitScalar(u8, res.stdout, '\n');
            while (lines.next()) |line| {
                if (!std.mem.startsWith(u8, line, "hostname:")) continue;
                const h = std.mem.trim(u8, line["hostname:".len..], " \t\r");
                if (h.len > 0) return try self.allocator.dupe(u8, h);
            }
        }
        return try std.fmt.allocPrint(self.allocator, "CT{s}", .{vmid});
    }

    /// /cluster/resources, parsed: every guest on every node. Whatever keeps
    /// it from being read is an error naming the cause -- the listing is
    /// read with a cap that fits a large cluster, and a failure is logged with
    /// what pvesh said -- because every caller used to take any failure for
    /// "ask this host instead".
    fn clusterResources(self: *const Self) !std.json.Parsed(std.json.Value) {
        // `--type vm`, not `--type lxc`: the API's enumeration is vm, storage,
        // node, sdn, and it rejects anything else with "400 Parameter
        // verification failed". Containers come back under vm with their own
        // `type` field set to lxc, which is what isLxcEntry reads.
        //
        // This was `--type lxc` when cluster support was written, so every
        // lookup failed and fell back to `pct list` -- which works for a
        // container on this host and answers "not found" for one anywhere else,
        // the exact thing the cluster support was for. The simulator's fake
        // accepted the wrong flag, so the tests agreed with the mistake.
        const args = [_][]const u8{ "pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json" };
        const res = common.runCommandMax(self.allocator, self.logger, &args, common.cluster_max_output) catch |err| {
            if (self.logger) |log| log.err("the cluster's listing of its containers (pvesh get /cluster/resources) could not be read", .{}) catch {};
            return err;
        };
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| log.err("the cluster's listing of its containers (pvesh get /cluster/resources) failed: {s}", .{std.mem.trim(u8, res.stderr, " \t\r\n")}) catch {};
            return listingError(res.stderr);
        }
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch |err| {
            if (err == error.OutOfMemory) return core.Error.OutOfMemory;
            if (self.logger) |log| log.err("the cluster's listing of its containers (pvesh get /cluster/resources) is not JSON: {s}", .{@errorName(err)}) catch {};
            return core.Error.OperationFailed;
        };
        if (parsed.value != .array) {
            parsed.deinit();
            if (self.logger) |log| log.err("the cluster's listing of its containers (pvesh get /cluster/resources) is not a list", .{}) catch {};
            return core.Error.OperationFailed;
        }
        return parsed;
    }

    /// A template as a storage lists it.
    pub const Template = struct {
        allocator: std.mem.Allocator,
        node: []u8,
        storage: []u8,
        volid: []u8,
        format: []u8,
        size: u64,
        /// A shared storage shows the same files on every node, so this one is
        /// reported once rather than once per node.
        shared: bool,

        pub fn deinit(self: *Template) void {
            self.allocator.free(self.node);
            self.allocator.free(self.storage);
            self.allocator.free(self.volid);
            self.allocator.free(self.format);
        }
    };

    /// The nodes of the cluster. The caller frees each name and the slice.
    ///
    /// A standalone host answers /nodes with itself, so a failure here is a
    /// failure, reported with pvesh's words. It used to be answered with this
    /// host alone, and `images` then listed one node's templates as if they
    /// were the cluster's.
    pub fn nodes(self: *const Self, allocator: std.mem.Allocator) ![][]u8 {
        const args = [_][]const u8{ "pvesh", "get", "/nodes", "--output-format", "json" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| log.err("the cluster's list of nodes (pvesh get /nodes) failed: {s}", .{std.mem.trim(u8, res.stderr, " \t\r\n")}) catch {};
            return errorFor(res.stderr);
        }
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch |err| {
            if (err == error.OutOfMemory) return core.Error.OutOfMemory;
            if (self.logger) |log| log.err("the cluster's list of nodes (pvesh get /nodes) is not JSON: {s}", .{@errorName(err)}) catch {};
            return core.Error.OperationFailed;
        };
        defer parsed.deinit();

        var out = std.ArrayListUnmanaged([]u8){};
        errdefer {
            for (out.items) |n| allocator.free(n);
            out.deinit(allocator);
        }
        if (parsed.value == .array) {
            for (parsed.value.array.items) |item| {
                if (item != .object) continue;
                const n = item.object.get("node") orelse continue;
                if (n != .string) continue;
                try out.append(allocator, try allocator.dupe(u8, n.string));
            }
        }
        if (out.items.len == 0) {
            if (self.logger) |log| log.err("the cluster's list of nodes (pvesh get /nodes) names none", .{}) catch {};
            return core.Error.OperationFailed;
        }
        return try out.toOwnedSlice(allocator);
    }

    /// Every container template the cluster can see.
    ///
    /// A shared storage carries the same files on every node, so it is listed
    /// from the first node that reports it and skipped afterwards -- otherwise
    /// one template on a shared storage appears once per node and a person
    /// counting them gets a number that means nothing.
    pub fn listTemplates(self: *const Self, allocator: std.mem.Allocator, only_node: ?[]const u8) ![]Template {
        const node_names = try self.nodes(allocator);
        defer {
            for (node_names) |n| allocator.free(n);
            allocator.free(node_names);
        }

        var out = std.ArrayListUnmanaged(Template){};
        errdefer {
            for (out.items) |*t| t.deinit();
            out.deinit(allocator);
        }
        // Owned copies: the storage entries are freed at the end of each node's
        // turn, so keeping their names here would leave this comparing freed
        // memory -- which does not crash, it just stops deduplicating, and the
        // shared storage gets listed once per node again.
        var seen_shared = std.ArrayListUnmanaged([]u8){};
        defer {
            for (seen_shared.items) |name| self.allocator.free(name);
            seen_shared.deinit(self.allocator);
        }

        // A node nobody has heard of is an error, not an empty list. Silence
        // there reads as "that node has no templates", which is a different
        // thing and sends someone looking in the wrong place.
        if (only_node) |want| {
            var known = false;
            for (node_names) |n| {
                if (std.mem.eql(u8, n, want)) known = true;
            }
            if (!known) {
                if (self.logger) |log| {
                    var names = std.ArrayListUnmanaged(u8){};
                    defer names.deinit(self.allocator);
                    for (node_names, 0..) |n, i| {
                        if (i > 0) try names.appendSlice(self.allocator, ", ");
                        try names.appendSlice(self.allocator, n);
                    }
                    log.err("no node called '{s}' in this cluster; it has: {s}", .{ want, names.items }) catch {};
                }
                return core.Error.NotFound;
            }
        }

        for (node_names) |node| {
            if (only_node) |want| if (!std.mem.eql(u8, want, node)) continue;

            // One node that cannot answer fails the listing, and the message
            // names it: a listing without that node's templates would read as
            // "it has none".
            const stores = self.templateStorages(node) catch |err| {
                if (only_node == null) {
                    if (self.logger) |log| log.err("the cluster's templates cannot all be listed while node {s} does not answer; 'images --node <node>' lists the others one at a time", .{node}) catch {};
                }
                return err;
            };
            defer {
                for (stores) |st| {
                    self.allocator.free(st.name);
                }
                self.allocator.free(stores);
            }

            for (stores) |st| {
                if (st.shared) {
                    var already = false;
                    for (seen_shared.items) |name| {
                        if (std.mem.eql(u8, name, st.name)) already = true;
                    }
                    if (already) continue;
                    try seen_shared.append(self.allocator, try self.allocator.dupe(u8, st.name));
                }
                try self.appendTemplatesOf(allocator, &out, node, st.name, st.shared, .skip);
            }
        }

        return try out.toOwnedSlice(allocator);
    }

    const StorageEntry = struct { name: []u8, shared: bool };

    /// The storages of a node that can hold container templates.
    fn templateStorages(self: *const Self, node: []const u8) ![]StorageEntry {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage", .{node});
        defer self.allocator.free(path);
        const args = [_][]const u8{ "pvesh", "get", path, "--output-format", "json" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| log.err("node {s} could not be asked for its storages: {s}", .{ node, std.mem.trim(u8, res.stderr, " \t\r\n") }) catch {};
            return errorFor(res.stderr);
        }

        // A parse error is not one of core.Error's, and the command registry
        // casts into that set: it would end the process with a panic.
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch |err| {
            if (err == error.OutOfMemory) return core.Error.OutOfMemory;
            if (self.logger) |log| log.err("node {s} listed its storages in something other than JSON: {s}", .{ node, @errorName(err) }) catch {};
            return core.Error.OperationFailed;
        };
        defer parsed.deinit();
        if (parsed.value != .array) return core.Error.OperationFailed;

        var out = std.ArrayListUnmanaged(StorageEntry){};
        errdefer {
            for (out.items) |e| self.allocator.free(e.name);
            out.deinit(self.allocator);
        }
        for (parsed.value.array.items) |item| {
            if (item != .object) continue;
            const content = if (item.object.get("content")) |c| (if (c == .string) c.string else "") else "";
            if (std.mem.indexOf(u8, content, "vztmpl") == null) continue;
            const name = if (item.object.get("storage")) |n| (if (n == .string) n.string else "") else "";
            if (name.len == 0) continue;
            const shared = if (item.object.get("shared")) |sh| switch (sh) {
                .bool => |b| b,
                .integer => |i| i != 0,
                else => false,
            } else false;
            try out.append(self.allocator, .{ .name = try self.allocator.dupe(u8, name), .shared = shared });
        }
        return try out.toOwnedSlice(self.allocator);
    }

    /// What to do with a storage that cannot be listed. Choosing a template
    /// needs the answer, so there it is an error. `images` shows what the
    /// cluster has, and one offline mount should not hide every template in
    /// it, so there the storage is left out, with a warning that names it.
    const Unlisted = enum { fail, skip };

    fn appendTemplatesOf(
        self: *const Self,
        allocator: std.mem.Allocator,
        out: *std.ArrayListUnmanaged(Template),
        node: []const u8,
        storage: []const u8,
        shared: bool,
        when_unlisted: Unlisted,
    ) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage/{s}/content", .{ node, storage });
        defer self.allocator.free(path);
        const args = [_][]const u8{ "pvesh", "get", path, "--content", "vztmpl", "--output-format", "json" };
        // runCommand has said why it could not run pvesh
        const res = common.runCommand(self.allocator, self.logger, &args) catch |err| {
            if (when_unlisted == .skip) return;
            return err;
        };
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            return self.unlisted(when_unlisted, node, storage, std.mem.trim(u8, res.stderr, " \t\r\n"));
        }

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch {
            return self.unlisted(when_unlisted, node, storage, "the answer was not JSON");
        };
        defer parsed.deinit();
        if (parsed.value != .array) return self.unlisted(when_unlisted, node, storage, "the answer was not a list");

        for (parsed.value.array.items) |item| {
            if (item != .object) continue;
            const volid = if (item.object.get("volid")) |v| (if (v == .string) v.string else "") else "";
            if (volid.len == 0) continue;
            const format = if (item.object.get("format")) |f| (if (f == .string) f.string else "") else "";
            const size: u64 = if (item.object.get("size")) |sz| switch (sz) {
                .integer => |i| if (i < 0) 0 else @intCast(i),
                .float => |f| @intFromFloat(f),
                else => 0,
            } else 0;

            const node_copy = try allocator.dupe(u8, node);
            errdefer allocator.free(node_copy);
            const storage_copy = try allocator.dupe(u8, storage);
            errdefer allocator.free(storage_copy);
            const volid_copy = try allocator.dupe(u8, volid);
            errdefer allocator.free(volid_copy);
            const format_copy = try allocator.dupe(u8, format);
            errdefer allocator.free(format_copy);
            try out.append(allocator, .{
                .allocator = allocator,
                .node = node_copy,
                .storage = storage_copy,
                .volid = volid_copy,
                .format = format_copy,
                .size = size,
                .shared = shared,
            });
        }
    }

    fn unlisted(self: *const Self, when: Unlisted, node: []const u8, storage: []const u8, why: []const u8) !void {
        switch (when) {
            .fail => {
                if (self.logger) |log| log.err("storage {s} on {s} could not be listed: {s}", .{ storage, node, why }) catch {};
                return core.Error.OperationFailed;
            },
            .skip => {
                if (self.logger) |log| log.warn("storage {s} on {s} could not be listed, so its templates are not shown: {s}", .{ storage, node, why }) catch {};
            },
        }
    }

    /// Refuse early unless the target node can see the template.
    ///
    /// A storage named `local` is a different directory on every node, so a
    /// volid that exists here may simply not be there -- and the API's own
    /// answer for that arrives after a VMID has been taken. The message names
    /// the storages on that node which do hold templates, because the fix is
    /// usually to put the template on one of them.
    pub fn requireTemplateOnNode(self: *const Self, node: []const u8, volid: []const u8) !void {
        // The storage goes into a path on that node; see templateVolidStorage.
        const storage = templateVolidStorage(volid) orelse {
            if (self.logger) |log| {
                log.err("--node needs a template named as <storage>:vztmpl/<file>, the file in letters, digits, '.', '_' and '-' without '..', got '{s}'", .{volid}) catch {};
            }
            return core.Error.InvalidInput;
        };

        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage/{s}/content", .{ node, storage });
        defer self.allocator.free(path);
        const args = [_][]const u8{ "pvesh", "get", path, "--content", "vztmpl", "--output-format", "json" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| {
                log.err("node {s} has no storage '{s}' to take the template from: {s}", .{ node, storage, std.mem.trim(u8, res.stderr, " \t\r\n") }) catch {};
            }
            return core.Error.NotFound;
        }

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch {
            return core.Error.OperationFailed;
        };
        defer parsed.deinit();
        if (parsed.value == .array) {
            for (parsed.value.array.items) |item| {
                if (item != .object) continue;
                const v = item.object.get("volid") orelse continue;
                if (v == .string and std.mem.eql(u8, v.string, volid)) return;
            }
        }

        if (self.logger) |log| {
            log.err("node {s} does not have the template '{s}'. A storage called '{s}' is a different directory on each node unless it is shared; put the template there, or use a shared storage", .{ node, volid, storage }) catch {};
        }
        return core.Error.NotFound;
    }

    /// One call against /nodes/<node>/lxc/<vmid><sub>, which is how the cluster
    /// reaches a container that is not on this host. `pct` has no equivalent:
    /// it is a local tool by construction.
    fn nodeApi(self: *const Self, node: []const u8, vmid: []const u8, verb: []const u8, sub: []const u8, extra: []const []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{s}{s}", .{ node, vmid, sub });
        defer self.allocator.free(path);

        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);
        try args.appendSlice(self.allocator, &.{ "pvesh", verb, path });
        try args.appendSlice(self.allocator, extra);

        const res = try common.runCommand(self.allocator, self.logger, args.items);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| {
                log.err("pvesh {s} {s} failed: {s}", .{ verb, path, std.mem.trim(u8, res.stderr, " \t\r\n") }) catch {};
            }
            return self.mapPctError(res.stderr);
        }
    }

    /// Get VMID by container name
    pub fn getVmidByName(self: *const Self, name: []const u8) ![]u8 {
        const args = [_][]const u8{ "pct", "list" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        // A failing `pct list` is not "no such container": create would read
        // that as the name being free.
        if (res.exit_code != 0) return self.mapPctError(res.stderr);

        const vmid = findVmidByName(res.stdout, name) orelse return core.Error.NotFound;
        return try self.allocator.dupe(u8, vmid);
    }

    /// Map pct command errors to core errors
    pub fn mapPctError(self: *const Self, stderr: []const u8) core.Error {
        if (self.logger) |log| log.err("pct command failed: {s}", .{std.mem.trim(u8, stderr, " \t\r\n")}) catch {};
        return errorFor(stderr);
    }

    /// What a Proxmox tool's complaint means, for a caller that has already
    /// said which call it was.
    fn errorFor(stderr: []const u8) core.Error {
        const s = stderr;
        if (std.mem.indexOf(u8, s, "already exists") != null) return core.Error.OperationFailed;
        if (std.mem.indexOf(u8, s, "No such file or directory") != null or
            std.mem.indexOf(u8, s, "does not exist") != null or
            std.mem.indexOf(u8, s, "not found") != null) return core.Error.NotFound;
        if (std.mem.indexOf(u8, s, "Permission denied") != null) return core.Error.PermissionDenied;
        if (std.mem.indexOf(u8, s, "timeout") != null) return core.Error.Timeout;

        return core.Error.OperationFailed;
    }

    /// What a listing that failed means. Never NotFound, whatever the tool
    /// said: a listing that could not be read says nothing about any one
    /// container, and NotFound from a lookup is what create takes for "the
    /// name is free". errorFor reads "not found" or "No such file or
    /// directory" as a missing container, which is right for a call about one
    /// container -- and it let create past its cluster-wide check whenever
    /// the listing failed with those words.
    fn listingError(stderr: []const u8) core.Error {
        const err = errorFor(stderr);
        return if (err == core.Error.NotFound) core.Error.OperationFailed else err;
    }

    /// List containers across the cluster.
    ///
    /// `pct list` answers for the node it runs on and nothing else, so on a
    /// cluster it showed a fraction of what was there without saying so. The
    /// cluster's own listing carries the node, which is the column a person
    /// then needs to make sense of the rest. A cluster that cannot be listed
    /// is an error, not this host's list in its place: that was the same
    /// fraction, still without saying so.
    pub fn list(self: *const Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        const cluster = try self.clusterList(allocator);

        // The cluster's listing is a cached view: pvestatd refreshes it every
        // few seconds, so a container created a moment ago is in `pct list` and
        // not yet here. Returning only the cluster's answer made `nexcage list`
        // -- and `state`, which reads it -- miss a container that plainly
        // exists. This host's own containers are merged in, by VMID.
        const local = self.localList(allocator) catch |err| {
            for (cluster) |*c| c.deinit();
            self.allocator.free(cluster);
            return err;
        };
        defer {
            for (local) |*c| c.deinit();
            self.allocator.free(local);
        }

        var merged = std.ArrayListUnmanaged(core.ContainerInfo).fromOwnedSlice(cluster);
        errdefer {
            for (merged.items) |*c| c.deinit();
            merged.deinit(self.allocator);
        }
        // For a container on this host, `pct list` is the current answer and the
        // cluster's is a cache that can be seconds behind -- a container started
        // a moment ago is still "stopped" there. So a local entry replaces the
        // cluster's for the same VMID rather than being dropped as a duplicate,
        // which is what made `state` say stopped right after a successful start
        // while `list` said running. The name is replaced too: the cache keeps
        // a destroyed container's name for a VMID the next one has taken, and a
        // lookup of the old name found the new container. The cluster stays
        // authoritative for the one thing only it knows: which node a container
        // on another host is on.
        for (local) |*c| {
            var replaced = false;
            for (merged.items) |*m| {
                if (!std.mem.eql(u8, m.id, c.id)) continue;
                const status = try allocator.dupe(u8, c.status);
                allocator.free(m.status);
                m.status = status;
                if (c.name.len > 0) {
                    const name = try allocator.dupe(u8, c.name);
                    allocator.free(m.name);
                    m.name = name;
                }
                replaced = true;
            }
            if (replaced) continue;
            try merged.append(self.allocator, core.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, c.id),
                .name = try allocator.dupe(u8, c.name),
                .status = try allocator.dupe(u8, c.status),
                .backend_type = try allocator.dupe(u8, c.backend_type),
                .runtime = if (c.runtime) |rt| try allocator.dupe(u8, rt) else null,
                .node = if (c.node) |n| try allocator.dupe(u8, n) else null,
            });
        }
        return try merged.toOwnedSlice(self.allocator);
    }

    fn clusterList(self: *const Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        // `--type vm` and a filter, for the reason spelt out in clusterResources.
        const parsed = try self.clusterResources();
        defer parsed.deinit();

        var containers = std.ArrayListUnmanaged(core.ContainerInfo){};
        errdefer {
            for (containers.items) |*c| c.deinit();
            containers.deinit(self.allocator);
        }

        for (parsed.value.array.items) |item| {
            if (item != .object) continue;
            const obj = item.object;
            if (!isLxcEntry(obj)) continue;
            const vmid_num = switch (obj.get("vmid") orelse continue) {
                .integer => |i| i,
                .float => |f| @as(i64, @intFromFloat(f)),
                .string => |str| std.fmt.parseInt(i64, str, 10) catch continue,
                else => continue,
            };
            var vmid_buf: [24]u8 = undefined;
            const vmid_str = std.fmt.bufPrint(&vmid_buf, "{d}", .{vmid_num}) catch continue;
            // A container its node has not reported yet has no name here, and
            // nor does every container of a node down for five minutes: the
            // API takes the name from the node's last report (Pick.unnamed).
            // It stays empty. The VMID used to be put in its place,
            // and then a container really named after its VMID -- `create
            // --name 100` on a fresh host gets VMID 100 -- passed for one
            // without a name: found "by VMID", it had no record written or
            // removed and no identity to confirm before it was destroyed.
            const name = if (obj.get("name")) |n| (if (n == .string) n.string else "") else "";
            const status = if (obj.get("status")) |st| (if (st == .string) st.string else "unknown") else "unknown";
            const node = if (obj.get("node")) |n| (if (n == .string) n.string else "") else "";

            try containers.append(self.allocator, core.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, vmid_str),
                .name = try allocator.dupe(u8, name),
                .status = try allocator.dupe(u8, status),
                .backend_type = try allocator.dupe(u8, "proxmox-lxc"),
                .runtime = try allocator.dupe(u8, "pct"),
                .node = if (node.len > 0) try allocator.dupe(u8, node) else null,
            });
        }
        return try containers.toOwnedSlice(self.allocator);
    }

    fn localList(self: *const Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        const here = self.getNodeName() catch null;
        defer if (here) |h| self.allocator.free(h);
        const args = [_][]const u8{ "pct", "list" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| log.err("this host's listing of its containers (pct list) failed: {s}", .{std.mem.trim(u8, res.stderr, " \t\r\n")}) catch {};
            return listingError(res.stderr);
        }

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        var containers = std.ArrayListUnmanaged(core.ContainerInfo){};
        errdefer {
            for (containers.items) |*c| c.deinit();
            containers.deinit(self.allocator);
        }

        while (lines.next()) |line| {
            const entry = parsePctListLine(line) orelse continue;
            try containers.append(self.allocator, core.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, entry.vmid),
                .name = try allocator.dupe(u8, entry.name),
                .status = try allocator.dupe(u8, entry.status),
                .backend_type = try allocator.dupe(u8, "proxmox-lxc"),
                .runtime = try allocator.dupe(u8, "pct"),
                .node = if (here) |h| try allocator.dupe(u8, h) else null,
            });
        }
        return try containers.toOwnedSlice(self.allocator);
    }

    /// Start container. `node` is null for a container on this host, where
    /// `pct` is used; for one elsewhere in the cluster the API does the same
    /// thing through the node that owns it.
    pub fn start(self: *const Self, vmid: []const u8, node: ?[]const u8) !void {
        if (node) |n| return self.nodeApi(n, vmid, "create", "/status/start", &.{});
        const args = [_][]const u8{ "pct", "start", vmid };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return self.mapPctError(res.stderr);
    }

    /// Stop container: a clean shutdown, forced once the timeout expires.
    /// `pct stop` kills every process at once, which is what `kill` is for.
    pub fn stop(self: *const Self, vmid: []const u8, node: ?[]const u8) !void {
        if (node) |n| return self.nodeApi(n, vmid, "create", "/status/shutdown", &.{ "--timeout", "60", "--forceStop", "1" });
        const args = [_][]const u8{ "pct", "shutdown", vmid, "--timeout", "60", "--forceStop", "1" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return self.mapPctError(res.stderr);
    }

    /// Destroy container
    pub fn delete(self: *const Self, vmid: []const u8, node: ?[]const u8) !void {
        if (node) |n| return self.nodeApi(n, vmid, "delete", "", &.{});
        const args = [_][]const u8{ "pct", "destroy", vmid };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return self.mapPctError(res.stderr);
    }

    /// Host PID of the container's init, or null when it is not running.
    ///
    /// This used to run `cat /proc/1/stat` inside the container with
    /// `pct exec`, which reads back the PID in the container's own namespace
    /// (always 1) and fails wherever lxc-attach cannot run.
    pub fn initPid(self: *const Self, vmid: []const u8, node: ?[]const u8) !?std.posix.pid_t {
        // A container on another node has an init, but its PID is a number in
        // that node's process table and means nothing here. Reporting it would
        // be worse than reporting none: `kill` would signal whatever holds that
        // PID on this host.
        if (node) |n| {
            if (self.logger) |log| {
                log.debug("CT {s} runs on {s}; its init PID is not a PID on this host", .{ vmid, n }) catch {};
            }
            return null;
        }
        const args = [_][]const u8{ "pct", "status", vmid, "--verbose" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return self.mapPctError(res.stderr);
        return parsePctStatus(res.stdout).pid;
    }

    /// Freeze or thaw a container through the cgroup freezer.
    ///
    /// `pct suspend` is **not** this: on a container it runs `lxc-checkpoint -s`,
    /// which dumps the processes to disk through CRIU and takes the container
    /// down -- measured on a Proxmox VE 9.2 host, where it also simply failed.
    /// The runtime-spec's paused means the processes stop where they are and
    /// stay in memory, and that is the cgroup freezer.
    ///
    /// Proxmox puts a container's processes under
    /// `/sys/fs/cgroup/lxc/<vmid>/ns/...`, and writing to the freezer of
    /// `lxc/<vmid>` freezes all of it: `cgroup.events` then reports `frozen 1`.
    ///
    /// **`pct status` keeps saying `running` for a frozen container** -- Proxmox
    /// has no notion of this state. `nexcage state` reads the freezer itself, so
    /// it says `paused`.
    pub fn freeze(self: *const Self, vmid: []const u8, on: bool, node: ?[]const u8) !void {
        if (node) |n| {
            if (self.logger) |log| {
                log.err("CT {s} runs on {s}: freezing is done through that host's cgroup filesystem, and the Proxmox API has no call for it. Run nexcage on {s}", .{ vmid, n, n }) catch {};
            }
            return core.Error.UnsupportedOperation;
        }

        const path = try std.fmt.allocPrint(self.allocator, "/sys/fs/cgroup/lxc/{s}/cgroup.freeze", .{vmid});
        defer self.allocator.free(path);

        const file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch |err| {
            if (self.logger) |log| {
                switch (err) {
                    error.FileNotFound => log.err("no cgroup freezer for CT {s} at {s}: the container is not running, or this host is not on cgroup v2", .{ vmid, path }) catch {},
                    error.AccessDenied => log.err("cannot write {s}: freezing a container needs root", .{path}) catch {},
                    else => log.err("cannot open {s}: {s}", .{ path, @errorName(err) }) catch {},
                }
            }
            return switch (err) {
                error.FileNotFound => core.Error.NotFound,
                error.AccessDenied => core.Error.PermissionDenied,
                else => core.Error.OperationFailed,
            };
        };
        defer file.close();

        file.writeAll(if (on) "1" else "0") catch |err| {
            if (self.logger) |log| log.err("writing {s} failed: {s}", .{ path, @errorName(err) }) catch {};
            return core.Error.OperationFailed;
        };
    }

    /// `update` in pct's terms. runc's vocabulary is the runtime-spec's --
    /// bytes, a quota over a period, cgroup v1 shares -- and pct's is MiB,
    /// cores and a cgroup v2 weight; the arithmetic is in core/resources.zig.
    /// A setting Proxmox has no option for is an error naming it, because a
    /// limit that was asked for and silently not applied is the worst outcome
    /// an update can have. Local containers go through `pct set`; one on
    /// another node through `pvesh set /nodes/<node>/lxc/<vmid>/config`, which
    /// takes the same options.
    pub fn setResources(self: *const Self, vmid: []const u8, values: []const core.types.ResourceUpdate, node: ?[]const u8) !void {
        var args = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (args.items) |a| self.allocator.free(a);
            args.deinit(self.allocator);
        }
        // pct's --swap is swap alone and runc's --memory-swap memory plus
        // swap, so a swap without a memory limit needs the container's own.
        var current_memory: ?i64 = null;
        if (hasSetting(values, "memory", "swap") and !hasSetting(values, "memory", "limit")) {
            current_memory = try self.currentMemoryBytes(vmid, node);
        }
        try self.resourceOptions(values, current_memory, &args);
        if (args.items.len == 0) return;

        if (node) |n| return self.nodeApi(n, vmid, "set", "/config", args.items);

        var argv = std.ArrayListUnmanaged([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.appendSlice(self.allocator, &.{ "pct", "set", vmid });
        try argv.appendSlice(self.allocator, args.items);
        const out = try common.runCommand(self.allocator, self.logger, argv.items);
        defer {
            self.allocator.free(out.stdout);
            self.allocator.free(out.stderr);
        }
        if (out.exit_code != 0) {
            if (self.logger) |log| log.err("pct set {s} failed: {s}", .{ vmid, std.mem.trim(u8, out.stderr, " \t\r\n") }) catch {};
            return self.mapPctError(out.stderr);
        }
    }

    /// The limits in pct's options, appended to `args` (each string owned by
    /// it): what `update` says to `pct set` and `create` to `pct create`
    /// (#308). `memory_fallback` is the memory limit in bytes when `values`
    /// has a swap but no memory of its own. A value pct cannot say as it was
    /// asked is refused, naming the setting, rather than said as a different
    /// limit.
    pub fn resourceOptions(self: *const Self, values: []const core.types.ResourceUpdate, memory_fallback: ?i64, args: *std.ArrayListUnmanaged([]const u8)) !void {
        const res = core.resources;
        var memory_bytes: ?i64 = null;
        var swap_total: ?i64 = null;
        var quota: ?i64 = null;
        var period: ?i64 = null;
        for (values) |v| {
            const num: i64 = if (v.numeric) std.fmt.parseInt(i64, v.value, 10) catch {
                if (self.logger) |log| log.err("{s}.{s}: '{s}' is not a number", .{ v.section, v.name, v.value }) catch {};
                return core.Error.InvalidInput;
            } else 0;
            if (isSetting(v, "memory", "limit")) {
                if (num < 0) {
                    if (self.logger) |log| log.err("--memory -1: Proxmox has no unlimited memory for a container; give a size", .{}) catch {};
                    return core.Error.UnsupportedOperation;
                }
                memory_bytes = num;
                const mib = res.mibCeil(num) catch {
                    if (self.logger) |log| log.err("memory.limit (--memory) of {d} bytes is more than Proxmox can hold: it keeps MiB and works the bytes out again in 64 bits", .{num}) catch {};
                    return core.Error.InvalidInput;
                };
                // Raised to pct's least, 0 (runc's "leave it as it is") and
                // 4 MiB both became a limit of 16 MiB that nobody asked for.
                if (mib < res.min_memory_mib) {
                    if (self.logger) |log| log.err("memory.limit (--memory) of {d} bytes is less than the {d} MiB pct takes, and raised to that it would be a limit nobody asked for; give at least {d}M, or leave it out", .{ num, res.min_memory_mib, res.min_memory_mib }) catch {};
                    return core.Error.InvalidInput;
                }
                try pushOption(self.allocator, args, "--memory", "{d}", .{mib});
            } else if (isSetting(v, "memory", "swap")) {
                if (num < 0) {
                    if (self.logger) |log| log.err("--memory-swap -1: Proxmox has no unlimited swap for a container; give a size", .{}) catch {};
                    return core.Error.UnsupportedOperation;
                }
                swap_total = num;
            } else if (isSetting(v, "cpu", "quota")) {
                quota = num;
            } else if (isSetting(v, "cpu", "period")) {
                period = num;
            } else if (isSetting(v, "cpu", "shares")) {
                // 0 is runc's "leave it as it is" and became the lowest
                // weight; a negative number of shares is none at all.
                if (num <= 0) {
                    if (self.logger) |log| log.err("cpu.shares (--cpu-share) of {d} is no CPU weight: shares run from 2 to 262144, and 0 is runc's \"leave it as it is\", which pct cannot say; give a number of shares, or leave it out", .{num}) catch {};
                    return core.Error.InvalidInput;
                }
                try pushOption(self.allocator, args, "--cpuunits", "{d}", .{res.sharesToWeight(num)});
            } else {
                if (self.logger) |log| log.err("{s}.{s} has no Proxmox setting for a container: Proxmox knows memory, swap, cpulimit and cpuunits, so this backend takes --memory, --memory-swap, --cpu-quota/--cpu-period and --cpu-share", .{ v.section, v.name }) catch {};
                return core.Error.UnsupportedOperation;
            }
        }

        if (swap_total) |total| {
            // runc's --memory-swap is memory plus swap; pct's --swap is swap
            // alone. The difference needs the memory limit, from this call or
            // from the caller: the container's config, or create's default.
            const limit = memory_bytes orelse memory_fallback orelse return core.Error.InvalidInput;
            if (total < limit) {
                if (self.logger) |log| log.err("--memory-swap is memory plus swap, as runc means it, and {d} is less than the memory limit of {d}", .{ total, limit }) catch {};
                return core.Error.InvalidInput;
            }
            // total >= limit >= 0, so the difference cannot overflow; its
            // MiB, which Proxmox turns back into bytes, can be too many.
            const swap_mib = res.mibCeil(total - limit) catch {
                if (self.logger) |log| log.err("memory.swap (--memory-swap) of {d} bytes is more than Proxmox can hold: it keeps MiB and works the bytes out again in 64 bits", .{total}) catch {};
                return core.Error.InvalidInput;
            };
            try pushOption(self.allocator, args, "--swap", "{d}", .{swap_mib});
        }
        if (quota) |q| {
            var buf: [32]u8 = undefined;
            const p = period orelse 100000;
            const cores = res.cpulimit(&buf, q, p) catch |err| {
                if (self.logger) |log| switch (err) {
                    error.QuotaTooLarge => log.err("cpu.quota (--cpu-quota) of {d} over a period of {d} is more cores than pct takes", .{ q, p }) catch {},
                    error.QuotaTooSmall => log.err("cpu.quota (--cpu-quota) of {d} over a period of {d} is less than a hundredth of a core, the least Proxmox can set, and pct's cpulimit 0 would be no limit at all; give a larger quota, or -1 for no limit", .{ q, p }) catch {},
                    else => log.err("cpu.period (--cpu-period) must be positive", .{}) catch {},
                };
                return core.Error.InvalidInput;
            };
            try pushOption(self.allocator, args, "--cpulimit", "{s}", .{cores});
        } else if (period != null) {
            if (self.logger) |log| log.err("--cpu-period on its own changes nothing here: Proxmox has a CPU limit in cores, which is quota over period, so give --cpu-quota too", .{}) catch {};
            return core.Error.InvalidInput;
        }
    }

    fn hasSetting(values: []const core.types.ResourceUpdate, section: []const u8, name: []const u8) bool {
        for (values) |v| if (isSetting(v, section, name)) return true;
        return false;
    }

    fn isSetting(v: core.types.ResourceUpdate, section: []const u8, name: []const u8) bool {
        return std.mem.eql(u8, v.section, section) and std.mem.eql(u8, v.name, name);
    }

    fn pushOption(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged([]const u8), flag: []const u8, comptime fmt: []const u8, v: anytype) !void {
        try out.append(allocator, try allocator.dupe(u8, flag));
        try out.append(allocator, try std.fmt.allocPrint(allocator, fmt, v));
    }

    /// The container's memory limit in bytes, from its config: `pct config`
    /// here, the node's API elsewhere. pct's default is 512 MiB.
    fn currentMemoryBytes(self: *const Self, vmid: []const u8, node: ?[]const u8) !i64 {
        var mib: i64 = 512;
        if (node) |n| {
            const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{s}/config", .{ n, vmid });
            defer self.allocator.free(path);
            const args = [_][]const u8{ "pvesh", "get", path, "--output-format", "json" };
            const res = try common.runCommand(self.allocator, self.logger, &args);
            defer {
                self.allocator.free(res.stdout);
                self.allocator.free(res.stderr);
            }
            if (res.exit_code != 0) return self.mapPctError(res.stderr);
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch return core.Error.OperationFailed;
            defer parsed.deinit();
            if (parsed.value == .object) if (parsed.value.object.get("memory")) |m| if (m == .integer) {
                mib = m.integer;
            };
        } else {
            const args = [_][]const u8{ "pct", "config", vmid };
            const res = try common.runCommand(self.allocator, self.logger, &args);
            defer {
                self.allocator.free(res.stdout);
                self.allocator.free(res.stderr);
            }
            if (res.exit_code != 0) return self.mapPctError(res.stderr);
            var lines = std.mem.splitScalar(u8, res.stdout, '\n');
            while (lines.next()) |line| {
                if (std.mem.startsWith(u8, line, "memory: ")) {
                    mib = std.fmt.parseInt(i64, std.mem.trim(u8, line["memory: ".len..], " \t\r"), 10) catch mib;
                }
            }
        }
        // A size in bytes is what the swap is worked out from, so a config
        // whose MiB are past 64 bits of bytes, or below none, is an error
        // here rather than an overflow there.
        const bytes = std.math.mul(i64, mib, 1024 * 1024) catch -1;
        if (bytes < 0) {
            if (self.logger) |log| log.err("the config of CT {s} gives a memory of {d} MiB, which is no size in bytes that 64 bits hold", .{ vmid, mib }) catch {};
            return core.Error.OperationFailed;
        }
        return bytes;
    }

    /// Whether a container's processes are frozen, read from the cgroup itself.
    /// Null when there is no freezer to read -- a container that is not running,
    /// or a host that is not on cgroup v2.
    pub fn isFrozen(self: *const Self, vmid: []const u8) ?bool {
        const path = std.fmt.allocPrint(self.allocator, "/sys/fs/cgroup/lxc/{s}/cgroup.freeze", .{vmid}) catch return null;
        defer self.allocator.free(path);

        var buf: [16]u8 = undefined;
        const file = std.fs.cwd().openFile(path, .{}) catch return null;
        defer file.close();
        const n = file.readAll(&buf) catch return null;
        const value = std.mem.trim(u8, buf[0..n], " \t\r\n");
        if (value.len == 0) return null;
        return value[0] == '1';
    }

    /// Send a signal to the container's init from the host, as an OCI runtime
    /// does.
    ///
    /// This used to run `kill -s SIGNAL 1` inside the container through
    /// `pct exec`. The kernel drops a signal sent to a PID namespace's init
    /// from inside that namespace unless init handles it, SIGKILL included, so
    /// `kill SIGKILL` did nothing; it also needed a kill binary in the image.
    /// From the host, SIGKILL and SIGSTOP are always delivered.
    pub fn kill(self: *const Self, vmid: []const u8, signal: []const u8, node: ?[]const u8) !void {
        if (node) |n| {
            if (self.logger) |log| {
                log.err("CT {s} runs on {s}: a signal is sent to the container's init from the host, and the Proxmox API has no call for that. Run nexcage on {s}, or use stop and delete, which work from here", .{ vmid, n, n }) catch {};
            }
            return core.Error.UnsupportedOperation;
        }
        const signo = core.signals.parse(signal) orelse {
            if (self.logger) |log| log.err("unknown signal '{s}'", .{signal}) catch {};
            return core.Error.InvalidInput;
        };
        // null, not node: the refusal above means we are on the container's
        // own host by the time we get here.
        const pid = (try self.initPid(vmid, null)) orelse {
            if (self.logger) |log| log.err("CT {s} is not running", .{vmid}) catch {};
            return core.Error.OperationFailed;
        };

        // `pct status`, another process, read that PID a moment ago -- for a
        // perl tool, most of a second. The init can exit in between and its
        // PID go to an unrelated process, which kill(2) as root would hit.
        // A pidfd names one process for good: it is opened first, the PID is
        // then confirmed to be in the container's cgroup, and the signal goes
        // through the pidfd, so it reaches that process or none. A PID that
        // is not the container's any more means the container is not running.
        const linux = std.os.linux;
        const open_rc = linux.pidfd_open(pid, 0);
        switch (linux.E.init(open_rc)) {
            .SUCCESS => {},
            .SRCH => {
                if (self.logger) |log| log.err("CT {s} is not running: its init, PID {d}, has exited", .{ vmid, pid }) catch {};
                return core.Error.OperationFailed;
            },
            .NOSYS => {
                if (self.logger) |log| log.err("this kernel has no pidfd_open (Linux 5.3); nexcage sends a container a signal only through one", .{}) catch {};
                return core.Error.UnsupportedOperation;
            },
            else => |e| {
                if (self.logger) |log| log.err("pidfd_open for PID {d} (init of CT {s}) failed: {s}", .{ pid, vmid, @tagName(e) }) catch {};
                return core.Error.OperationFailed;
            },
        }
        const pidfd: std.posix.fd_t = @intCast(open_rc);
        defer std.posix.close(pidfd);

        if (!try self.inContainerCgroup(vmid, pid)) {
            if (self.logger) |log| log.err("CT {s} is not running: PID {d}, which pct status reported as its init, is not in the container's cgroup", .{ vmid, pid }) catch {};
            return core.Error.OperationFailed;
        }

        switch (linux.E.init(linux.pidfd_send_signal(pidfd, signo, null, 0))) {
            .SUCCESS => {},
            .SRCH => {
                if (self.logger) |log| log.err("CT {s} is not running: its init, PID {d}, has exited", .{ vmid, pid }) catch {};
                return core.Error.OperationFailed;
            },
            .PERM => {
                if (self.logger) |log| log.err("sending signal {d} to PID {d} (init of CT {s}) is not permitted", .{ signo, pid, vmid }) catch {};
                return core.Error.PermissionDenied;
            },
            else => |e| {
                if (self.logger) |log| log.err("sending signal {d} to PID {d} (init of CT {s}) failed: {s}", .{ signo, pid, vmid, @tagName(e) }) catch {};
                return core.Error.OperationFailed;
            },
        }
    }

    /// Whether `pid` is one of CT `vmid`'s processes: listed in a
    /// cgroup.procs anywhere under /sys/fs/cgroup/lxc/<vmid>/, where Proxmox
    /// puts them -- the init under ns/, and systemd's units below that, so
    /// the whole tree is looked through.
    fn inContainerCgroup(self: *const Self, vmid: []const u8, pid: std.posix.pid_t) !bool {
        // A VMID is a number, and nothing else may become part of the path
        for (vmid) |c| if (!std.ascii.isDigit(c)) return false;
        if (vmid.len == 0) return false;

        const root = try std.fmt.allocPrint(self.allocator, "/sys/fs/cgroup/lxc/{s}", .{vmid});
        defer self.allocator.free(root);
        var dir = std.fs.cwd().openDir(root, .{ .iterate = true }) catch |err| switch (err) {
            // A stopped container has no cgroup, and a stopping one's is
            // being removed
            error.FileNotFound, error.NoDevice => return false,
            else => {
                if (self.logger) |log| log.err("cannot read {s}: {s}", .{ root, @errorName(err) }) catch {};
                return core.Error.OperationFailed;
            },
        };
        defer dir.close();

        const search = try cgroupTreeLists(self.allocator, dir, pid);
        if (!search.found and search.unread > 0) {
            if (self.logger) |log| log.warn("{d} cgroups under {s} could not be read and were passed over, the first with {s}; PID {d} may be in one of them", .{ search.unread, root, @errorName(search.first_error.?), pid }) catch {};
        }
        return search.found;
    }

    /// Run a command inside the container with `pct exec`, and return the
    /// status it exited with.
    ///
    /// stdio is inherited rather than captured: an exec is a pipe between the
    /// caller and the process in the container, so output has to arrive as it
    /// is produced and must not be held to runCommand's 1 MB cap.
    pub fn exec(self: *const Self, vmid: []const u8, argv: []const []const u8, node: ?[]const u8) !u8 {
        if (node) |n| {
            if (self.logger) |log| {
                log.err("CT {s} runs on {s}: `pct exec` attaches to a container on the host it runs on, and the Proxmox API has no exec. Run nexcage on {s}", .{ vmid, n, n }) catch {};
            }
            return core.Error.UnsupportedOperation;
        }
        if ((try self.initPid(vmid, null)) == null) {
            if (self.logger) |log| log.err("CT {s} is not running", .{vmid}) catch {};
            return core.Error.OperationFailed;
        }

        // --keep-env 0: lxc-attach --clear-env, so the command starts from
        // LXC's default PATH, container=lxc and the container's own
        // lxc.environment. pct's default is to keep the environment, which
        // handed the command -- a binary from the image, running as the
        // container's root -- every variable of the shell or job that ran
        // nexcage: API tokens, cloud keys, SSH_AUTH_SOCK. Proxmox meant to
        // change that default in PVE 9 and has not (pct.pm's FIXME).
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);
        try args.appendSlice(self.allocator, &.{ "pct", "exec", vmid, "--keep-env", "0", "--" });
        try args.appendSlice(self.allocator, argv);

        var child = std.process.Child.init(args.items, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.spawn() catch |err| {
            if (err == error.FileNotFound) {
                if (self.logger) |log| log.err("'pct' not found in PATH; nexcage must run on a Proxmox VE host", .{}) catch {};
                return core.Error.UnsupportedOperation;
            }
            if (self.logger) |log| log.err("Failed to run 'pct exec': {s}", .{@errorName(err)}) catch {};
            return core.Error.OperationFailed;
        };
        const term = child.wait() catch |err| {
            if (self.logger) |log| log.err("waiting for 'pct exec' failed: {s}", .{@errorName(err)}) catch {};
            return core.Error.OperationFailed;
        };
        return switch (term) {
            .Exited => |code| @as(u8, @intCast(@abs(code))),
            // Killed by a signal: report it the way a shell does.
            .Signal => |sig| @as(u8, @intCast(128 +% @as(u32, @intCast(sig)) % 128)),
            else => 1,
        };
    }

    /// One of a container's snapshots, as the node's API lists them.
    pub const Snapshot = struct {
        allocator: std.mem.Allocator,
        name: []u8,
        /// Proxmox's note on it; empty when none was given.
        description: []u8,
        /// When it was taken, as an epoch second. Null for an entry the API
        /// gives no time for.
        snaptime: ?i64,
        /// The snapshot it was taken on top of, or null for the first.
        parent: ?[]u8,

        pub fn deinit(self: *Snapshot) void {
            self.allocator.free(self.name);
            self.allocator.free(self.description);
            if (self.parent) |p| self.allocator.free(p);
        }

        fn earlier(_: void, a: Snapshot, b: Snapshot) bool {
            return (a.snaptime orelse 0) < (b.snaptime orelse 0);
        }
    };

    /// Take a snapshot of the container's volumes. Proxmox holds those volumes
    /// and knows how to snapshot each kind of storage, so this is one `pct`
    /// call here and one API call for a container on another node; nothing
    /// is for nexcage to do but name the container. A storage that cannot
    /// snapshot -- a raw volume on a directory storage -- is pct's refusal,
    /// passed on with the one thing pct does not say: which storages can.
    pub fn snapshot(self: *const Self, vmid: []const u8, name: []const u8, description: ?[]const u8, node: ?[]const u8) !void {
        try checkSnapshotName(self.logger, name);
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);
        var path: ?[]u8 = null;
        defer if (path) |p| self.allocator.free(p);
        if (node) |n| {
            path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{s}/snapshot", .{ n, vmid });
            try args.appendSlice(self.allocator, &.{ "pvesh", "create", path.?, "--snapname", name });
        } else {
            try args.appendSlice(self.allocator, &.{ "pct", "snapshot", vmid, name });
        }
        if (description) |d| try args.appendSlice(self.allocator, &.{ "--description", d });
        try self.runSnapshotCommand(args.items);
    }

    /// Roll the container back to a snapshot. Proxmox stops a running
    /// container itself first, with a kill, and `start_after` is pct's own
    /// --start: bring it up again afterwards.
    pub fn rollback(self: *const Self, vmid: []const u8, name: []const u8, start_after: bool, node: ?[]const u8) !void {
        try checkSnapshotName(self.logger, name);
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);
        var path: ?[]u8 = null;
        defer if (path) |p| self.allocator.free(p);
        if (node) |n| {
            path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{s}/snapshot/{s}/rollback", .{ n, vmid, name });
            try args.appendSlice(self.allocator, &.{ "pvesh", "create", path.? });
        } else {
            try args.appendSlice(self.allocator, &.{ "pct", "rollback", vmid, name });
        }
        if (start_after) try args.appendSlice(self.allocator, &.{ "--start", "1" });
        try self.runSnapshotCommand(args.items);
    }

    /// Delete a snapshot. A name that is not there is pct's error, passed on.
    pub fn deleteSnapshot(self: *const Self, vmid: []const u8, name: []const u8, node: ?[]const u8) !void {
        try checkSnapshotName(self.logger, name);
        if (node) |n| {
            const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{s}/snapshot/{s}", .{ n, vmid, name });
            defer self.allocator.free(path);
            return self.runSnapshotCommand(&.{ "pvesh", "delete", path });
        }
        return self.runSnapshotCommand(&.{ "pct", "delsnapshot", vmid, name });
    }

    /// The container's snapshots, oldest first, from the node's API -- for a
    /// container here as for one elsewhere, because the API answers with
    /// names, times as numbers and parents, where `pct listsnapshot` prints a
    /// tree for a person, in the node's local time with no zone. The "current"
    /// entry the API adds, which marks where the container is now, is not a
    /// snapshot and is left out.
    pub fn listSnapshots(self: *const Self, allocator: std.mem.Allocator, vmid: []const u8, node: []const u8) ![]Snapshot {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc/{s}/snapshot", .{ node, vmid });
        defer self.allocator.free(path);
        const args = [_][]const u8{ "pvesh", "get", path, "--output-format", "json" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return self.mapPctError(res.stderr);
        return parseSnapshotList(allocator, res.stdout) catch |err| {
            if (self.logger) |log| log.err("the answer for {s} was not a snapshot list ({s}): {s}", .{ path, @errorName(err), std.mem.trim(u8, res.stdout, " \t\r\n") }) catch {};
            return core.Error.OperationFailed;
        };
    }

    /// Run one of the snapshot commands, `pct` or `pvesh`, and pass its
    /// refusal on. The one line added is for the storage that cannot
    /// snapshot, because pct names the format and not the fix.
    fn runSnapshotCommand(self: *const Self, args: []const []const u8) !void {
        const res = try common.runCommand(self.allocator, self.logger, args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code == 0) return;
        const err = self.mapPctError(res.stderr);
        if (std.mem.indexOf(u8, res.stderr, "can't snapshot this image format") != null or
            std.mem.indexOf(u8, res.stderr, "snapshot feature is not available") != null)
        {
            if (self.logger) |log| log.err("the container's rootfs is on a storage that cannot take snapshots: a raw volume on a directory storage cannot, and zfs, lvm-thin and qcow2 can", .{}) catch {};
        }
        return err;
    }

    /// Find an available template in Proxmox
    pub fn findAvailableTemplate(self: *const Self) ![]const u8 {
        const args = [_][]const u8{ "pveam", "list", "local" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return core.Error.NotFound;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (std.mem.indexOf(u8, trimmed, ".tar.zst") != null) {
                var it = std.mem.splitScalar(u8, trimmed, ' ');
                if (it.next()) |tmpl| {
                    if (std.mem.indexOf(u8, tmpl, ":vztmpl/") != null) {
                        return try self.allocator.dupe(u8, tmpl);
                    }
                    return try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}", .{tmpl});
                }
            }
        }
        return core.Error.NotFound;
    }
};

/// Formats a row exactly as pct does: printf "%-10s %-10s %-12s %-20s\n".
fn pctRow(buf: []u8, vmid: []const u8, status: []const u8, lock: []const u8, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s: <10} {s: <10} {s: <12} {s: <20}", .{ vmid, status, lock, name });
}

/// A pull's UPID without its node and its file, as PVE::UPID::encode writes it
/// for pvesh, which runs as root@pam. pstart takes 9 hex digits once a node
/// has been up for 497 days.
const pull_upid_rest = "UPID:" ++ ":00000000:000000000:00000000:ociregistrypull:" ++ ":root@pam:";

/// The longest node name: a node is named for its hostname, and the kernel
/// keeps 64 characters of one.
const max_node_name = 64;

/// The longest file name nexcage gives a pull, before the ".tar" Proxmox adds:
/// 127 characters. The file itself could have 255, but the pull runs as a
/// task, and Proxmox names the task's log for its UPID, which holds the node
/// and the file: /var/log/pve/tasks/<x>/<UPID>, one file name of 255 bytes at
/// most (pve-common, PVE/UPID.pm encode and open_log). Past that, pvesh fails
/// with "unable to create file ... File name too long" before anything is
/// pulled. This was sized for the file alone once, and a reference of 160
/// characters, written out whole, failed on a node whose name was 24.
const max_pull_name = 255 - pull_upid_rest.len - max_node_name - ".tar".len;

/// The file name nexcage pulls `reference` under, before the ".tar" Proxmox
/// adds: the whole reference -- registry, namespace, name and tag -- with every
/// character a template's file name cannot have turned into '_', then '-' and
/// the first 16 hex digits of the reference's SHA-256.
///
/// Proxmox's own name is the last path component and the tag, so
/// docker.io/library/redis:7 and ghcr.io/someone/redis:7 were both
/// redis_7.tar: the name could not say which image a file held, and the second
/// pull was refused as already there. The whole reference spelled out says it
/// to a person reading `images`. The digest says it to nexcage, because '/'
/// and ':' both becoming '_' still lets two references read the same
/// (a/b_c:1 and a_b/c:1), and because past 110 characters a reference is cut
/// here (see max_pull_name) while the digest covers all of it.
fn pulledTemplateName(allocator: std.mem.Allocator, reference: []const u8) ![]u8 {
    const readable = reference[0..@min(reference.len, max_pull_name - 17)];
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(reference, &digest, .{});
    const hex = std.fmt.bytesToHex(digest[0..8], .lower);

    const name = try allocator.alloc(u8, readable.len + 1 + hex.len);
    for (readable, 0..) |c, i| {
        // A leading '.' would hide the file from the storage's listing, a
        // leading '-' reads as an option, and ".." -- which a tag may hold --
        // is what `rmi` refuses in a volid. (Only an empty reference gives a
        // name that starts with the '-' below, and Proxmox refuses that
        // reference before it looks at the name.)
        const keep = isFileNameChar(c) and
            !(i == 0 and (c == '.' or c == '-')) and
            !(c == '.' and i > 0 and name[i - 1] == '.');
        name[i] = if (keep) c else '_';
    }
    name[readable.len] = '-';
    @memcpy(name[readable.len + 1 ..], &hex);
    return name;
}

/// Whether a file name ends the way pulledTemplateName ends one: '-' and 16
/// lower-case hex digits.
fn hasDerivedShape(name: []const u8) bool {
    if (name.len < 17 or name[name.len - 17] != '-') return false;
    for (name[name.len - 16 ..]) |c| {
        if (!(std.ascii.isDigit(c) or (c >= 'a' and c <= 'f'))) return false;
    }
    return true;
}

/// What Proxmox keeps of a template's file name: normalize_content_filename
/// turns every other character into '_'.
fn isFileNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '-';
}

/// A file name `pull --filename` may give: one Proxmox's normalisation leaves
/// as it is, so that the file is known to be exactly <name>.tar afterwards,
/// and one `rmi` takes.
fn isPlainFileName(name: []const u8) bool {
    if (name.len == 0 or name.len > max_pull_name) return false;
    if (name[0] == '.' or name[0] == '-') return false;
    // `rmi` refuses ".." in a volid, so a template is not named with it --
    // nor with a last '.', which the ".tar" Proxmox adds turns into "..".
    // "myredis." was pulled as myredis..tar, printed, and then refused by
    // `rmi` and `create --node`.
    if (std.mem.indexOf(u8, name, "..") != null or name[name.len - 1] == '.') return false;
    for (name) |c| {
        if (!isFileNameChar(c)) return false;
    }
    return true;
}

/// A storage ID as Proxmox's parse_id takes it: two characters at least, a
/// letter first, a letter or digit last, and letters, digits, '-', '_' or '.'
/// between.
fn isStorageId(id: []const u8) bool {
    if (id.len < 2) return false;
    if (!std.ascii.isAlphabetic(id[0]) or !std.ascii.isAlphanumeric(id[id.len - 1])) return false;
    for (id) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.')) return false;
    }
    return true;
}

/// The storage of a volid that is exactly <storage>:vztmpl/<file>, or null:
/// the storage a Proxmox storage ID, the file in the characters Proxmox gives
/// a template's file name and without "..". The volid and its storage go
/// into pvesh paths, and for a node other than this one pvesh passes the path
/// to that node's shell over ssh without quoting it -- the options it quotes,
/// the path it does not (pve-manager, PVE/CLI/pvesh.pm, proxy_handler).
fn templateVolidStorage(volid: []const u8) ?[]const u8 {
    const colon = std.mem.indexOfScalar(u8, volid, ':') orelse return null;
    const storage = volid[0..colon];
    const kind = ":vztmpl/";
    if (!isStorageId(storage) or !std.mem.startsWith(u8, volid[colon..], kind)) return null;
    const file = volid[colon + kind.len ..];
    if (file.len == 0 or std.mem.indexOf(u8, file, "..") != null) return null;
    for (file) |c| {
        if (!isFileNameChar(c)) return null;
    }
    return storage;
}

/// Proxmox's rule for a snapshot name, pve-snapshot-name in pve-common: the
/// pve-configid format, a letter and then letters, digits, '-' or '_', two to
/// 40 characters. "current" fits it, and is refused too: it is the API's name
/// for where the container is now, not a snapshot.
fn isSnapshotName(name: []const u8) bool {
    if (name.len < 2 or name.len > 40) return false;
    if (!std.ascii.isAlphabetic(name[0])) return false;
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '-' or c == '_')) return false;
    }
    return !std.mem.eql(u8, name, "current");
}

/// Refuse a snapshot name Proxmox would not take, before it reaches pct or a
/// pvesh path. Proxmox checks the name too, but on the way to another node
/// pvesh hands the path to that node's shell first (see templateVolidStorage),
/// so a name was a command there.
pub fn checkSnapshotName(logger: ?*core.LogContext, name: []const u8) core.Error!void {
    if (isSnapshotName(name)) return;
    if (logger) |log| {
        if (std.mem.eql(u8, name, "current")) {
            log.err("'current' is reserved: it is Proxmox's name for where the container is now, not a snapshot", .{}) catch {};
        } else {
            log.err("'{s}' is not a snapshot name Proxmox takes: a letter, then letters, digits, '-' or '_', 2 to 40 characters", .{name}) catch {};
        }
    }
    return core.Error.InvalidInput;
}

test "snapshot names as Proxmox takes them, and not 'current'" {
    for ([_][]const u8{ "before-upgrade_1", "xx", "Snap2", "a" ++ "b" ** 39, "Current" }) |ok| {
        try std.testing.expect(isSnapshotName(ok));
    }
    for ([_][]const u8{ "", "x", "current", "1abc", "-x", "_x", "a/b", "../a", "x;id;", "x y", "a.b", "a" ++ "b" ** 40 }) |bad| {
        try std.testing.expect(!isSnapshotName(bad));
    }
    try std.testing.expectError(core.Error.InvalidInput, checkSnapshotName(null, "x;touch${IFS}/root/pwn;"));
    try checkSnapshotName(null, "before");
}

test "a template volid is <storage>:vztmpl/<file> and nothing more" {
    try std.testing.expectEqualStrings("local", templateVolidStorage("local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst").?);
    try std.testing.expectEqualStrings("shared-rdma", templateVolidStorage("shared-rdma:vztmpl/docker.io_library_redis_7-a0ed741ac6ba1c57.tar").?);
    for ([_][]const u8{
        "not-a-volid",
        "local:vztmpl/",
        "local:iso/x.iso",
        "local:vztmpl/../../x.tar",
        "local:vztmpl/a/b.tar",
        "local:vztmpl/x..tar",
        "local:vztmpl/evil;id>pwn.tar.zst",
        "local:vztmpl/a b.tar",
        "x;id;:vztmpl/a.tar",
        ":vztmpl/a.tar",
    }) |bad| {
        try std.testing.expect(templateVolidStorage(bad) == null);
    }
}

test "storage IDs as Proxmox parses them" {
    try std.testing.expect(isStorageId("local"));
    try std.testing.expect(isStorageId("shared-rdma"));
    try std.testing.expect(isStorageId("nfs.backup_2"));
    try std.testing.expect(!isStorageId("l"));
    try std.testing.expect(!isStorageId("2local"));
    try std.testing.expect(!isStorageId("local-"));
    try std.testing.expect(!isStorageId("x;id;"));
    try std.testing.expect(!isStorageId("a/b"));
    try std.testing.expect(!isStorageId(""));
}

test "a pulled template is named for the whole reference, and two references never share a name" {
    const a = std.testing.allocator;
    const redis = try pulledTemplateName(a, "docker.io/library/redis:7");
    defer a.free(redis);
    // The digest is pinned: tests/sim derives the same name with sha256sum.
    try std.testing.expectEqualStrings("docker.io_library_redis_7-a0ed741ac6ba1c57", redis);
    try std.testing.expect(isPlainFileName(redis));

    const other = try pulledTemplateName(a, "ghcr.io/someone/redis:7");
    defer a.free(other);
    try std.testing.expectEqualStrings("ghcr.io_someone_redis_7-", other[0 .. other.len - 16]);

    // The same once '/' and ':' are '_', told apart by the digest
    const left = try pulledTemplateName(a, "a/b_c:1");
    defer a.free(left);
    const right = try pulledTemplateName(a, "a_b/c:1");
    defer a.free(right);
    try std.testing.expectEqualStrings(left[0 .. left.len - 16], right[0 .. right.len - 16]);
    try std.testing.expect(!std.mem.eql(u8, left, right));

    // Too long for a pull's task: cut, and still told apart
    const long_a = "registry.example/" ++ "x" ** 250 ++ ":1";
    const long_b = "registry.example/" ++ "x" ** 250 ++ ":2";
    const cut_a = try pulledTemplateName(a, long_a);
    defer a.free(cut_a);
    const cut_b = try pulledTemplateName(a, long_b);
    defer a.free(cut_b);
    try std.testing.expectEqual(@as(usize, 127), max_pull_name);
    try std.testing.expectEqual(max_pull_name, cut_a.len);
    try std.testing.expectEqualStrings("registry.example_" ++ "x" ** 93 ++ "-", cut_a[0 .. cut_a.len - 16]);
    try std.testing.expect(isPlainFileName(cut_a));
    try std.testing.expect(!std.mem.eql(u8, cut_a, cut_b));

    // The UPID of its pull, on a node with the longest name and with a
    // 9-digit pstart, is still one file name
    const upid = try std.fmt.allocPrint(a, "UPID:{s}:000700FD:10057F07B:6AC81A67:ociregistrypull:{s}.tar:root@pam:", .{ "n" ** max_node_name, cut_a });
    defer a.free(upid);
    try std.testing.expectEqual(@as(usize, 255), upid.len);

    // Nothing Proxmox would rewrite, hide or read as an option, and nothing
    // rmi would refuse
    const odd = try pulledTemplateName(a, "-x/y z@sha256:ab");
    defer a.free(odd);
    try std.testing.expectEqualStrings("_x_y_z_sha256_ab-", odd[0 .. odd.len - 16]);
    try std.testing.expect(isPlainFileName(odd));
    const dots = try pulledTemplateName(a, "registry.example/app:1...2");
    defer a.free(dots);
    try std.testing.expectEqualStrings("registry.example_app_1._.2-", dots[0 .. dots.len - 16]);
    try std.testing.expect(isPlainFileName(dots));
    const volid = try std.fmt.allocPrint(a, "local:vztmpl/{s}.tar", .{dots});
    defer a.free(volid);
    try std.testing.expect(templateVolidStorage(volid) != null);
}

test "a --filename is one Proxmox leaves as it is" {
    try std.testing.expect(isPlainFileName("redis-7"));
    try std.testing.expect(isPlainFileName("my_app.v2"));
    try std.testing.expect(!isPlainFileName(""));
    try std.testing.expect(!isPlainFileName("a/b"));
    try std.testing.expect(!isPlainFileName("redis:7"));
    try std.testing.expect(!isPlainFileName(".hidden"));
    try std.testing.expect(!isPlainFileName("-x"));
    try std.testing.expect(!isPlainFileName("a b"));
    try std.testing.expect(!isPlainFileName("a..b"));
    // Proxmox adds ".tar": "foo." would be foo..tar, which rmi refuses
    try std.testing.expect(!isPlainFileName("foo."));
    try std.testing.expect(isPlainFileName("x" ** max_pull_name));
    try std.testing.expect(!isPlainFileName("x" ** (max_pull_name + 1)));

    // What pull prints for a name it takes, rmi and create --node take
    for ([_][]const u8{ "redis-7", "my_app.v2", "a.b-c_d", "x" ** max_pull_name }) |ok| {
        try std.testing.expect(isPlainFileName(ok));
        const volid = try std.fmt.allocPrint(std.testing.allocator, "local:vztmpl/{s}.tar", .{ok});
        defer std.testing.allocator.free(volid);
        try std.testing.expect(templateVolidStorage(volid) != null);
    }

    // The shape of a derived name, which a --filename may not have
    try std.testing.expect(hasDerivedShape("docker.io_library_redis_7-a0ed741ac6ba1c57"));
    try std.testing.expect(hasDerivedShape("-0123456789abcdef"));
    try std.testing.expect(!hasDerivedShape("redis-7"));
    try std.testing.expect(!hasDerivedShape("app-0123456789abcde"));
    try std.testing.expect(!hasDerivedShape("app-0123456789ABCDEF"));
    try std.testing.expect(!hasDerivedShape("app_0123456789abcdef"));
    try std.testing.expect(!hasDerivedShape("app-0123456789abcdefg"));
}

/// Why a registry pull failed, from what pvesh printed. A pull task that
/// fails still lets pvesh exit 0; skopeo's own message, `level=fatal
/// msg="..."`, is on stdout, and stderr only says that `skopeo copy` failed.
/// The message says why, so it comes first.
fn pullFailureReason(stdout: []const u8, stderr: []const u8) ?[]const u8 {
    const tag = "level=fatal msg=\"";
    var lines = std.mem.splitBackwardsScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        const at = std.mem.indexOf(u8, line, tag) orelse continue;
        const start = at + tag.len;
        const end = std.mem.lastIndexOfScalar(u8, line, '"') orelse line.len;
        if (end > start) return line[start..end];
    }
    const rest = std.mem.trim(u8, stderr, " \t\r\n");
    return if (rest.len > 0) rest else null;
}

/// A registry that turned the request away for want of a login, in the words
/// registries and skopeo use for it.
fn isLoginRefusal(reason: []const u8) bool {
    for ([_][]const u8{ "unauthorized", "authentication required", "denied" }) |word| {
        if (std.ascii.indexOfIgnoreCase(reason, word) != null) return true;
    }
    return false;
}

/// The registry of a reference, as `skopeo login` names it: what comes before
/// the first slash when that looks like a host, else docker.io.
fn registryOf(reference: []const u8) []const u8 {
    const slash = std.mem.indexOfScalar(u8, reference, '/') orelse return "docker.io";
    const first = reference[0..slash];
    if (std.mem.indexOfAny(u8, first, ".:") != null or std.mem.eql(u8, first, "localhost")) return first;
    return "docker.io";
}

/// Proxmox's pull runs skopeo with no --authfile, and skopeo reads root's
/// auth file on the node that pulls (#309). A refused login says where it
/// goes; the file under /run is skopeo's default and gone after a reboot.
fn reportPullFailure(log: *core.LogContext, reference: []const u8, storage: []const u8, node: []const u8, volid: []const u8, reason: ?[]const u8) void {
    const why = reason orelse {
        log.err("the pull of {s} reported success but {s} on {s} does not hold {s}", .{ reference, storage, node, volid }) catch {};
        return;
    };
    log.err("pulling {s} into {s} on {s} failed: {s}", .{ reference, storage, node, why }) catch {};
    if (isLoginRefusal(why)) {
        log.err("for a registry that needs a login, run as root on {s}: skopeo login --authfile /root/.config/containers/auth.json {s} (docs/INSTALL.md)", .{ node, registryOf(reference) }) catch {};
    }
}

test "a failed pull's reason is skopeo's message from stdout, then stderr" {
    const out =
        \\time="2026-10-08T22:34:16Z" level=fatal msg="initializing source docker://busybox:1.36: unable to retrieve auth token: invalid username/password: unauthorized: incorrect username or password"
        \\UPID:nexcage-e2e:000700FD:0057F07B:6AC81A67:ociregistrypull:busybox_1.36.tar:root@pam:
        \\
    ;
    const err = "command 'skopeo copy docker://docker.io/library/busybox:1.36 oci-archive:/x.tmp' failed: exit code 1\n";
    const why = pullFailureReason(out, err).?;
    try std.testing.expect(std.mem.startsWith(u8, why, "initializing source docker://busybox:1.36:"));
    try std.testing.expect(std.mem.endsWith(u8, why, "incorrect username or password"));
    try std.testing.expect(isLoginRefusal(why));

    try std.testing.expectEqualStrings("command 'skopeo copy x' failed: exit code 1", pullFailureReason("UPID:x\n", "command 'skopeo copy x' failed: exit code 1\n").?);
    try std.testing.expect(pullFailureReason("UPID:x\n", " \n") == null);
    try std.testing.expect(!isLoginRefusal("manifest unknown"));
}

test "the registry a login is for" {
    try std.testing.expectEqualStrings("docker.io", registryOf("busybox:1.36"));
    try std.testing.expectEqualStrings("docker.io", registryOf("library/busybox:1.36"));
    try std.testing.expectEqualStrings("docker.io", registryOf("docker.io/acme/app:1"));
    try std.testing.expectEqualStrings("ghcr.io", registryOf("ghcr.io/acme/app:1"));
    try std.testing.expectEqualStrings("registry.local:5000", registryOf("registry.local:5000/app"));
    try std.testing.expectEqualStrings("localhost", registryOf("localhost/app"));
}

test "parsePctListLine reads an unlocked container" {
    var buf: [128]u8 = undefined;
    const entry = parsePctListLine(try pctRow(&buf, "101", "running", "", "web-1")).?;
    try std.testing.expectEqualStrings("101", entry.vmid);
    try std.testing.expectEqualStrings("running", entry.status);
    try std.testing.expectEqualStrings("", entry.lock);
    try std.testing.expectEqualStrings("web-1", entry.name);
}

test "parsePctListLine does not read a lock as the name" {
    var buf: [128]u8 = undefined;
    const entry = parsePctListLine(try pctRow(&buf, "102", "stopped", "backup", "db-1")).?;
    try std.testing.expectEqualStrings("backup", entry.lock);
    try std.testing.expectEqualStrings("db-1", entry.name);
}

test "parsePctListLine survives a lock wider than its column" {
    var buf: [128]u8 = undefined;
    const entry = parsePctListLine(try pctRow(&buf, "103", "stopped", "snapshot-delete", "cache-1")).?;
    try std.testing.expectEqualStrings("103", entry.vmid);
    try std.testing.expectEqualStrings("snapshot-delete", entry.lock);
    try std.testing.expectEqualStrings("cache-1", entry.name);
}

test "parsePctListLine skips the header and blank lines" {
    var buf: [128]u8 = undefined;
    try std.testing.expect(parsePctListLine(try pctRow(&buf, "VMID", "Status", "Lock", "Name")) == null);
    try std.testing.expect(parsePctListLine("") == null);
    try std.testing.expect(parsePctListLine("   \r") == null);
}

test "findVmidByName matches whole names only" {
    const output =
        \\VMID       Status     Lock         Name
        \\101        running                 web-1
        \\102        stopped    backup       web-10
        \\1000       stopped                 db
        \\
    ;
    try std.testing.expectEqualStrings("101", findVmidByName(output, "web-1").?);
    try std.testing.expectEqualStrings("102", findVmidByName(output, "web-10").?);
    try std.testing.expectEqualStrings("1000", findVmidByName(output, "db").?);
    try std.testing.expect(findVmidByName(output, "web") == null);
    try std.testing.expect(findVmidByName(output, "backup") == null);
}

fn testEntry(vmid: []const u8, name: []const u8, node: []const u8) core.ContainerInfo {
    return .{ .allocator = std.testing.allocator, .id = vmid, .name = name, .status = "stopped", .backend_type = "proxmox-lxc", .node = node };
}

test "a name wins over a VMID, whichever the listing puts first" {
    // Proxmox lists VMIDs in string order, so 1000 comes before 150
    const rows = [_]core.ContainerInfo{ testEntry("1000", "db-prod", "pve"), testEntry("150", "1000", "pve") };
    try std.testing.expectEqual(PveClient.Pick{ .one = 1 }, PveClient.pick(&rows, "1000", .name_or_vmid));
    try std.testing.expectEqual(PveClient.Pick{ .one = 0 }, PveClient.pick(&rows, "db-prod", .name_or_vmid));
    // a VMID no container is named after still finds its container
    try std.testing.expectEqual(PveClient.Pick{ .one = 1 }, PveClient.pick(&rows, "150", .name_or_vmid));
    try std.testing.expectEqual(PveClient.Pick.none, PveClient.pick(&rows, "web", .name_or_vmid));
}

test "a name two containers share is no answer" {
    const rows = [_]core.ContainerInfo{ testEntry("100", "web-1", "titan"), testEntry("101", "web-1", "pve"), testEntry("102", "web-2", "pve") };
    try std.testing.expectEqual(PveClient.Pick.many, PveClient.pick(&rows, "web-1", .name_or_vmid));
    try std.testing.expectEqual(PveClient.Pick{ .one = 1 }, PveClient.pick(&rows, "101", .name_or_vmid));
    try std.testing.expectEqual(PveClient.Pick{ .one = 2 }, PveClient.pick(&rows, "web-2", .name_or_vmid));
}

test "by name alone, a VMID finds nothing" {
    const rows = [_]core.ContainerInfo{ testEntry("250", "tenant-b-db", "pve"), testEntry("100", "web-1", "pve") };
    try std.testing.expectEqual(PveClient.Pick.none, PveClient.pick(&rows, "250", .name));
    try std.testing.expectEqual(PveClient.Pick{ .one = 1 }, PveClient.pick(&rows, "web-1", .name));
    try std.testing.expectEqual(PveClient.Pick{ .one = 0 }, PveClient.pick(&rows, "250", .name_or_vmid));
}

test "a miss is no answer while a container has no name" {
    // CT 300 on titan, which the cluster has no report for: it may be rem-1
    const rows = [_]core.ContainerInfo{ testEntry("100", "web-1", "pve"), testEntry("300", "", "titan") };
    try std.testing.expectEqual(PveClient.Pick{ .unnamed = 1 }, PveClient.pick(&rows, "rem-1", .name));
    try std.testing.expectEqual(PveClient.Pick{ .unnamed = 1 }, PveClient.pick(&rows, "rem-1", .name_or_vmid));
    // what does match is still found
    try std.testing.expectEqual(PveClient.Pick{ .one = 0 }, PveClient.pick(&rows, "web-1", .name));
    try std.testing.expectEqual(PveClient.Pick{ .one = 1 }, PveClient.pick(&rows, "300", .name_or_vmid));
    // and with every container named, a miss is a miss
    try std.testing.expectEqual(PveClient.Pick.none, PveClient.pick(rows[0..1], "rem-1", .name));
}

test "an empty id names no container, not one without a name" {
    const rows = [_]core.ContainerInfo{ testEntry("300", "", "titan"), testEntry("100", "web-1", "pve") };
    try std.testing.expectEqual(PveClient.Pick.none, PveClient.pick(&rows, "", .name_or_vmid));
    try std.testing.expectEqual(PveClient.Pick.none, PveClient.pick(&rows, "", .name));
}

test "parsePctStatus reads the init's host PID of a running container" {
    // `pct status 100 --verbose` prints the keys sorted, one per line
    const status = parsePctStatus(
        \\cpus: 1
        \\disk: 0
        \\maxmem: 536870912
        \\name: web-1
        \\pid: 48213
        \\status: running
        \\type: lxc
        \\uptime: 42
        \\vmid: 100
    );
    try std.testing.expectEqual(@as(?std.posix.pid_t, 48213), status.pid);
    try std.testing.expectEqualStrings("running", status.status.?);
}

test "parsePctStatus has no PID for a stopped container or a bad value" {
    const stopped = parsePctStatus("maxmem: 536870912\nname: web-1\nstatus: stopped\nvmid: 100\n");
    try std.testing.expect(stopped.pid == null);
    try std.testing.expectEqualStrings("stopped", stopped.status.?);

    try std.testing.expect(parsePctStatus("pid: abc\nstatus: running").pid == null);
    try std.testing.expect(parsePctStatus("pid: 0\nstatus: running").pid == null);
    try std.testing.expect(parsePctStatus("").status == null);
}

test "parsePveVersion reads the proxmox-ve line of pveversion -v" {
    const version = parsePveVersion(
        \\proxmox-ve: 9.1.0 (running kernel: 6.14.8-2-pve)
        \\pve-manager: 9.1.1 (running version: 9.1.1/42db4a6cf33dac83)
        \\proxmox-kernel-helper: 9.0.4
    ).?;
    try std.testing.expectEqual(@as(u32, 9), version.major);
    try std.testing.expectEqual(@as(u32, 1), version.minor);
}

test "parsePveVersion reads the pve-manager/ form" {
    // The previous parser cut this line at the first '-' (inside the kernel
    // version) and returned "8.4.1/2a5fa54a8503f96d (running kernel: 6.8.12"
    // as the version, which then failed to parse as a number.
    const version = parsePveVersion("pve-manager/8.4.1/2a5fa54a8503f96d (running kernel: 6.8.12-9-pve)").?;
    try std.testing.expectEqual(@as(u32, 8), version.major);
    try std.testing.expectEqual(@as(u32, 4), version.minor);
}

test "parsePveVersion handles a release suffix and rejects the rest" {
    const version = parsePveVersion("proxmox-ve: 9.0-3").?;
    try std.testing.expectEqual(@as(u32, 9), version.major);
    try std.testing.expectEqual(@as(u32, 0), version.minor);

    try std.testing.expect(parsePveVersion("") == null);
    try std.testing.expect(parsePveVersion("proxmox-ve: unknown") == null);
    try std.testing.expect(parsePveVersion("pve-manager: 9.1.1") == null);
}

/// The snapshot list the API returns, parsed into `Snapshot`s and sorted oldest
/// first. The entry named "current" is the container's present state, not a
/// snapshot, and is skipped.
pub fn parseSnapshotList(allocator: std.mem.Allocator, json: []const u8) ![]PveClient.Snapshot {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.NotAnArray;

    var out = std.ArrayListUnmanaged(PveClient.Snapshot){};
    errdefer {
        for (out.items) |*s| s.deinit();
        out.deinit(allocator);
    }
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const name_v = obj.get("name") orelse continue;
        if (name_v != .string) continue;
        if (std.mem.eql(u8, name_v.string, "current")) continue;

        const name = try allocator.dupe(u8, name_v.string);
        errdefer allocator.free(name);
        const description = try allocator.dupe(u8, if (obj.get("description")) |d| (if (d == .string) d.string else "") else "");
        errdefer allocator.free(description);
        const parent: ?[]u8 = if (obj.get("parent")) |p| (if (p == .string) try allocator.dupe(u8, p.string) else null) else null;
        errdefer if (parent) |p| allocator.free(p);
        const snaptime: ?i64 = if (obj.get("snaptime")) |t| (if (t == .integer) t.integer else null) else null;

        try out.append(allocator, .{
            .allocator = allocator,
            .name = name,
            .description = description,
            .snaptime = snaptime,
            .parent = parent,
        });
    }
    std.mem.sort(PveClient.Snapshot, out.items, {}, PveClient.Snapshot.earlier);
    return out.toOwnedSlice(allocator);
}

/// An epoch second as UTC, `2026-10-02T08:00:00Z`: unambiguous where the
/// node's local time, which `pct listsnapshot` prints, carries no zone. An
/// empty string for a time before 1970, which no snapshot has.
pub fn formatUtc(buf: []u8, secs: i64) []const u8 {
    if (secs < 0) return "";
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(secs) };
    const year_day = es.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = es.getDaySeconds();
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        @as(u32, month_day.day_index) + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch "";
}

test "parseSnapshotList: oldest first, 'current' left out, missing fields tolerated" {
    const json =
        \\[{"name":"later","snaptime":1790928000,"description":"after the upgrade","parent":"before"},
        \\ {"name":"current","description":"You are here!","parent":"later","running":0},
        \\ {"name":"before","snaptime":1790812799}]
    ;
    const list = try parseSnapshotList(std.testing.allocator, json);
    defer {
        for (list) |*s| s.deinit();
        std.testing.allocator.free(list);
    }
    try std.testing.expectEqual(@as(usize, 2), list.len);
    try std.testing.expectEqualStrings("before", list[0].name);
    try std.testing.expectEqualStrings("", list[0].description);
    try std.testing.expect(list[0].parent == null);
    try std.testing.expectEqualStrings("later", list[1].name);
    try std.testing.expectEqualStrings("after the upgrade", list[1].description);
    try std.testing.expectEqualStrings("before", list[1].parent.?);
    try std.testing.expectEqual(@as(?i64, 1790928000), list[1].snaptime);
}

test "parseSnapshotList: an empty list and a non-list answer" {
    const empty = try parseSnapshotList(std.testing.allocator, "[]");
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expectError(error.NotAnArray, parseSnapshotList(std.testing.allocator, "{\"errors\":{}}"));
}

test "formatUtc writes the epoch second as UTC with a zone" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("2026-10-02T08:00:00Z", formatUtc(&buf, 1790928000));
    try std.testing.expectEqualStrings("2026-09-30T23:59:59Z", formatUtc(&buf, 1790812799));
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", formatUtc(&buf, 0));
    try std.testing.expectEqualStrings("", formatUtc(&buf, -1));
}

test "resourceOptions: a swap whose MiB Proxmox cannot hold is refused, not an overflow" {
    // The memory limit a swap is worked out from -- create's, the bundle's
    // or the default, or update's, the container's -- is 16 MiB at least as
    // those come, but taken as given here. With a byte, memory plus swap at
    // the top of i64 left nothing to round up into.
    const client = PveClient.init(std.testing.allocator, null);
    var args = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (args.items) |a| std.testing.allocator.free(a);
        args.deinit(std.testing.allocator);
    }
    const swap = [_]core.types.ResourceUpdate{.{ .section = "memory", .name = "swap", .value = "9223372036854775807", .numeric = true }};
    try std.testing.expectError(core.Error.InvalidInput, client.resourceOptions(&swap, 1, &args));
    try std.testing.expectEqual(@as(usize, 0), args.items.len);
    // With a MiB less in the difference it fits, and is said in MiB
    try client.resourceOptions(&swap, 1024 * 1024 - 1, &args);
    try std.testing.expectEqualStrings("--swap", args.items[0]);
    try std.testing.expectEqualStrings("8796093022207", args.items[1]);
}
