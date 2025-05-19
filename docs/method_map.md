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