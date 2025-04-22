const std = @import("std");
const c = @cImport({
    @cInclude("lxc/lxccontainer.h");
});
const Allocator = std.mem.Allocator;
const oci = @import("../oci/spec.zig");

pub const NetworkError = error{
    ConfigurationFailed,
    InterfaceCreationFailed,
    RouteAdditionFailed,
    DnsConfigurationFailed,
    InvalidConfiguration,
};

pub const LxcNetwork = struct {
    container: *c.struct_lxc_container,
    allocator: Allocator,

    const Self = @This();

    pub fn init(container: *c.struct_lxc_container, allocator: Allocator) Self {
        return Self{
            .container = container,
            .allocator = allocator,
        };
    }

    pub fn configure(self: *Self, network: oci.LinuxNetwork) NetworkError!void {
        // Налаштування мережевих інтерфейсів
        if (network.interfaces) |interfaces| {
            for (interfaces) |interface| {
                try self.configureInterface(interface);
            }
        }

        // Налаштування маршрутів
        if (network.routes) |routes| {
            for (routes) |route| {
                try self.addRoute(route);
            }
        }

        // Налаштування DNS
        if (network.dnsServers != null or network.dnsSearch != null) {
            try self.configureDns(network);
        }
    }

    fn configureInterface(self: *Self, interface: oci.NetworkInterface) NetworkError!void {
        // Створення конфігурації мережевого інтерфейсу для LXC
        var key_buf: [256]u8 = undefined;
        
        // Базова конфігурація
        const key = std.fmt.bufPrint(&key_buf, "lxc.net.0.type", .{}) catch return NetworkError.ConfigurationFailed;
        if (self.container.set_config_item(self.container, key.ptr, "veth") == 0) {
            return NetworkError.ConfigurationFailed;
        }

        // Ім'я інтерфейсу
        const name_key = std.fmt.bufPrint(&key_buf, "lxc.net.0.name", .{}) catch return NetworkError.ConfigurationFailed;
        if (self.container.set_config_item(self.container, name_key.ptr, interface.name.ptr) == 0) {
            return NetworkError.ConfigurationFailed;
        }

        // IP адреси
        if (interface.address) |addresses| {
            for (addresses) |addr| {
                const ipv4_key = std.fmt.bufPrint(&key_buf, "lxc.net.0.ipv4.address", .{}) catch return NetworkError.ConfigurationFailed;
                if (self.container.set_config_item(self.container, ipv4_key.ptr, addr.ptr) == 0) {
                    return NetworkError.ConfigurationFailed;
                }
            }
        }

        // MAC адреса
        if (interface.mac) |mac| {
            const mac_key = std.fmt.bufPrint(&key_buf, "lxc.net.0.hwaddr", .{}) catch return NetworkError.ConfigurationFailed;
            if (self.container.set_config_item(self.container, mac_key.ptr, mac.ptr) == 0) {
                return NetworkError.ConfigurationFailed;
            }
        }

        // MTU
        if (interface.mtu) |mtu| {
            const mtu_str = std.fmt.allocPrint(self.allocator, "{d}", .{mtu}) catch return NetworkError.ConfigurationFailed;
            defer self.allocator.free(mtu_str);
            
            const mtu_key = std.fmt.bufPrint(&key_buf, "lxc.net.0.mtu", .{}) catch return NetworkError.ConfigurationFailed;
            if (self.container.set_config_item(self.container, mtu_key.ptr, mtu_str.ptr) == 0) {
                return NetworkError.ConfigurationFailed;
            }
        }
    }

    fn addRoute(self: *Self, route: oci.NetworkRoute) NetworkError!void {
        var cmd_buf: [512]u8 = undefined;
        
        // Формування команди для додавання маршруту
        const cmd = std.fmt.bufPrint(
            &cmd_buf,
            "ip route add {s} via {s} {s}",
            .{
                route.destination,
                route.gateway,
                if (route.source) |src| src else "",
            }
        ) catch return NetworkError.RouteAdditionFailed;

        // Виконання команди в контейнері
        if (self.container.attach_run_wait(
            self.container,
            null,
            null,
            null,
            null,
            null,
            cmd.ptr,
            null
        ) != 0) {
            return NetworkError.RouteAdditionFailed;
        }
    }

    fn configureDns(self: *Self, network: oci.LinuxNetwork) NetworkError!void {
        var resolv_conf = std.ArrayList(u8).init(self.allocator);
        defer resolv_conf.deinit();

        // Додавання DNS серверів
        if (network.dnsServers) |servers| {
            for (servers) |server| {
                try resolv_conf.appendSlice("nameserver ");
                try resolv_conf.appendSlice(server);
                try resolv_conf.append('\n');
            }
        }

        // Додавання опцій DNS
        if (network.dnsOptions) |options| {
            for (options) |option| {
                try resolv_conf.appendSlice("options ");
                try resolv_conf.appendSlice(option);
                try resolv_conf.append('\n');
            }
        }

        // Додавання доменів пошуку
        if (network.dnsSearch) |search| {
            try resolv_conf.appendSlice("search");
            for (search) |domain| {
                try resolv_conf.append(' ');
                try resolv_conf.appendSlice(domain);
            }
            try resolv_conf.append('\n');
        }

        // Запис конфігурації в /etc/resolv.conf контейнера
        const resolv_conf_path = "/etc/resolv.conf";
        const content = try resolv_conf.toOwnedSlice();
        defer self.allocator.free(content);

        if (self.container.attach_run_wait(
            self.container,
            null,
            null,
            null,
            null,
            null,
            "sh",
            "-c",
            std.fmt.bufPrint(
                &[_]u8{512} ** undefined,
                "echo '{s}' > {s}",
                .{ content, resolv_conf_path }
            ) catch return NetworkError.DnsConfigurationFailed
        ) != 0) {
            return NetworkError.DnsConfigurationFailed;
        }
    }
}; 