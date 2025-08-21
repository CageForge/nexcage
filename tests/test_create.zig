const std = @import("std");
const testing = std.testing;
const logger_mod = @import("logger");
const types = @import("types");
const oci_commands = @import("oci");
const image = @import("image");
const zfs = @import("zfs");
const lxc = @import("lxc");
const ProxmoxClient = @import("proxmox").ProxmoxClient;
const cli_args = @import("cli_args");

test "create command validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Тест без bundle
    {
        const args = &[_][]const u8{
            "create",
            "test-container",
        };
        try testing.expectError(error.InvalidArguments, executeCreate(allocator, args, undefined, undefined, undefined));
    }

    // Тест без container-id
    {
        const args = &[_][]const u8{
            "create",
            "--bundle",
            "/path/to/bundle",
        };
        try testing.expectError(error.InvalidArguments, executeCreate(allocator, args, undefined, undefined, undefined));
    }

    // Тест з невалідним bundle
    {
        const args = &[_][]const u8{
            "create",
            "--bundle",
            "/nonexistent/path",
            "test-container",
        };
        try testing.expectError(error.FileNotFound, executeCreate(allocator, args, undefined, undefined, undefined));
    }
}

test "create command success" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Створюємо тимчасовий bundle для тесту
    const temp_dir = try std.fs.cwd().makeOpenPath("test_bundle", .{});
    defer (@constCast(temp_dir)).close();
    defer std.fs.cwd().deleteTree("test_bundle") catch {};

    // Створюємо config.json
    const config = try allocator.alloc(u8, 1024);
    defer allocator.free(config);
    const config_content = 
        \\{
        \\  "ociVersion": "1.0.2-dev",
        \\  "process": {
        \\    "terminal": true,
        \\    "user": {
        \\      "uid": 0,
        \\      "gid": 0
        \\    },
        \\    "args": ["sh"],
        \\    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
        \\    "cwd": "/"
        \\  },
        \\  "root": {
        \\    "path": "rootfs",
        \\    "readonly": true
        \\  },
        \\  "hostname": "test-container",
        \\  "mounts": [],
        \\  "linux": {
        \\    "namespaces": [
        \\      {"type": "pid"},
        \\      {"type": "network"},
        \\      {"type": "ipc"},
        \\      {"type": "uts"},
        \\      {"type": "mount"}
        \\    ]
        \\  }
        \\}
    ;
    try temp_dir.writeFile("config.json", config_content);

    // Створюємо rootfs директорію
    try temp_dir.makeDir("rootfs");

    // Ініціалізуємо необхідні менеджери
    var logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .debug, "test");
    defer logger.deinit();

    var image_manager = try image.ImageManager.init(allocator, "/var/lib/proxmox-lxcri/images", &logger);
    defer image_manager.deinit();

    var zfs_manager = try zfs.ZFSManager.init(allocator, &logger);
    defer zfs_manager.deinit();

    var lxc_manager = try lxc.LXCManager.init(allocator, &logger);
    defer lxc_manager.deinit();

    // Тестуємо створення контейнера
    const args = &[_][]const u8{
        "create",
        "--bundle",
        "test_bundle",
        "test-container",
    };

    try executeCreate(allocator, args, &image_manager, &zfs_manager, &lxc_manager);
}

fn executeCreate(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    image_manager: *image.ImageManager,
    zfs_manager: *zfs.ZFSManager,
    lxc_manager: *lxc.LXCManager,
) !void {
    _ = allocator;
    _ = image_manager;
    _ = zfs_manager;
    _ = lxc_manager;
    // args використовується у функції, тому не ігноруємо

    if (args.len < 4) {
        try std.io.getStdErr().writer().writeAll("Error: create requires --bundle and container-id arguments\n");
        return error.InvalidArguments;
    }

    var bundle_path: ?[]const u8 = null;
    var container_id: ?[]const u8 = null;
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --bundle requires a path argument\n");
                return error.InvalidArguments;
            }
            bundle_path = args[i + 1];
            i += 1;
        } else {
            container_id = arg;
        }
    }

    if (bundle_path == null or container_id == null) {
        try std.io.getStdErr().writer().writeAll("Error: both --bundle and container-id are required\n");
        return error.InvalidArguments;
    }

    // Перевіряємо існування bundle
    const bundle_dir = std.fs.cwd().openDir(bundle_path.?, .{}) catch |err| {
        if (err == error.FileNotFound) {
            try std.io.getStdErr().writer().print("Error: bundle directory '{s}' not found\n", .{bundle_path.?});
            return error.FileNotFound;
        }
        return err;
    };
    defer bundle_dir.close();

    // Перевіряємо наявність config.json
    bundle_dir.access("config.json", .{}) catch |err| {
        if (err == error.FileNotFound) {
            try std.io.getStdErr().writer().writeAll("Error: config.json not found in bundle\n");
            return error.FileNotFound;
        }
        return err;
    };

    // TODO: Додати реальну імплементацію створення контейнера
    // Наразі просто повертаємо успіх
}

test "parseArgs parses create command with all options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Імітуємо CLI-аргументи
    const argv = &[_][]const u8{
        "proxmox-lxcri", // program name
        "create",
        "--bundle", "/tmp/bundle",
        "--log", "/tmp/log.txt",
        "--log-format", "json",
        "--root", "/tmp/root",
        "--pid-file", "/tmp/pid",
        "--console-socket", "/tmp/socket",
        "--systemd-cgroup",
        "--debug",
        "test-container"
    };

    const result = try cli_args.parseArgsFromArray(allocator, argv);
    try testing.expect(result.command == cli_args.Command.create);
    try testing.expectEqualStrings(result.options.bundle.?, "/tmp/bundle");
    try testing.expectEqualStrings(result.options.log.?, "/tmp/log.txt");
    try testing.expectEqualStrings(result.options.log_format.?, "json");
    try testing.expectEqualStrings(result.options.root.?, "/tmp/root");
    try testing.expectEqualStrings(result.options.pid_file.?, "/tmp/pid");
    try testing.expectEqualStrings(result.options.console_socket.?, "/tmp/socket");
    try testing.expect(result.options.systemd_cgroup);
    try testing.expect(result.options.debug);
    try testing.expectEqualStrings(result.container_id.?, "test-container");
} 