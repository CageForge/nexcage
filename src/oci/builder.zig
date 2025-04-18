const std = @import("std");
const spec = @import("spec.zig");
const resources = @import("resources.zig");

pub const SpecError = error{
    InvalidVersion,
    InvalidProcess,
    InvalidRoot,
    InvalidMount,
    InvalidNamespace,
    InvalidCapability,
    InvalidResource,
    OutOfMemory,
};

/// Білдер для створення OCI специфікації
pub const SpecBuilder = struct {
    allocator: std.mem.Allocator,
    spec: spec.Spec,

    const Self = @This();

    /// Створює новий білдер
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .spec = spec.Spec{
                .oci_version = try allocator.dupe(u8, "1.0.0"),
                .process = undefined,
                .root = undefined,
                .mounts = &[_]spec.Mount{},
                .hostname = null,
                .linux = null,
                .annotations = std.StringHashMap([]const u8).init(allocator),
            },
        };
    }

    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        self.spec.deinit(self.allocator);
    }

    /// Встановлює процес
    pub fn setProcess(self: *Self, process: spec.Process) !void {
        self.spec.process = process;
    }

    /// Встановлює root
    pub fn setRoot(self: *Self, root: spec.Root) !void {
        self.spec.root = root;
    }

    /// Додає точку монтування
    pub fn addMount(self: *Self, mount: spec.Mount) !void {
        const new_mounts = try self.allocator.alloc(spec.Mount, self.spec.mounts.len + 1);
        std.mem.copy(spec.Mount, new_mounts, self.spec.mounts);
        new_mounts[self.spec.mounts.len] = mount;
        self.spec.mounts = new_mounts;
    }

    /// Встановлює хостнейм
    pub fn setHostname(self: *Self, hostname: []const u8) !void {
        self.spec.hostname = try self.allocator.dupe(u8, hostname);
    }

    /// Встановлює Linux-специфічні налаштування
    pub fn setLinux(self: *Self, linux: spec.Linux) !void {
        self.spec.linux = linux;
    }

    /// Додає анотацію
    pub fn addAnnotation(self: *Self, key: []const u8, value: []const u8) !void {
        const key_owned = try self.allocator.dupe(u8, key);
        const value_owned = try self.allocator.dupe(u8, value);
        try self.spec.annotations.put(key_owned, value_owned);
    }

    /// Будує специфікацію
    pub fn build(self: *Self) !spec.Spec {
        // Валідуємо специфікацію перед поверненням
        try self.validate();
        return self.spec;
    }

    /// Валідує специфікацію
    fn validate(self: *Self) !void {
        // Перевіряємо версію
        if (!std.mem.eql(u8, self.spec.oci_version, "1.0.0")) {
            return SpecError.InvalidVersion;
        }

        // Перевіряємо процес
        if (self.spec.process.args.len == 0) {
            return SpecError.InvalidProcess;
        }

        // Перевіряємо root
        if (self.spec.root.path.len == 0) {
            return SpecError.InvalidRoot;
        }

        // Перевіряємо точки монтування
        for (self.spec.mounts) |mount| {
            if (mount.destination.len == 0 or mount.type.len == 0) {
                return SpecError.InvalidMount;
            }
        }

        // Перевіряємо Linux-специфічні налаштування
        if (self.spec.linux) |linux| {
            // Перевіряємо простори імен
            for (linux.namespaces) |namespace| {
                if (namespace.type.len == 0) {
                    return SpecError.InvalidNamespace;
                }
            }

            // Перевіряємо ресурси
            if (linux.resources) |res| {
                if (res.memory) |memory| {
                    if (memory.limit) |limit| {
                        if (limit < 0) {
                            return SpecError.InvalidResource;
                        }
                    }
                }
            }
        }
    }
}; 