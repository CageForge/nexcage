const std = @import("std");
const os = std.os;
const types = @import("../types/pod.zig");

pub const Error = error{
    RuleAddFailed,
    RuleDeleteFailed,
    InvalidProtocol,
    CommandFailed,
    RuleCheckFailed,
};

pub const PortForwarder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    container_ip: []const u8,
    rules: std.ArrayList(types.PortMapping),

    pub fn init(allocator: std.mem.Allocator, container_ip: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .container_ip = try allocator.dupe(u8, container_ip),
            .rules = std.ArrayList(types.PortMapping).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.container_ip);
        self.rules.deinit();
    }

    /// Checks if a port forwarding rule exists
    pub fn hasRule(self: *const Self, mapping: types.PortMapping) bool {
        for (self.rules.items) |rule| {
            if (std.meta.eql(rule, mapping)) {
                return true;
            }
        }
        return false;
    }

    /// Adds a port forwarding rule
    pub fn addRule(self: *Self, mapping: types.PortMapping) !void {
        const protocol = switch (mapping.protocol) {
            .tcp => "tcp",
            .udp => "udp",
            else => return Error.InvalidProtocol,
        };

        // Create iptables command
        const cmd = try std.fmt.allocPrint(
            self.allocator,
            "iptables -t nat -A PREROUTING -p {s} " ++
                "-m {s} --dport {d} -j DNAT " ++
                "--to-destination {s}:{d}",
            .{
                protocol,
                protocol,
                mapping.host_port,
                self.container_ip,
                mapping.container_port,
            },
        );
        defer self.allocator.free(cmd);

        // Execute command
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", cmd },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            return Error.RuleAddFailed;
        }

        // Add MASQUERADE rule
        const masq_cmd = try std.fmt.allocPrint(
            self.allocator,
            "iptables -t nat -A POSTROUTING -p {s} " ++
                "-m {s} --dport {d} -j MASQUERADE",
            .{
                protocol,
                protocol,
                mapping.container_port,
            },
        );
        defer self.allocator.free(masq_cmd);

        const masq_result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", masq_cmd },
        });
        defer {
            self.allocator.free(masq_result.stdout);
            self.allocator.free(masq_result.stderr);
        }

        if (masq_result.term.Exited != 0) {
            // Remove previous rule if MASQUERADE failed
            _ = try std.ChildProcess.exec(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{ "sh", "-c", "iptables -t nat -D PREROUTING -p " ++ protocol },
            });
            return Error.RuleAddFailed;
        }

        // Save rule to the list
        try self.rules.append(mapping);
    }

    /// Removes a port forwarding rule
    pub fn deleteRule(self: *Self, mapping: types.PortMapping) !void {
        const protocol = switch (mapping.protocol) {
            .tcp => "tcp",
            .udp => "udp",
            else => return Error.InvalidProtocol,
        };

        // Remove DNAT rule
        const cmd = try std.fmt.allocPrint(
            self.allocator,
            "iptables -t nat -D PREROUTING -p {s} " ++
                "-m {s} --dport {d} -j DNAT " ++
                "--to-destination {s}:{d}",
            .{
                protocol,
                protocol,
                mapping.host_port,
                self.container_ip,
                mapping.container_port,
            },
        );
        defer self.allocator.free(cmd);

        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", cmd },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            return Error.RuleDeleteFailed;
        }

        // Remove MASQUERADE rule
        const masq_cmd = try std.fmt.allocPrint(
            self.allocator,
            "iptables -t nat -D POSTROUTING -p {s} " ++
                "-m {s} --dport {d} -j MASQUERADE",
            .{
                protocol,
                protocol,
                mapping.container_port,
            },
        );
        defer self.allocator.free(masq_cmd);

        const masq_result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", masq_cmd },
        });
        defer {
            self.allocator.free(masq_result.stdout);
            self.allocator.free(masq_result.stderr);
        }

        if (masq_result.term.Exited != 0) {
            return Error.RuleDeleteFailed;
        }

        // Remove rule from the list
        for (self.rules.items) |rule| {
            if (std.meta.eql(rule, mapping)) {
                try self.rules.swapRemove(i);
                break;
            }
        }
    }
};
