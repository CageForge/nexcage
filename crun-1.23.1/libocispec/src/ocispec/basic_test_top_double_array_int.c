/* Generated from test_top_double_array_int.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/basic_test_top_double_array_int.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)

define_cleaner_function (basic_test_top_double_array_int_container *, free_basic_test_top_double_array_int_container)
basic_test_top_double_array_int_container
*make_basic_test_top_double_array_int_container (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_basic_test_top_double_array_int_container) basic_test_top_double_array_int_container *ptr = NULL;
    size_t i, alen;
     (void) ctx;
     if (tree == NULL || err == NULL || YAJL_GET_ARRAY (tree) == NULL)
      return NULL;
    *err = NULL;
    alen = YAJL_GET_ARRAY_NO_CHECK (tree)->len;
    if (alen == 0)
      return NULL;
    ptr = calloc (1, sizeof (basic_test_top_double_array_int_container));
    if (ptr == NULL)
      return NULL;
    ptr->items = calloc (alen + 1, sizeof(*ptr->items));
    if (ptr->items == NULL)
      return NULL;
    ptr->len = alen;
    ptr->subitem_lens = calloc ( alen + 1, sizeof (size_t));
    if (ptr->subitem_lens == NULL)
      return NULL;

    for (i = 0; i < alen; i++)
      {
        yajl_val work = YAJL_GET_ARRAY_NO_CHECK (tree)->values[i];
        ptr->items[i] = calloc ( YAJL_GET_ARRAY_NO_CHECK(work)->len + 1, sizeof (**ptr->items));
        if (ptr->items[i] == NULL)
          return NULL;
        size_t j;
        yajl_val *tmps = YAJL_GET_ARRAY_NO_CHECK(work)->values;
        for (j = 0; j < YAJL_GET_ARRAY_NO_CHECK(work)->len; j++)
          {
            yajl_val val = tmps[j];
            if (val != NULL)
              {
                int invalid;
                if (! YAJL_IS_NUMBER (val))
                  {
                    *err = strdup ("invalid type");
                    return NULL;
                  }
                invalid = common_safe_int32 (YAJL_GET_NUMBER (val), &ptr->items[i][j]);
                if (invalid)
                  {
                    if (asprintf (err, "Invalid value '%s' with type 'int32' for key '': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                        *err = strdup ("error allocating memory");
                    return NULL;
                }
            }
            ptr->subitem_lens[i] += 1;
          }


      }
    return move_ptr(ptr);
}


void free_basic_test_top_double_array_int_container (basic_test_top_double_array_int_container *ptr)
{
    size_t i;

    if (ptr == NULL)
        return;

    for (i = 0; i < ptr->len; i++)
      {
        free (ptr->items[i]);
        ptr->items[i] = NULL;

      }
    free (ptr->subitem_lens);
    ptr->subitem_lens = NULL;

    free (ptr->items);
    ptr->items = NULL;


    free (ptr);
}
yajl_gen_status gen_basic_test_top_double_array_int_container (yajl_gen g, const basic_test_top_double_array_int_container *ptr, const struct parser_context *ctx,
                       parser_error *err)
{
    yajl_gen_status stat;
    size_t i;

    if (ptr == NULL)
        return yajl_gen_status_ok;
    *err = NULL;


    stat = yajl_gen_array_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    for (i = 0; i < ptr->len; i++)
      {
        {
            stat = yajl_gen_array_open ((yajl_gen) g);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
            size_t j;
            for (j = 0; j < ptr->subitem_lens[i]; j++)
              {
                stat = map_int (g, ptr->items[i][j]);
                if (stat != yajl_gen_status_ok)
                    GEN_SET_ERROR_AND_RETURN (stat, err);
            }
            stat = yajl_gen_array_close ((yajl_gen) g);


            }
      }
    stat = yajl_gen_array_close ((yajl_gen) g);


    if (ptr->len > 0 && !(ctx->options & OPT_GEN_SIMPLIFY))
        yajl_gen_config (g, yajl_gen_beautify, 1);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

basic_test_top_double_array_int_container *
basic_test_top_double_array_int_container_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
basic_test_top_double_array_int_container *ptr = NULL;size_t filesize;
    __auto_free char *content = NULL;

    if (filename == NULL || err == NULL)
      return NULL;

    *err = NULL;
    content = read_file (filename, &filesize);
    if (content == NULL)
      {
        if (asprintf (err, "cannot read the file: %s", filename) < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }ptr = basic_test_top_double_array_int_container_parse_data (content, ctx, err);return ptr;
}
basic_test_top_double_array_int_container * 
basic_test_top_double_array_int_container_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{basic_test_top_double_array_int_container *ptr = NULL;
size_t filesize;
    __auto_free char *content = NULL;

    if (stream == NULL || err == NULL)
      return NULL;

    *err = NULL;
    content = fread_file (stream, &filesize);
    if (content == NULL)
      {
        *err = strdup ("cannot read the file");
        return NULL;
      }
ptr = basic_test_top_double_array_int_container_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 basic_test_top_double_array_int_container * basic_test_top_double_array_int_container_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  basic_test_top_double_array_int_container *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
    char errbuf[1024];
    struct parser_context tmp_ctx = { 0 };

    if (jsondata == NULL || err == NULL)
      return NULL;

    *err = NULL;
    if (ctx == NULL)
     ctx = (const struct parser_context *)(&tmp_ctx);

    tree = yajl_tree_parse (jsondata, errbuf, sizeof (errbuf));
    if (tree == NULL)
      {
        if (asprintf (err, "cannot parse the data: %s", errbuf) < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
ptr = make_basic_test_top_double_array_int_container (tree, ctx, err);return ptr; 
}

static void
cleanup_yajl_gen (yajl_gen g)
{
    if (!g)
      return;
    yajl_gen_clear (g);
    yajl_gen_free (g);
}

define_cleaner_function (yajl_gen, cleanup_yajl_gen)


 char * 
basic_test_top_double_array_int_container_generate_json (const basic_test_top_double_array_int_container *ptr, const struct parser_context *ctx, parser_error *err){
    __auto_cleanup(cleanup_yajl_gen) yajl_gen g = NULL;
    struct parser_context tmp_ctx = { 0 };
    const unsigned char *gen_buf = NULL;
    char *json_buf = NULL;
    size_t gen_len = 0;

    if (ptr == NULL || err == NULL)
      return NULL;

    *err = NULL;
    if (ctx == NULL)
        ctx = (const struct parser_context *)(&tmp_ctx);

    if (!json_gen_init(&g, ctx))
      {
        *err = strdup ("Json_gen init failed");
        return json_buf;
      } 

if (yajl_gen_status_ok != gen_basic_test_top_double_array_int_container (g, ptr, ctx, err))  {
        if (*err == NULL)
            *err = strdup ("Failed to generate json");
        return json_buf;
      }

    yajl_gen_get_buf (g, &gen_buf, &gen_len);
    if (gen_buf == NULL)
      {
        *err = strdup ("Error to get generated json");
        return json_buf;
      }

    json_buf = calloc (1, gen_len + 1);
    if (json_buf == NULL)
      {
        *err = strdup ("Cannot allocate memory");
        return json_buf;
      }
    (void) memcpy (json_buf, gen_buf, gen_len);
    json_buf[gen_len] = '\0';

    return json_buf;
}
