#!/bin/bash

# Створюємо директорії для згенерованих файлів
mkdir -p src/grpc/proto

# Генеруємо C++ файли
protoc -I. \
    --cpp_out=src/grpc/proto \
    --grpc_out=src/grpc/proto \
    --plugin=protoc-gen-grpc=`which grpc_cpp_plugin` \
    runtime_service.proto

# Генеруємо C файли
protoc-c -I. \
    --c_out=src/grpc/proto \
    runtime_service.proto 