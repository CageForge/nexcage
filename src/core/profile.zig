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
    try refuseClaim(root, why);

    const linux = try child(arena, root, "linux");

    if (profile.require_user_namespace and !hasUserNamespace(linux))
        return why.set("profile '{s}' requires a user namespace, and the bundle has none with uid and gid mappings; in Kubernetes, set hostUsers: false on the pod", .{profile.name});

    if (profile.require_seccomp and !hasObject(linux, "seccomp"))
        return why.set("profile '{s}' requires a seccomp filter, and the bundle has none; in Kubernetes, set securityContext.seccompProfile.type: RuntimeDefault", .{profile.name});

    if (profile.drop_capabilities.len > 0) dropCapabilities(root, profile.drop_capabilities);

    if (profile.memory_limit != null or profile.pids_limit != null) {
        const resources = try child(arena, linux, "resources");
        if (profile.memory_limit) |limit| try lowerTo(try child(arena, resources, "memory"), "limit", limit);
        if (profile.pids_limit) |limit| try lowerTo(try child(arena, resources, "pids"), "limit", limit);
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

/// The record `state` reports must be one nexcage wrote.
fn refuseClaim(root: *const std.json.ObjectMap, why: *Refusal) error{ProfileRefused}!void {
    const a = root.get("annotations") orelse return;
    if (a == .object and a.object.contains(annotation))
        return why.set("the bundle carries the annotation {s}, which nexcage writes itself", .{annotation});
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
