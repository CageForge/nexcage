#!/bin/bash
set -e

# Check for required tools
PROTOC=$(which protoc)
if [ -z "$PROTOC" ]; then
  echo "Error: protoc not found"
  exit 1
fi

GRPC_PLUGIN=$(which grpc_cpp_plugin)
if [ -z "$GRPC_PLUGIN" ]; then
  echo "Error: grpc_cpp_plugin not found"
  exit 1
fi

PROTOBUFC_PLUGIN=$(which protoc-gen-c)
if [ -z "$PROTOBUFC_PLUGIN" ]; then
  echo "Error: protoc-gen-c not found"
  exit 1
fi

# Create output directories
echo "Creating output directories..."
mkdir -p src/grpc/proto

# Generate protobuf and gRPC code
echo "Generating protobuf and gRPC code..."
echo "Using protoc: $PROTOC"
echo "Using gRPC plugin: $GRPC_PLUGIN"
echo "Using protobuf-c plugin: $PROTOBUFC_PLUGIN"

$PROTOC \
  --cpp_out=src/grpc/proto \
  --grpc_out=src/grpc/proto \
  --c_out=src/grpc/proto \
  --plugin=protoc-gen-grpc="$GRPC_PLUGIN" \
  --plugin=protoc-gen-c="$PROTOBUFC_PLUGIN" \
  -I. \
  proto/runtime_service.proto

# Check if files were generated
if [ ! -f src/grpc/proto/runtime_service.grpc.pb.h ] || \
   [ ! -f src/grpc/proto/runtime_service.pb.h ] || \
   [ ! -f src/grpc/proto/runtime_service.grpc.pb.cc ] || \
   [ ! -f src/grpc/proto/runtime_service.pb.cc ] || \
   [ ! -f src/grpc/proto/runtime_service.pb-c.h ] || \
   [ ! -f src/grpc/proto/runtime_service.pb-c.c ]; then
  echo "Error: Code generation failed"
  exit 1
fi

echo "Done!" 