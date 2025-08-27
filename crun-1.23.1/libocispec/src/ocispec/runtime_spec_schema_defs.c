/* Generated from defs.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_defs.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_defs_hook *, free_runtime_spec_schema_defs_hook)
runtime_spec_schema_defs_hook *
make_runtime_spec_schema_defs_hook (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_hook) runtime_spec_schema_defs_hook *ret = NULL;
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
        yajl_val val = get_val (tree, "timeout", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int (YAJL_GET_NUMBER (val), (int *)&ret->timeout);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'integer' for key 'timeout': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->timeout_present = 1;
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
                && strcmp (tree->u.object.keys[i], "args")
                && strcmp (tree->u.object.keys[i], "env")
                && strcmp (tree->u.object.keys[i], "timeout")){
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
free_runtime_spec_schema_defs_hook (runtime_spec_schema_defs_hook *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->path);
    ptr->path = NULL;
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
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_hook (yajl_gen g, const runtime_spec_schema_defs_hook *ptr, const struct parser_context *ctx, parser_error *err)
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->timeout_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("timeout"), 7 /* strlen ("timeout") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->timeout)
            num = (long long int)ptr->timeout;
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

runtime_spec_schema_defs_hook *
clone_runtime_spec_schema_defs_hook (runtime_spec_schema_defs_hook *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_hook) runtime_spec_schema_defs_hook *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->path)
      {
        ret->path = strdup (src->path);
        if (ret->path == NULL)
          return NULL;
      }
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
    ret->timeout = src->timeout;
    ret->timeout_present = src->timeout_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_id_mapping *, free_runtime_spec_schema_defs_id_mapping)
runtime_spec_schema_defs_id_mapping *
make_runtime_spec_schema_defs_id_mapping (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_id_mapping) runtime_spec_schema_defs_id_mapping *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "containerID", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->container_id);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'containerID': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->container_id_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "hostID", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->host_id);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'hostID': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->host_id_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "size", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->size);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'size': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->size_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "containerID")
                && strcmp (tree->u.object.keys[i], "hostID")
                && strcmp (tree->u.object.keys[i], "size")){
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
free_runtime_spec_schema_defs_id_mapping (runtime_spec_schema_defs_id_mapping *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_id_mapping (yajl_gen g, const runtime_spec_schema_defs_id_mapping *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->container_id_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("containerID"), 11 /* strlen ("containerID") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->container_id)
            num = (long long unsigned int)ptr->container_id;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->host_id_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hostID"), 6 /* strlen ("hostID") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->host_id)
            num = (long long unsigned int)ptr->host_id;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->size_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("size"), 4 /* strlen ("size") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->size)
            num = (long long unsigned int)ptr->size;
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

runtime_spec_schema_defs_id_mapping *
clone_runtime_spec_schema_defs_id_mapping (runtime_spec_schema_defs_id_mapping *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_id_mapping) runtime_spec_schema_defs_id_mapping *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->container_id = src->container_id;
    ret->container_id_present = src->container_id_present;
    ret->host_id = src->host_id;
    ret->host_id_present = src->host_id_present;
    ret->size = src->size;
    ret->size_present = src->size_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_mount *, free_runtime_spec_schema_defs_mount)
runtime_spec_schema_defs_mount *
make_runtime_spec_schema_defs_mount (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_mount) runtime_spec_schema_defs_mount *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "source", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->source = strdup (str ? str : "");
            if (ret->source == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "destination", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->destination = strdup (str ? str : "");
            if (ret->destination == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "options", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->options_len = len;
            ret->options = calloc (len + 1, sizeof (*ret->options));
            if (ret->options == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->options[i] = strdup (str ? str : "");
                    if (ret->options[i] == NULL)
                      return NULL;
                  }
              }
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
    do
      {
        yajl_val tmp = get_val (tree, "uidMappings", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->uid_mappings_len = len;
            ret->uid_mappings = calloc (len + 1, sizeof (*ret->uid_mappings));
            if (ret->uid_mappings == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->uid_mappings[i] = make_runtime_spec_schema_defs_id_mapping (val, ctx, err);
                if (ret->uid_mappings[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "gidMappings", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->gid_mappings_len = len;
            ret->gid_mappings = calloc (len + 1, sizeof (*ret->gid_mappings));
            if (ret->gid_mappings == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->gid_mappings[i] = make_runtime_spec_schema_defs_id_mapping (val, ctx, err);
                if (ret->gid_mappings[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    if (ret->destination == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "destination") < 0)
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
            if (strcmp (tree->u.object.keys[i], "source")
                && strcmp (tree->u.object.keys[i], "destination")
                && strcmp (tree->u.object.keys[i], "options")
                && strcmp (tree->u.object.keys[i], "type")
                && strcmp (tree->u.object.keys[i], "uidMappings")
                && strcmp (tree->u.object.keys[i], "gidMappings")){
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
free_runtime_spec_schema_defs_mount (runtime_spec_schema_defs_mount *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->source);
    ptr->source = NULL;
    free (ptr->destination);
    ptr->destination = NULL;
    if (ptr->options != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->options_len; i++)
          {
            if (ptr->options[i] != NULL)
              {
                free (ptr->options[i]);
                ptr->options[i] = NULL;
              }
          }
        free (ptr->options);
        ptr->options = NULL;
    }
    free (ptr->type);
    ptr->type = NULL;
    if (ptr->uid_mappings != NULL)      {
        size_t i;
        for (i = 0; i < ptr->uid_mappings_len; i++)
          {
          if (ptr->uid_mappings[i] != NULL)
            {
              free_runtime_spec_schema_defs_id_mapping (ptr->uid_mappings[i]);
              ptr->uid_mappings[i] = NULL;
            }
          }
        free (ptr->uid_mappings);
        ptr->uid_mappings = NULL;
      }
    if (ptr->gid_mappings != NULL)      {
        size_t i;
        for (i = 0; i < ptr->gid_mappings_len; i++)
          {
          if (ptr->gid_mappings[i] != NULL)
            {
              free_runtime_spec_schema_defs_id_mapping (ptr->gid_mappings[i]);
              ptr->gid_mappings[i] = NULL;
            }
          }
        free (ptr->gid_mappings);
        ptr->gid_mappings = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_mount (yajl_gen g, const runtime_spec_schema_defs_mount *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->source != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("source"), 6 /* strlen ("source") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->source != NULL)
            str = ptr->source;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->destination != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("destination"), 11 /* strlen ("destination") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->destination != NULL)
            str = ptr->destination;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->options != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("options"), 7 /* strlen ("options") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->options != NULL)
          len = ptr->options_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->options[i]), strlen (ptr->options[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->uid_mappings != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("uidMappings"), 11 /* strlen ("uidMappings") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->uid_mappings != NULL)
            len = ptr->uid_mappings_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_id_mapping (g, ptr->uid_mappings[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->gid_mappings != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("gidMappings"), 11 /* strlen ("gidMappings") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->gid_mappings != NULL)
            len = ptr->gid_mappings_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_id_mapping (g, ptr->gid_mappings[i], ctx, err);
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

runtime_spec_schema_defs_mount *
clone_runtime_spec_schema_defs_mount (runtime_spec_schema_defs_mount *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_mount) runtime_spec_schema_defs_mount *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->source)
      {
        ret->source = strdup (src->source);
        if (ret->source == NULL)
          return NULL;
      }
    if (src->destination)
      {
        ret->destination = strdup (src->destination);
        if (ret->destination == NULL)
          return NULL;
      }
    if (src->options)
      {
        ret->options_len = src->options_len;
        ret->options = calloc (src->options_len + 1, sizeof (*ret->options));
        if (ret->options == NULL)
          return NULL;
        for (size_t i = 0; i < src->options_len; i++)
          {
            if (src->options[i])
              {
                ret->options[i] = strdup (src->options[i]);
                if (ret->options[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->type)
      {
        ret->type = strdup (src->type);
        if (ret->type == NULL)
          return NULL;
      }
    if (src->uid_mappings)
      {
        ret->uid_mappings_len = src->uid_mappings_len;
        ret->uid_mappings = calloc (src->uid_mappings_len + 1, sizeof (*ret->uid_mappings));
        if (ret->uid_mappings == NULL)
          return NULL;
        for (size_t i = 0; i < src->uid_mappings_len; i++)
          {
            ret->uid_mappings[i] = clone_runtime_spec_schema_defs_id_mapping (src->uid_mappings[i]);
            if (ret->uid_mappings[i] == NULL)
                return NULL;
          }
      }
    if (src->gid_mappings)
      {
        ret->gid_mappings_len = src->gid_mappings_len;
        ret->gid_mappings = calloc (src->gid_mappings_len + 1, sizeof (*ret->gid_mappings));
        if (ret->gid_mappings == NULL)
          return NULL;
        for (size_t i = 0; i < src->gid_mappings_len; i++)
          {
            ret->gid_mappings[i] = clone_runtime_spec_schema_defs_id_mapping (src->gid_mappings[i]);
            if (ret->gid_mappings[i] == NULL)
                return NULL;
          }
      }
    return move_ptr (ret);
}

