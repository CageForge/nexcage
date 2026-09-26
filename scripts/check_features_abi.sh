#!/bin/sh
# The features document is read through a hand-written Zig mirror of crun's
# `struct features_info_s` and `struct linux_info_s` (src/backends/crun/
# libcrun_ffi.zig). A hand-written mirror is only correct for the layout it was
# written against, and the vendored crun is a fork that moves: it already
# carries a field upstream does not have, `memory_policy` at the end of
# linux_info_s. Reading the wrong layout does not fail to compile — it puts
# every field after the divergence at the wrong offset, which is a segfault on
# the first pointer dereferenced, or worse, a features document full of
# plausible rubbish that a kubelet believes.
#
# So this compares the field order in the vendored header against what the
# mirror was written for, and fails loudly when the submodule pin moves.
#
# Run it where deps/crun is checked out: the Dockerfile's builder stage.
set -eu

HEADER=${1:-deps/crun/src/libcrun/container.h}
MIRROR=src/backends/crun/libcrun_ffi.zig

[ -r "$HEADER" ] || { echo "no vendored header at $HEADER" >&2; exit 1; }
[ -r "$MIRROR" ] || { echo "no mirror at $MIRROR" >&2; exit 1; }

# The last identifier before each `;` of a struct body, in order.
fields() {
    sed -n "/^struct $2\$/,/^};/p" "$1" |
        sed -n 's/^  .*[ *]\([A-Za-z_][A-Za-z0-9_]*\);$/\1/p' |
        tr '\n' ' ' |
        sed 's/ *$//'
}

expect_features="oci_version_min oci_version_max hooks mount_options linux annotations potentially_unsafe_annotations"
expect_linux="namespaces capabilities cgroup seccomp apparmor selinux mount_ext intel_rdt net_devices memory_policy"
expect_annotations="io_github_seccomp_libseccomp_version run_oci_crun_checkpoint_enabled run_oci_crun_commit run_oci_crun_version run_oci_crun_wasm"
expect_seccomp="enabled actions operators archs"
expect_cgroup="v1 v2 systemd systemd_user"

status=0
for pair in \
    "features_info_s:$expect_features" \
    "linux_info_s:$expect_linux" \
    "annotations_info_s:$expect_annotations" \
    "seccomp_info_s:$expect_seccomp" \
    "cgroup_info_s:$expect_cgroup"
do
    name=${pair%%:*}
    want=${pair#*:}
    got=$(fields "$HEADER" "$name")
    if [ "$got" != "$want" ]; then
        echo "ABI drift in struct $name:" >&2
        echo "  vendored header: $got" >&2
        echo "  the Zig mirror was written for: $want" >&2
        status=1
    else
        echo "ok  struct $name"
    fi
done

if [ "$status" -ne 0 ]; then
    cat >&2 <<'MSG'

deps/crun has moved and src/backends/crun/libcrun_ffi.zig no longer describes
it. Update the extern structs there to the header above, update the expected
lists in this script, and check whether featuresJson should emit the new
fields -- then this passes again.
MSG
    exit 1
fi

echo "features ABI matches the vendored header"
