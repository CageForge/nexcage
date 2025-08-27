// Generated from config-schema.json. Do not edit!
#ifndef RUNTIME_SPEC_SCHEMA_CONFIG_SCHEMA_SCHEMA_H
#define RUNTIME_SPEC_SCHEMA_CONFIG_SCHEMA_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/runtime_spec_schema_defs.h"
#include "ocispec/runtime_spec_schema_defs_linux.h"
#include "ocispec/runtime_spec_schema_config_linux.h"
#include "ocispec/runtime_spec_schema_config_solaris.h"
#include "ocispec/runtime_spec_schema_config_windows.h"
#include "ocispec/runtime_spec_schema_defs_windows.h"
#include "ocispec/runtime_spec_schema_config_vm.h"
#include "ocispec/runtime_spec_schema_defs_vm.h"
#include "ocispec/runtime_spec_schema_config_zos.h"
#include "ocispec/runtime_spec_schema_defs_zos.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    runtime_spec_schema_defs_hook **prestart;
    size_t prestart_len;

    runtime_spec_schema_defs_hook **create_runtime;
    size_t create_runtime_len;

    runtime_spec_schema_defs_hook **create_container;
    size_t create_container_len;

    runtime_spec_schema_defs_hook **start_container;
    size_t start_container_len;

    runtime_spec_schema_defs_hook **poststart;
    size_t poststart_len;

    runtime_spec_schema_defs_hook **poststop;
    size_t poststop_len;

    yajl_val _residual;
}
runtime_spec_schema_config_schema_hooks;

void free_runtime_spec_schema_config_schema_hooks (runtime_spec_schema_config_schema_hooks *ptr);

runtime_spec_schema_config_schema_hooks *clone_runtime_spec_schema_config_schema_hooks (runtime_spec_schema_config_schema_hooks *src);
runtime_spec_schema_config_schema_hooks *make_runtime_spec_schema_config_schema_hooks (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_hooks (yajl_gen g, const runtime_spec_schema_config_schema_hooks *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *path;

    bool readonly;

    yajl_val _residual;

    unsigned int readonly_present : 1;
}
runtime_spec_schema_config_schema_root;

void free_runtime_spec_schema_config_schema_root (runtime_spec_schema_config_schema_root *ptr);

runtime_spec_schema_config_schema_root *clone_runtime_spec_schema_config_schema_root (runtime_spec_schema_config_schema_root *src);
runtime_spec_schema_config_schema_root *make_runtime_spec_schema_config_schema_root (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_root (yajl_gen g, const runtime_spec_schema_config_schema_root *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    uint64_t height;

    uint64_t width;

    yajl_val _residual;

    unsigned int height_present : 1;
    unsigned int width_present : 1;
}
runtime_spec_schema_config_schema_process_console_size;

void free_runtime_spec_schema_config_schema_process_console_size (runtime_spec_schema_config_schema_process_console_size *ptr);

runtime_spec_schema_config_schema_process_console_size *clone_runtime_spec_schema_config_schema_process_console_size (runtime_spec_schema_config_schema_process_console_size *src);
runtime_spec_schema_config_schema_process_console_size *make_runtime_spec_schema_config_schema_process_console_size (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_process_console_size (yajl_gen g, const runtime_spec_schema_config_schema_process_console_size *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    uid_t uid;

    gid_t gid;

    uint32_t umask;

    gid_t *additional_gids;
    size_t additional_gids_len;

    char *username;

    yajl_val _residual;

    unsigned int uid_present : 1;
    unsigned int gid_present : 1;
    unsigned int umask_present : 1;
}
runtime_spec_schema_config_schema_process_user;

void free_runtime_spec_schema_config_schema_process_user (runtime_spec_schema_config_schema_process_user *ptr);

runtime_spec_schema_config_schema_process_user *clone_runtime_spec_schema_config_schema_process_user (runtime_spec_schema_config_schema_process_user *src);
runtime_spec_schema_config_schema_process_user *make_runtime_spec_schema_config_schema_process_user (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_process_user (yajl_gen g, const runtime_spec_schema_config_schema_process_user *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char **bounding;
    size_t bounding_len;

    char **permitted;
    size_t permitted_len;

    char **effective;
    size_t effective_len;

    char **inheritable;
    size_t inheritable_len;

    char **ambient;
    size_t ambient_len;

    yajl_val _residual;
}
runtime_spec_schema_config_schema_process_capabilities;

void free_runtime_spec_schema_config_schema_process_capabilities (runtime_spec_schema_config_schema_process_capabilities *ptr);

runtime_spec_schema_config_schema_process_capabilities *clone_runtime_spec_schema_config_schema_process_capabilities (runtime_spec_schema_config_schema_process_capabilities *src);
runtime_spec_schema_config_schema_process_capabilities *make_runtime_spec_schema_config_schema_process_capabilities (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_process_capabilities (yajl_gen g, const runtime_spec_schema_config_schema_process_capabilities *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *_class;

    int32_t priority;

    yajl_val _residual;

    unsigned int priority_present : 1;
}
runtime_spec_schema_config_schema_process_io_priority;

void free_runtime_spec_schema_config_schema_process_io_priority (runtime_spec_schema_config_schema_process_io_priority *ptr);

runtime_spec_schema_config_schema_process_io_priority *clone_runtime_spec_schema_config_schema_process_io_priority (runtime_spec_schema_config_schema_process_io_priority *src);
runtime_spec_schema_config_schema_process_io_priority *make_runtime_spec_schema_config_schema_process_io_priority (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_process_io_priority (yajl_gen g, const runtime_spec_schema_config_schema_process_io_priority *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *policy;

    int32_t nice;

    int32_t priority;

    char **flags;
    size_t flags_len;

    uint64_t runtime;

    uint64_t deadline;

    uint64_t period;

    yajl_val _residual;

    unsigned int nice_present : 1;
    unsigned int priority_present : 1;
    unsigned int runtime_present : 1;
    unsigned int deadline_present : 1;
    unsigned int period_present : 1;
}
runtime_spec_schema_config_schema_process_scheduler;

void free_runtime_spec_schema_config_schema_process_scheduler (runtime_spec_schema_config_schema_process_scheduler *ptr);

runtime_spec_schema_config_schema_process_scheduler *clone_runtime_spec_schema_config_schema_process_scheduler (runtime_spec_schema_config_schema_process_scheduler *src);
runtime_spec_schema_config_schema_process_scheduler *make_runtime_spec_schema_config_schema_process_scheduler (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_process_scheduler (yajl_gen g, const runtime_spec_schema_config_schema_process_scheduler *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    uint64_t hard;
    uint64_t soft;
    char *type;
    unsigned int hard_present : 1;
    unsigned int soft_present : 1;
}
runtime_spec_schema_config_schema_process_rlimits_element;

void free_runtime_spec_schema_config_schema_process_rlimits_element (runtime_spec_schema_config_schema_process_rlimits_element *ptr);

runtime_spec_schema_config_schema_process_rlimits_element *make_runtime_spec_schema_config_schema_process_rlimits_element (yajl_val tree, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *initial;

    char *final;

    yajl_val _residual;
}
runtime_spec_schema_config_schema_process_exec_cpu_affinity;

void free_runtime_spec_schema_config_schema_process_exec_cpu_affinity (runtime_spec_schema_config_schema_process_exec_cpu_affinity *ptr);

runtime_spec_schema_config_schema_process_exec_cpu_affinity *clone_runtime_spec_schema_config_schema_process_exec_cpu_affinity (runtime_spec_schema_config_schema_process_exec_cpu_affinity *src);
runtime_spec_schema_config_schema_process_exec_cpu_affinity *make_runtime_spec_schema_config_schema_process_exec_cpu_affinity (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_process_exec_cpu_affinity (yajl_gen g, const runtime_spec_schema_config_schema_process_exec_cpu_affinity *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char **args;
    size_t args_len;

    char *command_line;

    runtime_spec_schema_config_schema_process_console_size *console_size;

    char *cwd;

    char **env;
    size_t env_len;

    bool terminal;

    runtime_spec_schema_config_schema_process_user *user;

    runtime_spec_schema_config_schema_process_capabilities *capabilities;

    char *apparmor_profile;

    int oom_score_adj;

    char *selinux_label;

    runtime_spec_schema_config_schema_process_io_priority *io_priority;

    bool no_new_privileges;

    runtime_spec_schema_config_schema_process_scheduler *scheduler;

    runtime_spec_schema_config_schema_process_rlimits_element **rlimits;
    size_t rlimits_len;

    runtime_spec_schema_config_schema_process_exec_cpu_affinity *exec_cpu_affinity;

    yajl_val _residual;

    unsigned int terminal_present : 1;
    unsigned int oom_score_adj_present : 1;
    unsigned int no_new_privileges_present : 1;
}
runtime_spec_schema_config_schema_process;

void free_runtime_spec_schema_config_schema_process (runtime_spec_schema_config_schema_process *ptr);

runtime_spec_schema_config_schema_process *clone_runtime_spec_schema_config_schema_process (runtime_spec_schema_config_schema_process *src);
runtime_spec_schema_config_schema_process *make_runtime_spec_schema_config_schema_process (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema_process (yajl_gen g, const runtime_spec_schema_config_schema_process *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *oci_version;

    runtime_spec_schema_config_schema_hooks *hooks;

    json_map_string_string *annotations;

    char *hostname;

    char *domainname;

    runtime_spec_schema_defs_mount **mounts;
    size_t mounts_len;

    runtime_spec_schema_config_schema_root *root;

    runtime_spec_schema_config_schema_process *process;

    runtime_spec_schema_config_linux *linux;

    runtime_spec_schema_config_solaris *solaris;

    runtime_spec_schema_config_windows *windows;

    runtime_spec_schema_config_vm *vm;

    runtime_spec_schema_config_zos *zos;

    yajl_val _residual;
}
runtime_spec_schema_config_schema;

void free_runtime_spec_schema_config_schema (runtime_spec_schema_config_schema *ptr);

runtime_spec_schema_config_schema *clone_runtime_spec_schema_config_schema (runtime_spec_schema_config_schema *src);
runtime_spec_schema_config_schema *make_runtime_spec_schema_config_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_schema (yajl_gen g, const runtime_spec_schema_config_schema *ptr, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_config_schema *runtime_spec_schema_config_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_config_schema *runtime_spec_schema_config_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_config_schema *runtime_spec_schema_config_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *runtime_spec_schema_config_schema_generate_json (const runtime_spec_schema_config_schema *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

