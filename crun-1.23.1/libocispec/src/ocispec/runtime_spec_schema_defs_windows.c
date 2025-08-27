/* Generated from defs-windows.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_defs_windows.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_defs_windows_device *, free_runtime_spec_schema_defs_windows_device)
runtime_spec_schema_defs_windows_device *
make_runtime_spec_schema_defs_windows_device (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_windows_device) runtime_spec_schema_defs_windows_device *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "id", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->id = strdup (str ? str : "");
            if (ret->id == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "idType", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->id_type = strdup (str ? str : "");
            if (ret->id_type == NULL)
              return NULL;
          }
      }
    while (0);
    if (ret->id == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "id") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->id_type == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "idType") < 0)
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
            if (strcmp (tree->u.object.keys[i], "id")
                && strcmp (tree->u.object.keys[i], "idType")){
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
free_runtime_spec_schema_defs_windows_device (runtime_spec_schema_defs_windows_device *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->id);
    ptr->id = NULL;
    free (ptr->id_type);
    ptr->id_type = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_windows_device (yajl_gen g, const runtime_spec_schema_defs_windows_device *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->id != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("id"), 2 /* strlen ("id") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->id != NULL)
            str = ptr->id;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->id_type != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("idType"), 6 /* strlen ("idType") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->id_type != NULL)
            str = ptr->id_type;
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

runtime_spec_schema_defs_windows_device *
clone_runtime_spec_schema_defs_windows_device (runtime_spec_schema_defs_windows_device *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_windows_device) runtime_spec_schema_defs_windows_device *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->id)
      {
        ret->id = strdup (src->id);
        if (ret->id == NULL)
          return NULL;
      }
    if (src->id_type)
      {
        ret->id_type = strdup (src->id_type);
        if (ret->id_type == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

