#!/bin/bash

# Створюємо директорії для згенерованого коду
mkdir -p include
mkdir -p src/grpc/proto

# Генеруємо код з proto файлу
protoc \
    --cpp_out=include \
    --grpc_out=include \
    --plugin=protoc-gen-grpc=`which grpc_cpp_plugin` \
    proto/runtime_service.proto

# Копіюємо згенеровані файли в src/grpc/proto
cp include/runtime_service.grpc.pb.cc src/grpc/proto/
cp include/runtime_service.pb.cc src/grpc/proto/ 