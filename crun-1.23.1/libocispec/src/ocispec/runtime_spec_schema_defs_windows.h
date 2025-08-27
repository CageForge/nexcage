// Generated from defs-windows.json. Do not edit!
#ifndef RUNTIME_SPEC_SCHEMA_DEFS_WINDOWS_SCHEMA_H
#define RUNTIME_SPEC_SCHEMA_DEFS_WINDOWS_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *id;

    char *id_type;

    yajl_val _residual;
}
runtime_spec_schema_defs_windows_device;

void free_runtime_spec_schema_defs_windows_device (runtime_spec_schema_defs_windows_device *ptr);

runtime_spec_schema_defs_windows_device *clone_runtime_spec_schema_defs_windows_device (runtime_spec_schema_defs_windows_device *src);
runtime_spec_schema_defs_windows_device *make_runtime_spec_schema_defs_windows_device (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_defs_windows_device (yajl_gen g, const runtime_spec_schema_defs_windows_device *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

