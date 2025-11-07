#!/usr/bin/env bash
set -euo pipefail

# Build static site into site/

docker run --rm -it \
  -v "$(pwd)":/docs \
  --entrypoint sh \
  squidfunk/mkdocs-material:9.5.35 \
  -c "pip install --no-cache-dir mike && mkdocs build --strict"


