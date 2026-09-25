/// Where nexcage keeps its per-container state.
///
/// An OCI runtime takes this from `--root`, and a container engine relies on
/// it: containerd passes its own directory so that several callers keep
/// separate state on one host, and `runc --root` exists for the same reason.
/// Without it every caller shares /run/nexcage and they see each other's
/// containers.
///
/// The value is borrowed from argv, which outlives every use of it.
const default_root = "/run/nexcage";

var current: []const u8 = default_root;

pub fn get() []const u8 {
    return current;
}

pub fn set(path: []const u8) void {
    current = path;
}

/// True while nothing has overridden the default, which is what the
/// documentation describes.
pub fn isDefault() bool {
    const std = @import("std");
    return std.mem.eql(u8, current, default_root);
}
