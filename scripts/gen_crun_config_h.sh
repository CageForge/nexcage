#!/usr/bin/env bash
set -euo pipefail

# Generate a minimal config.h for vendored crun/libcrun build
# This is a conservative stub; proper values should come from upstream configure/meson.

OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/deps/crun"
OUT_FILE="$OUT_DIR/config.h"

mkdir -p "$OUT_DIR"

cat > "$OUT_FILE" << 'EOF'
/* Minimal config.h for vendored libcrun (generated) */
#pragma once

/* Toolchain/features */
#define HAVE_DLFCN_H 1
#define HAVE_ERR_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_MEMORY_H 1
#define HAVE_PTHREAD 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1

/* Optional subsystems (disabled by default) */
#undef HAVE_SYSTEMD
#undef HAVE_SECCOMP
#undef HAVE_APPARMOR
#undef HAVE_SELINUX
#undef HAVE_BPF

/* JSON backend */
#define HAVE_YAJL 1

/* General macros */
#define PACKAGE_NAME "libcrun"
#define PACKAGE_VERSION "vendored"
#define PACKAGE_STRING PACKAGE_NAME " " PACKAGE_VERSION

/* GNU extensions */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

/* End of generated config.h */
EOF

echo "[gen-config] Wrote $OUT_FILE"

