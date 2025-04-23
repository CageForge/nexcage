#ifndef RUNTIME_SERVICE_C_H
#define RUNTIME_SERVICE_C_H

#include <grpc/grpc.h>
#include <grpc/byte_buffer.h>

// Handler function type for gRPC methods
typedef void (*grpc_method_handler_fn)(grpc_byte_buffer* request, grpc_byte_buffer** response);

// Method handler structure
typedef struct {
    const char* name;
    grpc_method_handler_fn handler;
    int flags;
} grpc_method_handler_t;

// Service descriptor structure
typedef struct {
    const char* name;
    const grpc_method_handler_t* methods;
    size_t method_count;
} grpc_service_descriptor_t;

// Service descriptor
extern const grpc_service_descriptor_t runtime_service_descriptor;

#endif // RUNTIME_SERVICE_C_H 