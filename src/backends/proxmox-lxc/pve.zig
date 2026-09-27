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

    /// The volid of a template on `storage` that already holds `reference`,
    /// or null. What `create` asks before it pulls: an image already there is
    /// what a container engine would use too, and `pull` is the explicit
    /// fetch. Matched the way an "already there" pull is matched.
    pub fn findTemplate(self: *const Self, allocator: std.mem.Allocator, node: []const u8, storage: []const u8, reference: []const u8, filename: ?[]const u8) !?[]u8 {
        const volids = try self.volidsOf(allocator, node, storage);
        defer {
            for (volids) |v| allocator.free(v);
            allocator.free(volids);
        }
        return try self.matchTemplate(allocator, volids, reference, filename);
    }

    /// Pull an OCI image into a storage on a node, and answer with the volid
    /// the storage ended up holding.
    ///
    /// The volid is read back from the storage rather than composed from the
    /// reference. Composing it -- which `create` did until 0.13.0 -- is a
    /// guess about how PVE normalises a name, and the endpoint's own
    /// documentation says the filename "will be normalized". Asking the
    /// storage is the only way to know, and the answer is what `pct create`
    /// needs to be given.
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
        const before = try self.volidsOf(allocator, node, storage);
        defer {
            for (before) |v| allocator.free(v);
            allocator.free(before);
        }

        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage/{s}/oci-registry-pull", .{ node, storage });
        defer self.allocator.free(path);

        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);
        try args.appendSlice(self.allocator, &.{ "pvesh", "create", path, "--reference", reference });
        if (filename) |f| try args.appendSlice(self.allocator, &.{ "--filename", f });

        const res = try common.runCommand(self.allocator, self.logger, args.items);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        const already_there = res.exit_code == 25 and
            std.mem.indexOf(u8, res.stderr, "refusing to override existing file") != null;
        if (res.exit_code != 0 and !already_there) {
            if (self.logger) |log| {
                log.err("pulling {s} into {s} on {s} failed: {s}", .{ reference, storage, node, std.mem.trim(u8, res.stderr, " \t\r\n") }) catch {};
            }
            return core.Error.OperationFailed;
        }

        const after = try self.volidsOf(allocator, node, storage);
        defer {
            for (after) |v| allocator.free(v);
            allocator.free(after);
        }

        // What appeared. With nothing new and no "already there", the pull
        // reported success and left the storage as it was, which is worth an
        // error rather than a volid nobody can use.
        for (after) |candidate| {
            var found_before = false;
            for (before) |old_volid| {
                if (std.mem.eql(u8, old_volid, candidate)) found_before = true;
            }
            if (!found_before) return try allocator.dupe(u8, candidate);
        }

        if (already_there) {
            // Nothing new because it was there already: name the one that
            // matches what was asked for.
            if (try self.matchTemplate(allocator, after, reference, filename)) |match| return match;
        }

        if (self.logger) |log| {
            log.err("the pull of {s} reported success but {s} on {s} holds no new template", .{ reference, storage, node }) catch {};
        }
        return core.Error.OperationFailed;
    }

    /// The volid whose file name looks like what was asked for, or null.
    fn matchTemplate(self: *const Self, allocator: std.mem.Allocator, volids: []const []u8, reference: []const u8, filename: ?[]const u8) !?[]u8 {
        _ = self;
        if (filename) |f| {
            for (volids) |v| {
                if (std.mem.endsWith(u8, v, f)) return try allocator.dupe(u8, v);
            }
        }
        // docker.io/library/redis:7 -> "redis" and "7"
        const colon = std.mem.lastIndexOfScalar(u8, reference, ':') orelse reference.len;
        const name_part = reference[0..colon];
        const tag = if (colon < reference.len) reference[colon + 1 ..] else "latest";
        const slash = std.mem.lastIndexOfScalar(u8, name_part, '/');
        const image = if (slash) |i| name_part[i + 1 ..] else name_part;
        for (volids) |v| {
            if (std.mem.indexOf(u8, v, image) != null and std.mem.indexOf(u8, v, tag) != null) {
                return try allocator.dupe(u8, v);
            }
        }
        return null;
    }

    /// The volids of the templates on one storage of one node.
    fn volidsOf(self: *const Self, allocator: std.mem.Allocator, node: []const u8, storage: []const u8) ![][]u8 {
        var out = std.ArrayListUnmanaged(Template){};
        defer {
            for (out.items) |*t| t.deinit();
            out.deinit(allocator);
        }
        self.appendTemplatesOf(allocator, &out, node, storage, false) catch {};

        var volids = try allocator.alloc([]u8, out.items.len);
        errdefer allocator.free(volids);
        for (out.items, 0..) |t, i| volids[i] = try allocator.dupe(u8, t.volid);
        return volids;
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
        const colon = std.mem.indexOfScalar(u8, volid, ':') orelse {
            if (self.logger) |log| {
                log.err("a template is named <storage>:vztmpl/<file>, got '{s}'", .{volid}) catch {};
            }
            return core.Error.InvalidInput;
        };
        const storage = volid[0..colon];

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

            const volids = try self.volidsOf(allocator, node, storage);
            defer {
                for (volids) |v| allocator.free(v);
                allocator.free(volids);
            }
            for (volids) |v| {
                if (std.mem.eql(u8, v, volid)) present = true;
            }
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

        /// The node to address through the API, or null when `pct` will do.
        pub fn remote(self: *const Location) ?[]const u8 {
            return if (self.local) null else self.node;
        }

        pub fn deinit(self: *Location) void {
            self.allocator.free(self.vmid);
            self.allocator.free(self.node);
        }
    };

    /// Find a container by name or VMID anywhere in the cluster.
    ///
    /// Falls back to `pct list` when the cluster cannot be asked -- a host
    /// where pvesh is unavailable keeps working exactly as it did, seeing its
    /// own containers and nothing else.
    pub fn locate(self: *const Self, allocator: std.mem.Allocator, name_or_vmid: []const u8) !Location {
        const here = self.getNodeName() catch null;
        defer if (here) |h| self.allocator.free(h);

        // The cluster first, because only it knows which node a container is on.
        //
        // Its "not found" is not an answer, though: /cluster/resources is a
        // cached view that pvestatd refreshes every few seconds, so a container
        // created a moment ago is not in it yet while `pct list` sees it at
        // once. Treating that as missing made `create` followed straight away by
        // `start` fail on a real host. So a miss here means keep looking, and
        // only both sources coming up empty is a container that does not exist.
        if (self.clusterLookup(allocator, name_or_vmid, here)) |found| {
            return found;
        } else |err| {
            if (self.logger) |log| {
                if (err == core.Error.NotFound) {
                    log.debug("'{s}' is not in the cluster's listing yet; asking this host", .{name_or_vmid}) catch {};
                } else {
                    log.debug("the cluster could not be asked about '{s}' ({s}); asking this host", .{ name_or_vmid, @errorName(err) }) catch {};
                }
            }
        }

        // getVmidByName allocates with the client's allocator; the Location owns
        // a copy made with the caller's. Both exist for a moment and only one
        // was being freed -- a leak the GPA reported on every start, stop, pause
        // and resume that came through this path.
        const vmid = try self.getVmidByName(name_or_vmid);
        defer self.allocator.free(vmid);

        const vmid_owned = try allocator.dupe(u8, vmid);
        errdefer allocator.free(vmid_owned);
        return Location{
            .allocator = allocator,
            .vmid = vmid_owned,
            .node = try allocator.dupe(u8, here orelse "localhost"),
            .local = true,
        };
    }

    /// /cluster/resources, which lists every container on every node.
    fn clusterLookup(self: *const Self, allocator: std.mem.Allocator, name_or_vmid: []const u8, here: ?[]const u8) !Location {
        // `--type vm`, not `--type lxc`: the API's enumeration is vm, storage,
        // node, sdn, and it rejects anything else with "400 Parameter
        // verification failed". Containers come back under vm with their own
        // `type` field set to lxc, which is what the filter below reads.
        //
        // This was `--type lxc` when cluster support was written, so every
        // lookup failed and fell back to `pct list` -- which works for a
        // container on this host and answers "not found" for one anywhere else,
        // the exact thing the cluster support was for. The simulator's fake
        // accepted the wrong flag, so the tests agreed with the mistake.
        const args = [_][]const u8{ "pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return core.Error.OperationFailed;

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch {
            return core.Error.OperationFailed;
        };
        defer parsed.deinit();
        if (parsed.value != .array) return core.Error.OperationFailed;

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

            const name = if (obj.get("name")) |n| (if (n == .string) n.string else "") else "";
            if (!std.mem.eql(u8, name, name_or_vmid) and !std.mem.eql(u8, vmid_str, name_or_vmid)) continue;

            const node = if (obj.get("node")) |n| (if (n == .string) n.string else "") else "";
            if (node.len == 0) return core.Error.OperationFailed;

            const vmid_owned = try allocator.dupe(u8, vmid_str);
            errdefer allocator.free(vmid_owned);
            return Location{
                .allocator = allocator,
                .vmid = vmid_owned,
                .node = try allocator.dupe(u8, node),
                .local = if (here) |h| std.mem.eql(u8, h, node) else false,
            };
        }

        return core.Error.NotFound;
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

    /// The nodes of the cluster, or just this one when the cluster cannot be
    /// asked. The caller frees each name and the slice.
    pub fn nodes(self: *const Self, allocator: std.mem.Allocator) ![][]u8 {
        const args = [_][]const u8{ "pvesh", "get", "/nodes", "--output-format", "json" };
        if (common.runCommand(self.allocator, self.logger, &args)) |res| {
            defer {
                self.allocator.free(res.stdout);
                self.allocator.free(res.stderr);
            }
            if (res.exit_code == 0) {
                if (std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{})) |parsed| {
                    defer parsed.deinit();
                    if (parsed.value == .array) {
                        var out = std.ArrayListUnmanaged([]u8){};
                        errdefer {
                            for (out.items) |n| allocator.free(n);
                            out.deinit(allocator);
                        }
                        for (parsed.value.array.items) |item| {
                            if (item != .object) continue;
                            const n = item.object.get("node") orelse continue;
                            if (n != .string) continue;
                            try out.append(allocator, try allocator.dupe(u8, n.string));
                        }
                        if (out.items.len > 0) return try out.toOwnedSlice(allocator);
                        out.deinit(allocator);
                    }
                } else |_| {}
            }
        } else |_| {}

        // No cluster to ask: this host is the whole of it.
        const here = try self.getNodeName();
        defer self.allocator.free(here);
        var one = try allocator.alloc([]u8, 1);
        errdefer allocator.free(one);
        one[0] = try allocator.dupe(u8, here);
        return one;
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

            const stores = try self.templateStorages(node);
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
                try self.appendTemplatesOf(allocator, &out, node, st.name, st.shared);
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
        if (res.exit_code != 0) return core.Error.OperationFailed;

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{});
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

    fn appendTemplatesOf(
        self: *const Self,
        allocator: std.mem.Allocator,
        out: *std.ArrayListUnmanaged(Template),
        node: []const u8,
        storage: []const u8,
        shared: bool,
    ) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage/{s}/content", .{ node, storage });
        defer self.allocator.free(path);
        const args = [_][]const u8{ "pvesh", "get", path, "--content", "vztmpl", "--output-format", "json" };
        const res = common.runCommand(self.allocator, self.logger, &args) catch return;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        // A storage that cannot be read is skipped rather than fatal: one
        // offline mount should not hide every template in the cluster.
        if (res.exit_code != 0) {
            if (self.logger) |log| {
                log.debug("storage {s} on {s} could not be listed", .{ storage, node }) catch {};
            }
            return;
        }

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .array) return;

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

            try out.append(allocator, .{
                .allocator = allocator,
                .node = try allocator.dupe(u8, node),
                .storage = try allocator.dupe(u8, storage),
                .volid = try allocator.dupe(u8, volid),
                .format = try allocator.dupe(u8, format),
                .size = size,
                .shared = shared,
            });
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
        const colon = std.mem.indexOfScalar(u8, volid, ':') orelse {
            if (self.logger) |log| {
                log.err("--node needs a template named as <storage>:vztmpl/<file>, got '{s}'", .{volid}) catch {};
            }
            return core.Error.InvalidInput;
        };
        const storage = volid[0..colon];

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
        const s = stderr;
        if (self.logger) |log| log.err("pct command failed: {s}", .{std.mem.trim(u8, stderr, " \t\r\n")}) catch {};

        if (std.mem.indexOf(u8, s, "already exists") != null) return core.Error.OperationFailed;
        if (std.mem.indexOf(u8, s, "No such file or directory") != null or
            std.mem.indexOf(u8, s, "does not exist") != null or
            std.mem.indexOf(u8, s, "not found") != null) return core.Error.NotFound;
        if (std.mem.indexOf(u8, s, "Permission denied") != null) return core.Error.PermissionDenied;
        if (std.mem.indexOf(u8, s, "timeout") != null) return core.Error.Timeout;

        return core.Error.OperationFailed;
    }

    /// List containers across the cluster, falling back to this host.
    ///
    /// `pct list` answers for the node it runs on and nothing else, so on a
    /// cluster it showed a fraction of what was there without saying so. The
    /// cluster's own listing carries the node, which is the column a person
    /// then needs to make sense of the rest.
    pub fn list(self: *const Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        const cluster = self.clusterList(allocator) catch |err| {
            if (self.logger) |log| {
                log.debug("the cluster could not be listed ({s}); listing this host", .{@errorName(err)}) catch {};
            }
            return self.localList(allocator);
        };

        // The cluster's listing is a cached view: pvestatd refreshes it every
        // few seconds, so a container created a moment ago is in `pct list` and
        // not yet here. Returning only the cluster's answer made `nexcage list`
        // -- and `state`, which reads it -- miss a container that plainly
        // exists. This host's own containers are merged in, by VMID.
        const local = self.localList(allocator) catch {
            return cluster;
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
        // while `list` said running. The cluster stays authoritative for the one
        // thing only it knows: which node a container on another host is on.
        for (local) |*c| {
            var replaced = false;
            for (merged.items) |*m| {
                if (!std.mem.eql(u8, m.id, c.id)) continue;
                allocator.free(m.status);
                m.status = try allocator.dupe(u8, c.status);
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
        // `--type vm` and a filter, for the reason spelt out in clusterLookup.
        const args = [_][]const u8{ "pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return core.Error.OperationFailed;

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, res.stdout, .{});
        defer parsed.deinit();
        if (parsed.value != .array) return core.Error.OperationFailed;

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
            const name = if (obj.get("name")) |n| (if (n == .string) n.string else "") else "";
            const status = if (obj.get("status")) |st| (if (st == .string) st.string else "unknown") else "unknown";
            const node = if (obj.get("node")) |n| (if (n == .string) n.string else "") else "";

            try containers.append(self.allocator, core.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, vmid_str),
                .name = try allocator.dupe(u8, if (name.len > 0) name else vmid_str),
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
        if (res.exit_code != 0) return self.mapPctError(res.stderr);

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
        const res = core.resources;
        var args = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (args.items) |a| self.allocator.free(a);
            args.deinit(self.allocator);
        }

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
                try pushOption(self.allocator, &args, "--memory", "{d}", .{res.mibCeil(num)});
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
                try pushOption(self.allocator, &args, "--cpuunits", "{d}", .{res.sharesToWeight(num)});
            } else {
                if (self.logger) |log| log.err("{s}.{s} has no Proxmox setting for a container: pct set knows memory, swap, cpulimit and cpuunits, so this backend takes --memory, --memory-swap, --cpu-quota/--cpu-period and --cpu-share", .{ v.section, v.name }) catch {};
                return core.Error.UnsupportedOperation;
            }
        }

        if (swap_total) |total| {
            // runc's --memory-swap is memory plus swap; pct's --swap is swap
            // alone. The difference needs the memory limit, from this call or
            // from the container's config.
            const limit = memory_bytes orelse (try self.currentMemoryBytes(vmid, node));
            if (total < limit) {
                if (self.logger) |log| log.err("--memory-swap is memory plus swap, as runc means it, and {d} is less than the memory limit of {d}", .{ total, limit }) catch {};
                return core.Error.InvalidInput;
            }
            try pushOption(self.allocator, &args, "--swap", "{d}", .{@divFloor(total - limit + (1024 * 1024 - 1), 1024 * 1024)});
        }
        if (quota) |q| {
            var buf: [32]u8 = undefined;
            const cores = res.cpulimit(&buf, q, period orelse 100000) catch {
                if (self.logger) |log| log.err("--cpu-period must be positive", .{}) catch {};
                return core.Error.InvalidInput;
            };
            try pushOption(self.allocator, &args, "--cpulimit", "{s}", .{cores});
        } else if (period != null) {
            if (self.logger) |log| log.err("--cpu-period on its own changes nothing here: Proxmox has a CPU limit in cores, which is quota over period, so give --cpu-quota too", .{}) catch {};
            return core.Error.InvalidInput;
        }
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
        return mib * 1024 * 1024;
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
        std.posix.kill(pid, signo) catch |err| {
            if (self.logger) |log| log.err("sending signal {d} to PID {d} (init of CT {s}) failed: {s}", .{ signo, pid, vmid, @errorName(err) }) catch {};
            return switch (err) {
                error.PermissionDenied => core.Error.PermissionDenied,
                else => core.Error.OperationFailed,
            };
        };
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

        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);
        try args.appendSlice(self.allocator, &.{ "pct", "exec", vmid, "--" });
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
