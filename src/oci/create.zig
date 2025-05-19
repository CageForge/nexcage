const std = @import("std");
const json = @import("json");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const errors = @import("error");
const root_types = @import("types");
const oci_types = @import("types.zig");
const image_types = @import("image/types.zig");
const proxmox = @import("proxmox");
const mem = std.mem;
const log = std.log;
const RlimitType = oci_types.RlimitType;
const Rlimit = oci_types.Rlimit;
const Process = oci_types.Process;
const User = oci_types.User;
const Capabilities = oci_types.Capabilities;
const spec = @import("spec.zig");
const common = @import("common");
const image = @import("image");
const zfs = @import("zfs");
const lxc = @import("lxc");
const hooks = @import("hooks.zig");
const network = @import("network");
const NetworkValidator = network.NetworkValidator;
const registry = @import("registry");
const raw = @import("raw");
const logger_mod = @import("logger");
const crun = @import("crun");
const crun_spec = @import("../crun/spec.zig");

pub const CreateOpts = struct {
    config_path: []const u8,
    id: []const u8,
    bundle_path: []const u8,
    allocator: Allocator,
    pid_file: ?[]const u8 = null,
    console_socket: ?[]const u8 = null,
    detach: bool = false,
    no_pivot: bool = false,
    no_new_keyring: bool = false,
    preserve_fds: u32 = 0,

    pub fn deinit(self: *CreateOpts, allocator: Allocator) void {
        allocator.free(self.config_path);
        allocator.free(self.id);
        allocator.free(self.bundle_path);
        if (self.pid_file) |pid_file| {
            allocator.free(pid_file);
        }
    }
};

pub const CreateError = error{
    InvalidJson,
    InvalidSpec,
    FileError,
    OutOfMemory,
    ImageNotFound,
    BundleNotFound,
    ContainerExists,
    ZFSError,
    LXCError,
    ProxmoxError,
    ConfigError,
    InvalidConfig,
    InvalidRootfs,
    RuntimeNotAvailable,
};

pub const StorageType = enum {
    raw,
    zfs,
};

pub const StorageConfig = struct {
    type: StorageType,
    storage_path: ?[]const u8 = null,
    storage_pool: ?[]const u8 = null,
};

pub const CreateOptions = struct {
    container_id: []const u8,
    bundle_path: []const u8,
    image_name: []const u8,
    image_tag: []const u8,
    config: ?image_types.ImageConfig = null,
    zfs_dataset: []const u8,
    proxmox_node: []const u8,
    proxmox_storage: []const u8,
};

pub const Create = struct {
    allocator: std.mem.Allocator,
    image_manager: *image.ImageManager,
    zfs_manager: *zfs.ZFSManager,
    lxc_manager: ?*lxc.LXCManager,
    crun_manager: ?*crun.CrunManager,
    proxmox_client: *proxmox.ProxmoxClient,
    registry: ?*registry.Registry,
    options: CreateOptions,
    hook_executor: *hooks.HookExecutor,
    network_validator: NetworkValidator,
    oci_config: spec.OciImageConfig,
    logger: *logger_mod.Logger,
    runtime_type: oci_types.RuntimeType,
    
    const Self = @This();
    
    pub fn init(
        allocator: std.mem.Allocator,
        image_manager: *image.ImageManager,
        zfs_manager: *zfs.ZFSManager,
        lxc_manager: ?*lxc.LXCManager,
        crun_manager: ?*crun.CrunManager,
        proxmox_client: *proxmox.ProxmoxClient,
        options: CreateOptions,
        logger: *logger_mod.Logger,
        runtime_type: oci_types.RuntimeType,
    ) !*Self {
        const self = try allocator.create(Self);

        // Читаємо конфігурацію OCI образу
        const oci_config_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}/config.json",
            .{ options.bundle_path, options.container_id },
        );
        defer allocator.free(oci_config_path);

        const oci_config_file = try fs.cwd().openFile(oci_config_path, .{});
        defer oci_config_file.close();

        const oci_config_content = try oci_config_file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(oci_config_content);

        const oci_config = try parseOciImageConfig(allocator, oci_config_content);

        var registry_instance: ?*registry.Registry = null;
        if (oci_config.registry_url) |url| {
            registry_instance = try registry.Registry.init(
                allocator,
                url,
                oci_config.registry_username,
                oci_config.registry_password,
                logger,
            );
        }

        self.* = .{
            .allocator = allocator,
            .image_manager = image_manager,
            .zfs_manager = zfs_manager,
            .lxc_manager = lxc_manager,
            .crun_manager = crun_manager,
            .proxmox_client = proxmox_client,
            .registry = registry_instance,
            .options = options,
            .hook_executor = try hooks.HookExecutor.init(allocator),
            .network_validator = NetworkValidator.init(allocator),
            .oci_config = oci_config,
            .logger = logger,
            .runtime_type = runtime_type,
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.registry) |r| {
            r.deinit();
        }
        self.hook_executor.deinit();
        self.oci_config.deinit(self.allocator);
        self.allocator.destroy(self);
    }
    
    pub fn create(self: *Self) !void {
        try self.logger.info("Creating container {s} with runtime {s}", .{ 
            self.options.container_id,
            @tagName(self.runtime_type),
        });

        // Завантажуємо образ з реєстру якщо потрібно
        if (self.registry) |r| {
            try r.downloadImage(
                self.options.image_name,
                self.options.image_tag,
                self.image_manager.images_dir,
            );
        }

        // Валідуємо bundle
        try self.validateBundle();

        // Створюємо контейнер в залежності від типу runtime
        switch (self.runtime_type) {
            .lxc => {
                if (self.lxc_manager) |lxc_mgr| {
                    // Перевіряємо чи контейнер вже існує
                    if (try lxc_mgr.containerExists(self.options.container_id)) {
                        try self.logger.err("Container already exists: {s}", .{self.options.container_id});
                        return CreateError.ContainerExists;
                    }

                    if (self.oci_config.raw_image) {
                        // Створюємо .raw файл
                        const raw_path = try std.fmt.allocPrint(
                            self.allocator,
                            "{s}/{s}.raw",
                            .{ self.options.bundle_path, self.options.container_id },
                        );
                        defer self.allocator.free(raw_path);

                        var raw_image = try raw.RawImage.init(
                            self.allocator,
                            raw_path,
                            self.oci_config.raw_image_size,
                            self.logger,
                        );
                        defer raw_image.deinit();

                        try raw_image.create();

                        // Створюємо ZFS dataset
                        try self.createZfsDataset();

                        // Налаштовуємо LXC контейнер з .raw файлом
                        try self.configureLxcContainerWithRaw(raw_path);
                    } else {
                        // Створюємо ZFS dataset
                        try self.createZfsDataset();

                        // Налаштовуємо LXC контейнер
                        try self.configureLxcContainer();
                    }
                } else {
                    return CreateError.RuntimeNotAvailable;
                }
            },
            .crun => {
                if (self.crun_manager) |crun_mgr| {
                    try crun_mgr.createContainer(
                        self.options.container_id,
                        self.options.bundle_path,
                        try self.toSpec(),
                    );
                } else {
                    return CreateError.RuntimeNotAvailable;
                }
            },
            .vm => {
                // TODO: Implement VM creation
                return error.NotImplemented;
            },
        }

        // Виконуємо prestart хуки
        if (self.oci_config.hooks) |container_hooks| {
            if (container_hooks.prestart) |prestart| {
                try self.hook_executor.executeHooks(prestart, .{
                    .container_id = self.options.container_id,
                    .bundle = self.options.bundle_path,
                    .state = "creating",
                });
            }
        }

        // Запускаємо контейнер
        try self.startContainer();

        // Виконуємо poststart хуки
        if (self.oci_config.hooks) |container_hooks| {
            if (container_hooks.poststart) |poststart| {
                try self.hook_executor.executeHooks(poststart, .{
                    .container_id = self.options.container_id,
                    .bundle = self.options.bundle_path,
                    .state = "running",
                });
            }
        }

        try self.logger.info("Container {s} created successfully", .{self.options.container_id});
    }
    
    fn validateNetworkConfig(self: *Self) !void {
        const net_config = self.oci_config.linux.?.network orelse return;

        // Валідуємо інтерфейси
        for (net_config.interfaces) |iface| {
            try self.network_validator.validateInterface(iface.name);
            
            if (iface.bridge) |bridge| {
                try self.network_validator.validateBridge(bridge);
            }

            if (iface.vlan) |vlan| {
                try self.network_validator.validateVLAN(vlan);
            }

            if (iface.mtu) |mtu| {
                try self.network_validator.validateMTU(mtu);
            }

            if (iface.rate) |rate| {
                try self.network_validator.validateRate(rate);
            }

            // Валідуємо IP налаштування
            if (iface.ip) |ip| {
                try self.network_validator.validateIPRange(ip.address, ip.netmask);
                
                if (ip.gateway) |gateway| {
                    try self.network_validator.validateGateway(gateway);
                }
            }
        }

        // Валідуємо DNS налаштування
        if (net_config.dns) |dns| {
            if (dns.servers) |servers| {
                try self.network_validator.validateDNS(servers);
            }
        }
    }
    
    fn validateBundle(self: *Self) !void {
        try self.logger.info("Validating bundle at {s}", .{self.options.bundle_path});
        
        // Перевіряємо чи існує bundle директорія
        var bundle_dir = std.fs.openDirAbsolute(self.options.bundle_path, .{}) catch {
            try self.logger.err("Bundle directory not found: {s}", .{self.options.bundle_path});
            return CreateError.BundleNotFound;
        };
        defer bundle_dir.close();

        // Перевіряємо наявність config.json
        const config_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.options.bundle_path, "config.json" },
        );
        defer self.allocator.free(config_path);

        const config_file = std.fs.openFileAbsolute(config_path, .{}) catch {
            try self.logger.err("Config file not found: {s}", .{config_path});
            return CreateError.InvalidConfig;
        };
        defer config_file.close();

        // Перевіряємо наявність rootfs
        const rootfs_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.options.bundle_path, "rootfs" },
        );
        defer self.allocator.free(rootfs_path);

        var rootfs_dir = std.fs.openDirAbsolute(rootfs_path, .{}) catch {
            try self.logger.err("Rootfs directory not found: {s}", .{rootfs_path});
            return CreateError.InvalidRootfs;
        };
        defer rootfs_dir.close();
    }

    fn createZfsDataset(self: *Self) !void {
        try self.logger.info("Creating ZFS dataset for container {s}", .{self.options.container_id});

        const dataset_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.options.zfs_dataset, self.options.container_id },
        );
        defer self.allocator.free(dataset_path);

        // Створюємо ZFS dataset
        try self.zfs_manager.createDataset(dataset_path);

        // Копіюємо rootfs в dataset
        const rootfs_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.options.bundle_path, "rootfs" },
        );
        defer self.allocator.free(rootfs_path);

        try self.zfs_manager.copyToDataset(rootfs_path, dataset_path);
    }

    fn configureLxcContainer(self: *Self) !void {
        try self.logger.info("Configuring LXC container {s}", .{self.options.container_id});

        // Створюємо базову конфігурацію
        var config = try self.lxc_manager.?.createConfig();
        defer config.deinit();

        // Встановлюємо основні параметри
        try config.setName(self.options.container_id);
        try config.setRootfs(try std.fmt.allocPrint(
            self.allocator,
            "zfs:{s}/{s}",
            .{ self.options.zfs_dataset, self.options.container_id },
        ));

        // Встановлюємо hostname з OCI spec
        if (self.oci_config.hostname) |hostname| {
            try config.setHostname(hostname);
        }

        // Налаштовуємо процес
        // Встановлюємо environment змінні
        if (self.oci_config.env) |env| {
            for (env) |env_var| {
                try config.addEnvironmentVariable(env_var);
            }
        }

        // Встановлюємо робочу директорію
        if (self.oci_config.cwd) |cwd| {
            try config.setWorkingDirectory(cwd);
        }

        // Налаштовуємо користувача
        if (self.oci_config.user) |user| {
            config.setUID(user.uid);
            config.setGID(user.gid);
            
            if (user.additionalGids) |additional_gids| {
                try config.setAdditionalGids(additional_gids);
            }
        }

        // Налаштовуємо capabilities
        if (self.oci_config.capabilities) |caps| {
            if (caps.bounding) |bounding| {
                try config.setBoundingCapabilities(bounding);
            }
            if (caps.effective) |effective| {
                try config.setEffectiveCapabilities(effective);
            }
        }

        // Налаштовуємо мережу
        if (self.oci_config.network) |net| {
            for (net.interfaces) |iface| {
                try config.addNetworkInterface(.{
                    .name = iface.name,
                    .type = "veth", // За замовчуванням використовуємо veth
                    .bridge = null,
                    .vlan = null,
                    .mtu = iface.mtu,
                    .rate = null,
                    .ip = if (iface.address) |addrs| blk: {
                        if (addrs.len > 0) {
                            break :blk .{
                                .address = addrs[0],
                                .netmask = "255.255.255.0", // За замовчуванням
                                .gateway = iface.gateway,
                            };
                        }
                        break :blk null;
                    } else null,
                });
            }

            // Налаштовуємо DNS
            if (net.dns) |dns| {
                if (dns.servers) |servers| {
                    try config.setDNSServers(servers);
                }
                if (dns.search) |search| {
                    try config.setDNSSearchDomains(search);
                }
            }
        }

        // Налаштовуємо ресурси
        if (self.oci_config.resources) |res| {
            if (res.memory) |memory| {
                if (memory.limit) |limit| {
                    try config.setMemoryLimit(limit);
                }
                if (memory.reservation) |reservation| {
                    try config.setMemoryReservation(reservation);
                }
                if (memory.swap) |swap| {
                    try config.setMemorySwap(swap);
                }
            }

            if (res.cpu) |cpu| {
                if (cpu.shares) |shares| {
                    try config.setCpuShares(shares);
                }
                if (cpu.quota) |quota| {
                    try config.setCpuQuota(quota);
                }
                if (cpu.period) |period| {
                    try config.setCpuPeriod(period);
                }
                if (cpu.cpus) |cpus| {
                    try config.setCpus(cpus);
                }
                if (cpu.mems) |mems| {
                    try config.setMems(mems);
                }
            }

            // Налаштовуємо блочні пристрої
            if (res.blockIO) |blockio| {
                if (blockio.weight) |weight| {
                    try config.setBlockIOWeight(weight);
                }
            }

            // Налаштовуємо hugepages
            if (res.hugepageLimits) |hugepages| {
                for (hugepages) |hp| {
                    const page_size = try std.fmt.parseInt(u64, hp.pageSize, 10);
                    try config.setHugepageLimit(page_size, hp.limit);
                }
            }
        }

        // Налаштовуємо namespaces
        if (self.oci_config.linux) |linux| {
            for (linux.namespaces) |ns| {
                try config.addNamespace(ns.type, ns.path);
            }
        }

        // Налаштовуємо devices
        if (self.oci_config.linux) |linux| {
            for (linux.devices) |dev| {
                try config.addDevice(.{
                    .path = dev.path,
                    .type = dev.type,
                    .major = dev.major,
                    .minor = dev.minor,
                    .fileMode = dev.fileMode,
                    .uid = dev.uid,
                    .gid = dev.gid,
                });
            }
        }

        // Налаштовуємо монтування
        if (self.oci_config.linux) |linux| {
            for (linux.mounts) |mount| {
            try config.addMount(.{
                .source = mount.source,
                .target = mount.destination,
                .type = mount.type,
                    .options = if (mount.options) |opts| blk: {
                        var new_opts = try self.allocator.alloc([]const u8, opts.len);
                        for (opts, 0..) |opt, i| {
                            new_opts[i] = try self.allocator.dupe(u8, opt);
                        }
                        break :blk new_opts;
                    } else null,
            });
            }
        }

        // Зберігаємо конфігурацію
        try self.lxc_manager.?.saveConfig(self.options.container_id, config);
    }

    fn configureLxcContainerWithRaw(self: *Self, raw_path: []const u8) !void {
        try self.logger.info("Configuring LXC container {s} with raw image", .{self.options.container_id});

        // Створюємо базову конфігурацію
        var config = try self.lxc_manager.?.createConfig();
        defer config.deinit();

        // Встановлюємо основні параметри
        try config.setName(self.options.container_id);

        // Встановлюємо rootfs в залежності від типу зберігання
        switch (self.oci_config.storage.type) {
            .raw => {
                if (self.oci_config.storage.storage_path) |storage_path| {
                    const full_path = try std.fmt.allocPrint(
                        self.allocator,
                        "{s}/{s}",
                        .{ storage_path, self.options.container_id },
                    );
                    defer self.allocator.free(full_path);

                    // Створюємо директорію для зберігання якщо не існує
                    try fs.cwd().makePath(full_path);

                    // Копіюємо raw файл в storage path
                    var output = std.process.Child.init(&[_][]const u8{ "cp", raw_path, full_path }, self.allocator);
                    try output.spawn();
                    const term = try output.wait();

                    if (term.Exited != 0) {
                        return CreateError.FileError;
                    }

                    try config.setRootfs(try std.fmt.allocPrint(
                        self.allocator,
                        "{s}/{s}",
                        .{ full_path, self.options.container_id },
                    ));
                } else {
                    return CreateError.InvalidConfig;
                }
            },
            .zfs => {
                if (self.oci_config.storage.storage_pool) |pool| {
                    try config.setRootfs(try std.fmt.allocPrint(
                        self.allocator,
                        "zfs:{s}/{s}",
                        .{ pool, self.options.container_id },
                    ));
                } else {
                    return CreateError.InvalidConfig;
                }
            },
        }

        // Встановлюємо hostname з OCI spec
        if (self.oci_config.hostname) |hostname| {
            try config.setHostname(hostname);
        }

        // Налаштовуємо процес
        // Встановлюємо environment змінні
        if (self.oci_config.env) |env| {
            for (env) |env_var| {
                try config.addEnvironmentVariable(env_var);
            }
        }

        // Встановлюємо робочу директорію
        if (self.oci_config.cwd) |cwd| {
            try config.setWorkingDirectory(cwd);
        }

        // Налаштовуємо користувача
        if (self.oci_config.user) |user| {
            config.setUID(user.uid);
            config.setGID(user.gid);
            
            if (user.additionalGids) |additional_gids| {
                try config.setAdditionalGids(additional_gids);
            }
        }

        // Налаштовуємо capabilities
        if (self.oci_config.capabilities) |caps| {
            if (caps.bounding) |bounding| {
                try config.setBoundingCapabilities(bounding);
            }
            if (caps.effective) |effective| {
                try config.setEffectiveCapabilities(effective);
            }
        }

        // Налаштовуємо мережу
        if (self.oci_config.network) |net| {
            for (net.interfaces) |iface| {
                try config.addNetworkInterface(.{
                    .name = iface.name,
                    .type = "veth", // За замовчуванням використовуємо veth
                    .bridge = null,
                    .vlan = null,
                    .mtu = iface.mtu,
                    .rate = null,
                    .ip = if (iface.address) |addrs| blk: {
                        if (addrs.len > 0) {
                            break :blk .{
                                .address = addrs[0],
                                .netmask = "255.255.255.0", // За замовчуванням
                                .gateway = iface.gateway,
                            };
                        }
                        break :blk null;
                    } else null,
                });
            }

            // Налаштовуємо DNS
            if (net.dns) |dns| {
                if (dns.servers) |servers| {
                    try config.setDNSServers(servers);
                }
                if (dns.search) |search| {
                    try config.setDNSSearchDomains(search);
                }
            }
        }

        // Налаштовуємо ресурси
        if (self.oci_config.resources) |res| {
            if (res.memory) |memory| {
                if (memory.limit) |limit| {
                    try config.setMemoryLimit(limit);
                }
                if (memory.reservation) |reservation| {
                    try config.setMemoryReservation(reservation);
                }
                if (memory.swap) |swap| {
                    try config.setMemorySwap(swap);
                }
            }

            if (res.cpu) |cpu| {
                if (cpu.shares) |shares| {
                    try config.setCpuShares(shares);
                }
                if (cpu.quota) |quota| {
                    try config.setCpuQuota(quota);
                }
                if (cpu.period) |period| {
                    try config.setCpuPeriod(period);
                }
                if (cpu.cpus) |cpus| {
                    try config.setCpus(cpus);
                }
                if (cpu.mems) |mems| {
                    try config.setMems(mems);
                }
            }

            // Налаштовуємо блочні пристрої
            if (res.blockIO) |blockio| {
                if (blockio.weight) |weight| {
                    try config.setBlockIOWeight(weight);
                }
            }

            // Налаштовуємо hugepages
            if (res.hugepageLimits) |hugepages| {
                for (hugepages) |hp| {
                    const page_size = try std.fmt.parseInt(u64, hp.pageSize, 10);
                    try config.setHugepageLimit(page_size, hp.limit);
                }
            }
        }

        // Налаштовуємо namespaces
        if (self.oci_config.linux) |linux| {
            for (linux.namespaces) |ns| {
                try config.addNamespace(ns.type, ns.path);
            }
        }

        // Налаштовуємо devices
        if (self.oci_config.linux) |linux| {
            for (linux.devices) |dev| {
                try config.addDevice(.{
                    .path = dev.path,
                    .type = dev.type,
                    .major = dev.major,
                    .minor = dev.minor,
                    .fileMode = dev.fileMode,
                    .uid = dev.uid,
                    .gid = dev.gid,
                });
            }
        }

        // Налаштовуємо монтування
        if (self.oci_config.linux) |linux| {
            for (linux.mounts) |mount| {
            try config.addMount(.{
                .source = mount.source,
                .target = mount.destination,
                .type = mount.type,
                    .options = if (mount.options) |opts| blk: {
                        var new_opts = try self.allocator.alloc([]const u8, opts.len);
                        for (opts, 0..) |opt, i| {
                            new_opts[i] = try self.allocator.dupe(u8, opt);
                        }
                        break :blk new_opts;
                    } else null,
            });
            }
        }

        // Зберігаємо конфігурацію
        try self.lxc_manager.?.saveConfig(self.options.container_id, config);
    }

    fn startContainer(self: *Self) !void {
        try self.logger.info("Starting container {s}", .{self.options.container_id});

        switch (self.runtime_type) {
            .lxc => {
                if (self.lxc_manager) |lxc_mgr| {
                    try lxc_mgr.startContainer(self.options.container_id);
                } else {
                    return CreateError.RuntimeNotAvailable;
                }
            },
            .crun => {
                if (self.crun_manager) |crun_mgr| {
                    try crun_mgr.startContainer(self.options.container_id);
                } else {
                    return CreateError.RuntimeNotAvailable;
                }
            },
            .vm => {
                // TODO: Implement VM start
                return error.NotImplemented;
            },
        }
    }

    fn toSpec(self: *Self) !crun_spec.Spec {
        return crun_spec.Spec{
            .process = crun_spec.Process{
                .terminal = false,
            },
            .linux = if (self.oci_config.linux) |linux| crun_spec.Linux{
                .resources = if (linux.resources) |resources| crun_spec.Resources{
                    .memory = if (resources.memory) |memory| crun_spec.Memory{
                        .limit = memory.limit,
                    } else null,
                } else null,
            } else null,
        };
    }
};

pub fn create(opts: CreateOpts, proxmox_client: *proxmox.ProxmoxClient) !void {
    const logger = logger_mod.Logger.init(opts.allocator, .info, null);
    defer logger.deinit();

    try logger.info("Creating container {s} with bundle {s}", .{ opts.id, opts.bundle_path });

    // Перевіряємо, чи існує директорія bundle
    try fs.cwd().access(opts.bundle_path, .{});

    // Відкриваємо файл конфігурації
    const config_file = try fs.cwd().openFile(opts.config_path, .{});
    defer config_file.close();

    // Читаємо конфігурацію
    const config_content = try config_file.readToEndAlloc(opts.allocator, 1024 * 1024);
    defer opts.allocator.free(config_content);

    // Парсимо конфігурацію
    var parsed = try std.json.parseFromSlice(std.json.Value, opts.allocator, config_content, .{});
    defer parsed.deinit();

    // Перевіряємо версію OCI
    const version = parsed.value.object.get("ociVersion") orelse return error.InvalidSpec;
    if (!std.mem.eql(u8, version.string, "1.0.2")) {
        return error.UnsupportedVersion;
    }

    // Перевіряємо наявність необхідних полів
    if (parsed.value.object.get("root") == null) return error.InvalidSpec;
    if (parsed.value.object.get("process") == null) return error.InvalidSpec;

    // Створюємо контейнер в Proxmox
    try proxmox_client.createContainer(opts.id, config_content);

    // Якщо вказано pid_file, записуємо PID
    if (opts.pid_file) |pid_file| {
        const pid_str = try std.fmt.allocPrint(opts.allocator, "{d}\n", .{0}); // TODO: Get real PID
        defer opts.allocator.free(pid_str);
        
        try fs.cwd().writeFile(.{
            .data = pid_str,
            .sub_path = pid_file,
        });
    }

    logger.info("Container {s} created successfully", .{opts.id});
}

fn getStorageFromConfig(allocator: Allocator, config: spec.Spec) ![]const u8 {
    // Спочатку перевіряємо анотації
    if (config.annotations) |annotations| {
        if (annotations.get("proxmox.storage")) |storage| {
            return try allocator.dupe(u8, storage);
        }
    }

    // Перевіряємо тип монтування root
    for (config.mounts) |mount| {
        if (std.mem.eql(u8, mount.destination, "/")) {
            if (std.mem.startsWith(u8, mount.source, "zfs:")) {
                return try allocator.dupe(u8, "zfs");
            } else if (std.mem.startsWith(u8, mount.source, "dir:")) {
                return try allocator.dupe(u8, "local");
            }
        }
    }

    // За замовчуванням використовуємо local
    return try allocator.dupe(u8, "local");
}

fn parseLinuxSpec(allocator: Allocator, value: *json.JsonValue) !spec.LinuxSpec {
    if (value.type != .object) return error.InvalidSpec;
    const obj = value.object();

    var result = spec.LinuxSpec{
        .namespaces = &[_]spec.LinuxNamespace{},
        .devices = &[_]spec.LinuxDevice{},
        .resources = null,
        .cgroupsPath = null,
        .seccomp = null,
        .selinux = null,
    };

    if (obj.getOrNull("namespaces")) |namespaces| {
        if (namespaces.type != .array) return error.InvalidSpec;
        const items = namespaces.array();
        var ns_list = try allocator.alloc(spec.LinuxNamespace, items.len());
        for (items.items(), 0..) |ns, i| {
            const ns_obj = ns.object();
            ns_list[i] = spec.LinuxNamespace{
                .type = try allocator.dupe(u8, ns_obj.get("type").string()),
                .path = if (ns_obj.getOrNull("path")) |p| try allocator.dupe(u8, p.string()) else null,
            };
        }
        result.namespaces = ns_list;
    }

    if (obj.getOrNull("devices")) |devices| {
        if (devices.type != .array) return error.InvalidSpec;
        const items = devices.array();
        var dev_list = try allocator.alloc(spec.LinuxDevice, items.len());
        for (items.items(), 0..) |dev, i| {
            const dev_obj = dev.object();
            dev_list[i] = spec.LinuxDevice{
                .path = try allocator.dupe(u8, dev_obj.get("path").string()),
                .type = try allocator.dupe(u8, dev_obj.get("type").string()),
                .major = dev_obj.get("major").integer(),
                .minor = dev_obj.get("minor").integer(),
                .fileMode = if (dev_obj.getOrNull("fileMode")) |m| @intCast(m.integer()) else null,
                .uid = if (dev_obj.getOrNull("uid")) |u| @intCast(u.integer()) else null,
                .gid = if (dev_obj.getOrNull("gid")) |g| @intCast(g.integer()) else null,
            };
        }
        result.devices = dev_list;
    }

    return result;
}

fn parseStorageConfig(allocator: Allocator, value: *json.JsonValue) !StorageConfig {
    if (value.type != .object) return error.InvalidSpec;
    const obj = value.object();

    const type_str = if (obj.getOrNull("type")) |t| t.string() else return error.InvalidSpec;
    const storage_type = std.meta.stringToEnum(StorageType, type_str) orelse return error.InvalidSpec;

    var config = StorageConfig{
        .type = storage_type,
    };

    switch (storage_type) {
        .raw => {
            if (obj.getOrNull("storage_path")) |path| {
                config.storage_path = try allocator.dupe(u8, path.string());
            } else {
                return error.InvalidSpec;
            }
        },
        .zfs => {
            if (obj.getOrNull("storage_pool")) |pool| {
                config.storage_pool = try allocator.dupe(u8, pool.string());
            } else {
                return error.InvalidSpec;
            }
        },
    }

    return config;
}

pub fn parseContainerSpec(allocator: Allocator, value: *json.JsonValue) !spec.Spec {
    if (value.type != .object) return error.InvalidSpec;
    const obj = value.object();

    const container_spec = spec.Spec{
        .version = if (obj.getOrNull("ociVersion")) |v| try allocator.dupe(u8, v.string()) else return error.InvalidSpec,
        .process = try parseProcess(allocator, obj.get("process")),
        .root = try parseRoot(allocator, obj.get("root")),
        .hostname = try allocator.dupe(u8, obj.get("hostname").string()),
        .mounts = if (obj.getOrNull("mounts")) |m| try parseMounts(allocator, m) else &[_]spec.Mount{},
        .hooks = if (obj.getOrNull("hooks")) |h| try parseHooks(allocator, h) else null,
        .annotations = if (obj.getOrNull("annotations")) |a| blk: {
            var map = std.StringHashMap([]const u8).init(allocator);
            var it = a.object().map.iterator();
            while (it.next()) |entry| {
                try map.put(try allocator.dupe(u8, entry.key_ptr.*), try allocator.dupe(u8, entry.value_ptr.*.string()));
            }
            break :blk map;
        } else std.StringHashMap([]const u8).init(allocator),
        .linux = try parseLinuxSpec(allocator, obj.get("linux")),
        .storage = if (obj.getOrNull("storage")) |s| try parseStorageConfig(allocator, s) else return error.InvalidSpec,
    };

    errdefer container_spec.deinit(allocator);
    return container_spec;
}

pub fn parseProcess(allocator: Allocator, value: *json.JsonValue) !spec.Process {
    if (value.type != .object) return error.InvalidSpec;
    const obj = value.object();

    // Parse terminal
    const terminal = if (obj.getOrNull("terminal")) |t| t.boolean() else false;

    // Parse env
    var env: []const []const u8 = &[_][]const u8{};
    if (obj.getOrNull("env")) |env_array| {
        if (env_array.type != .array) return error.InvalidSpec;
        const items = env_array.array();
        var env_list = try allocator.alloc([]const u8, items.len());
        for (items.items(), 0..) |item, i| {
            env_list[i] = try allocator.dupe(u8, item.string());
        }
        env = env_list;
    }

    // Parse args
    var args: []const []const u8 = &[_][]const u8{};
    if (obj.getOrNull("args")) |args_array| {
        if (args_array.type != .array) return error.InvalidSpec;
        const items = args_array.array();
        var args_list = try allocator.alloc([]const u8, items.len());
        for (items.items(), 0..) |item, i| {
            args_list[i] = try allocator.dupe(u8, item.string());
        }
        args = args_list;
    }

    // Parse user
    var user: ?oci_types.User = null;
    if (obj.getOrNull("user")) |user_obj| {
        user = try parseUser(allocator, user_obj);
    }

    // Parse capabilities
    var capabilities: ?oci_types.Capabilities = null;
    if (obj.getOrNull("capabilities")) |caps_obj| {
        capabilities = try parseCapabilities(caps_obj, allocator);
    }

    // Parse rlimits
    var rlimits: ?[]oci_types.Rlimit = null;
    if (obj.getOrNull("rlimits")) |rlimits_array| {
        if (rlimits_array.type != .array) return error.InvalidSpec;
        const items = rlimits_array.array();
        var rlimits_list = try allocator.alloc(oci_types.Rlimit, items.len());
        for (items.items(), 0..) |item, i| {
            const type_str = if (item.object().getOrNull("type")) |type_value| type_value.string() else return error.InvalidSpec;
            const rlimit_type = std.meta.stringToEnum(oci_types.RlimitType, type_str) orelse return error.InvalidSpec;
            rlimits_list[i] = .{ .type = rlimit_type, .soft = @intCast(item.object().get("soft").integer()), .hard = @intCast(item.object().get("hard").integer()) };
        }
        rlimits = rlimits_list;
    }

    // Parse cwd
    const cwd = if (obj.getOrNull("cwd")) |c| try allocator.dupe(u8, c.string()) else return error.InvalidSpec;

    return spec.Process{
        .args = args,
        .env = env,
        .cwd = cwd,
        .user = user orelse return error.InvalidSpec,
        .capabilities = capabilities,
        .rlimits = rlimits,
        .terminal = terminal,
        .no_new_privileges = if (obj.getOrNull("noNewPrivileges")) |n| n.boolean() else false,
    };
}

fn parseUser(allocator: Allocator, value: *json.JsonValue) !oci_types.User {
    if (value.type != .object) return error.InvalidSpec;
    const user_obj = value.object();

    const uid = if (user_obj.getOrNull("uid")) |u| @as(u32, @intCast(u.integer())) else return error.InvalidSpec;
    const gid = if (user_obj.getOrNull("gid")) |g| @as(u32, @intCast(g.integer())) else return error.InvalidSpec;

    var additional_gids: ?[]const u32 = null;
    if (user_obj.getOrNull("additionalGids")) |gids_array| {
        if (gids_array.type != .array) return error.InvalidSpec;
        const items = gids_array.array();
        var gids_list = try allocator.alloc(u32, items.len());
        for (items.items(), 0..) |gid_value, i| {
            gids_list[i] = @as(u32, @intCast(gid_value.integer()));
        }
        additional_gids = gids_list;
    }

    return oci_types.User{
        .uid = uid,
        .gid = gid,
        .additionalGids = additional_gids,
    };
}

fn parseCapabilities(value: *json.JsonValue, allocator: Allocator) !?oci_types.Capabilities {
    if (value.type != .object) return error.InvalidSpec;
    const obj = value.object();

    var result = oci_types.Capabilities{};

    if (obj.getOrNull("bounding")) |arr| {
        if (arr.type != .array) return error.InvalidSpec;
        const items = arr.array();
        var bounding = try allocator.alloc([]const u8, items.len());
        for (items.items(), 0..) |item, i| {
            bounding[i] = try allocator.dupe(u8, item.string());
        }
        result.bounding = bounding;
    }

    if (obj.getOrNull("effective")) |arr| {
        if (arr.type != .array) return error.InvalidSpec;
        const items = arr.array();
        var effective = try allocator.alloc([]const u8, items.len());
        for (items.items(), 0..) |item, i| {
            effective[i] = try allocator.dupe(u8, item.string());
        }
        result.effective = effective;
    }

    if (obj.getOrNull("inheritable")) |arr| {
        if (arr.type != .array) return error.InvalidSpec;
        const items = arr.array();
        var inheritable = try allocator.alloc([]const u8, items.len());
        for (items.items(), 0..) |item, i| {
            inheritable[i] = try allocator.dupe(u8, item.string());
        }
        result.inheritable = inheritable;
    }

    if (obj.getOrNull("permitted")) |arr| {
        if (arr.type != .array) return error.InvalidSpec;
        const items = arr.array();
        var permitted = try allocator.alloc([]const u8, items.len());
        for (items.items(), 0..) |item, i| {
            permitted[i] = try allocator.dupe(u8, item.string());
        }
        result.permitted = permitted;
    }

    if (obj.getOrNull("ambient")) |arr| {
        if (arr.type != .array) return error.InvalidSpec;
        const items = arr.array();
        var ambient = try allocator.alloc([]const u8, items.len());
        for (items.items(), 0..) |item, i| {
            ambient[i] = try allocator.dupe(u8, item.string());
        }
        result.ambient = ambient;
    }

    return result;
}

fn parseRoot(allocator: Allocator, value: *json.JsonValue) !spec.Root {
    const obj = value.object();
    return spec.Root{
        .path = try allocator.dupe(u8, obj.get("path").string()),
        .readonly = if (obj.getOrNull("readonly")) |r| r.boolean() else false,
    };
}

fn parseMounts(allocator: Allocator, value: *json.JsonValue) ![]spec.Mount {
    const array = value.array();
    var result = try allocator.alloc(spec.Mount, array.len());
    errdefer allocator.free(result);

    for (array.items(), 0..) |mount_value, i| {
        const obj = mount_value.object();
        result[i] = spec.Mount{
            .destination = try allocator.dupe(u8, obj.get("destination").string()),
            .type = try allocator.dupe(u8, obj.get("type").string()),
            .source = try allocator.dupe(u8, obj.get("source").string()),
            .options = if (obj.getOrNull("options")) |opts| blk: {
                const opts_array = opts.array();
                var options = try allocator.alloc([]const u8, opts_array.len());
                for (opts_array.items(), 0..) |opt, j| {
                    options[j] = try allocator.dupe(u8, opt.string());
                }
                break :blk options;
            } else null,
        };
    }

    return result;
}

fn parseHooks(allocator: Allocator, value: *json.JsonValue) !spec.Hooks {
    const obj = value.object();
    return spec.Hooks{
        .prestart = if (obj.getOrNull("prestart")) |h| try parseHookArray(allocator, h) else null,
        .poststart = if (obj.getOrNull("poststart")) |h| try parseHookArray(allocator, h) else null,
        .poststop = if (obj.getOrNull("poststop")) |h| try parseHookArray(allocator, h) else null,
    };
}

fn parseHookArray(allocator: Allocator, value: *json.JsonValue) ![]spec.Hook {
    const array = value.array();
    var result = try allocator.alloc(spec.Hook, array.len());
    errdefer allocator.free(result);

    for (array.items(), 0..) |hook_value, i| {
        const obj = hook_value.object();
        result[i] = spec.Hook{
            .path = try allocator.dupe(u8, obj.get("path").string()),
            .args = if (obj.getOrNull("args")) |args| blk: {
                const args_array = args.array();
                var hook_args = try allocator.alloc([]const u8, args_array.len());
                for (args_array.items(), 0..) |arg, j| {
                    hook_args[j] = try allocator.dupe(u8, arg.string());
                }
                break :blk hook_args;
            } else null,
            .env = if (obj.getOrNull("env")) |env| blk: {
                const env_array = env.array();
                var hook_env = try allocator.alloc([]const u8, env_array.len());
                for (env_array.items(), 0..) |e, j| {
                    hook_env[j] = try allocator.dupe(u8, e.string());
                }
                break :blk hook_env;
            } else null,
            .timeout = if (obj.getOrNull("timeout")) |t| t.integer() else null,
        };
    }

    return result;
}

fn parseVersion(value: *json.JsonValue, allocator: Allocator) ![]const u8 {
    return try allocator.dupe(u8, value.object().get("ociVersion").string());
}

fn parseHostname(value: *json.JsonValue, allocator: Allocator) ![]const u8 {
    if (value.object().getOrNull("hostname")) |hostname| {
        return try allocator.dupe(u8, hostname.string());
    }
    return "";
}

fn parseOciImageConfig(allocator: Allocator, content: []const u8) !spec.OciImageConfig {
    var parsed = try json.parse(content, allocator);
    defer parsed.deinit(allocator);

    if (parsed.value == null) return error.InvalidJson;
    const obj = parsed.value.?.object;
    var config = spec.OciImageConfig{
        .storage = undefined,
        .raw_image = if (obj.getOrNull("raw_image")) |r| r.boolean() else false,
        .raw_image_size = if (obj.getOrNull("raw_image_size")) |s| @intCast(s.integer()) else 10 * 1024 * 1024 * 1024,
        .registry_url = if (obj.getOrNull("registry_url")) |url| try allocator.dupe(u8, url.string()) else null,
        .registry_username = if (obj.getOrNull("registry_username")) |username| try allocator.dupe(u8, username.string()) else null,
        .registry_password = if (obj.getOrNull("registry_password")) |password| try allocator.dupe(u8, password.string()) else null,
        .hostname = if (obj.getOrNull("hostname")) |hostname| try allocator.dupe(u8, hostname.string()) else null,
        .env = null,
        .cwd = null,
        .user = null,
        .capabilities = null,
        .network = null,
    };

    if (obj.getOrNull("storage")) |storage| {
        config.storage = try parseStorageConfig(allocator, storage);
    } else {
        return error.InvalidJson;
    }

    // Парсимо environment змінні
    if (obj.getOrNull("env")) |env_array| {
        if (env_array.type != .array) return error.InvalidJson;
        const items = env_array.array();
        var env_list = try allocator.alloc([]const u8, items.items().len);
        for (items.items(), 0..) |env_value, i| {
            env_list[i] = try allocator.dupe(u8, env_value.string());
        }
        config.env = env_list;
    }

    // Парсимо робочу директорію
    if (obj.getOrNull("cwd")) |cwd| {
        config.cwd = try allocator.dupe(u8, cwd.string());
    }

    // Парсимо користувача
    if (obj.getOrNull("user")) |user_obj| {
        config.user = try parseUser(allocator, user_obj);
    }

    // Парсимо capabilities
    if (obj.getOrNull("capabilities")) |caps_obj| {
        config.capabilities = try parseCapabilities(caps_obj, allocator);
    }

    // Парсимо мережу
    if (obj.getOrNull("network")) |network_obj| {
        config.network = try parseNetwork(allocator, network_obj);
    }

    return config;
}

fn parseNetwork(allocator: Allocator, value: *json.JsonValue) !spec.Network {
    if (value.type != .object) return error.InvalidJson;
    const network_obj = value.object();

    var interfaces = std.ArrayList(spec.NetworkInterface).init(allocator);
    defer interfaces.deinit();

    if (network_obj.getOrNull("interfaces")) |interfaces_array| {
        if (interfaces_array.type != .array) return error.InvalidJson;
        const items = interfaces_array.array();
        for (items.items()) |iface_value| {
            const iface = try parseNetworkInterface(allocator, iface_value);
            try interfaces.append(iface);
        }
    }

    var dns: ?spec.DNS = null;
    if (network_obj.getOrNull("dns")) |dns_obj| {
        dns = try parseDNS(allocator, dns_obj);
    }

    return spec.Network{
        .interfaces = try interfaces.toOwnedSlice(),
        .dns = dns,
    };
}

fn parseNetworkInterface(allocator: Allocator, value: *json.JsonValue) !spec.NetworkInterface {
    if (value.type != .object) return error.InvalidJson;
    const iface_obj = value.object();

    const name = if (iface_obj.getOrNull("name")) |n| try allocator.dupe(u8, n.string()) else return error.InvalidJson;

    var mac: ?[]const u8 = null;
    if (iface_obj.getOrNull("mac")) |m| {
        mac = try allocator.dupe(u8, m.string());
    }

    var address: ?[][]const u8 = null;
    if (iface_obj.getOrNull("address")) |addr_array| {
        if (addr_array.type != .array) return error.InvalidJson;
        const items = addr_array.array();
        var addr_list = try allocator.alloc([]const u8, items.items().len);
        for (items.items(), 0..) |addr_value, i| {
            addr_list[i] = try allocator.dupe(u8, addr_value.string());
        }
        address = addr_list;
    }

    var gateway: ?[]const u8 = null;
    if (iface_obj.getOrNull("gateway")) |g| {
        gateway = try allocator.dupe(u8, g.string());
    }

    var mtu: ?u32 = null;
    if (iface_obj.getOrNull("mtu")) |m| {
        mtu = @as(u32, @intCast(m.integer()));
    }

    return spec.NetworkInterface{
        .name = name,
        .mac = mac,
        .address = address,
        .gateway = gateway,
        .mtu = mtu,
    };
}

fn parseIP(allocator: Allocator, value: *json.JsonValue) !spec.IP {
    if (value.type != .object) return error.InvalidJson;
    const ip_obj = value.object();

    const address = if (ip_obj.getOrNull("address")) |a| try allocator.dupe(u8, a.string()) else return error.InvalidJson;
    const netmask = if (ip_obj.getOrNull("netmask")) |n| try allocator.dupe(u8, n.string()) else return error.InvalidJson;

    var gateway: ?[]const u8 = null;
    if (ip_obj.getOrNull("gateway")) |g| {
        gateway = try allocator.dupe(u8, g.string());
    }

    return spec.IP{
        .address = address,
        .netmask = netmask,
        .gateway = gateway,
    };
}

fn parseDNS(allocator: Allocator, value: *json.JsonValue) !spec.DNS {
    if (value.type != .object) return error.InvalidJson;
    const dns_obj = value.object();

    var servers: ?[][]const u8 = null;
    if (dns_obj.getOrNull("servers")) |servers_array| {
        if (servers_array.type != .array) return error.InvalidJson;
        const items = servers_array.array();
        var servers_list = try allocator.alloc([]const u8, items.items().len);
        for (items.items(), 0..) |server_value, i| {
            servers_list[i] = try allocator.dupe(u8, server_value.string());
        }
        servers = servers_list;
    }

    var search: ?[][]const u8 = null;
    if (dns_obj.getOrNull("search")) |search_array| {
        if (search_array.type != .array) return error.InvalidJson;
        const items = search_array.array();
        var search_list = try allocator.alloc([]const u8, items.items().len);
        for (items.items(), 0..) |search_value, i| {
            search_list[i] = try allocator.dupe(u8, search_value.string());
        }
        search = search_list;
    }

    return spec.DNS{
        .servers = servers,
        .search = search,
    };
}
