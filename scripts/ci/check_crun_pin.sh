#!/bin/sh
# The crun a release is built from is the crun this repository pins.
#
# The deps/crun submodule's commit is what a developer builds against and what
# dependency_check.yml reads to file or close its crun issue. The Dockerfile,
# which builds every release binary, .deb and CI image, clones crun by a hash
# of its own, because .dockerignore keeps .git out of the build. Nothing
# compared the two: a bump of the submodule for a crun fix that missed the
# Dockerfile would close the issue and keep shipping the old libcrun.
#
# Usage: scripts/ci/check_crun_pin.sh [path to Dockerfile]
set -eu

DOCKERFILE=$(realpath "${1:-Dockerfile}")
cd "$(git rev-parse --show-toplevel)"

entry=$(git ls-tree HEAD -- deps/crun)
if [ "$(echo "$entry" | awk '{print $2}')" != commit ]; then
    echo "check_crun_pin.sh: deps/crun is not a submodule at HEAD" >&2
    exit 1
fi
pin=$(echo "$entry" | awk '{print $3}')

built=$(sed -n 's/^.*git -C deps\/crun checkout -q \([0-9a-f]\{40\}\)\([^0-9a-f].*\)\{0,1\}$/\1/p' "$DOCKERFILE")
case "$(printf '%s\n' "$built" | grep -c .)" in
    1) ;;
    0) echo "check_crun_pin.sh: $DOCKERFILE has no 'git -C deps/crun checkout -q <40-hex sha>' line" >&2; exit 1 ;;
    *) echo "check_crun_pin.sh: $DOCKERFILE checks out crun more than once: $(echo "$built" | tr "\n" " ")" >&2; exit 1 ;;
esac

if [ "$built" != "$pin" ]; then
    echo "check_crun_pin.sh: deps/crun pins $pin but $DOCKERFILE builds crun $built" >&2
    echo "check_crun_pin.sh: change both together (docs/DEVELOPMENT_WORKFLOW.md, \"Updating the vendored crun\")" >&2
    exit 1
fi
echo "ok: the Dockerfile builds crun $pin, the commit deps/crun pins"
