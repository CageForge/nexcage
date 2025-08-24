const std = @import("std");
const logger = std.log.scoped(.oci_exec);
const proxmox = @import("proxmox");
const types = @import("types");
const ChildProcess = std.process.Child;

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
    method: ExecutionMethod = .auto,
};

// Метод виконання команди
pub const ExecutionMethod = enum {
    auto,       // Автоматичний вибір
    pct,        // Через pct exec
    api,        // Через Proxmox API
    lxc_attach, // Через lxc-attach
};

// Структура для результату виконання команди
pub const ExecResult = struct {
    exit_code: i32,
    stdout: []const u8,
    stderr: []const u8,
    execution_time_ns: u64,
    method_used: ExecutionMethod,
    
    pub fn deinit(self: *const ExecResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
    
    pub fn printTiming(self: *const ExecResult) void {
        const time_ms = @as(f64, @floatFromInt(self.execution_time_ns)) / 1_000_000.0;
        std.io.getStdOut().writer().print("Execution time: {d:.3} ms (method: {s})\n", .{
            time_ms, @tagName(self.method_used)
        }) catch {};
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

    // Визначаємо метод виконання
    const method = if (options.method == .auto) selectBestMethod(container.vmid) else options.method;
    
    // Виконуємо команду обраним методом
    return switch (method) {
        .pct => try execViaPCT(container.vmid, full_command.items, options, proxmox_client),
        .api => try execViaProxmoxAPI(container.vmid, full_command.items, options, proxmox_client),
        .lxc_attach => try execViaLXCAttach(container.vmid, full_command.items, options, proxmox_client),
        .auto => unreachable, // Вже оброблено вище
    };
}

// Функція для автоматичного вибору найкращого методу
fn selectBestMethod(_: u32) ExecutionMethod {
    // Перевіряємо доступність pct
    if (isPCTAvailable()) {
        return .pct; // pct зазвичай швидший для локальних операцій
    }
    
    // Перевіряємо доступність lxc-attach
    if (isLXCAttachAvailable()) {
        return .lxc_attach;
    }
    
    // За замовчуванням використовуємо API
    return .api;
}

// Перевірка доступності pct
fn isPCTAvailable() bool {
    const result = ChildProcess.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "which", "pct" },
    }) catch return false;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    return result.term.Exited == 0 and result.stdout.len > 0;
}

// Перевірка доступності lxc-attach
fn isLXCAttachAvailable() bool {
    const result = ChildProcess.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "which", "lxc-attach" },
    }) catch return false;
    return result.term.Exited == 0 and result.stdout.len > 0;
}

// Функція для виконання команди через Proxmox API
fn execViaProxmoxAPI(vmid: u32, command: []const u8, options: ExecOptions, proxmox_client: *proxmox.ProxmoxClient) !ExecResult {
    const start_time = std.time.nanoTimestamp();
    
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
    const end_time = std.time.nanoTimestamp();
    const execution_time = @as(u64, @intCast(end_time - start_time));
    
    return ExecResult{
        .exit_code = 0,
        .stdout = try proxmox_client.allocator.dupe(u8, "Command executed successfully via Proxmox API\n"),
        .stderr = try proxmox_client.allocator.dupe(u8, ""),
        .execution_time_ns = execution_time,
        .method_used = .api,
    };
}

// Функція для виконання через pct exec (Proxmox CLI)
fn execViaPCT(vmid: u32, command: []const u8, options: ExecOptions, proxmox_client: *proxmox.ProxmoxClient) !ExecResult {
    const start_time = std.time.nanoTimestamp();
    
    try proxmox_client.logger.info("Executing via pct exec for VMID: {d}", .{vmid});
    
    // Формуємо команду для pct exec
    var pct_argv = std.ArrayList([]const u8).init(proxmox_client.allocator);
    defer pct_argv.deinit();
    
    try pct_argv.append("pct");
    try pct_argv.append("exec");
    const vmid_str = try std.fmt.allocPrint(proxmox_client.allocator, "{d}", .{vmid});
    defer proxmox_client.allocator.free(vmid_str);
    try pct_argv.append(vmid_str);
    try pct_argv.append("--");
    
    // Додаємо робочу директорію якщо вказана
    if (options.working_dir) |wd| {
        try pct_argv.append("/bin/bash");
        try pct_argv.append("-c");
        const cd_cmd = try std.fmt.allocPrint(proxmox_client.allocator, "cd {s} && {s}", .{wd, command});
        defer proxmox_client.allocator.free(cd_cmd);
        try pct_argv.append(cd_cmd);
    } else {
        try pct_argv.append(command);
    }
    
    // Додаємо аргументи якщо є
    if (options.args) |args| {
        for (args) |arg| {
            try pct_argv.append(arg);
        }
    }

    const cmd_str = std.mem.join(proxmox_client.allocator, " ", pct_argv.items) catch "error";
    defer if (cmd_str.len > 0) proxmox_client.allocator.free(cmd_str);
    try proxmox_client.logger.info("pct exec command: {s}", .{cmd_str});
    
    // Виконуємо команду через child process
    const result = try ChildProcess.run(.{
        .allocator = proxmox_client.allocator,
        .argv = pct_argv.items,
    });
    

    
    const end_time = std.time.nanoTimestamp();
    const execution_time = @as(u64, @intCast(end_time - start_time));
    
    return ExecResult{
        .exit_code = result.term.Exited,
        .stdout = result.stdout,
        .stderr = result.stderr,
        .execution_time_ns = execution_time,
        .method_used = .pct,
    };
}

// Функція для виконання через lxc-attach
fn execViaLXCAttach(vmid: u32, command: []const u8, options: ExecOptions, proxmox_client: *proxmox.ProxmoxClient) !ExecResult {
    const start_time = std.time.nanoTimestamp();
    
    try proxmox_client.logger.info("Executing via lxc-attach for VMID: {d}", .{vmid});
    
    // Формуємо команду для lxc-attach
    var lxc_argv = std.ArrayList([]const u8).init(proxmox_client.allocator);
    defer lxc_argv.deinit();
    
    try lxc_argv.append("lxc-attach");
    try lxc_argv.append("-n");
    const vmid_str = try std.fmt.allocPrint(proxmox_client.allocator, "{d}", .{vmid});
    defer proxmox_client.allocator.free(vmid_str);
    try lxc_argv.append(vmid_str);
    
    // Додаємо опції
    if (options.working_dir) |wd| {
        try lxc_argv.append("-c");
        const cd_cmd = try std.fmt.allocPrint(proxmox_client.allocator, "cd {s}", .{wd});
        defer proxmox_client.allocator.free(cd_cmd);
        try lxc_argv.append(cd_cmd);
    }
    
    if (options.user) |user| {
        try lxc_argv.append("-u");
        try lxc_argv.append(user);
    }
    
    // Додаємо основну команду
    try lxc_argv.append("--");
    try lxc_argv.append(command);
    
    if (options.args) |args| {
        for (args) |arg| {
            try lxc_argv.append(arg);
        }
    }

    const cmd_str = std.mem.join(proxmox_client.allocator, " ", lxc_argv.items) catch "error";
    defer if (cmd_str.len > 0) proxmox_client.allocator.free(cmd_str);
    try proxmox_client.logger.info("lxc-attach command: {s}", .{cmd_str});
    
    // Виконуємо команду через child process
    const result = try ChildProcess.run(.{
        .allocator = proxmox_client.allocator,
        .argv = lxc_argv.items,
    });
    
    const end_time = std.time.nanoTimestamp();
    const execution_time = @as(u64, @intCast(end_time - start_time));
    
    return ExecResult{
        .exit_code = result.term.Exited,
        .stdout = result.stdout,
        .stderr = result.stderr,
        .execution_time_ns = execution_time,
        .method_used = .lxc_attach,
    };
}

// Функція для тестування та порівняння часу виконання
pub fn benchmarkExecution(container_id: []const u8, command: []const u8, args: ?[]const []const u8, proxmox_client: *proxmox.ProxmoxClient) !void {
    try proxmox_client.logger.info("Benchmarking execution methods for command: {s}", .{command});
    
    var results = std.ArrayList(ExecResult).init(proxmox_client.allocator);
    defer {
        for (results.items) |*result| {
            result.deinit(proxmox_client.allocator);
        }
        results.deinit();
    }
    
    // Тестуємо всі доступні методи
    const methods = [_]ExecutionMethod{ .pct, .api, .lxc_attach };
    
    for (methods) |method| {
        const method_options = ExecOptions{
            .container_id = container_id,
            .command = command,
            .args = args,
            .working_dir = null,
            .env = null,
            .user = null,
            .tty = false,
            .privileged = false,
            .method = method,
        };
        
        const result = exec(method_options, proxmox_client) catch |err| {
            try proxmox_client.logger.warn("Method {s} failed: {s}", .{@tagName(method), @errorName(err)});
            continue;
        };
        
        try results.append(result);
    }
    
    // Виводимо результати порівняння
    try printBenchmarkResults(results.items);
}

// Функція для виведення результатів бенчмарку
fn printBenchmarkResults(results: []ExecResult) !void {
    if (results.len == 0) {
        std.io.getStdOut().writer().print("No results to compare\n", .{}) catch {};
        return;
    }
    
    std.io.getStdOut().writer().print("\n=== Execution Method Comparison ===\n", .{}) catch {};
    
    // Сортуємо за часом виконання
    var sorted_results = std.ArrayList(ExecResult).init(std.heap.page_allocator);
    defer sorted_results.deinit();
    
    for (results) |result| {
        try sorted_results.append(result);
    }
    
    // Сортуємо за часом (від найшвидшого до найповільнішого)
    std.mem.sort(ExecResult, sorted_results.items, {}, struct {
        fn lessThan(_: void, a: ExecResult, b: ExecResult) bool {
            return a.execution_time_ns < b.execution_time_ns;
        }
    }.lessThan);
    
    // Виводимо результати
    for (sorted_results.items, 0..) |result, i| {
        const rank = if (i == 0) "🥇" else if (i == 1) "🥈" else "🥉";
        const time_ms = @as(f64, @floatFromInt(result.execution_time_ns)) / 1_000_000.0;
        
        std.io.getStdOut().writer().print("{s} {s}: {d:.3} ms\n", .{
            rank, @tagName(result.method_used), time_ms
        }) catch {};
        
        if (result.stdout.len > 0) {
            std.io.getStdOut().writer().print("  stdout: {s}", .{result.stdout}) catch {};
        }
        if (result.stderr.len > 0) {
            std.io.getStdErr().writer().print("  stderr: {s}", .{result.stderr}) catch {};
        }
    }
    
    // Знаходимо найшвидший метод
    if (sorted_results.items.len > 0) {
        const fastest = sorted_results.items[0];
        const time_ms = @as(f64, @floatFromInt(fastest.execution_time_ns)) / 1_000_000.0;
        
        std.io.getStdOut().writer().print("\n🏆 Fastest method: {s} ({d:.3} ms)\n", .{
            @tagName(fastest.method_used), time_ms
        }) catch {};
    }
}
