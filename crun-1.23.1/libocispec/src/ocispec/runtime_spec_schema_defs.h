// Generated from defs.json. Do not edit!
#ifndef RUNTIME_SPEC_SCHEMA_DEFS_SCHEMA_H
#define RUNTIME_SPEC_SCHEMA_DEFS_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *path;

    char **args;
    size_t args_len;

    char **env;
    size_t env_len;

    int timeout;

    yajl_val _residual;

    unsigned int timeout_present : 1;
}
runtime_spec_schema_defs_hook;

void free_runtime_spec_schema_defs_hook (runtime_spec_schema_defs_hook *ptr);

runtime_spec_schema_defs_hook *clone_runtime_spec_schema_defs_hook (runtime_spec_schema_defs_hook *src);
runtime_spec_schema_defs_hook *make_runtime_spec_schema_defs_hook (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_defs_hook (yajl_gen g, const runtime_spec_schema_defs_hook *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    uint32_t container_id;

    uint32_t host_id;

    uint32_t size;

    yajl_val _residual;

    unsigned int container_id_present : 1;
    unsigned int host_id_present : 1;
    unsigned int size_present : 1;
}
runtime_spec_schema_defs_id_mapping;

void free_runtime_spec_schema_defs_id_mapping (runtime_spec_schema_defs_id_mapping *ptr);

runtime_spec_schema_defs_id_mapping *clone_runtime_spec_schema_defs_id_mapping (runtime_spec_schema_defs_id_mapping *src);
runtime_spec_schema_defs_id_mapping *make_runtime_spec_schema_defs_id_mapping (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_defs_id_mapping (yajl_gen g, const runtime_spec_schema_defs_id_mapping *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *source;

    char *destination;

    char **options;
    size_t options_len;

    char *type;

    runtime_spec_schema_defs_id_mapping **uid_mappings;
    size_t uid_mappings_len;

    runtime_spec_schema_defs_id_mapping **gid_mappings;
    size_t gid_mappings_len;

    yajl_val _residual;
}
runtime_spec_schema_defs_mount;

void free_runtime_spec_schema_defs_mount (runtime_spec_schema_defs_mount *ptr);

runtime_spec_schema_defs_mount *clone_runtime_spec_schema_defs_mount (runtime_spec_schema_defs_mount *src);
runtime_spec_schema_defs_mount *make_runtime_spec_schema_defs_mount (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_defs_mount (yajl_gen g, const runtime_spec_schema_defs_mount *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

