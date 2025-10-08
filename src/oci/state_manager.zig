const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const logger_mod = @import("logger");

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

    pub fn deinit(self: *ContainerState, allocator: Allocator) void {
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
    allocator: Allocator,
    logger: *logger_mod.Logger,
    state_dir: []const u8,

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, state_dir: []const u8) !StateManager {
        // Ensure state directory exists
        try fs.cwd().makePath(state_dir);

        return StateManager{
            .allocator = allocator,
            .logger = logger,
            .state_dir = state_dir,
        };
    }

    pub fn deinit(self: *StateManager) void {
        _ = self;
    }

    /// Get path to state file for container
    fn getStateFilePath(self: *StateManager, container_id: []const u8) ![]const u8 {
        const filename = try std.fmt.allocPrint(self.allocator, "{s}.json", .{container_id});
        defer self.allocator.free(filename);
        
        return try fs.path.join(self.allocator, &[_][]const u8{ self.state_dir, filename });
    }

    /// Create new container state
    pub fn createState(
        self: *StateManager,
        container_id: []const u8,
        vmid: u32,
        bundle_path: []const u8,
        status: []const u8,
    ) !ContainerState {
        const timestamp = std.time.timestamp();

        return ContainerState{
            .ociVersion = try self.allocator.dupe(u8, "1.0.2"),
            .id = try self.allocator.dupe(u8, container_id),
            .status = try self.allocator.dupe(u8, status),
            .pid = 0,
            .bundle = try self.allocator.dupe(u8, bundle_path),
            .annotations = null,
            .vmid = vmid,
            .created_at = timestamp,
        };
    }

    /// Save container state to file
    pub fn saveState(self: *StateManager, state: *const ContainerState) !void {
        try self.logger.info("Saving state for container: {s}", .{state.id});

        const state_file = try self.getStateFilePath(state.id);
        defer self.allocator.free(state_file);

        // Serialize state to JSON
        const json_string = try std.json.stringifyAlloc(
            self.allocator,
            state,
            .{ .whitespace = .indent_2 },
        );
        defer self.allocator.free(json_string);

        // Write to file
        try fs.cwd().writeFile(.{
            .sub_path = state_file,
            .data = json_string,
        });

        try self.logger.debug("State saved to: {s}", .{state_file});
    }

    /// Load container state from file
    pub fn loadState(self: *StateManager, container_id: []const u8) !ContainerState {
        try self.logger.debug("Loading state for container: {s}", .{container_id});

        const state_file = try self.getStateFilePath(container_id);
        defer self.allocator.free(state_file);

        const file = try fs.cwd().openFile(state_file, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(ContainerState, self.allocator, content, .{
            .allocate = .alloc_always,
        });
        defer parsed.deinit();

        // Deep copy the parsed state
        return ContainerState{
            .ociVersion = try self.allocator.dupe(u8, parsed.value.ociVersion),
            .id = try self.allocator.dupe(u8, parsed.value.id),
            .status = try self.allocator.dupe(u8, parsed.value.status),
            .pid = parsed.value.pid,
            .bundle = try self.allocator.dupe(u8, parsed.value.bundle),
            .annotations = null, // TODO: Copy annotations if present
            .vmid = parsed.value.vmid,
            .created_at = parsed.value.created_at,
        };
    }

    /// Update container state status
    pub fn updateStatus(self: *StateManager, container_id: []const u8, new_status: []const u8, pid: i32) !void {
        try self.logger.info("Updating status for container {s}: {s}", .{ container_id, new_status });

        var state = try self.loadState(container_id);
        defer state.deinit(self.allocator);

        // Update status and pid
        self.allocator.free(state.status);
        state.status = try self.allocator.dupe(u8, new_status);
        state.pid = pid;

        try self.saveState(&state);
    }

    /// Check if container state exists
    pub fn stateExists(self: *StateManager, container_id: []const u8) !bool {
        const state_file = try self.getStateFilePath(container_id);
        defer self.allocator.free(state_file);

        fs.cwd().access(state_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return false;
            }
            return err;
        };

        return true;
    }

    /// Delete container state
    pub fn deleteState(self: *StateManager, container_id: []const u8) !void {
        try self.logger.info("Deleting state for container: {s}", .{container_id});

        const state_file = try self.getStateFilePath(container_id);
        defer self.allocator.free(state_file);

        try fs.cwd().deleteFile(state_file);
        try self.logger.debug("State deleted: {s}", .{state_file});
    }

    /// List all container states
    pub fn listStates(self: *StateManager) ![]ContainerState {
        var states = std.ArrayList(ContainerState).init(self.allocator);
        errdefer {
            for (states.items) |*state| {
                state.deinit(self.allocator);
            }
            states.deinit();
        }

        var dir = try fs.cwd().openDir(self.state_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

            // Extract container ID from filename (remove .json extension)
            const container_id = entry.name[0 .. entry.name.len - 5];
            
            const state = self.loadState(container_id) catch |err| {
                try self.logger.warn("Failed to load state for {s}: {}", .{ container_id, err });
                continue;
            };

            try states.append(state);
        }

        return try states.toOwnedSlice();
    }
};
