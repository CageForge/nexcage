#!/usr/bin/env bash
# The tests of the shell scripts in scripts/: every other *.sh here, each run
# on its own. Each prints ok/FAIL lines and exits non-zero on a failure.
#
#   bash tests/scripts/run.sh
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
failed=0
for t in "$DIR"/*.sh; do
  [ "$t" = "$DIR/run.sh" ] && continue
  echo "== ${t#"$DIR"/}"
  bash "$t" || failed=1
done
[ "$failed" = 0 ] && echo "all script tests passed" || echo "script tests failed"
exit "$failed"
