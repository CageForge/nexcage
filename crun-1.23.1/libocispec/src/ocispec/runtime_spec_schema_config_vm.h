// Generated from config-vm.json. Do not edit!
#ifndef RUNTIME_SPEC_SCHEMA_CONFIG_VM_SCHEMA_H
#define RUNTIME_SPEC_SCHEMA_CONFIG_VM_SCHEMA_H

#include <sys/types.h>
#include <stdint.h>
#include "ocispec/json_common.h"
#include "ocispec/runtime_spec_schema_defs.h"
#include "ocispec/runtime_spec_schema_defs_vm.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *path;

    char **parameters;
    size_t parameters_len;

    yajl_val _residual;
}
runtime_spec_schema_config_vm_hypervisor;

void free_runtime_spec_schema_config_vm_hypervisor (runtime_spec_schema_config_vm_hypervisor *ptr);

runtime_spec_schema_config_vm_hypervisor *clone_runtime_spec_schema_config_vm_hypervisor (runtime_spec_schema_config_vm_hypervisor *src);
runtime_spec_schema_config_vm_hypervisor *make_runtime_spec_schema_config_vm_hypervisor (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_vm_hypervisor (yajl_gen g, const runtime_spec_schema_config_vm_hypervisor *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *path;

    char **parameters;
    size_t parameters_len;

    char *initrd;

    yajl_val _residual;
}
runtime_spec_schema_config_vm_kernel;

void free_runtime_spec_schema_config_vm_kernel (runtime_spec_schema_config_vm_kernel *ptr);

runtime_spec_schema_config_vm_kernel *clone_runtime_spec_schema_config_vm_kernel (runtime_spec_schema_config_vm_kernel *src);
runtime_spec_schema_config_vm_kernel *make_runtime_spec_schema_config_vm_kernel (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_vm_kernel (yajl_gen g, const runtime_spec_schema_config_vm_kernel *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    char *path;

    char *format;

    yajl_val _residual;
}
runtime_spec_schema_config_vm_image;

void free_runtime_spec_schema_config_vm_image (runtime_spec_schema_config_vm_image *ptr);

runtime_spec_schema_config_vm_image *clone_runtime_spec_schema_config_vm_image (runtime_spec_schema_config_vm_image *src);
runtime_spec_schema_config_vm_image *make_runtime_spec_schema_config_vm_image (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_vm_image (yajl_gen g, const runtime_spec_schema_config_vm_image *ptr, const struct parser_context *ctx, parser_error *err);

typedef struct {
    runtime_spec_schema_config_vm_hypervisor *hypervisor;

    runtime_spec_schema_config_vm_kernel *kernel;

    runtime_spec_schema_config_vm_image *image;

    yajl_val _residual;
}
runtime_spec_schema_config_vm;

void free_runtime_spec_schema_config_vm (runtime_spec_schema_config_vm *ptr);

runtime_spec_schema_config_vm *clone_runtime_spec_schema_config_vm (runtime_spec_schema_config_vm *src);
runtime_spec_schema_config_vm *make_runtime_spec_schema_config_vm (yajl_val tree, const struct parser_context *ctx, parser_error *err);

yajl_gen_status gen_runtime_spec_schema_config_vm (yajl_gen g, const runtime_spec_schema_config_vm *ptr, const struct parser_context *ctx, parser_error *err);

#ifdef __cplusplus
}
#endif

#endif

