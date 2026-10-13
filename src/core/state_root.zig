/// Where nexcage keeps its per-container state.
///
/// An OCI runtime takes this from `--root`, and a container engine relies on
/// it: containerd passes its own directory so that several callers keep
/// separate state on one host, and `runc --root` exists for the same reason.
/// Without it every caller shares /run/nexcage and they see each other's
/// containers.
///
/// Two backends keep state under it, and they must never share a directory.
/// The router tells them apart by what is on disk -- libcrun's own files for
/// a crun container (crunHas), nexcage's `state.json` for a Proxmox LXC one --
/// and while both lived in `<root>/<id>`, an LXC container made under --root
/// was taken for libcrun's: every later command went to libcrun, and `delete`
/// removed the directory and reported success with the Proxmox container
/// still there. So under a caller's root the Proxmox LXC backend keeps its
/// records one level down, in a directory whose name starts with a dot:
/// libcrun skips such entries when it lists containers, and no crun container
/// id can be one.
const std = @import("std");

const default_root = "/run/nexcage";
const lxc_subdir = ".proxmox-lxc";

// The root as given, normalised, and the Proxmox LXC records' directory under
// it. Static, so that `set` needs no allocator and the slices outlive every
// use of them.
var root_buf: [std.fs.max_path_bytes]u8 = undefined;
var lxc_buf: [std.fs.max_path_bytes]u8 = undefined;
var root: []const u8 = default_root;
var lxc: []const u8 = default_root;

/// Where the Proxmox LXC backend keeps a container's state.json and
/// runtime-metadata.json, a directory per container name: /run/nexcage by
/// default, `<root>/.proxmox-lxc` under a caller's --root.
pub fn get() []const u8 {
    return lxc;
}

/// Take a caller's --root, which main has checked is absolute. It is
/// normalised first -- `/run/nexcage/`, `/run//nexcage` and
/// `/run/x/../nexcage` all name the default -- because whether it is the
/// default decides where libcrun's state goes, and a trailing slash once sent
/// that into the Proxmox backend's directory.
pub fn set(path: []const u8) error{NameTooLong}!void {
    var scratch: [std.fs.max_path_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    const normal = std.fs.path.resolvePosix(fba.allocator(), &.{path}) catch return error.NameTooLong;
    if (std.mem.eql(u8, normal, default_root)) {
        root = default_root;
        lxc = default_root;
        return;
    }
    // "/" is the one root that already ends in a slash
    const sep: []const u8 = if (std.mem.endsWith(u8, normal, "/")) "" else "/";
    const new_lxc = std.fmt.bufPrint(&lxc_buf, "{s}{s}{s}", .{ normal, sep, lxc_subdir }) catch return error.NameTooLong;
    @memcpy(root_buf[0..normal.len], normal);
    root = root_buf[0..normal.len];
    lxc = new_lxc;
}

/// True while nothing has overridden the default, which is what the
/// documentation describes.
pub fn isDefault() bool {
    return std.mem.eql(u8, root, default_root);
}

/// Where libcrun keeps a container's state: --root when given, else crun's
/// own default rather than nexcage's, because the state there is libcrun's.
pub fn crun() []const u8 {
    return if (isDefault()) "/run/crun" else root;
}

/// Whether libcrun has a container `id` here: the `status` file its create
/// writes last, or the copy of the bundle's config.json that create writes
/// first, with no state.json beside it.
///
/// The copy alone is a create killed half way -- SIGKILL, the OOM killer --
/// which leaves the directory, that copy and the cgroup it made, and no
/// status file. libcrun's delete --force removes all three
/// (CrunDriver.createDidNotFinish), so such an id has to reach it. With the
/// status file as the only evidence, an engine's delete --force of it found
/// no backend and exited 0, and the id stayed: create said it existed and
/// state that it did not.
///
/// A directory alone proves nothing, and nor does one with a state.json in
/// it. Under --root the Proxmox backend kept its records in <root>/<id>, as
/// state.json and runtime-metadata.json, before they moved to
/// <root>/.proxmox-lxc, and runc, whose root an engine's can be, keeps a
/// state.json there too; taking such a directory for libcrun's sent every
/// command after an LXC create to libcrun. Neither writes a config.json
/// there, and a state.json rules the directory out whatever else it holds.
pub fn crunHas(id: []const u8) bool {
    if (has(crun(), id, "status")) return true;
    return has(crun(), id, "config.json") and !has(crun(), id, "state.json");
}

/// Whether the Proxmox LXC backend has a record of a container named `id`:
/// the state.json it writes when it creates one.
pub fn lxcHas(id: []const u8) bool {
    return has(get(), id, "state.json");
}

fn has(dir: []const u8, id: []const u8, file: []const u8) bool {
    // An id is one path component; anything else is no backend's.
    if (id.len == 0 or std.mem.indexOfScalar(u8, id, '/') != null) return false;
    if (std.mem.eql(u8, id, ".") or std.mem.eql(u8, id, "..")) return false;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/{s}/{s}", .{ dir, id, file }) catch return false;
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

test "a root that only looks different is still the default" {
    defer set(default_root) catch unreachable;
    for ([_][]const u8{ "/run/nexcage/", "/run//nexcage", "/run/x/../nexcage", "/run/./nexcage/" }) |given| {
        try set(given);
        try std.testing.expect(isDefault());
        try std.testing.expectEqualStrings("/run/crun", crun());
        try std.testing.expectEqualStrings("/run/nexcage", get());
    }
}

test "a create libcrun did not finish is libcrun's, and a directory with a state.json never is" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir);
    try set(dir);
    defer set(default_root) catch unreachable;

    // What a create killed half way leaves: libcrun's copy of the config, no status
    try tmp.dir.makePath("half");
    try tmp.dir.writeFile(.{ .sub_path = "half/config.json", .data = "{}" });
    try std.testing.expect(crunHas("half"));
    // A finished one
    try tmp.dir.makePath("done");
    try tmp.dir.writeFile(.{ .sub_path = "done/config.json", .data = "{}" });
    try tmp.dir.writeFile(.{ .sub_path = "done/status", .data = "{}" });
    try std.testing.expect(crunHas("done"));
    // A Proxmox record from before they moved to .proxmox-lxc, and runc's state
    try tmp.dir.makePath("lxc-old");
    try tmp.dir.writeFile(.{ .sub_path = "lxc-old/state.json", .data = "{}" });
    try tmp.dir.writeFile(.{ .sub_path = "lxc-old/runtime-metadata.json", .data = "{}" });
    try std.testing.expect(!crunHas("lxc-old"));
    try tmp.dir.makePath("both");
    try tmp.dir.writeFile(.{ .sub_path = "both/config.json", .data = "{}" });
    try tmp.dir.writeFile(.{ .sub_path = "both/state.json", .data = "{}" });
    try std.testing.expect(!crunHas("both"));
    // and a directory with nothing in it
    try tmp.dir.makePath("empty");
    try std.testing.expect(!crunHas("empty"));
    try std.testing.expect(!crunHas("missing"));
}

test "under a caller's root the Proxmox LXC records are not in libcrun's directory" {
    defer set(default_root) catch unreachable;
    try set("/run/containerd/runc/k8s.io/");
    try std.testing.expectEqualStrings("/run/containerd/runc/k8s.io", crun());
    try std.testing.expectEqualStrings("/run/containerd/runc/k8s.io/.proxmox-lxc", get());
    try set("/");
    try std.testing.expectEqualStrings("/", crun());
    try std.testing.expectEqualStrings("/.proxmox-lxc", get());
}
