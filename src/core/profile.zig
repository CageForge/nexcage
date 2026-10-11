//! Isolation profiles (ADR-005): a name, the backend, and that backend's
//! parameters, defined in the configuration file on the node. An engine names
//! one by the program name, `nexcage@<profile>`; a person with `--profile`.
//! Only `create` reads a profile, and a profile only narrows what the engine's
//! bundle grants: it drops capabilities and lowers limits, and refuses a
//! bundle that lacks what it requires. It never adds anything.
//!
//! Profiles on the crun backend only, so far (#315); the Proxmox LXC backend
//! driven by an engine is #316.

const std = @import("std");
const os = std.os.linux;
const types = @import("types.zig");

/// The annotation `state` reports the profile under. nexcage writes it; a
/// bundle that arrives carrying it is refused, so that `state` never reports a
/// profile that was not applied.
pub const annotation = "io.cageforge.nexcage.profile";

pub const Profile = struct {
    name: []const u8,
    runtime: types.RuntimeType = .crun,
    /// Refuse a bundle without a user namespace and uid/gid mappings. Nothing
    /// is added: who owns the root filesystem is the engine's to arrange.
    require_user_namespace: bool = false,
    /// Refuse a bundle without linux.seccomp. nexcage ships no filter.
    require_seccomp: bool = false,
    /// Capability names removed from every set of the container's process.
    drop_capabilities: []const []const u8 = &.{},
    /// linux.resources.memory.limit, in bytes: the bundle's when lower.
    memory_limit: ?i64 = null,
    /// linux.resources.pids.limit: the bundle's when lower.
    pids_limit: ?i64 = null,

    pub fn deinit(self: *Profile, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.drop_capabilities) |cap| allocator.free(cap);
        allocator.free(self.drop_capabilities);
    }
};

/// The kernel's capability names, by number (include/uapi/linux/capability.h),
/// through CAP_CHECKPOINT_RESTORE, the last one as of Linux 7.0. A name not
/// here is no capability at all: a drop naming it would remove nothing.
const capability_names = [_][]const u8{
    "CAP_CHOWN",              "CAP_DAC_OVERRIDE",    "CAP_DAC_READ_SEARCH",  "CAP_FOWNER",
    "CAP_FSETID",             "CAP_KILL",            "CAP_SETGID",           "CAP_SETUID",
    "CAP_SETPCAP",            "CAP_LINUX_IMMUTABLE", "CAP_NET_BIND_SERVICE", "CAP_NET_BROADCAST",
    "CAP_NET_ADMIN",          "CAP_NET_RAW",         "CAP_IPC_LOCK",         "CAP_IPC_OWNER",
    "CAP_SYS_MODULE",         "CAP_SYS_RAWIO",       "CAP_SYS_CHROOT",       "CAP_SYS_PTRACE",
    "CAP_SYS_PACCT",          "CAP_SYS_ADMIN",       "CAP_SYS_BOOT",         "CAP_SYS_NICE",
    "CAP_SYS_RESOURCE",       "CAP_SYS_TIME",        "CAP_SYS_TTY_CONFIG",   "CAP_MKNOD",
    "CAP_LEASE",              "CAP_AUDIT_WRITE",     "CAP_AUDIT_CONTROL",    "CAP_SETFCAP",
    "CAP_MAC_OVERRIDE",       "CAP_MAC_ADMIN",       "CAP_SYSLOG",           "CAP_WAKE_ALARM",
    "CAP_BLOCK_SUSPEND",      "CAP_AUDIT_READ",      "CAP_PERFMON",          "CAP_BPF",
    "CAP_CHECKPOINT_RESTORE",
};

/// Whether `name` is a capability, spelt as the kernel spells it.
pub fn isCapabilityName(name: []const u8) bool {
    for (capability_names) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

/// A profile name is a DNS label, so that it can be a RuntimeClass handler's
/// name as it is.
pub fn isValidName(name: []const u8) bool {
    if (name.len == 0 or name.len > 32) return false;
    for (name, 0..) |c, i| {
        const ok = (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or (c == '-' and i != 0 and i != name.len - 1);
        if (!ok) return false;
    }
    return true;
}

/// The profile a program name names: what follows the `@` in
/// `nexcage@<profile>`, or null when there is no `@`. `@` rather than crun's
/// `-`, because the release files are called `nexcage-0.16.0-amd64-crun` and
/// a binary run under that name must not be read as a profile.
pub fn fromProgramName(argv0: []const u8) ?[]const u8 {
    const base = std.fs.path.basename(argv0);
    const at = std.mem.indexOfScalar(u8, base, '@') orelse return null;
    return base[at + 1 ..];
}

/// Why `narrow` refused a bundle, for the caller to log.
pub const Refusal = struct {
    buf: [320]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const Refusal) []const u8 {
        return self.buf[0..self.len];
    }

    fn set(self: *Refusal, comptime format: []const u8, args: anytype) error{ProfileRefused} {
        const msg = std.fmt.bufPrint(&self.buf, format, args) catch self.buf[0..];
        self.len = msg.len;
        return error.ProfileRefused;
    }
};

const capability_sets = [_][]const u8{ "bounding", "effective", "inheritable", "permitted", "ambient" };

/// What create hands libcrun instead of the bundle's file: with a profile,
/// the spec narrowed by it, which the caller owns; without one, null, and
/// libcrun reads the file. Either way a bundle that claims a profile is
/// refused.
pub fn prepare(allocator: std.mem.Allocator, spec_json: []const u8, profile: ?*const Profile, why: *Refusal) !?[]u8 {
    const p = profile orelse {
        try checkUnclaimed(allocator, spec_json, why);
        return null;
    };
    return try narrow(allocator, spec_json, p, why);
}

fn checkUnclaimed(allocator: std.mem.Allocator, spec_json: []const u8, why: *Refusal) !void {
    const parsed = try parse(allocator, spec_json, "the bundle's config.json", why);
    defer parsed.deinit();
    try refuseClaim(&parsed.value.object, why);
}

/// The bundle's config.json, narrowed by `profile` and marked with its name:
/// what libcrun is given instead of the file. The caller owns the result.
fn narrow(allocator: std.mem.Allocator, spec_json: []const u8, profile: *const Profile, why: *Refusal) ![]u8 {
    var parsed = try parse(allocator, spec_json, "the bundle's config.json", why);
    defer parsed.deinit();
    const arena = parsed.arena.allocator();
    const root = &parsed.value.object;
    try checkDocument(parsed.value, "the bundle's config.json", why);
    try refuseClaim(root, why);
    try checkCapabilityNames(capabilitiesOf(root.get("process")), "the bundle's process.capabilities", why);

    const linux = try child(arena, root, "linux");

    if (profile.require_user_namespace) try checkUserNamespace(linux, profile, why);

    if (profile.require_seccomp) try checkSeccomp(linux, profile, why);

    if (profile.drop_capabilities.len > 0) dropCapabilities(root, profile.drop_capabilities);

    if (profile.memory_limit != null or profile.pids_limit != null) {
        const resources = try child(arena, linux, "resources");
        if (profile.memory_limit) |limit| try lowerMemory(try child(arena, resources, "memory"), limit);
        if (profile.pids_limit) |limit| try lowerTo(try child(arena, resources, "pids"), "limit", limit);
        try lowerUnified(arena, resources, profile);
    }

    // Looked up again, not kept from above: adding a key to the root may
    // move the objects it holds.
    try (try child(arena, root, "annotations")).put(annotation, .{ .string = profile.name });
    return std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
}

/// The process spec for an `exec` into a container made under a profile:
/// every capability set cut to the bounding set the container was made with.
/// An engine builds exec's process from its own copy of the spec, from before
/// the profile narrowed it, and libcrun applies a process spec's capabilities
/// as they are; a process spec without them gets the container's. Null when
/// there is nothing to cut: the caller hands its file over untouched. The
/// caller owns the result.
pub fn boundExec(allocator: std.mem.Allocator, process_json: []const u8, container_json: []const u8, why: *Refusal) !?[]u8 {
    const container = try parse(allocator, container_json, "the container's stored config.json", why);
    defer container.deinit();
    const marks = container.value.object.get("annotations") orelse return null;
    if (marks != .object or !marks.object.contains(annotation)) return null;

    var process = try parse(allocator, process_json, "the process spec", why);
    defer process.deinit();
    // Before anything is taken from it, and before deciding it has nothing
    // to cut: "capabilities\u0000" is "capabilities" to libcrun.
    try checkDocument(process.value, "the process spec", why);
    const caps = process.value.object.getPtr("capabilities") orelse return null;
    if (caps.* != .object) return null;
    try checkCapabilityNames(caps.object, "the process spec's capabilities", why);

    const arena = process.arena.allocator();
    var bounding = std.ArrayListUnmanaged([]const u8){};
    if (capabilitiesOf(container.value.object.get("process"))) |held| {
        if (held.get("bounding")) |b| if (b == .array) for (b.array.items) |v| {
            if (v == .string) try bounding.append(arena, v.string);
        };
    }
    for (capability_sets) |set_name| {
        const set = caps.object.getPtr(set_name) orelse continue;
        if (set.* == .array) filter(&set.array, bounding.items, true);
    }
    return try std.json.Stringify.valueAlloc(allocator, process.value, .{});
}

/// Every entry of every capability set is a capability spelt as the kernel
/// spells it. libcrun reads them with libcap's cap_from_name, which takes
/// "cap_net_raw", "Cap_Net_Raw", "13", "0x0d", "13junk" and "CAP_NET_RAW2"
/// all for CAP_NET_RAW, and json-c hands it a number as its digits; a profile
/// compares names, and a drop that missed such a spelling left the capability
/// in place. Exec's bound compares names with the stored bounding set, which
/// this keeps to the same spellings.
fn checkCapabilityNames(caps: ?std.json.ObjectMap, at: []const u8, why: *Refusal) error{ProfileRefused}!void {
    const c = caps orelse return;
    for (capability_sets) |set_name| {
        // A set that is not a list is no set to libcrun, and grants nothing.
        const set = c.get(set_name) orelse continue;
        if (set != .array) continue;
        for (set.array.items) |item| {
            if (item != .string)
                return why.set("{s}.{s} holds a JSON {s}, where only capability names go, such as \"CAP_NET_RAW\"", .{ at, set_name, kindOf(item) });
            if (!isCapabilityName(item.string))
                return why.set("{s}.{s} lists \"{s}\", which is not a capability name as the kernel spells it, such as \"CAP_NET_RAW\"; libcrun could read it as one the profile does not see", .{ at, set_name, item.string });
        }
    }
}

/// A value's JSON type, for a message.
fn kindOf(v: std.json.Value) []const u8 {
    return switch (v) {
        .integer, .float, .number_string => "number",
        .bool => "boolean",
        else => @tagName(v),
    };
}

fn capabilitiesOf(process: ?std.json.Value) ?std.json.ObjectMap {
    const p = process orelse return null;
    if (p != .object) return null;
    const c = p.object.get("capabilities") orelse return null;
    return if (c == .object) c.object else null;
}

/// A JSON object, or a refusal. Duplicate keys are refused too: libcrun's
/// parser would read one of them and this one the other.
fn parse(allocator: std.mem.Allocator, json: []const u8, what: []const u8, why: *Refusal) !std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return why.set("{s} is not valid JSON ({s})", .{ what, @errorName(err) }),
    };
    if (parsed.value != .object) {
        parsed.deinit();
        return why.set("{s} is not a JSON object", .{what});
    }
    return parsed;
}

/// The record `state` reports must be one nexcage wrote. Keys are compared as
/// libcrun compares them, up to a NUL: without a profile libcrun reads the
/// file itself, and "annotations\u0000" or "io.cageforge.nexcage.profile\u0000"
/// is the real key to it.
fn refuseClaim(root: *const std.json.ObjectMap, why: *Refusal) error{ProfileRefused}!void {
    var it = root.iterator();
    while (it.next()) |entry| {
        if (!std.mem.eql(u8, beforeNul(entry.key_ptr.*), "annotations")) continue;
        if (entry.value_ptr.* != .object) continue;
        var keys = entry.value_ptr.object.iterator();
        while (keys.next()) |key| {
            if (std.mem.eql(u8, beforeNul(key.key_ptr.*), annotation))
                return why.set("the bundle carries the annotation {s}, which nexcage writes itself", .{annotation});
        }
    }
}

/// What a C reader of the key or string sees: everything before a NUL.
fn beforeNul(s: []const u8) []const u8 {
    return s[0 .. std.mem.indexOfScalar(u8, s, 0) orelse s.len];
}

/// Deeper than any runtime spec nests (a seccomp rule's argument is seven
/// levels down), and well under the 256 levels std.json.Stringify checks in a
/// safe build: a bundle nested past those made nexcage panic, not refuse it.
const max_depth = 64;

/// Refuses a document libcrun would read otherwise than this parser did, or
/// that cannot be written back. Its parser, json-c, ends a key or a string at
/// a NUL, and keeps the last of two keys that are then the same: with "linux"
/// and "linux\u0000", the profile would check the first and libcrun apply the
/// second, which nothing checked. "CAP_SYS_ADMIN\u0000x" would get past a
/// drop the same way. No runtime spec has a NUL anywhere, so every key and
/// string is refused for one, and so is nesting deeper than max_depth.
fn checkDocument(value: std.json.Value, what: []const u8, why: *Refusal) error{ProfileRefused}!void {
    var at: Path = .{};
    return walk(value, 1, &at, what, why);
}

/// Recursive, and bounded by max_depth: the parser that built `value` keeps
/// its own stack on the heap and takes any depth.
fn walk(value: std.json.Value, depth: usize, at: *Path, what: []const u8, why: *Refusal) error{ProfileRefused}!void {
    switch (value) {
        .object => |obj| {
            if (depth > max_depth) return tooDeep(what, at, why);
            var it = obj.iterator();
            while (it.next()) |entry| {
                const back = at.key(entry.key_ptr.*);
                if (std.mem.indexOfScalar(u8, entry.key_ptr.*, 0) != null) return nul(what, "key", at, why);
                try walk(entry.value_ptr.*, depth + 1, at, what, why);
                at.len = back;
            }
        },
        .array => |list| {
            if (depth > max_depth) return tooDeep(what, at, why);
            for (list.items, 0..) |item, i| {
                const back = at.index(i);
                try walk(item, depth + 1, at, what, why);
                at.len = back;
            }
        },
        .string => |s| if (std.mem.indexOfScalar(u8, s, 0) != null) return nul(what, "string", at, why),
        else => {},
    }
}

fn tooDeep(what: []const u8, at: *const Path, why: *Refusal) error{ProfileRefused} {
    return why.set("{s} nests deeper than {d} levels, at {s}; no runtime spec does", .{ what, max_depth, at.text() });
}

fn nul(what: []const u8, kind: []const u8, at: *const Path, why: *Refusal) error{ProfileRefused} {
    return why.set("{s} has a NUL in the {s} at {s}: libcrun's parser ends a {s} there, so it would read something other than what the profile checked", .{ what, kind, at.text(), kind });
}

/// Where in a document a refusal points, as linux.namespaces[1].path. A NUL
/// or another control character in a key is written as \u0000.
const Path = struct {
    buf: [128]u8 = undefined,
    len: usize = 0,

    fn text(self: *const Path) []const u8 {
        return if (self.len == 0) "the top level" else self.buf[0..self.len];
    }

    /// Appends `.name`, and returns the length to go back to.
    fn key(self: *Path, name: []const u8) usize {
        const back = self.len;
        if (self.len > 0) self.put(".");
        for (name) |c| {
            if (c >= 0x20) {
                self.put(&.{c});
                continue;
            }
            var esc: [6]u8 = undefined;
            self.put(std.fmt.bufPrint(&esc, "\\u{x:0>4}", .{c}) catch unreachable);
        }
        return back;
    }

    /// Appends `[i]`, and returns the length to go back to.
    fn index(self: *Path, i: usize) usize {
        const back = self.len;
        var digits: [24]u8 = undefined;
        self.put(std.fmt.bufPrint(&digits, "[{d}]", .{i}) catch unreachable);
        return back;
    }

    /// What fits: a path longer than the buffer is cut, not refused.
    fn put(self: *Path, bytes: []const u8) void {
        const n = @min(bytes.len, self.buf.len - self.len);
        @memcpy(self.buf[self.len..][0..n], bytes[0..n]);
        self.len += n;
    }
};

/// The object under `key`, made when it is not there. The pointer is good
/// until the next key is added to `obj`.
fn child(arena: std.mem.Allocator, obj: *std.json.ObjectMap, key: []const u8) !*std.json.ObjectMap {
    const gop = try obj.getOrPut(key);
    if (!gop.found_existing or gop.value_ptr.* != .object) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(arena) };
    return &gop.value_ptr.object;
}

/// require_seccomp: a filter that refuses some system call by itself. One
/// whose default action and every rule let calls through, or leave them to a
/// process in user space, is no filter: SCMP_ACT_ALLOW and SCMP_ACT_LOG run
/// the call, SCMP_ACT_NOTIFY asks whatever listens at listenerPath, and
/// SCMP_ACT_TRACE a tracer, which can be a process in the container. Which
/// calls a filter refuses is not judged: a rule naming no call this kernel
/// has is skipped by libcrun, and still counts here.
fn checkSeccomp(linux: *const std.json.ObjectMap, profile: *const Profile, why: *Refusal) error{ProfileRefused}!void {
    const seccomp = linux.get("seccomp") orelse
        return why.set("profile '{s}' requires a seccomp filter, and the bundle has none; in Kubernetes, set securityContext.seccompProfile.type: RuntimeDefault", .{profile.name});
    if (seccomp != .object)
        return why.set("profile '{s}' requires a seccomp filter, and the bundle has none; in Kubernetes, set securityContext.seccompProfile.type: RuntimeDefault", .{profile.name});
    if (refuses(seccomp.object.get("defaultAction"))) return;
    if (seccomp.object.get("syscalls")) |rules| if (rules == .array) for (rules.array.items) |rule| {
        if (rule != .object or !refuses(rule.object.get("action"))) continue;
        const names = rule.object.get("names") orelse continue;
        if (names != .array) continue;
        for (names.array.items) |name| {
            if (name == .string) return;
        }
    };
    return why.set("profile '{s}' requires a seccomp filter, and the bundle's refuses no system call: its default action and every rule let calls through or leave them to user space; in Kubernetes, set securityContext.seccompProfile.type: RuntimeDefault", .{profile.name});
}

/// Whether a seccomp action, by libcrun's names, stops the call in the kernel.
fn refuses(action: ?std.json.Value) bool {
    const a = action orelse return false;
    if (a != .string) return false;
    for ([_][]const u8{ "SCMP_ACT_KILL", "SCMP_ACT_KILL_PROCESS", "SCMP_ACT_KILL_THREAD", "SCMP_ACT_TRAP", "SCMP_ACT_ERRNO" }) |name| {
        if (std.mem.eql(u8, a.string, name)) return true;
    }
    return false;
}

/// require_user_namespace: a user namespace that keeps the container's root
/// from being the host's. Either libcrun makes one from uidMappings and
/// gidMappings, which must then leave host id 0 out, or it joins the one a
/// namespace entry names by path, ignoring the mappings, and that namespace
/// is checked instead. containerd and CRI-O do both for a pod's containers:
/// the pod's namespace by path, and its mappings beside it.
fn checkUserNamespace(linux: *const std.json.ObjectMap, profile: *const Profile, why: *Refusal) error{ProfileRefused}!void {
    const none = "profile '{s}' requires a user namespace, and the bundle has none with uid and gid mappings; in Kubernetes, set hostUsers: false on the pod";
    const namespaces = linux.get("namespaces") orelse return why.set(none, .{profile.name});
    if (namespaces != .array) return why.set(none, .{profile.name});
    var has_user = false;
    for (namespaces.array.items) |ns| {
        if (isUserNamespace(ns)) has_user = true;
    }
    if (!has_user) return why.set(none, .{profile.name});

    for ([_][]const u8{ "uidMappings", "gidMappings" }) |key| {
        const m = linux.get(key) orelse return why.set(none, .{profile.name});
        if (m != .array or m.array.items.len == 0) return why.set(none, .{profile.name});
        for (m.array.items, 0..) |range, i| {
            const host = idOf(range, "hostID");
            if (host == null or idOf(range, "containerID") == null or idOf(range, "size") == null)
                return why.set("profile '{s}' requires a user namespace, and linux.{s}[{d}] is not a range of whole numbers containerID, hostID and size", .{ profile.name, key, i });
            // A range starting anywhere else cannot reach 0. Kubernetes never
            // maps it: the kubelet keeps its ranges clear of host root.
            if (host.? == 0)
                return why.set("profile '{s}' requires a user namespace that does not map host {s} 0, and linux.{s}[{d}] maps it: root in the container would be root on the host", .{ profile.name, idName(key), key, i });
        }
    }

    for (namespaces.array.items) |ns| {
        if (!isUserNamespace(ns)) continue;
        if (ns.object.get("path")) |path| try checkJoined(path, profile, why);
    }
}

fn isUserNamespace(ns: std.json.Value) bool {
    if (ns != .object) return false;
    const t = ns.object.get("type") orelse return false;
    return t == .string and std.mem.eql(u8, t.string, "user");
}

/// A uid or gid as libcrun reads one: a whole number in 32 bits. libcrun
/// reads a field of another type as absent, and an absent hostID as 0.
fn idOf(range: std.json.Value, key: []const u8) ?u32 {
    if (range != .object) return null;
    const v = range.object.get(key) orelse return null;
    if (v != .integer or v.integer < 0 or v.integer > std.math.maxInt(u32)) return null;
    return @intCast(v.integer);
}

fn idName(mappings: []const u8) []const u8 {
    return if (mappings[0] == 'u') "uid" else "gid";
}

/// The user namespace a bundle joins by path. libcrun joins it as it is, so
/// it is refused unless it is a user namespace other than nexcage's own, and
/// its maps leave host uid and gid 0 out. containerd names a pod's as
/// /proc/<sandbox pid>/ns/user, CRI-O as a bind mount that pins it; both are
/// read the same way, from a child that joins it. What cannot be read is
/// refused: the requirement is that the container is isolated, not that its
/// bundle says so.
///
/// libcrun opens the path again later. A /proc/<pid> path could name another
/// process by then only if the pid were reused in between, which takes a
/// wrap of the whole pid space.
fn checkJoined(path: std.json.Value, profile: *const Profile, why: *Refusal) error{ProfileRefused}!void {
    // Relative to what? libcrun resolves it from the bundle, after this.
    if (path != .string or path.string.len == 0 or path.string[0] != '/')
        return why.set("profile '{s}' requires a user namespace nexcage can check, and the bundle joins one by a path that is not absolute", .{profile.name});
    const p = path.string;
    const own = std.posix.fstatat(std.posix.AT.FDCWD, "/proc/self/ns/user", 0) catch |err| return unchecked(profile, p, err, why);
    const named = std.posix.fstatat(std.posix.AT.FDCWD, p, 0) catch |err| return unchecked(profile, p, err, why);
    // Every namespace is a file of one filesystem, nsfs. Nothing off it is
    // opened: a device or a FIFO could do something on open.
    if (named.dev != own.dev)
        return why.set("profile '{s}' requires a user namespace, and the bundle joins {s}, which is not a namespace", .{ profile.name, p });
    if (named.ino == own.ino)
        return why.set("profile '{s}' requires a user namespace of the container's own, and the bundle joins {s}, which is nexcage's", .{ profile.name, p });

    const fd = std.posix.open(p, .{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NONBLOCK = true }, 0) catch |err| return unchecked(profile, p, err, why);
    defer std.posix.close(fd);
    const opened = std.posix.fstat(fd) catch |err| return unchecked(profile, p, err, why);
    if (opened.dev != named.dev or opened.ino != named.ino)
        return why.set("profile '{s}' requires a user namespace nexcage can check, and {s} changed while it was checked", .{ profile.name, p });
    if (os.ioctl(fd, ns_get_nstype, 0) != os.CLONE.NEWUSER)
        return why.set("profile '{s}' requires a user namespace, and the bundle joins {s}, which is another kind of namespace", .{ profile.name, p });

    const inside = Inside.join(fd) catch |err| return unchecked(profile, p, err, why);
    defer inside.leave();
    var file: [64]u8 = undefined;
    const joined = std.posix.fstatat(std.posix.AT.FDCWD, std.fmt.bufPrint(&file, "/proc/{d}/ns/user", .{inside.pid}) catch unreachable, 0) catch |err| return unchecked(profile, p, err, why);
    if (joined.dev != named.dev or joined.ino != named.ino)
        return why.set("profile '{s}' requires a user namespace nexcage can check, and {s} changed while it was checked", .{ profile.name, p });
    var buf: [16 * 1024]u8 = undefined;
    for ([_][]const u8{ "uid_map", "gid_map" }) |name| {
        const map = std.fs.cwd().readFile(std.fmt.bufPrint(&file, "/proc/{d}/{s}", .{ inside.pid, name }) catch unreachable, &buf) catch |err| return unchecked(profile, p, err, why);
        const id = name[0..3];
        // A full buffer may be a cut one; the kernel allows 340 lines.
        const verdict = if (map.len == buf.len) null else mapsZero(map);
        const zero = verdict orelse
            return why.set("profile '{s}' requires a user namespace nexcage can check, and the {s} of the one the bundle joins, {s}, does not read as a map", .{ profile.name, name, p });
        if (zero)
            return why.set("profile '{s}' requires a user namespace that does not map host {s} 0, and the one the bundle joins, {s}, maps it: root in the container would be root on the host", .{ profile.name, id, p });
    }
}

fn unchecked(profile: *const Profile, path: []const u8, err: anyerror, why: *Refusal) error{ProfileRefused} {
    return why.set("profile '{s}' requires a user namespace nexcage can check, and it cannot read the one the bundle joins, {s} ({s})", .{ profile.name, path, @errorName(err) });
}

/// The ioctl that says which kind of namespace a file is (<linux/nsfs.h>).
const ns_get_nstype = 0xb703;

/// Whether a uid_map or gid_map maps id 0 of the namespace that reads it.
/// Each line is "inside outside count", with outside in the reader's terms,
/// and a line's range lies within one range of every namespace above it, so
/// a range covering 0 starts at 0. Null for a map that maps nothing or does
/// not read as one.
fn mapsZero(map: []const u8) ?bool {
    var lines = std.mem.tokenizeScalar(u8, map, '\n');
    var any = false;
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        var n: [3]u32 = undefined;
        for (&n) |*field| field.* = std.fmt.parseInt(u32, fields.next() orelse return null, 10) catch return null;
        if (fields.next() != null or n[2] == 0) return null;
        if (n[1] == 0) return true;
        any = true;
    }
    return if (any) false else null;
}

/// A child of this process inside a user namespace, held there until leave.
/// /proc/<child>/uid_map then shows that namespace's map in this process's
/// terms, which is the only way to read one that a bind mount pins with no
/// process of its own.
const Inside = struct {
    pid: std.posix.pid_t,
    hold: std.posix.fd_t,

    fn join(ns: std.posix.fd_t) !Inside {
        const ready = try std.posix.pipe2(.{ .CLOEXEC = true });
        defer std.posix.close(ready[0]);
        const hold = std.posix.pipe2(.{ .CLOEXEC = true }) catch |err| {
            std.posix.close(ready[1]);
            return err;
        };
        const pid = std.posix.fork() catch |err| {
            for ([_]std.posix.fd_t{ ready[1], hold[0], hold[1] }) |fd| std.posix.close(fd);
            return err;
        };
        if (pid == 0) {
            // The child: system calls only, and out through exit_group, so
            // that nothing of the parent's runs twice. It waits for EOF on
            // the hold pipe, which comes when the parent closes its end or
            // dies.
            _ = os.close(hold[1]);
            if (os.syscall2(.setns, @intCast(ns), os.CLONE.NEWUSER) != 0) os.exit_group(1);
            _ = os.write(ready[1], "j", 1);
            var b: [1]u8 = undefined;
            _ = os.read(hold[0], &b, 1);
            os.exit_group(0);
        }
        std.posix.close(ready[1]);
        std.posix.close(hold[0]);
        const inside = Inside{ .pid = pid, .hold = hold[1] };
        var b: [1]u8 = undefined;
        const n = std.posix.read(ready[0], &b) catch 0;
        if (n != 1) {
            inside.leave();
            return error.SetnsFailed;
        }
        return inside;
    }

    fn leave(self: Inside) void {
        std.posix.close(self.hold);
        var status: u32 = undefined;
        while (true) {
            const rc = os.wait4(self.pid, &status, 0, null);
            if (os.E.init(rc) != .INTR) break;
        }
    }
};

fn dropCapabilities(root: *std.json.ObjectMap, drop: []const []const u8) void {
    const process = root.getPtr("process") orelse return;
    if (process.* != .object) return;
    const caps = process.object.getPtr("capabilities") orelse return;
    if (caps.* != .object) return;
    for (capability_sets) |set_name| {
        const set = caps.object.getPtr(set_name) orelse continue;
        if (set.* == .array) filter(&set.array, drop, false);
    }
}

/// Removes from `set` the names in `names`, or with `keep`, every name that
/// is not in it.
fn filter(set: *std.json.Array, names: []const []const u8, keep: bool) void {
    var i: usize = 0;
    while (i < set.items.len) {
        const item = set.items[i];
        var listed = false;
        if (item == .string) {
            for (names) |n| {
                if (std.mem.eql(u8, n, item.string)) listed = true;
            }
        }
        if (listed != keep) _ = set.orderedRemove(i) else i += 1;
    }
}

/// Sets obj[key] to `limit` unless it already holds a positive value no
/// higher; -1, 0 and an absent value all mean no limit.
fn lowerTo(obj: *std.json.ObjectMap, key: []const u8, limit: i64) !void {
    if (obj.get(key)) |v| {
        if (v == .integer and v.integer > 0 and v.integer <= limit) return;
    }
    try obj.put(key, .{ .integer = limit });
}

/// linux.resources.unified names cgroup v2 files and their values, and
/// libcrun writes them after everything else, so they win: "memory.max":
/// "max" undid the memory limit above. Each file a profile limits is lowered
/// as lowerTo lowers the spec's field, the profile's value unless the bundle
/// gives one no higher; memory.high, where the kernel starts to hold memory
/// back, goes with memory.max. Left alone: memory.swap.max, which is swap
/// alone in cgroup v2, since a profile keeps the swap the bundle asked for
/// (lowerMemory), even no limit at all; and memory.min and memory.low, which
/// protect memory only up to what memory.max allows.
fn lowerUnified(arena: std.mem.Allocator, resources: *std.json.ObjectMap, profile: *const Profile) !void {
    const unified = resources.getPtr("unified") orelse return;
    // libcrun reads one that is not an object as none.
    if (unified.* != .object) return;
    if (profile.memory_limit) |limit| {
        try lowerFile(arena, &unified.object, "memory.max", limit);
        try lowerFile(arena, &unified.object, "memory.high", limit);
    }
    if (profile.pids_limit) |limit| try lowerFile(arena, &unified.object, "pids.max", limit);
}

/// Sets unified[file] to `limit` unless it already holds a number no higher,
/// written as the kernel takes it, in plain digits. "max", a value with a
/// suffix and anything that is not a string get the limit, as lowerTo gives
/// it to a value it cannot compare. 0 is kept: in a cgroup file it is a
/// limit of nothing, not the spec's "unset".
fn lowerFile(arena: std.mem.Allocator, unified: *std.json.ObjectMap, file: []const u8, limit: i64) !void {
    const v = unified.get(file) orelse return;
    if (v == .string and v.string.len > 0 and v.string.len <= 18) {
        const digits = for (v.string) |c| {
            if (c < '0' or c > '9') break false;
        } else true;
        if (digits and (std.fmt.parseInt(i64, v.string, 10) catch unreachable) <= limit) return;
    }
    try unified.put(file, .{ .string = try std.fmt.allocPrint(arena, "{d}", .{limit}) });
}

/// lowerTo for memory.limit, keeping the swap the bundle allowed. OCI's
/// memory.swap is memory plus swap, so lowering the limit alone would turn
/// the difference into swap: containerd sets swap to the limit to mean none,
/// and a 2Gi pod under a 1G profile could have swapped 1G.
fn lowerMemory(memory: *std.json.ObjectMap, limit: i64) !void {
    const before = memory.get("limit");
    try lowerTo(memory, "limit", limit);
    const old = before orelse return;
    if (old != .integer or old.integer <= limit) return;
    // Unlimited (-1), absent, or less than the limit, which libcrun refuses.
    const swap = memory.get("swap") orelse return;
    if (swap != .integer or swap.integer < old.integer) return;
    try memory.put("swap", .{ .integer = swap.integer - (old.integer - limit) });
}

fn expectRefused(spec: []const u8, profile: Profile, says: []const u8) !void {
    var why: Refusal = .{};
    try std.testing.expectError(error.ProfileRefused, narrow(std.testing.allocator, spec, &profile, &why));
    if (std.mem.indexOf(u8, why.text(), says) == null) {
        std.debug.print("got: {s}\n", .{why.text()});
        return error.TestUnexpectedRefusal;
    }
}

test "a profile name is a DNS label, and only a program name with @ names one" {
    try std.testing.expect(isValidName("hardened"));
    try std.testing.expect(isValidName("pve-small-2"));
    try std.testing.expect(!isValidName("Hardened"));
    try std.testing.expect(!isValidName("-x"));
    try std.testing.expect(!isValidName("x-"));
    try std.testing.expect(!isValidName(""));
    try std.testing.expect(!isValidName("a_b"));

    try std.testing.expectEqualStrings("hardened", fromProgramName("/usr/local/bin/nexcage@hardened").?);
    try std.testing.expectEqualStrings("", fromProgramName("nexcage@").?);
    try std.testing.expect(fromProgramName("/usr/local/bin/nexcage") == null);
    // The release files' names must not read as a profile.
    try std.testing.expect(fromProgramName("./nexcage-0.16.0-amd64-crun") == null);
}

test "a profile drops capabilities from every set, lowers limits, and marks the spec" {
    const spec =
        \\{"ociVersion":"1.0.0","process":{"args":["sh"],"capabilities":{
        \\  "bounding":["CAP_CHOWN","CAP_NET_RAW","CAP_KILL"],
        \\  "effective":["CAP_NET_RAW"],"permitted":["CAP_NET_RAW","CAP_KILL"]}},
        \\ "linux":{"resources":{"memory":{"limit":1073741824},"pids":{"limit":10}}}}
    ;
    const drop = [_][]const u8{"CAP_NET_RAW"};
    const profile = Profile{ .name = "hardened", .drop_capabilities = &drop, .memory_limit = 67108864, .pids_limit = 512 };
    var why: Refusal = .{};
    const out = try narrow(std.testing.allocator, spec, &profile, &why);
    defer std.testing.allocator.free(out);

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out, .{});
    defer parsed.deinit();
    const caps = parsed.value.object.get("process").?.object.get("capabilities").?.object;
    try std.testing.expectEqual(@as(usize, 2), caps.get("bounding").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), caps.get("effective").?.array.items.len);
    try std.testing.expectEqualStrings("CAP_KILL", caps.get("permitted").?.array.items[0].string);
    const res = parsed.value.object.get("linux").?.object.get("resources").?.object;
    // 1 GiB is lowered to the profile's 64 MiB; 10 pids is already lower than 512.
    try std.testing.expectEqual(@as(i64, 67108864), res.get("memory").?.object.get("limit").?.integer);
    try std.testing.expectEqual(@as(i64, 10), res.get("pids").?.object.get("limit").?.integer);
    try std.testing.expectEqualStrings("hardened", parsed.value.object.get("annotations").?.object.get(annotation).?.string);
}

test "a limit the bundle does not set is the profile's" {
    const profile = Profile{ .name = "p", .pids_limit = 64 };
    var why: Refusal = .{};
    const out = try narrow(std.testing.allocator, "{\"ociVersion\":\"1.0.0\",\"linux\":{\"resources\":{\"pids\":{\"limit\":-1}}}}", &profile, &why);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"limit\":64") != null);
}

test "a profile refuses a bundle without what it requires, and one that names a profile" {
    const plain = "{\"ociVersion\":\"1.0.0\",\"linux\":{\"namespaces\":[{\"type\":\"pid\"}]}}";
    try expectRefused(plain, .{ .name = "h", .require_user_namespace = true }, "requires a user namespace");
    try expectRefused(plain, .{ .name = "h", .require_seccomp = true }, "seccompProfile.type: RuntimeDefault");
    // A user namespace without mappings is not enough.
    try expectRefused("{\"linux\":{\"namespaces\":[{\"type\":\"user\"}]}}", .{ .name = "h", .require_user_namespace = true }, "requires a user namespace");
    try expectRefused("{\"annotations\":{\"io.cageforge.nexcage.profile\":\"other\"}}", .{ .name = "h" }, "which nexcage writes itself");

    const ok =
        \\{"linux":{"namespaces":[{"type":"user"}],
        \\ "uidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
        \\ "gidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
        \\ "seccomp":{"defaultAction":"SCMP_ACT_ERRNO"}}}
    ;
    var why: Refusal = .{};
    const out = try narrow(std.testing.allocator, ok, &.{ .name = "h", .require_user_namespace = true, .require_seccomp = true }, &why);
    std.testing.allocator.free(out);
}

test "without a profile, a bundle may not claim one, nor hide a claim in a duplicate key" {
    var why: Refusal = .{};
    try checkUnclaimed(std.testing.allocator, "{\"ociVersion\":\"1.0.0\",\"annotations\":{\"a\":\"b\"}}", &why);
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(std.testing.allocator, "{\"annotations\":{\"io.cageforge.nexcage.profile\":\"hardened\"}}", &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "which nexcage writes itself") != null);
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(std.testing.allocator, "{\"annotations\":{\"io.cageforge.nexcage.profile\":\"hardened\"},\"annotations\":{}}", &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "not valid JSON") != null);
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(std.testing.allocator, "[]", &why));
}

test "an exec into a container made under a profile gets no capability the container lacks" {
    const stored =
        \\{"process":{"capabilities":{"bounding":["CAP_CHOWN","CAP_KILL"]}},
        \\ "annotations":{"io.cageforge.nexcage.profile":"hardened"}}
    ;
    // What containerd sends: the capabilities from its own copy of the spec.
    const process =
        \\{"args":["sh"],"capabilities":{"bounding":["CAP_CHOWN","CAP_NET_RAW","CAP_KILL"],
        \\ "effective":["CAP_NET_RAW"],"permitted":["CAP_KILL","CAP_NET_RAW"],"ambient":["CAP_NET_RAW"]}}
    ;
    var why: Refusal = .{};
    const out = (try boundExec(std.testing.allocator, process, stored, &why)).?;
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "CAP_NET_RAW") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"bounding\":[\"CAP_CHOWN\",\"CAP_KILL\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"permitted\":[\"CAP_KILL\"]") != null);

    // Made without a profile, or a process with no capabilities of its own:
    // handed over untouched.
    try std.testing.expect(try boundExec(std.testing.allocator, process, "{\"process\":{}}", &why) == null);
    try std.testing.expect(try boundExec(std.testing.allocator, "{\"args\":[\"sh\"]}", stored, &why) == null);
    try std.testing.expectError(error.ProfileRefused, boundExec(std.testing.allocator, "{\"capabilities\":", stored, &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "the process spec is not valid JSON") != null);
}

test "lowering the memory limit keeps the swap the bundle allowed, and no more" {
    const profile = Profile{ .name = "p", .memory_limit = 1 << 30 };
    const cases = [_]struct { spec: []const u8, limit: i64, swap: ?i64 }{
        // containerd: swap equal to the limit, meaning none
        .{ .spec = "{\"linux\":{\"resources\":{\"memory\":{\"limit\":2147483648,\"swap\":2147483648}}}}", .limit = 1 << 30, .swap = 1 << 30 },
        // 1G of swap allowed stays 1G
        .{ .spec = "{\"linux\":{\"resources\":{\"memory\":{\"limit\":2147483648,\"swap\":3221225472}}}}", .limit = 1 << 30, .swap = 2 << 30 },
        .{ .spec = "{\"linux\":{\"resources\":{\"memory\":{\"limit\":2147483648,\"swap\":-1}}}}", .limit = 1 << 30, .swap = -1 },
        // already under the profile: untouched
        .{ .spec = "{\"linux\":{\"resources\":{\"memory\":{\"limit\":536870912,\"swap\":536870912}}}}", .limit = 536870912, .swap = 536870912 },
        .{ .spec = "{\"linux\":{}}", .limit = 1 << 30, .swap = null },
    };
    for (cases) |c| {
        var why: Refusal = .{};
        const out = try narrow(std.testing.allocator, c.spec, &profile, &why);
        defer std.testing.allocator.free(out);
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out, .{});
        defer parsed.deinit();
        const mem = parsed.value.object.get("linux").?.object.get("resources").?.object.get("memory").?.object;
        try std.testing.expectEqual(c.limit, mem.get("limit").?.integer);
        if (c.swap) |want| {
            try std.testing.expectEqual(want, mem.get("swap").?.integer);
        } else try std.testing.expect(mem.get("swap") == null);
    }
}

test "a key or a string with a NUL in it is refused: libcrun would read another bundle than the one checked" {
    // The profile checks the first process and linux; json-c reads the keys
    // as "process" and "linux" again, keeps the second of each, and that is
    // what libcrun would apply: CAP_SYS_ADMIN, and no user namespace.
    const smuggled =
        \\{"process":{"capabilities":{"bounding":["CAP_KILL"]}},
        \\ "linux":{"namespaces":[{"type":"user"}],
        \\  "uidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
        \\  "gidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
        \\  "seccomp":{"defaultAction":"SCMP_ACT_ERRNO"}},
        \\ "process\u0000":{"capabilities":{"bounding":["CAP_KILL","CAP_SYS_ADMIN"]}},
        \\ "linux\u0000":{"namespaces":[{"type":"pid"}]}}
    ;
    const drop = [_][]const u8{"CAP_SYS_ADMIN"};
    try expectRefused(smuggled, .{ .name = "h", .require_user_namespace = true, .require_seccomp = true, .drop_capabilities = &drop }, "has a NUL in the key at process\\u0000:");
    // A C string ends at the NUL, so this is CAP_SYS_ADMIN to libcap.
    try expectRefused(
        \\{"process":{"capabilities":{"bounding":["CAP_KILL","CAP_SYS_ADMIN\u0000x"]}}}
    , .{ .name = "h", .drop_capabilities = &drop }, "a NUL in the string at process.capabilities.bounding[1]");

    // Without a profile libcrun reads the file itself, so a claim behind a
    // NUL is a claim.
    var why: Refusal = .{};
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(std.testing.allocator,
        \\{"annotations":{"io.cageforge.nexcage.profile\u0000":"hardened"}}
    , &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "which nexcage writes itself") != null);
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(std.testing.allocator,
        \\{"annotations":{"a":"b"},"annotations\u0000":{"io.cageforge.nexcage.profile":"hardened"}}
    , &why));
    try checkUnclaimed(std.testing.allocator,
        \\{"annotations":{"io.cageforge.nexcage.profilex":"y"}}
    , &why);

    // An exec into a container made under a profile: without this,
    // "capabilities\u0000" was a process with no capabilities to cut, handed
    // to libcrun as it was, and libcrun read them as "capabilities".
    const stored =
        \\{"process":{"capabilities":{"bounding":["CAP_KILL"]}},
        \\ "annotations":{"io.cageforge.nexcage.profile":"hardened"}}
    ;
    try std.testing.expectError(error.ProfileRefused, boundExec(std.testing.allocator,
        \\{"args":["sh"],"capabilities\u0000":{"bounding":["CAP_SYS_ADMIN"],"effective":["CAP_SYS_ADMIN"]}}
    , stored, &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "the process spec has a NUL in the key at capabilities\\u0000:") != null);
}

test "a document nested deeper than any runtime spec is refused, not a panic" {
    // Past 256 levels std.json.Stringify panics in a safe build; the release
    // binary is one.
    const deep = "{\"x\":" ++ "[" ** 300 ++ "]" ** 300 ++ "}";
    try expectRefused(deep, .{ .name = "h" }, "the bundle's config.json nests deeper than 64 levels, at x[0][0]");
    // The deepest a profile takes: the top level and 63 lists inside it.
    const deepest = "{\"x\":" ++ "[" ** 63 ++ "]" ** 63 ++ "}";
    var why: Refusal = .{};
    std.testing.allocator.free(try narrow(std.testing.allocator, deepest, &.{ .name = "h" }, &why));
    try expectRefused("{\"x\":" ++ "[" ** 64 ++ "]" ** 64 ++ "}", .{ .name = "h" }, "nests deeper than 64 levels");

    const stored =
        \\{"process":{"capabilities":{"bounding":["CAP_KILL"]}},
        \\ "annotations":{"io.cageforge.nexcage.profile":"hardened"}}
    ;
    const process = "{\"capabilities\":{\"bounding\":[\"CAP_KILL\"]},\"x\":" ++ "[" ** 300 ++ "]" ** 300 ++ "}";
    try std.testing.expectError(error.ProfileRefused, boundExec(std.testing.allocator, process, stored, &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "the process spec nests deeper than 64 levels") != null);
}

test "the capability names are the kernel's, by number" {
    try std.testing.expectEqual(@as(usize, 41), capability_names.len);
    try std.testing.expectEqualStrings("CAP_NET_RAW", capability_names[13]);
    try std.testing.expectEqualStrings("CAP_SYS_ADMIN", capability_names[21]);
    try std.testing.expectEqualStrings("CAP_MKNOD", capability_names[27]);
    try std.testing.expectEqualStrings("CAP_SETFCAP", capability_names[31]);
    try std.testing.expectEqualStrings("CAP_CHECKPOINT_RESTORE", capability_names[40]);
    try std.testing.expect(isCapabilityName("CAP_SYS_ADMIN"));
    // What libcap's cap_from_name also reads as CAP_SYS_ADMIN, and a typo.
    for ([_][]const u8{ "cap_sys_admin", "Cap_Sys_Admin", "21", "0x15", "CAP_SYS_ADMIN1", "CAP_SYS_ADMIN ", "CAP_SYSADMIN", "" }) |n|
        try std.testing.expect(!isCapabilityName(n));
}

test "a capability spelt otherwise than the kernel spells it is refused: libcap would grant what the drop missed" {
    const drop = [_][]const u8{ "CAP_NET_RAW", "CAP_SYS_ADMIN" };
    const profile = Profile{ .name = "h", .drop_capabilities = &drop };
    // Each of these is CAP_NET_RAW or CAP_SYS_ADMIN to cap_from_name.
    const spellings = [_][]const u8{ "cap_net_raw", "Cap_Sys_Admin", "13", "0x15", "13junk", "CAP_NET_RAW2", "CAP_SYS_ADMIN " };
    for (spellings) |name| {
        var spec: [256]u8 = undefined;
        const json = try std.fmt.bufPrint(&spec, "{{\"process\":{{\"capabilities\":{{\"bounding\":[\"CAP_KILL\",\"{s}\"],\"effective\":[\"CAP_KILL\"]}}}}}}", .{name});
        try expectRefused(json, profile, "is not a capability name as the kernel spells it");
    }
    // json-c gives libcap a number's digits: 21 is CAP_SYS_ADMIN.
    try expectRefused("{\"process\":{\"capabilities\":{\"permitted\":[\"CAP_KILL\",21]}}}", profile, "process.capabilities.permitted holds a JSON number, where only capability names go");
    // Under any profile, not only one that drops: exec compares names with
    // what the container was made with.
    try expectRefused("{\"process\":{\"capabilities\":{\"ambient\":[\"cap_kill\"]}}}", .{ .name = "h" }, "process.capabilities.ambient lists \"cap_kill\"");

    const stored =
        \\{"process":{"capabilities":{"bounding":["CAP_CHOWN","CAP_KILL"]}},
        \\ "annotations":{"io.cageforge.nexcage.profile":"hardened"}}
    ;
    var why: Refusal = .{};
    try std.testing.expectError(error.ProfileRefused, boundExec(std.testing.allocator,
        \\{"args":["sh"],"capabilities":{"bounding":["CAP_KILL","cap_sys_admin"],"effective":["cap_sys_admin"]}}
    , stored, &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "the process spec's capabilities.bounding lists \"cap_sys_admin\"") != null);
}

test "a user namespace that leaves the container's root the host's is refused" {
    const userns = Profile{ .name = "h", .require_user_namespace = true };
    // Container root mapped to host root, the whole range or one id.
    try expectRefused(
        \\{"linux":{"namespaces":[{"type":"user"}],
        \\ "uidMappings":[{"containerID":0,"hostID":0,"size":4294967295}],
        \\ "gidMappings":[{"containerID":0,"hostID":100000,"size":65536}]}}
    , userns, "requires a user namespace that does not map host uid 0, and linux.uidMappings[0] maps it");
    try expectRefused(
        \\{"linux":{"namespaces":[{"type":"user"}],
        \\ "uidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
        \\ "gidMappings":[{"containerID":0,"hostID":100000,"size":1},{"containerID":1,"hostID":0,"size":1}]}}
    , userns, "does not map host gid 0, and linux.gidMappings[1] maps it");
    // libcrun reads a hostID that is not a 32-bit number as absent, and an
    // absent one as 0.
    for ([_][]const u8{ "\"hostID\":\"100000\",", "", "\"hostID\":4294967296,", "\"hostID\":-1,", "\"hostID\":1e5," }) |host| {
        var spec: [400]u8 = undefined;
        const json = try std.fmt.bufPrint(&spec,
            \\{{"linux":{{"namespaces":[{{"type":"user"}}],
            \\ "uidMappings":[{{"containerID":0,{s}"size":65536}}],
            \\ "gidMappings":[{{"containerID":0,"hostID":100000,"size":65536}}]}}}}
        , .{host});
        try expectRefused(json, userns, "linux.uidMappings[0] is not a range of whole numbers containerID, hostID and size");
    }

    // Joined by path, libcrun takes the namespace as it is and ignores the
    // mappings, which are clear of 0 here.
    const joined = .{
        .{ .path = "\"/proc/self/ns/user\"", .says = "a user namespace of the container's own, and the bundle joins /proc/self/ns/user, which is nexcage's" },
        .{ .path = "\"/proc/self/status\"", .says = "joins /proc/self/status, which is not a namespace" },
        .{ .path = "\"/proc/self/ns/net\"", .says = "joins /proc/self/ns/net, which is another kind of namespace" },
        .{ .path = "\"/proc/self/ns/nonesuch\"", .says = "cannot read the one the bundle joins, /proc/self/ns/nonesuch (FileNotFound)" },
        .{ .path = "\"ns/user\"", .says = "by a path that is not absolute" },
        .{ .path = "1", .says = "by a path that is not absolute" },
    };
    inline for (joined) |case| {
        const json =
            \\{"linux":{"namespaces":[{"type":"pid"},{"type":"user","path":
        ++ case.path ++
            \\}],
            \\ "uidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
            \\ "gidMappings":[{"containerID":0,"hostID":100000,"size":65536}]}}
        ;
        try expectRefused(json, userns, case.says);
    }
}

test "a uid_map is read as the kernel writes it" {
    try std.testing.expectEqual(@as(?bool, true), mapsZero("         0          0 4294967295\n"));
    try std.testing.expectEqual(@as(?bool, true), mapsZero("0 100000 65536\n65536 0 1\n"));
    try std.testing.expectEqual(@as(?bool, false), mapsZero("         0     100000      65536\n"));
    try std.testing.expectEqual(@as(?bool, false), mapsZero("0 1000 1\n1 100000 65536\n"));
    // Nothing mapped yet, or not a map: not something to pass.
    try std.testing.expectEqual(@as(?bool, null), mapsZero(""));
    try std.testing.expectEqual(@as(?bool, null), mapsZero("0 100000\n"));
    try std.testing.expectEqual(@as(?bool, null), mapsZero("0 x 1\n"));
    try std.testing.expectEqual(@as(?bool, null), mapsZero("0 100000 0\n"));
}

test "a user namespace joined by path is read from inside it, and one that leaves host root out passes" {
    // A pod's sandbox, as any user can make one: a child in a user namespace
    // of its own, mapping one id that is not host root. Skipped where user
    // namespaces cannot be made, as in some CI containers.
    const ready = try std.posix.pipe2(.{ .CLOEXEC = true });
    defer std.posix.close(ready[0]);
    const hold = try std.posix.pipe2(.{ .CLOEXEC = true });
    const pid = try std.posix.fork();
    if (pid == 0) {
        _ = os.close(hold[1]);
        if (os.unshare(os.CLONE.NEWUSER) != 0) os.exit_group(1);
        _ = os.write(ready[1], "u", 1);
        var b: [1]u8 = undefined;
        _ = os.read(hold[0], &b, 1);
        os.exit_group(0);
    }
    std.posix.close(ready[1]);
    std.posix.close(hold[0]);
    const holder = Inside{ .pid = pid, .hold = hold[1] };
    defer holder.leave();
    var b: [1]u8 = undefined;
    if (try std.posix.read(ready[0], &b) != 1) return error.SkipZigTest;

    var name: [64]u8 = undefined;
    var line: [64]u8 = undefined;
    const outside_uid = if (os.geteuid() == 0) 100000 else os.geteuid();
    const outside_gid = if (os.getegid() == 0) 100000 else os.getegid();
    const writes = [_]struct { file: []const u8, text: []const u8 }{
        .{ .file = "setgroups", .text = "deny" },
        .{ .file = "uid_map", .text = try std.fmt.bufPrint(line[0..32], "0 {d} 1", .{outside_uid}) },
        .{ .file = "gid_map", .text = try std.fmt.bufPrint(line[32..], "0 {d} 1", .{outside_gid}) },
    };
    for (writes) |w| {
        const f = std.fs.cwd().openFile(try std.fmt.bufPrint(&name, "/proc/{d}/{s}", .{ pid, w.file }), .{ .mode = .write_only }) catch return error.SkipZigTest;
        defer f.close();
        f.writeAll(w.text) catch return error.SkipZigTest;
    }

    var spec: [400]u8 = undefined;
    const json = try std.fmt.bufPrint(&spec,
        \\{{"linux":{{"namespaces":[{{"type":"user","path":"/proc/{d}/ns/user"}}],
        \\ "uidMappings":[{{"containerID":0,"hostID":100000,"size":65536}}],
        \\ "gidMappings":[{{"containerID":0,"hostID":100000,"size":65536}}]}}}}
    , .{pid});
    var why: Refusal = .{};
    const out = narrow(std.testing.allocator, json, &.{ .name = "h", .require_user_namespace = true }, &why) catch |err| {
        std.debug.print("refused: {s}\n", .{why.text()});
        return err;
    };
    std.testing.allocator.free(out);
}

test "linux.resources.unified does not undo a profile's limits" {
    const profile = Profile{ .name = "p", .memory_limit = 64 << 20, .pids_limit = 50 };
    const spec =
        \\{"linux":{"resources":{"memory":{"limit":67108864},"pids":{"limit":50},
        \\ "unified":{"memory.max":"max","memory.high":"1073741824","pids.max":"max",
        \\  "memory.swap.max":"max","memory.min":"1048576","io.weight":"100"}}}}
    ;
    var why: Refusal = .{};
    const out = try narrow(std.testing.allocator, spec, &profile, &why);
    defer std.testing.allocator.free(out);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out, .{});
    defer parsed.deinit();
    const unified = parsed.value.object.get("linux").?.object.get("resources").?.object.get("unified").?.object;
    try std.testing.expectEqualStrings("67108864", unified.get("memory.max").?.string);
    try std.testing.expectEqualStrings("67108864", unified.get("memory.high").?.string);
    try std.testing.expectEqualStrings("50", unified.get("pids.max").?.string);
    // Swap is the bundle's under a profile, as memory.swap is; the rest is
    // nothing a profile limits.
    try std.testing.expectEqualStrings("max", unified.get("memory.swap.max").?.string);
    try std.testing.expectEqualStrings("1048576", unified.get("memory.min").?.string);
    try std.testing.expectEqualStrings("100", unified.get("io.weight").?.string);

    // Lower than the profile: the bundle's. Unreadable to a comparison: the
    // profile's, as for the spec's own fields.
    const cases = [_]struct { value: []const u8, want: []const u8 }{
        .{ .value = "\"33554432\"", .want = "33554432" },
        .{ .value = "\"0\"", .want = "0" },
        .{ .value = "\"67108865\"", .want = "67108864" },
        .{ .value = "\"32M\"", .want = "67108864" },
        .{ .value = "\" 1024\"", .want = "67108864" },
        .{ .value = "\"-1\"", .want = "67108864" },
        .{ .value = "\"99999999999999999999\"", .want = "67108864" },
        .{ .value = "1024", .want = "67108864" },
    };
    for (cases) |c| {
        var buf: [200]u8 = undefined;
        const json = try std.fmt.bufPrint(&buf, "{{\"linux\":{{\"resources\":{{\"unified\":{{\"memory.max\":{s}}}}}}}}}", .{c.value});
        const narrowed = try narrow(std.testing.allocator, json, &.{ .name = "p", .memory_limit = 64 << 20 }, &why);
        defer std.testing.allocator.free(narrowed);
        var p = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, narrowed, .{});
        defer p.deinit();
        try std.testing.expectEqualStrings(c.want, p.value.object.get("linux").?.object.get("resources").?.object.get("unified").?.object.get("memory.max").?.string);
    }

    // A profile without a pids limit leaves pids.max to the bundle.
    const memory_only = try narrow(std.testing.allocator, "{\"linux\":{\"resources\":{\"unified\":{\"pids.max\":\"max\"}}}}", &.{ .name = "p", .memory_limit = 64 << 20 }, &why);
    defer std.testing.allocator.free(memory_only);
    try std.testing.expect(std.mem.indexOf(u8, memory_only, "\"pids.max\":\"max\"") != null);
}

test "a seccomp filter that refuses no system call does not meet a profile that requires one" {
    const profile = Profile{ .name = "h", .require_seccomp = true };
    const none = [_][]const u8{
        \\{"defaultAction":"SCMP_ACT_ALLOW"}
        ,
        \\{"defaultAction":"SCMP_ACT_LOG","syscalls":[{"names":["mount"],"action":"SCMP_ACT_ALLOW"}]}
        ,
        // A notifier decides in user space, whatever it listens with.
        \\{"defaultAction":"SCMP_ACT_NOTIFY","listenerPath":"/run/agent.sock"}
        ,
        \\{"defaultAction":"SCMP_ACT_ALLOW","listenerPath":"/run/agent.sock","syscalls":[{"names":["mount"],"action":"SCMP_ACT_NOTIFY"}]}
        ,
        \\{"defaultAction":"SCMP_ACT_ALLOW","syscalls":[{"names":["ptrace"],"action":"SCMP_ACT_TRACE"}]}
        ,
        // A refusing rule that names no call, or names one as a number.
        \\{"defaultAction":"SCMP_ACT_ALLOW","syscalls":[{"names":[],"action":"SCMP_ACT_ERRNO"},{"names":[165],"action":"SCMP_ACT_KILL"}]}
        ,
        \\{"defaultAction":"scmp_act_errno"}
        ,
        \\{"defaultAction":["SCMP_ACT_ERRNO"]}
        ,
    };
    for (none) |given| {
        var buf: [300]u8 = undefined;
        try expectRefused(try std.fmt.bufPrint(&buf, "{{\"linux\":{{\"seccomp\":{s}}}}}", .{given}), profile, "the bundle's refuses no system call");
    }
    const real = [_][]const u8{
        // RuntimeDefault, in short: refuse what is not allowed.
        \\{"defaultAction":"SCMP_ACT_ERRNO","defaultErrnoRet":1,"syscalls":[{"names":["read","write"],"action":"SCMP_ACT_ALLOW"}]}
        ,
        \\{"defaultAction":"SCMP_ACT_ALLOW","syscalls":[{"names":["mount","umount2"],"action":"SCMP_ACT_ERRNO"}]}
        ,
        \\{"defaultAction":"SCMP_ACT_NOTIFY","listenerPath":"/run/agent.sock","syscalls":[{"names":["kexec_load"],"action":"SCMP_ACT_KILL_PROCESS"}]}
        ,
    };
    for (real) |given| {
        var buf: [300]u8 = undefined;
        var why: Refusal = .{};
        std.testing.allocator.free(try narrow(std.testing.allocator, try std.fmt.bufPrint(&buf, "{{\"linux\":{{\"seccomp\":{s}}}}}", .{given}), &profile, &why));
    }
}
