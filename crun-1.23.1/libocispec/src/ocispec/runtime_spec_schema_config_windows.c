/* Generated from config-windows.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_config_windows.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_config_windows_resources_memory *, free_runtime_spec_schema_config_windows_resources_memory)
runtime_spec_schema_config_windows_resources_memory *
make_runtime_spec_schema_config_windows_resources_memory (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources_memory) runtime_spec_schema_config_windows_resources_memory *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "limit", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->limit);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'limit': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->limit_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "limit")){
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
free_runtime_spec_schema_config_windows_resources_memory (runtime_spec_schema_config_windows_resources_memory *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows_resources_memory (yajl_gen g, const runtime_spec_schema_config_windows_resources_memory *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->limit_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("limit"), 5 /* strlen ("limit") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->limit)
            num = (long long unsigned int)ptr->limit;
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

runtime_spec_schema_config_windows_resources_memory *
clone_runtime_spec_schema_config_windows_resources_memory (runtime_spec_schema_config_windows_resources_memory *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources_memory) runtime_spec_schema_config_windows_resources_memory *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->limit = src->limit;
    ret->limit_present = src->limit_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_windows_resources_cpu_affinity *, free_runtime_spec_schema_config_windows_resources_cpu_affinity)
runtime_spec_schema_config_windows_resources_cpu_affinity *
make_runtime_spec_schema_config_windows_resources_cpu_affinity (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources_cpu_affinity) runtime_spec_schema_config_windows_resources_cpu_affinity *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "mask", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->mask);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'mask': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->mask_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "group", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint32 (YAJL_GET_NUMBER (val), &ret->group);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint32' for key 'group': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->group_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "mask")
                && strcmp (tree->u.object.keys[i], "group")){
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
free_runtime_spec_schema_config_windows_resources_cpu_affinity (runtime_spec_schema_config_windows_resources_cpu_affinity *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows_resources_cpu_affinity (yajl_gen g, const runtime_spec_schema_config_windows_resources_cpu_affinity *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->mask_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("mask"), 4 /* strlen ("mask") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->mask)
            num = (long long unsigned int)ptr->mask;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->group_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("group"), 5 /* strlen ("group") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->group)
            num = (long long unsigned int)ptr->group;
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

runtime_spec_schema_config_windows_resources_cpu_affinity *
clone_runtime_spec_schema_config_windows_resources_cpu_affinity (runtime_spec_schema_config_windows_resources_cpu_affinity *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources_cpu_affinity) runtime_spec_schema_config_windows_resources_cpu_affinity *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->mask = src->mask;
    ret->mask_present = src->mask_present;
    ret->group = src->group;
    ret->group_present = src->group_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_windows_resources_cpu *, free_runtime_spec_schema_config_windows_resources_cpu)
runtime_spec_schema_config_windows_resources_cpu *
make_runtime_spec_schema_config_windows_resources_cpu (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources_cpu) runtime_spec_schema_config_windows_resources_cpu *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "count", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->count);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'count': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->count_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "shares", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint16 (YAJL_GET_NUMBER (val), &ret->shares);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint16' for key 'shares': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->shares_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "maximum", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint16 (YAJL_GET_NUMBER (val), &ret->maximum);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint16' for key 'maximum': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->maximum_present = 1;
        }
      }
    while (0);
    ret->affinity = make_runtime_spec_schema_config_windows_resources_cpu_affinity (get_val (tree, "affinity", yajl_t_object), ctx, err);
    if (ret->affinity == NULL && *err != 0)
      return NULL;

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
            if (strcmp (tree->u.object.keys[i], "count")
                && strcmp (tree->u.object.keys[i], "shares")
                && strcmp (tree->u.object.keys[i], "maximum")
                && strcmp (tree->u.object.keys[i], "affinity")){
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
free_runtime_spec_schema_config_windows_resources_cpu (runtime_spec_schema_config_windows_resources_cpu *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->affinity != NULL)
      {
        free_runtime_spec_schema_config_windows_resources_cpu_affinity (ptr->affinity);
        ptr->affinity = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows_resources_cpu (yajl_gen g, const runtime_spec_schema_config_windows_resources_cpu *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->count_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("count"), 5 /* strlen ("count") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->count)
            num = (long long unsigned int)ptr->count;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->shares_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("shares"), 6 /* strlen ("shares") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->shares)
            num = (long long unsigned int)ptr->shares;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->maximum_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("maximum"), 7 /* strlen ("maximum") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->maximum)
            num = (long long unsigned int)ptr->maximum;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->affinity != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("affinity"), 8 /* strlen ("affinity") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows_resources_cpu_affinity (g, ptr != NULL ? ptr->affinity : NULL, ctx, err);
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

runtime_spec_schema_config_windows_resources_cpu *
clone_runtime_spec_schema_config_windows_resources_cpu (runtime_spec_schema_config_windows_resources_cpu *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources_cpu) runtime_spec_schema_config_windows_resources_cpu *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->count = src->count;
    ret->count_present = src->count_present;
    ret->shares = src->shares;
    ret->shares_present = src->shares_present;
    ret->maximum = src->maximum;
    ret->maximum_present = src->maximum_present;
    if (src->affinity)
      {
        ret->affinity = clone_runtime_spec_schema_config_windows_resources_cpu_affinity (src->affinity);
        if (ret->affinity == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_windows_resources_storage *, free_runtime_spec_schema_config_windows_resources_storage)
runtime_spec_schema_config_windows_resources_storage *
make_runtime_spec_schema_config_windows_resources_storage (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources_storage) runtime_spec_schema_config_windows_resources_storage *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "iops", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->iops);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'iops': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->iops_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "bps", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->bps);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'bps': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->bps_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "sandboxSize", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_uint64 (YAJL_GET_NUMBER (val), &ret->sandbox_size);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'uint64' for key 'sandboxSize': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->sandbox_size_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "iops")
                && strcmp (tree->u.object.keys[i], "bps")
                && strcmp (tree->u.object.keys[i], "sandboxSize")){
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
free_runtime_spec_schema_config_windows_resources_storage (runtime_spec_schema_config_windows_resources_storage *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows_resources_storage (yajl_gen g, const runtime_spec_schema_config_windows_resources_storage *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->iops_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("iops"), 4 /* strlen ("iops") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->iops)
            num = (long long unsigned int)ptr->iops;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->bps_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("bps"), 3 /* strlen ("bps") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->bps)
            num = (long long unsigned int)ptr->bps;
        stat = map_uint (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->sandbox_size_present))
      {
        long long unsigned int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("sandboxSize"), 11 /* strlen ("sandboxSize") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->sandbox_size)
            num = (long long unsigned int)ptr->sandbox_size;
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

runtime_spec_schema_config_windows_resources_storage *
clone_runtime_spec_schema_config_windows_resources_storage (runtime_spec_schema_config_windows_resources_storage *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources_storage) runtime_spec_schema_config_windows_resources_storage *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->iops = src->iops;
    ret->iops_present = src->iops_present;
    ret->bps = src->bps;
    ret->bps_present = src->bps_present;
    ret->sandbox_size = src->sandbox_size;
    ret->sandbox_size_present = src->sandbox_size_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_windows_resources *, free_runtime_spec_schema_config_windows_resources)
runtime_spec_schema_config_windows_resources *
make_runtime_spec_schema_config_windows_resources (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources) runtime_spec_schema_config_windows_resources *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->memory = make_runtime_spec_schema_config_windows_resources_memory (get_val (tree, "memory", yajl_t_object), ctx, err);
    if (ret->memory == NULL && *err != 0)
      return NULL;
    ret->cpu = make_runtime_spec_schema_config_windows_resources_cpu (get_val (tree, "cpu", yajl_t_object), ctx, err);
    if (ret->cpu == NULL && *err != 0)
      return NULL;
    ret->storage = make_runtime_spec_schema_config_windows_resources_storage (get_val (tree, "storage", yajl_t_object), ctx, err);
    if (ret->storage == NULL && *err != 0)
      return NULL;

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
            if (strcmp (tree->u.object.keys[i], "memory")
                && strcmp (tree->u.object.keys[i], "cpu")
                && strcmp (tree->u.object.keys[i], "storage")){
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
free_runtime_spec_schema_config_windows_resources (runtime_spec_schema_config_windows_resources *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->memory != NULL)
      {
        free_runtime_spec_schema_config_windows_resources_memory (ptr->memory);
        ptr->memory = NULL;
      }
    if (ptr->cpu != NULL)
      {
        free_runtime_spec_schema_config_windows_resources_cpu (ptr->cpu);
        ptr->cpu = NULL;
      }
    if (ptr->storage != NULL)
      {
        free_runtime_spec_schema_config_windows_resources_storage (ptr->storage);
        ptr->storage = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows_resources (yajl_gen g, const runtime_spec_schema_config_windows_resources *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->memory != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("memory"), 6 /* strlen ("memory") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows_resources_memory (g, ptr != NULL ? ptr->memory : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->cpu != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("cpu"), 3 /* strlen ("cpu") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows_resources_cpu (g, ptr != NULL ? ptr->cpu : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->storage != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("storage"), 7 /* strlen ("storage") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows_resources_storage (g, ptr != NULL ? ptr->storage : NULL, ctx, err);
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

runtime_spec_schema_config_windows_resources *
clone_runtime_spec_schema_config_windows_resources (runtime_spec_schema_config_windows_resources *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows_resources) runtime_spec_schema_config_windows_resources *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->memory)
      {
        ret->memory = clone_runtime_spec_schema_config_windows_resources_memory (src->memory);
        if (ret->memory == NULL)
          return NULL;
      }
    if (src->cpu)
      {
        ret->cpu = clone_runtime_spec_schema_config_windows_resources_cpu (src->cpu);
        if (ret->cpu == NULL)
          return NULL;
      }
    if (src->storage)
      {
        ret->storage = clone_runtime_spec_schema_config_windows_resources_storage (src->storage);
        if (ret->storage == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_windows_network *, free_runtime_spec_schema_config_windows_network)
runtime_spec_schema_config_windows_network *
make_runtime_spec_schema_config_windows_network (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows_network) runtime_spec_schema_config_windows_network *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "endpointList", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->endpoint_list_len = len;
            ret->endpoint_list = calloc (len + 1, sizeof (*ret->endpoint_list));
            if (ret->endpoint_list == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->endpoint_list[i] = strdup (str ? str : "");
                    if (ret->endpoint_list[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "allowUnqualifiedDNSQuery", yajl_t_true);
        if (val != NULL)
          {
            ret->allow_unqualified_dns_query = YAJL_IS_TRUE(val);
            ret->allow_unqualified_dns_query_present = 1;
          }
        else
          {
            val = get_val (tree, "allowUnqualifiedDNSQuery", yajl_t_false);
            if (val != NULL)
              {
                ret->allow_unqualified_dns_query = 0;
                ret->allow_unqualified_dns_query_present = 1;
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "DNSSearchList", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->dns_search_list_len = len;
            ret->dns_search_list = calloc (len + 1, sizeof (*ret->dns_search_list));
            if (ret->dns_search_list == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->dns_search_list[i] = strdup (str ? str : "");
                    if (ret->dns_search_list[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "networkSharedContainerName", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->network_shared_container_name = strdup (str ? str : "");
            if (ret->network_shared_container_name == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "networkNamespace", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->network_namespace = strdup (str ? str : "");
            if (ret->network_namespace == NULL)
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
            if (strcmp (tree->u.object.keys[i], "endpointList")
                && strcmp (tree->u.object.keys[i], "allowUnqualifiedDNSQuery")
                && strcmp (tree->u.object.keys[i], "DNSSearchList")
                && strcmp (tree->u.object.keys[i], "networkSharedContainerName")
                && strcmp (tree->u.object.keys[i], "networkNamespace")){
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
free_runtime_spec_schema_config_windows_network (runtime_spec_schema_config_windows_network *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->endpoint_list != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->endpoint_list_len; i++)
          {
            if (ptr->endpoint_list[i] != NULL)
              {
                free (ptr->endpoint_list[i]);
                ptr->endpoint_list[i] = NULL;
              }
          }
        free (ptr->endpoint_list);
        ptr->endpoint_list = NULL;
    }
    if (ptr->dns_search_list != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->dns_search_list_len; i++)
          {
            if (ptr->dns_search_list[i] != NULL)
              {
                free (ptr->dns_search_list[i]);
                ptr->dns_search_list[i] = NULL;
              }
          }
        free (ptr->dns_search_list);
        ptr->dns_search_list = NULL;
    }
    free (ptr->network_shared_container_name);
    ptr->network_shared_container_name = NULL;
    free (ptr->network_namespace);
    ptr->network_namespace = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows_network (yajl_gen g, const runtime_spec_schema_config_windows_network *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->endpoint_list != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("endpointList"), 12 /* strlen ("endpointList") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->endpoint_list != NULL)
          len = ptr->endpoint_list_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->endpoint_list[i]), strlen (ptr->endpoint_list[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->allow_unqualified_dns_query_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("allowUnqualifiedDNSQuery"), 24 /* strlen ("allowUnqualifiedDNSQuery") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->allow_unqualified_dns_query)
            b = ptr->allow_unqualified_dns_query;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->dns_search_list != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("DNSSearchList"), 13 /* strlen ("DNSSearchList") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->dns_search_list != NULL)
          len = ptr->dns_search_list_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->dns_search_list[i]), strlen (ptr->dns_search_list[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->network_shared_container_name != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("networkSharedContainerName"), 26 /* strlen ("networkSharedContainerName") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->network_shared_container_name != NULL)
            str = ptr->network_shared_container_name;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->network_namespace != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("networkNamespace"), 16 /* strlen ("networkNamespace") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->network_namespace != NULL)
            str = ptr->network_namespace;
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

runtime_spec_schema_config_windows_network *
clone_runtime_spec_schema_config_windows_network (runtime_spec_schema_config_windows_network *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows_network) runtime_spec_schema_config_windows_network *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->endpoint_list)
      {
        ret->endpoint_list_len = src->endpoint_list_len;
        ret->endpoint_list = calloc (src->endpoint_list_len + 1, sizeof (*ret->endpoint_list));
        if (ret->endpoint_list == NULL)
          return NULL;
        for (size_t i = 0; i < src->endpoint_list_len; i++)
          {
            if (src->endpoint_list[i])
              {
                ret->endpoint_list[i] = strdup (src->endpoint_list[i]);
                if (ret->endpoint_list[i] == NULL)
                  return NULL;
              }
          }
      }
    ret->allow_unqualified_dns_query = src->allow_unqualified_dns_query;
    ret->allow_unqualified_dns_query_present = src->allow_unqualified_dns_query_present;
    if (src->dns_search_list)
      {
        ret->dns_search_list_len = src->dns_search_list_len;
        ret->dns_search_list = calloc (src->dns_search_list_len + 1, sizeof (*ret->dns_search_list));
        if (ret->dns_search_list == NULL)
          return NULL;
        for (size_t i = 0; i < src->dns_search_list_len; i++)
          {
            if (src->dns_search_list[i])
              {
                ret->dns_search_list[i] = strdup (src->dns_search_list[i]);
                if (ret->dns_search_list[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->network_shared_container_name)
      {
        ret->network_shared_container_name = strdup (src->network_shared_container_name);
        if (ret->network_shared_container_name == NULL)
          return NULL;
      }
    if (src->network_namespace)
      {
        ret->network_namespace = strdup (src->network_namespace);
        if (ret->network_namespace == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_windows_credential_spec *, free_runtime_spec_schema_config_windows_credential_spec)
runtime_spec_schema_config_windows_credential_spec *
make_runtime_spec_schema_config_windows_credential_spec (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows_credential_spec) runtime_spec_schema_config_windows_credential_spec *ret = NULL;
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
free_runtime_spec_schema_config_windows_credential_spec (runtime_spec_schema_config_windows_credential_spec *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows_credential_spec (yajl_gen g, const runtime_spec_schema_config_windows_credential_spec *ptr, const struct parser_context *ctx, parser_error *err)
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

runtime_spec_schema_config_windows_credential_spec *
clone_runtime_spec_schema_config_windows_credential_spec (runtime_spec_schema_config_windows_credential_spec *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows_credential_spec) runtime_spec_schema_config_windows_credential_spec *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_windows_hyperv *, free_runtime_spec_schema_config_windows_hyperv)
runtime_spec_schema_config_windows_hyperv *
make_runtime_spec_schema_config_windows_hyperv (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows_hyperv) runtime_spec_schema_config_windows_hyperv *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "utilityVMPath", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->utility_vm_path = strdup (str ? str : "");
            if (ret->utility_vm_path == NULL)
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
            if (strcmp (tree->u.object.keys[i], "utilityVMPath")){
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
free_runtime_spec_schema_config_windows_hyperv (runtime_spec_schema_config_windows_hyperv *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->utility_vm_path);
    ptr->utility_vm_path = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows_hyperv (yajl_gen g, const runtime_spec_schema_config_windows_hyperv *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->utility_vm_path != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("utilityVMPath"), 13 /* strlen ("utilityVMPath") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->utility_vm_path != NULL)
            str = ptr->utility_vm_path;
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

runtime_spec_schema_config_windows_hyperv *
clone_runtime_spec_schema_config_windows_hyperv (runtime_spec_schema_config_windows_hyperv *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows_hyperv) runtime_spec_schema_config_windows_hyperv *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->utility_vm_path)
      {
        ret->utility_vm_path = strdup (src->utility_vm_path);
        if (ret->utility_vm_path == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_windows *, free_runtime_spec_schema_config_windows)
runtime_spec_schema_config_windows *
make_runtime_spec_schema_config_windows (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_windows) runtime_spec_schema_config_windows *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "layerFolders", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->layer_folders_len = len;
            ret->layer_folders = calloc (len + 1, sizeof (*ret->layer_folders));
            if (ret->layer_folders == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->layer_folders[i] = strdup (str ? str : "");
                    if (ret->layer_folders[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "devices", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->devices_len = len;
            ret->devices = calloc (len + 1, sizeof (*ret->devices));
            if (ret->devices == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->devices[i] = make_runtime_spec_schema_defs_windows_device (val, ctx, err);
                if (ret->devices[i] == NULL)
                  return NULL;
              }
          }
      }
    while (0);
    ret->resources = make_runtime_spec_schema_config_windows_resources (get_val (tree, "resources", yajl_t_object), ctx, err);
    if (ret->resources == NULL && *err != 0)
      return NULL;
    ret->network = make_runtime_spec_schema_config_windows_network (get_val (tree, "network", yajl_t_object), ctx, err);
    if (ret->network == NULL && *err != 0)
      return NULL;
    ret->credential_spec = make_runtime_spec_schema_config_windows_credential_spec (get_val (tree, "credentialSpec", yajl_t_object), ctx, err);
    if (ret->credential_spec == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "servicing", yajl_t_true);
        if (val != NULL)
          {
            ret->servicing = YAJL_IS_TRUE(val);
            ret->servicing_present = 1;
          }
        else
          {
            val = get_val (tree, "servicing", yajl_t_false);
            if (val != NULL)
              {
                ret->servicing = 0;
                ret->servicing_present = 1;
              }
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "ignoreFlushesDuringBoot", yajl_t_true);
        if (val != NULL)
          {
            ret->ignore_flushes_during_boot = YAJL_IS_TRUE(val);
            ret->ignore_flushes_during_boot_present = 1;
          }
        else
          {
            val = get_val (tree, "ignoreFlushesDuringBoot", yajl_t_false);
            if (val != NULL)
              {
                ret->ignore_flushes_during_boot = 0;
                ret->ignore_flushes_during_boot_present = 1;
              }
          }
      }
    while (0);
    ret->hyperv = make_runtime_spec_schema_config_windows_hyperv (get_val (tree, "hyperv", yajl_t_object), ctx, err);
    if (ret->hyperv == NULL && *err != 0)
      return NULL;
    if (ret->layer_folders == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "layerFolders") < 0)
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
            if (strcmp (tree->u.object.keys[i], "layerFolders")
                && strcmp (tree->u.object.keys[i], "devices")
                && strcmp (tree->u.object.keys[i], "resources")
                && strcmp (tree->u.object.keys[i], "network")
                && strcmp (tree->u.object.keys[i], "credentialSpec")
                && strcmp (tree->u.object.keys[i], "servicing")
                && strcmp (tree->u.object.keys[i], "ignoreFlushesDuringBoot")
                && strcmp (tree->u.object.keys[i], "hyperv")){
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
free_runtime_spec_schema_config_windows (runtime_spec_schema_config_windows *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->layer_folders != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->layer_folders_len; i++)
          {
            if (ptr->layer_folders[i] != NULL)
              {
                free (ptr->layer_folders[i]);
                ptr->layer_folders[i] = NULL;
              }
          }
        free (ptr->layer_folders);
        ptr->layer_folders = NULL;
    }
    if (ptr->devices != NULL)      {
        size_t i;
        for (i = 0; i < ptr->devices_len; i++)
          {
          if (ptr->devices[i] != NULL)
            {
              free_runtime_spec_schema_defs_windows_device (ptr->devices[i]);
              ptr->devices[i] = NULL;
            }
          }
        free (ptr->devices);
        ptr->devices = NULL;
      }
    if (ptr->resources != NULL)
      {
        free_runtime_spec_schema_config_windows_resources (ptr->resources);
        ptr->resources = NULL;
      }
    if (ptr->network != NULL)
      {
        free_runtime_spec_schema_config_windows_network (ptr->network);
        ptr->network = NULL;
      }
    if (ptr->credential_spec != NULL)
      {
        free_runtime_spec_schema_config_windows_credential_spec (ptr->credential_spec);
        ptr->credential_spec = NULL;
      }
    if (ptr->hyperv != NULL)
      {
        free_runtime_spec_schema_config_windows_hyperv (ptr->hyperv);
        ptr->hyperv = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_windows (yajl_gen g, const runtime_spec_schema_config_windows *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->layer_folders != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("layerFolders"), 12 /* strlen ("layerFolders") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->layer_folders != NULL)
          len = ptr->layer_folders_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->layer_folders[i]), strlen (ptr->layer_folders[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->devices != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("devices"), 7 /* strlen ("devices") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->devices != NULL)
            len = ptr->devices_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_defs_windows_device (g, ptr->devices[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->resources != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("resources"), 9 /* strlen ("resources") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows_resources (g, ptr != NULL ? ptr->resources : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->network != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("network"), 7 /* strlen ("network") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows_network (g, ptr != NULL ? ptr->network : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->credential_spec != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("credentialSpec"), 14 /* strlen ("credentialSpec") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows_credential_spec (g, ptr != NULL ? ptr->credential_spec : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->servicing_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("servicing"), 9 /* strlen ("servicing") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->servicing)
            b = ptr->servicing;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->ignore_flushes_during_boot_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ignoreFlushesDuringBoot"), 23 /* strlen ("ignoreFlushesDuringBoot") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->ignore_flushes_during_boot)
            b = ptr->ignore_flushes_during_boot;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->hyperv != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hyperv"), 6 /* strlen ("hyperv") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_windows_hyperv (g, ptr != NULL ? ptr->hyperv : NULL, ctx, err);
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

runtime_spec_schema_config_windows *
clone_runtime_spec_schema_config_windows (runtime_spec_schema_config_windows *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_windows) runtime_spec_schema_config_windows *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->layer_folders)
      {
        ret->layer_folders_len = src->layer_folders_len;
        ret->layer_folders = calloc (src->layer_folders_len + 1, sizeof (*ret->layer_folders));
        if (ret->layer_folders == NULL)
          return NULL;
        for (size_t i = 0; i < src->layer_folders_len; i++)
          {
            if (src->layer_folders[i])
              {
                ret->layer_folders[i] = strdup (src->layer_folders[i]);
                if (ret->layer_folders[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->devices)
      {
        ret->devices_len = src->devices_len;
        ret->devices = calloc (src->devices_len + 1, sizeof (*ret->devices));
        if (ret->devices == NULL)
          return NULL;
        for (size_t i = 0; i < src->devices_len; i++)
          {
            ret->devices[i] = clone_runtime_spec_schema_defs_windows_device (src->devices[i]);
            if (ret->devices[i] == NULL)
                return NULL;
          }
      }
    if (src->resources)
      {
        ret->resources = clone_runtime_spec_schema_config_windows_resources (src->resources);
        if (ret->resources == NULL)
          return NULL;
      }
    if (src->network)
      {
        ret->network = clone_runtime_spec_schema_config_windows_network (src->network);
        if (ret->network == NULL)
          return NULL;
      }
    if (src->credential_spec)
      {
        ret->credential_spec = clone_runtime_spec_schema_config_windows_credential_spec (src->credential_spec);
        if (ret->credential_spec == NULL)
          return NULL;
      }
    ret->servicing = src->servicing;
    ret->servicing_present = src->servicing_present;
    ret->ignore_flushes_during_boot = src->ignore_flushes_during_boot;
    ret->ignore_flushes_during_boot_present = src->ignore_flushes_during_boot_present;
    if (src->hyperv)
      {
        ret->hyperv = clone_runtime_spec_schema_config_windows_hyperv (src->hyperv);
        if (ret->hyperv == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

