# nexcage 0.15.0

`create` takes what `pct create` is usually given, and an option nexcage does
not know is refused by name instead of skipped.

## Read this first if you script nexcage

**A misspelt or unsupported option now fails with exit 2.** Until this release
an option no command took was skipped without a word, and its value became the
next positional word:

```
$ nexcage create --name typo-1 --memroy 2G local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
nexcage: unknown option '--memroy' for 'create'; see 'nexcage create --help'
nexcage: invalid input
```

0.14.1 answered the same line with "OCI bundle '2G' must be an absolute path".
An unknown option without a value was worse: `kill --al web-1` signalled the
init alone and exited 0. If a script passed an option nexcage never
implemented, it now stops there.

Container engines are not affected. Every option containerd, CRI-O and podman
were seen sending already had its own branch, and the CI's pod through
containerd's CRI runs unchanged. runc options nexcage does not implement
(`--no-pivot`, `--preserve-fds`, ...) are refused rather than dropped, since
dropping one would run the container differently from what was asked.

`create --image <image>`, the form `create --help` shows, had only worked
because `--image` was skipped and its value taken for the image. It is parsed
now.

## create takes what pct create is usually given

```bash
nexcage create --name db-1 --memory 4G --cores 2 --ip 10.0.0.5/24 --gw 10.0.0.1 \
  --vlan 20 --onboot --mp local-lvm:20,mp=/var/lib/postgresql \
  local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
```

Before this release, everything past the name and image took a `pct set` by
VMID afterwards, outside nexcage. Now:

| Option | pct |
|---|---|
| `--memory`, `--memory-swap`, `--cpu-quota`/`--cpu-period`, `--cpu-share` | `memory`, `swap`, `cpulimit`, `cpuunits`: `update`'s names and units, converted the way `update` converts them |
| `--cores` | `cores` |
| `--ip`, `--gw`, `--vlan`, `--firewall` | `net0`'s `ip=`, `gw=`, `tag=`, `firewall=1` |
| `--onboot`, `--tags` | `onboot 1`, `tags` |
| `--mp <spec>`, repeatable | `mp0`, `mp1`, ..., in pct's own syntax |

They go through `pct create` for a container here and through the node's API
for one made with `--node`. The Proxmox E2E creates a container with every one
of them and reads each back from `pct config`.

**Refused rather than half-done:**
- a limit Proxmox has no setting for, as `update` refuses it;
- an address containing `,` or `=`, which would add a `net0` key;
- a VLAN outside 1-4094;
- `--mp` with an OCI bundle, whose mounts take the `mp` entries;
- all of them on the crun backend, which takes limits, network and mounts from
  the bundle's `config.json`.

## Not in this release

**Private registries (#309)** moved to 0.16.0. Proxmox's `oci-registry-pull`
still takes no credentials. But it pulls with `skopeo copy` as root, and skopeo
reads the containers auth file, so a `skopeo login` on each node may be all it
takes. That is to be checked on a real node before anything is built. The
issue has what was found and how to check it.

## Upgrading from 0.14.1

- Install and carry on.
- A script passing an option nexcage does not take now exits 2, naming the
  option. Remove the option, or spell it as `--help` shows.
