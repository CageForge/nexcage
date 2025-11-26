const std = @import("std");
const core = @import("core");

pub const Pct = struct {
	const Self = @This();

	allocator: std.mem.Allocator,
	logger: ?*core.LogContext,

	pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
		return Self{ .allocator = allocator, .logger = logger };
	}

	pub const RunOutput = struct {
		stdout: []u8,
		stderr: []u8,
		exit_code: u8,

		pub fn deinit(self: *RunOutput, allocator: std.mem.Allocator) void {
			allocator.free(self.stdout);
			allocator.free(self.stderr);
		}
	};

	pub fn run(self: *Self, argv: []const []const u8) !RunOutput {
		const result = try std.process.Child.run(.{ .allocator = self.allocator, .argv = argv });
		defer self.allocator.free(result.stdout);
		defer self.allocator.free(result.stderr);

		if (self.logger) |log| {
			try log.debug("pct exec argv={any} exit={d}", .{ argv, result.term.Exited });
		}

		return RunOutput{
			.stdout = try self.allocator.dupe(u8, result.stdout),
			.stderr = try self.allocator.dupe(u8, result.stderr),
			.exit_code = @intCast(result.term.Exited),
		};
	}

	pub fn create(self: *Self, vmid: u32, rootfs: []const u8, hostname: []const u8, memory_mb: ?u64, cores: ?u32, net0: ?[]const u8) !void {
		// Validate inputs to prevent command injection and invalid values
		try core.validation.SecurityValidation.validateHostname(hostname);
		if (net0) |net_spec| try core.validation.SecurityValidation.validateNetSpec(net_spec);

		var args = std.ArrayListUnmanaged([]const u8){};
		defer args.deinit(self.allocator);

		try args.append(self.allocator, "pct");
		try args.append(self.allocator, "create");

		const vmid_str = try std.fmt.allocPrint(self.allocator, "{d}", .{ vmid });
		defer self.allocator.free(vmid_str);
		try args.append(self.allocator, vmid_str);

		try args.append(self.allocator, rootfs);

		// --hostname <value>
		try args.append(self.allocator, "--hostname");
		try args.append(self.allocator, hostname);

		try args.append(self.allocator, "--unprivileged");
		try args.append(self.allocator, "1");

		if (memory_mb) |mem_mb| {
			// --memory <value>
			const mem_val = try std.fmt.allocPrint(self.allocator, "{d}", .{ mem_mb });
			defer self.allocator.free(mem_val);
			try args.append(self.allocator, "--memory");
			try args.append(self.allocator, mem_val);
		}

		if (cores) |c| {
			// --cores <value>
			const cores_val = try std.fmt.allocPrint(self.allocator, "{d}", .{ c });
			defer self.allocator.free(cores_val);
			try args.append(self.allocator, "--cores");
			try args.append(self.allocator, cores_val);
		}

		if (net0) |n| {
			// --net0 <spec>
			try args.append(self.allocator, "--net0");
			try args.append(self.allocator, n);
		}

		var out = try self.run(args.items);
		defer out.deinit(self.allocator);
		if (out.exit_code != 0) {
			if (self.logger) |log| try log.err("pct create failed: {s}", .{ out.stderr });
			return error.LxcCreationFailed;
		}
	}

	pub fn start(self: *Self, vmid: u32) !void {
		const id = try std.fmt.allocPrint(self.allocator, "{d}", .{ vmid });
		defer self.allocator.free(id);
		var out = try self.run(&[_][]const u8{ "pct", "start", id });
		defer out.deinit(self.allocator);
		if (out.exit_code != 0) return error.LxcStartFailed;
	}

	pub fn stop(self: *Self, vmid: u32) !void {
		const id = try std.fmt.allocPrint(self.allocator, "{d}", .{ vmid });
		defer self.allocator.free(id);
		var out = try self.run(&[_][]const u8{ "pct", "stop", id });
		defer out.deinit(self.allocator);
		if (out.exit_code != 0) return error.LxcStopFailed;
	}

	pub fn destroy(self: *Self, vmid: u32) !void {
		const id = try std.fmt.allocPrint(self.allocator, "{d}", .{ vmid });
		defer self.allocator.free(id);
		var out = try self.run(&[_][]const u8{ "pct", "destroy", id });
		defer out.deinit(self.allocator);
		if (out.exit_code != 0) return error.LxcDeleteFailed;
	}

	/// Configure a bind mount using pct set -mpX
	pub fn setMount(self: *Self, vmid: u32, index: u8, source: []const u8, destination: []const u8, read_only: bool) !void {
		const id = try std.fmt.allocPrint(self.allocator, "{d}", .{ vmid });
		defer self.allocator.free(id);

		const mp_spec = if (read_only)
			try std.fmt.allocPrint(self.allocator, "{s},mp={s},ro=1", .{ source, destination })
		else
			try std.fmt.allocPrint(self.allocator, "{s},mp={s}", .{ source, destination });
		defer self.allocator.free(mp_spec);

		const key = try std.fmt.allocPrint(self.allocator, "-mp{d}", .{ index });
		defer self.allocator.free(key);

		var out = try self.run(&[_][]const u8{ "pct", "set", id, key, mp_spec });
		defer out.deinit(self.allocator);
		if (out.exit_code != 0) return error.LxcMountConfigFailed;
	}

};
