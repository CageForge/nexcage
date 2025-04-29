const std = @import("std");
const testing = std.testing;
const oci = @import("oci");
const spec = oci.spec;
const types = oci.types;

test "Validate minimal spec" {
    const allocator = testing.allocator;
    
    const minimal_spec = types.Spec{
        .version = "1.0.0",
        .root = .{
            .path = "rootfs",
            .readonly = false,
        },
        .process = .{
            .terminal = false,
            .user = .{
                .uid = 0,
                .gid = 0,
            },
            .args = &[_][]const u8{"/bin/sh"},
            .env = &[_][]const u8{"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
            .cwd = "/",
        },
        .hostname = "container",
        .mounts = &[_]types.Mount{},
        .linux = null,
    };
    
    try spec.validateSpec(&minimal_spec);
}

test "Validate full spec" {
    const allocator = testing.allocator;
    
    var full_spec = types.Spec{
        .version = "1.0.0",
        .root = .{
            .path = "rootfs",
            .readonly = true,
        },
        .process = .{
            .terminal = true,
            .user = .{
                .uid = 1000,
                .gid = 1000,
                .additionalGids = &[_]u32{100, 101},
            },
            .args = &[_][]const u8{"/bin/bash", "-c", "echo hello"},
            .env = &[_][]const u8{
                "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "TERM=xterm",
            },
            .cwd = "/home/user",
            .capabilities = .{
                .bounding = &[_][]const u8{"CAP_NET_RAW"},
                .effective = &[_][]const u8{"CAP_NET_RAW"},
                .inheritable = &[_][]const u8{},
                .permitted = &[_][]const u8{"CAP_NET_RAW"},
                .ambient = &[_][]const u8{},
            },
            .rlimits = &[_]types.Rlimit{
                .{
                    .type = .RLIMIT_NOFILE,
                    .soft = 1024,
                    .hard = 4096,
                },
            },
            .noNewPrivileges = true,
        },
        .hostname = "test-container",
        .mounts = &[_]types.Mount{
            .{
                .destination = "/proc",
                .type = "proc",
                .source = "proc",
                .options = &[_][]const u8{"nosuid", "noexec", "nodev"},
            },
            .{
                .destination = "/dev",
                .type = "tmpfs",
                .source = "tmpfs",
                .options = &[_][]const u8{"nosuid", "strictatime", "mode=755", "size=65536k"},
            },
        },
        .hooks = .{
            .prestart = &[_]types.Hook{
                .{
                    .path = "/usr/bin/echo",
                    .args = &[_][]const u8{"prestart"},
                },
            },
            .poststart = &[_]types.Hook{
                .{
                    .path = "/usr/bin/echo",
                    .args = &[_][]const u8{"poststart"},
                },
            },
            .poststop = &[_]types.Hook{
                .{
                    .path = "/usr/bin/echo",
                    .args = &[_][]const u8{"poststop"},
                },
            },
        },
        .linux = .{
            .namespaces = &[_]types.LinuxNamespace{
                .{
                    .type = "pid",
                },
                .{
                    .type = "network",
                },
                .{
                    .type = "ipc",
                },
                .{
                    .type = "uts",
                },
                .{
                    .type = "mount",
                },
            },
            .resources = .{
                .memory = .{
                    .limit = 209715200,
                    .reservation = 209715200,
                    .swap = 209715200,
                    .kernel = 209715200,
                    .kernelTCP = 209715200,
                    .swappiness = 50,
                    .disableOOMKiller = false,
                },
                .cpu = .{
                    .shares = 1024,
                    .quota = 1000000,
                    .period = 500000,
                    .realtimeRuntime = 950000,
                    .realtimePeriod = 1000000,
                    .cpus = "0-1",
                    .mems = "0-1",
                },
            },
            .cgroupsPath = "/test/cgroup",
            .devices = &[_]types.LinuxDevice{},
            .seccomp = null,
            .selinux = null,
        },
    };
    
    try spec.validateSpec(&full_spec);
}

test "Validate invalid spec" {
    const allocator = testing.allocator;
    
    // Специфікація без версії
    const invalid_spec_1 = types.Spec{
        .version = "",
        .root = .{
            .path = "rootfs",
            .readonly = false,
        },
        .process = .{
            .terminal = false,
            .user = .{
                .uid = 0,
                .gid = 0,
            },
            .args = &[_][]const u8{"/bin/sh"},
            .env = &[_][]const u8{},
            .cwd = "/",
        },
        .hostname = "container",
        .mounts = &[_]types.Mount{},
        .linux = null,
    };
    
    try testing.expectError(error.InvalidSpec, spec.validateSpec(&invalid_spec_1));
    
    // Специфікація без root path
    const invalid_spec_2 = types.Spec{
        .version = "1.0.0",
        .root = .{
            .path = "",
            .readonly = false,
        },
        .process = .{
            .terminal = false,
            .user = .{
                .uid = 0,
                .gid = 0,
            },
            .args = &[_][]const u8{"/bin/sh"},
            .env = &[_][]const u8{},
            .cwd = "/",
        },
        .hostname = "container",
        .mounts = &[_]types.Mount{},
        .linux = null,
    };
    
    try testing.expectError(error.InvalidSpec, spec.validateSpec(&invalid_spec_2));
    
    // Специфікація без аргументів процесу
    const invalid_spec_3 = types.Spec{
        .version = "1.0.0",
        .root = .{
            .path = "rootfs",
            .readonly = false,
        },
        .process = .{
            .terminal = false,
            .user = .{
                .uid = 0,
                .gid = 0,
            },
            .args = &[_][]const u8{},
            .env = &[_][]const u8{},
            .cwd = "/",
        },
        .hostname = "container",
        .mounts = &[_]types.Mount{},
        .linux = null,
    };
    
    try testing.expectError(error.InvalidSpec, spec.validateSpec(&invalid_spec_3));
} 