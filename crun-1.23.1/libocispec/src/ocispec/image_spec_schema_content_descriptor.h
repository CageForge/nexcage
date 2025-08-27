// Generated from content-descriptor.json. Do not edit!
#ifndef IMAGE_SPEC_SCHEMA_CONTENT_DESCRIPTOR_SCHEMA_H
#define IMAGE_SPEC_SCHEMA_CONTENT_DESCRIPTOR_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/image_spec_schema_defs_descriptor.h"
#include "ocispec/image_spec_schema_defs.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *media_type;

    int64_t size;

    char *digest;

    char **urls;
    size_t urls_len;

    char *data;

    char *artifact_type;

    json_map_string_string *annotations;

    yajl_val _residual;

    unsigned int size_present : 1;
}
image_spec_schema_content_descriptor;

void free_image_spec_schema_content_descriptor (image_spec_schema_content_descriptor *ptr);

image_spec_schema_content_descriptor *clone_image_spec_schema_content_descriptor (image_spec_schema_content_descriptor *src);
image_spec_schema_content_descriptor *make_image_spec_schema_content_descriptor (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_content_descriptor (yajl_gen g, const image_spec_schema_content_descriptor *ptr, const struct parser_context *ctx, parser_error *err);

image_spec_schema_content_descriptor *image_spec_schema_content_descriptor_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

image_spec_schema_content_descriptor *image_spec_schema_content_descriptor_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

image_spec_schema_content_descriptor *image_spec_schema_content_descriptor_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *image_spec_schema_content_descriptor_generate_json (const image_spec_schema_content_descriptor *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

