const std = @import("std");
const log = @import("logger").log;
const Allocator = std.mem.Allocator;
const Container = @import("container").Container;
const ContainerConfig = @import("container").ContainerConfig;
const ContainerState = @import("../types.zig").ContainerState;
const Error = @import("error").Error;
const image = @import("../image/mod.zig");
const zfs = @import("../zfs/mod.zig");
const PauseConfig = @import("config").PauseConfig;
const routing = @import("routing");

pub const PauseContainer = struct {
    allocator: Allocator,
    config: ContainerConfig,
    state: ContainerState,
    image_manager: *image.ImageManager,
    zfs_manager: *zfs.ZFSManager,

    pub fn init(allocator: Allocator, config: ContainerConfig) !*PauseContainer {
        const self = try allocator.create(PauseContainer);
        errdefer allocator.destroy(self);

        // Ініціалізуємо менеджери
        var image_manager = try allocator.create(image.ImageManager);
        image_manager.* = try image.ImageManager.init(allocator);
        errdefer image_manager.deinit();

        var zfs_manager = try allocator.create(zfs.ZFSManager);
        zfs_manager.* = try zfs.ZFSManager.init(allocator);
        errdefer zfs_manager.deinit();

        self.* = .{
            .allocator = allocator,
            .config = config,
            .state = .{
                .status = .created,
                .pid = 0,
                .bundle = config.bundle,
                .annotations = config.annotations,
            },
            .image_manager = image_manager,
            .zfs_manager = zfs_manager,
        };
        return self;
    }

    pub fn deinit(self: *PauseContainer) void {
        self.image_manager.deinit();
        self.allocator.destroy(self.image_manager);
        self.zfs_manager.deinit();
        self.allocator.destroy(self.zfs_manager);
        self.allocator.destroy(self);
    }

    pub fn prepareRootfs(self: *PauseContainer) !void {
        log.info("Preparing rootfs for pause container {s}", .{self.config.id});

        // Створюємо ZFS dataset для rootfs
        const dataset_name = try std.fmt.allocPrint(self.allocator, "rpool/containers/{s}", .{self.config.id});
        defer self.allocator.free(dataset_name);

        try self.zfs_manager.createDataset(dataset_name, .{
            .mountpoint = self.config.bundle,
            .compression = "lz4",
        });

        // Завантажуємо pause образ
        const pause_image = try self.image_manager.pullImage("k8s.gcr.io/pause:3.2");
        defer pause_image.deinit();

        // Конвертуємо OCI образ в rootfs
        try self.image_manager.convertToRootfs(pause_image, self.config.bundle);

        log.info("Rootfs prepared successfully", .{});
    }

    pub fn start(self: *PauseContainer) !void {
        log.info("Starting pause container {s}", .{self.config.id});

        // Підготовлюємо rootfs
        try self.prepareRootfs();

        // Створюємо LXC конфігурацію
        const config_path = try std.fmt.allocPrint(self.allocator, "{s}/config.json", .{self.config.bundle});
        defer self.allocator.free(config_path);

        const config = .{
            .ociVersion = "1.0.2",
            .process = .{
                .terminal = false,
                .user = .{ .uid = 0, .gid = 0 },
                .args = &.{"/pause"},
                .env = &.{"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
                .cwd = "/",
            },
            .root = .{
                .path = self.config.bundle,
                .readonly = false,
            },
            .hostname = self.config.id,
            .mounts = &.{},
            .linux = .{
                .namespaces = &.{
                    .{ .type = "network", .path = null },
                    .{ .type = "pid", .path = null },
                },
            },
        };

        // Зберігаємо конфігурацію
        const config_file = try std.fs.cwd().createFile(config_path, .{});
        defer config_file.close();

        try std.json.stringify(config, .{}, config_file.writer());

        self.state.status = .running;
    }

    pub fn stop(self: *PauseContainer) !void {
        log.info("Stopping pause container {s}", .{self.config.id});

        // Видаляємо ZFS dataset
        const dataset_name = try std.fmt.allocPrint(self.allocator, "rpool/containers/{s}", .{self.config.id});
        defer self.allocator.free(dataset_name);

        try self.zfs_manager.destroyDataset(dataset_name);

        self.state.status = .stopped;
    }

    pub fn getState(self: *PauseContainer) ContainerState {
        return self.state;
    }
};

pub fn createPauseContainer(allocator: Allocator, routing_config: *const routing.RoutingConfig) !*Container {
    // Створюємо конфігурацію для pause контейнера
    var pause_config = try PauseConfig.init(allocator);
    defer pause_config.deinit();

    // Конвертуємо PauseConfig в ContainerConfig
    var container_config = ContainerConfig{
        .allocator = allocator,
        .id = try allocator.dupe(u8, pause_config.id),
        .name = try allocator.dupe(u8, pause_config.name),
        .image = try allocator.dupe(u8, pause_config.image),
        .command = pause_config.command,
        .env = pause_config.env,
        .working_dir = try allocator.dupe(u8, pause_config.working_dir),
        .user = try allocator.dupe(u8, pause_config.user),
        .type = .crun, // Тип буде перевизначено роутером
        .hostname = try allocator.dupe(u8, pause_config.hostname),
        .mounts = pause_config.mounts,
        .resources = pause_config.resources,
        .namespaces = pause_config.namespaces,
    };

    // Створюємо контейнер
    var container = try Container.init(allocator, container_config);
    errdefer container.deinit();

    // Запускаємо контейнер
    try container.start(routing_config);

    return container;
}

pub fn stopPauseContainer(container: *Container, routing_config: *const routing.RoutingConfig) !void {
    try container.stop(routing_config);
    container.deinit();
} 