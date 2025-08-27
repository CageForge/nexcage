// Generated from test_top_double_array_refobj.json. Do not edit!
#ifndef BASIC_TEST_TOP_DOUBLE_ARRAY_REFOBJ_SCHEMA_H
#define BASIC_TEST_TOP_DOUBLE_ARRAY_REFOBJ_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/basic_test_double_array_item.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    basic_test_double_array_item ***items;
    size_t *subitem_lens;

    size_t len;

}
basic_test_top_double_array_refobj_container;

void free_basic_test_top_double_array_refobj_container (basic_test_top_double_array_refobj_container *ptr);

basic_test_top_double_array_refobj_container *basic_test_top_double_array_refobj_container_parse_file(const char *filename, const struct parser_context *ctx, parser_error *err);

basic_test_top_double_array_refobj_container *basic_test_top_double_array_refobj_container_parse_file_stream(FILE *stream, const struct parser_context *ctx, parser_error *err);

basic_test_top_double_array_refobj_container *basic_test_top_double_array_refobj_container_parse_data(const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *basic_test_top_double_array_refobj_container_generate_json(const basic_test_top_double_array_refobj_container *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

