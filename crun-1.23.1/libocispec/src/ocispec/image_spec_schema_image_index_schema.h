// Generated from image-index-schema.json. Do not edit!
#ifndef IMAGE_SPEC_SCHEMA_IMAGE_INDEX_SCHEMA_SCHEMA_H
#define IMAGE_SPEC_SCHEMA_IMAGE_INDEX_SCHEMA_SCHEMA_H

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
    char *architecture;

    char *os;

    char *os_version;

    char **os_features;
    size_t os_features_len;

    char *variant;

    yajl_val _residual;
}
image_spec_schema_image_index_schema_manifests_platform;

void free_image_spec_schema_image_index_schema_manifests_platform (image_spec_schema_image_index_schema_manifests_platform *ptr);

image_spec_schema_image_index_schema_manifests_platform *clone_image_spec_schema_image_index_schema_manifests_platform (image_spec_schema_image_index_schema_manifests_platform *src);
image_spec_schema_image_index_schema_manifests_platform *make_image_spec_schema_image_index_schema_manifests_platform (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_image_index_schema_manifests_platform (yajl_gen g, const image_spec_schema_image_index_schema_manifests_platform *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *media_type;
    int64_t size;
    char *digest;
    char **urls;
    size_t urls_len;

    image_spec_schema_image_index_schema_manifests_platform *platform;
    json_map_string_string *annotations;
    unsigned int size_present : 1;
}
image_spec_schema_image_index_schema_manifests_element;

void free_image_spec_schema_image_index_schema_manifests_element (image_spec_schema_image_index_schema_manifests_element *ptr);

image_spec_schema_image_index_schema_manifests_element *make_image_spec_schema_image_index_schema_manifests_element (yajl_val tree, const struct parser_context *ctx, parser_error *err);

typedef struct {
    int schema_version;

    char *media_type;

    char *artifact_type;

    image_spec_schema_content_descriptor *subject;

    image_spec_schema_image_index_schema_manifests_element **manifests;
    size_t manifests_len;

    json_map_string_string *annotations;

    yajl_val _residual;

    unsigned int schema_version_present : 1;
}
image_spec_schema_image_index_schema;

void free_image_spec_schema_image_index_schema (image_spec_schema_image_index_schema *ptr);

image_spec_schema_image_index_schema *clone_image_spec_schema_image_index_schema (image_spec_schema_image_index_schema *src);
image_spec_schema_image_index_schema *make_image_spec_schema_image_index_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_image_index_schema (yajl_gen g, const image_spec_schema_image_index_schema *ptr, const struct parser_context *ctx, parser_error *err);

image_spec_schema_image_index_schema *image_spec_schema_image_index_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

image_spec_schema_image_index_schema *image_spec_schema_image_index_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

image_spec_schema_image_index_schema *image_spec_schema_image_index_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *image_spec_schema_image_index_schema_generate_json (const image_spec_schema_image_index_schema *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

