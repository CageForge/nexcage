const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const logger_mod = @import("logger");

/// Container ID to VMID mapping entry
pub const MappingEntry = struct {
    container_id: []const u8,
    vmid: u32,
    created_at: i64, // Unix timestamp
    bundle_path: []const u8,

    pub fn deinit(self: *MappingEntry, allocator: Allocator) void {
        allocator.free(self.container_id);
        allocator.free(self.bundle_path);
    }
};

/// Manages mapping between OCI container IDs and Proxmox VMIDs
pub const MappingManager = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    state_dir: []const u8,
    mapping_file: []const u8,

    const VMID_START = 100;
    const VMID_END = 999999;

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, state_dir: []const u8) !MappingManager {
        const mapping_file = try fs.path.join(allocator, &[_][]const u8{ state_dir, "mapping.json" });
        
        // Ensure state directory exists
        try fs.cwd().makePath(state_dir);

        return MappingManager{
            .allocator = allocator,
            .logger = logger,
            .state_dir = state_dir,
            .mapping_file = mapping_file,
        };
    }

    pub fn deinit(self: *MappingManager) void {
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
    fn vmidExistsInProxmox(self: *MappingManager, vmid: u32) !bool {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "pct", "list" },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            try self.logger.warn("Failed to list containers: {s}", .{result.stderr});
            return false;
        }

        const vmid_str = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid});
        defer self.allocator.free(vmid_str);

        return std.mem.indexOf(u8, result.stdout, vmid_str) != null;
    }

    /// Load existing mappings from file
    fn loadMappings(self: *MappingManager) !std.StringHashMap(MappingEntry) {
        var mappings = std.StringHashMap(MappingEntry).init(self.allocator);

        const file = fs.cwd().openFile(self.mapping_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                try self.logger.debug("Mapping file not found, starting with empty mappings", .{});
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
    fn saveMappings(self: *MappingManager, mappings: *std.StringHashMap(MappingEntry)) !void {
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

        const json_string = try std.json.stringifyAlloc(self.allocator, json_obj, .{ .whitespace = .indent_2 });
        defer self.allocator.free(json_string);

        try fs.cwd().writeFile(.{
            .sub_path = self.mapping_file,
            .data = json_string,
        });

        try self.logger.debug("Mappings saved to {s}", .{self.mapping_file});
    }

    /// Generate unique VMID for container
    pub fn generateVmid(self: *MappingManager, container_id: []const u8) !u32 {
        try self.logger.info("Generating VMID for container: {s}", .{container_id});

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
            try self.logger.info("Found existing VMID {d} for container {s}", .{ entry.vmid, container_id });
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
                try self.logger.info("Generated VMID {d} for container {s}", .{ vmid, container_id });
                return vmid;
            }

            // Collision detected, try next VMID
            vmid = if (vmid >= VMID_END) VMID_START else vmid + 1;
        }

        try self.logger.err("Failed to generate unique VMID after {d} attempts", .{max_attempts});
        return error.VmidGenerationFailed;
    }

    /// Store mapping between container ID and VMID
    pub fn storeMapping(self: *MappingManager, container_id: []const u8, vmid: u32, bundle_path: []const u8) !void {
        try self.logger.info("Storing mapping: {s} -> VMID {d}", .{ container_id, vmid });

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
        try self.logger.info("Mapping stored successfully", .{});
    }

    /// Get VMID for container ID
    pub fn getVmid(self: *MappingManager, container_id: []const u8) !u32 {
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
    pub fn removeMapping(self: *MappingManager, container_id: []const u8) !void {
        try self.logger.info("Removing mapping for container: {s}", .{container_id});

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
            try self.logger.info("Mapping removed successfully", .{});
        } else {
            try self.logger.warn("Mapping not found for container: {s}", .{container_id});
        }
    }
};
