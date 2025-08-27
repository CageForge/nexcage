/* Generated from features-schema.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_features_schema.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_features_schema *, free_runtime_spec_schema_features_schema)
runtime_spec_schema_features_schema *
make_runtime_spec_schema_features_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_features_schema) runtime_spec_schema_features_schema *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "ociVersionMin", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->oci_version_min = strdup (str ? str : "");
            if (ret->oci_version_min == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "ociVersionMax", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->oci_version_max = strdup (str ? str : "");
            if (ret->oci_version_max == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "hooks", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->hooks_len = len;
            ret->hooks = calloc (len + 1, sizeof (*ret->hooks));
            if (ret->hooks == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->hooks[i] = strdup (str ? str : "");
                    if (ret->hooks[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "mountOptions", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->mount_options_len = len;
            ret->mount_options = calloc (len + 1, sizeof (*ret->mount_options));
            if (ret->mount_options == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->mount_options[i] = strdup (str ? str : "");
                    if (ret->mount_options[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
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
        yajl_val tmp = get_val (tree, "potentiallyUnsafeConfigAnnotations", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->potentially_unsafe_config_annotations_len = len;
            ret->potentially_unsafe_config_annotations = calloc (len + 1, sizeof (*ret->potentially_unsafe_config_annotations));
            if (ret->potentially_unsafe_config_annotations == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->potentially_unsafe_config_annotations[i] = strdup (str ? str : "");
                    if (ret->potentially_unsafe_config_annotations[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    ret->linux = make_runtime_spec_schema_features_linux (get_val (tree, "linux", yajl_t_object), ctx, err);
    if (ret->linux == NULL && *err != 0)
      return NULL;
    if (ret->oci_version_min == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "ociVersionMin") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->oci_version_max == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "ociVersionMax") < 0)
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
            if (strcmp (tree->u.object.keys[i], "ociVersionMin")
                && strcmp (tree->u.object.keys[i], "ociVersionMax")
                && strcmp (tree->u.object.keys[i], "hooks")
                && strcmp (tree->u.object.keys[i], "mountOptions")
                && strcmp (tree->u.object.keys[i], "annotations")
                && strcmp (tree->u.object.keys[i], "potentiallyUnsafeConfigAnnotations")
                && strcmp (tree->u.object.keys[i], "linux")){
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
free_runtime_spec_schema_features_schema (runtime_spec_schema_features_schema *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->oci_version_min);
    ptr->oci_version_min = NULL;
    free (ptr->oci_version_max);
    ptr->oci_version_max = NULL;
    if (ptr->hooks != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->hooks_len; i++)
          {
            if (ptr->hooks[i] != NULL)
              {
                free (ptr->hooks[i]);
                ptr->hooks[i] = NULL;
              }
          }
        free (ptr->hooks);
        ptr->hooks = NULL;
    }
    if (ptr->mount_options != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->mount_options_len; i++)
          {
            if (ptr->mount_options[i] != NULL)
              {
                free (ptr->mount_options[i]);
                ptr->mount_options[i] = NULL;
              }
          }
        free (ptr->mount_options);
        ptr->mount_options = NULL;
    }
    free_json_map_string_string (ptr->annotations);
    ptr->annotations = NULL;
    if (ptr->potentially_unsafe_config_annotations != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->potentially_unsafe_config_annotations_len; i++)
          {
            if (ptr->potentially_unsafe_config_annotations[i] != NULL)
              {
                free (ptr->potentially_unsafe_config_annotations[i]);
                ptr->potentially_unsafe_config_annotations[i] = NULL;
              }
          }
        free (ptr->potentially_unsafe_config_annotations);
        ptr->potentially_unsafe_config_annotations = NULL;
    }
    if (ptr->linux != NULL)
      {
        free_runtime_spec_schema_features_linux (ptr->linux);
        ptr->linux = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_features_schema (yajl_gen g, const runtime_spec_schema_features_schema *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->oci_version_min != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ociVersionMin"), 13 /* strlen ("ociVersionMin") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->oci_version_min != NULL)
            str = ptr->oci_version_min;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->oci_version_max != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ociVersionMax"), 13 /* strlen ("ociVersionMax") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->oci_version_max != NULL)
            str = ptr->oci_version_max;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->hooks != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("hooks"), 5 /* strlen ("hooks") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->hooks != NULL)
          len = ptr->hooks_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->hooks[i]), strlen (ptr->hooks[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->mount_options != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("mountOptions"), 12 /* strlen ("mountOptions") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->mount_options != NULL)
          len = ptr->mount_options_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->mount_options[i]), strlen (ptr->mount_options[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->potentially_unsafe_config_annotations != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("potentiallyUnsafeConfigAnnotations"), 34 /* strlen ("potentiallyUnsafeConfigAnnotations") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->potentially_unsafe_config_annotations != NULL)
          len = ptr->potentially_unsafe_config_annotations_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->potentially_unsafe_config_annotations[i]), strlen (ptr->potentially_unsafe_config_annotations[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->linux != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("linux"), 5 /* strlen ("linux") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_features_linux (g, ptr != NULL ? ptr->linux : NULL, ctx, err);
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

runtime_spec_schema_features_schema *
clone_runtime_spec_schema_features_schema (runtime_spec_schema_features_schema *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_features_schema) runtime_spec_schema_features_schema *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->oci_version_min)
      {
        ret->oci_version_min = strdup (src->oci_version_min);
        if (ret->oci_version_min == NULL)
          return NULL;
      }
    if (src->oci_version_max)
      {
        ret->oci_version_max = strdup (src->oci_version_max);
        if (ret->oci_version_max == NULL)
          return NULL;
      }
    if (src->hooks)
      {
        ret->hooks_len = src->hooks_len;
        ret->hooks = calloc (src->hooks_len + 1, sizeof (*ret->hooks));
        if (ret->hooks == NULL)
          return NULL;
        for (size_t i = 0; i < src->hooks_len; i++)
          {
            if (src->hooks[i])
              {
                ret->hooks[i] = strdup (src->hooks[i]);
                if (ret->hooks[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->mount_options)
      {
        ret->mount_options_len = src->mount_options_len;
        ret->mount_options = calloc (src->mount_options_len + 1, sizeof (*ret->mount_options));
        if (ret->mount_options == NULL)
          return NULL;
        for (size_t i = 0; i < src->mount_options_len; i++)
          {
            if (src->mount_options[i])
              {
                ret->mount_options[i] = strdup (src->mount_options[i]);
                if (ret->mount_options[i] == NULL)
                  return NULL;
              }
          }
      }
    ret->annotations = clone_map_string_string (src->annotations);
    if (ret->annotations == NULL)
        return NULL;
    if (src->potentially_unsafe_config_annotations)
      {
        ret->potentially_unsafe_config_annotations_len = src->potentially_unsafe_config_annotations_len;
        ret->potentially_unsafe_config_annotations = calloc (src->potentially_unsafe_config_annotations_len + 1, sizeof (*ret->potentially_unsafe_config_annotations));
        if (ret->potentially_unsafe_config_annotations == NULL)
          return NULL;
        for (size_t i = 0; i < src->potentially_unsafe_config_annotations_len; i++)
          {
            if (src->potentially_unsafe_config_annotations[i])
              {
                ret->potentially_unsafe_config_annotations[i] = strdup (src->potentially_unsafe_config_annotations[i]);
                if (ret->potentially_unsafe_config_annotations[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->linux)
      {
        ret->linux = clone_runtime_spec_schema_features_linux (src->linux);
        if (ret->linux == NULL)
          return NULL;
      }
    return move_ptr (ret);
}


runtime_spec_schema_features_schema *
runtime_spec_schema_features_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
runtime_spec_schema_features_schema *ptr = NULL;size_t filesize;
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
      }ptr = runtime_spec_schema_features_schema_parse_data (content, ctx, err);return ptr;
}
runtime_spec_schema_features_schema * 
runtime_spec_schema_features_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{runtime_spec_schema_features_schema *ptr = NULL;
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
ptr = runtime_spec_schema_features_schema_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 runtime_spec_schema_features_schema * runtime_spec_schema_features_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  runtime_spec_schema_features_schema *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
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
ptr = make_runtime_spec_schema_features_schema (tree, ctx, err);return ptr; 
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
runtime_spec_schema_features_schema_generate_json (const runtime_spec_schema_features_schema *ptr, const struct parser_context *ctx, parser_error *err){
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

if (yajl_gen_status_ok != gen_runtime_spec_schema_features_schema (g, ptr, ctx, err))  {
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
