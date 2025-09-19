const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;
const fs = std.fs;
const os = std.os;
const logger = std.log.scoped(.proxmox_template);

pub const TemplateInfo = struct {
    name: []const u8,
    size: u64,
    format: []const u8,
    os_type: []const u8,
    arch: []const u8,
    version: []const u8,
    owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, size: u64, format: []const u8, os_type: []const u8, arch: []const u8, version: []const u8, owned: bool) !TemplateInfo {
        if (owned) {
            return TemplateInfo{
                .name = try allocator.dupe(u8, name),
                .size = size,
                .format = try allocator.dupe(u8, format),
                .os_type = try allocator.dupe(u8, os_type),
                .arch = try allocator.dupe(u8, arch),
                .version = try allocator.dupe(u8, version),
                .owned = true,
            };
        } else {
            return TemplateInfo{
                .name = name,
                .size = size,
                .format = format,
                .os_type = os_type,
                .arch = arch,
                .version = version,
                .owned = false,
            };
        }
    }

    pub fn deinit(self: *TemplateInfo, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.name);
            allocator.free(self.format);
            allocator.free(self.os_type);
            allocator.free(self.arch);
            allocator.free(self.version);
        }
    }
};

pub fn createTemplateFromRootfs(client: *Client, rootfs_path: []const u8, template_name: []const u8) !TemplateInfo {
    try client.logger.info("Creating template from rootfs: {s}", .{rootfs_path});
    
    // Створюємо архів з rootfs
    const archive_path = try fmt.allocPrint(client.allocator, "/tmp/{s}.tar.zst", .{template_name});
    defer client.allocator.free(archive_path);
    
    // Використовуємо tar для створення архіву
    const tar_args = [_][]const u8{
        "tar",
        "-czf",
        archive_path,
        "-C",
        rootfs_path,
        ".",
    };
    
    const result = try std.process.Child.run(.{
        .allocator = client.allocator,
        .argv = &tar_args,
    });
    
    defer {
        client.allocator.free(result.stdout);
        client.allocator.free(result.stderr);
    }
    
    if (result.term != .Exited or result.term.Exited != 0) {
        try client.logger.err("Failed to create tar archive: {s}", .{result.stderr});
        return error.TemplateCreationFailed;
    }
    
    // Завантажуємо архів на Proxmox storage
    const upload_path = try fmt.allocPrint(client.allocator, "/nodes/{s}/storage/local/upload", .{client.node});
    defer client.allocator.free(upload_path);
    
    // Читаємо файл архіву
    const file = try fs.cwd().openFile(archive_path, .{});
    defer file.close();
    
    const file_size = try file.getEndPos();
    const file_content = try client.allocator.alloc(u8, file_size);
    defer client.allocator.free(file_content);
    
    _ = try file.readAll(file_content);
    
    // Створюємо multipart form data для завантаження
    var form_data = ArrayList(u8).init(client.allocator);
    defer form_data.deinit();
    
    const boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW";
    const content_type = try fmt.allocPrint(client.allocator, "multipart/form-data; boundary={s}", .{boundary});
    defer client.allocator.free(content_type);
    
    // Додаємо поле filename
    try form_data.writer().print("--{s}\r\n", .{boundary});
    try form_data.writer().print("Content-Disposition: form-data; name=\"filename\"\r\n\r\n", .{});
    try form_data.writer().print("{s}.tar.zst\r\n", .{template_name});
    
    // Додаємо поле content
    try form_data.writer().print("--{s}\r\n", .{boundary});
    try form_data.writer().print("Content-Disposition: form-data; name=\"content\"; filename=\"{s}.tar.zst\"\r\n", .{template_name});
    try form_data.writer().print("Content-Type: application/octet-stream\r\n\r\n", .{});
    try form_data.appendSlice(file_content);
    try form_data.writer().print("\r\n--{s}--\r\n", .{boundary});
    
    // Відправляємо запит
    const response = try client.makeRequest(.POST, upload_path, form_data.items);
    defer client.allocator.free(response);
    
    // Парсимо відповідь
    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();
    
    if (parsed.value.object.get("data")) |data| {
        const size = data.object.get("size").?.integer;
        
        // Визначаємо OS та архітектуру з rootfs
        const os_type = try detectOS(rootfs_path, client.allocator);
        const arch = try detectArchitecture(rootfs_path, client.allocator);
        const version = try detectVersion(rootfs_path, client.allocator);
        
        return TemplateInfo.init(
            client.allocator,
            template_name,
            @intCast(size),
            "tar.zst",
            os_type,
            arch,
            version,
            true,
        );
    }
    
    try client.logger.err("Failed to parse template creation response: {s}", .{response});
    return error.TemplateCreationFailed;
}

fn detectOS(rootfs_path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Перевіряємо /etc/os-release
    const os_release_path = try fmt.allocPrint(allocator, "{s}/etc/os-release", .{rootfs_path});
    defer allocator.free(os_release_path);
    
    const file = fs.cwd().openFile(os_release_path, .{}) catch {
        return allocator.dupe(u8, "unknown");
    };
    defer file.close();
    
    const content = file.readToEndAlloc(allocator, 1024) catch {
        return allocator.dupe(u8, "unknown");
    };
    defer allocator.free(content);
    
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "ID=")) {
            const id = line[3..];
            return allocator.dupe(u8, id);
        }
    }
    
    return allocator.dupe(u8, "unknown");
}

fn detectArchitecture(rootfs_path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Перевіряємо /proc/version
    const version_path = try fmt.allocPrint(allocator, "{s}/proc/version", .{rootfs_path});
    defer allocator.free(version_path);
    
    const file = fs.cwd().openFile(version_path, .{}) catch {
        return allocator.dupe(u8, "unknown");
    };
    defer file.close();
    
    const content = file.readToEndAlloc(allocator, 1024) catch {
        return allocator.dupe(u8, "unknown");
    };
    defer allocator.free(content);
    
    // Простий парсинг архітектури
    if (std.mem.indexOf(u8, content, "x86_64")) |_| {
        return allocator.dupe(u8, "amd64");
    } else if (std.mem.indexOf(u8, content, "aarch64")) |_| {
        return allocator.dupe(u8, "arm64");
    } else if (std.mem.indexOf(u8, content, "arm")) |_| {
        return allocator.dupe(u8, "arm");
    }
    
    return allocator.dupe(u8, "unknown");
}

fn detectVersion(rootfs_path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Перевіряємо /etc/os-release для версії
    const os_release_path = try fmt.allocPrint(allocator, "{s}/etc/os-release", .{rootfs_path});
    defer allocator.free(os_release_path);
    
    const file = fs.cwd().openFile(os_release_path, .{}) catch {
        return allocator.dupe(u8, "unknown");
    };
    defer file.close();
    
    const content = file.readToEndAlloc(allocator, 1024) catch {
        return allocator.dupe(u8, "unknown");
    };
    defer allocator.free(content);
    
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "VERSION_ID=")) {
            const version = line[11..];
            return allocator.dupe(u8, version);
        }
    }
    
    return allocator.dupe(u8, "unknown");
}

pub fn listAvailableTemplates(client: *Client) ![]TemplateInfo {
    const path = "/storage/local/template";
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var templates = ArrayList(TemplateInfo).init(client.allocator);
    errdefer {
        for (templates.items) |*template| {
            template.deinit(client.allocator);
        }
        templates.deinit();
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |template| {
            const volid = template.object.get("volid").?.string;
            const size = template.object.get("size").?.integer;
            const format = template.object.get("format").?.string;
            
            // Витягуємо назву з volid
            const name = if (std.mem.indexOf(u8, volid, "/")) |pos| volid[pos+1..] else volid;
            
            try templates.append(try TemplateInfo.init(
                client.allocator,
                name,
                @intCast(size),
                format,
                "unknown", // OS визначається під час створення
                "unknown", // Arch визначається під час створення
                "unknown", // Version визначається під час створення
                false, // Не створюємо копії, оскільки рядки не є власними
            ));
        }
    }

    return try templates.toOwnedSlice();
}
