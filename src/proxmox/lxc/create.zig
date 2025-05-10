const std = @import("std");
const proxmox = @import("proxmox");
const logger = @import("logger");
const oci = @import("oci");
const types = @import("types");
const network = @import("network");

const NetworkError = error{
    InvalidAnnotation,
    MissingRequiredAnnotation,
    InvalidIPAddress,
    InvalidMACAddress,
    CNIError,
};

pub fn createLXC(client: *proxmox.ProxmoxClient, oci_container_id: []const u8, spec: *const oci.Spec) !void {
    const vmid = try client.getProxmoxVMID(oci_container_id);

    const api_path = try std.fmt.allocPrint(client.allocator, "/nodes/{s}/lxc", .{client.node});
    defer client.allocator.free(api_path);

    // Створюємо конфігурацію для Proxmox LXC
    var config = std.StringHashMap([]const u8).init(client.allocator);
    defer {
        var iter = config.iterator();
        while (iter.next()) |entry| {
            client.allocator.free(entry.value_ptr.*);
        }
        config.deinit();
    }

    // Базові налаштування
    try config.put("vmid", try std.fmt.allocPrint(client.allocator, "{d}", .{vmid}));
    try config.put("hostname", try client.allocator.dupe(u8, spec.hostname));
    try config.put("ostype", try client.allocator.dupe(u8, "ubuntu")); // За замовчуванням використовуємо Ubuntu

    // Налаштування процесу
    if (spec.process) |process| {
        // User/Group
        try config.put("unprivileged", try std.fmt.allocPrint(client.allocator, "{d}", .{process.user.uid != 0}));
        if (process.user.uid != 0) {
            try config.put("uid", try std.fmt.allocPrint(client.allocator, "{d}", .{process.user.uid}));
        }
        if (process.user.gid != 0) {
            try config.put("gid", try std.fmt.allocPrint(client.allocator, "{d}", .{process.user.gid}));
        }

        // Environment
        if (process.env.len > 0) {
            var env_str = std.ArrayList(u8).init(client.allocator);
            defer env_str.deinit();
            for (process.env) |env| {
                try env_str.appendSlice(env);
                try env_str.append('\n');
            }
            try config.put("environment", try env_str.toOwnedSlice());
        }

        // Capabilities
        if (process.capabilities) |caps| {
            if (caps.bounding) |bounding| {
                var cap_str = std.ArrayList(u8).init(client.allocator);
                defer cap_str.deinit();
                for (bounding) |cap| {
                    try cap_str.appendSlice(cap);
                    try cap_str.append(',');
                }
                if (cap_str.items.len > 0) {
                    _ = cap_str.pop(); // Видаляємо останню кому
                }
                try config.put("capabilities", try cap_str.toOwnedSlice());
            }
        }
    }

    // Налаштування root filesystem
    if (spec.root) |root| {
        try config.put("rootfs", try client.allocator.dupe(u8, root.path));
        if (root.readonly) {
            try config.put("ro", try client.allocator.dupe(u8, "1"));
        }
    }

    // Налаштування монтування
    if (spec.mounts.len > 0) {
        var mp_index: usize = 0;
        for (spec.mounts) |mount| {
            const mp_name = try std.fmt.allocPrint(client.allocator, "mp{d}", .{mp_index});
            const mp_value = try std.fmt.allocPrint(client.allocator, "{s},mp={s}", .{ mount.source, mount.destination });
            try config.put(mp_name, mp_value);
            mp_index += 1;
        }
    }

    // Linux-специфічні налаштування
    if (spec.linux) |linux| {
        // Namespaces
        for (linux.namespaces) |ns| {
            switch (ns.type[0]) {
                'n' => if (std.mem.eql(u8, ns.type, "network")) {
                    // Налаштування мережі через Kube-OVN
                    if (spec.annotations) |annotations| {
                        try configureKubeOVNNetwork(client.allocator, &config, annotations) catch |err| {
                            logger.err("Failed to configure network: {}", .{err});
                            return err;
                        };
                    } else {
                        return NetworkError.MissingRequiredAnnotation;
                    }
                },
                'i' => if (std.mem.eql(u8, ns.type, "ipc")) {
                    try config.put("ipc", try client.allocator.dupe(u8, "1"));
                },
                'p' => if (std.mem.eql(u8, ns.type, "pid")) {
                    try config.put("pid", try client.allocator.dupe(u8, "1"));
                },
                'u' => if (std.mem.eql(u8, ns.type, "uts")) {
                    try config.put("uts", try client.allocator.dupe(u8, "1"));
                },
                else => {},
            }
        }

        // Resources
        if (linux.resources) |resources| {
            // Memory
            if (resources.memory) |memory| {
                if (memory.limit) |limit| {
                    try config.put("memory", try std.fmt.allocPrint(client.allocator, "{d}", .{limit / (1024 * 1024)}));
                }
                if (memory.swap) |swap| {
                    try config.put("swap", try std.fmt.allocPrint(client.allocator, "{d}", .{swap / (1024 * 1024)}));
                }
            }

            // CPU
            if (resources.cpu) |cpu| {
                if (cpu.shares) |shares| {
                    try config.put("cpuunits", try std.fmt.allocPrint(client.allocator, "{d}", .{shares}));
                }
                if (cpu.quota) |quota| {
                    try config.put("cpulimit", try std.fmt.allocPrint(client.allocator, "{d}", .{@divFloor(quota, 100000)}));
                }
                if (cpu.cpus) |cpus| {
                    try config.put("cores", try std.fmt.allocPrint(client.allocator, "{d}", .{try parseCpuCount(cpus)}));
                }
            }

            // Devices
            if (linux.devices.len > 0) {
                for (linux.devices) |device| {
                    const dev_name = try std.fmt.allocPrint(client.allocator, "dev{d}", .{device.major});
                    const dev_value = try std.fmt.allocPrint(client.allocator, "{s}:{d}:{d}", .{ device.type, device.major, device.minor });
                    try config.put(dev_name, dev_value);
                }
            }
        }

        // Seccomp
        if (linux.seccomp) |seccomp| {
            try config.put("seccomp", try client.allocator.dupe(u8, seccomp.defaultAction));
        }
    }

    // Анотації
    if (spec.annotations) |annotations| {
        var it = annotations.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, "proxmox.")) {
                const key = entry.key_ptr.*["proxmox.".len..];
                try config.put(key, try client.allocator.dupe(u8, entry.value_ptr.*));
            }
        }
    }

    // Перетворюємо конфігурацію в JSON
    const body = try std.json.stringifyAlloc(client.allocator, config, .{});
    defer client.allocator.free(body);

    // Відправляємо запит на створення контейнера
    const response = try client.makeRequest(.POST, api_path, body);
    defer client.allocator.free(response);

    // Перевіряємо відповідь
    var parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    // Логуємо успішне створення
    try logger.info("Created LXC container with VMID: {d}", .{vmid});
}

fn configureKubeOVNNetwork(allocator: std.mem.Allocator, config: *std.StringHashMap([]const u8), annotations: std.StringHashMap([]const u8)) !void {
    // Створюємо CNI менеджер
    var cni_manager = try network.NetworkManager.init(allocator);
    defer cni_manager.deinit();

    // Отримуємо мережевий namespace контейнера
    const netns = try std.fs.openFileAbsolute("/proc/self/ns/net", .{});
    defer netns.close();

    // Готуємо CNI конфігурацію
    var cni_config = network.CNIPlugin.Config{
        .container_id = try allocator.dupe(u8, config.get("vmid").?),
        .netns = netns,
        .ifname = "eth0",
        .annotations = annotations,
    };
    defer cni_config.deinit(allocator);

    // Викликаємо CNI ADD
    const result = try cni_manager.add(&cni_config) catch |err| {
        logger.err("Failed to execute CNI ADD: {}", .{err});
        return NetworkError.CNIError;
    };
    defer result.deinit(allocator);

    // Налаштовуємо мережу в LXC на основі результату CNI
    var net_config = std.ArrayList(u8).init(allocator);
    defer net_config.deinit();

    try net_config.writer().print("name=eth0,type=veth,bridge={s},", .{
        result.bridge orelse "vmbr0",
    });

    if (result.ip) |ip| {
        try net_config.writer().print("ip={s}/{d},", .{ ip.address, ip.prefix_len });
    }

    if (result.gateway) |gw| {
        try net_config.writer().print("gw={s},", .{gw});
    }

    if (result.mac_address) |mac| {
        try net_config.writer().print("hwaddr={s},", .{mac});
    }

    if (result.mtu) |mtu| {
        try net_config.writer().print("mtu={d},", .{mtu});
    }

    // Видаляємо останню кому
    if (net_config.items.len > 0) {
        _ = net_config.pop();
    }

    // Зберігаємо налаштування мережі
    try config.put("net0", try net_config.toOwnedSlice());

    // Налаштовуємо DNS якщо він є в результаті CNI
    if (result.dns) |dns| {
        if (dns.nameservers.len > 0) {
            const dns_servers = try std.mem.join(allocator, " ", dns.nameservers);
            defer allocator.free(dns_servers);
            try config.put("nameserver", try allocator.dupe(u8, dns_servers));
        }

        if (dns.search.len > 0) {
            const search_domains = try std.mem.join(allocator, " ", dns.search);
            defer allocator.free(search_domains);
            try config.put("searchdomain", try allocator.dupe(u8, search_domains));
        }
    }

    // Логуємо успішне налаштування мережі
    try logger.info("Configured network for container using CNI", .{});
}

fn parseCpuCount(cpus: []const u8) !u32 {
    var count: u32 = 0;
    var it = std.mem.split(u8, cpus, ",");
    while (it.next()) |range| {
        if (std.mem.indexOf(u8, range, "-")) |sep| {
            const start = try std.fmt.parseInt(u32, range[0..sep], 10);
            const end = try std.fmt.parseInt(u32, range[sep + 1 ..], 10);
            count += end - start + 1;
        } else {
            count += 1;
        }
    }
    return count;
}
