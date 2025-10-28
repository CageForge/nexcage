/// Input validation framework for plugin system
/// 
/// This module provides secure input validation to prevent injection attacks,
/// path traversal, and other security vulnerabilities.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Validation error types
pub const ValidationError = error{
    InvalidContainerId,
    InvalidPath,
    InvalidHostname,
    InvalidEmail,
    InvalidUrl,
    InvalidCommand,
    PathTraversal,
    InputTooLong,
    InvalidCharacters,
    EmptyInput,
};

/// Container ID validation
/// Only allows alphanumeric characters, hyphens, underscores, and dots
/// Length must be between 1 and 128 characters
pub fn validateContainerId(container_id: []const u8) ValidationError!void {
    if (container_id.len == 0) return ValidationError.EmptyInput;
    if (container_id.len > 128) return ValidationError.InputTooLong;
    
    for (container_id) |char| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.' => {},
            else => return ValidationError.InvalidCharacters,
        }
    }
    
    // Cannot start or end with special characters
    if (container_id[0] == '-' or container_id[0] == '_' or container_id[0] == '.') {
        return ValidationError.InvalidContainerId;
    }
    if (container_id[container_id.len - 1] == '-' or 
        container_id[container_id.len - 1] == '_' or 
        container_id[container_id.len - 1] == '.') {
        return ValidationError.InvalidContainerId;
    }
}

/// Hostname validation according to RFC 1123
pub fn validateHostname(hostname: []const u8) ValidationError!void {
    if (hostname.len == 0) return ValidationError.EmptyInput;
    if (hostname.len > 253) return ValidationError.InputTooLong;
    
    var label_start: usize = 0;
    for (hostname, 0..) |char, i| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '-' => {},
            '.' => {
                // Check label length and validity
                const label = hostname[label_start..i];
                try validateHostnameLabel(label);
                label_start = i + 1;
            },
            else => return ValidationError.InvalidCharacters,
        }
    }
    
    // Validate final label
    if (label_start < hostname.len) {
        const label = hostname[label_start..];
        try validateHostnameLabel(label);
    }
}

fn validateHostnameLabel(label: []const u8) ValidationError!void {
    if (label.len == 0 or label.len > 63) return ValidationError.InvalidHostname;
    if (label[0] == '-' or label[label.len - 1] == '-') return ValidationError.InvalidHostname;
}

/// Path validation to prevent directory traversal
pub fn validatePath(path: []const u8, base_path: []const u8, allocator: Allocator) ValidationError![]u8 {
    if (path.len == 0) return ValidationError.EmptyInput;
    if (path.len > 4096) return ValidationError.InputTooLong;
    
    // Check for dangerous patterns
    if (std.mem.indexOf(u8, path, "..") != null) {
        return ValidationError.PathTraversal;
    }
    
    // Resolve path to absolute form
    const resolved_path = std.fs.path.resolve(allocator, &[_][]const u8{path}) catch {
        return ValidationError.InvalidPath;
    };
    errdefer allocator.free(resolved_path);
    
    // Ensure path is within base directory
    if (!std.mem.startsWith(u8, resolved_path, base_path)) {
        allocator.free(resolved_path);
        return ValidationError.PathTraversal;
    }
    
    return resolved_path;
}

/// Command argument validation
/// Ensures command arguments don't contain shell injection patterns
pub fn validateCommandArgs(args: []const []const u8) ValidationError!void {
    for (args) |arg| {
        if (arg.len > 1024) return ValidationError.InputTooLong;
        
        // Check for shell metacharacters that could be used for injection
        for (arg) |char| {
            switch (char) {
                ';', '&', '|', '`', '$', '(', ')', '{', '}', '[', ']', 
                '<', '>', '"', '\'', '\\', '\n', '\r', '\t' => {
                    return ValidationError.InvalidCommand;
                },
                else => {},
            }
        }
    }
}

/// Sanitize string by removing or escaping dangerous characters
pub fn sanitizeString(input: []const u8, allocator: Allocator) Allocator.Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    for (input) |char| {
        switch (char) {
            // Allow alphanumeric and safe punctuation
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.', ':', '/', '@' => {
                try result.append(char);
            },
            ' ' => try result.append('_'),
            // Skip dangerous characters
            else => {},
        }
    }
    
    return result.toOwnedSlice();
}

/// Email validation (basic)
pub fn validateEmail(email: []const u8) ValidationError!void {
    if (email.len == 0) return ValidationError.EmptyInput;
    if (email.len > 254) return ValidationError.InputTooLong;
    
    const at_pos = std.mem.indexOf(u8, email, "@") orelse return ValidationError.InvalidEmail;
    if (at_pos == 0 or at_pos == email.len - 1) return ValidationError.InvalidEmail;
    
    const local_part = email[0..at_pos];
    const domain_part = email[at_pos + 1..];
    
    if (local_part.len == 0 or local_part.len > 64) return ValidationError.InvalidEmail;
    if (domain_part.len == 0 or domain_part.len > 253) return ValidationError.InvalidEmail;
    
    // Basic character validation
    for (local_part) |char| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '_', '+' => {},
            else => return ValidationError.InvalidEmail,
        }
    }
    
    try validateHostname(domain_part);
}

/// URL validation (basic)
pub fn validateUrl(url: []const u8) ValidationError!void {
    if (url.len == 0) return ValidationError.EmptyInput;
    if (url.len > 2048) return ValidationError.InputTooLong;
    
    // Must start with http:// or https://
    if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) {
        return ValidationError.InvalidUrl;
    }
    
    // Basic character validation
    for (url) |char| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '_', '~', ':', '/', '?', '#', 
            '[', ']', '@', '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=' => {},
            '%' => {}, // URL encoding allowed
            else => return ValidationError.InvalidUrl,
        }
    }
}

/// Validate file size limits
pub fn validateFileSize(size: u64, max_size: u64) ValidationError!void {
    if (size > max_size) return ValidationError.InputTooLong;
}

/// Validate memory size specification (e.g., "512M", "2G")
pub fn validateMemorySize(memory_spec: []const u8) ValidationError!u64 {
    if (memory_spec.len == 0) return ValidationError.EmptyInput;
    if (memory_spec.len > 16) return ValidationError.InputTooLong;
    
    const last_char = memory_spec[memory_spec.len - 1];
    const multiplier: u64 = switch (last_char) {
        'B', 'b' => 1,
        'K', 'k' => 1024,
        'M', 'm' => 1024 * 1024,
        'G', 'g' => 1024 * 1024 * 1024,
        '0'...'9' => 1, // No suffix means bytes
        else => return ValidationError.InvalidCharacters,
    };
    
    const number_part = if (multiplier == 1 and last_char >= '0' and last_char <= '9')
        memory_spec
    else
        memory_spec[0..memory_spec.len - 1];
    
    const number = std.fmt.parseInt(u64, number_part, 10) catch {
        return ValidationError.InvalidCharacters;
    };
    
    // Check for overflow
    if (number > std.math.maxInt(u64) / multiplier) {
        return ValidationError.InputTooLong;
    }
    
    return number * multiplier;
}

/// Validate CPU specification (percentage or count)
pub fn validateCpuSpec(cpu_spec: []const u8) ValidationError!f64 {
    if (cpu_spec.len == 0) return ValidationError.EmptyInput;
    if (cpu_spec.len > 16) return ValidationError.InputTooLong;
    
    const value = std.fmt.parseFloat(f64, cpu_spec) catch {
        return ValidationError.InvalidCharacters;
    };
    
    if (value < 0 or value > 100) {
        return ValidationError.InvalidCharacters;
    }
    
    return value;
}

/// Test suite
const testing = std.testing;

test "validateContainerId" {
    // Valid container IDs
    try validateContainerId("test-container");
    try validateContainerId("web-server-01");
    try validateContainerId("app.backend");
    try validateContainerId("service_worker");
    try validateContainerId("nginx123");
    
    // Invalid container IDs
    try testing.expectError(ValidationError.EmptyInput, validateContainerId(""));
    try testing.expectError(ValidationError.InvalidContainerId, validateContainerId("-invalid"));
    try testing.expectError(ValidationError.InvalidContainerId, validateContainerId("invalid-"));
    try testing.expectError(ValidationError.InvalidCharacters, validateContainerId("test@container"));
    try testing.expectError(ValidationError.InvalidCharacters, validateContainerId("test container"));
    
    // Too long
    const long_name = "a" ** 129;
    try testing.expectError(ValidationError.InputTooLong, validateContainerId(long_name));
}

test "validateHostname" {
    // Valid hostnames
    try validateHostname("example.com");
    try validateHostname("web-server");
    try validateHostname("api.service.local");
    try validateHostname("host123");
    
    // Invalid hostnames
    try testing.expectError(ValidationError.EmptyInput, validateHostname(""));
    try testing.expectError(ValidationError.InvalidHostname, validateHostname("-invalid"));
    try testing.expectError(ValidationError.InvalidCharacters, validateHostname("host@name"));
    
    // Too long
    const long_hostname = "a" ** 254;
    try testing.expectError(ValidationError.InputTooLong, validateHostname(long_hostname));
}

test "validateCommandArgs" {
    // Valid command args
    try validateCommandArgs(&[_][]const u8{ "ls", "-la", "/tmp" });
    try validateCommandArgs(&[_][]const u8{ "echo", "hello world" });
    
    // Invalid command args (shell injection)
    try testing.expectError(ValidationError.InvalidCommand, validateCommandArgs(&[_][]const u8{ "ls", "; rm -rf /" }));
    try testing.expectError(ValidationError.InvalidCommand, validateCommandArgs(&[_][]const u8{ "echo", "$(whoami)" }));
    try testing.expectError(ValidationError.InvalidCommand, validateCommandArgs(&[_][]const u8{ "cat", "/etc/passwd | grep root" }));
}

test "validateMemorySize" {
    try testing.expect((try validateMemorySize("1024")) == 1024);
    try testing.expect((try validateMemorySize("512M")) == 512 * 1024 * 1024);
    try testing.expect((try validateMemorySize("2G")) == 2 * 1024 * 1024 * 1024);
    try testing.expect((try validateMemorySize("128K")) == 128 * 1024);
    
    try testing.expectError(ValidationError.EmptyInput, validateMemorySize(""));
    try testing.expectError(ValidationError.InvalidCharacters, validateMemorySize("invalid"));
    try testing.expectError(ValidationError.InvalidCharacters, validateMemorySize("512X"));
}

test "validateCpuSpec" {
    try testing.expect((try validateCpuSpec("50")) == 50.0);
    try testing.expect((try validateCpuSpec("0.5")) == 0.5);
    try testing.expect((try validateCpuSpec("100")) == 100.0);
    
    try testing.expectError(ValidationError.EmptyInput, validateCpuSpec(""));
    try testing.expectError(ValidationError.InvalidCharacters, validateCpuSpec("150"));
    try testing.expectError(ValidationError.InvalidCharacters, validateCpuSpec("-10"));
    try testing.expectError(ValidationError.InvalidCharacters, validateCpuSpec("invalid"));
}