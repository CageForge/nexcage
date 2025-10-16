const std = @import("std");
const core = @import("core");
const types = @import("types.zig");

/// Result of running a command
const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

/// Proxmox LXC backend driver
pub const ProxmoxLxcDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: core.types.ProxmoxLxcBackendConfig,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator, config: core.types.ProxmoxLxcBackendConfig) !*Self {
        const driver = try allocator.alloc(Self, 1);
        driver[0] = Self{
            .allocator = allocator,
            .config = config,
        };

        return &driver[0];
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    /// Create LXC container using pct command
    pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating Proxmox LXC container: {s}", .{config.name});
        }
        
        // Generate VMID from name (Proxmox requires numeric vmid)
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(config.name);
        const vmid_num: u32 = @truncate(hasher.final());
        const vmid_calc: u32 = (vmid_num % 900000) + 100; // 100..900099
        const vmid = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid_calc});
        defer self.allocator.free(vmid);

        // Find available template
        const template = try self.findAvailableTemplate();
        defer self.allocator.free(template);

        // Use pct create command
        const args = [_][]const u8{
            "pct",
            "create",
            vmid,
            template,
            "--hostname", config.name,
            "--memory", "512",
            "--cores", "1",
            "--net0", "name=eth0,bridge=vmbr0,ip=dhcp",
        };

        if (self.logger) |log| {
            try log.debug("Proxmox LXC create: Creating container with pct create", .{});
        }

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        // Debug output
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("DEBUG: pct create result - exit_code: ");
        try stdout.writeAll(std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{result.exit_code}) catch "unknown");
        try stdout.writeAll(", stdout: ");
        try stdout.writeAll(result.stdout);
        try stdout.writeAll(", stderr: ");
        try stdout.writeAll(result.stderr);
        try stdout.writeAll("\n");
        
        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to create Proxmox LXC via pct: {s}", .{result.stderr});
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| try log.info("Proxmox LXC container created via pct: {s} (vmid {s})", .{ config.name, vmid });
    }

    /// Start LXC container using pct command
    pub fn start(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Starting Proxmox LXC container: {s}", .{container_id});
        }

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct start command
        const args = [_][]const u8{ "pct", "start", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to start Proxmox LXC container {s}: {s}", .{ container_id, result.stderr });
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            try log.info("Proxmox LXC container started successfully: {s}", .{container_id});
        }
    }

    /// Stop LXC container using pct command
    pub fn stop(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Stopping Proxmox LXC container: {s}", .{container_id});
        }

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct stop command
        const args = [_][]const u8{ "pct", "stop", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to stop Proxmox LXC container {s}: {s}", .{ container_id, result.stderr });
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            try log.info("Proxmox LXC container stopped successfully: {s}", .{container_id});
        }
    }

    /// Delete LXC container using pct command
    pub fn delete(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Deleting Proxmox LXC container: {s}", .{container_id});
        }

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct destroy command
        const args = [_][]const u8{ "pct", "destroy", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to delete Proxmox LXC container {s}: {s}", .{ container_id, result.stderr });
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            try log.info("Proxmox LXC container deleted successfully: {s}", .{container_id});
        }
    }

    /// Find an available template for container creation
    fn findAvailableTemplate(self: *Self) ![]const u8 {
        // First, try to list available templates
        const list_args = [_][]const u8{ "pveam", "available" };
        const list_result = self.runCommand(&list_args) catch |err| {
            if (self.logger) |log| try log.warn("Failed to list available templates: {}", .{err});
            return self.getDefaultTemplate();
        };
        defer self.allocator.free(list_result.stdout);
        defer self.allocator.free(list_result.stderr);

        if (list_result.exit_code != 0) {
            if (self.logger) |log| try log.warn("pveam available failed: {s}", .{list_result.stderr});
            return self.getDefaultTemplate();
        }

        // Parse available templates and find a suitable one
        var lines = std.mem.splitScalar(u8, list_result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "ubuntu") != null and std.mem.indexOf(u8, line, "standard") != null) {
                // Extract template name from line
                var fields = std.mem.splitScalar(u8, line, ' ');
                if (fields.next()) |template_name| {
                    const full_template = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}", .{template_name});
                    if (self.logger) |log| try log.info("Found available template: {s}", .{full_template});
                    return full_template;
                }
            }
        }

        // Fallback to default template
        if (self.logger) |log| try log.warn("No suitable template found, using default", .{});
        return self.getDefaultTemplate();
    }

    /// Get default template (fallback)
    fn getDefaultTemplate(self: *Self) ![]const u8 {
        // Try common template names
        const templates = [_][]const u8{
            "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.gz",
            "local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz",
            "local:vztmpl/debian-11-standard_11.7-1_amd64.tar.gz",
            "local:vztmpl/debian-12-standard_12.2-1_amd64.tar.gz",
        };

        for (templates) |template| {
            // Check if template exists
            const check_args = [_][]const u8{ "pveam", "list", "local:vztmpl" };
            const check_result = self.runCommand(&check_args) catch continue;
            defer self.allocator.free(check_result.stdout);
            defer self.allocator.free(check_result.stderr);

            if (check_result.exit_code == 0 and std.mem.indexOf(u8, check_result.stdout, template) != null) {
                if (self.logger) |log| try log.info("Using default template: {s}", .{template});
                return self.allocator.dupe(u8, template);
            }
        }

        // Last resort - return a basic template
        if (self.logger) |log| try log.warn("No templates found, using basic template", .{});
        return self.allocator.dupe(u8, "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.gz");
    }

    /// Get VMID by container name
    fn getVmidByName(self: *Self, name: []const u8) ![]u8 {
        const pct_args = [_][]const u8{ "pct", "list" };
        const pct_res = try self.runCommand(&pct_args);
        defer self.allocator.free(pct_res.stdout);
        defer self.allocator.free(pct_res.stderr);

        if (pct_res.exit_code != 0) {
            return core.Error.NotFound;
        }

        // Parse pct list output to find VMID by name
        var lines = std.mem.splitScalar(u8, pct_res.stdout, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (first) {
                first = false;
                continue; // Skip header
            }
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            // Split by whitespace columns
            var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
            const vmid_str = it.next() orelse continue;
            const name_str = it.next() orelse vmid_str;

            if (std.mem.eql(u8, name_str, name)) {
                return self.allocator.dupe(u8, vmid_str);
            }
        }

        return core.Error.NotFound;
    }

    /// Run a command and return result
    fn runCommand(self: *Self, args: []const []const u8) !CommandResult {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args,
            .max_output_bytes = 1024 * 1024, // 1MB
        }) catch |err| {
            if (self.logger) |log| try log.err("Failed to run command: {}", .{err});
            return core.Error.OperationFailed;
        };

        const exit_code = switch (result.term) {
            .Exited => |code| @as(u8, @intCast(@abs(code))),
            else => 1,
        };

        return CommandResult{
            .stdout = result.stdout,
            .stderr = result.stderr,
            .exit_code = exit_code,
        };
    }

    /// Map pct command errors to core errors
    fn mapPctError(self: *Self, exit_code: u8, stderr: []const u8) core.Error {
        _ = self;
        _ = exit_code;
        const s = stderr;
        if (std.mem.indexOf(u8, s, "No such file or directory") != null or
            std.mem.indexOf(u8, s, "does not exist") != null or
            std.mem.indexOf(u8, s, "not found") != null)
        {
            return core.Error.NotFound;
        }
        if (std.mem.indexOf(u8, s, "Permission denied") != null) {
            return core.Error.PermissionDenied;
        }
        if (std.mem.indexOf(u8, s, "already exists") != null) {
            return core.Error.OperationFailed;
        }
        if (std.mem.indexOf(u8, s, "timeout") != null) {
            return core.Error.Timeout;
        }
        return core.Error.OperationFailed;
    }

    /// List LXC containers using pct command
    pub fn list(self: *Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        if (self.logger) |log| {
            try log.info("Listing LXC containers via pct command", .{});
        }

        const pct_args = [_][]const u8{ "pct", "list" };
        const pct_res = try self.runCommand(&pct_args);
        defer self.allocator.free(pct_res.stdout);
        defer self.allocator.free(pct_res.stderr);

        if (pct_res.exit_code != 0) {
            return core.Error.OperationFailed;
        }

        // Parse pct list output
        var lines = std.mem.splitScalar(u8, pct_res.stdout, '\n');
        var containers = std.ArrayListUnmanaged(core.ContainerInfo){};
        defer {
            for (containers.items) |*c| {
                c.deinit();
            }
            containers.deinit(allocator);
        }

        var first = true;
        while (lines.next()) |line| {
            if (first) {
                first = false;
                continue; // Skip header
            }
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            // Split by whitespace columns
            var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
            const vmid_str = it.next() orelse continue;
            const status_str = it.next() orelse "unknown";
            const name_str = it.next() orelse "unknown";

            const container = core.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, vmid_str),
                .name = try allocator.dupe(u8, name_str),
                .status = try allocator.dupe(u8, status_str),
                .backend_type = try allocator.dupe(u8, "proxmox-lxc"),
                .runtime = try allocator.dupe(u8, "pct"),
            };

            try containers.append(allocator, container);
        }

        return containers.toOwnedSlice(allocator);
    }
};
