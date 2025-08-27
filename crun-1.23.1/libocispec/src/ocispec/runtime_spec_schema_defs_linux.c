/* Generated from defs-linux.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_defs_linux.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_defs_linux_personality *, free_runtime_spec_schema_defs_linux_personality)
runtime_spec_schema_defs_linux_personality *
make_runtime_spec_schema_defs_linux_personality (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_personality) runtime_spec_schema_defs_linux_personality *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "domain", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->domain = strdup (str ? str : "");
            if (ret->domain == NULL)
              return NULL;
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
            if (strcmp (tree->u.object.keys[i], "domain")
                && strcmp (tree->u.object.keys[i], "flags")){
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
free_runtime_spec_schema_defs_linux_personality (runtime_spec_schema_defs_linux_personality *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->domain);
    ptr->domain = NULL;
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
gen_runtime_spec_schema_defs_linux_personality (yajl_gen g, const runtime_spec_schema_defs_linux_personality *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->domain != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("domain"), 6 /* strlen ("domain") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->domain != NULL)
            str = ptr->domain;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
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

runtime_spec_schema_defs_linux_personality *
clone_runtime_spec_schema_defs_linux_personality (runtime_spec_schema_defs_linux_personality *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_personality) runtime_spec_schema_defs_linux_personality *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->domain)
      {
        ret->domain = strdup (src->domain);
        if (ret->domain == NULL)
          return NULL;
      }
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
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_syscall_arg *, free_runtime_spec_schema_defs_linux_syscall_arg)
runtime_spec_schema_defs_linux_syscall_arg *
make_runtime_spec_schema_defs_linux_syscall_arg (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_syscall_arg) runtime_spec_schema_defs_linux_syscall_arg *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "index", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->index);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'index': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->index_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "value", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->value);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'value': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->value_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "valueTwo", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->value_two);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'valueTwo': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->value_two_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "op", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->op = strdup (str ? str : "");
            if (ret->op == NULL)
              return NULL;
          }
      }
    while (0);
    if (ret->op == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "op") < 0)
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
            if (strcmp (tree->u.object.keys[i], "index")
                && strcmp (tree->u.object.keys[i], "value")
                && strcmp (tree->u.object.keys[i], "valueTwo")
                && strcmp (tree->u.object.keys[i], "op")){
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
free_runtime_spec_schema_defs_linux_syscall_arg (runtime_spec_schema_defs_linux_syscall_arg *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->op);
    ptr->op = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_syscall_arg (yajl_gen g, const runtime_spec_schema_defs_linux_syscall_arg *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->index_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("index"), 5 /* strlen ("index") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->index)
            num = (long long unsigned int)ptr->index;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->value_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("value"), 5 /* strlen ("value") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->value)
            num = (long long unsigned int)ptr->value;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->value_two_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("valueTwo"), 8 /* strlen ("valueTwo") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->value_two)
            num = (long long unsigned int)ptr->value_two;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->op != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("op"), 2 /* strlen ("op") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->op != NULL)
            str = ptr->op;
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

runtime_spec_schema_defs_linux_syscall_arg *
clone_runtime_spec_schema_defs_linux_syscall_arg (runtime_spec_schema_defs_linux_syscall_arg *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_syscall_arg) runtime_spec_schema_defs_linux_syscall_arg *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->index = src->index;
    ret->index_present = src->index_present;
    ret->value = src->value;
    ret->value_present = src->value_present;
    ret->value_two = src->value_two;
    ret->value_two_present = src->value_two_present;
    if (src->op)
      {
        ret->op = strdup (src->op);
        if (ret->op == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_syscall *, free_runtime_spec_schema_defs_linux_syscall)
runtime_spec_schema_defs_linux_syscall *
make_runtime_spec_schema_defs_linux_syscall (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_syscall) runtime_spec_schema_defs_linux_syscall *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "names", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->names_len = len;
            ret->names = calloc (len + 1, sizeof (*ret->names));
            if (ret->names == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->names[i] = strdup (str ? str : "");
                    if (ret->names[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "action", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->action = strdup (str ? str : "");
            if (ret->action == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "errnoRet", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->errno_ret);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'errnoRet': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->errno_ret_present = 1;
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
                ret->args[i] = make_runtime_spec_schema_defs_linux_syscall_arg (val, ctx, err);
                if (ret->args[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    if (ret->names == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "names") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->action == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "action") < 0)
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
            if (strcmp (tree->u.object.keys[i], "names")
                && strcmp (tree->u.object.keys[i], "action")
                && strcmp (tree->u.object.keys[i], "errnoRet")
                && strcmp (tree->u.object.keys[i], "args")){
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
free_runtime_spec_schema_defs_linux_syscall (runtime_spec_schema_defs_linux_syscall *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->names != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->names_len; i++)
          {
            if (ptr->names[i] != NULL)
              {
                free (ptr->names[i]);
                ptr->names[i] = NULL;
              }
          }
        free (ptr->names);
        ptr->names = NULL;
    }
    free (ptr->action);
    ptr->action = NULL;
    if (ptr->args != NULL)      {
        size_t i;
        for (i = 0; i < ptr->args_len; i++)
          {
          if (ptr->args[i] != NULL)
            {
              free_runtime_spec_schema_defs_linux_syscall_arg (ptr->args[i]);
              ptr->args[i] = NULL;
            }
          }
        free (ptr->args);
        ptr->args = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_syscall (yajl_gen g, const runtime_spec_schema_defs_linux_syscall *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->names != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("names"), 5 /* strlen ("names") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->names != NULL)
          len = ptr->names_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->names[i]), strlen (ptr->names[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->action != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("action"), 6 /* strlen ("action") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->action != NULL)
            str = ptr->action;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->errno_ret_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("errnoRet"), 8 /* strlen ("errnoRet") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->errno_ret)
            num = (long long unsigned int)ptr->errno_ret;
        stat = map_uint (g, num);
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
            stat = gen_runtime_spec_schema_defs_linux_syscall_arg (g, ptr->args[i], ctx, err);
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

runtime_spec_schema_defs_linux_syscall *
clone_runtime_spec_schema_defs_linux_syscall (runtime_spec_schema_defs_linux_syscall *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_syscall) runtime_spec_schema_defs_linux_syscall *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->names)
      {
        ret->names_len = src->names_len;
        ret->names = calloc (src->names_len + 1, sizeof (*ret->names));
        if (ret->names == NULL)
          return NULL;
        for (size_t i = 0; i < src->names_len; i++)
          {
            if (src->names[i])
              {
                ret->names[i] = strdup (src->names[i]);
                if (ret->names[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->action)
      {
        ret->action = strdup (src->action);
        if (ret->action == NULL)
          return NULL;
      }
    ret->errno_ret = src->errno_ret;
    ret->errno_ret_present = src->errno_ret_present;
    if (src->args)
      {
        ret->args_len = src->args_len;
        ret->args = calloc (src->args_len + 1, sizeof (*ret->args));
        if (ret->args == NULL)
          return NULL;
        for (size_t i = 0; i < src->args_len; i++)
          {
            ret->args[i] = clone_runtime_spec_schema_defs_linux_syscall_arg (src->args[i]);
            if (ret->args[i] == NULL)
                return NULL;
          }
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_device *, free_runtime_spec_schema_defs_linux_device)
runtime_spec_schema_defs_linux_device *
make_runtime_spec_schema_defs_linux_device (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_device) runtime_spec_schema_defs_linux_device *ret = NULL;
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
    do
      {
        yajl_val val = get_val (tree, "fileMode", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int (YAJL_GET_NUMBER (val), (int *)&ret->file_mode);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'integer' for key 'fileMode': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->file_mode_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "major", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->major);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'major': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->major_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "minor", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->minor);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'minor': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->minor_present = 1;
        }
      }
    while (0);
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
    if (ret->type == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "type") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
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
            if (strcmp (tree->u.object.keys[i], "type")
                && strcmp (tree->u.object.keys[i], "path")
                && strcmp (tree->u.object.keys[i], "fileMode")
                && strcmp (tree->u.object.keys[i], "major")
                && strcmp (tree->u.object.keys[i], "minor")
                && strcmp (tree->u.object.keys[i], "uid")
                && strcmp (tree->u.object.keys[i], "gid")){
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
free_runtime_spec_schema_defs_linux_device (runtime_spec_schema_defs_linux_device *ptr)
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
gen_runtime_spec_schema_defs_linux_device (yajl_gen g, const runtime_spec_schema_defs_linux_device *ptr, const struct parser_context *ctx, parser_error *err)
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->file_mode_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("fileMode"), 8 /* strlen ("fileMode") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->file_mode)
            num = (long long int)ptr->file_mode;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->major_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("major"), 5 /* strlen ("major") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->major)
            num = (long long int)ptr->major;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->minor_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("minor"), 5 /* strlen ("minor") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->minor)
            num = (long long int)ptr->minor;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
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

runtime_spec_schema_defs_linux_device *
clone_runtime_spec_schema_defs_linux_device (runtime_spec_schema_defs_linux_device *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_device) runtime_spec_schema_defs_linux_device *ret = NULL;
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
    ret->file_mode = src->file_mode;
    ret->file_mode_present = src->file_mode_present;
    ret->major = src->major;
    ret->major_present = src->major_present;
    ret->minor = src->minor;
    ret->minor_present = src->minor_present;
    ret->uid = src->uid;
    ret->uid_present = src->uid_present;
    ret->gid = src->gid;
    ret->gid_present = src->gid_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_net_device *, free_runtime_spec_schema_defs_linux_net_device)
runtime_spec_schema_defs_linux_net_device *
make_runtime_spec_schema_defs_linux_net_device (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_net_device) runtime_spec_schema_defs_linux_net_device *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "name", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->name = strdup (str ? str : "");
            if (ret->name == NULL)
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
            if (strcmp (tree->u.object.keys[i], "name")){
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
free_runtime_spec_schema_defs_linux_net_device (runtime_spec_schema_defs_linux_net_device *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->name);
    ptr->name = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_net_device (yajl_gen g, const runtime_spec_schema_defs_linux_net_device *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->name != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("name"), 4 /* strlen ("name") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->name != NULL)
            str = ptr->name;
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

runtime_spec_schema_defs_linux_net_device *
clone_runtime_spec_schema_defs_linux_net_device (runtime_spec_schema_defs_linux_net_device *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_net_device) runtime_spec_schema_defs_linux_net_device *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->name)
      {
        ret->name = strdup (src->name);
        if (ret->name == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_block_io_device *, free_runtime_spec_schema_defs_linux_block_io_device)
runtime_spec_schema_defs_linux_block_io_device *
make_runtime_spec_schema_defs_linux_block_io_device (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_block_io_device) runtime_spec_schema_defs_linux_block_io_device *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "major", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->major);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'major': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->major_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "minor", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->minor);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'minor': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->minor_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "major")
                && strcmp (tree->u.object.keys[i], "minor")){
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
free_runtime_spec_schema_defs_linux_block_io_device (runtime_spec_schema_defs_linux_block_io_device *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_block_io_device (yajl_gen g, const runtime_spec_schema_defs_linux_block_io_device *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->major_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("major"), 5 /* strlen ("major") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->major)
            num = (long long int)ptr->major;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->minor_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("minor"), 5 /* strlen ("minor") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->minor)
            num = (long long int)ptr->minor;
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

runtime_spec_schema_defs_linux_block_io_device *
clone_runtime_spec_schema_defs_linux_block_io_device (runtime_spec_schema_defs_linux_block_io_device *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_block_io_device) runtime_spec_schema_defs_linux_block_io_device *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->major = src->major;
    ret->major_present = src->major_present;
    ret->minor = src->minor;
    ret->minor_present = src->minor_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_block_io_device_weight *, free_runtime_spec_schema_defs_linux_block_io_device_weight)
runtime_spec_schema_defs_linux_block_io_device_weight *
make_runtime_spec_schema_defs_linux_block_io_device_weight (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_block_io_device_weight) runtime_spec_schema_defs_linux_block_io_device_weight *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "major", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->major);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'major': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->major_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "minor", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->minor);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'minor': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->minor_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "weight", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint16 (YAJL_GET_NUMBER (val), &ret->weight);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint16' for key 'weight': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->weight_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "leafWeight", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint16 (YAJL_GET_NUMBER (val), &ret->leaf_weight);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint16' for key 'leafWeight': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->leaf_weight_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "major")
                && strcmp (tree->u.object.keys[i], "minor")
                && strcmp (tree->u.object.keys[i], "weight")
                && strcmp (tree->u.object.keys[i], "leafWeight")){
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
free_runtime_spec_schema_defs_linux_block_io_device_weight (runtime_spec_schema_defs_linux_block_io_device_weight *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_block_io_device_weight (yajl_gen g, const runtime_spec_schema_defs_linux_block_io_device_weight *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->major_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("major"), 5 /* strlen ("major") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->major)
            num = (long long int)ptr->major;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->minor_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("minor"), 5 /* strlen ("minor") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->minor)
            num = (long long int)ptr->minor;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->weight_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("weight"), 6 /* strlen ("weight") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->weight)
            num = (long long unsigned int)ptr->weight;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->leaf_weight_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("leafWeight"), 10 /* strlen ("leafWeight") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->leaf_weight)
            num = (long long unsigned int)ptr->leaf_weight;
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

runtime_spec_schema_defs_linux_block_io_device_weight *
clone_runtime_spec_schema_defs_linux_block_io_device_weight (runtime_spec_schema_defs_linux_block_io_device_weight *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_block_io_device_weight) runtime_spec_schema_defs_linux_block_io_device_weight *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->major = src->major;
    ret->major_present = src->major_present;
    ret->minor = src->minor;
    ret->minor_present = src->minor_present;
    ret->weight = src->weight;
    ret->weight_present = src->weight_present;
    ret->leaf_weight = src->leaf_weight;
    ret->leaf_weight_present = src->leaf_weight_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_block_io_device_throttle *, free_runtime_spec_schema_defs_linux_block_io_device_throttle)
runtime_spec_schema_defs_linux_block_io_device_throttle *
make_runtime_spec_schema_defs_linux_block_io_device_throttle (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_block_io_device_throttle) runtime_spec_schema_defs_linux_block_io_device_throttle *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "major", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->major);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'major': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->major_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "minor", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->minor);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'minor': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->minor_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "rate", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->rate);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'rate': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->rate_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "major")
                && strcmp (tree->u.object.keys[i], "minor")
                && strcmp (tree->u.object.keys[i], "rate")){
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
free_runtime_spec_schema_defs_linux_block_io_device_throttle (runtime_spec_schema_defs_linux_block_io_device_throttle *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_block_io_device_throttle (yajl_gen g, const runtime_spec_schema_defs_linux_block_io_device_throttle *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->major_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("major"), 5 /* strlen ("major") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->major)
            num = (long long int)ptr->major;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->minor_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("minor"), 5 /* strlen ("minor") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->minor)
            num = (long long int)ptr->minor;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->rate_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("rate"), 4 /* strlen ("rate") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->rate)
            num = (long long unsigned int)ptr->rate;
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

runtime_spec_schema_defs_linux_block_io_device_throttle *
clone_runtime_spec_schema_defs_linux_block_io_device_throttle (runtime_spec_schema_defs_linux_block_io_device_throttle *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_block_io_device_throttle) runtime_spec_schema_defs_linux_block_io_device_throttle *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->major = src->major;
    ret->major_present = src->major_present;
    ret->minor = src->minor;
    ret->minor_present = src->minor_present;
    ret->rate = src->rate;
    ret->rate_present = src->rate_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_device_cgroup *, free_runtime_spec_schema_defs_linux_device_cgroup)
runtime_spec_schema_defs_linux_device_cgroup *
make_runtime_spec_schema_defs_linux_device_cgroup (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_device_cgroup) runtime_spec_schema_defs_linux_device_cgroup *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "allow", yajl_t_true);
        if (val != NULL)
          {
            ret->allow = YAJL_IS_TRUE(val);
            ret->allow_present = 1;
          }
        else
          {
            val = get_val (tree, "allow", yajl_t_false);
            if (val != NULL)
              {
                ret->allow = 0;
                ret->allow_present = 1;
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
        yajl_val val = get_val (tree, "major", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->major);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'major': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->major_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "minor", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->minor);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'minor': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->minor_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "access", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->access = strdup (str ? str : "");
            if (ret->access == NULL)
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
            if (strcmp (tree->u.object.keys[i], "allow")
                && strcmp (tree->u.object.keys[i], "type")
                && strcmp (tree->u.object.keys[i], "major")
                && strcmp (tree->u.object.keys[i], "minor")
                && strcmp (tree->u.object.keys[i], "access")){
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
free_runtime_spec_schema_defs_linux_device_cgroup (runtime_spec_schema_defs_linux_device_cgroup *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->type);
    ptr->type = NULL;
    free (ptr->access);
    ptr->access = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_device_cgroup (yajl_gen g, const runtime_spec_schema_defs_linux_device_cgroup *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->allow_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("allow"), 5 /* strlen ("allow") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->allow)
            b = ptr->allow;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->major_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("major"), 5 /* strlen ("major") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->major)
            num = (long long int)ptr->major;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->minor_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("minor"), 5 /* strlen ("minor") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->minor)
            num = (long long int)ptr->minor;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->access != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("access"), 6 /* strlen ("access") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->access != NULL)
            str = ptr->access;
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

runtime_spec_schema_defs_linux_device_cgroup *
clone_runtime_spec_schema_defs_linux_device_cgroup (runtime_spec_schema_defs_linux_device_cgroup *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_device_cgroup) runtime_spec_schema_defs_linux_device_cgroup *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->allow = src->allow;
    ret->allow_present = src->allow_present;
    if (src->type)
      {
        ret->type = strdup (src->type);
        if (ret->type == NULL)
          return NULL;
      }
    ret->major = src->major;
    ret->major_present = src->major_present;
    ret->minor = src->minor;
    ret->minor_present = src->minor_present;
    if (src->access)
      {
        ret->access = strdup (src->access);
        if (ret->access == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_network_interface_priority *, free_runtime_spec_schema_defs_linux_network_interface_priority)
runtime_spec_schema_defs_linux_network_interface_priority *
make_runtime_spec_schema_defs_linux_network_interface_priority (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_network_interface_priority) runtime_spec_schema_defs_linux_network_interface_priority *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "name", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->name = strdup (str ? str : "");
            if (ret->name == NULL)
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
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->priority);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'priority': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->priority_present = 1;
        }
      }
    while (0);
    if (ret->name == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "name") < 0)
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
            if (strcmp (tree->u.object.keys[i], "name")
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
free_runtime_spec_schema_defs_linux_network_interface_priority (runtime_spec_schema_defs_linux_network_interface_priority *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->name);
    ptr->name = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_network_interface_priority (yajl_gen g, const runtime_spec_schema_defs_linux_network_interface_priority *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->name != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("name"), 4 /* strlen ("name") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->name != NULL)
            str = ptr->name;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->priority_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("priority"), 8 /* strlen ("priority") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->priority)
            num = (long long unsigned int)ptr->priority;
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

runtime_spec_schema_defs_linux_network_interface_priority *
clone_runtime_spec_schema_defs_linux_network_interface_priority (runtime_spec_schema_defs_linux_network_interface_priority *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_network_interface_priority) runtime_spec_schema_defs_linux_network_interface_priority *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->name)
      {
        ret->name = strdup (src->name);
        if (ret->name == NULL)
          return NULL;
      }
    ret->priority = src->priority;
    ret->priority_present = src->priority_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_rdma *, free_runtime_spec_schema_defs_linux_rdma)
runtime_spec_schema_defs_linux_rdma *
make_runtime_spec_schema_defs_linux_rdma (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_rdma) runtime_spec_schema_defs_linux_rdma *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "hcaHandles", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->hca_handles);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'hcaHandles': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->hca_handles_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "hcaObjects", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->hca_objects);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'hcaObjects': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->hca_objects_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "hcaHandles")
                && strcmp (tree->u.object.keys[i], "hcaObjects")){
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
free_runtime_spec_schema_defs_linux_rdma (runtime_spec_schema_defs_linux_rdma *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_rdma (yajl_gen g, const runtime_spec_schema_defs_linux_rdma *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->hca_handles_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hcaHandles"), 10 /* strlen ("hcaHandles") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->hca_handles)
            num = (long long unsigned int)ptr->hca_handles;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->hca_objects_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hcaObjects"), 10 /* strlen ("hcaObjects") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->hca_objects)
            num = (long long unsigned int)ptr->hca_objects;
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

runtime_spec_schema_defs_linux_rdma *
clone_runtime_spec_schema_defs_linux_rdma (runtime_spec_schema_defs_linux_rdma *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_rdma) runtime_spec_schema_defs_linux_rdma *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->hca_handles = src->hca_handles;
    ret->hca_handles_present = src->hca_handles_present;
    ret->hca_objects = src->hca_objects;
    ret->hca_objects_present = src->hca_objects_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_defs_linux_namespace_reference *, free_runtime_spec_schema_defs_linux_namespace_reference)
runtime_spec_schema_defs_linux_namespace_reference *
make_runtime_spec_schema_defs_linux_namespace_reference (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_namespace_reference) runtime_spec_schema_defs_linux_namespace_reference *ret = NULL;
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
free_runtime_spec_schema_defs_linux_namespace_reference (runtime_spec_schema_defs_linux_namespace_reference *ptr)
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
gen_runtime_spec_schema_defs_linux_namespace_reference (yajl_gen g, const runtime_spec_schema_defs_linux_namespace_reference *ptr, const struct parser_context *ctx, parser_error *err)
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

runtime_spec_schema_defs_linux_namespace_reference *
clone_runtime_spec_schema_defs_linux_namespace_reference (runtime_spec_schema_defs_linux_namespace_reference *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_namespace_reference) runtime_spec_schema_defs_linux_namespace_reference *ret = NULL;
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

define_cleaner_function (runtime_spec_schema_defs_linux_time_offsets *, free_runtime_spec_schema_defs_linux_time_offsets)
runtime_spec_schema_defs_linux_time_offsets *
make_runtime_spec_schema_defs_linux_time_offsets (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_defs_linux_time_offsets) runtime_spec_schema_defs_linux_time_offsets *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "secs", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->secs);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'secs': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->secs_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "nanosecs", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->nanosecs);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'nanosecs': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->nanosecs_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "secs")
                && strcmp (tree->u.object.keys[i], "nanosecs")){
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
free_runtime_spec_schema_defs_linux_time_offsets (runtime_spec_schema_defs_linux_time_offsets *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_defs_linux_time_offsets (yajl_gen g, const runtime_spec_schema_defs_linux_time_offsets *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->secs_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("secs"), 4 /* strlen ("secs") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->secs)
            num = (long long int)ptr->secs;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->nanosecs_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("nanosecs"), 8 /* strlen ("nanosecs") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->nanosecs)
            num = (long long unsigned int)ptr->nanosecs;
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

runtime_spec_schema_defs_linux_time_offsets *
clone_runtime_spec_schema_defs_linux_time_offsets (runtime_spec_schema_defs_linux_time_offsets *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_defs_linux_time_offsets) runtime_spec_schema_defs_linux_time_offsets *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->secs = src->secs;
    ret->secs_present = src->secs_present;
    ret->nanosecs = src->nanosecs;
    ret->nanosecs_present = src->nanosecs_present;
    return move_ptr (ret);
}

