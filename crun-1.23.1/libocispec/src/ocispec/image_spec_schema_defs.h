// Generated from defs.json. Do not edit!
#ifndef IMAGE_SPEC_SCHEMA_DEFS_SCHEMA_H
#define IMAGE_SPEC_SCHEMA_DEFS_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char unuseful; // unuseful definition to avoid empty struct
}
image_spec_schema_defs_map_string_object_element;

void free_image_spec_schema_defs_map_string_object_element (image_spec_schema_defs_map_string_object_element *ptr);

image_spec_schema_defs_map_string_object_element *clone_image_spec_schema_defs_map_string_object_element (image_spec_schema_defs_map_string_object_element *src);
image_spec_schema_defs_map_string_object_element *make_image_spec_schema_defs_map_string_object_element (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_defs_map_string_object_element (yajl_gen g, const image_spec_schema_defs_map_string_object_element *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char **keys;
    image_spec_schema_defs_map_string_object_element **values;
    size_t len;
}
image_spec_schema_defs_map_string_object;

void free_image_spec_schema_defs_map_string_object (image_spec_schema_defs_map_string_object *ptr);

image_spec_schema_defs_map_string_object *clone_image_spec_schema_defs_map_string_object (image_spec_schema_defs_map_string_object *src);
image_spec_schema_defs_map_string_object *make_image_spec_schema_defs_map_string_object (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_defs_map_string_object (yajl_gen g, const image_spec_schema_defs_map_string_object *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

