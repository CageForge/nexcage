// Generated from defs-zos.json. Do not edit!
#ifndef RUNTIME_SPEC_SCHEMA_DEFS_ZOS_SCHEMA_H
#define RUNTIME_SPEC_SCHEMA_DEFS_ZOS_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/runtime_spec_schema_defs.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *type;

    char *path;

    yajl_val _residual;
}
runtime_spec_schema_defs_zos_namespace_reference;

void free_runtime_spec_schema_defs_zos_namespace_reference (runtime_spec_schema_defs_zos_namespace_reference *ptr);

runtime_spec_schema_defs_zos_namespace_reference *clone_runtime_spec_schema_defs_zos_namespace_reference (runtime_spec_schema_defs_zos_namespace_reference *src);
runtime_spec_schema_defs_zos_namespace_reference *make_runtime_spec_schema_defs_zos_namespace_reference (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_defs_zos_namespace_reference (yajl_gen g, const runtime_spec_schema_defs_zos_namespace_reference *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

