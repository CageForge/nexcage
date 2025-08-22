#!/bin/bash

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed"
    exit 1
fi

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo "Error: Dockerfile.build not found"
    exit 1
fi

# Build the builder image
echo "Building builder image..."
docker build -t proxmox-lxcri-builder -f Dockerfile .

# Run the build container
echo "Starting project build..."
docker run --rm -v $(pwd):/build proxmox-lxcri-builder

# Check build result
if [ $? -eq 0 ]; then
    echo "Build completed successfully!"
else
    echo "Error during build!"
    exit 1
fi
 