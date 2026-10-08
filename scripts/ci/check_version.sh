#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
cd "$ROOT_DIR"

if [[ ! -f VERSION ]]; then
  echo "VERSION file not found" >&2
  exit 1
fi

VERSION=$(tr -d '\n\r' < VERSION)
if [[ -z "$VERSION" ]]; then
  echo "VERSION file is empty" >&2
  exit 1
fi

# Verify semver format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION '$VERSION' is not valid semver (MAJOR.MINOR.PATCH)" >&2
  exit 1
fi

echo "Detected version: $VERSION"

# build.zig.zon carries the version too, for anything that reads the package
# manifest. Nothing in the build does, which is how it stayed at 0.9.0 through
# four releases.
ZON_VERSION=$(sed -n 's/^[[:space:]]*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' build.zig.zon)
if [[ "$ZON_VERSION" != "$VERSION" ]]; then
  echo "build.zig.zon says version '$ZON_VERSION', VERSION says '$VERSION'" >&2
  exit 1
fi

# Build should embed version; quick compile test
zig version >/dev/null
zig build >/dev/null

# Optional: verify binary reports version in help output without causing SIGPIPE
HELP_OUTPUT=$(./zig-out/bin/nexcage --help || true)
if echo "$HELP_OUTPUT" | grep -q "$VERSION"; then
  echo "Help output contains version $VERSION"
else
  echo "Help output does not contain version $VERSION" >&2
  exit 1
fi


