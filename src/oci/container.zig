pub const Container = struct {
    allocator: std.mem.Allocator,
    metadata: *ContainerMetadata,
    spec: *Spec,
    state: State,
    pid: ?i32,
    exit_code: ?i32,
    exit_reason: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, metadata: *ContainerMetadata, spec: *Spec) !*Container {
        var self = try allocator.create(Container);
        self.* = .{
            .allocator = allocator,
            .metadata = metadata,
            .spec = spec,
            .state = .created,
            .pid = null,
            .exit_code = null,
            .exit_reason = null,
        };
        return self;
    }

    pub fn resume(self: *Container) !void {
        if (self.state != .paused) {
            return ContainerError.NotPaused;
        }
        self.state = .running;
    }
}; 