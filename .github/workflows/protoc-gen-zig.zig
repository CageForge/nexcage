const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Read request from stdin
    const request = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(request);

    // Write response to stdout
    const file_name = "runtime_service.zig";
    const file_content =
        \\const std = @import("std");
        \\
        \\pub const RuntimeService = struct {
        \\    pub const CreatePodRequest = struct {
        \\        name: []const u8,
        \\        namespace: []const u8,
        \\        containers: []const ContainerSpec,
        \\    };
        \\
        \\    pub const CreatePodResponse = struct {
        \\        pod_id: []const u8,
        \\    };
        \\
        \\    pub const DeletePodRequest = struct {
        \\        pod_id: []const u8,
        \\    };
        \\
        \\    pub const DeletePodResponse = struct {};
        \\
        \\    pub const ListPodsRequest = struct {};
        \\
        \\    pub const ListPodsResponse = struct {
        \\        pods: []const Pod,
        \\    };
        \\
        \\    pub const CreateContainerRequest = struct {
        \\        name: []const u8,
        \\        image: []const u8,
        \\        command: []const []const u8,
        \\        args: []const []const u8,
        \\        env: []const EnvVar,
        \\    };
        \\
        \\    pub const CreateContainerResponse = struct {
        \\        container_id: []const u8,
        \\    };
        \\
        \\    pub const DeleteContainerRequest = struct {
        \\        container_id: []const u8,
        \\    };
        \\
        \\    pub const DeleteContainerResponse = struct {};
        \\
        \\    pub const ListContainersRequest = struct {};
        \\
        \\    pub const ListContainersResponse = struct {
        \\        containers: []const Container,
        \\    };
        \\
        \\    pub const Pod = struct {
        \\        id: []const u8,
        \\        name: []const u8,
        \\        namespace: []const u8,
        \\        status: PodStatus,
        \\        containers: []const Container,
        \\    };
        \\
        \\    pub const Container = struct {
        \\        id: []const u8,
        \\        name: []const u8,
        \\        status: ContainerStatus,
        \\        spec: ContainerSpec,
        \\    };
        \\
        \\    pub const ContainerSpec = struct {
        \\        name: []const u8,
        \\        image: []const u8,
        \\        command: []const []const u8,
        \\        args: []const []const u8,
        \\        env: []const EnvVar,
        \\    };
        \\
        \\    pub const EnvVar = struct {
        \\        name: []const u8,
        \\        value: []const u8,
        \\    };
        \\
        \\    pub const PodStatus = enum {
        \\        unknown,
        \\        pending,
        \\        running,
        \\        succeeded,
        \\        failed,
        \\    };
        \\
        \\    pub const ContainerStatus = enum {
        \\        unknown,
        \\        created,
        \\        running,
        \\        stopped,
        \\        failed,
        \\    };
        \\};
        \\
    ;

    // Write the number of files (1)
    try stdout.writeIntLittle(u32, 1);

    // Write file name length and content
    try stdout.writeIntLittle(u32, @intCast(file_name.len));
    try stdout.writeAll(file_name);

    // Write file content length and content
    try stdout.writeIntLittle(u32, @intCast(file_content.len));
    try stdout.writeAll(file_content);
}
