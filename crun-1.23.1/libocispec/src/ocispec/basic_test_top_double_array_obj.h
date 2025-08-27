// Generated from test_top_double_array_obj.json. Do not edit!
#ifndef BASIC_TEST_TOP_DOUBLE_ARRAY_OBJ_SCHEMA_H
#define BASIC_TEST_TOP_DOUBLE_ARRAY_OBJ_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool first;
    int32_t second;
    char *third;
    unsigned int first_present : 1;
    unsigned int second_present : 1;
}
basic_test_top_double_array_obj_element;

void free_basic_test_top_double_array_obj_element (basic_test_top_double_array_obj_element *ptr);

basic_test_top_double_array_obj_element *make_basic_test_top_double_array_obj_element (yajl_val tree, const struct parser_context *ctx, parser_error *err);

typedef struct {
    basic_test_top_double_array_obj_element ***items;
    size_t *subitem_lens;

    size_t len;

}
basic_test_top_double_array_obj_container;

void free_basic_test_top_double_array_obj_container (basic_test_top_double_array_obj_container *ptr);

basic_test_top_double_array_obj_container *basic_test_top_double_array_obj_container_parse_file(const char *filename, const struct parser_context *ctx, parser_error *err);

basic_test_top_double_array_obj_container *basic_test_top_double_array_obj_container_parse_file_stream(FILE *stream, const struct parser_context *ctx, parser_error *err);

basic_test_top_double_array_obj_container *basic_test_top_double_array_obj_container_parse_data(const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *basic_test_top_double_array_obj_container_generate_json(const basic_test_top_double_array_obj_container *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

