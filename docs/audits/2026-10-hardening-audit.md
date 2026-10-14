# The 2026-10 hardening audit

An audit of nexcage 0.17.0 for security and robustness, and the fixes that
came out of it, from 2026-10-10 to 2026-10-14. It found 77 defects: 2
critical, 6 high, 26 medium, 33 low and 10 of no direct consequence (info).
71 are fixed on the branches below, 3 partly, and 3 wait for steps only the
maintainer can take in GitHub's settings and on a machine.

What nexcage trusts and refuses after this work is
[ADR-003](../architecture/ADR-003-Security-Architecture.md); what each
execution mode isolates is [ISOLATION.md](../architecture/ISOLATION.md).

## Scope

- **Audited:** the tree at `8d373127`, which is `origin/main` at v0.17.0:
  `src/`, the bundle parser in `deps/oci-spec-zig`, `build.zig`, the
  `Dockerfile`, packaging, the Kubernetes node configurations in
  `deploy/kubernetes/node/`, the workflows and scripts, and the security
  claims in `docs/`. The vendored libcrun was read where nexcage drives it:
  `deps/crun` at 7d6f6955, which is crun 1.30.1 unchanged. GitHub's
  repository settings were read, never changed.
- **Not audited:** libcrun beyond the paths nexcage uses, Proxmox VE's own
  code, the kernel, and the E2E and build machines, which were not touched.
- **The fixes** are a stack of branches, each on the one before:
  `pr/crun-isolation` → `pr/config-cli` → `pr/proxmox-lxc` →
  `pr/ci-supply-chain` → `pr/cleanup` (dead code) → `pr/docs` (this report,
  ADR-003, ISOLATION.md). The commits in the table are on that stack.

## Method

1. **A map first.** One pass over the base commit wrote down every
   component, every input and where it is read, every privileged operation
   (each external program and which input fills which argument, each host
   path, each direct system call, each libcrun entry point), the trust
   boundaries, and what each bundle field becomes on each backend. The
   finders worked from it.
2. **Seventeen finders**, each with one lens: the CLI entry and argv; the
   configuration and profiles; the Proxmox client; the LXC driver; images
   and storage; the crun driver; core utilities; the command lifecycle;
   taint (untrusted data to privileged use); concurrency; memory safety;
   isolation; architecture hygiene; documentation claims; CI and the supply
   chain; and two that ran hostile inputs rather than read code:
   `dynamic-lxc`, against the simulator's fake Proxmox tools
   (`tests/sim/`), and `dynamic-crun`, against the crun backend in a
   privileged podman container. 119 reports came back, 69 of them distinct.
3. **Adversarial verification, scaled by severity.** A critical or high
   finding went to three verifiers -- one to reproduce it, one to refute it,
   one to exploit it -- and to a judge where they disagreed; a medium one to
   two (reproduce, refute), and a third when the finder had rated it higher;
   a low or info one to one. 121 of the 133 verdicts ran the scenario rather
   than reasoning about it. None of the 69 was rejected. Of all 77, 15 ended
   rated lower than their finder had rated them, and 6 higher.
4. **A gap round.** Three assignments went where no finder had looked:
   where a crun container's cgroup lands under a real engine, what `exec`
   hands a container of the caller's environment, and libcrun's
   re-execution at load time. They gave G001 to G008.
5. **Fix units.** Ten units, by area of code (see "Units" below), fixed the
   findings. Every test or check a unit added had to be seen to fail first:
   red on the base commit or on a mutant of the fix, then green, with the
   output quoted in the commit message. An independent reviewer read each
   unit, for up to three rounds. Eight units ended approved; the last review
   of two (`cli-config-core`, `lxc-bundle`) asked for one more change, which
   the integrator checked was made (c7215b49, 9f4b4492). Dead code
   (`pr/cleanup`) and documentation (`pr/docs`) came after.
6. **Integration.** The units were merged into the themed branches. Logic
   two units had written twice was made one: the NUL and depth walk of a
   document (54de5d9a), the quoting of bundle text in a refusal (df7d7279,
   aec99111), the 16 MiB memory floor (631b93f2). Where two units' changes
   met, a commit of its own fixed the meeting (for example 2e60026c, d202e34e,
   6e16520a, 7c84e2f9).
7. **Integration verification**, two rounds of four verifiers on the merged
   tree: **gates** (unit tests, the simulator as a user and as root under
   `act`, every crun check in a container, the CRI pod and critest, the
   `.deb` on Debian 13, zizmor, Trivy, shellcheck); **re-attack**, which ran
   the scenario of every critical, high and medium finding again, with
   variants of its own, against the integrated binary; **cross-review**, for
   what two units' changes did together; and **compatibility**, against
   0.17.0 and against crun itself, through containerd, `ctr`, CRI and
   podman. The second round's gates: `zig build test` 342/342, the
   simulator 528/0 as a user and as root, every crun check passing, critest
   110 passed, 10 failed, 22 skipped of 142, the same spec for spec as crun.
   What the verifiers found was fixed on the stack (for example 0c3c9057,
   038c5699, d1161dad, bbc024ef, a2ad2518, b6c6af29) or is an open item
   below.

### Units

| Unit | Findings | Commits | Review rounds, verdict |
|---|---|---|---|
| crun-profile | F002 F007 F019 F020 F021 F028 F058 | 17 | 3, approved |
| crun-driver | F004 F006 F014 F045 F061 G004 G005 | 16 | 3, approved |
| systemd-cgroup | G001 G002 | 2 | 1, approved |
| cli-config-core | F005 F018 F034 F036 F037 F038 F042 F043 F044 F062 F063 | 24 | 3, one change asked, made in c7215b49 |
| lxc-bundle | F001 F009 F010 F024 F025 F026 F027, and F066 with F001 | 23 | 3, one change asked, made in 9f4b4492 |
| lxc-resources | F011 F041 F046 | 3 | 1, approved |
| lxc-identity-routing | F008 F016 F017 F022 F029 F030 F040 | 18 | 3, approved |
| lxc-images | F012 F013 F039 | 10 | 3, approved |
| lxc-lifecycle | F023 F031 F048 F049 G003 | 12 | 3, approved |
| ci-supply-chain | F003 F032 F033 F050 F051 F052 F053 F054 F055 F056 F057 F064 F065 F069 G006 G007 | 31 | 3, approved |
| dead code (`pr/cleanup`) | F035 F047 F059 F060 F067 F068 G008 | 12 | none; the gates of the stack |
| documentation (`pr/docs`) | F015 | — | — |

Five commits of `cli-config-core` came after its last review (c7215b49,
534de327, 4c12974d, 8996db47, cd70b005). They passed every gate and the
integration verification's cross-review, but no unit reviewer read them.

## Behaviour changes

Fixing some findings changed what a user sees. The maintainer approved each
of these; nothing else changes visible behaviour, beyond inputs that should
never have been accepted, which are now refused. The
[CHANGELOG](https://github.com/CageForge/nexcage/blob/main/CHANGELOG.md) has them in full.

1. Configuration only from `/etc/nexcage` or `--config`; a group- or
   other-writable or foreign-owned file is refused; a pipe still works (F005,
   F038).
2. Proxmox LXC `exec` clears the caller's environment (G003).
3. An id reaches the Proxmox backend only through nexcage's record or
   `--runtime lxc`; `delete --force` of an unknown id exits 0; records under
   `--root` are in `<root>/.proxmox-lxc` (F016, F017, F029).
4. `--systemd-cgroup` before the command is honoured; the shipped Kubernetes
   configurations set `SystemdCgroup` (G001, G002).
5. A pulled template is named for the whole reference, and only that file is
   used (F012, F013).
6. A name means one container: several matches are an error, a name wins
   over a VMID, identity is checked again before acting, and `create` fails
   when the cluster cannot be asked (F008, F029, F030).
7. A Proxmox LXC bundle's mounts are checked strictly, and `ro`, `nosuid`,
   `nodev` and `noexec` are applied or refused (F001, F024).
8. No quiet fallback to this host's listing when the cluster's fails (F008,
   F022, F040).
9. A bundle's namespaces set no Proxmox features (F025).
10. A `create` that fails after `pct create`, and a `run` whose start fails,
    destroy what they made (F031, F048).
11. `health` runs only checks that can pass and fail (F063).
12. The words of the command `exec` runs are never read as nexcage's
    options; `--flag=value` for an exec flag that takes no value is a usage
    error (F034).
13. Control characters in tool errors, bundle text and logs are escaped
    (F062).

## Findings

Location is where the finding was, at `8d373127`; some of those files are
gone. Commits are every commit on the stack whose message names the finding
in an `Audit:` line, oldest first. The regression tests are the main ones;
the commits name the rest. `tests/sim/run.sh:N` is the line of a simulator
check.

| ID | Severity | Category | Finding | Location (at 8d373127) | Status | Commits | Regression tests |
|---|---|---|---|---|---|---|---|
| F001 | high | isolation | Bundle mounts written raw into `/etc/pve/lxc/<vmid>.conf`: config-line injection, any host path | `src/backends/proxmox-lxc/oci.zig:135` | fixed | 1e19a8b0 2caae931 d8ab4672 0c74dd2b 0c6394b9 0a9637b0 dd747c80 7c84e2f9 4fc6dceb aec99111 572f6db5 | `oci.zig` tests "a mount path goes into a pct property string only when ...", "a mount pct cannot take as a bind mount is refused ..."; `tests/sim/run.sh:1039`, `:1110` |
| F002 | critical | isolation | A NUL-smuggled duplicate key in `config.json` bypassed an isolation profile | `src/core/profile.zig:126` | fixed | 39229295 2c6b5c35 54de5d9a df7d7279 17e03d63 aec99111 | `profile.zig` test "a key or a string with a NUL in it is refused ..."; `tests/crun/profile.sh` |
| F003 | critical | ci-supply-chain | A fork pull request can run as root on the self-hosted runners; the `if:` guard is in a file the fork controls | `.github/workflows/proxmox_e2e.yml:27` | maintainer action | 76a407b1 1b184dc5 f89afeff 727213ba | `tests/scripts/check_runner_exposure.sh`; `scripts/check_runner_exposure.sh` against the live settings |
| F004 | high | isolation | `update` on a crun container ignored its profile's memory and pids caps | `src/cli/router.zig:356` | fixed | 67699b6d 54577176 51633c6a c8542fc0 ced9e057 54de5d9a 37b1fb72 e5d6bae9 | `profile.zig` test "update holds a container made under a profile to the caps recorded at create"; `tests/crun/profile_update.sh` |
| F005 | high | security | `./config.json` in the working directory was loaded as root's configuration, ahead of `/etc/nexcage` | `src/core/config.zig:21` | fixed | 68365301 142eda2c 87864396 a70c30b7 611ab50c c2ee8058 4aa29c6e | `config.zig` test "a config.json in the working directory is not read"; `tests/sim/run.sh:269`, `:1255` |
| F006 | medium | security | `exec`'s process spec had a predictable `/tmp` name; a planted directory aborted every exec into a profiled container | `src/backends/crun/libcrun_driver.zig:733` | fixed | 531ed336 54577176 | `libcrun_driver.zig` test "exec's process spec is a new 0600 file in the container's own state directory"; `tests/crun/exec_spec.sh` |
| F007 | high | isolation | `capabilities.drop` compared names, while libcap also reads lowercase and numeric spellings | `src/core/profile.zig:239` | fixed | ede7acf6 8cfba539 2c6b5c35 37b1fb72 df7d7279 | `profile.zig` tests "a capability spelt otherwise than the kernel spells it is refused ...", "the capability names are the kernel's, by number"; `tests/crun/profile.sh` |
| F008 | medium | stability | `create`'s cluster-wide name check was unlocked, against a lagging cache that failed open | `src/backends/proxmox-lxc/driver.zig:185` | fixed | 77189e77 9803be3b 4a3aabca dea3d6bf 8da2bad1 a796bbf9 | `pve.zig` tests "a name two containers share is no answer", "a miss is no answer while a container has no name"; `tests/sim/run.sh:1962`, `:1917`, `:2167` |
| F009 | medium | stability | A non-object entry in `mounts` freed an undefined pointer in the root process | `deps/oci-spec-zig/src/runtime/bundle.zig:213` | fixed | a53d37f4 b7350d91 | `oci.zig` test "a config.json with a mount, arg or env entry of the wrong type is refused, not crashed on"; `tests/sim/run.sh:871` |
| F010 | medium | stability | A bundle's `cpu.shares` and `memory.limit` crashed `create` (unchecked casts) | `src/backends/proxmox-lxc/driver.zig:389` | fixed | a142b312 b7350d91 1fae4db1 631b93f2 fd752225 | `oci.zig` tests "cpu.shares past the kernel's maximum is refused, not cast", "memory.limit -1 is no limit ..."; `tests/sim/run.sh:1138`, `:1152` |
| F011 | low | stability | `update` and `create` limit arithmetic overflowed and panicked on large values | `src/core/resources.zig:31` | fixed | 75a2552f | `resources.zig` test "limits at the top of i64 are converted or refused, never a trap"; `tests/sim/run.sh:297` |
| F012 | high | correctness | `pull` and `create` took whichever template newly appeared on the storage as the pulled image | `src/backends/proxmox-lxc/pve.zig:236` | fixed | e164bd39 f78fceae 330b37b8 1b9274cc a2ad2518 | `pve.zig` test "a pulled template is named for the whole reference, and two references never share a name"; `tests/sim/run.sh:229`, `:233`, `:2397` |
| F013 | medium | security | `create` reused any template whose name contained the image's name and tag | `src/backends/proxmox-lxc/pve.zig:271` | fixed | e164bd39 f78fceae 9b5dd517 99a9894e 65dbb94f a2ad2518 | `tests/sim/run.sh:209`, `:215`, `:2383` |
| F014 | medium | quality | crun `update --resources` gave libcrun a buffer without a NUL (heap over-read) | `src/backends/crun/libcrun_driver.zig:555` | fixed | 8ffb1c02 | `tests/crun/update.sh` |
| F015 | low | docs | ADR-003 described security controls that were never built | `docs/architecture/ADR-003-Security-Architecture.md:4` | fixed | dfdc86dc | None: a document. Its references were checked against the tree |
| F016 | medium | correctness | Under `--root`, Proxmox LXC state sat where routing looks for libcrun's, so LXC containers went to crun | `src/cli/router.zig:407` | fixed | 5a355c73 127ea8d4 5e589e27 0379cace 3da33cc9 835e44b3 46291930 3181575b 6756e699 bbc024ef 038c5699 | `state_root.zig` test "under a caller's root the Proxmox LXC records are not in libcrun's directory"; `router.zig` test "a Proxmox LXC container's state under --root is not taken for libcrun's"; `tests/crun/lxc_root.sh` |
| F017 | medium | stability | An id without crun state went to Proxmox, which matched any CT by name or VMID | `src/cli/router.zig:399` | fixed | eea56bb9 7d5488c9 0379cace 8bc82280 dea3d6bf 1858b46c 8da2bad1 7c84e2f9 4fc6dceb 6ad6d3ed 064a2461 2066fde0 3181575b 6756e699 fd752225 038c5699 b6c6af29 8a7abaf7 | `router.zig` test "an id with no backend's record is in neither backend"; `tests/sim/run.sh:610`, `:616` |
| F018 | low | stability | An error outside `core.types.Error` aborted nexcage with a panic | `src/cli/registry.zig:199` | fixed | f5cfa304 98838793 | `registry.zig` test "a command error outside core.types.Error is an error exit naming it, not a panic"; `tests/sim/run.sh:98` |
| F019 | medium | isolation | `user_namespace: "require"` accepted the host's user namespace, joined by path, or a mapping of host root | `src/core/profile.zig:202` | fixed | 9dae56c9 1cd3d62e edba4df7 395b9fd6 8cfba539 ceffbd46 2c6b5c35 7f5accf9 df7d7279 | `profile.zig` tests "a user namespace that leaves the container's root the host's is refused", "a user namespace joined by path is read from inside it ..."; `tests/crun/profile.sh` |
| F020 | medium | correctness | `capabilities.drop` accepted misspelt names, which drop nothing | `src/core/config.zig:428` | fixed | b9221b63 | `config.zig` test "a profile that is misspelt, mis-named or names what it cannot do refuses the file"; `tests/sim/run.sh:1389` |
| F021 | medium | stability | A document nested past 256 levels aborted nexcage under a profile | `src/core/profile.zig:126` | fixed | 39229295 2cb8bb9e 54de5d9a | `profile.zig` test "a document nested deeper than any runtime spec is refused, not a panic" |
| F022 | medium | stability | The 1 MiB output cap silently cut cluster listings on a large cluster | `src/backends/proxmox-lxc/common.zig:14` | fixed | 77189e77 4a3aabca a796bbf9 | `common.zig` test "the cluster's listing is read whole: 2 MiB is within its cap"; `tests/sim/run.sh:1894` |
| F023 | medium | security | `kill` signalled a PID read earlier from `pct status`, which can be reused | `src/backends/proxmox-lxc/pve.zig:1336` | fixed | db257606 c7d326bd 202bdcdd | `pve.zig` test "listsPid finds a whole PID in a cgroup.procs list, never a part of one"; `tests/sim/run.sh:387`, `:390` |
| F024 | medium | isolation | Bundle mount options were dropped: read-only, nosuid, nodev and noexec mounts became neither | `deps/oci-spec-zig/src/runtime/bundle.zig:231` | fixed | 5daff565 0c6394b9 8a7abaf7 | `oci.zig` tests "a bind mount's ro, nosuid, nodev and noexec reach its mount point", "a bind mount option Proxmox has nothing for is refused, not dropped"; `tests/sim/run.sh:1047` |
| F025 | low | isolation | A bundle's user namespace turned on Proxmox `nesting=1,keyctl=1` | `src/backends/proxmox-lxc/oci.zig:152` | fixed | b691937e a5bab14e 7c84e2f9 6ad6d3ed | `tests/sim/run.sh:897`, `:972` |
| F026 | low | isolation | Bundle hardening was parsed and silently not applied on Proxmox LXC | `src/backends/proxmox-lxc/driver.zig:480` | fixed | b2525cb9 576201ae 2a50aa72 d202e34e 4e8c52ef | `oci.zig` test "the confinement a bundle asks for is named, and a bundle that asks for none gets no list"; `tests/sim/run.sh:985` |
| F027 | medium | security | A bundle's rootfs was packed world-readable into the shared template store, and left there on interrupt | `src/backends/proxmox-lxc/oci.zig:70` | fixed | 49dbc0bb a5bab14e 529d1f37 a156ab36 6c90d4be dcc0c087 1219d616 c186301c 26ced3bd 9f4b4492 5aca92b0 531e03a3 4fc6dceb | `tests/sim/run.sh:890`, `:931`, `:967` |
| F028 | medium | isolation | `linux.resources.unified` overrode a profile's memory and pids limits | `src/core/profile.zig:117` | fixed | 041380a1 cd79d826 | `profile.zig` test "linux.resources.unified does not undo a profile's limits"; `tests/crun/profile.sh` |
| F029 | medium | correctness | A numeric name resolved ambiguously against VMIDs; commands could act on another CT | `src/backends/proxmox-lxc/pve.zig:533` | fixed | 9803be3b 18c606e4 11dede4a 3181575b a796bbf9 | `pve.zig` test "a name wins over a VMID, whichever the listing puts first"; `tests/sim/run.sh:1946`, `:2130` |
| F030 | medium | stability | Commands acted on a VMID without checking it was still the container found | `src/backends/proxmox-lxc/driver.zig:687` | fixed | 9803be3b 18c606e4 043a0735 6e16520a dc429f97 0c3c9057 | `tests/sim/run.sh:1978`, `:2089`, `:2030` |
| F031 | medium | stability | No rollback after `pct create`, and its children outlived a killed nexcage | `src/backends/proxmox-lxc/driver.zig:461` | fixed | dd9ac4a2 7fdfa5f8 7b7fe412 88be3339 749130e4 4fc6dceb 6ad6d3ed 6e16520a 889a00c5 417dbab5 | `common.zig` test "runBound: the child is sent parent_death_signal when its parent dies"; `tests/sim/run.sh:1065`, `:180` |
| F032 | medium | ci-supply-chain | Release and docs jobs ran tag-pinned third-party code holding write tokens | `.github/workflows/release.yml:122` | fixed | 09a5bd07 | `security.yml` job `zizmor` with `.github/zizmor.yml` |
| F033 | medium | ci-supply-chain | Stale credentials for a Proxmox host are stored as repository secrets | `.github/workflows/proxmox_e2e.yml:1` | maintainer action | 76a407b1 | `tests/scripts/check_runner_exposure.sh`; `scripts/check_runner_exposure.sh` against the live settings |
| F034 | low | correctness | Words of the command `exec` runs were read as nexcage's own flags | `src/core/logging_config.zig:69` | fixed | 6553fabd 8996db47 cd70b005 2e60026c 82ca6e1b 7787e7cb | `main.zig` test "the command exec runs is the container's, flags, values and = included"; `tests/sim/run.sh:472`, `:483` |
| F035 | info | quality | Two overlapping validation modules, mostly dead, one validator not compiling | `src/cli/validation.zig:57` | fixed | 4d991b87 8978effd | `tests/declarations_test.zig` |
| F036 | low | stability | An OCI spec over 1 MiB as `./config.json` failed every command | `src/core/config.zig:124` | fixed | 6cf179c0 c7215b49 | `config.zig` test "an OCI spec in the search is passed over whatever its size ..."; `tests/sim/run.sh:835` |
| F037 | low | quality | The `ociVersion` skip was silent, and errors named the wrong file | `src/core/config.zig:29` | fixed | 6cf179c0 c7215b49 | `config.zig` test "an error behind a spec names the file that has it, not the spec"; `tests/sim/run.sh:844` |
| F038 | medium | security | Configuration files were trusted without an owner or mode check | `src/core/config.zig:124` | fixed | 23276d28 c576ed95 a3dca77c b8160100 e209dc82 bd0d1a9c c7215b49 534de327 4c12974d 4aa29c6e | `config.zig` tests "a configuration others can write, or replace in its directory, is refused", "a symlink to a configuration is trusted only where the file it leads to is"; `tests/sim/run.sh:759`, `:819` |
| F039 | medium | security | Snapshot names and `rmi` volids reached `pvesh` paths and `pct` unchecked | `src/backends/proxmox-lxc/pve.zig:1445` | fixed | 01982a2d 839f0910 3a1007b5 330b37b8 99a9894e 65dbb94f a0aab549 | `pve.zig` tests "snapshot names as Proxmox takes them, and not 'current'", "a template volid is <storage>:vztmpl/<file> and nothing more"; `tests/sim/run.sh:1863`, `:2460` |
| F040 | low | stability | `images` failed outright when one node was unreachable | `src/backends/proxmox-lxc/pve.zig:664` | fixed | 77189e77 | `tests/sim/run.sh:2310`, `:2313` |
| F041 | low | correctness | Degenerate `update` values became other limits: a tiny quota became no limit, memory 0 became 16 MiB | `src/core/resources.zig:51` | fixed | 4af41a23 631b93f2 | `resources.zig` test "a quota below a hundredth of a core is refused, not made no limit"; `tests/sim/run.sh:1589` |
| F042 | low | stability | Log files were opened without `O_APPEND` and followed symlinks | `src/main.zig:75` | fixed | afae3779 e31c5d1f d22a2bf3 | `logging.zig` tests "two writers to one log file keep each other's lines", "a log path whose last component is a symlink is not followed"; `tests/sim/run.sh:1419` |
| F043 | low | correctness | A JSON log line lost its whole message past 2048 bytes | `src/core/logging.zig:104` | fixed | c317618d | `logging.zig` test "a json message longer than the line allows keeps its start, and says it was cut"; `tests/sim/run.sh:144` |
| F044 | low | stability | Duration logging panicked when the wall clock stepped back | `src/core/simple_advanced_logging.zig:137` | fixed | c012ad60 | `simple_advanced_logging.zig` test "a command's duration cannot overflow, whatever the clock did meanwhile" |
| F045 | low | correctness | `kill` checked one signal syntax and gave libcrun the raw text | `src/core/signals.zig:55` | fixed | 349030c2 54577176 | `signals.zig` test "parse rejects everything else"; `tests/sim/run.sh:422`; `tests/crun/kill.sh` |
| F046 | low | correctness | Proxmox LXC `update --resources` dropped settings it did not know and reported success | `src/core/resources.zig:98` | fixed | 3a5411e0 4e8c52ef | `resources.zig` test "firstUnread names a setting the values leave out, and passes an empty one"; `tests/sim/run.sh:1665` |
| F047 | info | quality | The `utils` module was dead and did not compile | `src/utils/net.zig:55` | fixed | bc3d9c19 8978effd | `tests/declarations_test.zig` |
| F048 | low | stability | Proxmox `run` left a half-made container when `start` failed | `src/cli/router.zig:273` | fixed | 8643bfd3 b01727cc 6e16520a dc429f97 8a7abaf7 417dbab5 | `tests/sim/run.sh:640`, `:668` |
| F049 | low | stability | `state.json` was rewritten in place; readers saw empty files | `src/backends/proxmox-lxc/driver.zig:877` | fixed | ba451552 | `common.zig` test "writeFileAtomic: a reader keeps a whole file, and a failed write keeps the old one"; `tests/sim/run.sh:1198` |
| F050 | low | ci-supply-chain | The release build fetched Zig and crun's sources without verification | `Dockerfile:47` | partially fixed | 9600d7b3 7b5c1190 cecca54d | `tests/scripts/gen_crun_headers.sh` |
| F051 | low | ci-supply-chain | Every security scanner was wired so that it could not fail | `.github/workflows/security.yml:39` | fixed | f706cd46 f9db91aa 7dc7eed9 | `security.yml` jobs, with planted canaries for Semgrep and Gitleaks |
| F052 | low | ci-supply-chain | Releases could not be verified independently | `.github/workflows/release.yml:133` | partially fixed | c05ad477 69ea96d6 | `release.yml` steps "The assets are the files this workflow built" and "It is the binary the binary job built" |
| F053 | low | ci-supply-chain | The Dockerfile pinned its own crun commit, apart from the `deps/crun` submodule | `Dockerfile:79` | fixed | 94889c23 27e37c95 | `tests/scripts/check_crun_pin.sh` |
| F054 | low | ci-supply-chain | Workflows without a `permissions:` block got a write-all token | `.github/workflows/version-check.yml:1` | partially fixed | 09a5bd07 51c7bed1 c78438f6 f7ca5c20 6f2cd3fa | `security.yml` job `zizmor`; `tests/scripts/check_runner_exposure.sh` |
| F055 | low | ci-supply-chain | `${{ }}` expressions were expanded into `run:` bodies | `.github/workflows/release.yml:53` | fixed | 09a5bd07 | `security.yml` job `zizmor` (template injection) |
| F056 | low | security | `gen_crun_headers_local.sh` ran `./configure` in a predictable, reused `/tmp` directory | `scripts/gen_crun_headers_local.sh:9` | fixed | f5147946 24b217c0 | `tests/scripts/gen_crun_headers.sh` |
| F057 | low | security | The release binary was not position-independent | `build.zig:208` | fixed | 6ead31d9 60d306fe | `ci.yml` step "The release build is position-independent"; `tests/scripts/check_deb.sh` |
| F058 | low | isolation | `seccomp: "require"` was met by an allow-all filter | `src/core/profile.zig:112` | fixed | 1bc0c121 1cd3d62e 3a74baaa c44b140e | `profile.zig` tests "a seccomp filter that refuses no system call does not meet a profile that requires one", "a precompiled seccomp program does not meet ..."; `tests/crun/profile.sh` |
| F059 | info | quality | Dead fields in `Config` | `src/core/config.zig:510` | fixed | 830bb33a | `tests/declarations_test.zig` |
| F060 | info | quality | `template_manager.zig` and `zfs.zig` were dead code with latent defects | `src/backends/proxmox-lxc/template_manager.zig:49` | fixed | e457a9a7 237eecd5 | `tests/sim/run.sh:114` |
| F061 | low | quality | The FFI context mirror lacked `no_open_tree_namespace` | `src/backends/crun/libcrun_ffi.zig:24` | fixed | 3b3a0ddd | the layout comparison in `src/backends/crun/mod.zig`, at build |
| F062 | low | security | Text logs, the stderr echo and tables wrote untrusted strings raw | `src/core/logging.zig:121` | fixed | e80baf9a 7d055071 f738de90 df7d7279 17e03d63 dd747c80 d202e34e d1161dad | `logging.zig` tests "a logged value cannot add a line or a terminal escape", "a table cell of someone else's text is one cell of one row ..."; `tests/sim/run.sh:152`, `:1777` |
| F063 | low | quality | `health` ran checks that could not pass or could not fail | `src/core/integrity.zig:68` | fixed | fc770bf5 46291930 3181575b | `integrity.zig` test "a zpool check passes only when zpool says every pool is healthy"; `tests/sim/run.sh:2497` |
| F064 | info | docs | `buildagent.yml` targets a runner that is gone, so its Debian 13 job never runs | `.github/workflows/buildagent.yml:37` | maintainer action (#339) | 628a1144 | None: the workflow and `docs/CI_CD_SETUP.md` say so |
| F065 | low | quality | `manage_github_runner.sh remove` could not deregister the Proxmox-host runner | `scripts/manage_github_runner.sh:115` | fixed | 637cf04b 92f9d9db 60d306fe | `tests/scripts/manage_github_runner.sh` |
| F066 | info | quality | `validateBundleVolumes` was dead; `create` checked no bundle mount | `src/backends/proxmox-lxc/driver.zig:620` | fixed | 1e19a8b0 | as F001 |
| F067 | info | quality | A dead command-registration path and helpers, one with a latent compile error | `src/cli/registry.zig:235` | fixed | 54daefad 8978effd | `tests/declarations_test.zig` |
| F068 | info | quality | `tests/*.zig` were placeholders that tested no nexcage code | `tests/simple_integration_test.zig:5` | fixed | 2b8c7722 e8537b1c | `tests/declarations_test.zig`; `validation.zig` test "a hostname is RFC 1123's ..." |
| F069 | info | quality | `build.zig` added include paths that do not exist | `build.zig:215` | fixed | 1488829f | `ci.yml` step "build.zig's include paths exist" |
| G001 | high | isolation | `--systemd-cgroup` before the command was dropped, so crun containers left the pod's cgroup | `src/main.zig:240` | fixed | 235e12d0 c9b3723c 95ff4578 | `main.zig` test "findCommand: --systemd-cgroup before the command is recorded, in each engine's order"; `tests/crun/systemd_cgroup.sh` |
| G002 | medium | isolation | The shipped containerd and k3s handlers left out `SystemdCgroup` | `deploy/kubernetes/node/k3s-config-v3.toml.tmpl:12` | fixed | a9c1eb37 57317715 | `in_pod_cgroup` in `tests/k8s/pod_on_node.sh` (`k8s_e2e.yml`, not run in this work) |
| G003 | medium | security | Proxmox LXC `exec` handed the caller's environment to the container | `src/backends/proxmox-lxc/pve.zig:1365` | fixed | 6c0a53db 82ca6e1b 3181575b 7787e7cb | `tests/sim/run.sh:439` |
| G004 | low | stability | libcrun's re-exec constructor ran on every invocation, before `main` | `deps/crun/src/libcrun/linux.c:7331` | fixed | d01e49f1 f4eb867c 54577176 21a90322 e52e5493 | `tests/crun/rexec.sh` |
| G005 | medium | stability | libcrun's UBSan traps on a bundle's memory values killed `create` and left a cgroup | `build.zig:165` | fixed | e9d70dd2 54577176 4f85f67b 96efa1ee ce9ddec9 c8542fc0 54de5d9a c9b3723c 038c5699 | `libcrun_driver.zig` test "memory values libcrun would overflow on are refused before it sees them"; `tests/crun/memory_values.sh` |
| G006 | low | ci-supply-chain | The release gates for "the crun backend is in it" could not fail | `.github/workflows/release.yml:99` | fixed | b5a69c2f 60d306fe | `tests/scripts/check_deb.sh` |
| G007 | low | quality | The Proxmox E2E tested an LXC-only build, not the release binary | `.github/workflows/proxmox_e2e.yml:61` | fixed | ebdfca3f cbea64c0 | `proxmox_e2e.yml` (not run in this work) |
| G008 | info | quality | `exec`'s environment plumbing was dead | `src/main.zig:436` | fixed | cfc82189 | `tests/declarations_test.zig` |

## Residual risks and open items

Each item has an owner: the maintainer, an existing issue, or a proposed
issue, drafted below. No issue was opened by this work.

| # | What remains | Disposition | Owner |
|---|---|---|---|
| 1 | **F003.** A fork's code can still reach the self-hosted runners if a maintainer approves its run: the runners serve any workflow of the repository. Approval of every outside contributor's run is the only barrier until the runners are restricted | Settings, not code | Maintainer: [steps below](#the-maintainers-remaining-steps) |
| 2 | **F033.** `PVE_HOST`, `PVE_PASSWORD`, `PROXMOX_SSH_KEY` and `GH_TOKEN` are still readable by any workflow pushed to a branch, and may already have been read | Delete, then rotate what they held | Maintainer |
| 3 | **F054.** The repository's default workflow token is write, and may approve pull requests. Every workflow here asks for its own permissions, so this matters for one added later | Settings | Maintainer |
| 4 | **F064.** `buildagent.yml`'s runner is gone; the job waits and is cancelled on every push | Restore the runner or remove the workflow | [#339](https://github.com/CageForge/nexcage/issues/339) |
| 5 | **F052.** `provenance.json` is written by the workflow about itself, unsigned, and the CycloneDX SBOM lists no components. The binary and the `.deb` are attested (c05ad477), which a tag run has yet to show | Build-generated provenance and a real SBOM | [#318](https://github.com/CageForge/nexcage/issues/318), [#333](https://github.com/CageForge/nexcage/issues/333) |
| 6 | **F051.** The scanners fail on findings now, but Semgrep and Gitleaks never ran outside GitHub here: their first run, canaries included, has to be watched. Semgrep's rules are fetched unpinned, so a new rule can turn the job red. None of the scanners reads Zig or libcrun's C | Watch the first runs; the README badge | [#321](https://github.com/CageForge/nexcage/issues/321) |
| 7 | **F050**, the rest: the actions-runner tarballs (`scripts/setup_secure_runner.sh`, `deploy/kubernetes/tenant-nexcage/pve-template/03-prepare-runner-host.sh`, `scripts/manage_github_runner.sh update`) and the Proxmox keyring in `deploy/kubernetes/tenant-nexcage/pve-template/02-install-pve.sh` are downloaded unchecked | Pin their checksums | Proposed issue A |
| 8 | **F008, F017.** Two overlapping `create --name x` on one node can both succeed; every later command then refuses the name. A record proves a name, not a VMID: a CT destroyed outside nexcage and replaced by an unrelated one with the same hostname is destroyed by `delete --force` through the record | A per-name lock; the VMID in the record | Proposed issue B |
| 9 | **F013.** Anyone with `Datastore.AllocateTemplate` can put a file under the name nexcage derives for a reference, and `create` uses it without pulling; no digest is kept | Documented trust in the storage's writers (ISOLATION.md) | Proposed issue C |
| 10 | **F019** and `exec --process`: libcrun opens a joined user namespace's path again after nexcage checked it; and an exec spec without capabilities under a profile is read again by libcrun from the engine's file | Give libcrun what was checked (an fd, the bytes) | Proposed issue D |
| 11 | `run.oci.*` annotations libcrun honours with or without a profile: `seccomp.plugins` (`dlopen`), `hooks.stdout` and `.stderr` (files created as root), `seccomp.receiver`, `pidfd_receiver`, `mount_context_type` | Documented in ISOLATION.md; whether a profile should refuse them is a decision | Proposed issue E |
| 12 | **F025**, the rest: a bundle with a user namespace under `proxmox.unprivileged: false` is created privileged, and nothing says so | Warn or refuse | Proposed issue F |
| 13 | What a profile does not cover: host namespaces other than the user one, `noNewPrivileges`, AppArmor, a read-only root, devices, mounts, rlimits | ADR-005 decision 4: "can follow when someone asks" | Maintainer (profile design before the 1.0 configuration freeze, [#317](https://github.com/CageForge/nexcage/issues/317)) |
| 14 | **F062**, the rest: `printError` in `src/main.zig` writes the caller's own words raw; the JSON log keeps a byte that is not UTF-8 as it is. And `@intFromFloat` on Proxmox's JSON (`src/backends/proxmox-lxc/pve.zig:1037`, `:1265`) traps on a negative or NaN value | Low: the caller's text, and a trusted tool's output | Proposed issue G |
| 15 | Nothing in CI checks the references in ADR-003 and ISOLATION.md; the crun id's characters (`validateContainerId`) have no test of their own | A check and a test | Proposed issue H |
| 16 | The identity checks add a `pct list` to every lookup and a `pct config` before every action. Their cost on a real host (pct is a Perl tool) was not measured | Measure on the E2E node before the release | Proposed issue I |
| 17 | Where nexcage still differs from crun: `exec` of a missing executable exits 1 (crun 255), an unknown signal 2 (crun 1), an unknown option 2 (crun 64); `create <id>` without `--bundle` does not take the working directory; INFO lines on stderr show in podman's output | A compatibility pass | Proposed issue J |
| 18 | runtime-tools' `linux_ns_itype` fails with nexcage under rootless podman (`mknodat /dev/null: Operation not permitted`) and passes with crun | Recorded in `docs/RUNTIME_SPEC_VALIDATION.md` | Proposed issue K |
| 19 | Proxmox LXC `create` truncates a bundle's `memory.limit` to MiB where `update` rounds up, and refuses `cpu.shares` past 262144 where `update` clamps it | Make them one rule (a visible change) | Proposed issue L |
| 20 | **G004** and **F031** chose differently from upstream, for reasons in their commits: the sealed copy is made for `create` and `exec` only, not on every run; a child of nexcage gets SIGTERM, not SIGKILL, when nexcage dies, so `pct create`'s worker removes what it made | Confirm | Maintainer |
| 21 | Accepted as they are: the directories above a configuration file are not checked (F038); writers of a record are not serialised, the last one wins (F049); a JSON log line keeps the head of a long message (F043); `kill` walks a cgroup tree the tenant shapes, and a PID reused inside the same container passes (F023); `pct exec` is not bound to nexcage's life, and SIGKILL leaves a bundle's archive, readable by root only (F031) | Documented in the code and in ADR-003 | Maintainer, if any should change |

### Proposed issues

Drafts, for the maintainer to open or drop.

**A. Check the downloads in the host-provisioning scripts.**
`scripts/setup_secure_runner.sh`, `scripts/manage_github_runner.sh update`
and `deploy/kubernetes/tenant-nexcage/pve-template/03-prepare-runner-host.sh`
download the GitHub actions-runner tarball, and `02-install-pve.sh` the
Proxmox keyring, without checking them, and run them as root on the build and
E2E machines. The release build and CI already check Zig and crun against
pinned sha256 sums (F050). Done when each script refuses a file whose sha256
is not the pinned one, and a test shows it refusing a changed file.

**B. One container per name, and a record that knows its VMID.** `create`
checks that a name is free across the cluster, but nothing holds the name
until `pct create` has run, so two overlapping creates of one name on a node
both succeed (later commands then refuse the name, so nothing acts on the
wrong one). And `delete --force` through a record finds the CT by hostname
alone: one destroyed outside nexcage and replaced by an unrelated CT with the
same hostname is destroyed in its place. Done when a lock under the state
root holds a name from the check until the record is written, the record
carries the VMID, and a command acting through a record refuses a CT whose
VMID differs; each shown in the simulator, red first.

**C. Keep an image's digest with its template.** A pulled template is used
again when the storage has a file of the derived name. Anyone with
`Datastore.AllocateTemplate` can upload one, and `create` runs it; Proxmox's
pull takes no reference pinned by digest. Done when nexcage can tell that a
file under a derived name is the image it pulled, for example by a digest
recorded at the pull and checked on reuse, or when the maintainer decides the
documented trust in the storage's writers is enough.

**D. Hand libcrun what nexcage checked.** Under a profile, nexcage reads a
joined user namespace's maps through the path in the bundle, and libcrun
opens the path again later; an `exec --process` spec without capabilities is
read again by libcrun from the engine's file. Both are windows in which
what libcrun uses can differ from what was checked; both need a path into
libcrun that takes an fd or bytes. Done when libcrun is given the checked
namespace fd and the checked process spec, with a test that swaps the path
or the file after the check.

**E. Decide what a profile does with `run.oci.*` annotations.** libcrun
acts on `run.oci.seccomp.plugins` (`dlopen` in the runtime process, in builds
with dlopen), `run.oci.hooks.stdout` and `.stderr` (files created as root at
the bundle's paths), `run.oci.seccomp.receiver`, `run.oci.pidfd_receiver` and
`run.oci.mount_context_type`, for any bundle. Under Kubernetes a pod reaches
them only through an annotation allowlist, and the shipped handlers have none;
podman's `--annotation` reaches them directly. Done when the maintainer has
decided whether a profile refuses some or all of them, and that is built and
tested, or recorded as a decision in ADR-005.

**F. Say so when a bundle's user namespace is not what it gets.** On the
Proxmox LXC backend, a bundle that asks for a user namespace under
`proxmox.unprivileged: false` gets a privileged container: the configuration
decides, and nothing says the bundle's request was not met. Done when
`create` warns or refuses, as the maintainer decides, with a simulator check.

**G. The last raw text, and float casts on Proxmox's output.** `printError`
in `src/main.zig` writes the caller's words raw on stderr (an unknown command,
a bad `--root`); the JSON log keeps a byte that is not UTF-8; and
`appendTemplatesOf` and the cluster listing cast Proxmox's JSON numbers with
`@intFromFloat` (`pve.zig:1037`, `:1265`), which traps on a negative, huge or
NaN value. All are low: the caller's own text, a trusted tool's output. Done
when each goes through the logger's escaping or is refused, with a test each.

**H. Keep ADR-003's references true.** ADR-003 and ISOLATION.md point at
`path:line`, test names and simulator lines. A change can move them without
anyone noticing. Done when CI checks that every referenced file, line range,
test name and simulator line exists, and a unit test covers
`validateContainerId`, which has none.

**I. Measure what the identity checks cost.** Every Proxmox LXC lookup now
reads `pct list` as well as the cluster listing, and `stop`, `delete`,
`kill`, `rollback` and the others read `pct config` before acting. `pct` is
a Perl tool; the simulator's fakes cannot show its cost. Done when `state`
and `start` are timed on the E2E node against 0.17.0, and, if it matters,
`pct` is asked only for a container on this node.

**J. Exit codes and output as crun has them.** For the same calls nexcage
exits 1 where crun exits 255 (exec of a missing executable), 2 where crun
exits 1 (an unknown signal) and 2 where crun exits 64 (an unknown option);
`create <id>` without `--bundle` does not use the working directory; and
nexcage's INFO lines on stderr show in `podman run` output. None is a
regression. Done when each is decided and matched or documented.

**K. `linux_ns_itype` under rootless podman.** The runtime-tools test fails
with nexcage (`mknodat /dev/null: Operation not permitted`) and passes with
crun in the same container. Done when the cause is found and fixed, or
recorded as a known failure with the reason.

**L. One conversion of limits on Proxmox LXC.** `create` truncates a
bundle's `memory.limit` to MiB where `update` and `--memory` round up, and
refuses `cpu.shares` past 262144 where `update` clamps it to weight 10000.
Done when both paths share one rule, which is a visible change.

## The maintainer's remaining steps

F003 and F033 cannot be closed by repository files. `bash
scripts/check_runner_exposure.sh`, with `gh` logged in as an organization
owner with `admin:org`, fails until these are done. Run read-only on
2026-10-14 (without `admin:org`), it reported:

```text
ok   fork pull requests of every outside contributor need approval
FAIL runners registered to the public repository itself; move them into a runner group (docs/CI_CD_SETUP.md):
     nexcage-e2e [self-hosted,Linux,X64,proxmox,pve9,nexcage-e2e] online
     proxmox-runner [self-hosted,Linux,X64,proxmox,ubuntu] online
FAIL could not read CageForge's runner groups (an organization owner's token with admin:org: gh auth refresh -s admin:org)
FAIL repository secrets no workflow uses (delete them, then rotate what they held): GH_TOKEN PROXMOX_SSH_KEY PVE_HOST PVE_PASSWORD
FAIL the workflow token's default is write, and approving pull requests is true; set "Read repository contents and packages permissions" and untick "Allow GitHub Actions to create and approve pull requests"
```

1. **Done:** the fork-PR approval policy is `all_external_contributors`
   (2026-10-11). Approving a run approves that pull request's code as root on
   the runners: read its `.github/`, `scripts/`, `build.zig` and `Makefile`
   changes first.
2. **Deregister `proxmox-runner`**, the runner on the Proxmox VE host
   mgr.cp.if.ua: `scripts/manage_github_runner.sh remove`, or `gh api -X
   DELETE repos/CageForge/nexcage/actions/runners/<id>`, then stop its service
   on the host. No workflow uses it, and a pull request's own workflow could.
3. **Delete `PVE_HOST`, `PVE_PASSWORD`, `PROXMOX_SSH_KEY` and `GH_TOKEN`,
   and rotate what they held**: remove the key from root's `authorized_keys`
   on mgr.cp.if.ua, change that host's root password, and revoke the
   personal access token. Deleting a secret does not undo a read.
4. **Restrict the runners**: put `nexcage-e2e`, the build agent, and any
   organization runner this repository can use into a runner group whose
   Workflow access names `proxmox_e2e.yml` and `k8s_e2e.yml` at
   `refs/heads/main`, written in full; then remove the repository-level
   registration. If the Team plan does not offer Workflow access, put the
   runners in a group this public repository cannot use, and run the E2E
   from a private repository that checks out `main`
   ([CI_CD_SETUP.md](../CI_CD_SETUP.md#self-hosted-runners-and-forks)).
5. **Make the workflow token read-only by default**, and untick "Allow
   GitHub Actions to create and approve pull requests" (F054).
6. Then run `scripts/check_runner_exposure.sh` with `admin:org`; it passes
   when all of the above holds.

## What was not covered

**Nothing ran on a real Proxmox VE host or a real Kubernetes node.** Every
Proxmox behaviour was shown against the simulator's fake `pct`, `pvesh` and
`pvesm`, which follow pve-container and pve-manager as read from their
source; the crun backend ran in privileged podman containers, under rootless
podman, where `cpuset` is not delegated; the CRI checks ran containerd inside
a container. The two E2E workflows run on the pull requests, on the
self-hosted node, and have to show there:

`proxmox_e2e.yml`, with the release binary as `release.yml` builds it:

- the lifecycle, `kill`, `exec`, pause and resume, `update` and snapshots
  through real `pct`, as before;
- a bundle's bind mount reaching `pct config` as `mp0` with `ro=1` and
  `mountoptions=nosuid`, and `ro,nosuid` in the running container's
  `/proc/mounts`;
- the bundle's archive gone from `/var/tmp` after `create`;
- the Proxmox record under `--root` in `<root>/.proxmox-lxc/<name>`, and
  nothing of it in `<root>/<name>`.

It does not check these, which only the simulator has shown; they are worth
a step on the node:

- `pct exec --keep-env 0`: a variable in the caller's environment is not in
  the command's;
- the undo of a `create` that fails after `pct create`, and of a `run` whose
  start fails, against real `pct destroy`;
- `kill` through a pidfd, refusing a PID outside the container's cgroup;
- a VMID that changes hands between lookup and action;
- `pull` naming the file for the whole reference on a real storage;
- the cost of the identity checks (item 16).

`k8s_e2e.yml`, with the `.deb` built from the commit:

- pods Ready under `nexcage`, `nexcage-hardened` and `nexcage-small`;
- `in_pod_cgroup`: each container and sandbox under its pod's cgroup, with
  `SystemdCgroup` taken from k3s (G001, G002);
- from inside the profiled pods, the profile's capabilities, seccomp mode and
  limits, and a `kubectl exec` cut to the container's bounding set;
- a pod the profile refuses saying why in its events.

Also not run here: the release workflow's attestation and asset checks
(they need a tag, then `gh attestation verify`), `pages.yml`, Dependabot's pip
entry, Gitleaks and Semgrep (item 6), and runtime-tools and critest outside
rootless podman, where the known failures in
`tests/runtime-tools/known-failures` and `tests/cri/critest-known-failures`
apply.
