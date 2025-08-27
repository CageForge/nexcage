// Generated from test_double_array.json. Do not edit!
#ifndef BASIC_TEST_DOUBLE_ARRAY_SCHEMA_H
#define BASIC_TEST_DOUBLE_ARRAY_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/basic_test_double_array_item.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool first;
    char *second;
    unsigned int first_present : 1;
}
basic_test_double_array_objectarrays_element;

void free_basic_test_double_array_objectarrays_element (basic_test_double_array_objectarrays_element *ptr);

basic_test_double_array_objectarrays_element *make_basic_test_double_array_objectarrays_element (yajl_val tree, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char ***strarrays;
    size_t *strarrays_item_lens;
    size_t strarrays_len;

    int32_t **intarrays;
    size_t *intarrays_item_lens;
    size_t intarrays_len;

    bool **boolarrays;
    size_t *boolarrays_item_lens;
    size_t boolarrays_len;

    basic_test_double_array_objectarrays_element ***objectarrays;
    size_t *objectarrays_item_lens;
    size_t objectarrays_len;

    basic_test_double_array_item ***refobjarrays;
    size_t *refobjarrays_item_lens;
    size_t refobjarrays_len;

    yajl_val _residual;
}
basic_test_double_array;

void free_basic_test_double_array (basic_test_double_array *ptr);

basic_test_double_array *clone_basic_test_double_array (basic_test_double_array *src);
basic_test_double_array *make_basic_test_double_array (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_basic_test_double_array (yajl_gen g, const basic_test_double_array *ptr, const struct parser_context *ctx, parser_error *err);

basic_test_double_array *basic_test_double_array_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err);

basic_test_double_array *basic_test_double_array_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err);

basic_test_double_array *basic_test_double_array_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err);

char *basic_test_double_array_generate_json (const basic_test_double_array *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

