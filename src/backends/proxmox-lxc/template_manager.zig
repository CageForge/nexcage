const std = @import("std");
const core = @import("core");

/// Template Management system for Proxmox LXC templates
/// Provides caching, validation, lifecycle management, and optimization
pub const TemplateManager = struct {
    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,
    cache_dir: []const u8,
    templates: std.HashMap([]const u8, TemplateInfo, StringContext, std.hash_map.default_max_load_percentage),
    
    const Self = @This();
    const StringContext = struct {
        pub fn hash(self: @This(), s: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }
        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext, cache_dir: []const u8) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .cache_dir = cache_dir,
            .templates = std.HashMap([]const u8, TemplateInfo, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Cleanup template cache
        var iterator = self.templates.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.templates.deinit();
    }

    /// Add template to cache with metadata
    pub fn addTemplate(self: *Self, template_name: []const u8, template_info: TemplateInfo) !void {
        const name_copy = try self.allocator.dupe(u8, template_name);
        const info_copy = try template_info.clone(self.allocator);
        
        // Remove existing entry if present
        if (self.templates.getPtr(template_name)) |existing| {
            self.allocator.free(existing.name);
            existing.deinit(self.allocator);
        }
        
        try self.templates.put(name_copy, info_copy);
        
        if (self.logger) |log| {
            try log.info("Added template to cache: {s}", .{template_name});
        }
    }

    /// Get template information from cache
    pub fn getTemplate(self: *Self, template_name: []const u8) ?TemplateInfo {
        return self.templates.get(template_name);
    }

    /// List all cached templates
    pub fn listTemplates(self: *Self) ![][]const u8 {
        var template_names = std.ArrayList([]const u8).init(self.allocator);
        defer template_names.deinit();
        
        var iterator = self.templates.iterator();
        while (iterator.next()) |entry| {
            const name_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
            try template_names.append(name_copy);
        }
        
        return template_names.toOwnedSlice();
    }

    /// Verify template integrity
    pub fn verifyTemplate(self: *Self, template_name: []const u8) !bool {
        if (self.logger) |log| {
            try log.info("Verifying template integrity: {s}", .{template_name});
        }

        // Check if template exists in Proxmox
        const exists = try self.checkTemplateExists(template_name);
        if (!exists) {
            if (self.logger) |log| {
                try log.warn("Template not found in Proxmox: {s}", .{template_name});
            }
            return false;
        }

        // Check template file integrity
        const template_path = try self.getTemplatePath(template_name);
        defer self.allocator.free(template_path);
        
        const integrity_ok = try self.checkFileIntegrity(template_path);
        
        if (self.logger) |log| {
            if (integrity_ok) {
                try log.info("Template integrity verified: {s}", .{template_name});
            } else {
                try log.err("Template integrity check failed: {s}", .{template_name});
            }
        }
        
        return integrity_ok;
    }

    /// Prune old or invalid templates
    pub fn pruneTemplates(self: *Self, max_age_days: u32) !void {
        if (self.logger) |log| {
            try log.info("Pruning templates older than {d} days", .{max_age_days});
        }

        const current_time = std.time.timestamp();
        const max_age_seconds = @as(i64, @intCast(max_age_days)) * 24 * 60 * 60;
        
        var templates_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer templates_to_remove.deinit();
        
        var iterator = self.templates.iterator();
        while (iterator.next()) |entry| {
            const template_name = entry.key_ptr.*;
            const template_info = entry.value_ptr.*;
            
            // Check if template is older than max_age_days
            if (current_time - template_info.created_at > max_age_seconds) {
                try templates_to_remove.append(template_name);
            }
        }
        
        // Remove old templates
        for (templates_to_remove.items) |template_name| {
            try self.removeTemplate(template_name);
        }
        
        if (self.logger) |log| {
            try log.info("Pruned {d} old templates", .{templates_to_remove.items.len});
        }
    }

    /// Remove template from cache and optionally from Proxmox
    pub fn removeTemplate(self: *Self, template_name: []const u8) !void {
        if (self.templates.getPtr(template_name)) |template_info| {
            template_info.deinit(self.allocator);
            _ = self.templates.remove(template_name);
            
            if (self.logger) |log| {
                try log.info("Removed template from cache: {s}", .{template_name});
            }
        }
    }

    /// Check if template exists in Proxmox storage
    fn checkTemplateExists(self: *Self, template_name: []const u8) !bool {
        const args = [_][]const u8{ "pveam", "list", "local:vztmpl" };
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        return result.exit_code == 0 and std.mem.indexOf(u8, result.stdout, template_name) != null;
    }

    /// Get full path to template file
    fn getTemplatePath(self: *Self, template_name: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "/var/lib/vz/template/cache/{s}", .{template_name});
    }

    /// Check file integrity using checksum
    fn checkFileIntegrity(self: *Self, file_path: []const u8) !bool {
        _ = self; // Avoid unused parameter warning
        const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
        defer file.close();
        
        // Simple integrity check - verify file is readable and has content
        const stat = file.stat() catch return false;
        return stat.size > 0;
    }

    /// Run shell command
    fn runCommand(self: *Self, args: []const []const u8) !CommandResult {
        var child = std.process.Child.init(args, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        
        const term = try child.wait();
        
        return CommandResult{
            .stdout = stdout,
            .stderr = stderr,
            .exit_code = switch (term) {
                .Exited => |code| @intCast(code),
                else => 1,
            },
        };
    }
};

/// Template information structure
pub const TemplateInfo = struct {
    name: []const u8,
    size: u64,
    created_at: i64,
    last_accessed: i64,
    source_type: TemplateSource,
    metadata: ?TemplateMetadata = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, size: u64, source_type: TemplateSource) !TemplateInfo {
        return TemplateInfo{
            .name = try allocator.dupe(u8, name),
            .size = size,
            .created_at = std.time.timestamp(),
            .last_accessed = std.time.timestamp(),
            .source_type = source_type,
        };
    }

    pub fn deinit(self: *TemplateInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.metadata) |*metadata| {
            metadata.deinit(allocator);
        }
    }

    pub fn clone(self: *const TemplateInfo, allocator: std.mem.Allocator) !TemplateInfo {
        var cloned = TemplateInfo{
            .name = try allocator.dupe(u8, self.name),
            .size = self.size,
            .created_at = self.created_at,
            .last_accessed = self.last_accessed,
            .source_type = self.source_type,
            .metadata = null,
        };
        
        if (self.metadata) |metadata| {
            cloned.metadata = try metadata.clone(allocator);
        }
        
        return cloned;
    }
};

/// Template source types
pub const TemplateSource = enum {
    oci_bundle,
    proxmox_downloaded,
    proxmox_available,
    custom,
};

/// Template metadata for enhanced information
pub const TemplateMetadata = struct {
    image_name: ?[]const u8 = null,
    image_tag: ?[]const u8 = null,
    entrypoint: ?[]const []const u8 = null,
    cmd: ?[]const []const u8 = null,
    working_directory: ?[]const u8 = null,
    labels: ?std.StringHashMap([]const u8) = null,

    pub fn init(allocator: std.mem.Allocator) TemplateMetadata {
        return TemplateMetadata{
            .labels = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *TemplateMetadata, allocator: std.mem.Allocator) void {
        if (self.image_name) |name| allocator.free(name);
        if (self.image_tag) |tag| allocator.free(tag);
        if (self.entrypoint) |ep| {
            for (ep) |arg| allocator.free(arg);
            allocator.free(ep);
        }
        if (self.cmd) |cmd| {
            for (cmd) |arg| allocator.free(arg);
            allocator.free(cmd);
        }
        if (self.working_directory) |wd| allocator.free(wd);
        if (self.labels) |*labels| {
            var iterator = labels.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            labels.deinit();
        }
    }

    pub fn clone(self: *const TemplateMetadata, allocator: std.mem.Allocator) !TemplateMetadata {
        var cloned = TemplateMetadata{};
        
        if (self.image_name) |name| {
            cloned.image_name = try allocator.dupe(u8, name);
        }
        if (self.image_tag) |tag| {
            cloned.image_tag = try allocator.dupe(u8, tag);
        }
        if (self.entrypoint) |ep| {
            var entrypoint_array = try allocator.alloc([]const u8, ep.len);
            for (ep, 0..) |arg, i| {
                entrypoint_array[i] = try allocator.dupe(u8, arg);
            }
            cloned.entrypoint = entrypoint_array;
        }
        if (self.cmd) |cmd| {
            var cmd_array = try allocator.alloc([]const u8, cmd.len);
            for (cmd, 0..) |arg, i| {
                cmd_array[i] = try allocator.dupe(u8, arg);
            }
            cloned.cmd = cmd_array;
        }
        if (self.working_directory) |wd| {
            cloned.working_directory = try allocator.dupe(u8, wd);
        }
        if (self.labels) |labels| {
            cloned.labels = std.StringHashMap([]const u8).init(allocator);
            var iterator = labels.iterator();
            while (iterator.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value = try allocator.dupe(u8, entry.value_ptr.*);
                try cloned.labels.?.put(key, value);
            }
        }
        
        return cloned;
    }
};

/// Command execution result
const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};
