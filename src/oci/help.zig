const std = @import("std");

/// Print usage information for proxmox-lxcri CLI
pub fn printUsage() void {
    const usage =
        \\Proxmox LXC Container Runtime Interface (proxmox-lxcri)
        \\
        \\Usage: proxmox-lxcri [OPTIONS] COMMAND [ARGS]...
        \\
        \\COMMANDS:
        \\  create <container_id>    Create a new container
        \\  start <container_id>     Start a container
        \\  stop <container_id>      Stop a container
        \\  delete <container_id>    Delete a container
        \\  list                     List all containers
        \\  info <container_id>      Show container information
        \\  state <container_id>     Get container state
        \\  kill <container_id>      Kill a container
        \\  pause <container_id>     Pause a running container
        \\  resume <container_id>    Resume a paused container
        \\  exec <container_id>      Execute new process inside the container
        \\  ps <container_id>        Display processes running inside a container
        \\  run <container_id>       Create and start a container in one operation
        \\  events <container_id>    Display container events and statistics
        \\  spec                     Create a new specification file
        \\  checkpoint <container_id> Create a checkpoint of a running container
        \\  restore <container_id>   Restore a container from a checkpoint
        \\  update <container_id>    Update container resource constraints
        \\  features                 Show the enabled features
        \\  generate-config          Generate OCI config for a container
        \\
        \\GLOBAL OPTIONS:
        \\  --debug                  Enable debug logging
        \\  --log <path>             Set the log file to write logs to (default: '/dev/stderr')
        \\  --log-format <format>    Set the log format ('text' (default), or 'json') (default: "text")
        \\
        \\  --root <path>            Root directory for storage of container state (default: "/run/proxmox-lxcri")
        \\
        \\  --systemd-cgroup         Enable systemd cgroup support
        \\  --config <path>          Path to configuration file
        \\  --bundle, -b <path>      Path to OCI bundle
        \\  --pid-file <path>        Path to pid file
        \\  --console-socket <path>  Path to console socket
        \\  --help, -h               Show this help message
        \\  --version, -v            Print the version
        \\
        \\Examples:
        \\  proxmox-lxcri --config /path/to/config.json create my-container
        \\  proxmox-lxcri --config /path/to/config.json start my-container
        \\  proxmox-lxcri list
        \\
        \\Configuration files are loaded in this order:
        \\  1. File specified with --config
        \\  2. ./config.json (current directory)
        \\  3. /etc/proxmox-lxcri/config.json
        \\  4. /etc/proxmox-lxcri/proxmox-lxcri.json
        \\
    ;
    std.io.getStdOut().writer().print(usage, .{}) catch {};
}

/// Print version information
pub fn printVersion() void {
    const version = "proxmox-lxcri version 0.2.0-beta\n";
    std.io.getStdOut().writer().print(version, .{}) catch {};
}

/// Print help for specific command
pub fn printCommandHelp(command: []const u8) void {
    if (std.mem.eql(u8, command, "create")) {
        printCreateHelp();
    } else if (std.mem.eql(u8, command, "list")) {
        printListHelp();
    } else if (std.mem.eql(u8, command, "start")) {
        printStartHelp();
    } else if (std.mem.eql(u8, command, "stop")) {
        printStopHelp();
    } else if (std.mem.eql(u8, command, "run")) {
        printRunHelp();
    } else if (std.mem.eql(u8, command, "spec")) {
        printSpecHelp();
    } else if (std.mem.eql(u8, command, "checkpoint")) {
        printCheckpointHelp();
    } else if (std.mem.eql(u8, command, "restore")) {
        printRestoreHelp();
    } else {
        std.io.getStdOut().writer().print("Help for command '{s}' is not available yet.\n", .{command}) catch {};
        printUsage();
    }
}

fn printCreateHelp() void {
    const help =
        \\Create a new container
        \\
        \\Usage: proxmox-lxcri create [OPTIONS] <container_id>
        \\
        \\Options:
        \\  --bundle, -b <path>      Path to OCI bundle directory
        \\  --runtime <runtime>      Container runtime (crun, lxc, vm)
        \\  --config <path>          Path to configuration file
        \\  --debug                  Enable debug logging
        \\
        \\Examples:
        \\  proxmox-lxcri create --bundle ./my-bundle container1
        \\  proxmox-lxcri create --runtime=crun --bundle ./bundle container2
        \\
    ;
    std.io.getStdOut().writer().print(help, .{}) catch {};
}

fn printListHelp() void {
    const help =
        \\List all containers
        \\
        \\Usage: proxmox-lxcri list [OPTIONS]
        \\
        \\Options:
        \\  --config <path>          Path to configuration file
        \\  --debug                  Enable debug logging
        \\
        \\Description:
        \\  Shows containers from both CRUN runtime and Proxmox LXC.
        \\  Output includes container ID, name, status, and type.
        \\
        \\Examples:
        \\  proxmox-lxcri list
        \\  proxmox-lxcri --config ./config.json list
        \\
    ;
    std.io.getStdOut().writer().print(help, .{}) catch {};
}

fn printStartHelp() void {
    const help =
        \\Start a container
        \\
        \\Usage: proxmox-lxcri start [OPTIONS] <container_id>
        \\
        \\Options:
        \\  --config <path>          Path to configuration file
        \\  --debug                  Enable debug logging
        \\
        \\Examples:
        \\  proxmox-lxcri start container1
        \\  proxmox-lxcri --config ./config.json start my-container
        \\
    ;
    std.io.getStdOut().writer().print(help, .{}) catch {};
}

fn printStopHelp() void {
    const help =
        \\Stop a container
        \\
        \\Usage: proxmox-lxcri stop [OPTIONS] <container_id>
        \\
        \\Options:
        \\  --config <path>          Path to configuration file
        \\  --debug                  Enable debug logging
        \\
        \\Examples:
        \\  proxmox-lxcri stop container1
        \\  proxmox-lxcri --config ./config.json stop my-container
        \\
    ;
    std.io.getStdOut().writer().print(help, .{}) catch {};
}

fn printRunHelp() void {
    const help =
        \\Create and start a container in one operation
        \\
        \\Usage: proxmox-lxcri run [OPTIONS] --bundle <path> <container_id>
        \\
        \\Options:
        \\  --bundle, -b <path>      Path to OCI bundle directory (required)
        \\  --runtime <runtime>      Container runtime (crun, lxc, vm) [default: crun]
        \\  --config <path>          Path to configuration file
        \\  --debug                  Enable debug logging
        \\
        \\Description:
        \\  The run command combines create and start operations:
        \\  1. Creates a new container from the specified bundle
        \\  2. Immediately starts the container
        \\  
        \\  This is equivalent to running:
        \\    proxmox-lxcri create --bundle <path> <container_id>
        \\    proxmox-lxcri start <container_id>
        \\
        \\Examples:
        \\  proxmox-lxcri run --bundle ./my-bundle container1
        \\  proxmox-lxcri run --runtime=crun --bundle ./bundle container2
        \\  proxmox-lxcri --config ./config.json run -b ./bundle my-container
        \\
    ;
    std.io.getStdOut().writer().print(help, .{}) catch {};
}

fn printSpecHelp() void {
    const help =
        \\Generate OCI specification file
        \\
        \\Usage: proxmox-lxcri spec [OPTIONS] [bundle-path]
        \\
        \\Options:
        \\  --bundle, -b <path>      Path to OCI bundle directory [default: .]
        \\  --config <path>          Path to configuration file
        \\  --debug                  Enable debug logging
        \\
        \\Description:
        \\  Generates a new OCI specification file (config.json) in the specified
        \\  bundle directory. This file defines the container configuration including
        \\  process, mounts, and security settings.
        \\
        \\Examples:
        \\  proxmox-lxcri spec                    # Generate in current directory
        \\  proxmox-lxcri spec ./my-bundle       # Generate in specific directory
        \\  proxmox-lxcri spec --bundle ./bundle # Using --bundle flag
        \\
    ;
    std.io.getStdOut().writer().print(help, .{}) catch {};
}

fn printCheckpointHelp() void {
    const help =
        \\Create a checkpoint of a running container
        \\
        \\Usage: proxmox-lxcri checkpoint [OPTIONS] <container_id>
        \\
        \\Options:
        \\  --image-path <path>      Path to save checkpoint image
        \\  --config <path>          Path to configuration file
        \\  --debug                  Enable debug logging
        \\
        \\Description:
        \\  Creates a checkpoint (snapshot) of a running container that can be
        \\  restored later using the restore command. The checkpoint includes
        \\  the container's memory state and process information.
        \\  
        \\  Note: Requires CRIU (Checkpoint/Restore In Userspace) support.
        \\  If CRIU is not available, this command will fail gracefully.
        \\
        \\Examples:
        \\  proxmox-lxcri checkpoint container1
        \\  proxmox-lxcri checkpoint --image-path /tmp/checkpoint container1
        \\  proxmox-lxcri --config ./config.json checkpoint my-container
        \\
    ;
    std.io.getStdOut().writer().print(help, .{}) catch {};
}

fn printRestoreHelp() void {
    const help =
        \\Restore a container from checkpoint
        \\
        \\Usage: proxmox-lxcri restore [OPTIONS] <container_id>
        \\
        \\Options:
        \\  --image-path <path>      Path to checkpoint image (for CRIU)
        \\  --snapshot <name>        ZFS snapshot name to restore from
        \\  --config <path>          Path to configuration file
        \\  --debug                  Enable debug logging
        \\
        \\Description:
        \\  Restores a container from a previously created checkpoint. This command
        \\  supports both ZFS snapshots and CRIU-based checkpoints:
        \\  
        \\  - ZFS Mode: Automatically detects and uses ZFS snapshots for restore
        \\    * Uses dataset pattern: tank/containers/<container_id>
        \\    * Automatically finds latest checkpoint if --snapshot not specified
        \\    * Fast, filesystem-level restore
        \\  
        \\  - CRIU Mode: Falls back to CRIU-based restore if ZFS unavailable
        \\    * Requires CRIU (Checkpoint/Restore In Userspace) support
        \\    * Uses --image-path for checkpoint location
        \\
        \\Examples:
        \\  # ZFS restore (automatic latest checkpoint)
        \\  proxmox-lxcri restore container1
        \\  
        \\  # ZFS restore from specific snapshot
        \\  proxmox-lxcri restore --snapshot checkpoint-1691234567 container1
        \\  
        \\  # CRIU restore (fallback)
        \\  proxmox-lxcri restore --image-path /tmp/checkpoint container1
        \\
    ;
    std.io.getStdOut().writer().print(help, .{}) catch {};
}
