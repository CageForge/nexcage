// Generated from features-schema.json. Do not edit!
#ifndef RUNTIME_SPEC_SCHEMA_FEATURES_SCHEMA_SCHEMA_H
#define RUNTIME_SPEC_SCHEMA_FEATURES_SCHEMA_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/runtime_spec_schema_defs.h"
#include "ocispec/runtime_spec_schema_features_linux.h"
#include "ocispec/runtime_spec_schema_defs_linux.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *oci_version_min;

    char *oci_version_max;

    char **hooks;
    size_t hooks_len;

    char **mount_options;
    size_t mount_options_len;

    json_map_string_string *annotations;

    char **potentially_unsafe_config_annotations;
    size_t potentially_unsafe_config_annotations_len;

    runtime_spec_schema_features_linux *linux;

    yajl_val _residual;
}
runtime_spec_schema_features_schema;

void free_runtime_spec_schema_features_schema (runtime_spec_schema_features_schema *ptr);

runtime_spec_schema_features_schema *clone_runtime_spec_schema_features_schema (runtime_spec_schema_features_schema *src);
runtime_spec_schema_features_schema *make_runtime_spec_schema_features_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_features_schema (yajl_gen g, const runtime_spec_schema_features_schema *ptr, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_features_schema *runtime_spec_schema_features_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_features_schema *runtime_spec_schema_features_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

runtime_spec_schema_features_schema *runtime_spec_schema_features_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *runtime_spec_schema_features_schema_generate_json (const runtime_spec_schema_features_schema *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

