const std = @import("std");

pub fn getString(value: std.json.Value, field: []const u8) ![]const u8 {
    const obj = value.object;
    const field_value = obj.get(field) orelse return error.MissingField;
    return switch (field_value) {
        .string => |str| str,
        else => error.InvalidType,
    };
}

pub fn getOptionalString(value: std.json.Value, field: []const u8) !?[]const u8 {
    const obj = value.object;
    const field_value = obj.get(field) orelse return null;
    return switch (field_value) {
        .string => |str| str,
        else => error.InvalidType,
    };
}

pub fn getBool(value: std.json.Value, field: []const u8) !bool {
    const obj = value.object;
    const field_value = obj.get(field) orelse return error.MissingField;
    return switch (field_value) {
        .bool => |b| b,
        else => error.InvalidType,
    };
}

pub fn getOptionalBool(value: std.json.Value, field: []const u8) !?bool {
    const obj = value.object;
    const field_value = obj.get(field) orelse return null;
    return switch (field_value) {
        .bool => |b| b,
        else => error.InvalidType,
    };
}

pub fn getInt(value: std.json.Value, field: []const u8) !i64 {
    const obj = value.object;
    const field_value = obj.get(field) orelse return error.MissingField;
    return switch (field_value) {
        .integer => |i| i,
        else => error.InvalidType,
    };
}

pub fn getOptionalInt(value: std.json.Value, field: []const u8) !?i64 {
    const obj = value.object;
    const field_value = obj.get(field) orelse return null;
    return switch (field_value) {
        .integer => |i| i,
        else => error.InvalidType,
    };
}

pub fn getObject(value: std.json.Value, field: []const u8) !std.json.Value {
    const obj = value.object;
    const field_value = obj.get(field) orelse return error.MissingField;
    return switch (field_value) {
        .object => field_value,
        else => error.InvalidType,
    };
}

pub fn getOptionalObject(value: std.json.Value, field: []const u8) !?std.json.Value {
    const obj = value.object;
    const field_value = obj.get(field) orelse return null;
    return switch (field_value) {
        .object => field_value,
        else => error.InvalidType,
    };
}

pub fn getArray(value: std.json.Value, field: []const u8) !std.json.Value {
    const obj = value.object;
    const field_value = obj.get(field) orelse return error.MissingField;
    return switch (field_value) {
        .array => field_value,
        else => error.InvalidType,
    };
}

pub fn getOptionalArray(value: std.json.Value, field: []const u8) !?std.json.Value {
    const obj = value.object;
    const field_value = obj.get(field) orelse return null;
    return switch (field_value) {
        .array => field_value,
        else => error.InvalidType,
    };
} 