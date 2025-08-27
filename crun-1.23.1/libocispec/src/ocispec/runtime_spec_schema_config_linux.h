// Generated from config-linux.json. Do not edit!
#ifndef RUNTIME_SPEC_SCHEMA_CONFIG_LINUX_SCHEMA_H
#define RUNTIME_SPEC_SCHEMA_CONFIG_LINUX_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/runtime_spec_schema_defs_linux.h"
#include "ocispec/runtime_spec_schema_defs.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char **keys;
    runtime_spec_schema_defs_linux_net_device **values;
    size_t len;
}
runtime_spec_schema_config_linux_net_devices;

void free_runtime_spec_schema_config_linux_net_devices (runtime_spec_schema_config_linux_net_devices *ptr);

runtime_spec_schema_config_linux_net_devices *clone_runtime_spec_schema_config_linux_net_devices (runtime_spec_schema_config_linux_net_devices *src);
runtime_spec_schema_config_linux_net_devices *make_runtime_spec_schema_config_linux_net_devices (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_net_devices (yajl_gen g, const runtime_spec_schema_config_linux_net_devices *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    int64_t limit;

    yajl_val _residual;

    unsigned int limit_present : 1;
}
runtime_spec_schema_config_linux_resources_pids;

void free_runtime_spec_schema_config_linux_resources_pids (runtime_spec_schema_config_linux_resources_pids *ptr);

runtime_spec_schema_config_linux_resources_pids *clone_runtime_spec_schema_config_linux_resources_pids (runtime_spec_schema_config_linux_resources_pids *src);
runtime_spec_schema_config_linux_resources_pids *make_runtime_spec_schema_config_linux_resources_pids (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_resources_pids (yajl_gen g, const runtime_spec_schema_config_linux_resources_pids *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    uint16_t weight;

    uint16_t leaf_weight;

    runtime_spec_schema_defs_linux_block_io_device_throttle **throttle_read_bps_device;
    size_t throttle_read_bps_device_len;

    runtime_spec_schema_defs_linux_block_io_device_throttle **throttle_write_bps_device;
    size_t throttle_write_bps_device_len;

    runtime_spec_schema_defs_linux_block_io_device_throttle **throttle_read_iops_device;
    size_t throttle_read_iops_device_len;

    runtime_spec_schema_defs_linux_block_io_device_throttle **throttle_write_iops_device;
    size_t throttle_write_iops_device_len;

    runtime_spec_schema_defs_linux_block_io_device_weight **weight_device;
    size_t weight_device_len;

    yajl_val _residual;

    unsigned int weight_present : 1;
    unsigned int leaf_weight_present : 1;
}
runtime_spec_schema_config_linux_resources_block_io;

void free_runtime_spec_schema_config_linux_resources_block_io (runtime_spec_schema_config_linux_resources_block_io *ptr);

runtime_spec_schema_config_linux_resources_block_io *clone_runtime_spec_schema_config_linux_resources_block_io (runtime_spec_schema_config_linux_resources_block_io *src);
runtime_spec_schema_config_linux_resources_block_io *make_runtime_spec_schema_config_linux_resources_block_io (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_resources_block_io (yajl_gen g, const runtime_spec_schema_config_linux_resources_block_io *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *cpus;

    char *mems;

    uint64_t period;

    int64_t quota;

    uint64_t burst;

    uint64_t realtime_period;

    int64_t realtime_runtime;

    uint64_t shares;

    int64_t idle;

    yajl_val _residual;

    unsigned int period_present : 1;
    unsigned int quota_present : 1;
    unsigned int burst_present : 1;
    unsigned int realtime_period_present : 1;
    unsigned int realtime_runtime_present : 1;
    unsigned int shares_present : 1;
    unsigned int idle_present : 1;
}
runtime_spec_schema_config_linux_resources_cpu;

void free_runtime_spec_schema_config_linux_resources_cpu (runtime_spec_schema_config_linux_resources_cpu *ptr);

runtime_spec_schema_config_linux_resources_cpu *clone_runtime_spec_schema_config_linux_resources_cpu (runtime_spec_schema_config_linux_resources_cpu *src);
runtime_spec_schema_config_linux_resources_cpu *make_runtime_spec_schema_config_linux_resources_cpu (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_resources_cpu (yajl_gen g, const runtime_spec_schema_config_linux_resources_cpu *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *page_size;
    uint64_t limit;
    unsigned int limit_present : 1;
}
runtime_spec_schema_config_linux_resources_hugepage_limits_element;

void free_runtime_spec_schema_config_linux_resources_hugepage_limits_element (runtime_spec_schema_config_linux_resources_hugepage_limits_element *ptr);

runtime_spec_schema_config_linux_resources_hugepage_limits_element *make_runtime_spec_schema_config_linux_resources_hugepage_limits_element (yajl_val tree, const struct parser_context *ctx, parser_error *err);

typedef struct {
    int64_t kernel;

    int64_t kernel_tcp;

    int64_t limit;

    int64_t reservation;

    int64_t swap;

    uint64_t swappiness;

    bool disable_oom_killer;

    bool use_hierarchy;

    bool check_before_update;

    yajl_val _residual;

    unsigned int kernel_present : 1;
    unsigned int kernel_tcp_present : 1;
    unsigned int limit_present : 1;
    unsigned int reservation_present : 1;
    unsigned int swap_present : 1;
    unsigned int swappiness_present : 1;
    unsigned int disable_oom_killer_present : 1;
    unsigned int use_hierarchy_present : 1;
    unsigned int check_before_update_present : 1;
}
runtime_spec_schema_config_linux_resources_memory;

void free_runtime_spec_schema_config_linux_resources_memory (runtime_spec_schema_config_linux_resources_memory *ptr);

runtime_spec_schema_config_linux_resources_memory *clone_runtime_spec_schema_config_linux_resources_memory (runtime_spec_schema_config_linux_resources_memory *src);
runtime_spec_schema_config_linux_resources_memory *make_runtime_spec_schema_config_linux_resources_memory (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_resources_memory (yajl_gen g, const runtime_spec_schema_config_linux_resources_memory *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    uint32_t class_id;

    runtime_spec_schema_defs_linux_network_interface_priority **priorities;
    size_t priorities_len;

    yajl_val _residual;

    unsigned int class_id_present : 1;
}
runtime_spec_schema_config_linux_resources_network;

void free_runtime_spec_schema_config_linux_resources_network (runtime_spec_schema_config_linux_resources_network *ptr);

runtime_spec_schema_config_linux_resources_network *clone_runtime_spec_schema_config_linux_resources_network (runtime_spec_schema_config_linux_resources_network *src);
runtime_spec_schema_config_linux_resources_network *make_runtime_spec_schema_config_linux_resources_network (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_resources_network (yajl_gen g, const runtime_spec_schema_config_linux_resources_network *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char **keys;
    runtime_spec_schema_defs_linux_rdma **values;
    size_t len;
}
runtime_spec_schema_config_linux_resources_rdma;

void free_runtime_spec_schema_config_linux_resources_rdma (runtime_spec_schema_config_linux_resources_rdma *ptr);

runtime_spec_schema_config_linux_resources_rdma *clone_runtime_spec_schema_config_linux_resources_rdma (runtime_spec_schema_config_linux_resources_rdma *src);
runtime_spec_schema_config_linux_resources_rdma *make_runtime_spec_schema_config_linux_resources_rdma (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_resources_rdma (yajl_gen g, const runtime_spec_schema_config_linux_resources_rdma *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    json_map_string_string *unified;

    runtime_spec_schema_defs_linux_device_cgroup **devices;
    size_t devices_len;

    runtime_spec_schema_config_linux_resources_pids *pids;

    runtime_spec_schema_config_linux_resources_block_io *block_io;

    runtime_spec_schema_config_linux_resources_cpu *cpu;

    runtime_spec_schema_config_linux_resources_hugepage_limits_element **hugepage_limits;
    size_t hugepage_limits_len;

    runtime_spec_schema_config_linux_resources_memory *memory;

    runtime_spec_schema_config_linux_resources_network *network;

    runtime_spec_schema_config_linux_resources_rdma *rdma;

    yajl_val _residual;
}
runtime_spec_schema_config_linux_resources;

void free_runtime_spec_schema_config_linux_resources (runtime_spec_schema_config_linux_resources *ptr);

runtime_spec_schema_config_linux_resources *clone_runtime_spec_schema_config_linux_resources (runtime_spec_schema_config_linux_resources *src);
runtime_spec_schema_config_linux_resources *make_runtime_spec_schema_config_linux_resources (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_resources (yajl_gen g, const runtime_spec_schema_config_linux_resources *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *default_action;

    uint32_t default_errno_ret;

    char **flags;
    size_t flags_len;

    char *listener_path;

    char *listener_metadata;

    char **architectures;
    size_t architectures_len;

    runtime_spec_schema_defs_linux_syscall **syscalls;
    size_t syscalls_len;

    yajl_val _residual;

    unsigned int default_errno_ret_present : 1;
}
runtime_spec_schema_config_linux_seccomp;

void free_runtime_spec_schema_config_linux_seccomp (runtime_spec_schema_config_linux_seccomp *ptr);

runtime_spec_schema_config_linux_seccomp *clone_runtime_spec_schema_config_linux_seccomp (runtime_spec_schema_config_linux_seccomp *src);
runtime_spec_schema_config_linux_seccomp *make_runtime_spec_schema_config_linux_seccomp (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_seccomp (yajl_gen g, const runtime_spec_schema_config_linux_seccomp *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *clos_id;

    char **schemata;
    size_t schemata_len;

    char *l3cache_schema;

    char *mem_bw_schema;

    bool enable_cmt;

    bool enable_mbm;

    yajl_val _residual;

    unsigned int enable_cmt_present : 1;
    unsigned int enable_mbm_present : 1;
}
runtime_spec_schema_config_linux_intel_rdt;

void free_runtime_spec_schema_config_linux_intel_rdt (runtime_spec_schema_config_linux_intel_rdt *ptr);

runtime_spec_schema_config_linux_intel_rdt *clone_runtime_spec_schema_config_linux_intel_rdt (runtime_spec_schema_config_linux_intel_rdt *src);
runtime_spec_schema_config_linux_intel_rdt *make_runtime_spec_schema_config_linux_intel_rdt (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_intel_rdt (yajl_gen g, const runtime_spec_schema_config_linux_intel_rdt *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    runtime_spec_schema_defs_linux_time_offsets *boottime;

    runtime_spec_schema_defs_linux_time_offsets *monotonic;

    yajl_val _residual;
}
runtime_spec_schema_config_linux_time_offsets;

void free_runtime_spec_schema_config_linux_time_offsets (runtime_spec_schema_config_linux_time_offsets *ptr);

runtime_spec_schema_config_linux_time_offsets *clone_runtime_spec_schema_config_linux_time_offsets (runtime_spec_schema_config_linux_time_offsets *src);
runtime_spec_schema_config_linux_time_offsets *make_runtime_spec_schema_config_linux_time_offsets (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux_time_offsets (yajl_gen g, const runtime_spec_schema_config_linux_time_offsets *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    runtime_spec_schema_defs_linux_device **devices;
    size_t devices_len;

    runtime_spec_schema_config_linux_net_devices *net_devices;

    runtime_spec_schema_defs_id_mapping **uid_mappings;
    size_t uid_mappings_len;

    runtime_spec_schema_defs_id_mapping **gid_mappings;
    size_t gid_mappings_len;

    runtime_spec_schema_defs_linux_namespace_reference **namespaces;
    size_t namespaces_len;

    runtime_spec_schema_config_linux_resources *resources;

    char *cgroups_path;

    char *rootfs_propagation;

    runtime_spec_schema_config_linux_seccomp *seccomp;

    json_map_string_string *sysctl;

    char **masked_paths;
    size_t masked_paths_len;

    char **readonly_paths;
    size_t readonly_paths_len;

    char *mount_label;

    runtime_spec_schema_config_linux_intel_rdt *intel_rdt;

    runtime_spec_schema_defs_linux_personality *personality;

    runtime_spec_schema_config_linux_time_offsets *time_offsets;

    yajl_val _residual;
}
runtime_spec_schema_config_linux;

void free_runtime_spec_schema_config_linux (runtime_spec_schema_config_linux *ptr);

runtime_spec_schema_config_linux *clone_runtime_spec_schema_config_linux (runtime_spec_schema_config_linux *src);
runtime_spec_schema_config_linux *make_runtime_spec_schema_config_linux (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_linux (yajl_gen g, const runtime_spec_schema_config_linux *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

