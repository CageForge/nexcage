const std = @import("std");
const testing = std.testing;
const core = @import("core");

test "ErrorContext creation and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = try core.errors.createErrorContext(allocator, "Test error message", .{});
    defer context.deinit();

    try testing.expectEqualStrings("Test error message", context.message);
    try testing.expect(context.source == null);
    try testing.expect(context.line == null);
}

test "ErrorContext with source location" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = try core.errors.createErrorContextWithSource(
        allocator,
        "Error in {s}",
        .{"test.zig"},
        "test.zig",
        42,
        10,
    );
    defer context.deinit();

    try testing.expectEqualStrings("Error in test.zig", context.message);
    try testing.expect(context.source != null);
    if (context.source) |src| {
        try testing.expectEqualStrings("test.zig", src);
    }
    try testing.expect(context.line == 42);
    try testing.expect(context.column == 10);
}

test "ErrorContextBuilder pattern" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = try core.errors.ErrorContextBuilder.init(allocator, "Builder test: {d}", .{42});
    defer builder.deinit();

    try builder.withSource("builder_test.zig");
    builder.withLocation(100, 5);
    
    const context = builder.build();
    defer context.deinit();

    try testing.expectEqualStrings("Builder test: 42", context.message);
    try testing.expect(context.source != null);
    if (context.source) |src| {
        try testing.expectEqualStrings("builder_test.zig", src);
    }
    try testing.expect(context.line == 100);
    try testing.expect(context.column == 5);
}

test "ContextualError creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context = try core.errors.createErrorContext(allocator, "Contextual error", .{});
    defer context.deinit();

    const contextual_error = core.errors.ContextualError{
        .error_type = types.Error.ValidationError,
        .context = context,
        .cause = null,
    };

    try testing.expect(contextual_error.error_type == .ValidationError);
    try testing.expect(contextual_error.cause == null);
}

test "ErrorWithContext simple error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const simple_error = core.errors.ErrorWithContext{ .simple = types.Error.InvalidConfig };
    
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try simple_error.formatError(buffer.writer());
    
    // Simple error should format as just the error type
    try testing.expect(buffer.items.len > 0);
}

test "ErrorWithContext contextual error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context = try core.errors.createErrorContextWithSource(
        allocator,
        "Validation failed",
        .{},
        "test.zig",
        10,
        5,
    );
    defer context.deinit();

    const contextual = core.errors.ErrorWithContext{
        .contextual = .{
            .error_type = types.Error.ValidationError,
            .context = context,
        },
    };
    
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try contextual.formatError(buffer.writer());
    
    // Should contain error type and message
    const output = try buffer.toOwnedSlice();
    defer allocator.free(output);
    
    try testing.expect(std.mem.indexOf(u8, output, "ValidationError") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Validation failed") != null);
}

