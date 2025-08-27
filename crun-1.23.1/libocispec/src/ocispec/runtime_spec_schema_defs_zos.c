/* Generated from defs-zos.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_defs_zos.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_defs_zos_namespace_reference *, free_runtime_spec_schema_defs_zos_namespace_reference)
runtime_spec_schema_defs_zos_namespace_reference *
make_runtime_spec_schema_defs_zos_namespace_reference (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_zos_namespace_reference) runtime_spec_schema_defs_zos_namespace_reference *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
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
    if (ret->type == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "type") < 0)
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
            if (strcmp (tree->u.object.keys[i], "type")
                && strcmp (tree->u.object.keys[i], "path")){
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
free_runtime_spec_schema_defs_zos_namespace_reference (runtime_spec_schema_defs_zos_namespace_reference *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->type);
    ptr->type = NULL;
    free (ptr->path);
    ptr->path = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_zos_namespace_reference (yajl_gen g, const runtime_spec_schema_defs_zos_namespace_reference *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
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

runtime_spec_schema_defs_zos_namespace_reference *
clone_runtime_spec_schema_defs_zos_namespace_reference (runtime_spec_schema_defs_zos_namespace_reference *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_zos_namespace_reference) runtime_spec_schema_defs_zos_namespace_reference *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->type)
      {
        ret->type = strdup (src->type);
        if (ret->type == NULL)
          return NULL;
      }
    if (src->path)
      {
        ret->path = strdup (src->path);
        if (ret->path == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

