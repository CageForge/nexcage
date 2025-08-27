/* Generated from image-manifest-items-schema.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/image_manifest_items_image_manifest_items_schema.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (image_manifest_items_image_manifest_items_schema_element *, free_image_manifest_items_image_manifest_items_schema_element)
image_manifest_items_image_manifest_items_schema_element *
make_image_manifest_items_image_manifest_items_schema_element (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_manifest_items_image_manifest_items_schema_element) image_manifest_items_image_manifest_items_schema_element *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "Config", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->config = strdup (str ? str : "");
            if (ret->config == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "Layers", yajl_t_array);
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
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->layers[i] = strdup (str ? str : "");
                    if (ret->layers[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val tmp = get_val (tree, "RepoTags", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->repo_tags_len = len;
            ret->repo_tags = calloc (len + 1, sizeof (*ret->repo_tags));
            if (ret->repo_tags == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                if (val != NULL)
                  {
                    char *str = YAJL_GET_STRING (val);
                    ret->repo_tags[i] = strdup (str ? str : "");
                    if (ret->repo_tags[i] == NULL)
                      return NULL;
                  }
              }
        }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "Parent", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->parent = strdup (str ? str : "");
            if (ret->parent == NULL)
              return NULL;
          }
      }
    while (0);
    if (ret->config == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "Config") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    if (ret->layers == NULL)
      {
        if (asprintf (err, "Required field '%s' not present",  "Layers") < 0)
            *err = strdup ("error allocating memory");
        return NULL;
      }
    return move_ptr (ret);
}

void
free_image_manifest_items_image_manifest_items_schema_element (image_manifest_items_image_manifest_items_schema_element *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->config);
    ptr->config = NULL;
    if (ptr->layers != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->layers_len; i++)
          {
            if (ptr->layers[i] != NULL)
              {
                free (ptr->layers[i]);
                ptr->layers[i] = NULL;
              }
          }
        free (ptr->layers);
        ptr->layers = NULL;
    }
    if (ptr->repo_tags != NULL)
      {
        size_t i;
        for (i = 0; i < ptr->repo_tags_len; i++)
          {
            if (ptr->repo_tags[i] != NULL)
              {
                free (ptr->repo_tags[i]);
                ptr->repo_tags[i] = NULL;
              }
          }
        free (ptr->repo_tags);
        ptr->repo_tags = NULL;
    }
    free (ptr->parent);
    ptr->parent = NULL;
    free (ptr);
}

yajl_gen_status
gen_image_manifest_items_image_manifest_items_schema_element (yajl_gen g, const image_manifest_items_image_manifest_items_schema_element *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->config != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("Config"), 6 /* strlen ("Config") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->config != NULL)
            str = ptr->config;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->layers != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("Layers"), 6 /* strlen ("Layers") */);
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
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->layers[i]), strlen (ptr->layers[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->repo_tags != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("RepoTags"), 8 /* strlen ("RepoTags") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->repo_tags != NULL)
          len = ptr->repo_tags_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(ptr->repo_tags[i]), strlen (ptr->repo_tags[i]));
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);
          }
        stat = yajl_gen_array_close ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 1);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->parent != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("Parent"), 6 /* strlen ("Parent") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->parent != NULL)
            str = ptr->parent;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

image_manifest_items_image_manifest_items_schema_element *
clone_image_manifest_items_image_manifest_items_schema_element (image_manifest_items_image_manifest_items_schema_element *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_image_manifest_items_image_manifest_items_schema_element) image_manifest_items_image_manifest_items_schema_element *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->config)
      {
        ret->config = strdup (src->config);
        if (ret->config == NULL)
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
            if (src->layers[i])
              {
                ret->layers[i] = strdup (src->layers[i]);
                if (ret->layers[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->repo_tags)
      {
        ret->repo_tags_len = src->repo_tags_len;
        ret->repo_tags = calloc (src->repo_tags_len + 1, sizeof (*ret->repo_tags));
        if (ret->repo_tags == NULL)
          return NULL;
        for (size_t i = 0; i < src->repo_tags_len; i++)
          {
            if (src->repo_tags[i])
              {
                ret->repo_tags[i] = strdup (src->repo_tags[i]);
                if (ret->repo_tags[i] == NULL)
                  return NULL;
              }
          }
      }
    if (src->parent)
      {
        ret->parent = strdup (src->parent);
        if (ret->parent == NULL)
          return NULL;
      }
    return move_ptr (ret);
}


define_cleaner_function (image_manifest_items_image_manifest_items_schema_container *, free_image_manifest_items_image_manifest_items_schema_container)
image_manifest_items_image_manifest_items_schema_container
*make_image_manifest_items_image_manifest_items_schema_container (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_image_manifest_items_image_manifest_items_schema_container) image_manifest_items_image_manifest_items_schema_container *ptr = NULL;
    size_t i, alen;
     (void) ctx;
     if (tree == NULL || err == NULL || YAJL_GET_ARRAY (tree) == NULL)
      return NULL;
    *err = NULL;
    alen = YAJL_GET_ARRAY_NO_CHECK (tree)->len;
    if (alen == 0)
      return NULL;
    ptr = calloc (1, sizeof (image_manifest_items_image_manifest_items_schema_container));
    if (ptr == NULL)
      return NULL;
    ptr->items = calloc (alen + 1, sizeof(*ptr->items));
    if (ptr->items == NULL)
      return NULL;
    ptr->len = alen;


    for (i = 0; i < alen; i++)
      {
        yajl_val work = YAJL_GET_ARRAY_NO_CHECK (tree)->values[i];
        ptr->items[i] = make_image_manifest_items_image_manifest_items_schema_element (work, ctx, err);
        if (ptr->items[i] == NULL)
          return NULL;


      }
    return move_ptr(ptr);
}


void free_image_manifest_items_image_manifest_items_schema_container (image_manifest_items_image_manifest_items_schema_container *ptr)
{
    size_t i;

    if (ptr == NULL)
        return;

    for (i = 0; i < ptr->len; i++)
      {
          free_image_manifest_items_image_manifest_items_schema_element (ptr->items[i]);
          ptr->items[i] = NULL;

      }

    free (ptr->items);
    ptr->items = NULL;


    free (ptr);
}
yajl_gen_status gen_image_manifest_items_image_manifest_items_schema_container (yajl_gen g, const image_manifest_items_image_manifest_items_schema_container *ptr, const struct parser_context *ctx,
                       parser_error *err)
{
    yajl_gen_status stat;
    size_t i;

    if (ptr == NULL)
        return yajl_gen_status_ok;
    *err = NULL;


    stat = yajl_gen_array_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    for (i = 0; i < ptr->len; i++)
      {
      {
            stat = gen_image_manifest_items_image_manifest_items_schema_element (g, ptr->items[i], ctx, err);
            if (stat != yajl_gen_status_ok)
                GEN_SET_ERROR_AND_RETURN (stat, err);


            }
      }
    stat = yajl_gen_array_close ((yajl_gen) g);


    if (ptr->len > 0 && !(ctx->options & OPT_GEN_SIMPLIFY))
        yajl_gen_config (g, yajl_gen_beautify, 1);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

image_manifest_items_image_manifest_items_schema_container *
image_manifest_items_image_manifest_items_schema_container_parse_file (const char *filename, const struct parser_context *ctx, parser_error *err)
{
image_manifest_items_image_manifest_items_schema_container *ptr = NULL;size_t filesize;
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
      }ptr = image_manifest_items_image_manifest_items_schema_container_parse_data (content, ctx, err);return ptr;
}
image_manifest_items_image_manifest_items_schema_container * 
image_manifest_items_image_manifest_items_schema_container_parse_file_stream (FILE *stream, const struct parser_context *ctx, parser_error *err)
{image_manifest_items_image_manifest_items_schema_container *ptr = NULL;
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
ptr = image_manifest_items_image_manifest_items_schema_container_parse_data (content, ctx, err);return ptr;
}

define_cleaner_function (yajl_val, yajl_tree_free)

 image_manifest_items_image_manifest_items_schema_container * image_manifest_items_image_manifest_items_schema_container_parse_data (const char *jsondata, const struct parser_context *ctx, parser_error *err)
 { 
  image_manifest_items_image_manifest_items_schema_container *ptr = NULL;__auto_cleanup(yajl_tree_free) yajl_val tree = NULL;
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
ptr = make_image_manifest_items_image_manifest_items_schema_container (tree, ctx, err);return ptr; 
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
image_manifest_items_image_manifest_items_schema_container_generate_json (const image_manifest_items_image_manifest_items_schema_container *ptr, const struct parser_context *ctx, parser_error *err){
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

if (yajl_gen_status_ok != gen_image_manifest_items_image_manifest_items_schema_container (g, ptr, ctx, err))  {
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
