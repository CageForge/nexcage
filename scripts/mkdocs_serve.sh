#!/usr/bin/env bash
set -euo pipefail

# Serve mkdocs locally using Docker (material theme)
# Usage: ./scripts/mkdocs_serve.sh [PORT]

PORT=${1:-8000}

docker run --rm -it \
  -p "$PORT:8000" \
  -v "$(pwd)":/docs \
  --entrypoint sh \
  squidfunk/mkdocs-material:9.5.35 \
  -c "pip install --no-cache-dir mike && mkdocs serve -a 0.0.0.0:8000"


