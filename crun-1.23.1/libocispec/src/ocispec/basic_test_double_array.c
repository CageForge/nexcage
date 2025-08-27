/* Generated from test_double_array.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/basic_test_double_array.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (basic_test_double_array_objectarrays_element *, free_basic_test_double_array_objectarrays_element)
basic_test_double_array_objectarrays_element *
make_basic_test_double_array_objectarrays_element (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_basic_test_double_array_objectarrays_element) basic_test_double_array_objectarrays_element *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "first", yajl_t_true);
        if (val != NULL)
          {
            ret->first = YAJL_IS_TRUE(val);
            ret->first_present = 1;
          }
        else
          {
            val = get_val (tree, "first", yajl_t_false);
            if (val != NULL)
              {
                ret->first = 0;
                ret->first_present = 1;
              }
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "second", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->second = strdup (str ? str : "");
            if (ret->second == NULL)
              return NULL;
          }
      }
    while (0);
    return move_ptr (ret);
}

void
free_basic_test_double_array_objectarrays_element (basic_test_double_array_objectarrays_element *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->second);
    ptr->second = NULL;
    free (ptr);
}

yajl_gen_status
gen_basic_test_double_array_objectarrays_element (yajl_gen g, const basic_test_double_array_objectarrays_element *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->first_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("first"), 5 /* strlen ("first") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->first)
            b = ptr->first;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->second != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("second"), 6 /* strlen ("second") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->second != NULL)
            str = ptr->second;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

basic_test_double_array_objectarrays_element *
clone_basic_test_double_array_objectarrays_element (basic_test_double_array_objectarrays_element *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_basic_test_double_array_objectarrays_element) basic_test_double_array_objectarrays_element *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->first = src->first;
    ret->first_present = src->first_present;
    if (src->second)
      {
        ret->second = strdup (src->second);
        if (ret->second == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (basic_test_double_array *, free_basic_test_double_array)
basic_test_double_array *
make_basic_test_double_array (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_basic_test_double_array) basic_test_double_array *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "strarrays", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->strarrays_len = len;
            ret->strarrays = calloc (len + 1, sizeof (*ret->strarrays));
            if (ret->strarrays == NULL)
              return NULL;
            ret->strarrays_item_lens = calloc ( len + 1, sizeof (size_t));
            if (ret->strarrays_item_lens == NULL)
                return NULL;
            for (i = 0; i < len; i++)
              {
                    yajl_val *items = YAJL_GET_ARRAY_NO_CHECK(values[i])->values;
                    ret->strarrays[i] = calloc ( YAJL_GET_ARRAY_NO_CHECK(values[i])->len + 1, sizeof (**ret->strarrays));
                    if (ret->strarrays[i] == NULL)
                        return NULL;
                    size_t j;
                    for (j = 0; j < YAJL_GET_ARRAY_NO_CHECK(values[i])->len; j++)
                      {
                    yajl_val val = items[j];
                    if (val != NULL)
                      {
                        char *str = YAJL_GET_STRING (val);
                        ret->strarrays[i][j] = strdup (str ? str : "");
                        if (ret->strarrays[i][j] == NULL)
                          return NULL;
                      }
                        ret->strarrays_item_lens[i] += 1;
                    };
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "intarrays", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->intarrays_len = len;
            ret->intarrays = calloc (len + 1, sizeof (*ret->intarrays));
            if (ret->intarrays == NULL)
              return NULL;
            ret->intarrays_item_lens = calloc ( len + 1, sizeof (size_t));
            if (ret->intarrays_item_lens == NULL)
                return NULL;
            for (i = 0; i < len; i++)
              {
                    yajl_val *items = YAJL_GET_ARRAY_NO_CHECK(values[i])->values;
                    ret->intarrays[i] = calloc ( YAJL_GET_ARRAY_NO_CHECK(values[i])->len + 1, sizeof (**ret->intarrays));
                    if (ret->intarrays[i] == NULL)
                        return NULL;
                    size_t j;
                    for (j = 0; j < YAJL_GET_ARRAY_NO_CHECK(values[i])->len; j++)
                      {
                    yajl_val val = items[j];
                    if (val != NULL)
                      {
                        int invalid;
                        if (! YAJL_IS_NUMBER (val))
                          {
                            *err = strdup ("invalid type");
                            return NULL;
                          }
                        invalid = common_safe_int32 (YAJL_GET_NUMBER (val), &ret->intarrays[i][j]);
                        if (invalid)
                          {
                            if (asprintf (err, "Invalid value '%s' with type 'int32' for key 'intarrays': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                                *err = strdup ("error allocating memory");
                            return NULL;
                        }
                    }
                        ret->intarrays_item_lens[i] += 1;
                    };
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "boolarrays", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->boolarrays_len = len;
            ret->boolarrays = calloc (len + 1, sizeof (*ret->boolarrays));
            if (ret->boolarrays == NULL)
              return NULL;
            ret->boolarrays_item_lens = calloc ( len + 1, sizeof (size_t));
            if (ret->boolarrays_item_lens == NULL)
                return NULL;
            for (i = 0; i < len; i++)
              {
                    yajl_val *items = YAJL_GET_ARRAY_NO_CHECK(values[i])->values;
                    ret->boolarrays[i] = calloc ( YAJL_GET_ARRAY_NO_CHECK(values[i])->len + 1, sizeof (**ret->boolarrays));
                    if (ret->boolarrays[i] == NULL)
                        return NULL;
                    size_t j;
                    for (j = 0; j < YAJL_GET_ARRAY_NO_CHECK(values[i])->len; j++)
                      {
                    yajl_val val = items[j];
                    if (val != NULL)
                      {
                        ret->boolarrays[i][j] = YAJL_IS_TRUE(val);
                      }
                        ret->boolarrays_item_lens[i] += 1;
                    };
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "objectarrays", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->objectarrays_len = len;
            ret->objectarrays = calloc (len + 1, sizeof (*ret->objectarrays));
            if (ret->objectarrays == NULL)
              return NULL;
            ret->objectarrays_item_lens = calloc ( len + 1, sizeof (size_t));
            if (ret->objectarrays_item_lens == NULL)
                return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                size_t j;
                ret->objectarrays[i] = calloc ( YAJL_GET_ARRAY_NO_CHECK(val)->len + 1, sizeof (**ret->objectarrays));
                if (ret->objectarrays[i] == NULL)
                    return NULL;
                yajl_val *items = YAJL_GET_ARRAY_NO_CHECK(val)->values;
                for (j = 0; j < YAJL_GET_ARRAY_NO_CHECK(val)->len; j++)
                  {
                    ret->objectarrays[i][j] = make_basic_test_double_array_objectarrays_element (items[j], ctx, err);
                    if (ret->objectarrays[i][j] == NULL)
                        return NULL;
                    ret->objectarrays_item_lens[i] += 1;
                  };
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "refobjarrays", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->refobjarrays_len = len;
            ret->refobjarrays = calloc (len + 1, sizeof (*ret->refobjarrays));
            if (ret->refobjarrays == NULL)
              return NULL;
            ret->refobjarrays_item_lens = calloc ( len + 1, sizeof (size_t));
            if (ret->refobjarrays_item_lens == NULL)
                return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                size_t j;
                ret->refobjarrays[i] = calloc ( YAJL_GET_ARRAY_NO_CHECK(val)->len + 1, sizeof (**ret->refobjarrays));
                if (ret->refobjarrays[i] == NULL)
                    return NULL;
                yajl_val *items = YAJL_GET_ARRAY_NO_CHECK(val)->values;
                for (j = 0; j < YAJL_GET_ARRAY_NO_CHECK(val)->len; j++)
                  {
                    ret->refobjarrays[i][j] = make_basic_test_double_array_item (items[j], ctx, err);
                    if (ret->refobjarrays[i][j] == NULL)
                        return NULL;
                    ret->refobjarrays_item_lens[i] += 1;
                  };
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
            if (strcmp (tree->u.object.keys[i], "strarrays")
                && strcmp (tree->u.object.keys[i], "intarrays")
                && strcmp (tree->u.object.keys[i], "boolarrays")
                && strcmp (tree->u.object.keys[i], "objectarrays")
                && strcmp (tree->u.object.keys[i], "refobjarrays")){
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
free_basic_test_double_array (basic_test_double_array *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->strarrays != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->strarrays_len; i++)
          {
            size_t j;
            for (j = 0; j < ptr->strarrays_item_lens[i]; j++)
              {
                free (ptr->strarrays[i][j]);
                ptr->strarrays[i][j] = NULL;
            }
            if (ptr->strarrays[i] != NULL)
              {
                free (ptr->strarrays[i]);
                ptr->strarrays[i] = NULL;
              }
          }
        free (ptr->strarrays_item_lens);
        ptr->strarrays_item_lens = NULL;
        free (ptr->strarrays);
        ptr->strarrays = NULL;
    }
   {
            size_t i;
            for (i = 0; i < ptr->intarrays_len; i++)
              {
                free (ptr->intarrays[i]);
                ptr->intarrays[i] = NULL;
              }
            free (ptr->intarrays_item_lens);
            ptr->intarrays_item_lens = NULL;
        free (ptr->intarrays);
        ptr->intarrays = NULL;
    }
   {
            size_t i;
            for (i = 0; i < ptr->boolarrays_len; i++)
              {
                free (ptr->boolarrays[i]);
                ptr->boolarrays[i] = NULL;
              }
            free (ptr->boolarrays_item_lens);
            ptr->boolarrays_item_lens = NULL;
        free (ptr->boolarrays);
        ptr->boolarrays = NULL;
    }
    if (ptr->objectarrays != NULL)      {
        size_t i;
        for (i = 0; i < ptr->objectarrays_len; i++)
          {
          size_t j;
          for (j = 0; j < ptr->objectarrays_item_lens[i]; j++)
            {
              free_basic_test_double_array_objectarrays_element (ptr->objectarrays[i][j]);
              ptr->objectarrays[i][j] = NULL;
          }
        free (ptr->objectarrays[i]);
        ptr->objectarrays[i] = NULL;
          }
        free (ptr->objectarrays_item_lens);
        ptr->objectarrays_item_lens = NULL;
        free (ptr->objectarrays);
        ptr->objectarrays = NULL;
      }
    if (ptr->refobjarrays != NULL)      {
        size_t i;
        for (i = 0; i < ptr->refobjarrays_len; i++)
          {
          size_t j;
          for (j = 0; j < ptr->refobjarrays_item_lens[i]; j++)
            {
              free_basic_test_double_array_item (ptr->refobjarrays[i][j]);
              ptr->refobjarrays[i][j] = NULL;
          }
        free (ptr->refobjarrays[i]);
        ptr->refobjarrays[i] = NULL;
          }
        free (ptr->refobjarrays_item_lens);
        ptr->refobjarrays_item_lens = NULL;
        free (ptr->refobjarrays);
        ptr->refobjarrays = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_basic_test_double_array (yajl_gen g, const basic_test_double_array *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->strarrays != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("strarrays"), 9 /* strlen ("strarrays") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->strarrays != NULL)
          len = ptr->strarrays_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_array_open ((yajl_gen) g);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
            size_t j;
            for (j = 0; j < ptr->strarrays_item_lens[i]; j++)
              {
                stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->strarrays[i][j]), strlen (ptr->strarrays[i][j]));
                if (stat != yajl_gen_status_ok)
                    GEN_SET_ERROR_AND_RETURN (stat, err);
              }
            stat = yajl_gen_array_close ((yajl_gen) g);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->intarrays != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("intarrays"), 9 /* strlen ("intarrays") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->intarrays != NULL)
          len = ptr->intarrays_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_array_open ((yajl_gen) g);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
            size_t j;
            for (j = 0; j < ptr->intarrays_item_lens[i]; j++)
              {
                stat = map_int (g, ptr->intarrays[i][j]);
                if (stat != yajl_gen_status_ok)
                    GEN_SET_ERROR_AND_RETURN (stat, err);
              }
            stat = yajl_gen_array_close ((yajl_gen) g);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->boolarrays != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("boolarrays"), 10 /* strlen ("boolarrays") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->boolarrays != NULL)
          len = ptr->boolarrays_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_array_open ((yajl_gen) g);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
            size_t j;
            for (j = 0; j < ptr->boolarrays_item_lens[i]; j++)
              {
                stat = yajl_gen_bool ((yajl_gen)g, (int)(ptr->boolarrays[i][j]));
                if (stat != yajl_gen_status_ok)
                    GEN_SET_ERROR_AND_RETURN (stat, err);
              }
            stat = yajl_gen_array_close ((yajl_gen) g);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->objectarrays != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("objectarrays"), 12 /* strlen ("objectarrays") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->objectarrays != NULL)
            len = ptr->objectarrays_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_array_open ((yajl_gen) g);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
            size_t j;
            for (j = 0; j < ptr->objectarrays_item_lens[i]; j++)
              {
                stat = gen_basic_test_double_array_objectarrays_element (g, ptr->objectarrays[i][j], ctx, err);
                if (stat != yajl_gen_status_ok)
                    GEN_SET_ERROR_AND_RETURN (stat, err);
              }
            stat = yajl_gen_array_close ((yajl_gen) g);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->refobjarrays != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("refobjarrays"), 12 /* strlen ("refobjarrays") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->refobjarrays != NULL)
            len = ptr->refobjarrays_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_array_open ((yajl_gen) g);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
            size_t j;
            for (j = 0; j < ptr->refobjarrays_item_lens[i]; j++)
              {
                stat = gen_basic_test_double_array_item (g, ptr->refobjarrays[i][j], ctx, err);
                if (stat != yajl_gen_status_ok)
                    GEN_SET_ERROR_AND_RETURN (stat, err);
              }
            stat = yajl_gen_array_close ((yajl_gen) g);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
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

basic_test_double_array *
clone_basic_test_double_array (basic_test_double_array *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_basic_test_double_array) basic_test_double_array *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->strarrays)
      {
        ret->strarrays_len = src->strarrays_len;
        ret->strarrays = calloc (src->strarrays_len + 1, sizeof (*ret->strarrays));
        if (ret->strarrays == NULL)
          return NULL;
        for (size_t i = 0; i < src->strarrays_len; i++)
          {
            ret->strarrays[i] = calloc (ret->strarrays_item_lens[i] + 1, sizeof (**ret->strarrays[i]));
            if (ret->strarrays[i] == NULL)
                return NULL;
            for (size_t j = 0; j < src->strarrays_item_lens[i]; j++)
              {
                ret->strarrays[i][j] = strdup (src->strarrays[i][j]);
                if (ret->strarrays[i][j] == NULL)
                    return NULL;
              }
          }
      }
    if (src->intarrays)
      {
        ret->intarrays_len = src->intarrays_len;
        ret->intarrays = calloc (src->intarrays_len + 1, sizeof (*ret->intarrays));
        if (ret->intarrays == NULL)
          return NULL;
        for (size_t i = 0; i < src->intarrays_len; i++)
          {
            ret->intarrays[i] = src->intarrays[i];
          }
      }
    if (src->boolarrays)
      {
        ret->boolarrays_len = src->boolarrays_len;
        ret->boolarrays = calloc (src->boolarrays_len + 1, sizeof (*ret->boolarrays));
        if (ret->boolarrays == NULL)
          return NULL;
        for (size_t i = 0; i < src->boolarrays_len; i++)
          {
            ret->boolarrays[i] = src->boolarrays[i];
          }
      }
    if (src->objectarrays)
      {
        ret->objectarrays_len = src->objectarrays_len;
        ret->objectarrays = calloc (src->objectarrays_len + 1, sizeof (*ret->objectarrays));
        if (ret->objectarrays == NULL)
          return NULL;
        for (size_t i = 0; i < src->objectarrays_len; i++)
          {
            ret->objectarrays_item_lens[i] = src->objectarrays_item_lens[i];
            ret->objectarrays[i] = calloc (ret->objectarrays_item_lens[i] + 1, sizeof (**ret->objectarrays[i]));
            if (ret->objectarrays[i] == NULL)
                return NULL;
            for (size_t j = 0; j < src->objectarrays_item_lens[i]; j++)
              {
                ret->objectarrays[i][j] = clone_basic_test_double_array_objectarrays_element (src->objectarrays[i][j]);
                if (ret->objectarrays[i][j] == NULL)
                    return NULL;
              }
          }
      }
    if (src->refobjarrays)
      {
        ret->refobjarrays_len = src->refobjarrays_len;
        ret->refobjarrays = calloc (src->refobjarrays_len + 1, sizeof (*ret->refobjarrays));
        if (ret->refobjarrays == NULL)
          return NULL;
        for (size_t i = 0; i < src->refobjarrays_len; i++)
          {
            ret->refobjarrays_item_lens[i] = src->refobjarrays_item_lens[i];
            ret->refobjarrays[i] = calloc (ret->refobjarrays_item_lens[i] + 1, sizeof (**ret->refobjarrays[i]));
            if (ret->refobjarrays[i] == NULL)
                return NULL;
            for (size_t j = 0; j < src->refobjarrays_item_lens[i]; j++)
              {
                ret->refobjarrays[i][j] = clone_basic_test_double_array_item (src->refobjarrays[i][j]);
                if (ret->refobjarrays[i][j] == NULL)
                    return NULL;
              }
          }
      }
    return move_ptr (ret);
}


basic_test_double_array *
basic_test_double_array_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
basic_test_double_array *ptr = NULL;size_t filesize;
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
      }ptr = basic_test_double_array_parse_data (content, ctx, err);return ptr;
}
basic_test_double_array * 
basic_test_double_array_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{basic_test_double_array *ptr = NULL;
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
ptr = basic_test_double_array_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 basic_test_double_array * basic_test_double_array_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  basic_test_double_array *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
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
ptr = make_basic_test_double_array (tree, ctx, err);return ptr; 
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
basic_test_double_array_generate_json (const basic_test_double_array *ptr, const struct parser_context *ctx, parser_error *err){
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

if (yajl_gen_status_ok != gen_basic_test_double_array (g, ptr, ctx, err))  {
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
