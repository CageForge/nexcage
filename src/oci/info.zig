const std = @import("std");
const logger = std.log.scoped(.oci_info);
const proxmox = @import("proxmox");
const types = @import("types");

// Структури для JSON виводу
const RuntimeInfo = struct {
    version: []const u8,
    git_commit: []const u8,
    spec: []const u8,
    runtime: []const u8,
    built: []const u8,
    compiler: []const u8,
    platform: []const u8,

    backends: Backends,
    features: []const []const u8,
    isolation: Isolation,

    pub fn toJson(self: RuntimeInfo, allocator: std.mem.Allocator) ![]const u8 {
        var json = std.ArrayList(u8).init(allocator);
        defer json.deinit();

        // Початок JSON
        try json.writer().print("{{\n", .{});

        // Основна інформація
        try json.writer().print("  \"version\": \"{s}\",\n", .{self.version});
        try json.writer().print("  \"git_commit\": \"{s}\",\n", .{self.git_commit});
        try json.writer().print("  \"spec\": \"{s}\",\n", .{self.spec});
        try json.writer().print("  \"runtime\": \"{s}\",\n", .{self.runtime});
        try json.writer().print("  \"built\": \"{s}\",\n", .{self.built});
        try json.writer().print("  \"compiler\": \"{s}\",\n", .{self.compiler});
        try json.writer().print("  \"platform\": \"{s}\",\n\n", .{self.platform});

        // Backends
        try json.writer().print("  \"backends\": {{\n", .{});
        try json.writer().print("    \"default\": \"{s}\",\n", .{self.backends.default});
        try json.writer().print("    \"proxmox-lxcri\": {{\n", .{});
        try json.writer().print("      \"engine\": \"{s}\",\n", .{self.backends.proxmox_lxcri.engine});
        try json.writer().print("      \"hypervisor\": \"{s}\",\n", .{self.backends.proxmox_lxcri.hypervisor});
        try json.writer().print("      \"sandbox_model\": \"{s}\",\n", .{self.backends.proxmox_lxcri.sandbox_model});
        try json.writer().print("      \"use_cases\": [\n", .{});
        try json.writer().print("        \"{s}\",\n", .{self.backends.proxmox_lxcri.use_cases[0]});
        try json.writer().print("        \"{s}\",\n", .{self.backends.proxmox_lxcri.use_cases[1]});
        try json.writer().print("        \"{s}\"\n", .{self.backends.proxmox_lxcri.use_cases[2]});
        try json.writer().print("      ]\n", .{});
        try json.writer().print("    }}\n", .{});
        try json.writer().print("  }},\n\n", .{});

        // Features
        try json.writer().print("  \"features\": [\n", .{});
        for (self.features, 0..) |feature, i| {
            if (i < self.features.len - 1) {
                try json.writer().print("    \"{s}\",\n", .{feature});
            } else {
                try json.writer().print("    \"{s}\"\n", .{feature});
            }
        }
        try json.writer().print("  ],\n\n", .{});

        // Isolation
        try json.writer().print("  \"isolation\": {{\n", .{});
        try json.writer().print("    \"image_support\": \"{s}\",\n", .{self.isolation.image_support});

        // Namespaces
        try json.writer().print("    \"namespaces\": [", .{});
        for (self.isolation.namespaces, 0..) |ns, i| {
            if (i < self.isolation.namespaces.len - 1) {
                try json.writer().print("\"{s}\", ", .{ns});
            } else {
                try json.writer().print("\"{s}\"", .{ns});
            }
        }
        try json.writer().print("],\n", .{});

        // Storage
        try json.writer().print("    \"storage\": {{\n", .{});
        try json.writer().print("      \"driver\": \"{s}\",\n", .{self.isolation.storage.driver});
        try json.writer().print("      \"snapshotting\": {s}\n", .{if (self.isolation.storage.snapshotting) "true" else "false"});
        try json.writer().print("    }},\n", .{});

        // Network
        try json.writer().print("    \"network\": {{\n", .{});
        try json.writer().print("      \"cni_plugins\": [", .{});
        for (self.isolation.network.cni_plugins, 0..) |plugin, i| {
            if (i < self.isolation.network.cni_plugins.len - 1) {
                try json.writer().print("\"{s}\", ", .{plugin});
            } else {
                try json.writer().print("\"{s}\"", .{plugin});
            }
        }
        try json.writer().print("],\n", .{});
        try json.writer().print("      \"proxmox_vnet\": {s}\n", .{if (self.isolation.network.proxmox_vnet) "true" else "false"});
        try json.writer().print("    }},\n", .{});

        // Security
        try json.writer().print("    \"security\": {{\n", .{});
        try json.writer().print("      \"idmapped_mounts\": {s},\n", .{if (self.isolation.security.idmapped_mounts) "true" else "false"});
        try json.writer().print("      \"seccomp\": {s},\n", .{if (self.isolation.security.seccomp) "true" else "false"});
        try json.writer().print("      \"capabilities\": {s}\n", .{if (self.isolation.security.capabilities) "true" else "false"});
        try json.writer().print("    }}\n", .{});

        // Кінець JSON
        try json.writer().print("  }}\n", .{});
        try json.writer().print("}}\n", .{});

        return json.toOwnedSlice();
    }
};

const Backends = struct {
    default: []const u8,
    proxmox_lxcri: ProxmoxBackend,
};

const ProxmoxBackend = struct {
    engine: []const u8,
    hypervisor: []const u8,
    sandbox_model: []const u8,
    use_cases: [3][]const u8,
};

const Isolation = struct {
    image_support: []const u8,
    namespaces: [6][]const u8,
    storage: StorageInfo,
    network: NetworkInfo,
    security: SecurityInfo,
};

const StorageInfo = struct {
    driver: []const u8,
    snapshotting: bool,
};

const NetworkInfo = struct {
    cni_plugins: [3][]const u8,
    proxmox_vnet: bool,
};

const SecurityInfo = struct {
    idmapped_mounts: bool,
    seccomp: bool,
    capabilities: bool,
};

// Функція для отримання поточної дати/часу
fn getCurrentTimestamp() []const u8 {
    const now = std.time.timestamp();
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return std.fmt.allocPrint(std.heap.page_allocator, "{d:0>4}-{d:0>2}-{d:0>2}T00:00:00Z", .{ year_day.year, month_day.month.numeric(), month_day.day_index + 1 }) catch "2025-01-01T00:00:00Z";
}

// Функція для отримання git commit hash
fn getGitCommit() []const u8 {
    // Спрощена версія - в реальному проекті тут була б логіка отримання git hash
    return "a1b2c3d4";
}

pub fn info(container_id: ?[]const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    try proxmox_client.logger.info("Getting runtime information", .{});

    // Створюємо інформацію про runtime
    const runtime_info = RuntimeInfo{
        .version = "0.1.1",
        .git_commit = getGitCommit(),
        .spec = "1.1.0",
        .runtime = "proxmox-lxcri",
        .built = getCurrentTimestamp(),
        .compiler = "zig 0.13.0",
        .platform = "linux/amd64",

        .backends = Backends{
            .default = "crun",
            .proxmox_lxcri = ProxmoxBackend{
                .engine = "LXC",
                .hypervisor = "QEMU (optional)",
                .sandbox_model = "LXC as a Pod",
                .use_cases = [_][]const u8{ "stateful workloads", "large DB containers", "heavy JVM apps" },
            },
        },

        .features = &[_][]const u8{ "cgroup v2", "seccomp", "apparmor", "selinux", "rootless", "systemd", "idmapped-mounts", "criu" },

        .isolation = Isolation{
            .image_support = "OCI (via containerd/CRI-O)",
            .namespaces = [_][]const u8{ "pid", "net", "mnt", "ipc", "uts", "user" },
            .storage = StorageInfo{
                .driver = "proxmox-nfs-csi",
                .snapshotting = true,
            },
            .network = NetworkInfo{
                .cni_plugins = [_][]const u8{ "bridge", "calico", "flannel" },
                .proxmox_vnet = true,
            },
            .security = SecurityInfo{
                .idmapped_mounts = true,
                .seccomp = true,
                .capabilities = true,
            },
        },
    };

    // Конвертуємо в JSON та виводимо
    const json_output = try runtime_info.toJson(proxmox_client.allocator);
    defer proxmox_client.allocator.free(json_output);

    try std.io.getStdOut().writer().print("{s}\n", .{json_output});

    // Якщо передано container_id, додатково показуємо інформацію про контейнер
    if (container_id) |cid| {
        try showContainerInfo(cid, proxmox_client);
    }
}

// Функція для показу інформації про конкретний контейнер
fn showContainerInfo(container_id: []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    try proxmox_client.logger.info("Getting info for container: {s}", .{container_id});

    // Отримуємо список контейнерів щоб знайти VMID за іменем
    const containers = try proxmox_client.listLXCs();
    defer {
        for (containers) |*container| {
            container.deinit(proxmox_client.allocator);
        }
        proxmox_client.allocator.free(containers);
    }

    // Шукаємо контейнер за іменем
    var vmid: ?u32 = null;
    var found_container: ?types.LXCContainer = null;
    for (containers) |container| {
        if (std.mem.eql(u8, container.name, container_id)) {
            vmid = container.vmid;
            found_container = container;
            break;
        }
    }

    if (vmid == null or found_container == null) {
        try proxmox_client.logger.err("Container with name {s} not found", .{container_id});
        return error.ContainerNotFound;
    }

    const container = found_container.?;

    // Виводимо детальну інформацію про контейнер у JSON форматі
    try std.io.getStdOut().writer().print(
        \\,
        \\Container Information:
        \\{{
        \\  "id": "{s}",
        \\  "vmid": {d},
        \\  "name": "{s}",
        \\  "status": "{s}",
        \\  "type": "LXC",
        \\  "config": {{
        \\    "hostname": "{s}",
        \\    "ostype": "{s}",
        \\    "memory": {d},
        \\    "cores": {d},
        \\    "rootfs": "{s}",
        \\    "network": {{
        \\      "name": "{s}",
        \\      "bridge": "{s}",
        \\      "ip": "{s}"
        \\    }}
        \\  }}
        \\}}
    , .{
        container_id,
        container.vmid,
        container.name,
        @tagName(container.status),
        container.config.hostname,
        container.config.ostype,
        container.config.memory,
        container.config.cores,
        container.config.rootfs,
        container.config.net0.name,
        container.config.net0.bridge,
        container.config.net0.ip,
    });
}
