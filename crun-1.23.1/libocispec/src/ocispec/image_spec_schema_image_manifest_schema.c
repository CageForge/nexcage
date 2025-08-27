/* Generated from image-manifest-schema.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/image_spec_schema_image_manifest_schema.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (image_spec_schema_image_manifest_schema *, free_image_spec_schema_image_manifest_schema)
image_spec_schema_image_manifest_schema *
make_image_spec_schema_image_manifest_schema (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_spec_schema_image_manifest_schema) image_spec_schema_image_manifest_schema *ret = NULL;
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
    ret->config = make_image_spec_schema_content_descriptor (get_val (tree, "config", yajl_t_object), ctx, err);
    if (ret->config == NULL && *err != 0)
      return NULL;
    ret->subject = make_image_spec_schema_content_descriptor (get_val (tree, "subject", yajl_t_object), ctx, err);
    if (ret->subject == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "layers", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->layers_len = len;
            ret->layers = calloc (len + 1, sizeof (*ret->layers));
            if (ret->layers == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->layers[i] = make_image_spec_schema_content_descriptor (val, ctx, err);
                if (ret->layers[i] == NULL)
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
    if (ret->config == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "config") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->layers == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "layers") < 0)
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
                && strcmp (tree->u.object.keys[i], "config")
                && strcmp (tree->u.object.keys[i], "subject")
                && strcmp (tree->u.object.keys[i], "layers")
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
free_image_spec_schema_image_manifest_schema (image_spec_schema_image_manifest_schema *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->media_type);
    ptr->media_type = NULL;
    free (ptr->artifact_type);
    ptr->artifact_type = NULL;
    if (ptr->config != NULL)
      {
        free_image_spec_schema_content_descriptor (ptr->config);
        ptr->config = NULL;
      }
    if (ptr->subject != NULL)
      {
        free_image_spec_schema_content_descriptor (ptr->subject);
        ptr->subject = NULL;
      }
    if (ptr->layers != NULL)      {
        size_t i;
        for (i = 0; i < ptr->layers_len; i++)
          {
          if (ptr->layers[i] != NULL)
            {
              free_image_spec_schema_content_descriptor (ptr->layers[i]);
              ptr->layers[i] = NULL;
            }
          }
        free (ptr->layers);
        ptr->layers = NULL;
      }
    free_json_map_string_string (ptr->annotations);
    ptr->annotations = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_spec_schema_image_manifest_schema (yajl_gen g, const image_spec_schema_image_manifest_schema *ptr, const struct parser_context *ctx, parser_error *err)
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->config != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("config"), 6 /* strlen ("config") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_image_spec_schema_content_descriptor (g, ptr != NULL ? ptr->config : NULL, ctx, err);
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
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->layers != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("layers"), 6 /* strlen ("layers") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->layers != NULL)
            len = ptr->layers_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_image_spec_schema_content_descriptor (g, ptr->layers[i], ctx, err);
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

image_spec_schema_image_manifest_schema *
clone_image_spec_schema_image_manifest_schema (image_spec_schema_image_manifest_schema *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_spec_schema_image_manifest_schema) image_spec_schema_image_manifest_schema *ret = NULL;
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
    if (src->config)
      {
        ret->config = clone_image_spec_schema_content_descriptor (src->config);
        if (ret->config == NULL)
          return NULL;
      }
    if (src->subject)
      {
        ret->subject = clone_image_spec_schema_content_descriptor (src->subject);
        if (ret->subject == NULL)
          return NULL;
      }
    if (src->layers)
      {
        ret->layers_len = src->layers_len;
        ret->layers = calloc (src->layers_len + 1, sizeof (*ret->layers));
        if (ret->layers == NULL)
          return NULL;
        for (size_t i = 0; i < src->layers_len; i++)
          {
            ret->layers[i] = clone_image_spec_schema_content_descriptor (src->layers[i]);
            if (ret->layers[i] == NULL)
                return NULL;
          }
      }
    ret->annotations = clone_map_string_string (src->annotations);
    if (ret->annotations == NULL)
        return NULL;
    return move_ptr (ret);
}


image_spec_schema_image_manifest_schema *
image_spec_schema_image_manifest_schema_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
image_spec_schema_image_manifest_schema *ptr = NULL;size_t filesize;
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
      }ptr = image_spec_schema_image_manifest_schema_parse_data (content, ctx, err);return ptr;
}
image_spec_schema_image_manifest_schema * 
image_spec_schema_image_manifest_schema_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{image_spec_schema_image_manifest_schema *ptr = NULL;
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
ptr = image_spec_schema_image_manifest_schema_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 image_spec_schema_image_manifest_schema * image_spec_schema_image_manifest_schema_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  image_spec_schema_image_manifest_schema *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
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
ptr = make_image_spec_schema_image_manifest_schema (tree, ctx, err);return ptr; 
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
image_spec_schema_image_manifest_schema_generate_json (const image_spec_schema_image_manifest_schema *ptr, const struct parser_context *ctx, parser_error *err){
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

if (yajl_gen_status_ok != gen_image_spec_schema_image_manifest_schema (g, ptr, ctx, err))  {
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
