/// Crun backend module (ABI only)
pub const libcrun_driver = @import("libcrun_driver.zig");
pub const libcrun_ffi = @import("libcrun_ffi.zig");

// Expose ABI-based driver only
pub const CrunDriver = libcrun_driver.CrunDriver;
pub const CrunDriverLibcrun = libcrun_driver.CrunDriver; // libcrun ABI-based

// The structs libcrun_ffi.zig mirrors by hand, compared with the vendored
// header whenever this backend is built. A mirror that has drifted still
// compiles, and then libcrun reads a field at the wrong offset in the root
// process: the features document once came out as rubbish and a segfault
// that way, and the context lost a field without anything noticing. Here it
// is a compile error that names the field. This file is only analysed when
// the backend is built, which is also when build.zig gives the backends
// module the vendored include paths.
comptime {
    const header = @cImport({
        @cDefine("_GNU_SOURCE", "1");
        @cInclude("config.h");
        @cInclude("libcrun/container.h");
    });
    const L = libcrun_ffi.Libcrun;
    const same = libcrun_ffi.expectSameLayout;
    same(L.Context, header.struct_libcrun_context_s);
    same(L.Error, header.struct_libcrun_error_s);
    same(L.UpdateValue, header.struct_libcrun_update_value_s);
    same(L.FeaturesInfo, header.struct_features_info_s);
    same(L.LinuxInfo, header.struct_linux_info_s);
    same(L.CgroupInfo, header.struct_cgroup_info_s);
    same(L.SeccompInfo, header.struct_seccomp_info_s);
    same(L.EnabledInfo, header.struct_apparmor_info_s);
    same(L.EnabledInfo, header.struct_selinux_info_s);
    same(L.EnabledInfo, header.struct_idmap_info_s);
    same(L.EnabledInfo, header.struct_intel_rdt_s);
    same(L.EnabledInfo, header.struct_net_devices_s);
    same(L.MountExtInfo, header.struct_mount_ext_info_s);
    same(L.MemoryPolicyInfo, header.struct_memory_policy_info_s);
    same(L.AnnotationsInfo, header.struct_annotations_info_s);
}
