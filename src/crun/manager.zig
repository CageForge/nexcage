const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const log = std.log;
const process = std.process;
const oci_spec = @import("spec.zig");
const types = @import("types");
const errors = @import("error");
const logger_mod = @import("logger");

pub const CrunConfig = struct {
    runtime_path: []const u8,
    container_id: []const u8,
};

pub const CrunManager = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    config: CrunConfig,

    const Self = @This();

    pub fn init(allocator: Allocator, config: CrunConfig, logger: *logger_mod.Logger) !Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.config.deinit();
    }

    pub fn create(self: *Self, spec: oci_spec.Spec) !void {
        try self.logger.info("Creating container {s} with crun", .{self.config.container_id});

        // Перевіряємо наявність crun
        try self.checkCrunAvailability();

        // Створюємо контейнер через crun з додатковими опціями зі spec
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.config.runtime_path);
        try args.append("create");
        try args.append("--bundle");
        try args.append(self.config.bundle_path);

        // Додаємо опції з spec
        if (spec.process) |proc| {
            if (proc.terminal) {
                try args.append("--console-socket");
                try args.append("/run/user/0/console.sock");
            }
        }

        if (spec.linux) |linux| {
            if (linux.resources) |resources| {
                if (resources.memory) |memory| {
                    if (memory.limit) |limit| {
                        try args.append("--memory");
                        const limit_str = try std.fmt.allocPrint(self.allocator, "{d}", .{limit});
                        defer self.allocator.free(limit_str);
                        try args.append(limit_str);
                    }
                }
            }
        }

        try args.append(self.config.container_id);

        const result = try process.Child.run(.{
            .allocator = self.allocator,
            .argv = args.items,
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to create container: {s}", .{result.stderr});
            return errors.Error.ContainerCreationFailed;
        }
    }

    pub fn start(self: *Self) !void {
        try self.logger.info("Starting container {s}", .{self.config.container_id});
        // TODO: Implement container start
    }

    pub fn stop(self: *Self) !void {
        try self.logger.info("Stopping container {s}", .{self.config.container_id});
        // TODO: Implement container stop
    }

    pub fn delete(self: *Self) !void {
        try self.logger.info("Deleting container {s}", .{self.config.container_id});
        // TODO: Implement container deletion
    }

    pub fn createContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, container_spec: oci_spec.Spec) !void {
        try self.logger.info("Creating container {s} with crun", .{container_id});

        // Перевіряємо наявність crun
        try self.checkCrunAvailability();

        // Створюємо контейнер через crun з додатковими опціями зі spec
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.config.runtime_path);
        try args.append("create");
        try args.append("--bundle");
        try args.append(bundle_path);

        // Додаємо опції з spec
        if (container_spec.process) |proc| {
            if (proc.terminal) {
                try args.append("--console-socket");
                try args.append("/run/user/0/console.sock");
            }
        }

        if (container_spec.linux) |linux| {
            if (linux.resources) |resources| {
                if (resources.memory) |memory| {
                    if (memory.limit) |limit| {
                        try args.append("--memory");
                        const limit_str = try std.fmt.allocPrint(self.allocator, "{d}", .{limit});
                        defer self.allocator.free(limit_str);
                        try args.append(limit_str);
                    }
                }
            }
        }

        try args.append(container_id);

        const result = try process.Child.run(.{
            .allocator = self.allocator,
            .argv = args.items,
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to create container: {s}", .{result.stderr});
            return errors.Error.ContainerCreationFailed;
        }
    }

    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Starting container {s} with crun", .{container_id});

        const result = try process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                self.config.runtime_path,
                "start",
                container_id,
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to start container: {s}", .{result.stderr});
            return errors.Error.ContainerStartFailed;
        }
    }

    pub fn stopContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Stopping container {s} with crun", .{container_id});

        const result = try process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                self.config.runtime_path,
                "kill",
                container_id,
                "SIGTERM",
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to stop container: {s}", .{result.stderr});
            return errors.Error.ContainerStopFailed;
        }
    }

    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Deleting container {s} with crun", .{container_id});

        const result = try process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                self.config.runtime_path,
                "delete",
                container_id,
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to delete container: {s}", .{result.stderr});
            return errors.Error.ContainerDeletionFailed;
        }
    }

    pub fn getContainerState(self: *Self, container_id: []const u8) !types.ContainerState {
        try self.logger.info("Getting state for container {s}", .{container_id});

        const result = try process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                self.config.runtime_path,
                "state",
                container_id,
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to get container state: {s}", .{result.stderr});
            return errors.Error.ContainerStateError;
        }

        // Парсимо JSON відповідь
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, result.stdout, .{});
        defer parsed.deinit();

        const state = parsed.value.object.get("status").?.string;
        return std.meta.stringToEnum(types.ContainerState, state) orelse .unknown;
    }

    fn checkCrunAvailability(self: *Self) !void {
        const result = try process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                self.config.runtime_path,
                "--version",
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            try self.logger.err("crun is not available: {s}", .{result.stderr});
            return errors.Error.SystemError;
        }
    }
};
