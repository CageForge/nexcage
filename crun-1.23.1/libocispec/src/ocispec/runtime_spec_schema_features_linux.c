/* Generated from features-linux.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_features_linux.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_features_linux_cgroup *, free_runtime_spec_schema_features_linux_cgroup)
runtime_spec_schema_features_linux_cgroup *
make_runtime_spec_schema_features_linux_cgroup (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux_cgroup) runtime_spec_schema_features_linux_cgroup *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "v1", yajl_t_true);
        if (val != NULL)
          {
            ret->v1 = YAJL_IS_TRUE(val);
            ret->v1_present = 1;
          }
        else
          {
            val = get_val (tree, "v1", yajl_t_false);
            if (val != NULL)
              {
                ret->v1 = 0;
                ret->v1_present = 1;
              }
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "v2", yajl_t_true);
        if (val != NULL)
          {
            ret->v2 = YAJL_IS_TRUE(val);
            ret->v2_present = 1;
          }
        else
          {
            val = get_val (tree, "v2", yajl_t_false);
            if (val != NULL)
              {
                ret->v2 = 0;
                ret->v2_present = 1;
              }
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "systemd", yajl_t_true);
        if (val != NULL)
          {
            ret->systemd = YAJL_IS_TRUE(val);
            ret->systemd_present = 1;
          }
        else
          {
            val = get_val (tree, "systemd", yajl_t_false);
            if (val != NULL)
              {
                ret->systemd = 0;
                ret->systemd_present = 1;
              }
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "systemdUser", yajl_t_true);
        if (val != NULL)
          {
            ret->systemd_user = YAJL_IS_TRUE(val);
            ret->systemd_user_present = 1;
          }
        else
          {
            val = get_val (tree, "systemdUser", yajl_t_false);
            if (val != NULL)
              {
                ret->systemd_user = 0;
                ret->systemd_user_present = 1;
              }
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "rdma", yajl_t_true);
        if (val != NULL)
          {
            ret->rdma = YAJL_IS_TRUE(val);
            ret->rdma_present = 1;
          }
        else
          {
            val = get_val (tree, "rdma", yajl_t_false);
            if (val != NULL)
              {
                ret->rdma = 0;
                ret->rdma_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "v1")
                && strcmp (tree->u.object.keys[i], "v2")
                && strcmp (tree->u.object.keys[i], "systemd")
                && strcmp (tree->u.object.keys[i], "systemdUser")
                && strcmp (tree->u.object.keys[i], "rdma")){
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
free_runtime_spec_schema_features_linux_cgroup (runtime_spec_schema_features_linux_cgroup *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux_cgroup (yajl_gen g, const runtime_spec_schema_features_linux_cgroup *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->v1_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("v1"), 2 /* strlen ("v1") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->v1)
            b = ptr->v1;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->v2_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("v2"), 2 /* strlen ("v2") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->v2)
            b = ptr->v2;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->systemd_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("systemd"), 7 /* strlen ("systemd") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->systemd)
            b = ptr->systemd;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->systemd_user_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("systemdUser"), 11 /* strlen ("systemdUser") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->systemd_user)
            b = ptr->systemd_user;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->rdma_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("rdma"), 4 /* strlen ("rdma") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->rdma)
            b = ptr->rdma;
        
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

runtime_spec_schema_features_linux_cgroup *
clone_runtime_spec_schema_features_linux_cgroup (runtime_spec_schema_features_linux_cgroup *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux_cgroup) runtime_spec_schema_features_linux_cgroup *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->v1 = src->v1;
    ret->v1_present = src->v1_present;
    ret->v2 = src->v2;
    ret->v2_present = src->v2_present;
    ret->systemd = src->systemd;
    ret->systemd_present = src->systemd_present;
    ret->systemd_user = src->systemd_user;
    ret->systemd_user_present = src->systemd_user_present;
    ret->rdma = src->rdma;
    ret->rdma_present = src->rdma_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_features_linux_seccomp *, free_runtime_spec_schema_features_linux_seccomp)
runtime_spec_schema_features_linux_seccomp *
make_runtime_spec_schema_features_linux_seccomp (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux_seccomp) runtime_spec_schema_features_linux_seccomp *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "enabled", yajl_t_true);
        if (val != NULL)
          {
            ret->enabled = YAJL_IS_TRUE(val);
            ret->enabled_present = 1;
          }
        else
          {
            val = get_val (tree, "enabled", yajl_t_false);
            if (val != NULL)
              {
                ret->enabled = 0;
                ret->enabled_present = 1;
              }
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "actions", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->actions_len = len;
            ret->actions = calloc (len + 1, sizeof (*ret->actions));
            if (ret->actions == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->actions[i] = strdup (str ? str : "");
                    if (ret->actions[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "operators", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->operators_len = len;
            ret->operators = calloc (len + 1, sizeof (*ret->operators));
            if (ret->operators == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->operators[i] = strdup (str ? str : "");
                    if (ret->operators[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "archs", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->archs_len = len;
            ret->archs = calloc (len + 1, sizeof (*ret->archs));
            if (ret->archs == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->archs[i] = strdup (str ? str : "");
                    if (ret->archs[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "knownFlags", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->known_flags_len = len;
            ret->known_flags = calloc (len + 1, sizeof (*ret->known_flags));
            if (ret->known_flags == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->known_flags[i] = strdup (str ? str : "");
                    if (ret->known_flags[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "supportedFlags", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->supported_flags_len = len;
            ret->supported_flags = calloc (len + 1, sizeof (*ret->supported_flags));
            if (ret->supported_flags == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->supported_flags[i] = strdup (str ? str : "");
                    if (ret->supported_flags[i] == NULL)
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
            if (strcmp (tree->u.object.keys[i], "enabled")
                && strcmp (tree->u.object.keys[i], "actions")
                && strcmp (tree->u.object.keys[i], "operators")
                && strcmp (tree->u.object.keys[i], "archs")
                && strcmp (tree->u.object.keys[i], "knownFlags")
                && strcmp (tree->u.object.keys[i], "supportedFlags")){
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
free_runtime_spec_schema_features_linux_seccomp (runtime_spec_schema_features_linux_seccomp *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->actions != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->actions_len; i++)
          {
            if (ptr->actions[i] != NULL)
              {
                free (ptr->actions[i]);
                ptr->actions[i] = NULL;
              }
          }
        free (ptr->actions);
        ptr->actions = NULL;
    }
    if (ptr->operators != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->operators_len; i++)
          {
            if (ptr->operators[i] != NULL)
              {
                free (ptr->operators[i]);
                ptr->operators[i] = NULL;
              }
          }
        free (ptr->operators);
        ptr->operators = NULL;
    }
    if (ptr->archs != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->archs_len; i++)
          {
            if (ptr->archs[i] != NULL)
              {
                free (ptr->archs[i]);
                ptr->archs[i] = NULL;
              }
          }
        free (ptr->archs);
        ptr->archs = NULL;
    }
    if (ptr->known_flags != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->known_flags_len; i++)
          {
            if (ptr->known_flags[i] != NULL)
              {
                free (ptr->known_flags[i]);
                ptr->known_flags[i] = NULL;
              }
          }
        free (ptr->known_flags);
        ptr->known_flags = NULL;
    }
    if (ptr->supported_flags != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->supported_flags_len; i++)
          {
            if (ptr->supported_flags[i] != NULL)
              {
                free (ptr->supported_flags[i]);
                ptr->supported_flags[i] = NULL;
              }
          }
        free (ptr->supported_flags);
        ptr->supported_flags = NULL;
    }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux_seccomp (yajl_gen g, const runtime_spec_schema_features_linux_seccomp *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->enabled_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("enabled"), 7 /* strlen ("enabled") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->enabled)
            b = ptr->enabled;
        
        stat = yajl_gen_bool ((yajl_gen)g, (int)(b));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->actions != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("actions"), 7 /* strlen ("actions") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->actions != NULL)
          len = ptr->actions_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->actions[i]), strlen (ptr->actions[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->operators != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("operators"), 9 /* strlen ("operators") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->operators != NULL)
          len = ptr->operators_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->operators[i]), strlen (ptr->operators[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->archs != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("archs"), 5 /* strlen ("archs") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->archs != NULL)
          len = ptr->archs_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->archs[i]), strlen (ptr->archs[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->known_flags != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("knownFlags"), 10 /* strlen ("knownFlags") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->known_flags != NULL)
          len = ptr->known_flags_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->known_flags[i]), strlen (ptr->known_flags[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->supported_flags != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("supportedFlags"), 14 /* strlen ("supportedFlags") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->supported_flags != NULL)
          len = ptr->supported_flags_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->supported_flags[i]), strlen (ptr->supported_flags[i]));
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

runtime_spec_schema_features_linux_seccomp *
clone_runtime_spec_schema_features_linux_seccomp (runtime_spec_schema_features_linux_seccomp *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux_seccomp) runtime_spec_schema_features_linux_seccomp *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->enabled = src->enabled;
    ret->enabled_present = src->enabled_present;
    if (src->actions)
      {
        ret->actions_len = src->actions_len;
        ret->actions = calloc (src->actions_len + 1, sizeof (*ret->actions));
        if (ret->actions == NULL)
          return NULL;
        for (size_t i = 0; i < src->actions_len; i++)
          {
            if (src->actions[i])
              {
                ret->actions[i] = strdup (src->actions[i]);
                if (ret->actions[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->operators)
      {
        ret->operators_len = src->operators_len;
        ret->operators = calloc (src->operators_len + 1, sizeof (*ret->operators));
        if (ret->operators == NULL)
          return NULL;
        for (size_t i = 0; i < src->operators_len; i++)
          {
            if (src->operators[i])
              {
                ret->operators[i] = strdup (src->operators[i]);
                if (ret->operators[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->archs)
      {
        ret->archs_len = src->archs_len;
        ret->archs = calloc (src->archs_len + 1, sizeof (*ret->archs));
        if (ret->archs == NULL)
          return NULL;
        for (size_t i = 0; i < src->archs_len; i++)
          {
            if (src->archs[i])
              {
                ret->archs[i] = strdup (src->archs[i]);
                if (ret->archs[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->known_flags)
      {
        ret->known_flags_len = src->known_flags_len;
        ret->known_flags = calloc (src->known_flags_len + 1, sizeof (*ret->known_flags));
        if (ret->known_flags == NULL)
          return NULL;
        for (size_t i = 0; i < src->known_flags_len; i++)
          {
            if (src->known_flags[i])
              {
                ret->known_flags[i] = strdup (src->known_flags[i]);
                if (ret->known_flags[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->supported_flags)
      {
        ret->supported_flags_len = src->supported_flags_len;
        ret->supported_flags = calloc (src->supported_flags_len + 1, sizeof (*ret->supported_flags));
        if (ret->supported_flags == NULL)
          return NULL;
        for (size_t i = 0; i < src->supported_flags_len; i++)
          {
            if (src->supported_flags[i])
              {
                ret->supported_flags[i] = strdup (src->supported_flags[i]);
                if (ret->supported_flags[i] == NULL)
                  return NULL;
              }
          }
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_features_linux_apparmor *, free_runtime_spec_schema_features_linux_apparmor)
runtime_spec_schema_features_linux_apparmor *
make_runtime_spec_schema_features_linux_apparmor (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux_apparmor) runtime_spec_schema_features_linux_apparmor *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "enabled", yajl_t_true);
        if (val != NULL)
          {
            ret->enabled = YAJL_IS_TRUE(val);
            ret->enabled_present = 1;
          }
        else
          {
            val = get_val (tree, "enabled", yajl_t_false);
            if (val != NULL)
              {
                ret->enabled = 0;
                ret->enabled_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "enabled")){
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
free_runtime_spec_schema_features_linux_apparmor (runtime_spec_schema_features_linux_apparmor *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux_apparmor (yajl_gen g, const runtime_spec_schema_features_linux_apparmor *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->enabled_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("enabled"), 7 /* strlen ("enabled") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->enabled)
            b = ptr->enabled;
        
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

runtime_spec_schema_features_linux_apparmor *
clone_runtime_spec_schema_features_linux_apparmor (runtime_spec_schema_features_linux_apparmor *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux_apparmor) runtime_spec_schema_features_linux_apparmor *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->enabled = src->enabled;
    ret->enabled_present = src->enabled_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_features_linux_selinux *, free_runtime_spec_schema_features_linux_selinux)
runtime_spec_schema_features_linux_selinux *
make_runtime_spec_schema_features_linux_selinux (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux_selinux) runtime_spec_schema_features_linux_selinux *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "enabled", yajl_t_true);
        if (val != NULL)
          {
            ret->enabled = YAJL_IS_TRUE(val);
            ret->enabled_present = 1;
          }
        else
          {
            val = get_val (tree, "enabled", yajl_t_false);
            if (val != NULL)
              {
                ret->enabled = 0;
                ret->enabled_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "enabled")){
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
free_runtime_spec_schema_features_linux_selinux (runtime_spec_schema_features_linux_selinux *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux_selinux (yajl_gen g, const runtime_spec_schema_features_linux_selinux *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->enabled_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("enabled"), 7 /* strlen ("enabled") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->enabled)
            b = ptr->enabled;
        
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

runtime_spec_schema_features_linux_selinux *
clone_runtime_spec_schema_features_linux_selinux (runtime_spec_schema_features_linux_selinux *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux_selinux) runtime_spec_schema_features_linux_selinux *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->enabled = src->enabled;
    ret->enabled_present = src->enabled_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_features_linux_intel_rdt *, free_runtime_spec_schema_features_linux_intel_rdt)
runtime_spec_schema_features_linux_intel_rdt *
make_runtime_spec_schema_features_linux_intel_rdt (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux_intel_rdt) runtime_spec_schema_features_linux_intel_rdt *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "enabled", yajl_t_true);
        if (val != NULL)
          {
            ret->enabled = YAJL_IS_TRUE(val);
            ret->enabled_present = 1;
          }
        else
          {
            val = get_val (tree, "enabled", yajl_t_false);
            if (val != NULL)
              {
                ret->enabled = 0;
                ret->enabled_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "enabled")){
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
free_runtime_spec_schema_features_linux_intel_rdt (runtime_spec_schema_features_linux_intel_rdt *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux_intel_rdt (yajl_gen g, const runtime_spec_schema_features_linux_intel_rdt *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->enabled_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("enabled"), 7 /* strlen ("enabled") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->enabled)
            b = ptr->enabled;
        
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

runtime_spec_schema_features_linux_intel_rdt *
clone_runtime_spec_schema_features_linux_intel_rdt (runtime_spec_schema_features_linux_intel_rdt *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux_intel_rdt) runtime_spec_schema_features_linux_intel_rdt *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->enabled = src->enabled;
    ret->enabled_present = src->enabled_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_features_linux_mount_extensions_idmap *, free_runtime_spec_schema_features_linux_mount_extensions_idmap)
runtime_spec_schema_features_linux_mount_extensions_idmap *
make_runtime_spec_schema_features_linux_mount_extensions_idmap (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux_mount_extensions_idmap) runtime_spec_schema_features_linux_mount_extensions_idmap *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "enabled", yajl_t_true);
        if (val != NULL)
          {
            ret->enabled = YAJL_IS_TRUE(val);
            ret->enabled_present = 1;
          }
        else
          {
            val = get_val (tree, "enabled", yajl_t_false);
            if (val != NULL)
              {
                ret->enabled = 0;
                ret->enabled_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "enabled")){
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
free_runtime_spec_schema_features_linux_mount_extensions_idmap (runtime_spec_schema_features_linux_mount_extensions_idmap *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux_mount_extensions_idmap (yajl_gen g, const runtime_spec_schema_features_linux_mount_extensions_idmap *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->enabled_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("enabled"), 7 /* strlen ("enabled") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->enabled)
            b = ptr->enabled;
        
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

runtime_spec_schema_features_linux_mount_extensions_idmap *
clone_runtime_spec_schema_features_linux_mount_extensions_idmap (runtime_spec_schema_features_linux_mount_extensions_idmap *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux_mount_extensions_idmap) runtime_spec_schema_features_linux_mount_extensions_idmap *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->enabled = src->enabled;
    ret->enabled_present = src->enabled_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_features_linux_mount_extensions *, free_runtime_spec_schema_features_linux_mount_extensions)
runtime_spec_schema_features_linux_mount_extensions *
make_runtime_spec_schema_features_linux_mount_extensions (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux_mount_extensions) runtime_spec_schema_features_linux_mount_extensions *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->idmap = make_runtime_spec_schema_features_linux_mount_extensions_idmap (get_val (tree, "idmap", yajl_t_object), ctx, err);
    if (ret->idmap == NULL && *err != 0)
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
            if (strcmp (tree->u.object.keys[i], "idmap")){
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
free_runtime_spec_schema_features_linux_mount_extensions (runtime_spec_schema_features_linux_mount_extensions *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->idmap != NULL)
      {
        free_runtime_spec_schema_features_linux_mount_extensions_idmap (ptr->idmap);
        ptr->idmap = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux_mount_extensions (yajl_gen g, const runtime_spec_schema_features_linux_mount_extensions *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->idmap != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("idmap"), 5 /* strlen ("idmap") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux_mount_extensions_idmap (g, ptr != NULL ? ptr->idmap : NULL, ctx, err);
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

runtime_spec_schema_features_linux_mount_extensions *
clone_runtime_spec_schema_features_linux_mount_extensions (runtime_spec_schema_features_linux_mount_extensions *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux_mount_extensions) runtime_spec_schema_features_linux_mount_extensions *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->idmap)
      {
        ret->idmap = clone_runtime_spec_schema_features_linux_mount_extensions_idmap (src->idmap);
        if (ret->idmap == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_features_linux_net_devices *, free_runtime_spec_schema_features_linux_net_devices)
runtime_spec_schema_features_linux_net_devices *
make_runtime_spec_schema_features_linux_net_devices (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux_net_devices) runtime_spec_schema_features_linux_net_devices *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "enabled", yajl_t_true);
        if (val != NULL)
          {
            ret->enabled = YAJL_IS_TRUE(val);
            ret->enabled_present = 1;
          }
        else
          {
            val = get_val (tree, "enabled", yajl_t_false);
            if (val != NULL)
              {
                ret->enabled = 0;
                ret->enabled_present = 1;
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
            if (strcmp (tree->u.object.keys[i], "enabled")){
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
free_runtime_spec_schema_features_linux_net_devices (runtime_spec_schema_features_linux_net_devices *ptr)
{
    if (ptr == NULL)
        return;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux_net_devices (yajl_gen g, const runtime_spec_schema_features_linux_net_devices *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->enabled_present))
      {
        bool b = false;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("enabled"), 7 /* strlen ("enabled") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->enabled)
            b = ptr->enabled;
        
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

runtime_spec_schema_features_linux_net_devices *
clone_runtime_spec_schema_features_linux_net_devices (runtime_spec_schema_features_linux_net_devices *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux_net_devices) runtime_spec_schema_features_linux_net_devices *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->enabled = src->enabled;
    ret->enabled_present = src->enabled_present;
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_features_linux *, free_runtime_spec_schema_features_linux)
runtime_spec_schema_features_linux *
make_runtime_spec_schema_features_linux (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_linux) runtime_spec_schema_features_linux *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "namespaces", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->namespaces_len = len;
            ret->namespaces = calloc (len + 1, sizeof (*ret->namespaces));
            if (ret->namespaces == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->namespaces[i] = strdup (str ? str : "");
                    if (ret->namespaces[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "capabilities", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->capabilities_len = len;
            ret->capabilities = calloc (len + 1, sizeof (*ret->capabilities));
            if (ret->capabilities == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->capabilities[i] = strdup (str ? str : "");
                    if (ret->capabilities[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    ret->cgroup = make_runtime_spec_schema_features_linux_cgroup (get_val (tree, "cgroup", yajl_t_object), ctx, err);
    if (ret->cgroup == NULL && *err != 0)
      return NULL;
    ret->seccomp = make_runtime_spec_schema_features_linux_seccomp (get_val (tree, "seccomp", yajl_t_object), ctx, err);
    if (ret->seccomp == NULL && *err != 0)
      return NULL;
    ret->apparmor = make_runtime_spec_schema_features_linux_apparmor (get_val (tree, "apparmor", yajl_t_object), ctx, err);
    if (ret->apparmor == NULL && *err != 0)
      return NULL;
    ret->selinux = make_runtime_spec_schema_features_linux_selinux (get_val (tree, "selinux", yajl_t_object), ctx, err);
    if (ret->selinux == NULL && *err != 0)
      return NULL;
    ret->intel_rdt = make_runtime_spec_schema_features_linux_intel_rdt (get_val (tree, "intelRdt", yajl_t_object), ctx, err);
    if (ret->intel_rdt == NULL && *err != 0)
      return NULL;
    ret->mount_extensions = make_runtime_spec_schema_features_linux_mount_extensions (get_val (tree, "mountExtensions", yajl_t_object), ctx, err);
    if (ret->mount_extensions == NULL && *err != 0)
      return NULL;
    ret->net_devices = make_runtime_spec_schema_features_linux_net_devices (get_val (tree, "netDevices", yajl_t_object), ctx, err);
    if (ret->net_devices == NULL && *err != 0)
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
            if (strcmp (tree->u.object.keys[i], "namespaces")
                && strcmp (tree->u.object.keys[i], "capabilities")
                && strcmp (tree->u.object.keys[i], "cgroup")
                && strcmp (tree->u.object.keys[i], "seccomp")
                && strcmp (tree->u.object.keys[i], "apparmor")
                && strcmp (tree->u.object.keys[i], "selinux")
                && strcmp (tree->u.object.keys[i], "intelRdt")
                && strcmp (tree->u.object.keys[i], "mountExtensions")
                && strcmp (tree->u.object.keys[i], "netDevices")){
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
free_runtime_spec_schema_features_linux (runtime_spec_schema_features_linux *ptr)
{
    if (ptr == NULL)
        return;
    if (ptr->namespaces != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->namespaces_len; i++)
          {
            if (ptr->namespaces[i] != NULL)
              {
                free (ptr->namespaces[i]);
                ptr->namespaces[i] = NULL;
              }
          }
        free (ptr->namespaces);
        ptr->namespaces = NULL;
    }
    if (ptr->capabilities != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->capabilities_len; i++)
          {
            if (ptr->capabilities[i] != NULL)
              {
                free (ptr->capabilities[i]);
                ptr->capabilities[i] = NULL;
              }
          }
        free (ptr->capabilities);
        ptr->capabilities = NULL;
    }
    if (ptr->cgroup != NULL)
      {
        free_runtime_spec_schema_features_linux_cgroup (ptr->cgroup);
        ptr->cgroup = NULL;
      }
    if (ptr->seccomp != NULL)
      {
        free_runtime_spec_schema_features_linux_seccomp (ptr->seccomp);
        ptr->seccomp = NULL;
      }
    if (ptr->apparmor != NULL)
      {
        free_runtime_spec_schema_features_linux_apparmor (ptr->apparmor);
        ptr->apparmor = NULL;
      }
    if (ptr->selinux != NULL)
      {
        free_runtime_spec_schema_features_linux_selinux (ptr->selinux);
        ptr->selinux = NULL;
      }
    if (ptr->intel_rdt != NULL)
      {
        free_runtime_spec_schema_features_linux_intel_rdt (ptr->intel_rdt);
        ptr->intel_rdt = NULL;
      }
    if (ptr->mount_extensions != NULL)
      {
        free_runtime_spec_schema_features_linux_mount_extensions (ptr->mount_extensions);
        ptr->mount_extensions = NULL;
      }
    if (ptr->net_devices != NULL)
      {
        free_runtime_spec_schema_features_linux_net_devices (ptr->net_devices);
        ptr->net_devices = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_linux (yajl_gen g, const runtime_spec_schema_features_linux *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->namespaces != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("namespaces"), 10 /* strlen ("namespaces") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->namespaces != NULL)
          len = ptr->namespaces_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->namespaces[i]), strlen (ptr->namespaces[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->capabilities != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("capabilities"), 12 /* strlen ("capabilities") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->capabilities != NULL)
          len = ptr->capabilities_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->capabilities[i]), strlen (ptr->capabilities[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->cgroup != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("cgroup"), 6 /* strlen ("cgroup") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux_cgroup (g, ptr != NULL ? ptr->cgroup : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->seccomp != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("seccomp"), 7 /* strlen ("seccomp") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux_seccomp (g, ptr != NULL ? ptr->seccomp : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->apparmor != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("apparmor"), 8 /* strlen ("apparmor") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux_apparmor (g, ptr != NULL ? ptr->apparmor : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->selinux != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("selinux"), 7 /* strlen ("selinux") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux_selinux (g, ptr != NULL ? ptr->selinux : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->intel_rdt != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("intelRdt"), 8 /* strlen ("intelRdt") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux_intel_rdt (g, ptr != NULL ? ptr->intel_rdt : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->mount_extensions != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("mountExtensions"), 15 /* strlen ("mountExtensions") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux_mount_extensions (g, ptr != NULL ? ptr->mount_extensions : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->net_devices != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("netDevices"), 10 /* strlen ("netDevices") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux_net_devices (g, ptr != NULL ? ptr->net_devices : NULL, ctx, err);
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

runtime_spec_schema_features_linux *
clone_runtime_spec_schema_features_linux (runtime_spec_schema_features_linux *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_linux) runtime_spec_schema_features_linux *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->namespaces)
      {
        ret->namespaces_len = src->namespaces_len;
        ret->namespaces = calloc (src->namespaces_len + 1, sizeof (*ret->namespaces));
        if (ret->namespaces == NULL)
          return NULL;
        for (size_t i = 0; i < src->namespaces_len; i++)
          {
            if (src->namespaces[i])
              {
                ret->namespaces[i] = strdup (src->namespaces[i]);
                if (ret->namespaces[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->capabilities)
      {
        ret->capabilities_len = src->capabilities_len;
        ret->capabilities = calloc (src->capabilities_len + 1, sizeof (*ret->capabilities));
        if (ret->capabilities == NULL)
          return NULL;
        for (size_t i = 0; i < src->capabilities_len; i++)
          {
            if (src->capabilities[i])
              {
                ret->capabilities[i] = strdup (src->capabilities[i]);
                if (ret->capabilities[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->cgroup)
      {
        ret->cgroup = clone_runtime_spec_schema_features_linux_cgroup (src->cgroup);
        if (ret->cgroup == NULL)
          return NULL;
      }
    if (src->seccomp)
      {
        ret->seccomp = clone_runtime_spec_schema_features_linux_seccomp (src->seccomp);
        if (ret->seccomp == NULL)
          return NULL;
      }
    if (src->apparmor)
      {
        ret->apparmor = clone_runtime_spec_schema_features_linux_apparmor (src->apparmor);
        if (ret->apparmor == NULL)
          return NULL;
      }
    if (src->selinux)
      {
        ret->selinux = clone_runtime_spec_schema_features_linux_selinux (src->selinux);
        if (ret->selinux == NULL)
          return NULL;
      }
    if (src->intel_rdt)
      {
        ret->intel_rdt = clone_runtime_spec_schema_features_linux_intel_rdt (src->intel_rdt);
        if (ret->intel_rdt == NULL)
          return NULL;
      }
    if (src->mount_extensions)
      {
        ret->mount_extensions = clone_runtime_spec_schema_features_linux_mount_extensions (src->mount_extensions);
        if (ret->mount_extensions == NULL)
          return NULL;
      }
    if (src->net_devices)
      {
        ret->net_devices = clone_runtime_spec_schema_features_linux_net_devices (src->net_devices);
        if (ret->net_devices == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

