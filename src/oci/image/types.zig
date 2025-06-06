const std = @import("std");
const zig_json = @import("zig_json");

pub const ImageManifest = struct {
    schemaVersion: i64,
    config: Descriptor,
    layers: []Descriptor,
    annotations: ?std.StringHashMap([]const u8),
};

pub const ImageConfig = struct {
    created: ?[]const u8,
    author: ?[]const u8,
    architecture: []const u8,
    os: []const u8,
    os_version: ?[]const u8,
    config: Config,
    rootfs: Rootfs,
    history: ?[]History,
};

pub const Config = struct {
    user: ?[]const u8,
    exposed_ports: ?std.StringHashMap(zig_json.JsonValue),
    env: ?[][]const u8,
    entrypoint: ?[][]const u8,
    cmd: ?[][]const u8,
    volumes: ?std.StringHashMap(zig_json.JsonValue),
    working_dir: ?[]const u8,
    labels: ?std.StringHashMap([]const u8),
    stop_signal: ?[]const u8,
};

pub const Rootfs = struct {
    type: []const u8,
    diff_ids: [][]const u8,
};

pub const History = struct {
    created: ?[]const u8,
    author: ?[]const u8,
    created_by: ?[]const u8,
    comment: ?[]const u8,
    empty_layer: ?bool,
};

pub const Descriptor = struct {
    mediaType: []const u8,
    size: i64,
    digest: []const u8,
    urls: ?[][]const u8,
    annotations: ?std.StringHashMap([]const u8),
    platform: ?Platform,
};

pub const Platform = struct {
    architecture: []const u8,
    os: []const u8,
    os_version: ?[]const u8,
    os_features: ?[][]const u8,
    variant: ?[]const u8,
    features: ?[][]const u8,
};

pub const ImageIndex = struct {
    schemaVersion: i64,
    manifests: []ManifestDescriptor,
};

pub const ManifestDescriptor = struct {
    mediaType: []const u8,
    size: i64,
    digest: []const u8,
    platform: ?Platform,
};
