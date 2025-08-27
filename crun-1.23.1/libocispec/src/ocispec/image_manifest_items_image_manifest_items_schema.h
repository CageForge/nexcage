// Generated from image-manifest-items-schema.json. Do not edit!
#ifndef IMAGE_MANIFEST_ITEMS_IMAGE_MANIFEST_ITEMS_SCHEMA_SCHEMA_H
#define IMAGE_MANIFEST_ITEMS_IMAGE_MANIFEST_ITEMS_SCHEMA_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *config;
    char **layers;
    size_t layers_len;

    char **repo_tags;
    size_t repo_tags_len;

    char *parent;
}
image_manifest_items_image_manifest_items_schema_element;

void free_image_manifest_items_image_manifest_items_schema_element (image_manifest_items_image_manifest_items_schema_element *ptr);

image_manifest_items_image_manifest_items_schema_element *make_image_manifest_items_image_manifest_items_schema_element (yajl_val tree, const struct parser_context *ctx, parser_error *err);

typedef struct {
    image_manifest_items_image_manifest_items_schema_element **items;
    size_t len;

}
image_manifest_items_image_manifest_items_schema_container;

void free_image_manifest_items_image_manifest_items_schema_container (image_manifest_items_image_manifest_items_schema_container *ptr);

image_manifest_items_image_manifest_items_schema_container *image_manifest_items_image_manifest_items_schema_container_parse_file(const char *filename, const struct parser_context *ctx, parser_error *err);

image_manifest_items_image_manifest_items_schema_container *image_manifest_items_image_manifest_items_schema_container_parse_file_stream(FILE *stream, const struct parser_context *ctx, parser_error *err);

image_manifest_items_image_manifest_items_schema_container *image_manifest_items_image_manifest_items_schema_container_parse_data(const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *image_manifest_items_image_manifest_items_schema_container_generate_json(const image_manifest_items_image_manifest_items_schema_container *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

