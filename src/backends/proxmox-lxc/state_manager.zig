const std = @import("std");
const core = @import("core");

/// OCI container state as per OCI runtime spec
pub const ContainerState = struct {
    ociVersion: []const u8,
    id: []const u8,
    status: []const u8, // created, running, stopped, paused
    pid: i32,
    bundle: []const u8,
    annotations: ?std.json.ObjectMap = null,
    
    // Extension: Proxmox-specific fields
    vmid: u32,
    created_at: i64,

    pub fn deinit(self: *ContainerState, allocator: std.mem.Allocator) void {
        allocator.free(self.ociVersion);
        allocator.free(self.id);
        allocator.free(self.status);
        allocator.free(self.bundle);
        if (self.annotations) |*annotations| {
            annotations.deinit();
        }
    }
};

/// Manages container state persistence
pub const StateManager = struct {
    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,
    state_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext, state_dir: []const u8) !StateManager {
        // Ensure state directory exists
        try std.fs.cwd().makePath(state_dir);

        return StateManager{
            .allocator = allocator,
            .logger = logger,
            .state_dir = state_dir,
        };
    }

    pub fn deinit(self: *StateManager) void {
        _ = self;
    }

    /// Check if container state exists
    pub fn stateExists(self: *StateManager, container_id: []const u8) !bool {
        const state_file = try self.getStateFilePath(container_id);
        defer self.allocator.free(state_file);

        const file = std.fs.cwd().openFile(state_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return false;
            }
            return err;
        };
        defer file.close();

        return true;
    }

    /// Create container state
    pub fn createState(self: *StateManager, container_id: []const u8, vmid: u32, bundle_path: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Creating state for container: {s} (VMID: {d})", .{ container_id, vmid });
        }

        var state = ContainerState{
            .ociVersion = try self.allocator.dupe(u8, "1.0.2"),
            .id = try self.allocator.dupe(u8, container_id),
            .status = try self.allocator.dupe(u8, "created"),
            .pid = 0,
            .bundle = try self.allocator.dupe(u8, bundle_path),
            .annotations = null,
            .vmid = vmid,
            .created_at = std.time.timestamp(),
        };
        defer state.deinit(self.allocator);

        try self.saveState(&state);
    }

    /// Update container state
    pub fn updateState(self: *StateManager, container_id: []const u8, status: []const u8, pid: i32) !void {
        if (self.logger) |log| {
            try log.info("Updating state for container: {s} -> {s} (PID: {d})", .{ container_id, status, pid });
        }

        var state = try self.loadState(container_id);
        defer state.deinit(self.allocator);

        // Update status and PID
        self.allocator.free(state.status);
        state.status = try self.allocator.dupe(u8, status);
        state.pid = pid;

        try self.saveState(&state);
    }

    /// Load container state
    pub fn loadState(self: *StateManager, container_id: []const u8) !ContainerState {
        const state_file = try self.getStateFilePath(container_id);
        defer self.allocator.free(state_file);

        const file = try std.fs.cwd().openFile(state_file, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        if (parsed.value != .object) {
            return error.InvalidStateFormat;
        }

        const obj = parsed.value.object;

        const ociVersion = if (obj.get("ociVersion")) |v| 
            if (v == .string) try self.allocator.dupe(u8, v.string) else try self.allocator.dupe(u8, "1.0.2")
        else try self.allocator.dupe(u8, "1.0.2");

        const id = if (obj.get("id")) |v| 
            if (v == .string) try self.allocator.dupe(u8, v.string) else try self.allocator.dupe(u8, container_id)
        else try self.allocator.dupe(u8, container_id);

        const status = if (obj.get("status")) |v| 
            if (v == .string) try self.allocator.dupe(u8, v.string) else try self.allocator.dupe(u8, "unknown")
        else try self.allocator.dupe(u8, "unknown");

        const pid = if (obj.get("pid")) |v| 
            if (v == .integer) @as(i32, @intCast(v.integer)) else 0
        else 0;

        const bundle = if (obj.get("bundle")) |v| 
            if (v == .string) try self.allocator.dupe(u8, v.string) else try self.allocator.dupe(u8, "")
        else try self.allocator.dupe(u8, "");

        const vmid = if (obj.get("vmid")) |v| 
            if (v == .integer) @as(u32, @intCast(v.integer)) else 0
        else 0;

        const created_at = if (obj.get("created_at")) |v| 
            if (v == .integer) v.integer else std.time.timestamp()
        else std.time.timestamp();

        return ContainerState{
            .ociVersion = ociVersion,
            .id = id,
            .status = status,
            .pid = pid,
            .bundle = bundle,
            .annotations = null,
            .vmid = vmid,
            .created_at = created_at,
        };
    }

    /// Save container state
    fn saveState(self: *StateManager, state: *const ContainerState) !void {
        const state_file = try self.getStateFilePath(state.id);
        defer self.allocator.free(state_file);

        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();

        try json_obj.put("ociVersion", .{ .string = state.ociVersion });
        try json_obj.put("id", .{ .string = state.id });
        try json_obj.put("status", .{ .string = state.status });
        try json_obj.put("pid", .{ .integer = state.pid });
        try json_obj.put("bundle", .{ .string = state.bundle });
        try json_obj.put("vmid", .{ .integer = state.vmid });
        try json_obj.put("created_at", .{ .integer = state.created_at });

        if (state.annotations) |annotations| {
            try json_obj.put("annotations", .{ .object = annotations });
        }

        // Simple JSON serialization
        var json_buffer = std.ArrayListUnmanaged(u8){};
        defer json_buffer.deinit(self.allocator);
        
        try json_buffer.append(self.allocator, '{');
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, "ociVersion");
        try json_buffer.append(self.allocator, '"');
        try json_buffer.append(self.allocator, ':');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, state.ociVersion);
        try json_buffer.append(self.allocator, '"');
        
        try json_buffer.append(self.allocator, ',');
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, "id");
        try json_buffer.append(self.allocator, '"');
        try json_buffer.append(self.allocator, ':');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, state.id);
        try json_buffer.append(self.allocator, '"');
        
        try json_buffer.append(self.allocator, ',');
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, "status");
        try json_buffer.append(self.allocator, '"');
        try json_buffer.append(self.allocator, ':');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, state.status);
        try json_buffer.append(self.allocator, '"');
        
        try json_buffer.append(self.allocator, ',');
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, "pid");
        try json_buffer.append(self.allocator, '"');
        try json_buffer.append(self.allocator, ':');
        try json_buffer.append(self.allocator, ' ');
        const pid_str = try std.fmt.allocPrint(self.allocator, "{d}", .{state.pid});
        defer self.allocator.free(pid_str);
        try json_buffer.appendSlice(self.allocator, pid_str);
        
        try json_buffer.append(self.allocator, ',');
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, "bundle");
        try json_buffer.append(self.allocator, '"');
        try json_buffer.append(self.allocator, ':');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, state.bundle);
        try json_buffer.append(self.allocator, '"');
        
        try json_buffer.append(self.allocator, ',');
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, "vmid");
        try json_buffer.append(self.allocator, '"');
        try json_buffer.append(self.allocator, ':');
        try json_buffer.append(self.allocator, ' ');
        const vmid_str = try std.fmt.allocPrint(self.allocator, "{d}", .{state.vmid});
        defer self.allocator.free(vmid_str);
        try json_buffer.appendSlice(self.allocator, vmid_str);
        
        try json_buffer.append(self.allocator, ',');
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, ' ');
        try json_buffer.append(self.allocator, '"');
        try json_buffer.appendSlice(self.allocator, "created_at");
        try json_buffer.append(self.allocator, '"');
        try json_buffer.append(self.allocator, ':');
        try json_buffer.append(self.allocator, ' ');
        const created_str = try std.fmt.allocPrint(self.allocator, "{d}", .{state.created_at});
        defer self.allocator.free(created_str);
        try json_buffer.appendSlice(self.allocator, created_str);
        
        try json_buffer.append(self.allocator, '\n');
        try json_buffer.append(self.allocator, '}');
        
        const json_string = try json_buffer.toOwnedSlice(self.allocator);
        defer self.allocator.free(json_string);

        try std.fs.cwd().writeFile(.{
            .sub_path = state_file,
            .data = json_string,
        });

        if (self.logger) |log| {
            try log.debug("State saved to {s}", .{state_file});
        }
    }

    /// Get state file path for container
    fn getStateFilePath(self: *StateManager, container_id: []const u8) ![]const u8 {
        const filename = try std.fmt.allocPrint(self.allocator, "{s}.json", .{container_id});
        defer self.allocator.free(filename);
        return std.fs.path.join(self.allocator, &[_][]const u8{ self.state_dir, filename });
    }

    /// Delete container state
    pub fn deleteState(self: *StateManager, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Deleting state for container: {s}", .{container_id});
        }

        const state_file = try self.getStateFilePath(container_id);
        defer self.allocator.free(state_file);

        std.fs.cwd().deleteFile(state_file) catch |err| {
            if (err == error.FileNotFound) {
                if (self.logger) |log| {
                    try log.warn("State file not found for container: {s}", .{container_id});
                }
                return;
            }
            return err;
        };

        if (self.logger) |log| {
            try log.info("State deleted for container: {s}", .{container_id});
        }
    }
};
