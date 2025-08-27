// Generated from config-schema.json. Do not edit!
#ifndef IMAGE_SPEC_SCHEMA_CONFIG_SCHEMA_SCHEMA_H
#define IMAGE_SPEC_SCHEMA_CONFIG_SCHEMA_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/image_spec_schema_defs.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *user;

    image_spec_schema_defs_map_string_object *exposed_ports;

    char **env;
    size_t env_len;

    char **entrypoint;
    size_t entrypoint_len;

    char **cmd;
    size_t cmd_len;

    image_spec_schema_defs_map_string_object *volumes;

    char *working_dir;

    json_map_string_string *labels;

    char *stop_signal;

    bool args_escaped;

    yajl_val _residual;

    unsigned int args_escaped_present : 1;
}
image_spec_schema_config_schema_config;

void free_image_spec_schema_config_schema_config (image_spec_schema_config_schema_config *ptr);

image_spec_schema_config_schema_config *clone_image_spec_schema_config_schema_config (image_spec_schema_config_schema_config *src);
image_spec_schema_config_schema_config *make_image_spec_schema_config_schema_config (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_config_schema_config (yajl_gen g, const image_spec_schema_config_schema_config *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char **diff_ids;
    size_t diff_ids_len;

    char *type;

    yajl_val _residual;
}
image_spec_schema_config_schema_rootfs;

void free_image_spec_schema_config_schema_rootfs (image_spec_schema_config_schema_rootfs *ptr);

image_spec_schema_config_schema_rootfs *clone_image_spec_schema_config_schema_rootfs (image_spec_schema_config_schema_rootfs *src);
image_spec_schema_config_schema_rootfs *make_image_spec_schema_config_schema_rootfs (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_config_schema_rootfs (yajl_gen g, const image_spec_schema_config_schema_rootfs *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *created;
    char *author;
    char *created_by;
    char *comment;
    bool empty_layer;
    unsigned int empty_layer_present : 1;
}
image_spec_schema_config_schema_history_element;

void free_image_spec_schema_config_schema_history_element (image_spec_schema_config_schema_history_element *ptr);

image_spec_schema_config_schema_history_element *make_image_spec_schema_config_schema_history_element (yajl_val tree, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *created;

    char *author;

    char *architecture;

    char *variant;

    char *os;

    char *os_version;

    char **os_features;
    size_t os_features_len;

    image_spec_schema_config_schema_config *config;

    image_spec_schema_config_schema_rootfs *rootfs;

    image_spec_schema_config_schema_history_element **history;
    size_t history_len;

    yajl_val _residual;
}
image_spec_schema_config_schema;

void free_image_spec_schema_config_schema (image_spec_schema_config_schema *ptr);

image_spec_schema_config_schema *clone_image_spec_schema_config_schema (image_spec_schema_config_schema *src);
image_spec_schema_config_schema *make_image_spec_schema_config_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_image_spec_schema_config_schema (yajl_gen g, const image_spec_schema_config_schema *ptr, const struct parser_context *ctx, parser_error *err);

image_spec_schema_config_schema *image_spec_schema_config_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

image_spec_schema_config_schema *image_spec_schema_config_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

image_spec_schema_config_schema *image_spec_schema_config_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *image_spec_schema_config_schema_generate_json (const image_spec_schema_config_schema *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

