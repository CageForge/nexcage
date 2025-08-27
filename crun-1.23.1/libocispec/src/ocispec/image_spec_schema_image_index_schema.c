/* Generated from image-index-schema.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/image_spec_schema_image_index_schema.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (image_spec_schema_image_index_schema_manifests_platform *, free_image_spec_schema_image_index_schema_manifests_platform)
image_spec_schema_image_index_schema_manifests_platform *
make_image_spec_schema_image_index_schema_manifests_platform (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_image_index_schema_manifests_platform) image_spec_schema_image_index_schema_manifests_platform *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
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
            if (strcmp (tree->u.object.keys[i], "architecture")
                && strcmp (tree->u.object.keys[i], "os")
                && strcmp (tree->u.object.keys[i], "os.version")
                && strcmp (tree->u.object.keys[i], "os.features")
                && strcmp (tree->u.object.keys[i], "variant")){
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
free_image_spec_schema_image_index_schema_manifests_platform (image_spec_schema_image_index_schema_manifests_platform *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->architecture);
    ptr->architecture = NULL;
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
    free (ptr->variant);
    ptr->variant = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_image_index_schema_manifests_platform (yajl_gen g, const image_spec_schema_image_index_schema_manifests_platform *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
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

image_spec_schema_image_index_schema_manifests_platform *
clone_image_spec_schema_image_index_schema_manifests_platform (image_spec_schema_image_index_schema_manifests_platform *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_image_index_schema_manifests_platform) image_spec_schema_image_index_schema_manifests_platform *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->architecture)
      {
        ret->architecture = strdup (src->architecture);
        if (ret->architecture == NULL)
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
    if (src->variant)
      {
        ret->variant = strdup (src->variant);
        if (ret->variant == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (image_spec_schema_image_index_schema_manifests_element *, free_image_spec_schema_image_index_schema_manifests_element)
image_spec_schema_image_index_schema_manifests_element *
make_image_spec_schema_image_index_schema_manifests_element (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_image_index_schema_manifests_element) image_spec_schema_image_index_schema_manifests_element *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "mediaType", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->media_type = strdup (str ? str : "");
            if (ret->media_type == NULL)
              return NULL;
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
            invalid = common_safe_int64 (YAJL_GET_NUMBER (val), &ret->size);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'int64' for key 'size': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->size_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "digest", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->digest = strdup (str ? str : "");
            if (ret->digest == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "urls", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->urls_len = len;
            ret->urls = calloc (len + 1, sizeof (*ret->urls));
            if (ret->urls == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->urls[i] = strdup (str ? str : "");
                    if (ret->urls[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    ret->platform = make_image_spec_schema_image_index_schema_manifests_platform (get_val (tree, "platform", yajl_t_object), ctx, err);
    if (ret->platform == NULL && *err != 0)
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
    if (ret->media_type == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "mediaType") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->digest == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "digest") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    return move_ptr (ret);
}

void
free_image_spec_schema_image_index_schema_manifests_element (image_spec_schema_image_index_schema_manifests_element *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->media_type);
    ptr->media_type = NULL;
    free (ptr->digest);
    ptr->digest = NULL;
    if (ptr->urls != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->urls_len; i++)
          {
            if (ptr->urls[i] != NULL)
              {
                free (ptr->urls[i]);
                ptr->urls[i] = NULL;
              }
          }
        free (ptr->urls);
        ptr->urls = NULL;
    }
    if (ptr->platform != NULL)
      {
        free_image_spec_schema_image_index_schema_manifests_platform (ptr->platform);
        ptr->platform = NULL;
      }
    free_json_map_string_string (ptr->annotations);
    ptr->annotations = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_image_index_schema_manifests_element (yajl_gen g, const image_spec_schema_image_index_schema_manifests_element *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->media_type != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("mediaType"), 9 /* strlen ("mediaType") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->media_type != NULL)
            str = ptr->media_type;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->size_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("size"), 4 /* strlen ("size") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->size)
            num = (long long int)ptr->size;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->digest != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("digest"), 6 /* strlen ("digest") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->digest != NULL)
            str = ptr->digest;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->urls != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("urls"), 4 /* strlen ("urls") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->urls != NULL)
          len = ptr->urls_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->urls[i]), strlen (ptr->urls[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->platform != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("platform"), 8 /* strlen ("platform") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_image_spec_schema_image_index_schema_manifests_platform (g, ptr != NULL ? ptr->platform : NULL, ctx, err);
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
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

image_spec_schema_image_index_schema_manifests_element *
clone_image_spec_schema_image_index_schema_manifests_element (image_spec_schema_image_index_schema_manifests_element *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_image_index_schema_manifests_element) image_spec_schema_image_index_schema_manifests_element *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->media_type)
      {
        ret->media_type = strdup (src->media_type);
        if (ret->media_type == NULL)
          return NULL;
      }
    ret->size = src->size;
    ret->size_present = src->size_present;
    if (src->digest)
      {
        ret->digest = strdup (src->digest);
        if (ret->digest == NULL)
          return NULL;
      }
    if (src->urls)
      {
        ret->urls_len = src->urls_len;
        ret->urls = calloc (src->urls_len + 1, sizeof (*ret->urls));
        if (ret->urls == NULL)
          return NULL;
        for (size_t i = 0; i < src->urls_len; i++)
          {
            if (src->urls[i])
              {
                ret->urls[i] = strdup (src->urls[i]);
                if (ret->urls[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->platform)
      {
        ret->platform = clone_image_spec_schema_image_index_schema_manifests_platform (src->platform);
        if (ret->platform == NULL)
          return NULL;
      }
    ret->annotations = clone_map_string_string (src->annotations);
    if (ret->annotations == NULL)
        return NULL;
    return move_ptr (ret);
}

define_cleaner_function (image_spec_schema_image_index_schema *, free_image_spec_schema_image_index_schema)
image_spec_schema_image_index_schema *
make_image_spec_schema_image_index_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_image_index_schema) image_spec_schema_image_index_schema *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "schemaVersion", yajl_t_number);
        if (val != NULL)
          {
            int invalid;
            if (! YAJL_IS_NUMBER (val))
              {
                *err = strdup ("invalid type");
                return NULL;
              }
            invalid = common_safe_int (YAJL_GET_NUMBER (val), (int *)&ret->schema_version);
            if (invalid)
              {
                if (asprintf (err, "Invalid value '%s' with type 'integer' for key 'schemaVersion': %s", YAJL_GET_NUMBER (val), strerror (-invalid)) < 0)
                    *err = strdup ("error allocating memory");
                return NULL;
            }
            ret->schema_version_present = 1;
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "mediaType", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->media_type = strdup (str ? str : "");
            if (ret->media_type == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "artifactType", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->artifact_type = strdup (str ? str : "");
            if (ret->artifact_type == NULL)
              return NULL;
          }
      }
    while (0);
    ret->subject = make_image_spec_schema_content_descriptor (get_val (tree, "subject", yajl_t_object), ctx, err);
    if (ret->subject == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "manifests", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->manifests_len = len;
            ret->manifests = calloc (len + 1, sizeof (*ret->manifests));
            if (ret->manifests == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->manifests[i] = make_image_spec_schema_image_index_schema_manifests_element (val, ctx, err);
                if (ret->manifests[i] == NULL)
                  return NULL;
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
    if (ret->manifests == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "manifests") < 0)
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
            if (strcmp (tree->u.object.keys[i], "schemaVersion")
                && strcmp (tree->u.object.keys[i], "mediaType")
                && strcmp (tree->u.object.keys[i], "artifactType")
                && strcmp (tree->u.object.keys[i], "subject")
                && strcmp (tree->u.object.keys[i], "manifests")
                && strcmp (tree->u.object.keys[i], "annotations")){
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
free_image_spec_schema_image_index_schema (image_spec_schema_image_index_schema *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->media_type);
    ptr->media_type = NULL;
    free (ptr->artifact_type);
    ptr->artifact_type = NULL;
    if (ptr->subject != NULL)
      {
        free_image_spec_schema_content_descriptor (ptr->subject);
        ptr->subject = NULL;
      }
    if (ptr->manifests != NULL)      {
        size_t i;
        for (i = 0; i < ptr->manifests_len; i++)
          {
          if (ptr->manifests[i] != NULL)
            {
              free_image_spec_schema_image_index_schema_manifests_element (ptr->manifests[i]);
              ptr->manifests[i] = NULL;
            }
          }
        free (ptr->manifests);
        ptr->manifests = NULL;
      }
    free_json_map_string_string (ptr->annotations);
    ptr->annotations = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_image_index_schema (yajl_gen g, const image_spec_schema_image_index_schema *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->schema_version_present))
      {
        long long int num = 0;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("schemaVersion"), 13 /* strlen ("schemaVersion") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->schema_version)
            num = (long long int)ptr->schema_version;
        stat = map_int (g, num);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->media_type != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("mediaType"), 9 /* strlen ("mediaType") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->media_type != NULL)
            str = ptr->media_type;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->artifact_type != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("artifactType"), 12 /* strlen ("artifactType") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->artifact_type != NULL)
            str = ptr->artifact_type;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->subject != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("subject"), 7 /* strlen ("subject") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_image_spec_schema_content_descriptor (g, ptr != NULL ? ptr->subject : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->manifests != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("manifests"), 9 /* strlen ("manifests") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->manifests != NULL)
            len = ptr->manifests_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_image_spec_schema_image_index_schema_manifests_element (g, ptr->manifests[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
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

image_spec_schema_image_index_schema *
clone_image_spec_schema_image_index_schema (image_spec_schema_image_index_schema *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_image_index_schema) image_spec_schema_image_index_schema *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    ret->schema_version = src->schema_version;
    ret->schema_version_present = src->schema_version_present;
    if (src->media_type)
      {
        ret->media_type = strdup (src->media_type);
        if (ret->media_type == NULL)
          return NULL;
      }
    if (src->artifact_type)
      {
        ret->artifact_type = strdup (src->artifact_type);
        if (ret->artifact_type == NULL)
          return NULL;
      }
    if (src->subject)
      {
        ret->subject = clone_image_spec_schema_content_descriptor (src->subject);
        if (ret->subject == NULL)
          return NULL;
      }
    if (src->manifests)
      {
        ret->manifests_len = src->manifests_len;
        ret->manifests = calloc (src->manifests_len + 1, sizeof (*ret->manifests));
        if (ret->manifests == NULL)
          return NULL;
        for (size_t i = 0; i < src->manifests_len; i++)
          {
            ret->manifests[i] = clone_image_spec_schema_image_index_schema_manifests_element (src->manifests[i]);
            if (ret->manifests[i] == NULL)
                return NULL;
          }
      }
    ret->annotations = clone_map_string_string (src->annotations);
    if (ret->annotations == NULL)
        return NULL;
    return move_ptr (ret);
}


image_spec_schema_image_index_schema *
image_spec_schema_image_index_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
image_spec_schema_image_index_schema *ptr = NULL;size_t filesize;
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
      }ptr = image_spec_schema_image_index_schema_parse_data (content, ctx, err);return ptr;
}
image_spec_schema_image_index_schema * 
image_spec_schema_image_index_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{image_spec_schema_image_index_schema *ptr = NULL;
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
ptr = image_spec_schema_image_index_schema_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 image_spec_schema_image_index_schema * image_spec_schema_image_index_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  image_spec_schema_image_index_schema *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
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
ptr = make_image_spec_schema_image_index_schema (tree, ctx, err);return ptr; 
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
image_spec_schema_image_index_schema_generate_json (const image_spec_schema_image_index_schema *ptr, const struct parser_context *ctx, parser_error *err){
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

if (yajl_gen_status_ok != gen_image_spec_schema_image_index_schema (g, ptr, ctx, err))  {
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
