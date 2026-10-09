# nexcage 0.14.1

**`exec --user 1000` on Proxmox LXC ran the command as root.** This release
refuses that and every other flag `run` and `exec` accepted there and then
dropped. It also has three smaller fixes: an explicit `--log-level info`,
`health`'s idea of the configuration, and how CI installs Zig.

## Refused rather than ignored

nexcage's rule since 0.10.0 is that a flag it cannot honour is refused by
name: a caller that is told no can do something else, and one that is ignored
believes something false. 0.14.0's documentation pass found two commands that
broke it on the Proxmox LXC backend.

**`exec`** passed `--user`, `--cwd`, `--console-socket` and `--pid-file` to
the crun backend only. On Proxmox LXC it runs `pct exec`, which takes a
command and nothing else. The command runs as root, in a directory nexcage
does not choose, and no pty or pid comes back. So a caller asking for uid 1000
got root without a word. These flags now exit 1, naming the flag, as
`--process` and `--detach` already did:

```
$ nexcage exec --user 1000 web-1 id; echo "exit $?"
[1791452028] ERROR nexcage: --user is not possible on the Proxmox LXC backend: pct exec takes a command and nothing else, and runs it as root. Use --runtime crun
nexcage: exec: not supported on this host or by this build
exit 1
```

`--tty` is honoured when nexcage runs on a terminal. `pct exec` runs
`lxc-attach`, which gives the command a terminal whenever one of its standard
descriptors is one. When none is, nothing can give the command a terminal, so
`--tty` is refused.

**`run`** dropped `--node`, `--console-socket` and `--pid-file`. `run --node
titan` made the container on this host. All three are refused now, before
anything is created. To make a container on another node, use `create --node
titan`, then `start`.

If a script relied on the old silence, it now sees the refusal. On this
backend the flags never did what they said.

## Fixed

- **`--log-level info` and `NEXCAGE_LOG_LEVEL=info` now override the
  configuration file.** An explicit `info` used to be taken for "not set", so
  a file saying `debug` could not be turned back down for one command. A level
  that is named wins over the file's, and takes the `[DEBUG]` lines the file's
  `debug` turned on with it. `--debug` and `NEXCAGE_DEBUG` still keep them.
- **`health` reports the configuration file the commands read**: the one
  `--config` names, else the first of `./config.json`,
  `/etc/nexcage/config.json` and `/etc/nexcage/nexcage.json`. It used to look
  at a pair of files of its own, whatever `--config` said. It no longer runs
  `nslookup google.com`: nexcage resolves no names itself, and a root tool on
  an air-gapped cluster should not query an outside host to warn about
  nothing.

## CI

Zig comes from `mlugg/setup-zig`, pinned by commit, instead of
`goto-bus-stop/setup-zig`, whose README calls it unmaintained. The Proxmox E2E
on `main` failed in that step before any test ran. On the self-hosted runners
Zig now stays in the runner's tool cache. The release workflow builds without
the Zig cache, from the tagged tree alone.

## Upgrading from 0.14.0

Install and carry on. A script that passes `--user`, `--cwd`,
`--console-socket` or `--pid-file` to `exec`, or `--node` to `run`, on the
Proxmox LXC backend now gets exit 1 instead of a command that did something
else.
