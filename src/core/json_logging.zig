const std = @import("std");
const logging = @import("logging.zig");

/// JSON-structured logging system
pub const JsonLogger = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    writer: std.fs.File.Writer,
    component: []const u8,
    
    /// Initialize JSON logger
    pub fn init(allocator: std.mem.Allocator, writer: std.fs.File.Writer, component: []const u8) Self {
        return Self{
            .allocator = allocator,
            .writer = writer,
            .component = component,
        };
    }
    
    /// Log message as JSON
    pub fn log(self: *Self, level: logging.LogLevel, comptime format: []const u8, args: anytype) !void {
        const timestamp = std.time.timestamp();
        const message = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(message);
        
        // Build JSON structure
        try self.writer.writeAll("{\"timestamp\":");
        try std.fmt.format(self.writer, "{d}", .{timestamp});
        
        try self.writer.writeAll(",\"level\":\"");
        try self.writeLevel(level);
        try self.writer.writeAll("\"");
        
        try self.writer.writeAll(",\"component\":\"");
        try self.writer.writeAll(self.component);
        try self.writer.writeAll("\"");
        
        try self.writer.writeAll(",\"message\":");
        try self.writeJsonString(message);
        
        try self.writer.writeAll("}\n");
    }
    
    fn writeLevel(self: *Self, level: logging.LogLevel) !void {
        const level_str = switch (level) {
            .trace => "trace",
            .debug => "debug",
            .info => "info",
            .warn => "warn",
            .@"error" => "error",
            .fatal => "fatal",
        };
        try self.writer.writeAll(level_str);
    }
    
    fn writeJsonString(self: *Self, str: []const u8) !void {
        try self.writer.writeAll("\"");
        for (str) |byte| {
            switch (byte) {
                '"' => try self.writer.writeAll("\\\""),
                '\\' => try self.writer.writeAll("\\\\"),
                '\n' => try self.writer.writeAll("\\n"),
                '\r' => try self.writer.writeAll("\\r"),
                '\t' => try self.writer.writeAll("\\t"),
                else => try self.writer.writeByte(byte),
            }
        }
        try self.writer.writeAll("\"");
    }
    
    /// Log with additional fields
    pub fn logWithFields(
        self: *Self,
        level: logging.LogLevel,
        comptime format: []const u8,
        args: anytype,
        fields: anytype,
    ) !void {
        const timestamp = std.time.timestamp();
        const message = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(message);
        
        try self.writer.writeAll("{\"timestamp\":");
        try std.fmt.format(self.writer, "{d}", .{timestamp});
        
        try self.writer.writeAll(",\"level\":\"");
        try self.writeLevel(level);
        try self.writer.writeAll("\"");
        
        try self.writer.writeAll(",\"component\":\"");
        try self.writer.writeAll(self.component);
        try self.writer.writeAll("\"");
        
        try self.writer.writeAll(",\"message\":");
        try self.writeJsonString(message);
        
        // Add custom fields
        if (@TypeOf(fields) != @TypeOf({})) {
            try self.writer.writeAll(",\"fields\":{");
            const fields_info = @typeInfo(@TypeOf(fields));
            if (fields_info == .Struct) {
                var first = true;
                inline for (fields_info.Struct.fields) |field| {
                    if (!first) try self.writer.writeAll(",");
                    first = false;
                    
                    try self.writer.writeAll("\"");
                    try self.writer.writeAll(field.name);
                    try self.writer.writeAll("\":");
                    
                    const field_value = @field(fields, field.name);
                    try self.writeJsonValue(field_value);
                }
            }
            try self.writer.writeAll("}");
        }
        
        try self.writer.writeAll("}\n");
    }
    
    fn writeJsonValue(self: *Self, value: anytype) !void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .Int, .ComptimeInt => {
                try std.fmt.format(self.writer, "{d}", .{value});
            },
            .Float, .ComptimeFloat => {
                try std.fmt.format(self.writer, "{d}", .{value});
            },
            .Bool => {
                if (value) {
                    try self.writer.writeAll("true");
                } else {
                    try self.writer.writeAll("false");
                }
            },
            .Optional => {
                if (value) |v| {
                    try self.writeJsonValue(v);
                } else {
                    try self.writer.writeAll("null");
                }
            },
            .Pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .Slice => {
                        if (ptr_info.child == u8) {
                            try self.writeJsonString(value);
                        } else {
                            // Array of values
                            try self.writer.writeAll("[");
                            for (value, 0..) |item, i| {
                                if (i > 0) try self.writer.writeAll(",");
                                try self.writeJsonValue(item);
                            }
                            try self.writer.writeAll("]");
                        }
                    },
                    else => {
                        try self.writeJsonString(try std.fmt.allocPrint(self.allocator, "{any}", .{value}));
                    },
                }
            },
            else => {
                // Fallback to string representation
                try self.writeJsonString(try std.fmt.allocPrint(self.allocator, "{any}", .{value}));
            },
        }
    }
    
    pub fn trace(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.trace, format, args);
    }
    
    pub fn debug(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.debug, format, args);
    }
    
    pub fn info(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.info, format, args);
    }
    
    pub fn warn(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.warn, format, args);
    }
    
    pub fn err(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.@"error", format, args);
    }
    
    pub fn fatal(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.fatal, format, args);
    }
};

