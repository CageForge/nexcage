const std = @import("std");

// Global types and structures accessible to all modules

/// Global error types
pub const Error = error{
    InvalidConfig,
    NetworkError,
    StorageError,
    RuntimeError,
    ValidationError,
    NotFound,
    FileNotFound,
    PermissionDenied,
    Timeout,
    OutOfMemory,
    InvalidInput,
    OperationFailed,
    UnsupportedOperation,
    CopyFailed,
    RootfsNotFound,
    EmptyRootfs,
    ArchiveCreationFailed,
};

/// Sandbox configuration
pub const SandboxConfig = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    runtime_type: RuntimeType,
    image: ?[]const u8 = null,
    resources: ?ResourceLimits = null,
    security: ?SecurityConfig = null,
    network: ?NetworkConfig = null,
    storage: ?StorageConfig = null,
    /// `create --node <name>`: the cluster node to make the container on.
    /// Borrowed from the caller's options, which outlive the create.
    node: ?[]const u8 = null,
    /// `create --storage <name>`: the Proxmox storage a registry image is
    /// found on, or pulled to. Borrowed the same way. Not the root filesystem
    /// storage -- that is `proxmox.storage` -- but where templates live.
    template_storage: ?[]const u8 = null,
    /// `create --memory`, `--cores`, `--ip` and the rest (#308): what pct
    /// create is usually given. Borrowed the same way.
    pve: ProxmoxCreateOptions = .{},

    pub fn deinit(self: *SandboxConfig) void {
        self.allocator.free(self.name);
        if (self.resources) |*r| r.deinit();
        if (self.security) |*s| s.deinit();
        if (self.network) |*n| n.deinit(self.allocator);
        if (self.storage) |*s| s.deinit(self.allocator);
    }
};

/// What `create` says to pct beyond the image and the name, on the Proxmox LXC
/// backend (#308). Each maps onto one pct option, through `pct create` here
/// and the node's API for `--node`; nothing here means pct's default.
pub const ProxmoxCreateOptions = struct {
    /// `--memory`, `--memory-swap`, `--cpu-quota`, `--cpu-period` and
    /// `--cpu-share`, as `update` takes them and in its units: bytes,
    /// microseconds, cgroup v1 shares. Turned into pct's terms the way
    /// `update` turns them.
    limits: []const ResourceUpdate = &.{},
    /// pct's --cores
    cores: ?[]const u8 = null,
    /// net0's ip=, gw= and tag=, and firewall=1
    ip: ?[]const u8 = null,
    gw: ?[]const u8 = null,
    vlan: ?[]const u8 = null,
    firewall: bool = false,
    /// pct's --onboot 1 and --tags
    onboot: bool = false,
    tags: ?[]const u8 = null,
    /// `--mp <spec>`, in the order given: pct's mp0, mp1, ... verbatim
    mount_points: []const []const u8 = &.{},

    /// The flag of the first option given, for a backend that takes none.
    pub fn firstGiven(self: ProxmoxCreateOptions) ?[]const u8 {
        if (self.limits.len > 0) return "--memory and the other limits";
        if (self.cores != null) return "--cores";
        if (self.ip != null) return "--ip";
        if (self.gw != null) return "--gw";
        if (self.vlan != null) return "--vlan";
        if (self.firewall) return "--firewall";
        if (self.onboot) return "--onboot";
        if (self.tags != null) return "--tags";
        if (self.mount_points.len > 0) return "--mp";
        return null;
    }
};

/// Runtime type enumeration
pub const RuntimeType = enum {
    lxc,
    crun,
    proxmox_lxc,
};

/// Container type enumeration
pub const ContainerType = enum {
    lxc,
    crun,
    proxmox_lxc,
};

/// Resource limits
pub const ResourceLimits = struct {
    memory: ?u64 = null,
    cpu: ?f64 = null,
    disk: ?u64 = null,
    network_bandwidth: ?u64 = null,

    pub fn deinit(self: *ResourceLimits) void {
        _ = self;
    }
};

/// Security configuration
pub const SecurityConfig = struct {
    seccomp: ?bool = null,
    apparmor: ?bool = null,
    capabilities: ?[]const []const u8 = null,
    read_only: ?bool = null,

    pub fn deinit(self: *SecurityConfig) void {
        if (self.capabilities) |caps| {
            for (caps) |cap| {
                // Note: capabilities are not allocated, just referenced
                _ = cap;
            }
        }
    }
};

/// Network configuration
pub const NetworkConfig = struct {
    bridge: ?[]const u8 = null,
    ip: ?[]const u8 = null,
    gateway: ?[]const u8 = null,
    dns: ?[]const []const u8 = null,
    port_mappings: ?[]const PortMapping = null,

    pub fn deinit(self: *NetworkConfig, allocator: std.mem.Allocator) void {
        if (self.bridge) |b| allocator.free(b);
        if (self.ip) |i| allocator.free(i);
        if (self.gateway) |g| allocator.free(g);
        if (self.dns) |d| {
            for (d) |dns| {
                // DNS entries are not allocated, just referenced
                _ = dns;
            }
        }
        if (self.port_mappings) |pm| {
            for (pm) |mapping| {
                mapping.deinit(allocator);
            }
            allocator.free(pm);
        }
    }
};

/// Port mapping
pub const PortMapping = struct {
    host_port: u16,
    container_port: u16,
    protocol: []const u8,

    pub fn deinit(self: *const PortMapping, allocator: std.mem.Allocator) void {
        // protocol is not allocated, just referenced
        _ = self;
        _ = allocator;
    }
};

/// Storage configuration
pub const StorageConfig = struct {
    rootfs: ?[]const u8 = null,
    volumes: ?[]const Volume = null,
    tmpfs: ?[]const TmpfsMount = null,

    pub fn deinit(self: *StorageConfig, allocator: std.mem.Allocator) void {
        if (self.rootfs) |r| allocator.free(r);
        if (self.volumes) |v| {
            for (v) |*vol| {
                vol.deinit(allocator);
            }
            allocator.free(v);
        }
        if (self.tmpfs) |t| {
            for (t) |*tmp| {
                tmp.deinit(allocator);
            }
            allocator.free(t);
        }
    }
};

/// Volume mount
pub const Volume = struct {
    source: []const u8,
    destination: []const u8,
    read_only: bool = false,
    options: ?[]const u8 = null,

    pub fn deinit(self: *Volume, allocator: std.mem.Allocator) void {
        // source, destination, options are not allocated, just referenced
        _ = self;
        _ = allocator;
    }
};

/// Tmpfs mount
pub const TmpfsMount = struct {
    destination: []const u8,
    size: ?u64 = null,
    mode: ?u32 = null,

    pub fn deinit(self: *TmpfsMount, allocator: std.mem.Allocator) void {
        // destination is not allocated, just referenced
        _ = self;
        _ = allocator;
    }
};

/// Command enumeration
pub const Command = enum {
    create,
    start,
    stop,
    delete,
    list,
    info,
    exec,
    run,
    help,
    version,
    state,
    kill,
    features,
    ps,
    images,
    pull,
    rmi,
    pause,
    resume_,
    update,
    /// Snapshots through Proxmox VE, with pct's names
    snapshot,
    snapshots,
    rollback,
    delsnapshot,
};

/// One resource setting for `update`, in crun's own vocabulary: the section
/// and field of the runtime-spec `linux.resources` object it changes, so what
/// a caller can say to crun it can say here. `value` is owned.
pub const ResourceUpdate = struct {
    section: []const u8,
    name: []const u8,
    value: []const u8,
    /// A number (`memory.limit`) rather than a string (`cpu.cpus`)
    numeric: bool,
};

/// Runtime options
pub const RuntimeOptions = struct {
    allocator: std.mem.Allocator,
    command: Command,
    container_id: ?[]const u8 = null,
    image: ?[]const u8 = null,
    runtime_type: ?RuntimeType = null,
    config_file: ?[]const u8 = null,
    verbose: bool = false,
    debug: bool = false,
    help: bool = false,
    detach: bool = false,
    /// `delete --force`: stop a running container instead of refusing
    force: bool = false,
    /// `kill --all`: signal every process, not only the init
    all: bool = false,
    /// `create --console-socket <path>`: where the runtime sends the master
    /// end of the container's pty, over SCM_RIGHTS. A container engine passes
    /// it whenever the spec asks for a terminal.
    console_socket: ?[]const u8 = null,
    /// `create --pid-file <path>`: where the runtime writes the container
    /// process's pid, so the caller can find it without parsing `state`.
    pid_file: ?[]const u8 = null,
    /// `--systemd-cgroup`: manage cgroups through systemd. containerd sends it
    /// when configured with SystemdCgroup, and libcrun has the field for it.
    systemd_cgroup: bool = false,
    interactive: bool = false,
    tty: bool = false,
    user: ?[]const u8 = null,
    workdir: ?[]const u8 = null,
    env: ?[]const []const u8 = null,
    args: ?[]const []const u8 = null,
    /// `exec --process <file>`: a file holding an OCI process spec, which
    /// is the shape a container engine sends an exec in.
    process_file: ?[]const u8 = null,
    /// `ps --format <json|table>`. containerd asks for json.
    format: ?[]const u8 = null,
    /// `create --node <name>`: which node of the Proxmox cluster to create on,
    /// and which node `images` and `pull` act on.
    node: ?[]const u8 = null,
    /// `pull --storage <name>`: the Proxmox storage to put the template on.
    storage_name: ?[]const u8 = null,
    /// `pull --filename <name>`: the destination file name, which Proxmox
    /// normalises.
    filename: ?[]const u8 = null,
    /// `update --resources <file>`: a runtime-spec `linux.resources` object,
    /// which is how a container engine sends a resize. `-` is stdin.
    resources_path: ?[]const u8 = null,
    /// `update --memory <n>`, `--cpu-quota <n>` and the rest, as runc and
    /// crun name them; each is one setting, in the order given.
    resource_updates: ?[]ResourceUpdate = null,
    /// `create`'s pct options (#308) other than the limits, which arrive in
    /// resource_updates as for update. The strings and the mount point list
    /// are owned.
    create_options: ProxmoxCreateOptions = .{},
    /// `snapshot --description <text>`: Proxmox's note on the snapshot.
    description: ?[]const u8 = null,
    /// `rollback --start`: start the container once it is back at the
    /// snapshot, as pct's own flag does.
    start_after_rollback: bool = false,

    pub fn deinit(self: *RuntimeOptions) void {
        if (self.container_id) |id| self.allocator.free(id);
        if (self.image) |img| self.allocator.free(img);
        if (self.config_file) |cfg| self.allocator.free(cfg);
        if (self.user) |u| self.allocator.free(u);
        if (self.workdir) |wd| self.allocator.free(wd);
        if (self.process_file) |pf| self.allocator.free(pf);
        if (self.format) |f| self.allocator.free(f);
        if (self.node) |n| self.allocator.free(n);
        if (self.storage_name) |sn| self.allocator.free(sn);
        if (self.filename) |f| self.allocator.free(f);
        if (self.resources_path) |rp| self.allocator.free(rp);
        if (self.description) |d| self.allocator.free(d);
        if (self.resource_updates) |ups| {
            for (ups) |u| self.allocator.free(u.value);
            self.allocator.free(ups);
        }
        const co = self.create_options;
        inline for (.{ co.cores, co.ip, co.gw, co.vlan, co.tags }) |s| if (s) |v| self.allocator.free(v);
        for (co.mount_points) |mp| self.allocator.free(mp);
        if (co.mount_points.len > 0) self.allocator.free(co.mount_points);
        if (self.console_socket) |cs| self.allocator.free(cs);
        if (self.pid_file) |pf| self.allocator.free(pf);
        if (self.env) |e| {
            for (e) |env_var| {
                // env vars are not allocated, just referenced
                _ = env_var;
            }
        }
        if (self.args) |a| {
            for (a) |arg| {
                // args are not allocated, just referenced
                _ = arg;
            }
        }
    }
};

/// Configuration error types
pub const ConfigError = error{
    InvalidFormat,
    MissingField,
    InvalidValue,
    FileNotFound,
    PermissionDenied,
    ParseError,
};

/// Routing rule for container backend selection
pub const RoutingRule = struct {
    pattern: []const u8,
    runtime: RuntimeType,

    pub fn deinit(self: *const RoutingRule, allocator: std.mem.Allocator) void {
        allocator.free(self.pattern);
    }
};

/// Container configuration
pub const ContainerConfig = struct {
    default_container_type: ContainerType,

    // Which backend a container goes to, by name: first matching rule wins.
    // A pattern is a glob unless it starts with ^ or ends with $, in which
    // case it is a regular expression. This is the only routing there is;
    // `crun_name_patterns`, the glob list that preceded it, was removed in
    // 0.13.0 because a glob under `routing` is the same matcher.
    routing: []const RoutingRule,
    default_runtime: RuntimeType,

    pub fn deinit(self: *ContainerConfig, allocator: std.mem.Allocator) void {
        for (self.routing) |rule| {
            rule.deinit(allocator);
        }
        allocator.free(self.routing);
    }
};

/// Signal constants
pub const SIGINT = 2;
pub const SIGTERM = 15;
pub const SIGHUP = 1;

/// The "proxmox" section of the config file
pub const ProxmoxSettings = struct {
    /// Storage for new container root filesystems, e.g. "local-lvm". When
    /// unset, pct uses its own default storage "local", which a stock LVM
    /// install does not allow for container volumes.
    storage: ?[]const u8 = null,
    /// Root filesystem size in GiB for new containers on `storage`
    rootfs_size_gb: ?u32 = null,
    /// Passed as --ostype; when unset pct detects it from the template
    ostype: ?[]const u8 = null,
    /// Passed as --unprivileged. When unset nexcage creates unprivileged
    /// containers, as the Proxmox VE web UI does (pct's own default is 0).
    unprivileged: ?bool = null,

    pub fn deinit(self: *ProxmoxSettings, allocator: std.mem.Allocator) void {
        if (self.storage) |s| allocator.free(s);
        if (self.ostype) |o| allocator.free(o);
    }
};

/// Proxmox LXC backend configuration
pub const ProxmoxLxcBackendConfig = struct {
    allocator: std.mem.Allocator,
    // Optional overrides from config file
    zfs_pool: ?[]const u8 = null,
    default_memory_mb: ?u32 = null,
    default_cores: ?u32 = null,
    default_bridge: ?[]const u8 = null,
    default_ostype: ?[]const u8 = null,
    default_unprivileged: ?bool = null,
    default_storage: ?[]const u8 = null,
    rootfs_size_gb: ?u32 = null,

    pub fn deinit(self: *ProxmoxLxcBackendConfig) void {
        if (self.zfs_pool) |p| self.allocator.free(p);
        if (self.default_bridge) |b| self.allocator.free(b);
        if (self.default_ostype) |o| self.allocator.free(o);
        if (self.default_storage) |s| self.allocator.free(s);
    }
};
