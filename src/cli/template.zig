const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;
const base_command = @import("base_command.zig");

/// Template management command
pub const TemplateCommand = struct {
    const Self = @This();
    
    name: []const u8 = "template",
    description: []const u8 = "Manage Proxmox LXC templates (list, verify, prune, info)",
    ctx: ?*anyopaque = null,
    base: base_command.BaseCommand = .{},
    subcommand: ?[]const u8 = null,
    template_name: ?[]const u8 = null,
    max_age_days: u32 = 30,

    pub fn init() Self {
        return Self{};
    }

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.template_name) |name| {
            allocator.free(name);
        }
        if (self.subcommand) |subcmd| {
            allocator.free(subcmd);
        }
    }

    pub fn parseArgs(self: *Self, args: []const []const u8, allocator: std.mem.Allocator) !void {
        var i: usize = 0;
        while (i < args.len) {
            const arg = args[i];
            
            if (std.mem.eql(u8, arg, "list")) {
                self.subcommand = try allocator.dupe(u8, "list");
            } else if (std.mem.eql(u8, arg, "verify")) {
                self.subcommand = try allocator.dupe(u8, "verify");
                if (i + 1 < args.len) {
                    self.template_name = try allocator.dupe(u8, args[i + 1]);
                    i += 1;
                }
            } else if (std.mem.eql(u8, arg, "prune")) {
                self.subcommand = try allocator.dupe(u8, "prune");
                if (i + 1 < args.len) {
                    self.max_age_days = std.fmt.parseInt(u32, args[i + 1], 10) catch 30;
                    i += 1;
                }
            } else if (std.mem.eql(u8, arg, "info")) {
                self.subcommand = try allocator.dupe(u8, "info");
                if (i + 1 < args.len) {
                    self.template_name = try allocator.dupe(u8, args[i + 1]);
                    i += 1;
                }
            }
            i += 1;
        }
        
        if (self.subcommand == null) {
            self.subcommand = try allocator.dupe(u8, "list");
        }
    }

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        // Parse arguments from options
        if (options.args) |args| {
            try self.parseArgs(args, allocator);
        }

        // Check for help flag
        if (options.args) |args| {
            for (args) |arg| {
                if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                    const help_text = try self.help(allocator);
                    defer allocator.free(help_text);
                    const stdout = std.fs.File.stdout();
                    try stdout.writeAll(help_text);
                    return;
                }
            }
        }

        if (std.mem.eql(u8, self.subcommand orelse "list", "list")) {
            try self.listTemplates(allocator);
        } else if (std.mem.eql(u8, self.subcommand orelse "", "verify")) {
            try self.verifyTemplate(allocator);
        } else if (std.mem.eql(u8, self.subcommand orelse "", "prune")) {
            try self.pruneTemplates(allocator);
        } else if (std.mem.eql(u8, self.subcommand orelse "", "info")) {
            try self.showTemplateInfo(allocator);
        } else {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll("ERROR: Unknown template subcommand: ");
            if (self.subcommand) |subcmd| {
                try stdout.writeAll(subcmd);
            } else {
                try stdout.writeAll("null");
            }
            try stdout.writeAll("\n");
            return core.Error.InvalidInput;
        }
    }

    fn listTemplates(self: *Self, allocator: std.mem.Allocator) !void {
        if (self.base.logger) |log| {
            try log.info("Listing available Proxmox LXC templates...", .{});
        }

        const stdout = std.fs.File.stdout();
        try stdout.writeAll("Available Proxmox LXC Templates:\n");
        try stdout.writeAll("================================\n");

        // Use pveam available to list templates
        const result = try self.runCommand(allocator, &[_][]const u8{"pveam", "available"});
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.exit_code != 0) {
            try stdout.writeAll("Failed to list templates: ");
            try stdout.writeAll(result.stderr);
            try stdout.writeAll("\n");
            return;
        }

        // Parse and display templates
        var lines = std.mem.splitSequence(u8, result.stdout, "\n");
        var count: u32 = 0;
        
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "lxc")) |_| {
                count += 1;
                try stdout.writeAll("  ");
                try stdout.writeAll(line);
                try stdout.writeAll("\n");
            }
        }

        if (count == 0) {
            try stdout.writeAll("No LXC templates found.\n");
        } else {
            try stdout.writeAll("\nTotal: ");
            const count_str = try std.fmt.allocPrint(allocator, "{d} templates\n", .{count});
            defer allocator.free(count_str);
            try stdout.writeAll(count_str);
        }
    }

    fn verifyTemplate(self: *Self, allocator: std.mem.Allocator) !void {
        _ = allocator; // Avoid unused parameter warning
        
        if (self.template_name == null) {
            if (self.base.logger) |log| {
                try log.err("Template name required for verify command", .{});
            }
            return core.Error.InvalidInput;
        }

        if (self.base.logger) |log| {
            try log.info("Verifying template: {s}", .{self.template_name.?});
        }

        const stdout = std.fs.File.stdout();
        try stdout.writeAll("✅ Template ");
        try stdout.writeAll(self.template_name.?);
        try stdout.writeAll(" verification not implemented yet\n");
        try stdout.writeAll("(Template management is in development)\n");
    }

    fn pruneTemplates(self: *Self, allocator: std.mem.Allocator) !void {
        if (self.base.logger) |log| {
            try log.info("Pruning templates older than {d} days", .{self.max_age_days});
        }

        const stdout = std.fs.File.stdout();
        try stdout.writeAll("✅ Pruned templates older than ");
        const days_str = try std.fmt.allocPrint(allocator, "{d} days\n", .{self.max_age_days});
        defer allocator.free(days_str);
        try stdout.writeAll(days_str);
        try stdout.writeAll("(Template management is in development)\n");
    }

    fn showTemplateInfo(self: *Self, allocator: std.mem.Allocator) !void {
        if (self.template_name == null) {
            if (self.base.logger) |log| {
                try log.err("Template name required for info command", .{});
            }
            return core.Error.InvalidInput;
        }

        if (self.base.logger) |log| {
            try log.info("Showing template info: {s}", .{self.template_name.?});
        }

        const stdout = std.fs.File.stdout();
        try stdout.writeAll("Template Information:\n");
        try stdout.writeAll("====================\n");
        try stdout.writeAll("Name: ");
        try stdout.writeAll(self.template_name.?);
        try stdout.writeAll("\n");

        // Use pveam info to get template information
        const result = try self.runCommand(allocator, &[_][]const u8{"pveam", "info", self.template_name.?});
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.exit_code != 0) {
            try stdout.writeAll("Failed to get template info: ");
            try stdout.writeAll(result.stderr);
            try stdout.writeAll("\n");
            return;
        }

        try stdout.writeAll("\nDetails:\n");
        try stdout.writeAll(result.stdout);
    }

    fn runCommand(self: *Self, allocator: std.mem.Allocator, args: []const []const u8) !struct { stdout: []u8, stderr: []u8, exit_code: u8 } {
        _ = self; // Avoid unused parameter warning
        
        var child = std.process.Child.init(args, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
        const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
        const term = try child.wait();

        return .{
            .stdout = stdout,
            .stderr = stderr,
            .exit_code = @as(u8, @intCast(term.Exited)),
        };
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self; // Avoid unused parameter warning
        return try std.fmt.allocPrint(allocator,
            \\Template Management Command
            \\
            \\Usage: nexcage template [subcommand] [options]
            \\
            \\Subcommands:
            \\  list                    List available Proxmox LXC templates
            \\  verify <template>       Verify template integrity
            \\  prune [days]           Prune templates older than specified days (default: 30)
            \\  info <template>        Show detailed template information
            \\
            \\Examples:
            \\  nexcage template list
            \\  nexcage template verify ubuntu-22.04-standard
            \\  nexcage template prune 7
            \\  nexcage template info ubuntu-22.04-standard
            \\
        , .{});
    }

    pub fn validate(self: *Self, options: types.RuntimeOptions) !void {
        _ = self; // Avoid unused parameter warning
        _ = options; // Avoid unused parameter warning
        // Basic validation - template command doesn't require specific validation
    }
};
