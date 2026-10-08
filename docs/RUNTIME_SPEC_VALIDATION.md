# Runtime-spec validation

The crun backend runs the runtime-spec's own validation suite,
[opencontainers/runtime-tools](https://github.com/opencontainers/runtime-tools),
in `crun_build.yml` on every push and pull request to `main` (#310). It asks
what the specification says, not only what one container engine happened to
ask.

## What runs

- runtime-tools at `8a4db579` (`RUNTIME_TOOLS_COMMIT` in
  `tests/runtime-tools/Dockerfile`), whose tests cite runtime-spec v1.3.0,
  built on top of the CI's `-crun` image.
- nexcage with the routing `*` → crun, then the image's own crun (Ubuntu's
  crun 1.21) for reference.
- A GitHub `ubuntu-24.04` runner: cgroup v2 only, AppArmor enabled. The suite
  runs in a privileged Docker container with its own cgroup namespace and a
  tmpfs on `/tmp`.

`tests/runtime-tools/validate.py` reads the suite's output, and
`tests/runtime-tools/known-failures` names every test that fails, with the
reason. The step fails on a failure the list does not name, and on a named
test that passes. A runtime whose `kill` did nothing turned it red on `kill`
and `killsig`.

The list is for that host. On a host without AppArmor,
`linux_process_apparmor_profile` passes; where `capset` is not permitted,
`process_capabilities` fails.

## Results

**nexcage passes 33 of 58 tests.** Run locally against crun 1.30.1, the
release the vendored libcrun comes from, the results were nexcage's test for
test. Ubuntu's crun 1.21, which the job runs for reference, passed 34. It
differs on three: it accepts a capability name that does not exist
(`process_capabilities_fail` fails), it logs a failing poststart hook and
carries on, as runtime-spec 1.0 said (`poststart_fail` passes), and `poststart`
is a race either way.

Passing: `config_updates_without_affect`, `create`, `default`, `hooks_stdin`,
`hostname`, `kill`, `kill_no_effect`, `killsig`, `linux_devices`,
`linux_masked_paths`, `linux_mount_label`, `linux_ns_itype`, `linux_ns_nopath`,
`linux_ns_path`, `linux_ns_path_type`, `linux_readonly_paths`,
`linux_rootfs_propagation`, `linux_seccomp`, `linux_sysctl`,
`linux_uid_mappings`, `mounts`, `poststop`, `poststop_fail`, `prestart_fail`,
`process`, `process_capabilities`, `process_capabilities_fail`,
`process_oom_score_adj`, `process_rlimits_fail`, `process_user`,
`root_readonly_true`, `start`, `state`.

## The 25 that fail, and why

None of them is nexcage's code: each fails with crun run directly, 1.30.1 or
1.21. Each test's own reason is in `tests/runtime-tools/known-failures`.

**The suite cannot read cgroup v2 (10).** Its cgroup v2 reader is
unimplemented (`cgroups/cgroups_v2.go` answers "unimplemented yet"), and
these tests look for v1 hierarchies: `delete_only_create_resources`,
`delete_resources`, `linux_cgroups_cpus`, `linux_cgroups_devices`,
`linux_cgroups_hugetlb`, `linux_cgroups_pids` and the `relative_` variants
of cpus, devices, hugetlb and pids.

**cgroup v1 settings, refused by name (6).** `linux_cgroups_blkio`
(`leafWeight`), `linux_cgroups_memory` (kernel memory, deprecated by the spec)
and `linux_cgroups_network` (`classID`, priorities), each with its `relative_`
variant, ask for settings cgroup v2 does not have. libcrun refuses each one
with a message naming it, which is what the spec asks of a runtime that
cannot apply a value.

**The tests contradict runtime-spec 1.3.0, or themselves (7).**

- `prestart` expects prestart hooks to run at `start`; 1.3.0 says they MUST be
  called as part of `create`.
- `poststart_fail` expects a failing poststart hook to be logged and ignored,
  as runtime-spec 1.0 said; 1.3.0's lifecycle says it MUST be an error that
  stops the container.
- `hooks` expects `post-start1` where its own hook writes `post-start1 called`,
  so no runtime can pass it.
- `poststart` races: the container's process and the hook append to one file
  at once, and the test wants the process's line first. It passed 1 run in 20
  against nexcage and 7 in 20 against crun 1.30.1. Its result is printed and
  not checked (`~poststart` in the list).
- `pidfile` kills a container whose process, `true`, has already exited, and a
  runtime must refuse to signal a stopped container.
- `misc_props` runs `/runtimetest` in a bundle it never copied it into.
- `process_rlimits` reads the limits from a Go program, and Go raises its own
  soft `RLIMIT_NOFILE` at startup.

**libcrun does what runc does (1).** `delete` expects `delete` of a container
in the `created` state, without `--force`, to fail. libcrun and runc delete it.

**The host (1).** `linux_process_apparmor_profile` needs a profile named
`acme_secure_profile` loaded on the host.

## What it does not show

Whether the limits in `config.json` reach the container's cgroup on a cgroup
v2 host: the 16 tests that would say are the ones above that cannot read v2 or
ask for v1. The pod test through containerd's CRI checks one limit, from the
other side: `crictl update --memory` lands in the container's `memory.max`.
`nexcage update`'s own flags on the crun backend (`--memory`, `--cpu-quota`,
...) are not checked against a cgroup anywhere yet (#359).

## Running it

```bash
docker build --build-arg BUILD_FLAGS=-Denable-backend-crun=true -t nexcage:ci .
docker build -f tests/runtime-tools/Dockerfile -t nexcage:runtime-tools tests/runtime-tools
docker run --rm --privileged --cgroupns=private \
  -v "$PWD/tests/runtime-tools:/t:ro" nexcage:runtime-tools /t/run.sh
```

After bumping the vendored libcrun or `RUNTIME_TOOLS_COMMIT`, the step names
every test whose result changed. Take a test that passes now off the list;
add one that fails with the reason, after finding it.
