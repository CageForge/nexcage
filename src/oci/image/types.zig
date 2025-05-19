const std = @import("std");
const json = std.json;

pub const ImageManifest = struct {
    schemaVersion: i32 = 2,
    mediaType: []const u8 = "application/vnd.oci.image.manifest.v1+json",
    config: Descriptor,
    layers: []Descriptor,
    subject: ?Descriptor = null,
    annotations: ?std.StringHashMap([]const u8) = null,
};

pub const Descriptor = struct {
    mediaType: []const u8,
    digest: []const u8,
    size: i64,
    urls: ?[][]const u8 = null,
    annotations: ?std.StringHashMap([]const u8) = null,
    data: ?[]const u8 = null,
    platform: ?Platform = null,
};

pub const Platform = struct {
    architecture: []const u8,
    os: []const u8,
    os_version: ?[]const u8 = null,
    os_features: ?[][]const u8 = null,
    variant: ?[]const u8 = null,
};

pub const ImageConfig = struct {
    created: ?[]const u8 = null,
    author: ?[]const u8 = null,
    architecture: []const u8,
    os: []const u8,
    config: ?Config = null,
    rootfs: RootFS,
    history: ?[]History = null,
};

pub const Config = struct {
    User: ?[]const u8 = null,
    ExposedPorts: ?std.StringHashMap(std.json.Value) = null,
    Env: ?[][]const u8 = null,
    Entrypoint: ?[][]const u8 = null,
    Cmd: ?[][]const u8 = null,
    Volumes: ?std.StringHashMap(std.json.Value) = null,
    WorkingDir: ?[]const u8 = null,
    Labels: ?std.StringHashMap([]const u8) = null,
    StopSignal: ?[]const u8 = null,
};

pub const RootFS = struct {
    type: []const u8 = "layers",
    diff_ids: [][]const u8,
};

pub const History = struct {
    created: ?[]const u8 = null,
    author: ?[]const u8 = null,
    created_by: ?[]const u8 = null,
    comment: ?[]const u8 = null,
    empty_layer: ?bool = null,
};
