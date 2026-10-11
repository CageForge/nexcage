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

    const linux = try child(arena, root, "linux");

    if (profile.require_user_namespace and !hasUserNamespace(linux))
        return why.set("profile '{s}' requires a user namespace, and the bundle has none with uid and gid mappings; in Kubernetes, set hostUsers: false on the pod", .{profile.name});

    if (profile.require_seccomp and !hasObject(linux, "seccomp"))
        return why.set("profile '{s}' requires a seccomp filter, and the bundle has none; in Kubernetes, set securityContext.seccompProfile.type: RuntimeDefault", .{profile.name});

    if (profile.drop_capabilities.len > 0) dropCapabilities(root, profile.drop_capabilities);

    if (profile.memory_limit != null or profile.pids_limit != null) {
        const resources = try child(arena, linux, "resources");
        if (profile.memory_limit) |limit| try lowerMemory(try child(arena, resources, "memory"), limit);
        if (profile.pids_limit) |limit| try lowerTo(try child(arena, resources, "pids"), "limit", limit);
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

    var process = try parse(allocator, process_json, "the process spec", why);
    defer process.deinit();
    const caps = process.value.object.getPtr("capabilities") orelse return null;
    if (caps.* != .object) return null;

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
/// whatever checks it before libcrun does. Duplicate keys are refused too:
/// libcrun's parser would read one of them and this one the other. So is a
/// key with a NUL in it (refuseNulKeys), which is a duplicate to libcrun.
pub fn parse(allocator: std.mem.Allocator, json: []const u8, what: []const u8, why: *Refusal) !std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return why.set("{s} is not valid JSON ({s})", .{ what, @errorName(err) }),
    };
    errdefer parsed.deinit();
    if (parsed.value != .object) return why.set("{s} is not a JSON object", .{what});
    try refuseNulKeys(allocator, parsed.value, what, why);
    return parsed;
}

/// Refuses a document with a NUL in any key, at any depth. libcrun's parser
/// copies a key as a C string, so it ends at the NUL, and of two keys that
/// are then the same it keeps the last: {"limit":33554432,"limit\u0000":-1}
/// is a limit of -1 to libcrun and of 33554432 to every check here, and so
/// is a "memory\u0000" object, or "memory.max\u0000" in unified. No runtime
/// spec has a NUL in a key. A list, not recursion: std.json builds a
/// document of any depth, and this walk must not run out of stack on one.
fn refuseNulKeys(allocator: std.mem.Allocator, root: std.json.Value, what: []const u8, why: *Refusal) !void {
    var todo = std.ArrayListUnmanaged(std.json.Value){};
    defer todo.deinit(allocator);
    try todo.append(allocator, root);
    while (todo.pop()) |value| switch (value) {
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                // Spelt as JSON, with every control and non-ASCII character
                // escaped: the NUL itself is not for the log.
                if (std.mem.indexOfScalar(u8, key, 0)) |nul|
                    return why.set("{s} has a NUL in the key {f}, which libcrun's parser reads as {f}", .{ what, std.json.fmt(key, .{ .escape_unicode = true }), std.json.fmt(key[0..nul], .{ .escape_unicode = true }) });
                try todo.append(allocator, entry.value_ptr.*);
            }
        },
        .array => |list| try todo.appendSlice(allocator, list.items),
        else => {},
    };
}

/// The record `state` reports must be one nexcage wrote: the profile's name
/// and every annotation under it, the recorded caps among them.
fn refuseClaim(root: *const std.json.ObjectMap, why: *Refusal) error{ProfileRefused}!void {
    const a = root.get("annotations") orelse return;
    if (a != .object) return;
    for (a.object.keys()) |key| {
        if (std.mem.eql(u8, key, annotation) or std.mem.startsWith(u8, key, annotation ++ "."))
            return why.set("the bundle carries the annotation {s}, which nexcage writes itself", .{key});
    }
}

/// The object under `key`, made when it is not there. The pointer is good
/// until the next key is added to `obj`.
fn child(arena: std.mem.Allocator, obj: *std.json.ObjectMap, key: []const u8) !*std.json.ObjectMap {
    const gop = try obj.getOrPut(key);
    if (!gop.found_existing or gop.value_ptr.* != .object) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(arena) };
    return &gop.value_ptr.object;
}

fn hasObject(obj: *std.json.ObjectMap, key: []const u8) bool {
    const v = obj.get(key) orelse return false;
    return v == .object;
}

fn hasUserNamespace(linux: *std.json.ObjectMap) bool {
    const namespaces = linux.get("namespaces") orelse return false;
    if (namespaces != .array) return false;
    var has_user = false;
    for (namespaces.array.items) |ns| {
        if (ns != .object) continue;
        const t = ns.object.get("type") orelse continue;
        if (t == .string and std.mem.eql(u8, t.string, "user")) has_user = true;
    }
    if (!has_user) return false;
    for ([_][]const u8{ "uidMappings", "gidMappings" }) |key| {
        const m = linux.get(key) orelse return false;
        if (m != .array or m.array.items.len == 0) return false;
    }
    return true;
}

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

test "a key with a NUL in it is refused in every document read, at any depth" {
    const allocator = std.testing.allocator;
    var why: Refusal = .{};
    const stored = "{\"annotations\":{\"io.cageforge.nexcage.profile\":\"hardened\",\"io.cageforge.nexcage.profile.memory\":\"67108864\",\"io.cageforge.nexcage.profile.pids\":\"50\"}}";
    try std.testing.expectError(error.ProfileRefused, boundUpdate(allocator, stored, "{\"memory\":{\"limit\":33554432,\"limit\\u0000\":1073741824}}", &.{}, &why));
    try std.testing.expectEqualStrings("the resources document has a NUL in the key \"limit\\u0000\", which libcrun's parser reads as \"limit\"", why.text());

    // create, without a profile: libcrun would take a limit nothing checked,
    // and overflow on it (the driver's checkMemory).
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(allocator, "{\"linux\":{\"resources\":{\"memory\":{\"limit\":67108864,\"limit\\u0000\":-9223372036854775808,\"swap\":1}}}}", &why));
    try std.testing.expectEqualStrings("the bundle's config.json has a NUL in the key \"limit\\u0000\", which libcrun's parser reads as \"limit\"", why.text());
    // ... and under one: the profile lowers the first limit, libcrun applies
    // the second.
    try expectRefused("{\"linux\":{\"resources\":{\"memory\":{\"limit\":1073741824,\"limit\\u0000\":1073741824},\"pids\":{\"limit\":500,\"limit\\u0000\":500}}}}", .{ .name = "hardened", .memory_limit = 67108864, .pids_limit = 50 }, "has a NUL in the key \"limit\\u0000\"");
    // A claim of the caps behind a NUL is a claim to libcrun.
    try std.testing.expectError(error.ProfileRefused, checkUnclaimed(allocator, "{\"annotations\":{},\"annotations\\u0000\":{\"io.cageforge.nexcage.profile.memory\":\"1099511627776\"}}", &why));
    try std.testing.expectEqualStrings("the bundle's config.json has a NUL in the key \"annotations\\u0000\", which libcrun's parser reads as \"annotations\"", why.text());
    // exec: "capabilities\u0000" is a process with nothing to cut, and
    // libcrun's "capabilities".
    try std.testing.expectError(error.ProfileRefused, boundExec(allocator, "{\"args\":[\"sh\"],\"capabilities\\u0000\":{\"bounding\":[\"CAP_SYS_ADMIN\"]}}", "{\"annotations\":{\"io.cageforge.nexcage.profile\":\"hardened\"}}", &why));
    try std.testing.expect(std.mem.indexOf(u8, why.text(), "the process spec has a NUL in the key \"capabilities\\u0000\"") != null);

    // Deeper than any stack would hold as recursion, inside a list.
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
    try std.testing.expectEqualStrings("the bundle's config.json has a NUL in the key \"a\\u0000\", which libcrun's parser reads as \"a\"", why.text());
    // Anything else spelt with \u escapes is a key like any other.
    try checkUnclaimed(allocator, "{\"annotations\":{\"caf\\u00e9\":\"\\u0000 in a value\"}}", &why);
}
