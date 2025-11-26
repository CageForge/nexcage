#!/usr/bin/env bash
set -euo pipefail

# Build static site into site/

docker run --rm -it \
  -v "$(pwd)":/docs \
  squidfunk/mkdocs-material:9.5.35 \
  mkdocs build --strict


