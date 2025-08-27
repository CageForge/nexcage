// Generated from test_double_array_item.json. Do not edit!
#ifndef BASIC_TEST_DOUBLE_ARRAY_ITEM_SCHEMA_H
#define BASIC_TEST_DOUBLE_ARRAY_ITEM_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *item1;

    int32_t item2;

    bool item3;

    yajl_val _residual;

    unsigned int item2_present : 1;
    unsigned int item3_present : 1;
}
basic_test_double_array_item;

void free_basic_test_double_array_item (basic_test_double_array_item *ptr);

basic_test_double_array_item *clone_basic_test_double_array_item (basic_test_double_array_item *src);
basic_test_double_array_item *make_basic_test_double_array_item (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_basic_test_double_array_item (yajl_gen g, const basic_test_double_array_item *ptr, const struct parser_context *ctx, parser_error *err);

basic_test_double_array_item *basic_test_double_array_item_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

basic_test_double_array_item *basic_test_double_array_item_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

basic_test_double_array_item *basic_test_double_array_item_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *basic_test_double_array_item_generate_json (const basic_test_double_array_item *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

