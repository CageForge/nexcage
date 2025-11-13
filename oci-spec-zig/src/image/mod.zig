const std = @import("std");

pub const version = "1.1.0";

pub const Manifest = struct {
    schema_version: u32 = 2,
    config_media_type: []const u8 = "application/vnd.oci.image.config.v1+json",
};

test "image module loads" {
    const manifest = Manifest{};
    std.debug.assert(manifest.schema_version == 2);
}

