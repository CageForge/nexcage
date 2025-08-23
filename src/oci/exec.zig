const std = @import("std");
const logger = std.log.scoped(.oci_exec);
const proxmox = @import("proxmox");
const types = @import("types");

// Структура для параметрів команди exec
pub const ExecOptions = struct {
    container_id: []const u8,
    command: []const u8,
    args: ?[]const []const u8 = null,
    working_dir: ?[]const u8 = null,
    env: ?[]const []const u8 = null,
    user: ?[]const u8 = null,
    tty: bool = false,
    privileged: bool = false,
};

// Структура для результату виконання команди
pub const ExecResult = struct {
    exit_code: i32,
    stdout: []const u8,
    stderr: []const u8,
    
    pub fn deinit(self: *const ExecResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

// Основна функція для виконання команди в контейнері
pub fn exec(options: ExecOptions, proxmox_client: *proxmox.ProxmoxClient) !ExecResult {
    try proxmox_client.logger.info("Executing command '{s}' in container: {s}", .{options.command, options.container_id});
    
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
        if (std.mem.eql(u8, container.name, options.container_id)) {
            vmid = container.vmid;
            found_container = container;
            break;
        }
    }

    if (vmid == null or found_container == null) {
        try proxmox_client.logger.err("Container with name {s} not found", .{options.container_id});
        return error.ContainerNotFound;
    }

    const container = found_container.?;
    
    // Перевіряємо, чи контейнер запущений
    if (container.status != .running) {
        try proxmox_client.logger.err("Container {s} is not running (status: {s})", .{options.container_id, @tagName(container.status)});
        return error.ContainerNotRunning;
    }

    // Формуємо повну команду з аргументами
    var full_command = std.ArrayList(u8).init(proxmox_client.allocator);
    defer full_command.deinit();
    
    try full_command.appendSlice(options.command);
    
    if (options.args) |args| {
        for (args) |arg| {
            try full_command.append(' ');
            try full_command.appendSlice(arg);
        }
    }

    try proxmox_client.logger.info("Full command: {s}", .{full_command.items});

    // Використовуємо Proxmox API для виконання команди
    return try executeViaProxmoxAPI(container.vmid, full_command.items, options, proxmox_client);
}

// Функція для виконання команди через Proxmox API
fn executeViaProxmoxAPI(vmid: u32, command: []const u8, options: ExecOptions, proxmox_client: *proxmox.ProxmoxClient) !ExecResult {
    try proxmox_client.logger.info("Executing via Proxmox API for VMID: {d}", .{vmid});
    
    // Створюємо payload для API запиту
    var payload = std.ArrayList(u8).init(proxmox_client.allocator);
    defer payload.deinit();
    
    // Формуємо JSON payload
    try payload.writer().print("{{\n", .{});
    try payload.writer().print("  \"command\": \"{s}\"", .{command});
    
    if (options.working_dir) |wd| {
        try payload.writer().print(",\n  \"cwd\": \"{s}\"", .{wd});
    }
    
    if (options.env) |env_vars| {
        try payload.writer().print(",\n  \"env\": [", .{});
        for (env_vars, 0..) |env_var, i| {
            if (i > 0) try payload.writer().print(", ", .{});
            try payload.writer().print("\"{s}\"", .{env_var});
        }
        try payload.writer().print("]", .{});
    }
    
    if (options.user) |user| {
        try payload.writer().print(",\n  \"user\": \"{s}\"", .{user});
    }
    
    try payload.writer().print(",\n  \"tty\": {s}", .{if (options.tty) "true" else "false"});
    try payload.writer().print(",\n  \"privileged\": {s}", .{if (options.privileged) "true" else "false"});
    try payload.writer().print("\n}}", .{});
    
    try proxmox_client.logger.debug("API payload: {s}", .{payload.items});
    
    // Виконуємо POST запит до Proxmox API
    const node = proxmox_client.node;
    const url = try std.fmt.allocPrint(
        proxmox_client.allocator,
        "/nodes/{s}/lxc/{d}/exec",
        .{node, vmid}
    );
    defer proxmox_client.allocator.free(url);
    
    try proxmox_client.logger.info("Making POST request to: {s}", .{url});
    
    // Тут має бути реалізація HTTP POST запиту
    // Поки що повертаємо заглушку
    try proxmox_client.logger.info("POST request to {s} with payload: {s}", .{url, payload.items});
    
    // Заглушка - в реальній реалізації тут буде HTTP запит
    // та обробка відповіді
    return ExecResult{
        .exit_code = 0,
        .stdout = try proxmox_client.allocator.dupe(u8, "Command executed successfully\n"),
        .stderr = try proxmox_client.allocator.dupe(u8, ""),
    };
}

// Альтернативна функція для виконання через lxc-attach (якщо доступно)
pub fn execViaLXCAttach(options: ExecOptions, proxmox_client: *proxmox.ProxmoxClient) !ExecResult {
    try proxmox_client.logger.info("Executing via lxc-attach for container: {s}", .{options.container_id});
    
    // Отримуємо VMID контейнера
    const containers = try proxmox_client.listLXCs();
    defer {
        for (containers) |*container| {
            container.deinit(proxmox_client.allocator);
        }
        proxmox_client.allocator.free(containers);
    }

    var vmid: ?u32 = null;
    for (containers) |container| {
        if (std.mem.eql(u8, container.name, options.container_id)) {
            vmid = container.vmid;
            break;
        }
    }

    if (vmid == null) {
        try proxmox_client.logger.err("Container with name {s} not found", .{options.container_id});
        return error.ContainerNotFound;
    }

    // Формуємо команду для lxc-attach
    var lxc_command = std.ArrayList([]const u8).init(proxmox_client.allocator);
    defer lxc_command.deinit();
    
    // Додаємо базову команду
    try lxc_command.append("lxc-attach");
    try lxc_command.append("-n");
    try lxc_command.append(try std.fmt.allocPrint(proxmox_client.allocator, "{d}", .{vmid}));
    
    // Додаємо опції
    if (options.working_dir) |wd| {
        try lxc_command.append("-c");
        try lxc_command.append(try std.fmt.allocPrint(proxmox_client.allocator, "cd {s}", .{wd}));
    }
    
    if (options.user) |user| {
        try lxc_command.append("-u");
        try lxc_command.append(user);
    }
    
    // Додаємо основну команду
    try lxc_command.append("--");
    try lxc_command.append(options.command);
    
    if (options.args) |args| {
        for (args) |arg| {
            try lxc_command.append(arg);
        }
    }

    try proxmox_client.logger.info("lxc-attach command: {s}", .{std.mem.join(proxmox_client.allocator, " ", lxc_command.items) catch "error"});
    
    // Тут має бути реалізація виконання команди через child process
    // Поки що повертаємо заглушку
    try proxmox_client.logger.info("Executing lxc-attach command (placeholder)", .{});
    
    return ExecResult{
        .exit_code = 0,
        .stdout = try proxmox_client.allocator.dupe(u8, "Command executed via lxc-attach\n"),
        .stderr = try proxmox_client.allocator.dupe(u8, ""),
    };
}

// Функція для виконання через pct exec (Proxmox CLI)
pub fn execViaPCT(options: ExecOptions, proxmox_client: *proxmox.ProxmoxClient) !ExecResult {
    try proxmox_client.logger.info("Executing via pct exec for container: {s}", .{options.container_id});
    
    // Отримуємо VMID контейнера
    const containers = try proxmox_client.listLXCs();
    defer {
        for (containers) |*container| {
            container.deinit(proxmox_client.allocator);
        }
        proxmox_client.allocator.free(containers);
    }

    var vmid: ?u32 = null;
    for (containers) |container| {
        if (std.mem.eql(u8, container.name, options.container_id)) {
            vmid = container.vmid;
            break;
        }
    }

    if (vmid == null) {
        try proxmox_client.logger.err("Container with name {s} not found", .{options.container_id});
        return error.ContainerNotFound;
    }

    // Формуємо команду для pct exec
    var pct_command = std.ArrayList([]const u8).init(proxmox_client.allocator);
    defer pct_command.deinit();
    
    try pct_command.append("pct");
    try pct_command.append("exec");
    try pct_command.append(try std.fmt.allocPrint(proxmox_client.allocator, "{d}", .{vmid}));
    try pct_command.append("--");
    
    // Додаємо робочу директорію якщо вказана
    if (options.working_dir) |wd| {
        try pct_command.append("/bin/bash");
        try pct_command.append("-c");
        try pct_command.append(try std.fmt.allocPrint(proxmox_client.allocator, "cd {s} && {s}", .{wd, options.command}));
    } else {
        try pct_command.append(options.command);
    }
    
    // Додаємо аргументи якщо є
    if (options.args) |args| {
        for (args) |arg| {
            try pct_command.append(arg);
        }
    }

    try proxmox_client.logger.info("pct exec command: {s}", .{std.mem.join(proxmox_client.allocator, " ", pct_command.items) catch "error"});
    
    // Тут має бути реалізація виконання команди через child process
    // Поки що повертаємо заглушку
    try proxmox_client.logger.info("Executing pct exec command (placeholder)", .{});
    
    return ExecResult{
        .exit_code = 0,
        .stdout = try proxmox_client.allocator.dupe(u8, "Command executed via pct exec\n"),
        .stderr = try proxmox_client.allocator.dupe(u8, ""),
    };
}
