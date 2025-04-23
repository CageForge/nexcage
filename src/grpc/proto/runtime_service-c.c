#include "runtime_service-c.h"
#include "runtime_service.pb-c.h"
#include "runtime_service.grpc-c.h"
#include <protobuf-c/protobuf-c.h>
#include <grpc/grpc.h>
#include <grpc/support/log.h>
#include <grpc/support/alloc.h>
#include <grpc/byte_buffer_reader.h>

// Helper function to pack protobuf message into gRPC byte buffer
static grpc_byte_buffer* pack_message(const void* msg, size_t (*get_size_fn)(const void*), void (*pack_fn)(const void*, uint8_t*)) {
    size_t size = get_size_fn(msg);
    void* buf = gpr_malloc(size);
    pack_fn(msg, buf);
    grpc_slice slice = grpc_slice_from_copied_buffer(buf, size);
    grpc_byte_buffer* byte_buffer = grpc_raw_byte_buffer_create(&slice, 1);
    grpc_slice_unref(slice);
    gpr_free(buf);
    return byte_buffer;
}

// Helper function to unpack gRPC byte buffer into protobuf message
static void* unpack_message(grpc_byte_buffer* buffer, void* (*unpack_fn)(ProtobufCAllocator*, size_t, const uint8_t*)) {
    grpc_byte_buffer_reader reader;
    grpc_byte_buffer_reader_init(&reader, buffer);
    grpc_slice slice = grpc_byte_buffer_reader_readall(&reader);
    void* msg = unpack_fn(NULL, GRPC_SLICE_LENGTH(slice), GRPC_SLICE_START_PTR(slice));
    grpc_slice_unref(slice);
    grpc_byte_buffer_reader_destroy(&reader);
    return msg;
}

// Handler functions declarations
static void handle_version(grpc_byte_buffer* request, grpc_byte_buffer** response);
static void handle_create_container(grpc_byte_buffer* request, grpc_byte_buffer** response);
static void handle_start_container(grpc_byte_buffer* request, grpc_byte_buffer** response);
static void handle_stop_container(grpc_byte_buffer* request, grpc_byte_buffer** response);
static void handle_remove_container(grpc_byte_buffer* request, grpc_byte_buffer** response);
static void handle_list_containers(grpc_byte_buffer* request, grpc_byte_buffer** response);
static void handle_container_status(grpc_byte_buffer* request, grpc_byte_buffer** response);
static void handle_update_container_resources(grpc_byte_buffer* request, grpc_byte_buffer** response);

// Method handlers array
static const grpc_method_handler_t runtime_methods[] = {
    {
        .name = "/runtime.v1alpha2.RuntimeService/Version",
        .handler = handle_version,
        .flags = 0
    },
    {
        .name = "/runtime.v1alpha2.RuntimeService/CreateContainer",
        .handler = handle_create_container,
        .flags = 0
    },
    {
        .name = "/runtime.v1alpha2.RuntimeService/StartContainer",
        .handler = handle_start_container,
        .flags = 0
    },
    {
        .name = "/runtime.v1alpha2.RuntimeService/StopContainer",
        .handler = handle_stop_container,
        .flags = 0
    },
    {
        .name = "/runtime.v1alpha2.RuntimeService/RemoveContainer",
        .handler = handle_remove_container,
        .flags = 0
    },
    {
        .name = "/runtime.v1alpha2.RuntimeService/ListContainers",
        .handler = handle_list_containers,
        .flags = 0
    },
    {
        .name = "/runtime.v1alpha2.RuntimeService/ContainerStatus",
        .handler = handle_container_status,
        .flags = 0
    },
    {
        .name = "/runtime.v1alpha2.RuntimeService/UpdateContainerResources",
        .handler = handle_update_container_resources,
        .flags = 0
    }
};

// Service descriptor definition
const grpc_service_descriptor_t runtime_service_descriptor = {
    .name = "runtime.v1alpha2.RuntimeService",
    .methods = runtime_methods,
    .method_count = sizeof(runtime_methods) / sizeof(runtime_methods[0])
};

// Handler functions implementations
static void handle_version(grpc_byte_buffer* request, grpc_byte_buffer** response) {
    // Implementation will be added later
}

static void handle_create_container(grpc_byte_buffer* request, grpc_byte_buffer** response) {
    // Implementation will be added later
}

static void handle_start_container(grpc_byte_buffer* request, grpc_byte_buffer** response) {
    // Implementation will be added later
}

static void handle_stop_container(grpc_byte_buffer* request, grpc_byte_buffer** response) {
    // Implementation will be added later
}

static void handle_remove_container(grpc_byte_buffer* request, grpc_byte_buffer** response) {
    // Implementation will be added later
}

static void handle_list_containers(grpc_byte_buffer* request, grpc_byte_buffer** response) {
    // Implementation will be added later
}

static void handle_container_status(grpc_byte_buffer* request, grpc_byte_buffer** response) {
    // Implementation will be added later
}

static void handle_update_container_resources(grpc_byte_buffer* request, grpc_byte_buffer** response) {
    // Implementation will be added later
}

// Service implementation
static void runtime_service_create_pod(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__CreatePodRequest* request = unpack_message(request_buffer, 
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__create_pod_request__unpack);
    
    Runtime__V1alpha2__CreatePodResponse response = RUNTIME__V1ALPHA2__CREATE_POD_RESPONSE__INIT;
    response.pod_sandbox_id = "test-pod-id";

    *response_buffer = pack_message(&response, 
        (size_t (*)(const void*))runtime__v1alpha2__create_pod_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__create_pod_response__pack);

    if (request) {
        runtime__v1alpha2__create_pod_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_delete_pod(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__DeletePodRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__delete_pod_request__unpack);
    
    Runtime__V1alpha2__DeletePodResponse response = RUNTIME__V1ALPHA2__DELETE_POD_RESPONSE__INIT;

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__delete_pod_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__delete_pod_response__pack);

    if (request) {
        runtime__v1alpha2__delete_pod_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_list_pods(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__ListPodRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__list_pod_request__unpack);
    
    Runtime__V1alpha2__ListPodResponse response = RUNTIME__V1ALPHA2__LIST_POD_RESPONSE__INIT;

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__list_pod_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__list_pod_response__pack);

    if (request) {
        runtime__v1alpha2__list_pod_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_start_pod(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__StartPodRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__start_pod_request__unpack);
    
    Runtime__V1alpha2__StartPodResponse response = RUNTIME__V1ALPHA2__START_POD_RESPONSE__INIT;

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__start_pod_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__start_pod_response__pack);

    if (request) {
        runtime__v1alpha2__start_pod_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_stop_pod(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__StopPodRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__stop_pod_request__unpack);
    
    Runtime__V1alpha2__StopPodResponse response = RUNTIME__V1ALPHA2__STOP_POD_RESPONSE__INIT;

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__stop_pod_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__stop_pod_response__pack);

    if (request) {
        runtime__v1alpha2__stop_pod_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_create_container(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__CreateContainerRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__create_container_request__unpack);
    
    Runtime__V1alpha2__CreateContainerResponse response = RUNTIME__V1ALPHA2__CREATE_CONTAINER_RESPONSE__INIT;
    response.container_id = "test-container-id";

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__create_container_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__create_container_response__pack);

    if (request) {
        runtime__v1alpha2__create_container_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_delete_container(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__DeleteContainerRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__delete_container_request__unpack);
    
    Runtime__V1alpha2__DeleteContainerResponse response = RUNTIME__V1ALPHA2__DELETE_CONTAINER_RESPONSE__INIT;

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__delete_container_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__delete_container_response__pack);

    if (request) {
        runtime__v1alpha2__delete_container_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_list_containers(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__ListContainersRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__list_containers_request__unpack);
    
    Runtime__V1alpha2__ListContainersResponse response = RUNTIME__V1ALPHA2__LIST_CONTAINERS_RESPONSE__INIT;

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__list_containers_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__list_containers_response__pack);

    if (request) {
        runtime__v1alpha2__list_containers_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_start_container(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__StartContainerRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__start_container_request__unpack);
    
    Runtime__V1alpha2__StartContainerResponse response = RUNTIME__V1ALPHA2__START_CONTAINER_RESPONSE__INIT;

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__start_container_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__start_container_response__pack);

    if (request) {
        runtime__v1alpha2__start_container_request__free_unpacked(request, NULL);
    }
}

static void runtime_service_stop_container(grpc_byte_buffer* request_buffer, grpc_byte_buffer** response_buffer) {
    Runtime__V1alpha2__StopContainerRequest* request = unpack_message(request_buffer,
        (void* (*)(ProtobufCAllocator*, size_t, const uint8_t*))runtime__v1alpha2__stop_container_request__unpack);
    
    Runtime__V1alpha2__StopContainerResponse response = RUNTIME__V1ALPHA2__STOP_CONTAINER_RESPONSE__INIT;

    *response_buffer = pack_message(&response,
        (size_t (*)(const void*))runtime__v1alpha2__stop_container_response__get_packed_size,
        (void (*)(const void*, uint8_t*))runtime__v1alpha2__stop_container_response__pack);

    if (request) {
        runtime__v1alpha2__stop_container_request__free_unpacked(request, NULL);
    }
}

// Service descriptor
static const grpc_method_handler_t runtime_service_methods[] = {
    {
        .name = "CreatePod",
        .handler = runtime_service_create_pod,
        .flags = 0
    },
    {
        .name = "DeletePod",
        .handler = runtime_service_delete_pod,
        .flags = 0
    },
    {
        .name = "ListPods",
        .handler = runtime_service_list_pods,
        .flags = 0
    },
    {
        .name = "StartPod",
        .handler = runtime_service_start_pod,
        .flags = 0
    },
    {
        .name = "StopPod",
        .handler = runtime_service_stop_pod,
        .flags = 0
    },
    {
        .name = "CreateContainer",
        .handler = runtime_service_create_container,
        .flags = 0
    },
    {
        .name = "DeleteContainer",
        .handler = runtime_service_delete_container,
        .flags = 0
    },
    {
        .name = "ListContainers",
        .handler = runtime_service_list_containers,
        .flags = 0
    },
    {
        .name = "StartContainer",
        .handler = runtime_service_start_container,
        .flags = 0
    },
    {
        .name = "StopContainer",
        .handler = runtime_service_stop_container,
        .flags = 0
    },
};

const grpc_service_descriptor_t runtime_service_descriptor = {
    .name = "runtime.v1alpha2.RuntimeService",
    .methods = runtime_service_methods,
    .method_count = sizeof(runtime_service_methods) / sizeof(grpc_method_handler_t)
}; 