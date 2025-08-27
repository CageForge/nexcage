// Generated from image-manifest-schema.json. Do not edit!
#ifndef IMAGE_SPEC_SCHEMA_IMAGE_MANIFEST_SCHEMA_SCHEMA_H
#define IMAGE_SPEC_SCHEMA_IMAGE_MANIFEST_SCHEMA_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/image_spec_schema_defs_descriptor.h"
#include "ocispec/image_spec_schema_content_descriptor.h"
#include "ocispec/image_spec_schema_defs.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int schema_version;

    char *media_type;

    char *artifact_type;

    image_spec_schema_content_descriptor *config;

    image_spec_schema_content_descriptor *subject;

    image_spec_schema_content_descriptor **layers;
    size_t layers_len;

    json_map_string_string *annotations;

    yajl_val _residual;

    unsigned int schema_version_present : 1;
}
image_spec_schema_image_manifest_schema;

void free_image_spec_schema_image_manifest_schema (image_spec_schema_image_manifest_schema *ptr);

image_spec_schema_image_manifest_schema *clone_image_spec_schema_image_manifest_schema (image_spec_schema_image_manifest_schema *src);
image_spec_schema_image_manifest_schema *make_image_spec_schema_image_manifest_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_image_manifest_schema (yajl_gen g, const image_spec_schema_image_manifest_schema *ptr, const struct parser_context *ctx, parser_error *err);

image_spec_schema_image_manifest_schema *image_spec_schema_image_manifest_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

image_spec_schema_image_manifest_schema *image_spec_schema_image_manifest_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

image_spec_schema_image_manifest_schema *image_spec_schema_image_manifest_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *image_spec_schema_image_manifest_schema_generate_json (const image_spec_schema_image_manifest_schema *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

