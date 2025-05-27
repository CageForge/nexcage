# Method Map and Interactions

## Module `config`
- **Config**
  - `init(allocator: std.mem.Allocator, logger_ctx: *logger.LogContext) !Config`  
    Initializes the configuration, including settings for runtime, proxmox, storage, network, and container.
  - `deinit(self: *Config) void`  
    Frees resources by calling deinit for all sub-configurations.
  - `fromJson(allocator: std.mem.Allocator, json_config: JsonConfig, logger_ctx: *logger.LogContext) !Config`  
    Creates a configuration from JSON data.
  - `getContainerType(self: *Config, container_name: []const u8) container.ContainerType`  
    Determines the container type based on its name (crun or lxc).
  - `matchesPattern(_: *Config, name: []const u8, pattern: []const u8) bool`  
    Checks if the container name matches the given pattern.

## Module `container`
- **Container**
  - `init(allocator: Allocator, config: ContainerConfig) !*Container`  
    Initializes a container with the given configuration.
  - `deinit(self: *Container) void`  
    Frees container resources.
  - `start(self: *Container) !void`  
    Starts the container, calling the appropriate method (startLxc or startCrun) based on its type.
  - `stop(self: *Container) !void`  
    Stops the container, calling the appropriate method (stopLxc or stopCrun) based on its type.
  - `getState(self: *Container) ContainerState`  
    Returns the current state of the container.
  - `startLxc(self: *Container) !void`  
    Starts an LXC container (stub).
  - `startCrun(self: *Container) !void`  
    Starts a crun container (stub).
  - `stopLxc(self: *Container) !void`  
    Stops an LXC container (stub).
  - `stopCrun(self: *Container) !void`  
    Stops a crun container (stub).

- **createContainer(allocator: Allocator, config: *Config, container_config: ContainerConfig) !*Container**  
  Creates a container with the given configuration, determining its type based on its name.

## Module `oci`
- **OCIRuntime**
  - `init(allocator: std.mem.Allocator, config: *Config) !*OCIRuntime`  
    Initializes the OCI runtime with the given configuration.
  - `deinit(self: *OCIRuntime) void`  
    Frees OCI runtime resources.
  - `createContainer(self: *OCIRuntime, config: *types.ContainerConfig) !*container.Container`  
    Creates a container via the OCI runtime, using the given configuration.

- **Container**
  - `init(allocator: std.mem.Allocator, metadata: *ContainerMetadata, spec: *Spec) !*Container`  
    Initializes an OCI container with metadata and specification.
  - `resume(self: *Container) !void`  
    Resumes the container from a paused state; if not paused, returns an error.

## Interactions
- **Config** is used to determine the container type (`getContainerType`), which is then used in `createContainer` to create the appropriate container (LXC or crun).
- **Container** uses the `start` and `stop` methods, which call the appropriate methods based on the container type.
- **OCIRuntime** is used to create containers via the OCI specification, calling `createContainer`, which in turn uses `container.createContainer`.

## Notes
- The methods `startLxc`, `startCrun`, `stopLxc`, and `stopCrun` are stubs and require implementation.
- The `resume` function in the OCI container checks the container's state before resuming.

## Runtime

### Інтерфейс

```zig
pub const Runtime = struct {
    pub fn init(allocator: std.mem.Allocator, runtime_type: RuntimeType) !Runtime
    pub fn deinit(self: *Runtime) void
    pub fn create(self: *Runtime, spec: *Spec) !void
    pub fn start(self: *Runtime, id: []const u8) !void
    pub fn kill(self: *Runtime, id: []const u8, signal: u32) !void
    pub fn delete(self: *Runtime, id: []const u8) !void
}
```

### runc

```zig
pub const RuncRuntime = struct {
    pub fn init(allocator: std.mem.Allocator) !RuncRuntime
    pub fn deinit(self: *RuncRuntime) void
    pub fn create(self: *RuncRuntime, spec: *Spec) !void
    pub fn start(self: *RuncRuntime, id: []const u8) !void
    pub fn kill(self: *RuncRuntime, id: []const u8, signal: u32) !void
    pub fn delete(self: *RuncRuntime, id: []const u8) !void
}
```

### crun

```zig
pub const CrunRuntime = struct {
    pub fn init(allocator: std.mem.Allocator) !CrunRuntime
    pub fn deinit(self: *CrunRuntime) void
    pub fn create(self: *CrunRuntime, spec: *Spec) !void
    pub fn start(self: *CrunRuntime, id: []const u8) !void
    pub fn kill(self: *CrunRuntime, id: []const u8, signal: u32) !void
    pub fn delete(self: *CrunRuntime, id: []const u8) !void
}
```

## Контейнер

```zig
pub const Container = struct {
    pub fn init(allocator: std.mem.Allocator, config: *Config, spec: *Spec, id: []const u8) !Container
    pub fn deinit(self: *Container) void
    pub fn create(self: *Container) !void
    pub fn start(self: *Container) !void
    pub fn kill(self: *Container, signal: u32) !void
    pub fn delete(self: *Container) !void
}
```

## Конфігурація

```zig
pub const Config = struct {
    pub fn init(allocator: std.mem.Allocator) !Config
    pub fn deinit(self: *Config) void
    pub fn setRuntimeType(self: *Config, runtime_type: RuntimeType) void
    pub fn setRuntimePath(self: *Config, path: []const u8) !void
    pub fn getRuntimePath(self: *Config) ![]const u8
}
```

## Специфікація

```zig
pub const Spec = struct {
    pub fn init(allocator: std.mem.Allocator) !Spec
    pub fn deinit(self: *Spec) void
}
```

## Тести

```zig
test "runtime init"
test "runtime create"
test "runtime start"
test "runtime kill"
test "runtime delete"
``` 