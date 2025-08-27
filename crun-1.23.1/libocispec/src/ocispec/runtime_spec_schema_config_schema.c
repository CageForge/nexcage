/* Generated from config-schema.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_config_schema.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_config_schema_hooks *, free_runtime_spec_schema_config_schema_hooks)
runtime_spec_schema_config_schema_hooks *
make_runtime_spec_schema_config_schema_hooks (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_hooks) runtime_spec_schema_config_schema_hooks *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "prestart", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->prestart_len = len;
            ret->prestart = calloc (len + 1, sizeof (*ret->prestart));
            if (ret->prestart == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->prestart[i] = make_runtime_spec_schema_defs_hook (val, ctx, err);
                if (ret->prestart[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "createRuntime", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->create_runtime_len = len;
            ret->create_runtime = calloc (len + 1, sizeof (*ret->create_runtime));
            if (ret->create_runtime == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->create_runtime[i] = make_runtime_spec_schema_defs_hook (val, ctx, err);
                if (ret->create_runtime[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "createContainer", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->create_container_len = len;
            ret->create_container = calloc (len + 1, sizeof (*ret->create_container));
            if (ret->create_container == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->create_container[i] = make_runtime_spec_schema_defs_hook (val, ctx, err);
                if (ret->create_container[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "startContainer", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->start_container_len = len;
            ret->start_container = calloc (len + 1, sizeof (*ret->start_container));
            if (ret->start_container == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->start_container[i] = make_runtime_spec_schema_defs_hook (val, ctx, err);
                if (ret->start_container[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "poststart", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->poststart_len = len;
            ret->poststart = calloc (len + 1, sizeof (*ret->poststart));
            if (ret->poststart == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->poststart[i] = make_runtime_spec_schema_defs_hook (val, ctx, err);
                if (ret->poststart[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "poststop", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->poststop_len = len;
            ret->poststop = calloc (len + 1, sizeof (*ret->poststop));
            if (ret->poststop == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->poststop[i] = make_runtime_spec_schema_defs_hook (val, ctx, err);
                if (ret->poststop[i] == NULL)
                  return NULL;
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
            if (strcmp (tree->u.object.keys[i], "prestart")
                && strcmp (tree->u.object.keys[i], "createRuntime")
                && strcmp (tree->u.object.keys[i], "createContainer")
                && strcmp (tree->u.object.keys[i], "startContainer")
                && strcmp (tree->u.object.keys[i], "poststart")
                && strcmp (tree->u.object.keys[i], "poststop")){
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
free_runtime_spec_schema_config_schema_hooks (runtime_spec_schema_config_schema_hooks *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->prestart != NULL)      {
        size_t i;
        for (i = 0; i < ptr->prestart_len; i++)
          {
          if (ptr->prestart[i] != NULL)
            {
              free_runtime_spec_schema_defs_hook (ptr->prestart[i]);
              ptr->prestart[i] = NULL;
            }
          }
        free (ptr->prestart);
        ptr->prestart = NULL;
      }
    if (ptr->create_runtime != NULL)      {
        size_t i;
        for (i = 0; i < ptr->create_runtime_len; i++)
          {
          if (ptr->create_runtime[i] != NULL)
            {
              free_runtime_spec_schema_defs_hook (ptr->create_runtime[i]);
              ptr->create_runtime[i] = NULL;
            }
          }
        free (ptr->create_runtime);
        ptr->create_runtime = NULL;
      }
    if (ptr->create_container != NULL)      {
        size_t i;
        for (i = 0; i < ptr->create_container_len; i++)
          {
          if (ptr->create_container[i] != NULL)
            {
              free_runtime_spec_schema_defs_hook (ptr->create_container[i]);
              ptr->create_container[i] = NULL;
            }
          }
        free (ptr->create_container);
        ptr->create_container = NULL;
      }
    if (ptr->start_container != NULL)      {
        size_t i;
        for (i = 0; i < ptr->start_container_len; i++)
          {
          if (ptr->start_container[i] != NULL)
            {
              free_runtime_spec_schema_defs_hook (ptr->start_container[i]);
              ptr->start_container[i] = NULL;
            }
          }
        free (ptr->start_container);
        ptr->start_container = NULL;
      }
    if (ptr->poststart != NULL)      {
        size_t i;
        for (i = 0; i < ptr->poststart_len; i++)
          {
          if (ptr->poststart[i] != NULL)
            {
              free_runtime_spec_schema_defs_hook (ptr->poststart[i]);
              ptr->poststart[i] = NULL;
            }
          }
        free (ptr->poststart);
        ptr->poststart = NULL;
      }
    if (ptr->poststop != NULL)      {
        size_t i;
        for (i = 0; i < ptr->poststop_len; i++)
          {
          if (ptr->poststop[i] != NULL)
            {
              free_runtime_spec_schema_defs_hook (ptr->poststop[i]);
              ptr->poststop[i] = NULL;
            }
          }
        free (ptr->poststop);
        ptr->poststop = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_hooks (yajl_gen g, const runtime_spec_schema_config_schema_hooks *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->prestart != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("prestart"), 8 /* strlen ("prestart") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->prestart != NULL)
            len = ptr->prestart_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_hook (g, ptr->prestart[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->create_runtime != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("createRuntime"), 13 /* strlen ("createRuntime") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->create_runtime != NULL)
            len = ptr->create_runtime_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_hook (g, ptr->create_runtime[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->create_container != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("createContainer"), 15 /* strlen ("createContainer") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->create_container != NULL)
            len = ptr->create_container_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_hook (g, ptr->create_container[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->start_container != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("startContainer"), 14 /* strlen ("startContainer") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->start_container != NULL)
            len = ptr->start_container_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_hook (g, ptr->start_container[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->poststart != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("poststart"), 9 /* strlen ("poststart") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->poststart != NULL)
            len = ptr->poststart_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_hook (g, ptr->poststart[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->poststop != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("poststop"), 8 /* strlen ("poststop") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->poststop != NULL)
            len = ptr->poststop_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_hook (g, ptr->poststop[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
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

runtime_spec_schema_config_schema_hooks *
clone_runtime_spec_schema_config_schema_hooks (runtime_spec_schema_config_schema_hooks *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_hooks) runtime_spec_schema_config_schema_hooks *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->prestart)
      {
        ret->prestart_len = src->prestart_len;
        ret->prestart = calloc (src->prestart_len + 1, sizeof (*ret->prestart));
        if (ret->prestart == NULL)
          return NULL;
        for (size_t i = 0; i < src->prestart_len; i++)
          {
            ret->prestart[i] = clone_runtime_spec_schema_defs_hook (src->prestart[i]);
            if (ret->prestart[i] == NULL)
                return NULL;
          }
      }
    if (src->create_runtime)
      {
        ret->create_runtime_len = src->create_runtime_len;
        ret->create_runtime = calloc (src->create_runtime_len + 1, sizeof (*ret->create_runtime));
        if (ret->create_runtime == NULL)
          return NULL;
        for (size_t i = 0; i < src->create_runtime_len; i++)
          {
            ret->create_runtime[i] = clone_runtime_spec_schema_defs_hook (src->create_runtime[i]);
            if (ret->create_runtime[i] == NULL)
                return NULL;
          }
      }
    if (src->create_container)
      {
        ret->create_container_len = src->create_container_len;
        ret->create_container = calloc (src->create_container_len + 1, sizeof (*ret->create_container));
        if (ret->create_container == NULL)
          return NULL;
        for (size_t i = 0; i < src->create_container_len; i++)
          {
            ret->create_container[i] = clone_runtime_spec_schema_defs_hook (src->create_container[i]);
            if (ret->create_container[i] == NULL)
                return NULL;
          }
      }
    if (src->start_container)
      {
        ret->start_container_len = src->start_container_len;
        ret->start_container = calloc (src->start_container_len + 1, sizeof (*ret->start_container));
        if (ret->start_container == NULL)
          return NULL;
        for (size_t i = 0; i < src->start_container_len; i++)
          {
            ret->start_container[i] = clone_runtime_spec_schema_defs_hook (src->start_container[i]);
            if (ret->start_container[i] == NULL)
                return NULL;
          }
      }
    if (src->poststart)
      {
        ret->poststart_len = src->poststart_len;
        ret->poststart = calloc (src->poststart_len + 1, sizeof (*ret->poststart));
        if (ret->poststart == NULL)
          return NULL;
        for (size_t i = 0; i < src->poststart_len; i++)
          {
            ret->poststart[i] = clone_runtime_spec_schema_defs_hook (src->poststart[i]);
            if (ret->poststart[i] == NULL)
                return NULL;
          }
      }
    if (src->poststop)
      {
        ret->poststop_len = src->poststop_len;
        ret->poststop = calloc (src->poststop_len + 1, sizeof (*ret->poststop));
        if (ret->poststop == NULL)
          return NULL;
        for (size_t i = 0; i < src->poststop_len; i++)
          {
            ret->poststop[i] = clone_runtime_spec_schema_defs_hook (src->poststop[i]);
            if (ret->poststop[i] == NULL)
                return NULL;
          }
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_root *, free_runtime_spec_schema_config_schema_root)
runtime_spec_schema_config_schema_root *
make_runtime_spec_schema_config_schema_root (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_root) runtime_spec_schema_config_schema_root *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "path", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->path = strdup (str ? str : "");
            if (ret->path == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "readonly", yajl_t_true);
        if (val != NULL)
          {
            ret->readonly = YAJL_IS_TRUE(val);
            ret->readonly_present = 1;
          }
        else
          {
            val = get_val (tree, "readonly", yajl_t_false);
            if (val != NULL)
              {
                ret->readonly = 0;
                ret->readonly_present = 1;
              }
          }
      }
    while (0);
    if (ret->path == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "path") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }

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
            if (strcmp (tree->u.object.keys[i], "path")
                && strcmp (tree->u.object.keys[i], "readonly")){
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
free_runtime_spec_schema_config_schema_root (runtime_spec_schema_config_schema_root *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->path);
    ptr->path = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_root (yajl_gen g, const runtime_spec_schema_config_schema_root *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->path != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("path"), 4 /* strlen ("path") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->path != NULL)
            str = ptr->path;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->readonly_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("readonly"), 8 /* strlen ("readonly") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->readonly)
            b = ptr->readonly;
        
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

runtime_spec_schema_config_schema_root *
clone_runtime_spec_schema_config_schema_root (runtime_spec_schema_config_schema_root *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_root) runtime_spec_schema_config_schema_root *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->path)
      {
        ret->path = strdup (src->path);
        if (ret->path == NULL)
          return NULL;
      }
    ret->readonly = src->readonly;
    ret->readonly_present = src->readonly_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_process_console_size *, free_runtime_spec_schema_config_schema_process_console_size)
runtime_spec_schema_config_schema_process_console_size *
make_runtime_spec_schema_config_schema_process_console_size (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_console_size) runtime_spec_schema_config_schema_process_console_size *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "height", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->height);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'height': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->height_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "width", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->width);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'width': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->width_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "height")
                && strcmp (tree->u.object.keys[i], "width")){
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
free_runtime_spec_schema_config_schema_process_console_size (runtime_spec_schema_config_schema_process_console_size *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_process_console_size (yajl_gen g, const runtime_spec_schema_config_schema_process_console_size *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->height_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("height"), 6 /* strlen ("height") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->height)
            num = (long long unsigned int)ptr->height;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->width_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("width"), 5 /* strlen ("width") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->width)
            num = (long long unsigned int)ptr->width;
        stat = map_uint (g, num);
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

runtime_spec_schema_config_schema_process_console_size *
clone_runtime_spec_schema_config_schema_process_console_size (runtime_spec_schema_config_schema_process_console_size *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_console_size) runtime_spec_schema_config_schema_process_console_size *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->height = src->height;
    ret->height_present = src->height_present;
    ret->width = src->width;
    ret->width_present = src->width_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_process_user *, free_runtime_spec_schema_config_schema_process_user)
runtime_spec_schema_config_schema_process_user *
make_runtime_spec_schema_config_schema_process_user (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_user) runtime_spec_schema_config_schema_process_user *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "uid", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint (YAJL_GET_NUMBER (val), (unsigned int *)&ret->uid);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'UID' for key 'uid': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->uid_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "gid", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint (YAJL_GET_NUMBER (val), (unsigned int *)&ret->gid);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'GID' for key 'gid': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->gid_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "umask", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->umask);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'umask': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->umask_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "additionalGids", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->additional_gids_len = len;
            ret->additional_gids = calloc (len + 1, sizeof (*ret->additional_gids));
            if (ret->additional_gids == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    int invalid;
                    if (! YAJL_IS_NUMBER (val))
                      {
                        *err = strdup ("invalid type");
                        return NULL;
                      }
                    invalid = common_safe_uint (YAJL_GET_NUMBER (val), (unsigned int *)&ret->additional_gids[i]);
                    if (invalid)
                      {
                        if (asprintf (err, "Invalid value '%s' with type 'GID' for key 'additionalGids': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                            *err = strdup ("error allocating memory");
                        return NULL;
                    }
                }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "username", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->username = strdup (str ? str : "");
            if (ret->username == NULL)
              return NULL;
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
            if (strcmp (tree->u.object.keys[i], "uid")
                && strcmp (tree->u.object.keys[i], "gid")
                && strcmp (tree->u.object.keys[i], "umask")
                && strcmp (tree->u.object.keys[i], "additionalGids")
                && strcmp (tree->u.object.keys[i], "username")){
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
free_runtime_spec_schema_config_schema_process_user (runtime_spec_schema_config_schema_process_user *ptr)
{
    if (ptr == NULL)
        return;
   {
        free (ptr->additional_gids);
        ptr->additional_gids = NULL;
    }
    free (ptr->username);
    ptr->username = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_process_user (yajl_gen g, const runtime_spec_schema_config_schema_process_user *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->uid_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("uid"), 3 /* strlen ("uid") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->uid)
            num = (long long unsigned int)ptr->uid;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->gid_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("gid"), 3 /* strlen ("gid") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->gid)
            num = (long long unsigned int)ptr->gid;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->umask_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("umask"), 5 /* strlen ("umask") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->umask)
            num = (long long unsigned int)ptr->umask;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->additional_gids != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("additionalGids"), 14 /* strlen ("additionalGids") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->additional_gids != NULL)
          len = ptr->additional_gids_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = map_uint (g, ptr->additional_gids[i]);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->username != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("username"), 8 /* strlen ("username") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->username != NULL)
            str = ptr->username;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
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

runtime_spec_schema_config_schema_process_user *
clone_runtime_spec_schema_config_schema_process_user (runtime_spec_schema_config_schema_process_user *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_user) runtime_spec_schema_config_schema_process_user *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->uid = src->uid;
    ret->uid_present = src->uid_present;
    ret->gid = src->gid;
    ret->gid_present = src->gid_present;
    ret->umask = src->umask;
    ret->umask_present = src->umask_present;
    if (src->additional_gids)
      {
        ret->additional_gids_len = src->additional_gids_len;
        ret->additional_gids = calloc (src->additional_gids_len + 1, sizeof (*ret->additional_gids));
        if (ret->additional_gids == NULL)
          return NULL;
        for (size_t i = 0; i < src->additional_gids_len; i++)
          {
            ret->additional_gids[i] = src->additional_gids[i];
          }
      }
    if (src->username)
      {
        ret->username = strdup (src->username);
        if (ret->username == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_process_capabilities *, free_runtime_spec_schema_config_schema_process_capabilities)
runtime_spec_schema_config_schema_process_capabilities *
make_runtime_spec_schema_config_schema_process_capabilities (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_capabilities) runtime_spec_schema_config_schema_process_capabilities *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "bounding", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->bounding_len = len;
            ret->bounding = calloc (len + 1, sizeof (*ret->bounding));
            if (ret->bounding == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->bounding[i] = strdup (str ? str : "");
                    if (ret->bounding[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "permitted", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->permitted_len = len;
            ret->permitted = calloc (len + 1, sizeof (*ret->permitted));
            if (ret->permitted == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->permitted[i] = strdup (str ? str : "");
                    if (ret->permitted[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "effective", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->effective_len = len;
            ret->effective = calloc (len + 1, sizeof (*ret->effective));
            if (ret->effective == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->effective[i] = strdup (str ? str : "");
                    if (ret->effective[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "inheritable", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->inheritable_len = len;
            ret->inheritable = calloc (len + 1, sizeof (*ret->inheritable));
            if (ret->inheritable == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->inheritable[i] = strdup (str ? str : "");
                    if (ret->inheritable[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "ambient", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->ambient_len = len;
            ret->ambient = calloc (len + 1, sizeof (*ret->ambient));
            if (ret->ambient == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->ambient[i] = strdup (str ? str : "");
                    if (ret->ambient[i] == NULL)
                      return NULL;
                  }
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
            if (strcmp (tree->u.object.keys[i], "bounding")
                && strcmp (tree->u.object.keys[i], "permitted")
                && strcmp (tree->u.object.keys[i], "effective")
                && strcmp (tree->u.object.keys[i], "inheritable")
                && strcmp (tree->u.object.keys[i], "ambient")){
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
free_runtime_spec_schema_config_schema_process_capabilities (runtime_spec_schema_config_schema_process_capabilities *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->bounding != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->bounding_len; i++)
          {
            if (ptr->bounding[i] != NULL)
              {
                free (ptr->bounding[i]);
                ptr->bounding[i] = NULL;
              }
          }
        free (ptr->bounding);
        ptr->bounding = NULL;
    }
    if (ptr->permitted != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->permitted_len; i++)
          {
            if (ptr->permitted[i] != NULL)
              {
                free (ptr->permitted[i]);
                ptr->permitted[i] = NULL;
              }
          }
        free (ptr->permitted);
        ptr->permitted = NULL;
    }
    if (ptr->effective != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->effective_len; i++)
          {
            if (ptr->effective[i] != NULL)
              {
                free (ptr->effective[i]);
                ptr->effective[i] = NULL;
              }
          }
        free (ptr->effective);
        ptr->effective = NULL;
    }
    if (ptr->inheritable != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->inheritable_len; i++)
          {
            if (ptr->inheritable[i] != NULL)
              {
                free (ptr->inheritable[i]);
                ptr->inheritable[i] = NULL;
              }
          }
        free (ptr->inheritable);
        ptr->inheritable = NULL;
    }
    if (ptr->ambient != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->ambient_len; i++)
          {
            if (ptr->ambient[i] != NULL)
              {
                free (ptr->ambient[i]);
                ptr->ambient[i] = NULL;
              }
          }
        free (ptr->ambient);
        ptr->ambient = NULL;
    }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_process_capabilities (yajl_gen g, const runtime_spec_schema_config_schema_process_capabilities *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->bounding != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("bounding"), 8 /* strlen ("bounding") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->bounding != NULL)
          len = ptr->bounding_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->bounding[i]), strlen (ptr->bounding[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->permitted != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("permitted"), 9 /* strlen ("permitted") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->permitted != NULL)
          len = ptr->permitted_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->permitted[i]), strlen (ptr->permitted[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->effective != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("effective"), 9 /* strlen ("effective") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->effective != NULL)
          len = ptr->effective_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->effective[i]), strlen (ptr->effective[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->inheritable != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("inheritable"), 11 /* strlen ("inheritable") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->inheritable != NULL)
          len = ptr->inheritable_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->inheritable[i]), strlen (ptr->inheritable[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->ambient != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ambient"), 7 /* strlen ("ambient") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->ambient != NULL)
          len = ptr->ambient_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->ambient[i]), strlen (ptr->ambient[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
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

runtime_spec_schema_config_schema_process_capabilities *
clone_runtime_spec_schema_config_schema_process_capabilities (runtime_spec_schema_config_schema_process_capabilities *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_capabilities) runtime_spec_schema_config_schema_process_capabilities *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->bounding)
      {
        ret->bounding_len = src->bounding_len;
        ret->bounding = calloc (src->bounding_len + 1, sizeof (*ret->bounding));
        if (ret->bounding == NULL)
          return NULL;
        for (size_t i = 0; i < src->bounding_len; i++)
          {
            if (src->bounding[i])
              {
                ret->bounding[i] = strdup (src->bounding[i]);
                if (ret->bounding[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->permitted)
      {
        ret->permitted_len = src->permitted_len;
        ret->permitted = calloc (src->permitted_len + 1, sizeof (*ret->permitted));
        if (ret->permitted == NULL)
          return NULL;
        for (size_t i = 0; i < src->permitted_len; i++)
          {
            if (src->permitted[i])
              {
                ret->permitted[i] = strdup (src->permitted[i]);
                if (ret->permitted[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->effective)
      {
        ret->effective_len = src->effective_len;
        ret->effective = calloc (src->effective_len + 1, sizeof (*ret->effective));
        if (ret->effective == NULL)
          return NULL;
        for (size_t i = 0; i < src->effective_len; i++)
          {
            if (src->effective[i])
              {
                ret->effective[i] = strdup (src->effective[i]);
                if (ret->effective[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->inheritable)
      {
        ret->inheritable_len = src->inheritable_len;
        ret->inheritable = calloc (src->inheritable_len + 1, sizeof (*ret->inheritable));
        if (ret->inheritable == NULL)
          return NULL;
        for (size_t i = 0; i < src->inheritable_len; i++)
          {
            if (src->inheritable[i])
              {
                ret->inheritable[i] = strdup (src->inheritable[i]);
                if (ret->inheritable[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->ambient)
      {
        ret->ambient_len = src->ambient_len;
        ret->ambient = calloc (src->ambient_len + 1, sizeof (*ret->ambient));
        if (ret->ambient == NULL)
          return NULL;
        for (size_t i = 0; i < src->ambient_len; i++)
          {
            if (src->ambient[i])
              {
                ret->ambient[i] = strdup (src->ambient[i]);
                if (ret->ambient[i] == NULL)
                  return NULL;
              }
          }
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_process_io_priority *, free_runtime_spec_schema_config_schema_process_io_priority)
runtime_spec_schema_config_schema_process_io_priority *
make_runtime_spec_schema_config_schema_process_io_priority (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_io_priority) runtime_spec_schema_config_schema_process_io_priority *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "class", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->_class = strdup (str ? str : "");
            if (ret->_class == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "priority", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int32 (YAJL_GET_NUMBER (val), &ret->priority);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int32' for key 'priority': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->priority_present = 1;
        }
      }
    while (0);
    if (ret->_class == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "class") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }

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
            if (strcmp (tree->u.object.keys[i], "class")
                && strcmp (tree->u.object.keys[i], "priority")){
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
free_runtime_spec_schema_config_schema_process_io_priority (runtime_spec_schema_config_schema_process_io_priority *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->_class);
    ptr->_class = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_process_io_priority (yajl_gen g, const runtime_spec_schema_config_schema_process_io_priority *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->_class != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("class"), 5 /* strlen ("class") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->_class != NULL)
            str = ptr->_class;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->priority_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("priority"), 8 /* strlen ("priority") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->priority)
            num = (long long int)ptr->priority;
        stat = map_int (g, num);
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

runtime_spec_schema_config_schema_process_io_priority *
clone_runtime_spec_schema_config_schema_process_io_priority (runtime_spec_schema_config_schema_process_io_priority *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_io_priority) runtime_spec_schema_config_schema_process_io_priority *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->_class)
      {
        ret->_class = strdup (src->_class);
        if (ret->_class == NULL)
          return NULL;
      }
    ret->priority = src->priority;
    ret->priority_present = src->priority_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_process_scheduler *, free_runtime_spec_schema_config_schema_process_scheduler)
runtime_spec_schema_config_schema_process_scheduler *
make_runtime_spec_schema_config_schema_process_scheduler (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_scheduler) runtime_spec_schema_config_schema_process_scheduler *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "policy", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->policy = strdup (str ? str : "");
            if (ret->policy == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "nice", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int32 (YAJL_GET_NUMBER (val), &ret->nice);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int32' for key 'nice': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->nice_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "priority", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int32 (YAJL_GET_NUMBER (val), &ret->priority);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int32' for key 'priority': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->priority_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "flags", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->flags_len = len;
            ret->flags = calloc (len + 1, sizeof (*ret->flags));
            if (ret->flags == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->flags[i] = strdup (str ? str : "");
                    if (ret->flags[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "runtime", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->runtime);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'runtime': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->runtime_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "deadline", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->deadline);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'deadline': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->deadline_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "period", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->period);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'period': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->period_present = 1;
        }
      }
    while (0);
    if (ret->policy == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "policy") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }

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
            if (strcmp (tree->u.object.keys[i], "policy")
                && strcmp (tree->u.object.keys[i], "nice")
                && strcmp (tree->u.object.keys[i], "priority")
                && strcmp (tree->u.object.keys[i], "flags")
                && strcmp (tree->u.object.keys[i], "runtime")
                && strcmp (tree->u.object.keys[i], "deadline")
                && strcmp (tree->u.object.keys[i], "period")){
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
free_runtime_spec_schema_config_schema_process_scheduler (runtime_spec_schema_config_schema_process_scheduler *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->policy);
    ptr->policy = NULL;
    if (ptr->flags != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->flags_len; i++)
          {
            if (ptr->flags[i] != NULL)
              {
                free (ptr->flags[i]);
                ptr->flags[i] = NULL;
              }
          }
        free (ptr->flags);
        ptr->flags = NULL;
    }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_process_scheduler (yajl_gen g, const runtime_spec_schema_config_schema_process_scheduler *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->policy != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("policy"), 6 /* strlen ("policy") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->policy != NULL)
            str = ptr->policy;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->nice_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("nice"), 4 /* strlen ("nice") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->nice)
            num = (long long int)ptr->nice;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->priority_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("priority"), 8 /* strlen ("priority") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->priority)
            num = (long long int)ptr->priority;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->flags != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("flags"), 5 /* strlen ("flags") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->flags != NULL)
          len = ptr->flags_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->flags[i]), strlen (ptr->flags[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->runtime_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("runtime"), 7 /* strlen ("runtime") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->runtime)
            num = (long long unsigned int)ptr->runtime;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->deadline_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("deadline"), 8 /* strlen ("deadline") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->deadline)
            num = (long long unsigned int)ptr->deadline;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->period_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("period"), 6 /* strlen ("period") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->period)
            num = (long long unsigned int)ptr->period;
        stat = map_uint (g, num);
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

runtime_spec_schema_config_schema_process_scheduler *
clone_runtime_spec_schema_config_schema_process_scheduler (runtime_spec_schema_config_schema_process_scheduler *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_scheduler) runtime_spec_schema_config_schema_process_scheduler *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->policy)
      {
        ret->policy = strdup (src->policy);
        if (ret->policy == NULL)
          return NULL;
      }
    ret->nice = src->nice;
    ret->nice_present = src->nice_present;
    ret->priority = src->priority;
    ret->priority_present = src->priority_present;
    if (src->flags)
      {
        ret->flags_len = src->flags_len;
        ret->flags = calloc (src->flags_len + 1, sizeof (*ret->flags));
        if (ret->flags == NULL)
          return NULL;
        for (size_t i = 0; i < src->flags_len; i++)
          {
            if (src->flags[i])
              {
                ret->flags[i] = strdup (src->flags[i]);
                if (ret->flags[i] == NULL)
                  return NULL;
              }
          }
      }
    ret->runtime = src->runtime;
    ret->runtime_present = src->runtime_present;
    ret->deadline = src->deadline;
    ret->deadline_present = src->deadline_present;
    ret->period = src->period;
    ret->period_present = src->period_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_process_rlimits_element *, free_runtime_spec_schema_config_schema_process_rlimits_element)
runtime_spec_schema_config_schema_process_rlimits_element *
make_runtime_spec_schema_config_schema_process_rlimits_element (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_rlimits_element) runtime_spec_schema_config_schema_process_rlimits_element *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "hard", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->hard);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'hard': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->hard_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "soft", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->soft);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'soft': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->soft_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "type", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->type = strdup (str ? str : "");
            if (ret->type == NULL)
              return NULL;
          }
      }
    while (0);
    if (ret->type == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "type") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    return move_ptr (ret);
}

void
free_runtime_spec_schema_config_schema_process_rlimits_element (runtime_spec_schema_config_schema_process_rlimits_element *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->type);
    ptr->type = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_process_rlimits_element (yajl_gen g, const runtime_spec_schema_config_schema_process_rlimits_element *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->hard_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hard"), 4 /* strlen ("hard") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->hard)
            num = (long long unsigned int)ptr->hard;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->soft_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("soft"), 4 /* strlen ("soft") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->soft)
            num = (long long unsigned int)ptr->soft;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->type != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("type"), 4 /* strlen ("type") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->type != NULL)
            str = ptr->type;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

runtime_spec_schema_config_schema_process_rlimits_element *
clone_runtime_spec_schema_config_schema_process_rlimits_element (runtime_spec_schema_config_schema_process_rlimits_element *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_rlimits_element) runtime_spec_schema_config_schema_process_rlimits_element *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->hard = src->hard;
    ret->hard_present = src->hard_present;
    ret->soft = src->soft;
    ret->soft_present = src->soft_present;
    if (src->type)
      {
        ret->type = strdup (src->type);
        if (ret->type == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_process_exec_cpu_affinity *, free_runtime_spec_schema_config_schema_process_exec_cpu_affinity)
runtime_spec_schema_config_schema_process_exec_cpu_affinity *
make_runtime_spec_schema_config_schema_process_exec_cpu_affinity (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_exec_cpu_affinity) runtime_spec_schema_config_schema_process_exec_cpu_affinity *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "initial", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->initial = strdup (str ? str : "");
            if (ret->initial == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "final", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->final = strdup (str ? str : "");
            if (ret->final == NULL)
              return NULL;
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
            if (strcmp (tree->u.object.keys[i], "initial")
                && strcmp (tree->u.object.keys[i], "final")){
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
free_runtime_spec_schema_config_schema_process_exec_cpu_affinity (runtime_spec_schema_config_schema_process_exec_cpu_affinity *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->initial);
    ptr->initial = NULL;
    free (ptr->final);
    ptr->final = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_process_exec_cpu_affinity (yajl_gen g, const runtime_spec_schema_config_schema_process_exec_cpu_affinity *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->initial != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("initial"), 7 /* strlen ("initial") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->initial != NULL)
            str = ptr->initial;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->final != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("final"), 5 /* strlen ("final") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->final != NULL)
            str = ptr->final;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
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

runtime_spec_schema_config_schema_process_exec_cpu_affinity *
clone_runtime_spec_schema_config_schema_process_exec_cpu_affinity (runtime_spec_schema_config_schema_process_exec_cpu_affinity *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_process_exec_cpu_affinity) runtime_spec_schema_config_schema_process_exec_cpu_affinity *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->initial)
      {
        ret->initial = strdup (src->initial);
        if (ret->initial == NULL)
          return NULL;
      }
    if (src->final)
      {
        ret->final = strdup (src->final);
        if (ret->final == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema_process *, free_runtime_spec_schema_config_schema_process)
runtime_spec_schema_config_schema_process *
make_runtime_spec_schema_config_schema_process (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema_process) runtime_spec_schema_config_schema_process *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "args", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->args_len = len;
            ret->args = calloc (len + 1, sizeof (*ret->args));
            if (ret->args == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->args[i] = strdup (str ? str : "");
                    if (ret->args[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "commandLine", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->command_line = strdup (str ? str : "");
            if (ret->command_line == NULL)
              return NULL;
          }
      }
    while (0);
    ret->console_size = make_runtime_spec_schema_config_schema_process_console_size (get_val (tree, "consoleSize", yajl_t_object), ctx, err);
    if (ret->console_size == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "cwd", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->cwd = strdup (str ? str : "");
            if (ret->cwd == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "env", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->env_len = len;
            ret->env = calloc (len + 1, sizeof (*ret->env));
            if (ret->env == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->env[i] = strdup (str ? str : "");
                    if (ret->env[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "terminal", yajl_t_true);
        if (val != NULL)
          {
            ret->terminal = YAJL_IS_TRUE(val);
            ret->terminal_present = 1;
          }
        else
          {
            val = get_val (tree, "terminal", yajl_t_false);
            if (val != NULL)
              {
                ret->terminal = 0;
                ret->terminal_present = 1;
              }
          }
      }
    while (0);
    ret->user = make_runtime_spec_schema_config_schema_process_user (get_val (tree, "user", yajl_t_object), ctx, err);
    if (ret->user == NULL && *err != 0)
      return NULL;
    ret->capabilities = make_runtime_spec_schema_config_schema_process_capabilities (get_val (tree, "capabilities", yajl_t_object), ctx, err);
    if (ret->capabilities == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "apparmorProfile", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->apparmor_profile = strdup (str ? str : "");
            if (ret->apparmor_profile == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "oomScoreAdj", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int (YAJL_GET_NUMBER (val), (int *)&ret->oom_score_adj);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'integer' for key 'oomScoreAdj': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->oom_score_adj_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "selinuxLabel", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->selinux_label = strdup (str ? str : "");
            if (ret->selinux_label == NULL)
              return NULL;
          }
      }
    while (0);
    ret->io_priority = make_runtime_spec_schema_config_schema_process_io_priority (get_val (tree, "ioPriority", yajl_t_object), ctx, err);
    if (ret->io_priority == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "noNewPrivileges", yajl_t_true);
        if (val != NULL)
          {
            ret->no_new_privileges = YAJL_IS_TRUE(val);
            ret->no_new_privileges_present = 1;
          }
        else
          {
            val = get_val (tree, "noNewPrivileges", yajl_t_false);
            if (val != NULL)
              {
                ret->no_new_privileges = 0;
                ret->no_new_privileges_present = 1;
              }
          }
      }
    while (0);
    ret->scheduler = make_runtime_spec_schema_config_schema_process_scheduler (get_val (tree, "scheduler", yajl_t_object), ctx, err);
    if (ret->scheduler == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "rlimits", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->rlimits_len = len;
            ret->rlimits = calloc (len + 1, sizeof (*ret->rlimits));
            if (ret->rlimits == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->rlimits[i] = make_runtime_spec_schema_config_schema_process_rlimits_element (val, ctx, err);
                if (ret->rlimits[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    ret->exec_cpu_affinity = make_runtime_spec_schema_config_schema_process_exec_cpu_affinity (get_val (tree, "execCPUAffinity", yajl_t_object), ctx, err);
    if (ret->exec_cpu_affinity == NULL && *err != 0)
      return NULL;
    if (ret->cwd == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "cwd") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }

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
            if (strcmp (tree->u.object.keys[i], "args")
                && strcmp (tree->u.object.keys[i], "commandLine")
                && strcmp (tree->u.object.keys[i], "consoleSize")
                && strcmp (tree->u.object.keys[i], "cwd")
                && strcmp (tree->u.object.keys[i], "env")
                && strcmp (tree->u.object.keys[i], "terminal")
                && strcmp (tree->u.object.keys[i], "user")
                && strcmp (tree->u.object.keys[i], "capabilities")
                && strcmp (tree->u.object.keys[i], "apparmorProfile")
                && strcmp (tree->u.object.keys[i], "oomScoreAdj")
                && strcmp (tree->u.object.keys[i], "selinuxLabel")
                && strcmp (tree->u.object.keys[i], "ioPriority")
                && strcmp (tree->u.object.keys[i], "noNewPrivileges")
                && strcmp (tree->u.object.keys[i], "scheduler")
                && strcmp (tree->u.object.keys[i], "rlimits")
                && strcmp (tree->u.object.keys[i], "execCPUAffinity")){
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
free_runtime_spec_schema_config_schema_process (runtime_spec_schema_config_schema_process *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->args != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->args_len; i++)
          {
            if (ptr->args[i] != NULL)
              {
                free (ptr->args[i]);
                ptr->args[i] = NULL;
              }
          }
        free (ptr->args);
        ptr->args = NULL;
    }
    free (ptr->command_line);
    ptr->command_line = NULL;
    if (ptr->console_size != NULL)
      {
        free_runtime_spec_schema_config_schema_process_console_size (ptr->console_size);
        ptr->console_size = NULL;
      }
    free (ptr->cwd);
    ptr->cwd = NULL;
    if (ptr->env != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->env_len; i++)
          {
            if (ptr->env[i] != NULL)
              {
                free (ptr->env[i]);
                ptr->env[i] = NULL;
              }
          }
        free (ptr->env);
        ptr->env = NULL;
    }
    if (ptr->user != NULL)
      {
        free_runtime_spec_schema_config_schema_process_user (ptr->user);
        ptr->user = NULL;
      }
    if (ptr->capabilities != NULL)
      {
        free_runtime_spec_schema_config_schema_process_capabilities (ptr->capabilities);
        ptr->capabilities = NULL;
      }
    free (ptr->apparmor_profile);
    ptr->apparmor_profile = NULL;
    free (ptr->selinux_label);
    ptr->selinux_label = NULL;
    if (ptr->io_priority != NULL)
      {
        free_runtime_spec_schema_config_schema_process_io_priority (ptr->io_priority);
        ptr->io_priority = NULL;
      }
    if (ptr->scheduler != NULL)
      {
        free_runtime_spec_schema_config_schema_process_scheduler (ptr->scheduler);
        ptr->scheduler = NULL;
      }
    if (ptr->rlimits != NULL)      {
        size_t i;
        for (i = 0; i < ptr->rlimits_len; i++)
          {
          if (ptr->rlimits[i] != NULL)
            {
              free_runtime_spec_schema_config_schema_process_rlimits_element (ptr->rlimits[i]);
              ptr->rlimits[i] = NULL;
            }
          }
        free (ptr->rlimits);
        ptr->rlimits = NULL;
      }
    if (ptr->exec_cpu_affinity != NULL)
      {
        free_runtime_spec_schema_config_schema_process_exec_cpu_affinity (ptr->exec_cpu_affinity);
        ptr->exec_cpu_affinity = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema_process (yajl_gen g, const runtime_spec_schema_config_schema_process *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->args != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("args"), 4 /* strlen ("args") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->args != NULL)
          len = ptr->args_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->args[i]), strlen (ptr->args[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->command_line != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("commandLine"), 11 /* strlen ("commandLine") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->command_line != NULL)
            str = ptr->command_line;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->console_size != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("consoleSize"), 11 /* strlen ("consoleSize") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_process_console_size (g, ptr != NULL ? ptr->console_size : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->cwd != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("cwd"), 3 /* strlen ("cwd") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->cwd != NULL)
            str = ptr->cwd;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->env != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("env"), 3 /* strlen ("env") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->env != NULL)
          len = ptr->env_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->env[i]), strlen (ptr->env[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->terminal_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("terminal"), 8 /* strlen ("terminal") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->terminal)
            b = ptr->terminal;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->user != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("user"), 4 /* strlen ("user") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_process_user (g, ptr != NULL ? ptr->user : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->capabilities != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("capabilities"), 12 /* strlen ("capabilities") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_process_capabilities (g, ptr != NULL ? ptr->capabilities : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->apparmor_profile != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("apparmorProfile"), 15 /* strlen ("apparmorProfile") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->apparmor_profile != NULL)
            str = ptr->apparmor_profile;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->oom_score_adj_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("oomScoreAdj"), 11 /* strlen ("oomScoreAdj") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->oom_score_adj)
            num = (long long int)ptr->oom_score_adj;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->selinux_label != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("selinuxLabel"), 12 /* strlen ("selinuxLabel") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->selinux_label != NULL)
            str = ptr->selinux_label;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->io_priority != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ioPriority"), 10 /* strlen ("ioPriority") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_process_io_priority (g, ptr != NULL ? ptr->io_priority : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->no_new_privileges_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("noNewPrivileges"), 15 /* strlen ("noNewPrivileges") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->no_new_privileges)
            b = ptr->no_new_privileges;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->scheduler != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("scheduler"), 9 /* strlen ("scheduler") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_process_scheduler (g, ptr != NULL ? ptr->scheduler : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->rlimits != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("rlimits"), 7 /* strlen ("rlimits") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->rlimits != NULL)
            len = ptr->rlimits_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_config_schema_process_rlimits_element (g, ptr->rlimits[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->exec_cpu_affinity != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("execCPUAffinity"), 15 /* strlen ("execCPUAffinity") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_process_exec_cpu_affinity (g, ptr != NULL ? ptr->exec_cpu_affinity : NULL, ctx, err);
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

runtime_spec_schema_config_schema_process *
clone_runtime_spec_schema_config_schema_process (runtime_spec_schema_config_schema_process *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema_process) runtime_spec_schema_config_schema_process *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->args)
      {
        ret->args_len = src->args_len;
        ret->args = calloc (src->args_len + 1, sizeof (*ret->args));
        if (ret->args == NULL)
          return NULL;
        for (size_t i = 0; i < src->args_len; i++)
          {
            if (src->args[i])
              {
                ret->args[i] = strdup (src->args[i]);
                if (ret->args[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->command_line)
      {
        ret->command_line = strdup (src->command_line);
        if (ret->command_line == NULL)
          return NULL;
      }
    if (src->console_size)
      {
        ret->console_size = clone_runtime_spec_schema_config_schema_process_console_size (src->console_size);
        if (ret->console_size == NULL)
          return NULL;
      }
    if (src->cwd)
      {
        ret->cwd = strdup (src->cwd);
        if (ret->cwd == NULL)
          return NULL;
      }
    if (src->env)
      {
        ret->env_len = src->env_len;
        ret->env = calloc (src->env_len + 1, sizeof (*ret->env));
        if (ret->env == NULL)
          return NULL;
        for (size_t i = 0; i < src->env_len; i++)
          {
            if (src->env[i])
              {
                ret->env[i] = strdup (src->env[i]);
                if (ret->env[i] == NULL)
                  return NULL;
              }
          }
      }
    ret->terminal = src->terminal;
    ret->terminal_present = src->terminal_present;
    if (src->user)
      {
        ret->user = clone_runtime_spec_schema_config_schema_process_user (src->user);
        if (ret->user == NULL)
          return NULL;
      }
    if (src->capabilities)
      {
        ret->capabilities = clone_runtime_spec_schema_config_schema_process_capabilities (src->capabilities);
        if (ret->capabilities == NULL)
          return NULL;
      }
    if (src->apparmor_profile)
      {
        ret->apparmor_profile = strdup (src->apparmor_profile);
        if (ret->apparmor_profile == NULL)
          return NULL;
      }
    ret->oom_score_adj = src->oom_score_adj;
    ret->oom_score_adj_present = src->oom_score_adj_present;
    if (src->selinux_label)
      {
        ret->selinux_label = strdup (src->selinux_label);
        if (ret->selinux_label == NULL)
          return NULL;
      }
    if (src->io_priority)
      {
        ret->io_priority = clone_runtime_spec_schema_config_schema_process_io_priority (src->io_priority);
        if (ret->io_priority == NULL)
          return NULL;
      }
    ret->no_new_privileges = src->no_new_privileges;
    ret->no_new_privileges_present = src->no_new_privileges_present;
    if (src->scheduler)
      {
        ret->scheduler = clone_runtime_spec_schema_config_schema_process_scheduler (src->scheduler);
        if (ret->scheduler == NULL)
          return NULL;
      }
    if (src->rlimits)
      {
        ret->rlimits_len = src->rlimits_len;
        ret->rlimits = calloc (src->rlimits_len + 1, sizeof (*ret->rlimits));
        if (ret->rlimits == NULL)
          return NULL;
        for (size_t i = 0; i < src->rlimits_len; i++)
          {
            ret->rlimits[i] = clone_runtime_spec_schema_config_schema_process_rlimits_element (src->rlimits[i]);
            if (ret->rlimits[i] == NULL)
                return NULL;
          }
      }
    if (src->exec_cpu_affinity)
      {
        ret->exec_cpu_affinity = clone_runtime_spec_schema_config_schema_process_exec_cpu_affinity (src->exec_cpu_affinity);
        if (ret->exec_cpu_affinity == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_schema *, free_runtime_spec_schema_config_schema)
runtime_spec_schema_config_schema *
make_runtime_spec_schema_config_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_schema) runtime_spec_schema_config_schema *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "ociVersion", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->oci_version = strdup (str ? str : "");
            if (ret->oci_version == NULL)
              return NULL;
          }
      }
    while (0);
    ret->hooks = make_runtime_spec_schema_config_schema_hooks (get_val (tree, "hooks", yajl_t_object), ctx, err);
    if (ret->hooks == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "annotations", yajl_t_object);
        if (tmp != NULL)
          {
            ret->annotations = make_json_map_string_string (tmp, ctx, err);
            if (ret->annotations == NULL)
              {
                char *new_error = NULL;
                if (asprintf (&new_error, "Value error for key 'annotations': %s", *err ? *err : "null") < 0)
                  new_error = strdup ("error allocating memory");
                free (*err);
                *err = new_error;
                return NULL;
              }
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "hostname", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->hostname = strdup (str ? str : "");
            if (ret->hostname == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "domainname", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->domainname = strdup (str ? str : "");
            if (ret->domainname == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "mounts", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->mounts_len = len;
            ret->mounts = calloc (len + 1, sizeof (*ret->mounts));
            if (ret->mounts == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->mounts[i] = make_runtime_spec_schema_defs_mount (val, ctx, err);
                if (ret->mounts[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    ret->root = make_runtime_spec_schema_config_schema_root (get_val (tree, "root", yajl_t_object), ctx, err);
    if (ret->root == NULL && *err != 0)
      return NULL;
    ret->process = make_runtime_spec_schema_config_schema_process (get_val (tree, "process", yajl_t_object), ctx, err);
    if (ret->process == NULL && *err != 0)
      return NULL;
    ret->linux = make_runtime_spec_schema_config_linux (get_val (tree, "linux", yajl_t_object), ctx, err);
    if (ret->linux == NULL && *err != 0)
      return NULL;
    ret->solaris = make_runtime_spec_schema_config_solaris (get_val (tree, "solaris", yajl_t_object), ctx, err);
    if (ret->solaris == NULL && *err != 0)
      return NULL;
    ret->windows = make_runtime_spec_schema_config_windows (get_val (tree, "windows", yajl_t_object), ctx, err);
    if (ret->windows == NULL && *err != 0)
      return NULL;
    ret->vm = make_runtime_spec_schema_config_vm (get_val (tree, "vm", yajl_t_object), ctx, err);
    if (ret->vm == NULL && *err != 0)
      return NULL;
    ret->zos = make_runtime_spec_schema_config_zos (get_val (tree, "zos", yajl_t_object), ctx, err);
    if (ret->zos == NULL && *err != 0)
      return NULL;
    if (ret->oci_version == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "ociVersion") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }

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
            if (strcmp (tree->u.object.keys[i], "ociVersion")
                && strcmp (tree->u.object.keys[i], "hooks")
                && strcmp (tree->u.object.keys[i], "annotations")
                && strcmp (tree->u.object.keys[i], "hostname")
                && strcmp (tree->u.object.keys[i], "domainname")
                && strcmp (tree->u.object.keys[i], "mounts")
                && strcmp (tree->u.object.keys[i], "root")
                && strcmp (tree->u.object.keys[i], "process")
                && strcmp (tree->u.object.keys[i], "linux")
                && strcmp (tree->u.object.keys[i], "solaris")
                && strcmp (tree->u.object.keys[i], "windows")
                && strcmp (tree->u.object.keys[i], "vm")
                && strcmp (tree->u.object.keys[i], "zos")){
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
free_runtime_spec_schema_config_schema (runtime_spec_schema_config_schema *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->oci_version);
    ptr->oci_version = NULL;
    if (ptr->hooks != NULL)
      {
        free_runtime_spec_schema_config_schema_hooks (ptr->hooks);
        ptr->hooks = NULL;
      }
    free_json_map_string_string (ptr->annotations);
    ptr->annotations = NULL;
    free (ptr->hostname);
    ptr->hostname = NULL;
    free (ptr->domainname);
    ptr->domainname = NULL;
    if (ptr->mounts != NULL)      {
        size_t i;
        for (i = 0; i < ptr->mounts_len; i++)
          {
          if (ptr->mounts[i] != NULL)
            {
              free_runtime_spec_schema_defs_mount (ptr->mounts[i]);
              ptr->mounts[i] = NULL;
            }
          }
        free (ptr->mounts);
        ptr->mounts = NULL;
      }
    if (ptr->root != NULL)
      {
        free_runtime_spec_schema_config_schema_root (ptr->root);
        ptr->root = NULL;
      }
    if (ptr->process != NULL)
      {
        free_runtime_spec_schema_config_schema_process (ptr->process);
        ptr->process = NULL;
      }
    if (ptr->linux != NULL)
      {
        free_runtime_spec_schema_config_linux (ptr->linux);
        ptr->linux = NULL;
      }
    if (ptr->solaris != NULL)
      {
        free_runtime_spec_schema_config_solaris (ptr->solaris);
        ptr->solaris = NULL;
      }
    if (ptr->windows != NULL)
      {
        free_runtime_spec_schema_config_windows (ptr->windows);
        ptr->windows = NULL;
      }
    if (ptr->vm != NULL)
      {
        free_runtime_spec_schema_config_vm (ptr->vm);
        ptr->vm = NULL;
      }
    if (ptr->zos != NULL)
      {
        free_runtime_spec_schema_config_zos (ptr->zos);
        ptr->zos = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_schema (yajl_gen g, const runtime_spec_schema_config_schema *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->oci_version != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ociVersion"), 10 /* strlen ("ociVersion") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->oci_version != NULL)
            str = ptr->oci_version;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->hooks != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hooks"), 5 /* strlen ("hooks") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_hooks (g, ptr != NULL ? ptr->hooks : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->annotations != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("annotations"), 11 /* strlen ("annotations") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_json_map_string_string (g, ptr ? ptr->annotations : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->hostname != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hostname"), 8 /* strlen ("hostname") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->hostname != NULL)
            str = ptr->hostname;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->domainname != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("domainname"), 10 /* strlen ("domainname") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->domainname != NULL)
            str = ptr->domainname;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->mounts != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("mounts"), 6 /* strlen ("mounts") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->mounts != NULL)
            len = ptr->mounts_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_mount (g, ptr->mounts[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->root != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("root"), 4 /* strlen ("root") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_root (g, ptr != NULL ? ptr->root : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->process != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("process"), 7 /* strlen ("process") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_schema_process (g, ptr != NULL ? ptr->process : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->linux != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("linux"), 5 /* strlen ("linux") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_linux (g, ptr != NULL ? ptr->linux : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->solaris != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("solaris"), 7 /* strlen ("solaris") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_solaris (g, ptr != NULL ? ptr->solaris : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->windows != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("windows"), 7 /* strlen ("windows") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows (g, ptr != NULL ? ptr->windows : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->vm != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("vm"), 2 /* strlen ("vm") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_vm (g, ptr != NULL ? ptr->vm : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->zos != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("zos"), 3 /* strlen ("zos") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_zos (g, ptr != NULL ? ptr->zos : NULL, ctx, err);
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

runtime_spec_schema_config_schema *
clone_runtime_spec_schema_config_schema (runtime_spec_schema_config_schema *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_schema) runtime_spec_schema_config_schema *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->oci_version)
      {
        ret->oci_version = strdup (src->oci_version);
        if (ret->oci_version == NULL)
          return NULL;
      }
    if (src->hooks)
      {
        ret->hooks = clone_runtime_spec_schema_config_schema_hooks (src->hooks);
        if (ret->hooks == NULL)
          return NULL;
      }
    ret->annotations = clone_map_string_string (src->annotations);
    if (ret->annotations == NULL)
        return NULL;
    if (src->hostname)
      {
        ret->hostname = strdup (src->hostname);
        if (ret->hostname == NULL)
          return NULL;
      }
    if (src->domainname)
      {
        ret->domainname = strdup (src->domainname);
        if (ret->domainname == NULL)
          return NULL;
      }
    if (src->mounts)
      {
        ret->mounts_len = src->mounts_len;
        ret->mounts = calloc (src->mounts_len + 1, sizeof (*ret->mounts));
        if (ret->mounts == NULL)
          return NULL;
        for (size_t i = 0; i < src->mounts_len; i++)
          {
            ret->mounts[i] = clone_runtime_spec_schema_defs_mount (src->mounts[i]);
            if (ret->mounts[i] == NULL)
                return NULL;
          }
      }
    if (src->root)
      {
        ret->root = clone_runtime_spec_schema_config_schema_root (src->root);
        if (ret->root == NULL)
          return NULL;
      }
    if (src->process)
      {
        ret->process = clone_runtime_spec_schema_config_schema_process (src->process);
        if (ret->process == NULL)
          return NULL;
      }
    if (src->linux)
      {
        ret->linux = clone_runtime_spec_schema_config_linux (src->linux);
        if (ret->linux == NULL)
          return NULL;
      }
    if (src->solaris)
      {
        ret->solaris = clone_runtime_spec_schema_config_solaris (src->solaris);
        if (ret->solaris == NULL)
          return NULL;
      }
    if (src->windows)
      {
        ret->windows = clone_runtime_spec_schema_config_windows (src->windows);
        if (ret->windows == NULL)
          return NULL;
      }
    if (src->vm)
      {
        ret->vm = clone_runtime_spec_schema_config_vm (src->vm);
        if (ret->vm == NULL)
          return NULL;
      }
    if (src->zos)
      {
        ret->zos = clone_runtime_spec_schema_config_zos (src->zos);
        if (ret->zos == NULL)
          return NULL;
      }
    return move_ptr (ret);
}


runtime_spec_schema_config_schema *
runtime_spec_schema_config_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
runtime_spec_schema_config_schema *ptr = NULL;size_t filesize;
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
      }ptr = runtime_spec_schema_config_schema_parse_data (content, ctx, err);return ptr;
}
runtime_spec_schema_config_schema * 
runtime_spec_schema_config_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{runtime_spec_schema_config_schema *ptr = NULL;
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
ptr = runtime_spec_schema_config_schema_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 runtime_spec_schema_config_schema * runtime_spec_schema_config_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  runtime_spec_schema_config_schema *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
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
ptr = make_runtime_spec_schema_config_schema (tree, ctx, err);return ptr; 
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
runtime_spec_schema_config_schema_generate_json (const runtime_spec_schema_config_schema *ptr, const struct parser_context *ctx, parser_error *err){
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

if (yajl_gen_status_ok != gen_runtime_spec_schema_config_schema (g, ptr, ctx, err))  {
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
