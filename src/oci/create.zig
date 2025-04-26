const std = @import("std");
const Allocator = std.mem.Allocator;
const json = @import("json");
const fs = std.fs;
const spec = @import("spec.zig");
const logger = std.log.scoped(.oci_create);
const errors = @import("error");
const types = @import("types");
const proxmox = @import("proxmox");
const mem = std.mem;
const log = std.log;
const RlimitType = spec.RlimitType;
const Rlimit = spec.RLimit;
const Process = spec.Process;
const User = spec.User;
const Capabilities = spec.Capabilities;

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

    pub fn deinit(self: *CreateOpts) void {
        self.allocator.free(self.config_path);
        self.allocator.free(self.id);
        self.allocator.free(self.bundle_path);
    }
};

pub const CreateError = error{
    InvalidJson,
    InvalidSpec,
    FileError,
    OutOfMemory,
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

    const value = try json.parse(config_content, allocator);
    defer value.deinit(allocator);

    const container_spec = try parseContainerSpec(allocator, value);
    errdefer container_spec.deinit(allocator);

    const config = container_spec;

    const default_memory: u32 = 512 * 1024 * 1024;
    const memory_limit: u32 = if (config.linux.resources) |res| 
        if (res.memory) |memory_res| 
            if (memory_res.limit) |limit| 
                @intCast(@min(limit, std.math.maxInt(u32)))
            else default_memory
        else default_memory
    else default_memory;

    const storage = try getStorageFromConfig(allocator, config);
    defer allocator.free(storage);

    const rootfs = try std.fmt.allocPrint(allocator, "{s}:8", .{storage});
    defer allocator.free(rootfs);

    // Створюємо LXC контейнер через Proxmox API
    var container_config = types.LXCConfig{
        .hostname = try allocator.dupe(u8, config.hostname),
        .ostype = try allocator.dupe(u8, "ubuntu"),
        .memory = memory_limit,
        .swap = 0,
        .cores = if (config.linux.resources) |res|
            if (res.cpu) |cpu| @intCast(cpu.quota orelse 1) else 1
        else 1,
        .rootfs = rootfs,
        .net0 = .{
            .name = try allocator.dupe(u8, "vmbr50"),
            .bridge = try allocator.dupe(u8, "vmbr50"),
            .ip = try allocator.dupe(u8, "dhcp"),
            .type = try allocator.dupe(u8, "veth"),
        },
        .onboot = false,
        .protection = false,
        .start = true,
        .template = false,
        .unprivileged = true,
        .features = .{},
    };
    defer container_config.deinit(allocator);

    const container = try proxmox_client.createLXC(container_config);

    // Якщо вказано pid_file, записуємо PID
    if (opts.pid_file) |pid_file| {
        const pid_str = try std.fmt.allocPrint(allocator, "{d}\n", .{container.vmid});
        defer allocator.free(pid_str);
        
        try fs.cwd().writeFile(.{
            .sub_path = pid_file,
            .data = pid_str,
            .flags = .{},
        });
        //try fs.cwd().chmod(pid_file, 0o644);
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

    // Parse namespaces
    var namespaces: []spec.LinuxNamespace = &[_]spec.LinuxNamespace{};
    if (obj.getOrNull("namespaces")) |ns_array| {
        if (ns_array.type != .array) return error.InvalidSpec;
        const items = ns_array.array();
        var ns_list = try allocator.alloc(spec.LinuxNamespace, items.len());
        for (items.items(), 0..) |item, i| {
            ns_list[i] = .{
                .type = try allocator.dupe(u8, item.object().get("type").string()),
                .path = if (item.object().getOrNull("path")) |p| try allocator.dupe(u8, p.string()) else null,
            };
        }
        namespaces = ns_list;
    }

    // Parse devices
    var devices: []spec.LinuxDevice = &[_]spec.LinuxDevice{};
    if (obj.getOrNull("devices")) |dev_array| {
        if (dev_array.type != .array) return error.InvalidSpec;
        const items = dev_array.array();
        var dev_list = try allocator.alloc(spec.LinuxDevice, items.len());
        for (items.items(), 0..) |item, i| {
            const dev_obj = item.object();
            dev_list[i] = .{
                .path = try allocator.dupe(u8, dev_obj.get("path").string()),
                .type = try allocator.dupe(u8, dev_obj.get("type").string()),
                .major = dev_obj.get("major").integer(),
                .minor = dev_obj.get("minor").integer(),
                .fileMode = if (dev_obj.getOrNull("fileMode")) |m| @intCast(m.integer()) else null,
                .uid = if (dev_obj.getOrNull("uid")) |u| @intCast(u.integer()) else null,
                .gid = if (dev_obj.getOrNull("gid")) |g| @intCast(g.integer()) else null,
            };
        }
        devices = dev_list;
    }

    return spec.LinuxSpec{
        .namespaces = namespaces,
        .devices = devices,
        .resources = null,
        .cgroupsPath = null,
        .seccomp = null,
        .selinux = null,
    };
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

pub fn parseProcess(allocator: Allocator, value: *json.JsonValue) !Process {
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
    var user: ?User = null;
    if (obj.getOrNull("user")) |user_obj| {
        user = try parseUser(allocator, user_obj);
    }

    // Parse capabilities
    var capabilities: ?Capabilities = null;
    if (obj.getOrNull("capabilities")) |caps_obj| {
        capabilities = try parseCapabilities(caps_obj, allocator);
    }

    // Parse rlimits
    var rlimits: ?[]spec.RLimit = null;
    if (obj.getOrNull("rlimits")) |rlimits_array| {
        if (rlimits_array.type != .array) return error.InvalidSpec;
        const items = rlimits_array.array();
        var rlimits_list = try allocator.alloc(spec.RLimit, items.len());
        for (items.items(), 0..) |item, i| {
            const type_str = if (item.object().getOrNull("type")) |type_value| type_value.string() else return error.InvalidSpec;
            const rlimit_type = std.meta.stringToEnum(spec.RlimitType, type_str) orelse return error.InvalidSpec;
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

    return Process{
        .args = args,
        .env = env,
        .cwd = cwd,
        .user = user orelse return error.InvalidSpec,
        .capabilities = capabilities,
        .rlimits = rlimits,
        .terminal = terminal,
    };
}

fn parseUser(allocator: Allocator, value: *json.JsonValue) !User {
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

    return User{
        .uid = uid,
        .gid = gid,
        .additionalGids = additional_gids,
    };
}

fn parseCapabilities(value: *json.JsonValue, allocator: Allocator) !?Capabilities {
    if (value.type != .object) return error.InvalidSpec;
    const obj = value.object();

    var result = Capabilities{};

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