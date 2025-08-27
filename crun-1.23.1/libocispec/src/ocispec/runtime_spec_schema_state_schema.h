// Generated from state-schema.json. Do not edit!
#ifndef RUNTIME_SPEC_SCHEMA_STATE_SCHEMA_SCHEMA_H
#define RUNTIME_SPEC_SCHEMA_STATE_SCHEMA_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/runtime_spec_schema_defs.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *oci_version;

    char *id;

    char *status;

    int pid;

    char *bundle;

    json_map_string_string *annotations;

    yajl_val _residual;

    unsigned int pid_present : 1;
}
runtime_spec_schema_state_schema;

void free_runtime_spec_schema_state_schema (runtime_spec_schema_state_schema *ptr);

runtime_spec_schema_state_schema *clone_runtime_spec_schema_state_schema (runtime_spec_schema_state_schema *src);
runtime_spec_schema_state_schema *make_runtime_spec_schema_state_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_state_schema (yajl_gen g, const runtime_spec_schema_state_schema *ptr, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_state_schema *runtime_spec_schema_state_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_state_schema *runtime_spec_schema_state_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_state_schema *runtime_spec_schema_state_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *runtime_spec_schema_state_schema_generate_json (const runtime_spec_schema_state_schema *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

