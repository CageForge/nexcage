/* Generated from config-vm.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_config_vm.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_config_vm_hypervisor *, free_runtime_spec_schema_config_vm_hypervisor)
runtime_spec_schema_config_vm_hypervisor *
make_runtime_spec_schema_config_vm_hypervisor (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_vm_hypervisor) runtime_spec_schema_config_vm_hypervisor *ret = NULL;
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
        yajl_val tmp = get_val (tree, "parameters", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->parameters_len = len;
            ret->parameters = calloc (len + 1, sizeof (*ret->parameters));
            if (ret->parameters == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->parameters[i] = strdup (str ? str : "");
                    if (ret->parameters[i] == NULL)
                      return NULL;
                  }
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
                && strcmp (tree->u.object.keys[i], "parameters")){
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
free_runtime_spec_schema_config_vm_hypervisor (runtime_spec_schema_config_vm_hypervisor *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->path);
    ptr->path = NULL;
    if (ptr->parameters != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->parameters_len; i++)
          {
            if (ptr->parameters[i] != NULL)
              {
                free (ptr->parameters[i]);
                ptr->parameters[i] = NULL;
              }
          }
        free (ptr->parameters);
        ptr->parameters = NULL;
    }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_vm_hypervisor (yajl_gen g, const runtime_spec_schema_config_vm_hypervisor *ptr, const struct parser_context *ctx, parser_error *err)
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->parameters != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("parameters"), 10 /* strlen ("parameters") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->parameters != NULL)
          len = ptr->parameters_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->parameters[i]), strlen (ptr->parameters[i]));
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

runtime_spec_schema_config_vm_hypervisor *
clone_runtime_spec_schema_config_vm_hypervisor (runtime_spec_schema_config_vm_hypervisor *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_vm_hypervisor) runtime_spec_schema_config_vm_hypervisor *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->path)
      {
        ret->path = strdup (src->path);
        if (ret->path == NULL)
          return NULL;
      }
    if (src->parameters)
      {
        ret->parameters_len = src->parameters_len;
        ret->parameters = calloc (src->parameters_len + 1, sizeof (*ret->parameters));
        if (ret->parameters == NULL)
          return NULL;
        for (size_t i = 0; i < src->parameters_len; i++)
          {
            if (src->parameters[i])
              {
                ret->parameters[i] = strdup (src->parameters[i]);
                if (ret->parameters[i] == NULL)
                  return NULL;
              }
          }
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_vm_kernel *, free_runtime_spec_schema_config_vm_kernel)
runtime_spec_schema_config_vm_kernel *
make_runtime_spec_schema_config_vm_kernel (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_vm_kernel) runtime_spec_schema_config_vm_kernel *ret = NULL;
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
        yajl_val tmp = get_val (tree, "parameters", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->parameters_len = len;
            ret->parameters = calloc (len + 1, sizeof (*ret->parameters));
            if (ret->parameters == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->parameters[i] = strdup (str ? str : "");
                    if (ret->parameters[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "initrd", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->initrd = strdup (str ? str : "");
            if (ret->initrd == NULL)
              return NULL;
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
                && strcmp (tree->u.object.keys[i], "parameters")
                && strcmp (tree->u.object.keys[i], "initrd")){
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
free_runtime_spec_schema_config_vm_kernel (runtime_spec_schema_config_vm_kernel *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->path);
    ptr->path = NULL;
    if (ptr->parameters != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->parameters_len; i++)
          {
            if (ptr->parameters[i] != NULL)
              {
                free (ptr->parameters[i]);
                ptr->parameters[i] = NULL;
              }
          }
        free (ptr->parameters);
        ptr->parameters = NULL;
    }
    free (ptr->initrd);
    ptr->initrd = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_vm_kernel (yajl_gen g, const runtime_spec_schema_config_vm_kernel *ptr, const struct parser_context *ctx, parser_error *err)
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->parameters != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("parameters"), 10 /* strlen ("parameters") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->parameters != NULL)
          len = ptr->parameters_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->parameters[i]), strlen (ptr->parameters[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->initrd != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("initrd"), 6 /* strlen ("initrd") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->initrd != NULL)
            str = ptr->initrd;
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

runtime_spec_schema_config_vm_kernel *
clone_runtime_spec_schema_config_vm_kernel (runtime_spec_schema_config_vm_kernel *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_vm_kernel) runtime_spec_schema_config_vm_kernel *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->path)
      {
        ret->path = strdup (src->path);
        if (ret->path == NULL)
          return NULL;
      }
    if (src->parameters)
      {
        ret->parameters_len = src->parameters_len;
        ret->parameters = calloc (src->parameters_len + 1, sizeof (*ret->parameters));
        if (ret->parameters == NULL)
          return NULL;
        for (size_t i = 0; i < src->parameters_len; i++)
          {
            if (src->parameters[i])
              {
                ret->parameters[i] = strdup (src->parameters[i]);
                if (ret->parameters[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->initrd)
      {
        ret->initrd = strdup (src->initrd);
        if (ret->initrd == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_vm_image *, free_runtime_spec_schema_config_vm_image)
runtime_spec_schema_config_vm_image *
make_runtime_spec_schema_config_vm_image (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_vm_image) runtime_spec_schema_config_vm_image *ret = NULL;
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
        yajl_val val = get_val (tree, "format", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->format = strdup (str ? str : "");
            if (ret->format == NULL)
              return NULL;
          }
      }
    while (0);
    if (ret->path == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "path") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->format == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "format") < 0)
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
                && strcmp (tree->u.object.keys[i], "format")){
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
free_runtime_spec_schema_config_vm_image (runtime_spec_schema_config_vm_image *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->path);
    ptr->path = NULL;
    free (ptr->format);
    ptr->format = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_vm_image (yajl_gen g, const runtime_spec_schema_config_vm_image *ptr, const struct parser_context *ctx, parser_error *err)
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->format != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("format"), 6 /* strlen ("format") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->format != NULL)
            str = ptr->format;
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

runtime_spec_schema_config_vm_image *
clone_runtime_spec_schema_config_vm_image (runtime_spec_schema_config_vm_image *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_vm_image) runtime_spec_schema_config_vm_image *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->path)
      {
        ret->path = strdup (src->path);
        if (ret->path == NULL)
          return NULL;
      }
    if (src->format)
      {
        ret->format = strdup (src->format);
        if (ret->format == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_vm *, free_runtime_spec_schema_config_vm)
runtime_spec_schema_config_vm *
make_runtime_spec_schema_config_vm (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_vm) runtime_spec_schema_config_vm *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->hypervisor = make_runtime_spec_schema_config_vm_hypervisor (get_val (tree, "hypervisor", yajl_t_object), ctx, err);
    if (ret->hypervisor == NULL && *err != 0)
      return NULL;
    ret->kernel = make_runtime_spec_schema_config_vm_kernel (get_val (tree, "kernel", yajl_t_object), ctx, err);
    if (ret->kernel == NULL && *err != 0)
      return NULL;
    ret->image = make_runtime_spec_schema_config_vm_image (get_val (tree, "image", yajl_t_object), ctx, err);
    if (ret->image == NULL && *err != 0)
      return NULL;
    if (ret->kernel == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "kernel") < 0)
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
            if (strcmp (tree->u.object.keys[i], "hypervisor")
                && strcmp (tree->u.object.keys[i], "kernel")
                && strcmp (tree->u.object.keys[i], "image")){
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
free_runtime_spec_schema_config_vm (runtime_spec_schema_config_vm *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->hypervisor != NULL)
      {
        free_runtime_spec_schema_config_vm_hypervisor (ptr->hypervisor);
        ptr->hypervisor = NULL;
      }
    if (ptr->kernel != NULL)
      {
        free_runtime_spec_schema_config_vm_kernel (ptr->kernel);
        ptr->kernel = NULL;
      }
    if (ptr->image != NULL)
      {
        free_runtime_spec_schema_config_vm_image (ptr->image);
        ptr->image = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_vm (yajl_gen g, const runtime_spec_schema_config_vm *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->hypervisor != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hypervisor"), 10 /* strlen ("hypervisor") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_vm_hypervisor (g, ptr != NULL ? ptr->hypervisor : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->kernel != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("kernel"), 6 /* strlen ("kernel") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_vm_kernel (g, ptr != NULL ? ptr->kernel : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->image != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("image"), 5 /* strlen ("image") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_vm_image (g, ptr != NULL ? ptr->image : NULL, ctx, err);
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

runtime_spec_schema_config_vm *
clone_runtime_spec_schema_config_vm (runtime_spec_schema_config_vm *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_vm) runtime_spec_schema_config_vm *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->hypervisor)
      {
        ret->hypervisor = clone_runtime_spec_schema_config_vm_hypervisor (src->hypervisor);
        if (ret->hypervisor == NULL)
          return NULL;
      }
    if (src->kernel)
      {
        ret->kernel = clone_runtime_spec_schema_config_vm_kernel (src->kernel);
        if (ret->kernel == NULL)
          return NULL;
      }
    if (src->image)
      {
        ret->image = clone_runtime_spec_schema_config_vm_image (src->image);
        if (ret->image == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

