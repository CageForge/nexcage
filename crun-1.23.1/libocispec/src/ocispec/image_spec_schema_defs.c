/* Generated from defs.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/image_spec_schema_defs.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (image_spec_schema_defs_map_string_object_element *, free_image_spec_schema_defs_map_string_object_element)
image_spec_schema_defs_map_string_object_element *
make_image_spec_schema_defs_map_string_object_element (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_defs_map_string_object_element) image_spec_schema_defs_map_string_object_element *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    return move_ptr (ret);
}

void
free_image_spec_schema_defs_map_string_object_element (image_spec_schema_defs_map_string_object_element *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_defs_map_string_object_element (yajl_gen g, const image_spec_schema_defs_map_string_object_element *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    if (!(ctx->options & OPT_GEN_SIMPLIFY))
        yajl_gen_config (g, yajl_gen_beautify, 0);
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if (!(ctx->options & OPT_GEN_SIMPLIFY))
        yajl_gen_config (g, yajl_gen_beautify, 1);
    return yajl_gen_status_ok;
}

image_spec_schema_defs_map_string_object_element *
clone_image_spec_schema_defs_map_string_object_element (image_spec_schema_defs_map_string_object_element *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_defs_map_string_object_element) image_spec_schema_defs_map_string_object_element *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    return move_ptr (ret);
}

define_cleaner_function (image_spec_schema_defs_map_string_object *, free_image_spec_schema_defs_map_string_object)
image_spec_schema_defs_map_string_object *
make_image_spec_schema_defs_map_string_object (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_defs_map_string_object) image_spec_schema_defs_map_string_object *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (YAJL_GET_OBJECT (tree) != NULL)
      {
        size_t i;
        size_t len = YAJL_GET_OBJECT_NO_CHECK (tree)->len;
        const char **keys = YAJL_GET_OBJECT_NO_CHECK (tree)->keys;
        yajl_val *values = YAJL_GET_OBJECT_NO_CHECK (tree)->values;
        ret->len = len;
        ret->keys = calloc (len + 1, sizeof (*ret->keys));
        if (ret->keys == NULL)
          return NULL;
        ret->values = calloc (len + 1, sizeof (*ret->values));
        if (ret->values == NULL)
          return NULL;
        for (i = 0; i < len; i++)
          {
            yajl_val val;
            const char *tmpkey = keys[i];
            ret->keys[i] = strdup (tmpkey ? tmpkey : "");
            if (ret->keys[i] == NULL)
              return NULL;
            val = values[i];
            ret->values[i] = make_image_spec_schema_defs_map_string_object_element (val, ctx, err);
            if (ret->values[i] == NULL)
              return NULL;
          }
      }
    return move_ptr (ret);
}

void
free_image_spec_schema_defs_map_string_object (image_spec_schema_defs_map_string_object *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->keys != NULL && ptr->values != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->len; i++)
          {
            free (ptr->keys[i]);
            ptr->keys[i] = NULL;
            free_image_spec_schema_defs_map_string_object_element (ptr->values[i]);
            ptr->values[i] = NULL;
          }
        free (ptr->keys);
        ptr->keys = NULL;
        free (ptr->values);
        ptr->values = NULL;
      }
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_defs_map_string_object (yajl_gen g, const image_spec_schema_defs_map_string_object *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    size_t len = 0, i;
    if (ptr != NULL)
        len = ptr->len;
    if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
        yajl_gen_config (g, yajl_gen_beautify, 0);
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if (len || (ptr != NULL && ptr->keys != NULL && ptr->values != NULL))
      {
        for (i = 0; i < len; i++)
          {
            char *str = ptr->keys[i] ? ptr->keys[i] : "";
            stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)str, strlen (str));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
            stat = gen_image_spec_schema_defs_map_string_object_element (g, ptr->values[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
      }
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
        yajl_gen_config (g, yajl_gen_beautify, 1);
    return yajl_gen_status_ok;
}

image_spec_schema_defs_map_string_object *
clone_image_spec_schema_defs_map_string_object (image_spec_schema_defs_map_string_object *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_defs_map_string_object) image_spec_schema_defs_map_string_object *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->values)
      {
        size_t i;
        ret->values = calloc (src->len + 1, sizeof (*ret->values));
        for (i = 0; i < src->len; i++)
          {
             ret->values[i] = clone_image_spec_schema_defs_map_string_object_element (src->values[i]);
             if (ret->values[i] == NULL)
               return NULL;
          }
      }
    return move_ptr (ret);
}

