/* Generated from config-schema.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/image_spec_schema_config_schema.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (image_spec_schema_config_schema_config *, free_image_spec_schema_config_schema_config)
image_spec_schema_config_schema_config *
make_image_spec_schema_config_schema_config (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_config_schema_config) image_spec_schema_config_schema_config *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "User", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->user = strdup (str ? str : "");
            if (ret->user == NULL)
              return NULL;
          }
      }
    while (0);
    ret->exposed_ports = make_image_spec_schema_defs_map_string_object (get_val (tree, "ExposedPorts", yajl_t_object), ctx, err);
    if (ret->exposed_ports == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "Env", yajl_t_array);
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
        yajl_val tmp = get_val (tree, "Entrypoint", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->entrypoint_len = len;
            ret->entrypoint = calloc (len + 1, sizeof (*ret->entrypoint));
            if (ret->entrypoint == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->entrypoint[i] = strdup (str ? str : "");
                    if (ret->entrypoint[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "Cmd", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->cmd_len = len;
            ret->cmd = calloc (len + 1, sizeof (*ret->cmd));
            if (ret->cmd == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->cmd[i] = strdup (str ? str : "");
                    if (ret->cmd[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    ret->volumes = make_image_spec_schema_defs_map_string_object (get_val (tree, "Volumes", yajl_t_object), ctx, err);
    if (ret->volumes == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "WorkingDir", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->working_dir = strdup (str ? str : "");
            if (ret->working_dir == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "Labels", yajl_t_object);
        if (tmp != NULL)
          {
            ret->labels = make_json_map_string_string (tmp, ctx, err);
            if (ret->labels == NULL)
              {
                char *new_error = NULL;
                if (asprintf (&new_error, "Value error for key 'Labels': %s", *err ? *err : "null") < 0)
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
        yajl_val val = get_val (tree, "StopSignal", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->stop_signal = strdup (str ? str : "");
            if (ret->stop_signal == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "ArgsEscaped", yajl_t_true);
        if (val != NULL)
          {
            ret->args_escaped = YAJL_IS_TRUE(val);
            ret->args_escaped_present = 1;
          }
        else
          {
            val = get_val (tree, "ArgsEscaped", yajl_t_false);
            if (val != NULL)
              {
                ret->args_escaped = 0;
                ret->args_escaped_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "User")
                && strcmp (tree->u.object.keys[i], "ExposedPorts")
                && strcmp (tree->u.object.keys[i], "Env")
                && strcmp (tree->u.object.keys[i], "Entrypoint")
                && strcmp (tree->u.object.keys[i], "Cmd")
                && strcmp (tree->u.object.keys[i], "Volumes")
                && strcmp (tree->u.object.keys[i], "WorkingDir")
                && strcmp (tree->u.object.keys[i], "Labels")
                && strcmp (tree->u.object.keys[i], "StopSignal")
                && strcmp (tree->u.object.keys[i], "ArgsEscaped")){
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
free_image_spec_schema_config_schema_config (image_spec_schema_config_schema_config *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->user);
    ptr->user = NULL;
    free_image_spec_schema_defs_map_string_object (ptr->exposed_ports);
    ptr->exposed_ports = NULL;
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
    if (ptr->entrypoint != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->entrypoint_len; i++)
          {
            if (ptr->entrypoint[i] != NULL)
              {
                free (ptr->entrypoint[i]);
                ptr->entrypoint[i] = NULL;
              }
          }
        free (ptr->entrypoint);
        ptr->entrypoint = NULL;
    }
    if (ptr->cmd != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->cmd_len; i++)
          {
            if (ptr->cmd[i] != NULL)
              {
                free (ptr->cmd[i]);
                ptr->cmd[i] = NULL;
              }
          }
        free (ptr->cmd);
        ptr->cmd = NULL;
    }
    free_image_spec_schema_defs_map_string_object (ptr->volumes);
    ptr->volumes = NULL;
    free (ptr->working_dir);
    ptr->working_dir = NULL;
    free_json_map_string_string (ptr->labels);
    ptr->labels = NULL;
    free (ptr->stop_signal);
    ptr->stop_signal = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_config_schema_config (yajl_gen g, const image_spec_schema_config_schema_config *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->user != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("User"), 4 /* strlen ("User") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->user != NULL)
            str = ptr->user;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->exposed_ports != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ExposedPorts"), 12 /* strlen ("ExposedPorts") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_image_spec_schema_defs_map_string_object (g, ptr != NULL ? ptr->exposed_ports : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->env != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("Env"), 3 /* strlen ("Env") */);
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->entrypoint != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("Entrypoint"), 10 /* strlen ("Entrypoint") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->entrypoint != NULL)
          len = ptr->entrypoint_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->entrypoint[i]), strlen (ptr->entrypoint[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->cmd != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("Cmd"), 3 /* strlen ("Cmd") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->cmd != NULL)
          len = ptr->cmd_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->cmd[i]), strlen (ptr->cmd[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->volumes != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("Volumes"), 7 /* strlen ("Volumes") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_image_spec_schema_defs_map_string_object (g, ptr != NULL ? ptr->volumes : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->working_dir != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("WorkingDir"), 10 /* strlen ("WorkingDir") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->working_dir != NULL)
            str = ptr->working_dir;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->labels != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("labels"), 6 /* strlen ("labels") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_json_map_string_string (g, ptr ? ptr->labels : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->stop_signal != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("StopSignal"), 10 /* strlen ("StopSignal") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->stop_signal != NULL)
            str = ptr->stop_signal;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->args_escaped_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ArgsEscaped"), 11 /* strlen ("ArgsEscaped") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->args_escaped)
            b = ptr->args_escaped;
        
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

image_spec_schema_config_schema_config *
clone_image_spec_schema_config_schema_config (image_spec_schema_config_schema_config *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_config_schema_config) image_spec_schema_config_schema_config *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->user)
      {
        ret->user = strdup (src->user);
        if (ret->user == NULL)
          return NULL;
      }
    if (src->exposed_ports)
      {
        ret->exposed_ports = calloc (1, sizeof (*ret->exposed_ports));
        if (ret->exposed_ports == NULL)
            return NULL;
        ret->exposed_ports->len = src->exposed_ports->len;
        ret->exposed_ports->keys = calloc (src->exposed_ports->len + 1, sizeof (char *));
        if (ret->exposed_ports->keys == NULL)
            return NULL;
        ret->exposed_ports->values = calloc (src->exposed_ports->len + 1, sizeof (*ret->exposed_ports->values));
        if (ret->exposed_ports->values == NULL)
            return NULL;
        for (size_t i = 0; i < ret->exposed_ports->len; i++)
          {
            ret->exposed_ports->keys[i] = strdup (src->exposed_ports->keys[i]);
            if (ret->exposed_ports->keys[i] == NULL)
              return NULL;
            ret->exposed_ports->values[i] = clone_image_spec_schema_defs_map_string_object_element (src->exposed_ports->values[i]);
            if (ret->exposed_ports->values[i] == NULL)
              return NULL;
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
    if (src->entrypoint)
      {
        ret->entrypoint_len = src->entrypoint_len;
        ret->entrypoint = calloc (src->entrypoint_len + 1, sizeof (*ret->entrypoint));
        if (ret->entrypoint == NULL)
          return NULL;
        for (size_t i = 0; i < src->entrypoint_len; i++)
          {
            if (src->entrypoint[i])
              {
                ret->entrypoint[i] = strdup (src->entrypoint[i]);
                if (ret->entrypoint[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->cmd)
      {
        ret->cmd_len = src->cmd_len;
        ret->cmd = calloc (src->cmd_len + 1, sizeof (*ret->cmd));
        if (ret->cmd == NULL)
          return NULL;
        for (size_t i = 0; i < src->cmd_len; i++)
          {
            if (src->cmd[i])
              {
                ret->cmd[i] = strdup (src->cmd[i]);
                if (ret->cmd[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->volumes)
      {
        ret->volumes = calloc (1, sizeof (*ret->volumes));
        if (ret->volumes == NULL)
            return NULL;
        ret->volumes->len = src->volumes->len;
        ret->volumes->keys = calloc (src->volumes->len + 1, sizeof (char *));
        if (ret->volumes->keys == NULL)
            return NULL;
        ret->volumes->values = calloc (src->volumes->len + 1, sizeof (*ret->volumes->values));
        if (ret->volumes->values == NULL)
            return NULL;
        for (size_t i = 0; i < ret->volumes->len; i++)
          {
            ret->volumes->keys[i] = strdup (src->volumes->keys[i]);
            if (ret->volumes->keys[i] == NULL)
              return NULL;
            ret->volumes->values[i] = clone_image_spec_schema_defs_map_string_object_element (src->volumes->values[i]);
            if (ret->volumes->values[i] == NULL)
              return NULL;
          }
      }
    if (src->working_dir)
      {
        ret->working_dir = strdup (src->working_dir);
        if (ret->working_dir == NULL)
          return NULL;
      }
    ret->labels = clone_map_string_string (src->labels);
    if (ret->labels == NULL)
        return NULL;
    if (src->stop_signal)
      {
        ret->stop_signal = strdup (src->stop_signal);
        if (ret->stop_signal == NULL)
          return NULL;
      }
    ret->args_escaped = src->args_escaped;
    ret->args_escaped_present = src->args_escaped_present;
    return move_ptr (ret);
}

define_cleaner_function (image_spec_schema_config_schema_rootfs *, free_image_spec_schema_config_schema_rootfs)
image_spec_schema_config_schema_rootfs *
make_image_spec_schema_config_schema_rootfs (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_config_schema_rootfs) image_spec_schema_config_schema_rootfs *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "diff_ids", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->diff_ids_len = len;
            ret->diff_ids = calloc (len + 1, sizeof (*ret->diff_ids));
            if (ret->diff_ids == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->diff_ids[i] = strdup (str ? str : "");
                    if (ret->diff_ids[i] == NULL)
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
    if (ret->diff_ids == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "diff_ids") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
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
            if (strcmp (tree->u.object.keys[i], "diff_ids")
                && strcmp (tree->u.object.keys[i], "type")){
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
free_image_spec_schema_config_schema_rootfs (image_spec_schema_config_schema_rootfs *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->diff_ids != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->diff_ids_len; i++)
          {
            if (ptr->diff_ids[i] != NULL)
              {
                free (ptr->diff_ids[i]);
                ptr->diff_ids[i] = NULL;
              }
          }
        free (ptr->diff_ids);
        ptr->diff_ids = NULL;
    }
    free (ptr->type);
    ptr->type = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_config_schema_rootfs (yajl_gen g, const image_spec_schema_config_schema_rootfs *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->diff_ids != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("diff_ids"), 8 /* strlen ("diff_ids") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->diff_ids != NULL)
          len = ptr->diff_ids_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->diff_ids[i]), strlen (ptr->diff_ids[i]));
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

image_spec_schema_config_schema_rootfs *
clone_image_spec_schema_config_schema_rootfs (image_spec_schema_config_schema_rootfs *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_config_schema_rootfs) image_spec_schema_config_schema_rootfs *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->diff_ids)
      {
        ret->diff_ids_len = src->diff_ids_len;
        ret->diff_ids = calloc (src->diff_ids_len + 1, sizeof (*ret->diff_ids));
        if (ret->diff_ids == NULL)
          return NULL;
        for (size_t i = 0; i < src->diff_ids_len; i++)
          {
            if (src->diff_ids[i])
              {
                ret->diff_ids[i] = strdup (src->diff_ids[i]);
                if (ret->diff_ids[i] == NULL)
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
    return move_ptr (ret);
}

define_cleaner_function (image_spec_schema_config_schema_history_element *, free_image_spec_schema_config_schema_history_element)
image_spec_schema_config_schema_history_element *
make_image_spec_schema_config_schema_history_element (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_config_schema_history_element) image_spec_schema_config_schema_history_element *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "created", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->created = strdup (str ? str : "");
            if (ret->created == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "author", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->author = strdup (str ? str : "");
            if (ret->author == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "created_by", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->created_by = strdup (str ? str : "");
            if (ret->created_by == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "comment", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->comment = strdup (str ? str : "");
            if (ret->comment == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "empty_layer", yajl_t_true);
        if (val != NULL)
          {
            ret->empty_layer = YAJL_IS_TRUE(val);
            ret->empty_layer_present = 1;
          }
        else
          {
            val = get_val (tree, "empty_layer", yajl_t_false);
            if (val != NULL)
              {
                ret->empty_layer = 0;
                ret->empty_layer_present = 1;
              }
          }
      }
    while (0);
    return move_ptr (ret);
}

void
free_image_spec_schema_config_schema_history_element (image_spec_schema_config_schema_history_element *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->created);
    ptr->created = NULL;
    free (ptr->author);
    ptr->author = NULL;
    free (ptr->created_by);
    ptr->created_by = NULL;
    free (ptr->comment);
    ptr->comment = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_config_schema_history_element (yajl_gen g, const image_spec_schema_config_schema_history_element *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->created != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("created"), 7 /* strlen ("created") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->created != NULL)
            str = ptr->created;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->author != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("author"), 6 /* strlen ("author") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->author != NULL)
            str = ptr->author;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->created_by != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("created_by"), 10 /* strlen ("created_by") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->created_by != NULL)
            str = ptr->created_by;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->comment != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("comment"), 7 /* strlen ("comment") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->comment != NULL)
            str = ptr->comment;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->empty_layer_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("empty_layer"), 11 /* strlen ("empty_layer") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->empty_layer)
            b = ptr->empty_layer;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

image_spec_schema_config_schema_history_element *
clone_image_spec_schema_config_schema_history_element (image_spec_schema_config_schema_history_element *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_config_schema_history_element) image_spec_schema_config_schema_history_element *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->created)
      {
        ret->created = strdup (src->created);
        if (ret->created == NULL)
          return NULL;
      }
    if (src->author)
      {
        ret->author = strdup (src->author);
        if (ret->author == NULL)
          return NULL;
      }
    if (src->created_by)
      {
        ret->created_by = strdup (src->created_by);
        if (ret->created_by == NULL)
          return NULL;
      }
    if (src->comment)
      {
        ret->comment = strdup (src->comment);
        if (ret->comment == NULL)
          return NULL;
      }
    ret->empty_layer = src->empty_layer;
    ret->empty_layer_present = src->empty_layer_present;
    return move_ptr (ret);
}

define_cleaner_function (image_spec_schema_config_schema *, free_image_spec_schema_config_schema)
image_spec_schema_config_schema *
make_image_spec_schema_config_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_config_schema) image_spec_schema_config_schema *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "created", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->created = strdup (str ? str : "");
            if (ret->created == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "author", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->author = strdup (str ? str : "");
            if (ret->author == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "architecture", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->architecture = strdup (str ? str : "");
            if (ret->architecture == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "variant", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->variant = strdup (str ? str : "");
            if (ret->variant == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "os", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->os = strdup (str ? str : "");
            if (ret->os == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "os.version", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->os_version = strdup (str ? str : "");
            if (ret->os_version == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "os.features", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->os_features_len = len;
            ret->os_features = calloc (len + 1, sizeof (*ret->os_features));
            if (ret->os_features == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->os_features[i] = strdup (str ? str : "");
                    if (ret->os_features[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    ret->config = make_image_spec_schema_config_schema_config (get_val (tree, "config", yajl_t_object), ctx, err);
    if (ret->config == NULL && *err != 0)
      return NULL;
    ret->rootfs = make_image_spec_schema_config_schema_rootfs (get_val (tree, "rootfs", yajl_t_object), ctx, err);
    if (ret->rootfs == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "history", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->history_len = len;
            ret->history = calloc (len + 1, sizeof (*ret->history));
            if (ret->history == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->history[i] = make_image_spec_schema_config_schema_history_element (val, ctx, err);
                if (ret->history[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    if (ret->architecture == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "architecture") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->os == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "os") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->rootfs == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "rootfs") < 0)
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
            if (strcmp (tree->u.object.keys[i], "created")
                && strcmp (tree->u.object.keys[i], "author")
                && strcmp (tree->u.object.keys[i], "architecture")
                && strcmp (tree->u.object.keys[i], "variant")
                && strcmp (tree->u.object.keys[i], "os")
                && strcmp (tree->u.object.keys[i], "os.version")
                && strcmp (tree->u.object.keys[i], "os.features")
                && strcmp (tree->u.object.keys[i], "config")
                && strcmp (tree->u.object.keys[i], "rootfs")
                && strcmp (tree->u.object.keys[i], "history")){
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
free_image_spec_schema_config_schema (image_spec_schema_config_schema *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->created);
    ptr->created = NULL;
    free (ptr->author);
    ptr->author = NULL;
    free (ptr->architecture);
    ptr->architecture = NULL;
    free (ptr->variant);
    ptr->variant = NULL;
    free (ptr->os);
    ptr->os = NULL;
    free (ptr->os_version);
    ptr->os_version = NULL;
    if (ptr->os_features != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->os_features_len; i++)
          {
            if (ptr->os_features[i] != NULL)
              {
                free (ptr->os_features[i]);
                ptr->os_features[i] = NULL;
              }
          }
        free (ptr->os_features);
        ptr->os_features = NULL;
    }
    if (ptr->config != NULL)
      {
        free_image_spec_schema_config_schema_config (ptr->config);
        ptr->config = NULL;
      }
    if (ptr->rootfs != NULL)
      {
        free_image_spec_schema_config_schema_rootfs (ptr->rootfs);
        ptr->rootfs = NULL;
      }
    if (ptr->history != NULL)      {
        size_t i;
        for (i = 0; i < ptr->history_len; i++)
          {
          if (ptr->history[i] != NULL)
            {
              free_image_spec_schema_config_schema_history_element (ptr->history[i]);
              ptr->history[i] = NULL;
            }
          }
        free (ptr->history);
        ptr->history = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_config_schema (yajl_gen g, const image_spec_schema_config_schema *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->created != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("created"), 7 /* strlen ("created") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->created != NULL)
            str = ptr->created;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->author != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("author"), 6 /* strlen ("author") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->author != NULL)
            str = ptr->author;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->architecture != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("architecture"), 12 /* strlen ("architecture") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->architecture != NULL)
            str = ptr->architecture;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->variant != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("variant"), 7 /* strlen ("variant") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->variant != NULL)
            str = ptr->variant;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->os != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("os"), 2 /* strlen ("os") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->os != NULL)
            str = ptr->os;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->os_version != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("os.version"), 10 /* strlen ("os.version") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->os_version != NULL)
            str = ptr->os_version;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->os_features != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("os.features"), 11 /* strlen ("os.features") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->os_features != NULL)
          len = ptr->os_features_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->os_features[i]), strlen (ptr->os_features[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->config != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("config"), 6 /* strlen ("config") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_image_spec_schema_config_schema_config (g, ptr != NULL ? ptr->config : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->rootfs != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("rootfs"), 6 /* strlen ("rootfs") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_image_spec_schema_config_schema_rootfs (g, ptr != NULL ? ptr->rootfs : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->history != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("history"), 7 /* strlen ("history") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->history != NULL)
            len = ptr->history_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_image_spec_schema_config_schema_history_element (g, ptr->history[i], ctx, err);
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

image_spec_schema_config_schema *
clone_image_spec_schema_config_schema (image_spec_schema_config_schema *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_config_schema) image_spec_schema_config_schema *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->created)
      {
        ret->created = strdup (src->created);
        if (ret->created == NULL)
          return NULL;
      }
    if (src->author)
      {
        ret->author = strdup (src->author);
        if (ret->author == NULL)
          return NULL;
      }
    if (src->architecture)
      {
        ret->architecture = strdup (src->architecture);
        if (ret->architecture == NULL)
          return NULL;
      }
    if (src->variant)
      {
        ret->variant = strdup (src->variant);
        if (ret->variant == NULL)
          return NULL;
      }
    if (src->os)
      {
        ret->os = strdup (src->os);
        if (ret->os == NULL)
          return NULL;
      }
    if (src->os_version)
      {
        ret->os_version = strdup (src->os_version);
        if (ret->os_version == NULL)
          return NULL;
      }
    if (src->os_features)
      {
        ret->os_features_len = src->os_features_len;
        ret->os_features = calloc (src->os_features_len + 1, sizeof (*ret->os_features));
        if (ret->os_features == NULL)
          return NULL;
        for (size_t i = 0; i < src->os_features_len; i++)
          {
            if (src->os_features[i])
              {
                ret->os_features[i] = strdup (src->os_features[i]);
                if (ret->os_features[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->config)
      {
        ret->config = clone_image_spec_schema_config_schema_config (src->config);
        if (ret->config == NULL)
          return NULL;
      }
    if (src->rootfs)
      {
        ret->rootfs = clone_image_spec_schema_config_schema_rootfs (src->rootfs);
        if (ret->rootfs == NULL)
          return NULL;
      }
    if (src->history)
      {
        ret->history_len = src->history_len;
        ret->history = calloc (src->history_len + 1, sizeof (*ret->history));
        if (ret->history == NULL)
          return NULL;
        for (size_t i = 0; i < src->history_len; i++)
          {
            ret->history[i] = clone_image_spec_schema_config_schema_history_element (src->history[i]);
            if (ret->history[i] == NULL)
                return NULL;
          }
      }
    return move_ptr (ret);
}


image_spec_schema_config_schema *
image_spec_schema_config_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
image_spec_schema_config_schema *ptr = NULL;size_t filesize;
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
      }ptr = image_spec_schema_config_schema_parse_data (content, ctx, err);return ptr;
}
image_spec_schema_config_schema * 
image_spec_schema_config_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{image_spec_schema_config_schema *ptr = NULL;
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
ptr = image_spec_schema_config_schema_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 image_spec_schema_config_schema * image_spec_schema_config_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  image_spec_schema_config_schema *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
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
ptr = make_image_spec_schema_config_schema (tree, ctx, err);return ptr; 
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
image_spec_schema_config_schema_generate_json (const image_spec_schema_config_schema *ptr, const struct parser_context *ctx, parser_error *err){
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

if (yajl_gen_status_ok != gen_image_spec_schema_config_schema (g, ptr, ctx, err))  {
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
