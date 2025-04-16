const std = @import("std");

/// Генератор коду Zig для Protocol Buffers
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Читаємо запит з stdin
    const request = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(request);

    // Записуємо відповідь в stdout
    const file_name = "runtime_service.zig";
    const file_content =
        \\const std = @import("std");
        \\
        \\/// Сервіс для роботи з контейнерами
        \\pub const RuntimeService = struct {
        \\    /// Запит на створення поду
        \\    pub const CreatePodRequest = struct {
        \\        name: []const u8,
        \\        namespace: []const u8,
        \\        containers: []const ContainerSpec,
        \\    };
        \\
        \\    /// Відповідь на створення поду
        \\    pub const CreatePodResponse = struct {
        \\        pod_id: []const u8,
        \\    };
        \\
        \\    /// Запит на видалення поду
        \\    pub const DeletePodRequest = struct {
        \\        pod_id: []const u8,
        \\    };
        \\
        \\    /// Відповідь на видалення поду
        \\    pub const DeletePodResponse = struct {};
        \\
        \\    /// Запит на отримання списку подів
        \\    pub const ListPodsRequest = struct {};
        \\
        \\    /// Відповідь зі списком подів
        \\    pub const ListPodsResponse = struct {
        \\        pods: []const Pod,
        \\    };
        \\
        \\    /// Запит на створення контейнера
        \\    pub const CreateContainerRequest = struct {
        \\        name: []const u8,
        \\        image: []const u8,
        \\        command: []const []const u8,
        \\        args: []const []const u8,
        \\        env: []const EnvVar,
        \\    };
        \\
        \\    /// Відповідь на створення контейнера
        \\    pub const CreateContainerResponse = struct {
        \\        container_id: []const u8,
        \\    };
        \\
        \\    /// Запит на видалення контейнера
        \\    pub const DeleteContainerRequest = struct {
        \\        container_id: []const u8,
        \\    };
        \\
        \\    /// Відповідь на видалення контейнера
        \\    pub const DeleteContainerResponse = struct {};
        \\
        \\    /// Запит на отримання списку контейнерів
        \\    pub const ListContainersRequest = struct {};
        \\
        \\    /// Відповідь зі списком контейнерів
        \\    pub const ListContainersResponse = struct {
        \\        containers: []const Container,
        \\    };
        \\};
    ;

    try stdout.writer().print("{s}\n", .{file_content});
}
