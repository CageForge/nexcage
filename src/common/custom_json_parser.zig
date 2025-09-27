const std = @import("std");
const zig_json = @import("zig_json");

pub fn ParsedResult(comptime T: type) type {
    return struct {
        value: T,
        unknown_fields: []const []const u8,
    };
}

pub fn parseWithUnknownFields(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !ParsedResult(T) {
    var unknown_fields = std.ArrayList([]const u8).init(allocator);
    defer unknown_fields.deinit();

    // First, parse as an object to get all fields
    const raw_value = try zig_json.parse(input, allocator);
    defer raw_value.deinit(allocator);

    // Collect unknown fields
    if (raw_value.type == .object) {
        const obj = raw_value.object();
        var it = obj.map.iterator();
        while (it.next()) |entry| {
            const field_name = entry.key_ptr.*;
            var is_known = false;
            inline for (std.meta.fields(T)) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    is_known = true;
                    break;
                }
            }
            if (!is_known) {
                try unknown_fields.append(try allocator.dupe(u8, field_name));
            }
        }
    }

    // Now parse as our type
    const value = try zig_json.parse(input, allocator);
    defer value.deinit(allocator);

    // Convert value to our type
    var result: T = undefined;
    inline for (std.meta.fields(T)) |field| {
        const obj = value.object();
        if (obj.map.get(field.name)) |field_value| {
            @field(result, field.name) = try convertValue(field.type, field_value, allocator);
        } else {
            @field(result, field.name) = @as(field.type, undefined);
        }
    }

    // Initialize unknown_fields for each field
    inline for (std.meta.fields(T)) |field| {
        if (@typeInfo(field.type) == .Struct) {
            if (@hasField(field.type, "unknown_fields")) {
                @field(result, field.name).unknown_fields = &[_][]const u8{};
            }
        }
    }

    return .{
        .value = result,
        .unknown_fields = try unknown_fields.toOwnedSlice(),
    };
}

fn convertValue(comptime T: type, value: *zig_json.JsonValue, allocator: std.mem.Allocator) !T {
    switch (@typeInfo(T)) {
        .Struct => {
            if (value.type != .object) return error.InvalidType;
            var result: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                const obj = value.object();
                if (obj.map.get(field.name)) |field_value| {
                    @field(result, field.name) = try convertValue(field.type, field_value, allocator);
                } else {
                    @field(result, field.name) = @as(field.type, undefined);
                }
            }
            // Initialize unknown_fields for nested structs
            inline for (std.meta.fields(T)) |field| {
                if (@typeInfo(field.type) == .Struct) {
                    if (@hasField(field.type, "unknown_fields")) {
                        @field(result, field.name).unknown_fields = &[_][]const u8{};
                    }
                }
            }
            return result;
        },
        .Enum => {
            if (value.type != .string) return error.InvalidType;
            const str = value.string();
            return std.meta.stringToEnum(T, str) orelse return error.InvalidEnumValue;
        },
        .Optional => |optional_info| {
            if (value.type == .nil) {
                return null;
            }
            const child_value = try convertValue(optional_info.child, value, allocator);
            return child_value;
        },
        .Array => |array_info| {
            if (value.type != .array) return error.InvalidType;
            const arr = value.array();
            var result = try allocator.alloc(array_info.child, arr.len());

            // Initialize array with safe defaults
            for (0..arr.len()) |i| {
                result[i] = try convertValue(array_info.child, arr.get(i), allocator);
            }
            return result;
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .Slice => {
                    if (ptr_info.child == u8) {
                        if (value.type != .string) return error.InvalidType;
                        const str = value.string();
                        return try allocator.dupe(u8, str);
                    } else if (ptr_info.child == []const u8) {
                        if (value.type != .array) return error.InvalidType;
                        const arr = value.array();
                        var result = try allocator.alloc([]const u8, arr.len());

                        // Initialize array with safe defaults
                        for (0..arr.len()) |i| {
                            const item = arr.get(i);
                            if (item.type != .string) return error.InvalidType;
                            result[i] = try allocator.dupe(u8, item.string());
                        }
                        return result;
                    } else {
                        @compileError("Unsupported slice type: " ++ @typeName(ptr_info.child));
                    }
                },
                else => return error.UnsupportedType,
            }
        },
        .Int => {
            if (value.type != .integer and value.type != .float) return error.InvalidType;
            return if (value.type == .integer) @intCast(value.integer()) else @intFromFloat(value.float());
        },
        .Float => {
            if (value.type != .integer and value.type != .float) return error.InvalidType;
            return if (value.type == .integer) @floatFromInt(value.integer()) else value.float();
        },
        .Bool => {
            if (value.type != .boolean) return error.InvalidType;
            return value.boolean();
        },
        else => @compileError("Unsupported type: " ++ @typeName(T)),
    }
}

fn parseValue(comptime T: type, allocator: std.mem.Allocator, node: zig_json.Value, unknown_fields: *std.ArrayList([]const u8)) !T {
    switch (@typeInfo(T)) {
        .Struct => {
            var result: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(result, field.name) = @as(field.type, undefined);
            }

            if (node != .object) return error.InvalidType;
            var it = node.object.iterator();
            while (it.next()) |entry| {
                const field_name = entry.key_ptr.*;
                var is_known = false;
                inline for (std.meta.fields(T)) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        @field(result, field.name) = try parseValue(field.type, allocator, entry.value_ptr.*, unknown_fields);
                        is_known = true;
                        break;
                    }
                }
                if (!is_known) {
                    try unknown_fields.append(try allocator.dupe(u8, field_name));
                }
            }

            return result;
        },
        .Optional => |optional_info| {
            if (node == .null) {
                return null;
            }
            return try parseValue(optional_info.child, allocator, node, unknown_fields);
        },
        .Array => |array_info| {
            if (node != .array) return error.InvalidType;
            var result = try allocator.alloc(array_info.child, node.array.items.len);
            for (node.array.items, 0..) |item, i| {
                result[i] = try parseValue(array_info.child, allocator, item, unknown_fields);
            }
            return result;
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .Slice => {
                    if (node != .string) return error.InvalidType;
                    return try allocator.dupe(u8, node.string);
                },
                else => @compileError("Unsupported pointer type"),
            }
        },
        .Int => {
            if (node != .integer) return error.InvalidType;
            return @intCast(node.integer);
        },
        .Float => {
            if (node != .float) return error.InvalidType;
            return @floatCast(node.float);
        },
        .Bool => {
            if (node != .bool) return error.InvalidType;
            return node.bool;
        },
        else => @compileError("Unsupported type: " ++ @typeName(T)),
    }
}

fn skipValue(stream: *zig_json.TokenStream) !void {
    switch (stream.next()) {
        .object_begin => {
            while (true) {
                if (stream.next() == .object_end) break;
                _ = try stream.expectString();
                try skipValue(stream);
            }
        },
        .array_begin => {
            while (true) {
                if (stream.next() == .array_end) break;
                stream.unget();
                try skipValue(stream);
            }
        },
        .string => {},
        .number => {},
        .true, .false => {},
        .null => {},
        else => return error.InvalidJson,
    }
}
