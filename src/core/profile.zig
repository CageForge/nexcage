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

/// The profile's caps, recorded next to its name at create, in decimal: what
/// `update` holds the container to (boundUpdate). Recorded rather than read
/// from the profile again, because a profile may change or go after create
/// (decision 3) and a running container keeps what it was made with. Reserved
/// like the name: a bundle carrying either is refused.
pub const memory_cap_annotation = annotation ++ ".memory";
pub const pids_cap_annotation = annotation ++ ".pids";

pub const Profile = struct {
    name: []const u8,
    runtime: types.RuntimeType = .crun,
    /// Refuse a bundle without a user namespace and uid/gid mappings, or with
    /// one that maps host uid or gid 0, or that keeps nexcage's own groups.
    /// Nothing is added: who owns the root filesystem is the engine's to
    /// arrange.
    require_user_namespace: bool = false,
    /// Refuse a bundle without a seccomp filter that refuses some system
    /// call, or with a precompiled program libcrun would install instead.
    /// nexcage ships no filter.
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

/// What create hands libcrun instead of the bytes it read: with a profile,
/// the spec narrowed by it, which the caller owns; without one, null, and
/// libcrun gets those bytes. Either way a bundle that claims a profile is
/// refused, and so is one libcrun would read otherwise than parse does.
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
    try refuseClaim(root, why);
    try checkCapabilityNames(capabilitiesOf(root.get("process")), "the bundle's process.capabilities", why);

    const linux = try child(arena, root, "linux");

    if (profile.require_user_namespace) {
        try checkUserNamespace(linux, profile, why);
        try refuseKeptGroups(root, profile, why);
    }

    if (profile.require_seccomp) {
        try checkSeccomp(linux, profile, why);
        try refusePrecompiledSeccomp(root, profile, why);
    }

    if (profile.drop_capabilities.len > 0) dropCapabilities(root, profile.drop_capabilities);

    if (profile.memory_limit != null or profile.pids_limit != null) {
        const resources = try child(arena, linux, "resources");
        if (profile.memory_limit) |limit| try lowerMemory(try child(arena, resources, "memory"), limit);
        if (profile.pids_limit) |limit| try lowerTo(try child(arena, resources, "pids"), "limit", limit);
        try lowerUnified(arena, resources, profile);
    }

    // Looked up again, not kept from above: adding a key to the root may
    // move the objects it holds.
    const marks = try child(arena, root, "annotations");
    try marks.put(annotation, .{ .string = profile.name });
    // The caps themselves, not the limits lowered to them: a bundle that
    // asked for less than a cap may still be resized up to it.
    if (profile.memory_limit) |cap| try marks.put(memory_cap_annotation, .{ .string = try std.fmt.allocPrint(arena, "{d}", .{cap}) });
    if (profile.pids_limit) |cap| try marks.put(pids_cap_annotation, .{ .string = try std.fmt.allocPrint(arena, "{d}", .{cap}) });
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

    // parse refuses "capabilities\u0000", which is "capabilities" to libcrun,
    // before anything is taken from the spec or it is found to have nothing
    // to cut.
    var process = try parse(allocator, process_json, "the process spec", why);
    defer process.deinit();
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
                return why.set("{s}.{s} lists \"{f}\", which is not a capability name as the kernel spells it, such as \"CAP_NET_RAW\"; libcrun could read it as one the profile does not see", .{ at, set_name, shown(item.string) });
        }
    }
}

/// Refuses an `update` of a container made under a profile that would take
/// memory or pids above the caps recorded at create, or to no limit at all.
/// An engine builds an update from its own copy of the spec, from before the
/// profile lowered it, and libcrun writes what it is given into the cgroup:
/// containerd's in-place resize sent the pod's own 8Gi, and `update --memory
/// -1 --pids-limit -1` took both caps off, while `state` still named the
/// profile. Refused rather than lowered to the cap, so that the caller is
/// not told a value took that did not. A resize within the caps is let
/// through as it is, and so is a container made without a profile or under
/// one without caps.
///
/// `resources_json` is the linux.resources document libcrun is about to
/// read; without one, `values` are the command line's settings in crun's
/// section/name form, which is what libcrun turns into one.
pub fn boundUpdate(allocator: std.mem.Allocator, container_json: []const u8, resources_json: ?[]const u8, values: []const types.ResourceUpdate, why: *Refusal) !void {
    const container = try parse(allocator, container_json, "the container's stored config.json", why);
    defer container.deinit();
    const marks_value = container.value.object.get("annotations") orelse return;
    if (marks_value != .object) return;
    const marks = marks_value.object;
    const named = marks.get(annotation) orelse return;
    const caps = Caps{
        .profile = if (named == .string) named.string else "",
        .memory = try recordedCap(marks, memory_cap_annotation, why),
        .pids = try recordedCap(marks, pids_cap_annotation, why),
    };
    if (caps.memory == null and caps.pids == null) return;

    const doc = resources_json orelse {
        for (values) |v| {
            const field: Field = if (std.mem.eql(u8, v.section, "memory") and std.mem.eql(u8, v.name, "limit"))
                .memory_limit
            else if (std.mem.eql(u8, v.section, "memory") and std.mem.eql(u8, v.name, "swap"))
                .memory_swap
            else if (std.mem.eql(u8, v.section, "pids") and std.mem.eql(u8, v.name, "limit"))
                .pids_limit
            else
                continue;
            try caps.check(field, wholeNumber(v.value), v.value, why);
        }
        return;
    };

    // The document as libcrun reads it: the resources object itself.
    var parsed = try parse(allocator, doc, "the resources document", why);
    defer parsed.deinit();
    const r = &parsed.value.object;
    if (r.get("memory")) |m| {
        if (m != .object) return why.set("the resources document's memory is not an object", .{});
        try caps.checkJson(.memory_limit, m.object.get("limit"), why);
        try caps.checkJson(.memory_swap, m.object.get("swap"), why);
    }
    if (r.get("pids")) |p| {
        if (p != .object) return why.set("the resources document's pids is not an object", .{});
        try caps.checkJson(.pids_limit, p.object.get("limit"), why);
    }
    // cgroup v2 files by name, which libcrun writes after everything else.
    if (r.get("unified")) |u| {
        if (u != .object) return why.set("the resources document's unified is not an object", .{});
        var it = u.object.iterator();
        while (it.next()) |e| {
            const field: Field = if (std.mem.eql(u8, e.key_ptr.*, "memory.max"))
                .unified_memory_max
            else if (std.mem.eql(u8, e.key_ptr.*, "memory.swap.max"))
                .unified_memory_swap_max
            else if (std.mem.eql(u8, e.key_ptr.*, "pids.max"))
                .unified_pids_max
            else
                continue;
            if (e.value_ptr.* != .string) return why.set("unified {s} is not a string", .{e.key_ptr.*});
            const text = e.value_ptr.string;
            // Digits only: the kernel also takes "max" and sizes like "8G",
            // and a cap compares against bytes.
            const n: ?i64 = for (text) |c| {
                if (!std.ascii.isDigit(c)) break null;
            } else std.fmt.parseInt(i64, text, 10) catch null;
            try caps.check(field, n, text, why);
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

const Field = enum {
    memory_limit,
    memory_swap,
    pids_limit,
    unified_memory_max,
    unified_memory_swap_max,
    unified_pids_max,

    fn name(f: Field) []const u8 {
        return switch (f) {
            .memory_limit => "memory.limit",
            .memory_swap => "memory.swap",
            .pids_limit => "pids.limit",
            .unified_memory_max => "unified memory.max",
            .unified_memory_swap_max => "unified memory.swap.max",
            .unified_pids_max => "unified pids.max",
        };
    }
};

const Caps = struct {
    profile: []const u8,
    memory: ?i64,
    pids: ?i64,

    /// `n` is the value as a whole number, null when `text` is not one.
    fn check(caps: Caps, field: Field, n: ?i64, text: []const u8, why: *Refusal) error{ProfileRefused}!void {
        const cap = switch (field) {
            .pids_limit, .unified_pids_max => caps.pids,
            else => caps.memory,
        } orelse return;
        const unit = switch (field) {
            .pids_limit, .unified_pids_max => "",
            else => " bytes",
        };
        const v = n orelse {
            if (std.mem.eql(u8, text, "max")) return why.set("profile '{s}' caps {s} at {d}{s}, and the update asks for max, which is no limit", .{ caps.profile, field.name(), cap, unit });
            return why.set("profile '{s}' caps {s} at {d}{s}, and the update asks for '{s}', which is not a whole number", .{ caps.profile, field.name(), cap, unit, text });
        };
        const lowest: i64 = switch (field) {
            // No memory at all is no use to anyone, and -1 is no limit.
            .memory_limit => 1,
            // libcrun leaves pids.max as it is for a limit of 0.
            else => 0,
        };
        // A negative value is "max" to libcrun; a memory.limit of 0 it
        // writes as it is, and memory.max 0 leaves the container no memory.
        if (v < lowest) return why.set("profile '{s}' caps {s} at {d}{s}, and the update asks for {d}, {s}", .{ caps.profile, field.name(), cap, unit, v, if (v < 0) "which is no limit" else "which is not a usable limit" });
        if (v > cap) return why.set("profile '{s}' caps {s} at {d}{s}, and the update asks for {d}", .{ caps.profile, field.name(), cap, unit, v });
    }

    fn checkJson(caps: Caps, field: Field, value: ?std.json.Value, why: *Refusal) error{ProfileRefused}!void {
        const v = value orelse return;
        switch (v) {
            .null => return,
            .integer => |i| return caps.check(field, i, "", why),
            else => return caps.check(field, null, @tagName(v), why),
        }
    }
};

/// A cap recorded at create, or null when the profile set none. One that does
/// not read back as a number refuses the update: it was written by nexcage,
/// and guessing would be choosing a limit.
fn recordedCap(marks: std.json.ObjectMap, key: []const u8, why: *Refusal) error{ProfileRefused}!?i64 {
    const v = marks.get(key) orelse return null;
    if (v == .string) if (wholeNumber(v.string)) |n| return n;
    return why.set("the container's recorded cap {s} is not a number; refusing to update it", .{key});
}

/// Decimal digits with an optional leading minus, and nothing else.
fn wholeNumber(text: []const u8) ?i64 {
    const digits = if (text.len > 0 and text[0] == '-') text[1..] else text;
    if (digits.len == 0) return null;
    for (digits) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseInt(i64, text, 10) catch null;
}

fn capabilitiesOf(process: ?std.json.Value) ?std.json.ObjectMap {
    const p = process orelse return null;
    if (p != .object) return null;
    const c = p.object.get("capabilities") orelse return null;
    return if (c == .object) c.object else null;
}

/// A JSON object, or a refusal: a document read as libcrun will read it, for
/// whatever checks it before libcrun does, with a profile or without: the
/// bundle's spec, update's resources document, exec's process spec and the
/// container's stored config. Duplicate keys are refused too: libcrun's
/// parser would read one of them and this one the other. So is a NUL in a
/// key or a string, which libcrun reads up to the NUL, and nesting deeper
/// than any runtime spec (checkDocument).
pub fn parse(allocator: std.mem.Allocator, json: []const u8, what: []const u8, why: *Refusal) !std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return why.set("{s} is not valid JSON ({s})", .{ what, @errorName(err) }),
    };
    errdefer parsed.deinit();
    if (parsed.value != .object) return why.set("{s} is not a JSON object", .{what});
    try checkDocument(parsed.value, what, why);
    return parsed;
}

/// The record `state` reports must be one nexcage wrote: the profile's name
/// and every annotation under it, the recorded caps among them. Keys are
/// compared whole: parse has refused "annotations\u0000" and
/// "io.cageforge.nexcage.profile\u0000", which are those keys to libcrun.
fn refuseClaim(root: *const std.json.ObjectMap, why: *Refusal) error{ProfileRefused}!void {
    const a = root.get("annotations") orelse return;
    if (a != .object) return;
    for (a.object.keys()) |key| {
        if (std.mem.eql(u8, key, annotation) or std.mem.startsWith(u8, key, annotation ++ "."))
            return why.set("the bundle carries the annotation {s}, which nexcage writes itself", .{key});
    }
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
/// drop the same way, and {"limit":33554432,"limit\u0000":-1} past update's
/// caps and the driver's memory checks. No runtime spec has a NUL anywhere,
/// so every key and string is refused for one, and so is nesting deeper than
/// max_depth. Every document parse reads goes through here.
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
    return why.set("{s} has a NUL in the {s} at {s}: libcrun's parser ends a {s} there, so it would read something other than what nexcage checked", .{ what, kind, at.text(), kind });
}

/// Where in a document a refusal points, as linux.namespaces[1].path. A NUL
/// or another control character in a key is written as \u0000, as Shown
/// writes it.
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
        var w: std.Io.Writer = .fixed(self.buf[self.len..]);
        // A fixed writer fails only when it is full: what fits is kept, and
        // the rest cut, as put cuts.
        w.print("{f}", .{shown(name)}) catch {};
        self.len += w.end;
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

/// A string from the bundle, as a refusal shows it with `{f}`: a control
/// character is written escaped, a newline as \u000a, so that a bundle cannot
/// start a line of its own, or move the cursor, in the log the engine keeps
/// of the message. That is C0, DEL, and C1, which UTF-8 writes as 0xc2 then
/// 0x80 to 0x9f: U+009B is a terminal's CSI, as ESC [ is. std.json refuses
/// a document that is not UTF-8, so no other byte of 0x80 to 0x9f stands
/// for one.
const Shown = struct {
    s: []const u8,

    pub fn format(self: Shown, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var i: usize = 0;
        while (i < self.s.len) : (i += 1) {
            const c = self.s[i];
            if (c == 0xc2 and i + 1 < self.s.len and self.s[i + 1] >= 0x80 and self.s[i + 1] <= 0x9f) {
                i += 1;
                try w.print("\\u{x:0>4}", .{self.s[i]});
            } else if (c < 0x20 or c == 0x7f) {
                try w.print("\\u{x:0>4}", .{c});
            } else try w.writeByte(c);
        }
    }
};

fn shown(s: []const u8) Shown {
    return .{ .s = s };
}

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
/// has is skipped by libcrun, and still counts here, and so does a rule whose
/// args conditions no call can meet. Refusing rules with args would refuse
/// real filters, such as one that refuses clone(CLONE_NEWUSER) only.
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

/// libcrun's annotation for a seccomp program compiled elsewhere: base64 BPF,
/// installed in place of the filter libcrun would compile from linux.seccomp,
/// for the container and for every exec into it.
const precompiled_seccomp = "run.oci.seccomp_bpf_data";

/// require_seccomp, the other way in: with the annotation, the filter
/// checkSeccomp judged is never installed, and a program nexcage cannot read
/// is, which may let every call through. It is refused whatever it holds:
/// libcrun uses any value in place of linux.seccomp.
fn refusePrecompiledSeccomp(root: *const std.json.ObjectMap, profile: *const Profile, why: *Refusal) error{ProfileRefused}!void {
    if (annotationOf(root, precompiled_seccomp) == null) return;
    return why.set("profile '{s}' requires a seccomp filter nexcage can judge, and the bundle's annotation {s} has libcrun install a precompiled program in place of linux.seccomp; leave it out", .{ profile.name, precompiled_seccomp });
}

/// One of the bundle's annotations, as libcrun finds it. Keys are compared
/// whole: parse has refused a key with a NUL in it, and a key given twice.
fn annotationOf(root: *const std.json.ObjectMap, name: []const u8) ?std.json.Value {
    const marks = root.get("annotations") orelse return null;
    if (marks != .object) return null;
    return marks.object.get(name);
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

/// libcrun's annotation for keeping the caller's supplementary groups: with
/// any value but "0" it skips setgroups, and the container's process keeps
/// nexcage's own groups in place of process.user's.
const keep_groups = "run.oci.keep_original_groups";

/// require_user_namespace, the other way in: a supplementary group is a host
/// gid, which no gid_map limits. nexcage's own, gid 0 among them when it runs
/// from a root shell, would follow the container into a namespace that leaves
/// host gid 0 out, and open what the host's group 0 may open.
fn refuseKeptGroups(root: *const std.json.ObjectMap, profile: *const Profile, why: *Refusal) error{ProfileRefused}!void {
    const keep = annotationOf(root, keep_groups) orelse return;
    if (keep == .string and std.mem.eql(u8, keep.string, "0")) return;
    return why.set("profile '{s}' requires a user namespace that leaves host gid 0 out, and the bundle's annotation {s} keeps nexcage's own supplementary groups, which are host gids, in the container", .{ profile.name, keep_groups });
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
        return why.set("profile '{s}' requires a user namespace, and the bundle joins {f}, which is not a namespace", .{ profile.name, shown(p) });
    if (named.ino == own.ino)
        return why.set("profile '{s}' requires a user namespace of the container's own, and the bundle joins {f}, which is nexcage's", .{ profile.name, shown(p) });

    const fd = std.posix.open(p, .{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NONBLOCK = true }, 0) catch |err| return unchecked(profile, p, err, why);
    defer std.posix.close(fd);
    const opened = std.posix.fstat(fd) catch |err| return unchecked(profile, p, err, why);
    if (opened.dev != named.dev or opened.ino != named.ino)
        return why.set("profile '{s}' requires a user namespace nexcage can check, and {f} changed while it was checked", .{ profile.name, shown(p) });
    if (os.ioctl(fd, ns_get_nstype, 0) != os.CLONE.NEWUSER)
        return why.set("profile '{s}' requires a user namespace, and the bundle joins {f}, which is another kind of namespace", .{ profile.name, shown(p) });

    const inside = Inside.join(fd) catch |err| return unchecked(profile, p, err, why);
    defer inside.leave();
    var file: [64]u8 = undefined;
    const joined = std.posix.fstatat(std.posix.AT.FDCWD, std.fmt.bufPrint(&file, "/proc/{d}/ns/user", .{inside.pid}) catch unreachable, 0) catch |err| return unchecked(profile, p, err, why);
    if (joined.dev != named.dev or joined.ino != named.ino)
        return why.set("profile '{s}' requires a user namespace nexcage can check, and {f} changed while it was checked", .{ profile.name, shown(p) });
    var buf: [16 * 1024]u8 = undefined;
    for ([_][]const u8{ "uid_map", "gid_map" }) |name| {
        const map = std.fs.cwd().readFile(std.fmt.bufPrint(&file, "/proc/{d}/{s}", .{ inside.pid, name }) catch unreachable, &buf) catch |err| return unchecked(profile, p, err, why);
        const id = name[0..3];
        // A full buffer may be a cut one; the kernel allows 340 lines.
        const verdict = if (map.len == buf.len) null else mapsZero(map);
        const zero = verdict orelse
            return why.set("profile '{s}' requires a user namespace nexcage can check, and the {s} of the one the bundle joins, {f}, does not read as a map", .{ profile.name, name, shown(p) });
        if (zero)
            return why.set("profile '{s}' requires a user namespace that does not map host {s} 0, and the one the bundle joins, {f}, maps it: root in the container would be root on the host", .{ profile.name, id, shown(p) });
    }
}

fn unchecked(profile: *const Profile, path: []const u8, err: anyerror, why: *Refusal) error{ProfileRefused} {
    return why.set("profile '{s}' requires a user namespace nexcage can check, and it cannot read the one the bundle joins, {f} ({s})", .{ profile.name, shown(path), @errorName(err) });
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

    // Without a profile libcrun reads the bundle as it is, so a claim behind
    // a NUL would be a claim to it: refused for the NUL, as under one.
    var why: Refusal = .{};
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(std.testing.allocator,
        \\{"annotations":{"io.cageforge.nexcage.profile\u0000":"hardened"}}
    , &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "the bundle's config.json has a NUL in the key at annotations.io.cageforge.nexcage.profile\\u0000:") != null);
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(std.testing.allocator,
        \\{"annotations":{"a":"b"},"annotations\u0000":{"io.cageforge.nexcage.profile":"hardened"}}
    , &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "has a NUL in the key at annotations\\u0000:") != null);
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
    // Objects nest as lists do.
    const deep_objects = "{\"x\":" ++ "{\"a\":" ** 300 ++ "1" ++ "}" ** 301;
    try expectRefused(deep_objects, .{ .name = "h" }, "the bundle's config.json nests deeper than 64 levels, at x.a.a");
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
    // Where a namespace can be made but not joined (a seccomp filter that
    // allows unshare and not setns), there is nothing to check here. Its
    // owner joins it with nothing mapped yet.
    {
        const fd = try std.posix.open(try std.fmt.bufPrint(&name, "/proc/{d}/ns/user", .{pid}), .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
        defer std.posix.close(fd);
        const probe = Inside.join(fd) catch return error.SkipZigTest;
        probe.leave();
    }

    var spec: [400]u8 = undefined;
    const json = try std.fmt.bufPrint(&spec,
        \\{{"linux":{{"namespaces":[{{"type":"user","path":"/proc/{d}/ns/user"}}],
        \\ "uidMappings":[{{"containerID":0,"hostID":100000,"size":65536}}],
        \\ "gidMappings":[{{"containerID":0,"hostID":100000,"size":65536}}]}}}}
    , .{pid});
    // A namespace that maps nothing yet is not one that leaves host root
    // out: whoever owns it can still map 0, if that is theirs to map.
    var says: [128]u8 = undefined;
    try expectRefused(json, .{ .name = "h", .require_user_namespace = true }, try std.fmt.bufPrint(&says, "the uid_map of the one the bundle joins, /proc/{d}/ns/user, does not read as a map", .{pid}));

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

test "a precompiled seccomp program does not meet a profile that requires a filter: libcrun installs it in place of the one judged" {
    const profile = Profile{ .name = "h", .require_seccomp = true };
    // RuntimeDefault in linux.seccomp, and beside it a program that lets
    // every call through: load the arch, load the number, return ALLOW.
    const smuggled =
        \\{"linux":{"seccomp":{"defaultAction":"SCMP_ACT_ERRNO","syscalls":[{"names":["read","write"],"action":"SCMP_ACT_ALLOW"}]}},
        \\ "annotations":{"run.oci.seccomp_bpf_data":"IAAAAAQAAAAgAAAAAAAAAAYAAAAAAP9/"}}
    ;
    try expectRefused(smuggled, profile, "annotation run.oci.seccomp_bpf_data has libcrun install a precompiled program");
    // Whatever it holds.
    try expectRefused(
        \\{"linux":{"seccomp":{"defaultAction":"SCMP_ACT_ERRNO"}},"annotations":{"run.oci.seccomp_bpf_data":""}}
    , profile, "run.oci.seccomp_bpf_data");

    var why: Refusal = .{};
    // Other annotations are the bundle's own.
    std.testing.allocator.free(try narrow(std.testing.allocator,
        \\{"linux":{"seccomp":{"defaultAction":"SCMP_ACT_ERRNO"}},"annotations":{"run.oci.seccomp_fail_unknown_syscall":"1"}}
    , &profile, &why));
    // A profile that requires no filter does not judge which one is installed.
    std.testing.allocator.free(try narrow(std.testing.allocator, smuggled, &.{ .name = "p" }, &why));
}

test "a bundle that keeps nexcage's own groups does not meet a profile that requires a user namespace" {
    const profile = Profile{ .name = "h", .require_user_namespace = true };
    const userns =
        \\{"linux":{"namespaces":[{"type":"user"}],
        \\ "uidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
        \\ "gidMappings":[{"containerID":0,"hostID":100000,"size":65536}]},
        \\ "annotations":{"run.oci.keep_original_groups":
    ;
    // libcrun skips setgroups for anything but "0".
    for ([_][]const u8{ "\"1\"", "\"\"", "\"false\"", "0" }) |value| {
        var buf: [400]u8 = undefined;
        try expectRefused(try std.fmt.bufPrint(&buf, "{s}{s}}}}}", .{ userns, value }), profile, "annotation run.oci.keep_original_groups keeps nexcage's own supplementary groups");
    }
    var why: Refusal = .{};
    std.testing.allocator.free(try narrow(std.testing.allocator, userns ++ "\"0\"}}", &profile, &why));
    // Without the requirement, the groups are the bundle's to keep.
    std.testing.allocator.free(try narrow(std.testing.allocator, userns ++ "\"1\"}}", &.{ .name = "p" }, &why));
}

test "a refusal shows the bundle's strings with control characters escaped: it writes no line of its own into a log" {
    // A newline, a forged log line, and the escape that erases a line,
    // written as ESC [ and as the one character CSI; then DEL.
    const forged = "\\n[INFO] nexcage: create completed\\u001b[2K\\u009b2K\\u007f";
    const cases = [_]struct { []const u8, Profile }{
        .{ "{\"process\":{\"capabilities\":{\"bounding\":[\"CAP_X" ++ forged ++ "\"]}}}", .{ .name = "h" } },
        // A key, as a refusal's path shows it.
        .{ "{\"x\\u0000" ++ forged ++ "\":1}", .{ .name = "h" } },
        .{
            \\{"linux":{"uidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
            \\ "gidMappings":[{"containerID":0,"hostID":100000,"size":65536}],
            \\ "namespaces":[{"type":"user","path":"/nonexistent
            ++ forged ++ "\"}]}}",
            .{ .name = "h", .require_user_namespace = true },
        },
    };
    for (cases) |c| {
        var why: Refusal = .{};
        try std.testing.expectError(error.ProfileRefused, narrow(std.testing.allocator, c[0], &c[1], &why));
        const text = why.text();
        if (std.mem.indexOfAny(u8, text, "\n\x1b\x7f") != null or std.mem.indexOf(u8, text, "\u{9b}") != null or
            std.mem.indexOf(u8, text, "\\u000a[INFO] nexcage: create completed\\u001b[2K\\u009b2K\\u007f") == null)
        {
            std.debug.print("got: {s}\n", .{text});
            return error.TestUnexpectedRefusal;
        }
    }
}

test "update holds a container made under a profile to the caps recorded at create" {
    const allocator = std.testing.allocator;
    const profile = Profile{ .name = "hardened", .memory_limit = 67108864, .pids_limit = 50 };
    var why: Refusal = .{};
    // What libcrun keeps as the container's config.json.
    const stored = try narrow(allocator, "{\"ociVersion\":\"1.0.0\",\"linux\":{\"resources\":{\"memory\":{\"limit\":1073741824,\"swap\":1073741824}}}}", &profile, &why);
    defer allocator.free(stored);

    // containerd's resize, from its copy of the spec from before the profile
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, stored, "{\"memory\":{\"limit\":8589934592,\"swap\":8589934592},\"cpu\":{\"shares\":512}}", &.{}, &why));
    try std.testing.expectEqualStrings("profile 'hardened' caps memory.limit at 67108864 bytes, and the update asks for 8589934592", why.text());
    const refused = [_][]const u8{
        "{\"memory\":{\"limit\":-1}}",
        "{\"memory\":{\"limit\":0}}",
        "{\"memory\":{\"limit\":33554432,\"swap\":-1}}",
        "{\"memory\":{\"limit\":33554432,\"swap\":134217728}}",
        "{\"memory\":{\"limit\":1.5e9}}",
        "{\"memory\":{\"limit\":\"33554432\"}}",
        "{\"memory\":\"lots\"}",
        "{\"pids\":{\"limit\":500}}",
        "{\"pids\":{\"limit\":-1}}",
        "{\"unified\":{\"memory.max\":\"max\"}}",
        "{\"unified\":{\"memory.max\":\"8G\"}}",
        "{\"unified\":{\"memory.swap.max\":\"max\"}}",
        "{\"unified\":{\"pids.max\":\"51\"}}",
        "{\"unified\":{\"pids.max\":\"max\"}}",
        // two of the same key: libcrun's parser would read the second
        "{\"pids\":{\"limit\":40,\"limit\":500}}",
        // and so they are to it when one ends in a NUL
        "{\"memory\":{\"limit\":33554432,\"limit\\u0000\":1073741824}}",
        "{\"memory\":{\"limit\":33554432},\"memory\\u0000\":{\"limit\":-1}}",
        "{\"unified\":{\"memory.max\\u0000\":\"max\"}}",
        "{\"pids\":{\"limit\":40,\"limit\\u0000\":-1}}",
    };
    for (refused) |doc| {
        boundUpdate(allocator, stored, doc, &.{}, &why) catch |err| {
            try std.testing.expectEqual(error.ProfileRefused, err);
            continue;
        };
        std.debug.print("let through: {s}\n", .{doc});
        return error.TestExpectedRefusal;
    }
    const pids_over = [_]types.ResourceUpdate{.{ .section = "pids", .name = "limit", .value = "999", .numeric = true }};
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, stored, null, &pids_over, &why));
    try std.testing.expectEqualStrings("profile 'hardened' caps pids.limit at 50, and the update asks for 999", why.text());
    const unlimited = [_]types.ResourceUpdate{.{ .section = "memory", .name = "limit", .value = "-1", .numeric = true }};
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, stored, null, &unlimited, &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "which is no limit") != null);
    const no_memory = [_]types.ResourceUpdate{.{ .section = "memory", .name = "limit", .value = "0", .numeric = true }};
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, stored, null, &no_memory, &why));
    try std.testing.expectEqualStrings("profile 'hardened' caps memory.limit at 67108864 bytes, and the update asks for 0, which is not a usable limit", why.text());

    // Within the caps, up to them from below, and what the caps do not name.
    const allowed = [_][]const u8{
        "{\"memory\":{\"limit\":33554432,\"swap\":33554432},\"pids\":{\"limit\":40}}",
        "{\"memory\":{\"limit\":67108864,\"swap\":67108864},\"pids\":{\"limit\":50}}",
        "{\"cpu\":{\"shares\":512,\"quota\":-1}}",
        "{\"pids\":{\"limit\":0}}",
        "{\"unified\":{\"memory.max\":\"33554432\",\"memory.high\":\"max\",\"pids.max\":\"50\"}}",
    };
    for (allowed) |doc| try boundUpdate(allocator, stored, doc, &.{}, &why);
    const within = [_]types.ResourceUpdate{
        .{ .section = "memory", .name = "limit", .value = "33554432", .numeric = true },
        .{ .section = "cpu", .name = "quota", .value = "-1", .numeric = true },
    };
    try boundUpdate(allocator, stored, null, &within, &why);
}

test "update is not bounded without a profile or its caps, and the caps cannot be claimed" {
    const allocator = std.testing.allocator;
    var why: Refusal = .{};
    const unlimited = "{\"memory\":{\"limit\":-1},\"pids\":{\"limit\":-1}}";
    try boundUpdate(allocator, "{\"ociVersion\":\"1.0.0\"}", unlimited, &.{}, &why);
    // A profile that caps neither, as made before the caps were recorded.
    try boundUpdate(allocator, "{\"annotations\":{\"io.cageforge.nexcage.profile\":\"p\"}}", unlimited, &.{}, &why);
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, "{\"annotations\":{\"io.cageforge.nexcage.profile\":\"p\",\"io.cageforge.nexcage.profile.pids\":\"lots\"}}", unlimited, &.{}, &why));

    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(allocator, "{\"annotations\":{\"io.cageforge.nexcage.profile.memory\":\"1099511627776\"}}", &why));
    try std.testing.expectEqualStrings("the bundle carries the annotation io.cageforge.nexcage.profile.memory, which nexcage writes itself", why.text());
    try expectRefused("{\"annotations\":{\"io.cageforge.nexcage.profile.pids\":\"1\"}}", .{ .name = "h", .pids_limit = 10 }, "which nexcage writes itself");
}

test "a NUL in a key or a string, or nesting past any runtime spec, is refused in every document read" {
    const allocator = std.testing.allocator;
    var why: Refusal = .{};
    const ends = ": libcrun's parser ends a key there, so it would read something other than what nexcage checked";
    const stored = "{\"annotations\":{\"io.cageforge.nexcage.profile\":\"hardened\",\"io.cageforge.nexcage.profile.memory\":\"67108864\",\"io.cageforge.nexcage.profile.pids\":\"50\"}}";
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, stored, "{\"memory\":{\"limit\":33554432,\"limit\\u0000\":1073741824}}", &.{}, &why));
    try std.testing.expectEqualStrings("the resources document has a NUL in the key at memory.limit\\u0000" ++ ends, why.text());
    // update under a profile is walked as create and exec under one are: a
    // NUL in a string, and nesting no runtime spec has.
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, stored, "{\"unified\":{\"memory.high\":\"33554432\\u0000\"}}", &.{}, &why));
    try std.testing.expectEqualStrings("the resources document has a NUL in the string at unified.memory.high: libcrun's parser ends a string there, so it would read something other than what nexcage checked", why.text());
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, stored, "{\"x\":" ++ "[" ** 300 ++ "]" ** 300 ++ "}", &.{}, &why));
    try std.testing.expect(std.mem.startsWith(u8, why.text(), "the resources document nests deeper than 64 levels, at x[0][0]"));

    // create, without a profile: libcrun would take a limit nothing checked,
    // and overflow on it (the driver's checkMemory).
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(allocator, "{\"linux\":{\"resources\":{\"memory\":{\"limit\":67108864,\"limit\\u0000\":-9223372036854775808,\"swap\":1}}}}", &why));
    try std.testing.expectEqualStrings("the bundle's config.json has a NUL in the key at linux.resources.memory.limit\\u0000" ++ ends, why.text());
    // ... and under one: the profile lowers the first limit, libcrun applies
    // the second.
    try expectRefused("{\"linux\":{\"resources\":{\"memory\":{\"limit\":1073741824,\"limit\\u0000\":1073741824},\"pids\":{\"limit\":500,\"limit\\u0000\":500}}}}", .{ .name = "hardened", .memory_limit = 67108864, .pids_limit = 50 }, "has a NUL in the key at linux.resources.memory.limit\\u0000:");
    // A claim of the caps behind a NUL is a claim to libcrun.
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(allocator, "{\"annotations\":{},\"annotations\\u0000\":{\"io.cageforge.nexcage.profile.memory\":\"1099511627776\"}}", &why));
    try std.testing.expectEqualStrings("the bundle's config.json has a NUL in the key at annotations\\u0000" ++ ends, why.text());
    // exec: "capabilities\u0000" is a process with nothing to cut, and
    // libcrun's "capabilities".
    try std.testing.expectError(error.ProfileRefused, boundExec(allocator, "{\"args\":[\"sh\"],\"capabilities\\u0000\":{\"bounding\":[\"CAP_SYS_ADMIN\"]}}", "{\"annotations\":{\"io.cageforge.nexcage.profile\":\"hardened\"}}", &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "the process spec has a NUL in the key at capabilities\\u0000:") != null);

    // Deeper than any stack would hold as recursion, inside a list: refused
    // for its depth, long before the NUL, and the walk goes no deeper.
    const depth = 1 << 17;
    const deep = try allocator.alloc(u8, 2 * depth + 16);
    defer allocator.free(deep);
    @memset(deep[0..depth], '[');
    const middle = "{\"a\\u0000\":1}";
    @memcpy(deep[depth..][0..middle.len], middle);
    @memset(deep[depth + middle.len ..][0..depth], ']');
    var doc = std.ArrayListUnmanaged(u8){};
    defer doc.deinit(allocator);
    try doc.print(allocator, "{{\"x\":{s}}}", .{deep[0 .. 2 * depth + middle.len]});
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(allocator, doc.items, &why));
    try std.testing.expect(std.mem.startsWith(u8, why.text(), "the bundle's config.json nests deeper than 64 levels, at x[0][0]"));
    // Anything else spelt with \u escapes is a key or a string like any other.
    try checkUnclaimed(allocator, "{\"annotations\":{\"caf\\u00e9\":\"\\u00e9t\\u00e9\"}}", &why);
    // A NUL in a value is not: libcrun would read the value up to it.
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(allocator, "{\"annotations\":{\"caf\\u00e9\":\"\\u0000 in a value\"}}", &why));
    try std.testing.expectEqualStrings("the bundle's config.json has a NUL in the string at annotations.caf\u{e9}: libcrun's parser ends a string there, so it would read something other than what nexcage checked", why.text());
}
