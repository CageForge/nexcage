/* Generated from test_double_array_item.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/basic_test_double_array_item.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (basic_test_double_array_item *, free_basic_test_double_array_item)
basic_test_double_array_item *
make_basic_test_double_array_item (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_basic_test_double_array_item) basic_test_double_array_item *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "item1", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->item1 = strdup (str ? str : "");
            if (ret->item1 == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "item2", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int32 (YAJL_GET_NUMBER (val), &ret->item2);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int32' for key 'item2': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->item2_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "item3", yajl_t_true);
        if (val != NULL)
          {
            ret->item3 = YAJL_IS_TRUE(val);
            ret->item3_present = 1;
          }
        else
          {
            val = get_val (tree, "item3", yajl_t_false);
            if (val != NULL)
              {
                ret->item3 = 0;
                ret->item3_present = 1;
              }
          }
      }
    while (0);

    if (tree->type == yajl_t_object)
      {
        size_t i;
        size_t j = 0;
        size_t cnt = tree->u.object.len;
        yajl_val resi = NULL;

        if (ctx->options & OPT_PARSE_FULLKEY)
          {
            resi = calloc (1, sizeof(*tree));
            if (resi == NULL)
              return NULL;

            resi->type = yajl_t_object;
            resi->u.object.keys = calloc (cnt, sizeof (const char *));
            if (resi->u.object.keys == NULL)
              {
                yajl_tree_free (resi);
                return NULL;
              }
            resi->u.object.values = calloc (cnt, sizeof (yajl_val));
            if (resi->u.object.values == NULL)
              {
                yajl_tree_free (resi);
                return NULL;
              }
          }

        for (i = 0; i < tree->u.object.len; i++)
          {
            if (strcmp (tree->u.object.keys[i], "item1")
                && strcmp (tree->u.object.keys[i], "item2")
                && strcmp (tree->u.object.keys[i], "item3")){
                if (ctx->options & OPT_PARSE_FULLKEY)
                  {
                    resi->u.object.keys[j] = tree->u.object.keys[i];
                    tree->u.object.keys[i] = NULL;
                    resi->u.object.values[j] = tree->u.object.values[i];
                    tree->u.object.values[i] = NULL;
                    resi->u.object.len++;
                  }
                j++;
              }
          }

        if ((ctx->options & OPT_PARSE_STRICT) && j > 0 && ctx->errfile != NULL)
          (void) fprintf (ctx->errfile, "WARNING: unknown key found\n");

        if (ctx->options & OPT_PARSE_FULLKEY)
          ret->_residual = resi;
      }
    return move_ptr (ret);
}

void
free_basic_test_double_array_item (basic_test_double_array_item *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->item1);
    ptr->item1 = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_basic_test_double_array_item (yajl_gen g, const basic_test_double_array_item *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->item1 != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("item1"), 5 /* strlen ("item1") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->item1 != NULL)
            str = ptr->item1;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->item2_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("item2"), 5 /* strlen ("item2") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->item2)
            num = (long long int)ptr->item2;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->item3_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("item3"), 5 /* strlen ("item3") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->item3)
            b = ptr->item3;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if (ptr != NULL && ptr->_residual != NULL)
      {
        stat = gen_yajl_object_residual (ptr->_residual, g, err);
        if (yajl_gen_status_ok != stat)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

basic_test_double_array_item *
clone_basic_test_double_array_item (basic_test_double_array_item *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_basic_test_double_array_item) basic_test_double_array_item *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->item1)
      {
        ret->item1 = strdup (src->item1);
        if (ret->item1 == NULL)
          return NULL;
      }
    ret->item2 = src->item2;
    ret->item2_present = src->item2_present;
    ret->item3 = src->item3;
    ret->item3_present = src->item3_present;
    return move_ptr (ret);
}


basic_test_double_array_item *
basic_test_double_array_item_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
basic_test_double_array_item *ptr = NULL;size_t filesize;
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
      }ptr = basic_test_double_array_item_parse_data (content, ctx, err);return ptr;
}
basic_test_double_array_item * 
basic_test_double_array_item_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{basic_test_double_array_item *ptr = NULL;
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
ptr = basic_test_double_array_item_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 basic_test_double_array_item * basic_test_double_array_item_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  basic_test_double_array_item *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
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
ptr = make_basic_test_double_array_item (tree, ctx, err);return ptr; 
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
basic_test_double_array_item_generate_json (const basic_test_double_array_item *ptr, const struct parser_context *ctx, parser_error *err){
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

if (yajl_gen_status_ok != gen_basic_test_double_array_item (g, ptr, ctx, err))  {
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
