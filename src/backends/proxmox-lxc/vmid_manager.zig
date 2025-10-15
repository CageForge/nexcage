const std = @import("std");
const core = @import("core");

/// VMID Manager for Proxmox LXC containers
/// Handles VMID generation, collision detection, and mapping storage
pub const VmidManager = struct {
    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,
    state_dir: []const u8,
    mapping_file: []const u8,

    const VMID_START = 100;
    const VMID_END = 999999;

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext, state_dir: []const u8) !VmidManager {
        const mapping_file = try std.fs.path.join(allocator, &[_][]const u8{ state_dir, "mapping.json" });
        
        // Ensure state directory exists
        try std.fs.cwd().makePath(state_dir);

        return VmidManager{
            .allocator = allocator,
            .logger = logger,
            .state_dir = state_dir,
            .mapping_file = mapping_file,
        };
    }

    pub fn deinit(self: *VmidManager) void {
        self.allocator.free(self.mapping_file);
    }

    /// Generate VMID from container ID using hash-based method
    fn generateVmidFromHash(container_id: []const u8) u32 {
        var hash = std.hash.Wyhash.init(0);
        hash.update(container_id);
        const hash_value = hash.final();
        
        // Map hash to VMID range
        const range = VMID_END - VMID_START + 1;
        return @as(u32, @intCast(VMID_START + (hash_value % range)));
    }

    /// Check if VMID exists in Proxmox using pct list
    fn vmidExistsInProxmox(self: *VmidManager, vmid: u32) !bool {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "pct", "list" },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            if (self.logger) |log| {
                try log.warn("Failed to list containers: {s}", .{result.stderr});
            }
            return false;
        }

        const vmid_str = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid});
        defer self.allocator.free(vmid_str);

        return std.mem.indexOf(u8, result.stdout, vmid_str) != null;
    }

    /// Load existing mappings from file
    fn loadMappings(self: *VmidManager) !std.StringHashMap(MappingEntry) {
        var mappings = std.StringHashMap(MappingEntry).init(self.allocator);

        const file = std.fs.cwd().openFile(self.mapping_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                if (self.logger) |log| {
                    try log.debug("Mapping file not found, starting with empty mappings", .{});
                }
                return mappings;
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        if (parsed.value != .object) {
            return mappings;
        }

        var it = parsed.value.object.iterator();
        while (it.next()) |entry| {
            const container_id = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            if (value != .object) continue;

            const vmid = if (value.object.get("vmid")) |v| 
                if (v == .integer) @as(u32, @intCast(v.integer)) else continue
            else continue;

            const created_at = if (value.object.get("created_at")) |v|
                if (v == .integer) v.integer else 0
            else 0;

            const bundle_path = if (value.object.get("bundle_path")) |v|
                if (v == .string) try self.allocator.dupe(u8, v.string) else continue
            else continue;

            try mappings.put(try self.allocator.dupe(u8, container_id), .{
                .container_id = try self.allocator.dupe(u8, container_id),
                .vmid = vmid,
                .created_at = created_at,
                .bundle_path = bundle_path,
            });
        }

        return mappings;
    }

    /// Save mappings to file
    fn saveMappings(self: *VmidManager, mappings: *std.StringHashMap(MappingEntry)) !void {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();

        var it = mappings.iterator();
        while (it.next()) |entry| {
            var entry_obj = std.json.ObjectMap.init(self.allocator);
            
            try entry_obj.put("vmid", .{ .integer = entry.value_ptr.vmid });
            try entry_obj.put("created_at", .{ .integer = entry.value_ptr.created_at });
            try entry_obj.put("bundle_path", .{ .string = entry.value_ptr.bundle_path });

            try json_obj.put(entry.key_ptr.*, .{ .object = entry_obj });
        }

        // Simple JSON serialization
        var json_buffer = std.ArrayListUnmanaged(u8){};
        defer json_buffer.deinit(self.allocator);
        
        try json_buffer.append(self.allocator, '{');
        var first = true;
        var json_it = json_obj.iterator();
        while (json_it.next()) |entry| {
            if (!first) try json_buffer.append(self.allocator, ',');
            first = false;
            
            try json_buffer.append(self.allocator, '\n');
            try json_buffer.append(self.allocator, ' ');
            try json_buffer.append(self.allocator, ' ');
            try json_buffer.append(self.allocator, '"');
            try json_buffer.appendSlice(self.allocator, entry.key_ptr.*);
            try json_buffer.append(self.allocator, '"');
            try json_buffer.append(self.allocator, ':');
            try json_buffer.append(self.allocator, ' ');
            
            const value = entry.value_ptr.*;
            if (value == .object) {
                const obj = value.object;
                try json_buffer.append(self.allocator, '{');
                var first_field = true;
                var field_it = obj.iterator();
                while (field_it.next()) |field| {
                    if (!first_field) try json_buffer.append(self.allocator, ',');
                    first_field = false;
                    
                    try json_buffer.append(self.allocator, '\n');
                    try json_buffer.append(self.allocator, ' ');
                    try json_buffer.append(self.allocator, ' ');
                    try json_buffer.append(self.allocator, ' ');
                    try json_buffer.append(self.allocator, ' ');
                    try json_buffer.append(self.allocator, '"');
                    try json_buffer.appendSlice(self.allocator, field.key_ptr.*);
                    try json_buffer.append(self.allocator, '"');
                    try json_buffer.append(self.allocator, ':');
                    try json_buffer.append(self.allocator, ' ');
                    
                    const field_value = field.value_ptr.*;
                    if (field_value == .string) {
                        try json_buffer.append(self.allocator, '"');
                        try json_buffer.appendSlice(self.allocator, field_value.string);
                        try json_buffer.append(self.allocator, '"');
                    } else if (field_value == .integer) {
                        const int_str = try std.fmt.allocPrint(self.allocator, "{d}", .{field_value.integer});
                        defer self.allocator.free(int_str);
                        try json_buffer.appendSlice(self.allocator, int_str);
                    }
                }
                try json_buffer.append(self.allocator, '\n');
                try json_buffer.append(self.allocator, ' ');
                try json_buffer.append(self.allocator, ' ');
                try json_buffer.append(self.allocator, '}');
            }
        }
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, '}');
        
        const json_string = try json_buffer.toOwnedSlice(self.allocator);
        defer self.allocator.free(json_string);

        try std.fs.cwd().writeFile(.{
            .sub_path = self.mapping_file,
            .data = json_string,
        });

        if (self.logger) |log| {
            try log.debug("Mappings saved to {s}", .{self.mapping_file});
        }
    }

    /// Generate unique VMID for container
    pub fn generateVmid(self: *VmidManager, container_id: []const u8) !u32 {
        if (self.logger) |log| {
            try log.info("Generating VMID for container: {s}", .{container_id});
        }

        var mappings = try self.loadMappings();
        defer {
            var it = mappings.iterator();
            while (it.next()) |entry| {
                var e = entry.value_ptr.*;
                e.deinit(self.allocator);
            }
            mappings.deinit();
        }

        // Check if mapping already exists
        if (mappings.get(container_id)) |entry| {
            if (self.logger) |log| {
                try log.info("Found existing VMID {d} for container {s}", .{ entry.vmid, container_id });
            }
            return entry.vmid;
        }

        // Generate new VMID
        var vmid = generateVmidFromHash(container_id);
        var attempts: u32 = 0;
        const max_attempts: u32 = 1000;

        while (attempts < max_attempts) : (attempts += 1) {
            // Check if VMID is already used in mappings
            var is_used = false;
            var it = mappings.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.vmid == vmid) {
                    is_used = true;
                    break;
                }
            }

            // Check if VMID exists in Proxmox
            if (!is_used) {
                is_used = try self.vmidExistsInProxmox(vmid);
            }

            if (!is_used) {
                if (self.logger) |log| {
                    try log.info("Generated VMID {d} for container {s}", .{ vmid, container_id });
                }
                return vmid;
            }

            // Collision detected, try next VMID
            vmid = if (vmid >= VMID_END) VMID_START else vmid + 1;
        }

        if (self.logger) |log| {
            try log.err("Failed to generate unique VMID after {d} attempts", .{max_attempts});
        }
        return error.VmidGenerationFailed;
    }

    /// Store mapping between container ID and VMID
    pub fn storeMapping(self: *VmidManager, container_id: []const u8, vmid: u32, bundle_path: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Storing mapping: {s} -> VMID {d}", .{ container_id, vmid });
        }

        var mappings = try self.loadMappings();
        defer {
            var it = mappings.iterator();
            while (it.next()) |entry| {
                var e = entry.value_ptr.*;
                e.deinit(self.allocator);
            }
            mappings.deinit();
        }

        const timestamp = std.time.timestamp();
        
        try mappings.put(try self.allocator.dupe(u8, container_id), .{
            .container_id = try self.allocator.dupe(u8, container_id),
            .vmid = vmid,
            .created_at = timestamp,
            .bundle_path = try self.allocator.dupe(u8, bundle_path),
        });

        try self.saveMappings(&mappings);
        if (self.logger) |log| {
            try log.info("Mapping stored successfully", .{});
        }
    }

    /// Get VMID for container ID
    pub fn getVmid(self: *VmidManager, container_id: []const u8) !u32 {
        var mappings = try self.loadMappings();
        defer {
            var it = mappings.iterator();
            while (it.next()) |entry| {
                var e = entry.value_ptr.*;
                e.deinit(self.allocator);
            }
            mappings.deinit();
        }

        if (mappings.get(container_id)) |entry| {
            return entry.vmid;
        }

        return error.MappingNotFound;
    }

    /// Remove mapping for container ID
    pub fn removeMapping(self: *VmidManager, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Removing mapping for container: {s}", .{container_id});
        }

        var mappings = try self.loadMappings();
        defer {
            var it = mappings.iterator();
            while (it.next()) |entry| {
                var e = entry.value_ptr.*;
                e.deinit(self.allocator);
            }
            mappings.deinit();
        }

        if (mappings.fetchRemove(container_id)) |removed| {
            var e = removed.value;
            e.deinit(self.allocator);
            try self.saveMappings(&mappings);
            if (self.logger) |log| {
                try log.info("Mapping removed successfully", .{});
            }
        } else {
            if (self.logger) |log| {
                try log.warn("Mapping not found for container: {s}", .{container_id});
            }
        }
    }
};

/// Container ID to VMID mapping entry
pub const MappingEntry = struct {
    container_id: []const u8,
    vmid: u32,
    created_at: i64, // Unix timestamp
    bundle_path: []const u8,

    pub fn deinit(self: *MappingEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.container_id);
        allocator.free(self.bundle_path);
    }
};
