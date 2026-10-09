# nexcage 0.17.0

**One binary, both backends.** The release's binary manages Proxmox LXC
containers and is the OCI runtime a container engine drives, with the crun
backend built in. The `.deb` installs it with the libraries it needs.

**A pod can run under an isolation profile.** The node's administrator names,
in the configuration file, what a container may not exceed. An engine's
`RuntimeClass` picks a profile by the handler's program name,
`nexcage@<profile>`. On a k3s node, two pods under two profiles were checked
from inside each pod.

**Read "Upgrading" before you install.** The configuration file now fails
closed, so a file that loaded under 0.16.0 can be refused.

## One release: one binary, one `.deb` (#380)

From 0.11.2 to 0.16.0 a release carried two binaries:
- `nexcage-<version>-amd64`, with Proxmox LXC only, which the `.deb` packed;
- `nexcage-<version>-amd64-crun`, with the crun backend too.

So an engine configuration or an isolation profile next to the `.deb` pointed
at a backend the installed binary did not have.

Now there is **one binary with both backends**, and **one `.deb` that packs
it**:
- Its `Depends` pulls `libjson-c5`, `libseccomp2`, `libcap2` and
  `libsystemd0`, so `apt install ./nexcage-0.17.0-amd64.deb` is the whole
  setup, for the command line and for a container engine alike.
- The package ships `config.oci.example.json` next to `config.json`.
- The node configurations in `deploy/kubernetes/node/` name
  `/usr/bin/nexcage`, where the package puts the binary.

Before it publishes, the release installs the `.deb` in a clean Debian 13
container and asks the crun backend for `features`. `crun_build.yml` does the
same on every pull request, and `k8s_e2e.yml` installs the `.deb` on the E2E
node to run its pods. The `.deb`'s copyright file names the licenses of
libcrun (LGPL-2.1-or-later) and libocispec, which the binary carries.

Thanks to @IhorTelepenko, whose #301 started this.

## Isolation profiles

```json
{ "profiles": {
    "hardened": { "runtime": "crun", "crun": {
      "user_namespace": "require",
      "seccomp": "require",
      "capabilities": { "drop": ["CAP_NET_RAW", "CAP_MKNOD", "CAP_SYS_CHROOT"] },
      "limits": { "memory": "1G", "pids": 1024 } } } } }
```

`create` applies a profile to the bundle before libcrun sees it.

- **Requirements** refuse a bundle that lacks them:
  - a user namespace with uid and gid mappings (`hostUsers: false` on the pod);
  - a seccomp filter (`seccompProfile.type: RuntimeDefault`).
- **Capabilities** are dropped from every set of the process. That includes
  `exec`: containerd builds `kubectl exec`'s process from its own copy of the
  spec, from before the profile narrowed it. An exec'd process is cut to the
  container's bounding set.
- **Memory and pids limits** are lowered to the profile's, and set where the
  bundle has none. The bundle's swap allowance is kept: containerd's
  `swap = limit`, which means no swap, still means no swap.

A profile only takes away: it never adds a capability or raises a limit.

**Naming a profile.**
- An engine names one by the program name, `nexcage@<profile>`: a symlink used
  as containerd's `BinaryName` or CRI-O's `runtime_path`.
- A person uses `--profile <name>`.
- Only `create` reads a profile. Every later command finds the container
  without it.
- `state` reports the profile as the annotation `io.cageforge.nexcage.profile`.

**Refusals.** These exit 2 and create nothing:
- a profile the file does not define;
- `--profile` and the program name naming different profiles;
- a `--runtime` that disagrees with the profile;
- `run` given a profile;
- a bundle the profile refuses;
- a bundle that carries the profile annotation itself, with a profile or
  without.

`packaging/config/config.oci.example.json` now defines two profiles,
`hardened` and `small`.
[INSTALL.md](https://github.com/CageForge/nexcage/blob/v0.17.0/docs/INSTALL.md#an-isolation-profile-per-runtimeclass-since-0170)
shows the symlink, the k3s handler and the `RuntimeClass` for each, and
[CLI_REFERENCE.md](https://github.com/CageForge/nexcage/blob/v0.17.0/docs/CLI_REFERENCE.md#isolation-profiles)
the keys.

### Checked from inside the container, not from nexcage's log

`tests/k8s/pod_on_node.sh` on the E2E node (k3s v1.36.5) runs one pod under
each of two classes:

| | `nexcage-hardened` | `nexcage-small` |
|---|---|---|
| `uid_map` | a user namespace | the host's, `0 0 4294967295` |
| `Seccomp` of pid 1 | 2 | 2 |
| `CapBnd` of pid 1 and of a `kubectl exec` | no NET_RAW, SYS_CHROOT, MKNOD | no NET_RAW |
| `memory.max` | 1073741824 (the pod asked for 2Gi) | 268435456 (the pod set none) |
| `pids.max` | 1024 | 256 |

A third pod under `nexcage-hardened` without `hostUsers: false` is refused,
and its events say "requires a user namespace".

`tests/crun/profile.sh` runs in `crun_build.yml` on every push. It checks the
same on a bundle, through `exec --process` and through cgroup v2's
`memory.swap.max`.

## The configuration file fails closed (#371)

A key nexcage does not read, a value of the wrong type, and a runtime or log
level it does not know all refuse the file. The message names the file and the
key, nothing runs, and the exit status is 1.

Under 0.16.0:
- a misspelt runtime in a routing rule sent containers to LXC without a word;
- `{"runtime": 5}` crashed every command, `--help` included;
- `"security": {"seccomp": true}` turned nothing on.

The keys that remain are the README's table, plus `profiles`.

## A container's backend comes from the container (#372)

Every command used to choose its backend from the routing rules again, so a
rule changed after `create` sent `state`, `kill` or `delete` to the other
backend. Routing now decides only for `create` and `run`. Every other command
goes to the backend that has the container. `--runtime lxc` for a container on
the crun backend exits 2 instead of being obeyed.

## Fixed

- **`--config`, `--root` and `--runtime` were read after `--`.** That made
  `nexcage exec web-1 -- grep --config x` load `x` as nexcage's configuration.
  Words after `--` belong to the command `exec` runs.
- **`exec`'s temporary process file** has a predictable name in `/tmp`. It was
  opened with truncate, so on a host with `fs.protected_symlinks` off, a
  symlink left there would have been followed. It is now created exclusively,
  mode 0600.

## Not in this release

**A pod as a Proxmox LXC container (#316).**
[ADR-006](https://github.com/CageForge/nexcage/blob/v0.17.0/docs/architecture/ADR-006-LXC-Driven-By-An-Engine.md)
records what a probe on the E2E node (Proxmox VE 9.2.20) showed. It can be
done:
- `lxc-execute` passes its stdio to the container and exits with its status;
- `--share-net` joins CNI's namespace;
- `pct list` shows the container.

Its costs fall on every pod:
- the sandbox stays on crun;
- every create goes through Proxmox's perl internals and pmxcfs;
- the container is privileged;
- its cgroups are outside the kubelet's.

All it would add is visibility in `pct list`. A profile with
`"runtime": "lxc"` keeps refusing the file.

## Upgrading from 0.16.0

1. **Check the configuration before you replace the binary.** Run the new
   binary against your file:

   ```bash
   ./nexcage-0.17.0-amd64 --config /etc/nexcage/config.json version
   ```

   - It prints the version if the file loads.
   - If it does not, it names the file and the key to remove or fix, and exits
     1.
   - The keys 0.16.0 parsed and never used are refused like misspelt ones:
     `runtime_type`, `default_runtime`, `runtime.root_path`, `data_dir`,
     `cache_dir`, `temp_dir`, `network.ip`, `network.gateway`, `security`,
     `resources`, `container_config.default_container_type`, and `pct_path`,
     `node` and `legacy_api` under `proxmox`.
   - `container_config.crun_name_patterns` is refused, with
     `runtime.routing` named as its replacement.
2. **There is no `-crun` asset.** A script that downloads
   `nexcage-<version>-amd64-crun` has to drop the suffix: `nexcage-0.17.0-amd64`
   is that build now.
3. Install the `.deb`: `apt install ./nexcage-0.17.0-amd64.deb`.
4. **A node set up from 0.16.0's instructions** has the `-crun` binary at
   `/usr/local/bin/nexcage`, and its engine names that path. The `.deb` puts
   nexcage at `/usr/bin/nexcage`. Either change `BinaryName` (or CRI-O's
   `runtime_path`) to `/usr/bin/nexcage` and restart the engine, then remove
   `/usr/local/bin/nexcage`, or leave the engine as it is and replace
   `/usr/local/bin/nexcage` with the new binary. Do not leave two different
   versions installed.
5. Profiles are optional. A file without `profiles` behaves as before.
