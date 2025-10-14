const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const logger_mod = @import("logger");
const mapping = @import("mapping.zig");
const state_manager = @import("state_manager.zig");
const config_parser = @import("config_parser.zig");
const lxc_creator = @import("../backends/lxc/creator.zig");

/// OCI create command implementation
pub const CreateCommand = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    state_dir: []const u8,

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, state_dir: []const u8) !CreateCommand {
        return CreateCommand{
            .allocator = allocator,
            .logger = logger,
            .state_dir = state_dir,
        };
    }

    /// Execute create command
    /// Creates LXC container from OCI bundle but does not start it
    pub fn execute(
        self: *CreateCommand,
        container_id: []const u8,
        bundle_path: []const u8,
    ) !void {
        try self.logger.info("Creating container: {s} from bundle: {s}", .{ container_id, bundle_path });

        // Step 1: Initialize managers
        var mapping_mgr = try mapping.MappingManager.init(self.allocator, self.logger, self.state_dir);
        defer mapping_mgr.deinit();

        var state_mgr = try state_manager.StateManager.init(self.allocator, self.logger, self.state_dir);
        defer state_mgr.deinit();

        // Step 2: Check if container already exists
        if (try state_mgr.stateExists(container_id)) {
            try self.logger.err("Container {s} already exists", .{container_id});
            return error.ContainerExists;
        }

        // Step 3: Generate VMID
        const vmid = try mapping_mgr.generateVmid(container_id);
        try self.logger.info("Generated VMID {d} for container {s}", .{ vmid, container_id });

        // Step 4: Parse OCI config.json
        var parser = config_parser.ConfigParser.init(self.allocator, self.logger);
        const oci_spec = try parser.parseConfig(bundle_path);
        defer {
            // TODO: Implement proper spec cleanup
            self.allocator.free(oci_spec.ociVersion);
        }

        // Step 5: Convert to LXC config
        const lxc_config = try parser.toLxcConfig(&oci_spec, bundle_path);
        defer lxc_config.deinit(self.allocator);

        // Step 6: Create LXC container
        var creator = lxc_creator.LxcCreator.init(self.allocator, self.logger);
        try creator.createContainer(vmid, &lxc_config);

        // Step 7: Configure environment
        if (lxc_config.env.len > 0) {
            try creator.configureEnvironment(vmid, lxc_config.env);
        }

        // Step 8: Configure mounts (if any)
        if (lxc_config.mounts.len > 0) {
            try creator.configureMounts(vmid, lxc_config.mounts);
        }

        // Step 9: Store mapping
        try mapping_mgr.storeMapping(container_id, vmid, bundle_path);

        // Step 10: Create and save state
        var container_state = try state_mgr.createState(
            container_id,
            vmid,
            bundle_path,
            "created",
        );
        defer container_state.deinit(self.allocator);

        try state_mgr.saveState(&container_state);

        try self.logger.info("Container {s} created successfully (VMID {d}, status: created)", .{ container_id, vmid });
    }

    /// Validate bundle before creation
    pub fn validateBundle(self: *CreateCommand, bundle_path: []const u8) !void {
        try self.logger.debug("Validating bundle: {s}", .{bundle_path});

        // Check if bundle directory exists
        var bundle_dir = fs.cwd().openDir(bundle_path, .{}) catch |err| {
            try self.logger.err("Bundle directory not found: {s}", .{bundle_path});
            return err;
        };
        defer bundle_dir.close();

        // Check if config.json exists
        bundle_dir.access("config.json", .{}) catch |err| {
            try self.logger.err("config.json not found in bundle: {s}", .{bundle_path});
            return err;
        };

        // Check if rootfs directory exists
        bundle_dir.access("rootfs", .{}) catch |err| {
            try self.logger.err("rootfs directory not found in bundle: {s}", .{bundle_path});
            return err;
        };

        try self.logger.debug("Bundle validation passed: {s}", .{bundle_path});
    }
};
