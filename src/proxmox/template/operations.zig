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
    const archive_path = try createTemplateArchive(client.allocator, rootfs_path, template_name);
    defer client.allocator.free(archive_path);
    
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
    
    // Створюємо multipart form data для завантаження (Proxmox expects fields: content=vztmpl, filename=<name>)
    const boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW";
    const mf = try buildMultipartForm(client.allocator, boundary, template_name, file_content);
    defer client.allocator.free(mf.body);
    defer client.allocator.free(mf.content_type);
    
    // Відправляємо запит (з fallback через curl у разі ConnectionResetByPeer)
    const response = client.makeRequestWithContentType(.POST, upload_path, mf.body, mf.content_type) catch |err| blk: {
        try client.logger.warn("Primary HTTP upload failed: {s}. Falling back to curl", .{@errorName(err)});

        const host = client.hosts[client.current_host_index];
        const url = try fmt.allocPrint(client.allocator, "https://{s}:{d}/api2/json{s}", .{ host, client.port, upload_path });
        defer client.allocator.free(url);

        const auth = try fmt.allocPrint(client.allocator, "PVEAPIToken={s}", .{client.token});
        defer client.allocator.free(auth);

        const filename_arg = try fmt.allocPrint(client.allocator, "filename={s}.tar.zst", .{template_name});
        defer client.allocator.free(filename_arg);

        // Використовуємо абсолютний шлях до архіву
        const content_arg = try fmt.allocPrint(client.allocator, "content=@{s};type=application/octet-stream", .{archive_path});
        defer client.allocator.free(content_arg);

        const auth_header_arg = try fmt.allocPrint(client.allocator, "Authorization: PVEAPIToken={s}", .{client.token});
        defer client.allocator.free(auth_header_arg);

        const curl_args = [_][]const u8{
            "curl", "-sS", "-k", "-X", "POST",
            "-H", "Accept: application/json",
            "-H", "Connection: close",
            "-H", "User-Agent: proxmox-lxcri/0.3",
            "-H", auth_header_arg,
            "-F", filename_arg,
            "-F", content_arg,
            url,
        };

        const curl_res = try std.process.Child.run(.{ .allocator = client.allocator, .argv = &curl_args });
        defer {
            client.allocator.free(curl_res.stdout);
            client.allocator.free(curl_res.stderr);
        }
        if (curl_res.term != .Exited or curl_res.term.Exited != 0) {
            try client.logger.err("curl upload failed: {s}", .{curl_res.stderr});
            return error.TemplateCreationFailed;
        }
        if (curl_res.stdout.len == 0) {
            // Fallback: перевіряємо, чи з'явився шаблон у списку
            const templates = try listAvailableTemplates(client);
            defer {
                for (templates) |*t| t.deinit(client.allocator);
                client.allocator.free(templates);
            }
            const expected = try fmt.allocPrint(client.allocator, "{s}.tar.zst", .{template_name});
            defer client.allocator.free(expected);
            for (templates) |*t| {
                if (std.mem.eql(u8, t.name, expected)) {
                    // Повертаємо фіктивну JSON-відповідь, щоб нижче створити TemplateInfo стандартним шляхом
                    const fake = try fmt.allocPrint(client.allocator, "{s}", .{"{\"data\":{\"size\":0}}"});
                    break :blk fake;
                }
            }
            try client.logger.err("Upload via curl returned empty response and template not found", .{});
            return error.TemplateCreationFailed;
        }
        break :blk try client.allocator.dupe(u8, curl_res.stdout);
    };
    defer client.allocator.free(response);
    
    // Парсимо відповідь
    var parsed = json.parseFromSlice(json.Value, client.allocator, response, .{}) catch |perr| {
        // Якщо парсинг JSON не вдався (наприклад, порожня відповідь), спробуємо знайти шаблон у списку
        try client.logger.warn("Template upload response parse failed: {s}. Trying list-based verification", .{@errorName(perr)});
        const templates = try listAvailableTemplates(client);
        defer {
            for (templates) |*t| t.deinit(client.allocator);
            client.allocator.free(templates);
        }
        const expected = try fmt.allocPrint(client.allocator, "{s}.tar.zst", .{template_name});
        defer client.allocator.free(expected);
        for (templates) |*t| {
            if (std.mem.eql(u8, t.name, expected)) {
                return TemplateInfo.init(
                    client.allocator,
                    expected,
                    t.size,
                    t.format,
                    t.os_type,
                    t.arch,
                    t.version,
                    true,
                );
            }
        }
        return error.TemplateCreationFailed;
    };
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
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/storage/{s}/content?content=vztmpl", .{ client.node, "local" });
    defer client.allocator.free(path);
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
        for (data.array.items) |item| {
            const volid = item.object.get("volid").?.string;
            const size = item.object.get("size").?.integer;
            const format = if (item.object.get("format")) |f| f.string else "unknown";

            const slash = std.mem.lastIndexOf(u8, volid, "/");
            const name = if (slash) |pos| volid[pos+1..] else volid;

            try templates.append(try TemplateInfo.init(
                client.allocator,
                name,
                @intCast(size),
                format,
                "unknown",
                "unknown",
                "unknown",
                false,
            ));
        }
    }

    return try templates.toOwnedSlice();
}

// Допоміжні хелпери для тестування
pub fn createTemplateArchive(allocator: std.mem.Allocator, rootfs_path: []const u8, template_name: []const u8) ![]const u8 {
    const archive_path = try fmt.allocPrint(allocator, "/tmp/{s}.tar.zst", .{template_name});
    errdefer allocator.free(archive_path);
    const tar_args = [_][]const u8{
        "tar", "--zstd", "-cf", archive_path, "-C", rootfs_path, ".",
    };
    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = &tar_args });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    if (result.term != .Exited or result.term.Exited != 0) return error.TemplateCreationFailed;
    return archive_path;
}

pub fn buildMultipartForm(allocator: std.mem.Allocator, boundary: []const u8, template_name: []const u8, file_content: []const u8) !struct { body: []u8, content_type: []u8 } {
    var form_data = ArrayList(u8).init(allocator);
    errdefer form_data.deinit();
    try form_data.writer().print("--{s}\r\n", .{boundary});
    try form_data.writer().print("Content-Disposition: form-data; name=\"filename\"\r\n\r\n", .{});
    try form_data.writer().print("{s}.tar.zst\r\n", .{template_name});
    try form_data.writer().print("--{s}\r\n", .{boundary});
    try form_data.writer().print("Content-Disposition: form-data; name=\"content\"; filename=\"{s}.tar.zst\"\r\n", .{template_name});
    try form_data.writer().print("Content-Type: application/octet-stream\r\n\r\n", .{});
    try form_data.appendSlice(file_content);
    try form_data.writer().print("\r\n--{s}--\r\n", .{boundary});
    const content_type = try fmt.allocPrint(allocator, "multipart/form-data; boundary={s}", .{boundary});
    return .{ .body = try form_data.toOwnedSlice(), .content_type = content_type };
}

pub fn parseTemplatesFromJson(allocator: std.mem.Allocator, response: []const u8) ![]TemplateInfo {
    const templates = ArrayList(TemplateInfo).init(allocator);
    errdefer {
        for (templates.items) |*t| t.deinit(allocator);
        templates.deinit();
    }
    var parsed = try json.parseFromSlice(json.Value, allocator, response, .{});
    defer parsed.deinit();
    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |item| {
            const volid = item.object.get("volid").?.string;
            const size = item.object.get("size").?.integer;
            const format = if (item.object.get("format")) |f| f.string else "unknown";
            const slash = std.mem.lastIndexOf(u8, volid, "/");
            const name = if (slash) |pos| volid[pos+1..] else volid;
            try templates.append(try TemplateInfo.init(
                allocator,
                name,
                @intCast(size),
                format,
                "unknown",
                "unknown",
                "unknown",
                false,
            ));
        }
    }
    return try templates.toOwnedSlice();
}

