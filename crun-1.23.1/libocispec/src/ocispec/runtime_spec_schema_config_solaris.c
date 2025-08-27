/* Generated from config-solaris.json. Do not edit!  */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <ocispec/read-file.h>
#include "ocispec/runtime_spec_schema_config_solaris.h"

#define YAJL_GET_ARRAY_NO_CHECK(v) (&(v)->u.array)
#define YAJL_GET_OBJECT_NO_CHECK(v) (&(v)->u.object)
define_cleaner_function (runtime_spec_schema_config_solaris_capped_cpu *, free_runtime_spec_schema_config_solaris_capped_cpu)
runtime_spec_schema_config_solaris_capped_cpu *
make_runtime_spec_schema_config_solaris_capped_cpu (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_solaris_capped_cpu) runtime_spec_schema_config_solaris_capped_cpu *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "ncpus", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->ncpus = strdup (str ? str : "");
            if (ret->ncpus == NULL)
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
            if (strcmp (tree->u.object.keys[i], "ncpus")){
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
free_runtime_spec_schema_config_solaris_capped_cpu (runtime_spec_schema_config_solaris_capped_cpu *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->ncpus);
    ptr->ncpus = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_solaris_capped_cpu (yajl_gen g, const runtime_spec_schema_config_solaris_capped_cpu *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->ncpus != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("ncpus"), 5 /* strlen ("ncpus") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->ncpus != NULL)
            str = ptr->ncpus;
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

runtime_spec_schema_config_solaris_capped_cpu *
clone_runtime_spec_schema_config_solaris_capped_cpu (runtime_spec_schema_config_solaris_capped_cpu *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_solaris_capped_cpu) runtime_spec_schema_config_solaris_capped_cpu *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->ncpus)
      {
        ret->ncpus = strdup (src->ncpus);
        if (ret->ncpus == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_solaris_capped_memory *, free_runtime_spec_schema_config_solaris_capped_memory)
runtime_spec_schema_config_solaris_capped_memory *
make_runtime_spec_schema_config_solaris_capped_memory (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_solaris_capped_memory) runtime_spec_schema_config_solaris_capped_memory *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "physical", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->physical = strdup (str ? str : "");
            if (ret->physical == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "swap", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->swap = strdup (str ? str : "");
            if (ret->swap == NULL)
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
            if (strcmp (tree->u.object.keys[i], "physical")
                && strcmp (tree->u.object.keys[i], "swap")){
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
free_runtime_spec_schema_config_solaris_capped_memory (runtime_spec_schema_config_solaris_capped_memory *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->physical);
    ptr->physical = NULL;
    free (ptr->swap);
    ptr->swap = NULL;
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_solaris_capped_memory (yajl_gen g, const runtime_spec_schema_config_solaris_capped_memory *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->physical != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("physical"), 8 /* strlen ("physical") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->physical != NULL)
            str = ptr->physical;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->swap != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("swap"), 4 /* strlen ("swap") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->swap != NULL)
            str = ptr->swap;
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

runtime_spec_schema_config_solaris_capped_memory *
clone_runtime_spec_schema_config_solaris_capped_memory (runtime_spec_schema_config_solaris_capped_memory *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_solaris_capped_memory) runtime_spec_schema_config_solaris_capped_memory *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->physical)
      {
        ret->physical = strdup (src->physical);
        if (ret->physical == NULL)
          return NULL;
      }
    if (src->swap)
      {
        ret->swap = strdup (src->swap);
        if (ret->swap == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_solaris_anet_element *, free_runtime_spec_schema_config_solaris_anet_element)
runtime_spec_schema_config_solaris_anet_element *
make_runtime_spec_schema_config_solaris_anet_element (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_solaris_anet_element) runtime_spec_schema_config_solaris_anet_element *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "linkname", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->linkname = strdup (str ? str : "");
            if (ret->linkname == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "lowerLink", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->lower_link = strdup (str ? str : "");
            if (ret->lower_link == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "allowedAddress", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->allowed_address = strdup (str ? str : "");
            if (ret->allowed_address == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "configureAllowedAddress", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->configure_allowed_address = strdup (str ? str : "");
            if (ret->configure_allowed_address == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "defrouter", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->defrouter = strdup (str ? str : "");
            if (ret->defrouter == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "macAddress", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->mac_address = strdup (str ? str : "");
            if (ret->mac_address == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "linkProtection", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->link_protection = strdup (str ? str : "");
            if (ret->link_protection == NULL)
              return NULL;
          }
      }
    while (0);
    return move_ptr (ret);
}

void
free_runtime_spec_schema_config_solaris_anet_element (runtime_spec_schema_config_solaris_anet_element *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->linkname);
    ptr->linkname = NULL;
    free (ptr->lower_link);
    ptr->lower_link = NULL;
    free (ptr->allowed_address);
    ptr->allowed_address = NULL;
    free (ptr->configure_allowed_address);
    ptr->configure_allowed_address = NULL;
    free (ptr->defrouter);
    ptr->defrouter = NULL;
    free (ptr->mac_address);
    ptr->mac_address = NULL;
    free (ptr->link_protection);
    ptr->link_protection = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_solaris_anet_element (yajl_gen g, const runtime_spec_schema_config_solaris_anet_element *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->linkname != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("linkname"), 8 /* strlen ("linkname") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->linkname != NULL)
            str = ptr->linkname;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->lower_link != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("lowerLink"), 9 /* strlen ("lowerLink") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->lower_link != NULL)
            str = ptr->lower_link;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->allowed_address != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("allowedAddress"), 14 /* strlen ("allowedAddress") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->allowed_address != NULL)
            str = ptr->allowed_address;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->configure_allowed_address != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("configureAllowedAddress"), 23 /* strlen ("configureAllowedAddress") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->configure_allowed_address != NULL)
            str = ptr->configure_allowed_address;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->defrouter != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("defrouter"), 9 /* strlen ("defrouter") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->defrouter != NULL)
            str = ptr->defrouter;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->mac_address != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("macAddress"), 10 /* strlen ("macAddress") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->mac_address != NULL)
            str = ptr->mac_address;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->link_protection != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("linkProtection"), 14 /* strlen ("linkProtection") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->link_protection != NULL)
            str = ptr->link_protection;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    stat = yajl_gen_map_close ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    return yajl_gen_status_ok;
}

runtime_spec_schema_config_solaris_anet_element *
clone_runtime_spec_schema_config_solaris_anet_element (runtime_spec_schema_config_solaris_anet_element *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_solaris_anet_element) runtime_spec_schema_config_solaris_anet_element *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->linkname)
      {
        ret->linkname = strdup (src->linkname);
        if (ret->linkname == NULL)
          return NULL;
      }
    if (src->lower_link)
      {
        ret->lower_link = strdup (src->lower_link);
        if (ret->lower_link == NULL)
          return NULL;
      }
    if (src->allowed_address)
      {
        ret->allowed_address = strdup (src->allowed_address);
        if (ret->allowed_address == NULL)
          return NULL;
      }
    if (src->configure_allowed_address)
      {
        ret->configure_allowed_address = strdup (src->configure_allowed_address);
        if (ret->configure_allowed_address == NULL)
          return NULL;
      }
    if (src->defrouter)
      {
        ret->defrouter = strdup (src->defrouter);
        if (ret->defrouter == NULL)
          return NULL;
      }
    if (src->mac_address)
      {
        ret->mac_address = strdup (src->mac_address);
        if (ret->mac_address == NULL)
          return NULL;
      }
    if (src->link_protection)
      {
        ret->link_protection = strdup (src->link_protection);
        if (ret->link_protection == NULL)
          return NULL;
      }
    return move_ptr (ret);
}

define_cleaner_function (runtime_spec_schema_config_solaris *, free_runtime_spec_schema_config_solaris)
runtime_spec_schema_config_solaris *
make_runtime_spec_schema_config_solaris (yajl_val tree, const struct parser_context *ctx, parser_error *err)
{
    __auto_cleanup(free_runtime_spec_schema_config_solaris) runtime_spec_schema_config_solaris *ret = NULL;
    *err = NULL;
    (void) ctx;  /* Silence compiler warning.  */
    if (tree == NULL)
      return NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    do
      {
        yajl_val val = get_val (tree, "milestone", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->milestone = strdup (str ? str : "");
            if (ret->milestone == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "limitpriv", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->limitpriv = strdup (str ? str : "");
            if (ret->limitpriv == NULL)
              return NULL;
          }
      }
    while (0);
    do
      {
        yajl_val val = get_val (tree, "maxShmMemory", yajl_t_string);
        if (val != NULL)
          {
            char *str = YAJL_GET_STRING (val);
            ret->max_shm_memory = strdup (str ? str : "");
            if (ret->max_shm_memory == NULL)
              return NULL;
          }
      }
    while (0);
    ret->capped_cpu = make_runtime_spec_schema_config_solaris_capped_cpu (get_val (tree, "cappedCPU", yajl_t_object), ctx, err);
    if (ret->capped_cpu == NULL && *err != 0)
      return NULL;
    ret->capped_memory = make_runtime_spec_schema_config_solaris_capped_memory (get_val (tree, "cappedMemory", yajl_t_object), ctx, err);
    if (ret->capped_memory == NULL && *err != 0)
      return NULL;
    do
      {
        yajl_val tmp = get_val (tree, "anet", yajl_t_array);
        if (tmp != NULL && YAJL_GET_ARRAY (tmp) != NULL)
          {
            size_t i;
            size_t len = YAJL_GET_ARRAY_NO_CHECK (tmp)->len;
            yajl_val *values = YAJL_GET_ARRAY_NO_CHECK (tmp)->values;
            ret->anet_len = len;
            ret->anet = calloc (len + 1, sizeof (*ret->anet));
            if (ret->anet == NULL)
              return NULL;
            for (i = 0; i < len; i++)
              {
                yajl_val val = values[i];
                ret->anet[i] = make_runtime_spec_schema_config_solaris_anet_element (val, ctx, err);
                if (ret->anet[i] == NULL)
                  return NULL;
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
            if (strcmp (tree->u.object.keys[i], "milestone")
                && strcmp (tree->u.object.keys[i], "limitpriv")
                && strcmp (tree->u.object.keys[i], "maxShmMemory")
                && strcmp (tree->u.object.keys[i], "cappedCPU")
                && strcmp (tree->u.object.keys[i], "cappedMemory")
                && strcmp (tree->u.object.keys[i], "anet")){
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
free_runtime_spec_schema_config_solaris (runtime_spec_schema_config_solaris *ptr)
{
    if (ptr == NULL)
        return;
    free (ptr->milestone);
    ptr->milestone = NULL;
    free (ptr->limitpriv);
    ptr->limitpriv = NULL;
    free (ptr->max_shm_memory);
    ptr->max_shm_memory = NULL;
    if (ptr->capped_cpu != NULL)
      {
        free_runtime_spec_schema_config_solaris_capped_cpu (ptr->capped_cpu);
        ptr->capped_cpu = NULL;
      }
    if (ptr->capped_memory != NULL)
      {
        free_runtime_spec_schema_config_solaris_capped_memory (ptr->capped_memory);
        ptr->capped_memory = NULL;
      }
    if (ptr->anet != NULL)      {
        size_t i;
        for (i = 0; i < ptr->anet_len; i++)
          {
          if (ptr->anet[i] != NULL)
            {
              free_runtime_spec_schema_config_solaris_anet_element (ptr->anet[i]);
              ptr->anet[i] = NULL;
            }
          }
        free (ptr->anet);
        ptr->anet = NULL;
      }
    yajl_tree_free (ptr->_residual);
    ptr->_residual = NULL;
    free (ptr);
}

yajl_gen_status
gen_runtime_spec_schema_config_solaris (yajl_gen g, const runtime_spec_schema_config_solaris *ptr, const struct parser_context *ctx, parser_error *err)
{
    yajl_gen_status stat = yajl_gen_status_ok;
    *err = NULL;
    (void) ptr;  /* Silence compiler warning.  */
    stat = yajl_gen_map_open ((yajl_gen) g);
    if (stat != yajl_gen_status_ok)
        GEN_SET_ERROR_AND_RETURN (stat, err);
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->milestone != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("milestone"), 9 /* strlen ("milestone") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->milestone != NULL)
            str = ptr->milestone;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->limitpriv != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("limitpriv"), 9 /* strlen ("limitpriv") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->limitpriv != NULL)
            str = ptr->limitpriv;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->max_shm_memory != NULL))
      {
        char *str = "";
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("maxShmMemory"), 12 /* strlen ("maxShmMemory") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->max_shm_memory != NULL)
            str = ptr->max_shm_memory;
        stat = yajl_gen_string ((yajl_gen)g, (const unsigned char *)(str), strlen (str));
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->capped_cpu != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("cappedCPU"), 9 /* strlen ("cappedCPU") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_solaris_capped_cpu (g, ptr != NULL ? ptr->capped_cpu : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->capped_memory != NULL))
      {
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("cappedMemory"), 12 /* strlen ("cappedMemory") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        stat = gen_runtime_spec_schema_config_solaris_capped_memory (g, ptr != NULL ? ptr->capped_memory : NULL, ctx, err);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
      }
    if ((ctx->options & OPT_GEN_KEY_VALUE) || (ptr != NULL && ptr->anet != NULL))
      {
        size_t len = 0, i;
        stat = yajl_gen_string ((yajl_gen) g, (const unsigned char *)("anet"), 4 /* strlen ("anet") */);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        if (ptr != NULL && ptr->anet != NULL)
            len = ptr->anet_len;
        if (!len && !(ctx->options & OPT_GEN_SIMPLIFY))
            yajl_gen_config (g, yajl_gen_beautify, 0);
        stat = yajl_gen_array_open ((yajl_gen) g);
        if (stat != yajl_gen_status_ok)
            GEN_SET_ERROR_AND_RETURN (stat, err);
        for (i = 0; i < len; i++)
          {
            stat = gen_runtime_spec_schema_config_solaris_anet_element (g, ptr->anet[i], ctx, err);
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

runtime_spec_schema_config_solaris *
clone_runtime_spec_schema_config_solaris (runtime_spec_schema_config_solaris *src)
{
    (void) src;  /* Silence compiler warning.  */
    __auto_cleanup(free_runtime_spec_schema_config_solaris) runtime_spec_schema_config_solaris *ret = NULL;
    ret = calloc (1, sizeof (*ret));
    if (ret == NULL)
      return NULL;
    if (src->milestone)
      {
        ret->milestone = strdup (src->milestone);
        if (ret->milestone == NULL)
          return NULL;
      }
    if (src->limitpriv)
      {
        ret->limitpriv = strdup (src->limitpriv);
        if (ret->limitpriv == NULL)
          return NULL;
      }
    if (src->max_shm_memory)
      {
        ret->max_shm_memory = strdup (src->max_shm_memory);
        if (ret->max_shm_memory == NULL)
          return NULL;
      }
    if (src->capped_cpu)
      {
        ret->capped_cpu = clone_runtime_spec_schema_config_solaris_capped_cpu (src->capped_cpu);
        if (ret->capped_cpu == NULL)
          return NULL;
      }
    if (src->capped_memory)
      {
        ret->capped_memory = clone_runtime_spec_schema_config_solaris_capped_memory (src->capped_memory);
        if (ret->capped_memory == NULL)
          return NULL;
      }
    if (src->anet)
      {
        ret->anet_len = src->anet_len;
        ret->anet = calloc (src->anet_len + 1, sizeof (*ret->anet));
        if (ret->anet == NULL)
          return NULL;
        for (size_t i = 0; i < src->anet_len; i++)
          {
            ret->anet[i] = clone_runtime_spec_schema_config_solaris_anet_element (src->anet[i]);
            if (ret->anet[i] == NULL)
                return NULL;
          }
      }
    return move_ptr (ret);
}

