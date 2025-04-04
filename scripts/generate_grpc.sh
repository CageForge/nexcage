#!/bin/bash
set -e

# Create output directories if they don't exist
echo "Creating output directories..."
mkdir -p include
mkdir -p src/grpc

# Generate gRPC code
echo "Generating gRPC code..."
GRPC_PLUGIN=$(which grpc_cpp_plugin)
if [ -z "$GRPC_PLUGIN" ]; then
  echo "Error: grpc_cpp_plugin not found"
  exit 1
fi

echo "Using gRPC plugin: $GRPC_PLUGIN"
protoc \
  --cpp_out=src/grpc \
  --grpc_out=src/grpc \
  --plugin=protoc-gen-grpc="$GRPC_PLUGIN" \
  -I. \
  proto/runtime_service.proto

# Check if files were generated
if [ ! -f src/grpc/proto/runtime_service.grpc.pb.h ] || [ ! -f src/grpc/proto/runtime_service.pb.h ]; then
  echo "Error: gRPC code generation failed"
  exit 1
fi

# Copy header files to include directory
echo "Copying header files to include directory..."
cp src/grpc/proto/runtime_service.grpc.pb.h include/
cp src/grpc/proto/runtime_service.pb.h include/

echo "Done!" 