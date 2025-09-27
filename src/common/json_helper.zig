const std = @import("std");
const zig_json = @import("zig_json");

pub fn getString(value: zig_json.JsonValue, field: []const u8) ![]const u8 {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return error.MissingField;
    if (field_value.type != .string) return error.InvalidType;
    return field_value.string();
}

pub fn getOptionalString(value: zig_json.JsonValue, field: []const u8) !?[]const u8 {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return null;
    if (field_value.type != .string) return error.InvalidType;
    return field_value.string();
}

pub fn getBool(value: zig_json.JsonValue, field: []const u8) !bool {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return error.MissingField;
    if (field_value.type != .bool) return error.InvalidType;
    return field_value.bool();
}

pub fn getOptionalBool(value: zig_json.JsonValue, field: []const u8) !?bool {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return null;
    if (field_value.type != .bool) return error.InvalidType;
    return field_value.bool();
}

pub fn getInt(value: zig_json.JsonValue, field: []const u8) !i64 {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return error.MissingField;
    if (field_value.type != .integer) return error.InvalidType;
    return field_value.integer();
}

pub fn getOptionalInt(value: zig_json.JsonValue, field: []const u8) !?i64 {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return null;
    if (field_value.type != .integer) return error.InvalidType;
    return field_value.integer();
}

pub fn getObject(value: zig_json.JsonValue, field: []const u8) !zig_json.JsonValue {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return error.MissingField;
    if (field_value.type != .object) return error.InvalidType;
    return field_value;
}

pub fn getOptionalObject(value: zig_json.JsonValue, field: []const u8) !?zig_json.JsonValue {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return null;
    if (field_value.type != .object) return error.InvalidType;
    return field_value;
}

pub fn getArray(value: zig_json.JsonValue, field: []const u8) !zig_json.JsonValue {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return error.MissingField;
    if (field_value.type != .array) return error.InvalidType;
    return field_value;
}

pub fn getOptionalArray(value: zig_json.JsonValue, field: []const u8) !?zig_json.JsonValue {
    if (value.type != .object) return error.InvalidJson;
    const obj = value.object();
    const field_value = obj.get(field) orelse return null;
    if (field_value.type != .array) return error.InvalidType;
    return field_value;
}
