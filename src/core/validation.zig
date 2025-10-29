const std = @import("std");
const types = @import("types.zig");

/// Security-focused validation utilities for paths, IDs, and user inputs
pub const SecurityValidation = struct {
    /// Canonicalize and validate that path is within allowed boundaries
    /// Returns canonicalized path or error if outside boundaries
    pub fn validatePath(path: []const u8, allowed_prefixes: []const []const u8, allocator: std.mem.Allocator) ![]u8 {
        // Canonicalize the path
        const resolved = try std.fs.path.resolve(allocator, &[_][]const u8{path});
        defer allocator.free(resolved);
        
        // Check if path is within any allowed prefix
        for (allowed_prefixes) |prefix| {
            if (std.mem.startsWith(u8, resolved, prefix)) {
                return try allocator.dupe(u8, resolved);
            }
        }
        
        return types.Error.ValidationError;
    }
    
    /// Validate container ID format (alphanumeric, hyphens, underscores, 1-64 chars)
    pub fn validateContainerId(id: []const u8) !void {
        if (id.len == 0 or id.len > 64) return types.Error.InvalidInput;
        
        for (id) |c| {
            const is_lower = c >= 'a' and c <= 'z';
            const is_upper = c >= 'A' and c <= 'Z';
            const is_digit = c >= '0' and c <= '9';
            const is_hyphen = c == '-';
            const is_underscore = c == '_';
            
            if (!(is_lower or is_upper or is_digit or is_hyphen or is_underscore)) {
                return types.Error.InvalidInput;
            }
        }
    }
    
    /// Validate VMID (1-999999999)
    pub fn validateVmid(vmid: u32) !void {
        if (vmid == 0 or vmid > 999999999) return types.Error.InvalidInput;
    }
    
    /// Validate hostname (RFC-1123 compliant)
    pub fn validateHostname(name: []const u8) !void {
        if (name.len == 0 or name.len > 253) return types.Error.InvalidInput;
        
        var label_len: usize = 0;
        var i: usize = 0;
        
        while (i < name.len) : (i += 1) {
            const c = name[i];
            if (c == '.') {
                if (label_len == 0 or label_len > 63) return types.Error.InvalidInput;
                label_len = 0;
                continue;
            }
            
            const is_lower = c >= 'a' and c <= 'z';
            const is_upper = c >= 'A' and c <= 'Z';
            const is_digit = c >= '0' and c <= '9';
            const is_hyphen = c == '-';
            
            if (!(is_lower or is_upper or is_digit or is_hyphen)) {
                return types.Error.InvalidInput;
            }
            
            // Labels cannot start or end with hyphen
            if (label_len == 0 and is_hyphen) return types.Error.InvalidInput;
            label_len += 1;
        }
        
        if (label_len == 0 or label_len > 63) return types.Error.InvalidInput;
    }
    
    /// Validate network specification string (safe charset, reasonable length)
    pub fn validateNetSpec(spec: []const u8) !void {
        if (spec.len == 0 or spec.len > 512) return types.Error.InvalidInput;
        
        for (spec) |c| {
            const allowed = (c >= 'a' and c <= 'z') or 
                          (c >= 'A' and c <= 'Z') or 
                          (c >= '0' and c <= '9') or
                          (c == ',') or (c == '=') or (c == ':') or 
                          (c == '.') or (c == '-') or (c == '_') or 
                          (c == '/') or (c == '%');
            
            if (!allowed) return types.Error.InvalidInput;
        }
    }
    
    /// Validate file size limits
    pub fn validateFileSize(size: u64, max_size: u64) !void {
        if (size > max_size) return types.Error.FileTooLarge;
    }
    
    /// Validate memory limits (reasonable bounds)
    pub fn validateMemoryLimit(mb: u64) !void {
        if (mb == 0 or mb > 1024 * 1024) return types.Error.InvalidInput; // 0 < MB < 1TB
    }
    
    /// Validate CPU core limits
    pub fn validateCpuCores(cores: u32) !void {
        if (cores == 0 or cores > 128) return types.Error.InvalidInput;
    }
};

/// Path security utilities
pub const PathSecurity = struct {
    /// Allowed prefixes for different path types
    pub const BUNDLE_PREFIXES = [_][]const u8{
        "/var/lib/nexcage/bundles/",
        "/tmp/nexcage-bundles/",
    };
    
    pub const CONFIG_PREFIXES = [_][]const u8{
        "/etc/nexcage/",
        "/var/lib/nexcage/config/",
    };
    
    pub const LOG_PREFIXES = [_][]const u8{
        "/var/log/nexcage/",
        "/tmp/nexcage-logs/",
    };
    
    pub const TEMPLATE_PREFIXES = [_][]const u8{
        "/var/lib/vz/template/cache/",
        "/tmp/nexcage-template-cache/",
    };
    
    /// Secure path joining that prevents directory traversal
    pub fn secureJoin(allocator: std.mem.Allocator, base: []const u8, relative: []const u8) ![]u8 {
        // Check for directory traversal attempts
        if (std.mem.indexOf(u8, relative, "..") != null) {
            return types.Error.ValidationError;
        }
        
        // Check for absolute paths in relative component
        if (std.fs.path.isAbsolute(relative)) {
            return types.Error.ValidationError;
        }
        
        return try std.fs.path.join(allocator, &[_][]const u8{base, relative});
    }
    
    /// Validate and canonicalize bundle path
    pub fn validateBundlePath(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
        return SecurityValidation.validatePath(path, &BUNDLE_PREFIXES, allocator);
    }
    
    /// Validate and canonicalize config path
    pub fn validateConfigPath(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
        return SecurityValidation.validatePath(path, &CONFIG_PREFIXES, allocator);
    }
    
    /// Validate and canonicalize log path
    pub fn validateLogPath(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
        return SecurityValidation.validatePath(path, &LOG_PREFIXES, allocator);
    }
    
    /// Validate and canonicalize template path
    pub fn validateTemplatePath(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
        return SecurityValidation.validatePath(path, &TEMPLATE_PREFIXES, allocator);
    }
};
