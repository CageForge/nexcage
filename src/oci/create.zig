const std = @import("std");
const json = @import("json");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.oci_create);
const errors = @import("error");
const types = @import("types");
const proxmox = @import("proxmox");
const mem = std.mem;
const log = std.log;
const RlimitType = types.RlimitType;
const Rlimit = types.Rlimit;
const Process = types.Process;
const User = types.User;
const Capabilities = types.Capabilities;
const spec = @import("spec.zig");
const common = @import("common");
const image = @import("image/manager.zig");
const zfs = @import("../zfs/manager.zig");
const lxc = @import("../lxc/container.zig");
const hooks = @import("hooks.zig");
const network = @import("../network/mod.zig");
const NetworkValidator = @import("../network/validator.zig").NetworkValidator;

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
};

pub const CreateOptions = struct {
    container_id: []const u8,
    bundle_path: []const u8,
    image_name: []const u8,
    image_tag: []const u8,
    config: ?types.ImageConfig = null,
    zfs_dataset: []const u8,
    proxmox_node: []const u8,
    proxmox_storage: []const u8,
};

pub const Create = struct {
    allocator: std.mem.Allocator,
    image_manager: *image.ImageManager,
    zfs_manager: *zfs.ZFSManager,
    lxc_manager: *lxc.LXCManager,
    proxmox_client: *proxmox.ProxmoxClient,
    options: CreateOptions,
    hook_executor: *hooks.HookExecutor,
    network_validator: NetworkValidator,
    
    const Self = @This();
    
    pub fn init(
        allocator: std.mem.Allocator,
        image_manager: *image.ImageManager,
        zfs_manager: *zfs.ZFSManager,
        lxc_manager: *lxc.LXCManager,
        proxmox_client: *proxmox.ProxmoxClient,
        options: CreateOptions,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .image_manager = image_manager,
            .zfs_manager = zfs_manager,
            .lxc_manager = lxc_manager,
            .proxmox_client = proxmox_client,
            .options = options,
            .hook_executor = try hooks.HookExecutor.init(allocator),
            .network_validator = NetworkValidator.init(allocator),
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.hook_executor.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn create(self: *Self) !void {
        logger.info("Creating container {s}", .{self.options.container_id});

        // Валідуємо bundle
        try self.validateBundle();

        // Перевіряємо чи контейнер вже існує
        if (try self.lxc_manager.containerExists(self.options.container_id)) {
            logger.err("Container already exists: {s}", .{self.options.container_id});
            return CreateError.ContainerExists;
        }

        // Створюємо ZFS dataset
        try self.createZfsDataset();

        // Налаштовуємо LXC контейнер
        try self.configureLxcContainer();

        // Виконуємо prestart хуки
        if (self.options.spec.hooks) |container_hooks| {
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
        if (self.options.spec.hooks) |container_hooks| {
            if (container_hooks.poststart) |poststart| {
                try self.hook_executor.executeHooks(poststart, .{
                    .container_id = self.options.container_id,
                    .bundle = self.options.bundle_path,
                    .state = "running",
                });
            }
        }

        logger.info("Container {s} created successfully", .{self.options.container_id});
    }
    
    fn validateNetworkConfig(self: *Self) !void {
        const net_config = self.options.spec.linux.?.network orelse return;

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
        logger.info("Validating bundle at {s}", .{self.options.bundle_path});
        
        // Перевіряємо чи існує bundle директорія
        const bundle_dir = std.fs.openDirAbsolute(self.options.bundle_path, .{}) catch {
            logger.err("Bundle directory not found: {s}", .{self.options.bundle_path});
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
            logger.err("Config file not found: {s}", .{config_path});
            return CreateError.InvalidConfig;
        };
        defer config_file.close();

        // Перевіряємо наявність rootfs
        const rootfs_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.options.bundle_path, "rootfs" },
        );
        defer self.allocator.free(rootfs_path);

        const rootfs_dir = std.fs.openDirAbsolute(rootfs_path, .{}) catch {
            logger.err("Rootfs directory not found: {s}", .{rootfs_path});
            return CreateError.InvalidRootfs;
        };
        defer rootfs_dir.close();
    }

    fn createZfsDataset(self: *Self) !void {
        logger.info("Creating ZFS dataset for container {s}", .{self.options.container_id});

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
        logger.info("Configuring LXC container {s}", .{self.options.container_id});

        // Створюємо базову конфігурацію
        var config = try self.lxc_manager.createConfig();
        defer config.deinit();

        // Встановлюємо основні параметри
        try config.setName(self.options.container_id);
        try config.setRootfs(try std.fmt.allocPrint(
            self.allocator,
            "zfs:{s}/{s}",
            .{ self.options.zfs_dataset, self.options.container_id },
        ));

        // Встановлюємо hostname з OCI spec
        if (self.options.spec.hostname) |hostname| {
            try config.setHostname(hostname);
        }

        // Налаштовуємо процес
        if (self.options.spec.process) |process| {
            // Встановлюємо environment змінні
            if (process.env) |env| {
                for (env) |env_var| {
                    try config.addEnvironmentVariable(env_var);
                }
            }

            // Встановлюємо робочу директорію
            if (process.cwd) |cwd| {
                try config.setWorkingDirectory(cwd);
            }

            // Налаштовуємо користувача
            if (process.user) |user| {
                try config.setUID(user.uid);
                try config.setGID(user.gid);
                
                if (user.additionalGids) |additional_gids| {
                    try config.setAdditionalGids(additional_gids);
                }
            }

            // Налаштовуємо capabilities
            if (process.capabilities) |caps| {
                if (caps.bounding) |bounding| {
                    try config.setBoundingCapabilities(bounding);
                }
                if (caps.effective) |effective| {
                    try config.setEffectiveCapabilities(effective);
                }
            }
        }

        // Налаштовуємо мережу
        if (self.options.spec.linux) |linux| {
            if (linux.network) |net| {
                for (net.interfaces) |iface| {
                    try config.addNetworkInterface(.{
                        .name = iface.name,
                        .type = iface.type,
                        .bridge = iface.bridge,
                        .vlan = iface.vlan,
                        .mtu = iface.mtu,
                        .rate = iface.rate,
                        .ip = if (iface.ip) |ip| .{
                            .address = ip.address,
                            .netmask = ip.netmask,
                            .gateway = ip.gateway,
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
            if (linux.resources) |res| {
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
                if (res.blockio) |blockio| {
                    if (blockio.weight) |weight| {
                        try config.setBlockIOWeight(weight);
                    }
                }

                // Налаштовуємо hugepages
                if (res.hugepageLimits) |hugepages| {
                    for (hugepages) |hp| {
                        try config.setHugepageLimit(hp.pageSize, hp.limit);
                    }
                }
            }

            // Налаштовуємо namespaces
            if (linux.namespaces) |namespaces| {
                for (namespaces) |ns| {
                    try config.addNamespace(ns.type, ns.path);
                }
            }

            // Налаштовуємо devices
            if (linux.devices) |devices| {
                for (devices) |dev| {
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
        }

        // Налаштовуємо монтування
        for (self.options.spec.mounts) |mount| {
            try config.addMount(.{
                .source = mount.source,
                .target = mount.destination,
                .type = mount.type,
                .options = mount.options,
            });
        }

        // Зберігаємо конфігурацію
        try self.lxc_manager.saveConfig(self.options.container_id, config);
    }

    fn startContainer(self: *Self) !void {
        logger.info("Starting container {s}", .{self.options.container_id});

        // Створюємо контейнер через Proxmox API
        try self.proxmox_client.createContainer(
            self.options.proxmox_node,
            self.options.container_id,
            .{
                .ostemplate = try std.fmt.allocPrint(
                    self.allocator,
                    "zfs:{s}/{s}",
                    .{ self.options.zfs_dataset, self.options.container_id },
                ),
                .storage = self.options.proxmox_storage,
                .start = true,
            },
        );
    }
};

pub fn create(
    allocator: Allocator,
    opts: CreateOpts,
    proxmox_client: *proxmox.ProxmoxClient,
) !void {
    logger.info("Creating container {s} with bundle {s}", .{ opts.id, opts.bundle_path });

    // Перевіряємо наявність bundle директорії
    try fs.cwd().access(opts.bundle_path, .{});

    // Читаємо та парсимо config.json
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ opts.bundle_path, "config.json" });
    defer allocator.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    const config_content = try config_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_content);

    try proxmox_client.createContainer(opts.id, config_content);

    // Якщо вказано pid_file, записуємо PID
    if (opts.pid_file) |pid_file| {
        const pid_str = try std.fmt.allocPrint(allocator, "{d}\n", .{0}); // TODO: Get real PID
        defer allocator.free(pid_str);
        
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
    var user: ?types.User = null;
    if (obj.getOrNull("user")) |user_obj| {
        user = try parseUser(allocator, user_obj);
    }

    // Parse capabilities
    var capabilities: ?types.Capabilities = null;
    if (obj.getOrNull("capabilities")) |caps_obj| {
        capabilities = try parseCapabilities(caps_obj, allocator);
    }

    // Parse rlimits
    var rlimits: ?[]types.Rlimit = null;
    if (obj.getOrNull("rlimits")) |rlimits_array| {
        if (rlimits_array.type != .array) return error.InvalidSpec;
        const items = rlimits_array.array();
        var rlimits_list = try allocator.alloc(types.Rlimit, items.len());
        for (items.items(), 0..) |item, i| {
            const type_str = if (item.object().getOrNull("type")) |type_value| type_value.string() else return error.InvalidSpec;
            const rlimit_type = std.meta.stringToEnum(types.RlimitType, type_str) orelse return error.InvalidSpec;
            rlimits_list[i] = .{
                .type = rlimit_type,
                .soft = @intCast(item.object().get("soft").integer()),
                .hard = @intCast(item.object().get("hard").integer())
            };
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

fn parseUser(allocator: Allocator, value: *json.JsonValue) !types.User {
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

    return types.User{
        .uid = uid,
        .gid = gid,
        .additionalGids = additional_gids,
    };
}

fn parseCapabilities(value: *json.JsonValue, allocator: Allocator) !?types.Capabilities {
    if (value.type != .object) return error.InvalidSpec;
    const obj = value.object();

    var result = types.Capabilities{};

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
