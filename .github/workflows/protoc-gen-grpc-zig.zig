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
    const file_name = "runtime_service_grpc.zig";
    const file_content =
        \\const std = @import("std");
        \\const RuntimeService = @import("runtime_service.zig").RuntimeService;
        \\
        \\pub const RuntimeServiceServer = struct {
        \\    pub fn createPod(request: RuntimeService.CreatePodRequest) !RuntimeService.CreatePodResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn deletePod(request: RuntimeService.DeletePodRequest) !RuntimeService.DeletePodResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn listPods(request: RuntimeService.ListPodsRequest) !RuntimeService.ListPodsResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn createContainer(request: RuntimeService.CreateContainerRequest) !RuntimeService.CreateContainerResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn deleteContainer(request: RuntimeService.DeleteContainerRequest) !RuntimeService.DeleteContainerResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn listContainers(request: RuntimeService.ListContainersRequest) !RuntimeService.ListContainersResponse {
        \\        return error.Unimplemented;
        \\    }
        \\};
        \\
        \\pub const RuntimeServiceClient = struct {
        \\    pub fn createPod(request: RuntimeService.CreatePodRequest) !RuntimeService.CreatePodResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn deletePod(request: RuntimeService.DeletePodRequest) !RuntimeService.DeletePodResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn listPods(request: RuntimeService.ListPodsRequest) !RuntimeService.ListPodsResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn createContainer(request: RuntimeService.CreateContainerRequest) !RuntimeService.CreateContainerResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn deleteContainer(request: RuntimeService.DeleteContainerRequest) !RuntimeService.DeleteContainerResponse {
        \\        return error.Unimplemented;
        \\    }
        \\
        \\    pub fn listContainers(request: RuntimeService.ListContainersRequest) !RuntimeService.ListContainersResponse {
        \\        return error.Unimplemented;
        \\    }
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
