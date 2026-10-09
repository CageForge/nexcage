# Roadmap

Where nexcage goes after 0.16.0, and what it deliberately will not do.
Reviewed against `main` on 2026-10-08.

This file says what comes next and why, not when. The `Roadmap/` directory it
replaces was removed in September 2026 because it held a sprint plan due in
2025, and a date nobody is held to goes stale faster than anything else in a
repository. So:

- **Only the next release is a commitment.** Everything after it is an order,
  not a schedule.
- **Each item links its issue, and the issue holds the status.** An item
  marked *no issue yet* is a proposal until one is filed.
- **The release pull request edits this file.** What shipped moves to
  [CHANGELOG.md](CHANGELOG.md) and leaves here.
- **Done means it ran against the real thing** — a Proxmox VE host, a
  container engine, a kubelet — not that the simulator agreed. Every defect
  0.12.0 fixed was in code the fakes were happy with.

## Where it stands

nexcage is one binary with two faces
([OVERVIEW.md](docs/architecture/OVERVIEW.md)):

- **A command line for LXC containers on a Proxmox VE cluster**: the
  lifecycle, `exec`, templates (`images`, `pull`, `rmi`), `pause` and
  `resume`, `update` and snapshots, on any node of the cluster, created with the
  options `pct create` takes.
- **An OCI runtime that container engines drive**: podman, `ctr`,
  containerd's CRI, CRI-O and a kubelet run containers on the crun backend,
  and a pod with `runtimeClassName: nexcage` runs on a node installed from the
  files a release ships. The runtime-spec validation suite and `critest` run
  in CI, and every test they fail also fails with crun run directly.

Everything a kubelet's containerd asks a runtime is answered, and the suites
that define a runtime have been asked. What is left is the choice of backend
per pod, depth on the Proxmox side, and what makes a 1.0 a promise rather than
a number.

## Not code: protect `main`

Carried since 0.14.0, and in no release: it is a repository setting, which no
pull request can make. The `main` ruleset exists, disabled; it needs the three
required checks of `ci.yml` and `crun_build.yml`, no force push or deletion,
and no approving review while there is one maintainer
([MAINTAINERS.md](MAINTAINERS.md)). [#305]

## Next: 0.17.0 — isolation profiles

What a Kubernetes user gets from nexcage that crun does not give: **an
isolation profile** — a named choice of which backend creates and runs a
container, and with what parameters.

Today a container's backend is a name lookup
([ADR-001](docs/architecture/ADR-001-Container-Runtime-Selection.md)), and an
engine addresses containers by a 64-character hex id, so the only rule a host
that serves an engine can usefully write is `*`: one node, one backend, one set
of parameters, and a pod on nexcage is a libcrun container that Proxmox VE does
not see. A profile is something the engine can carry for each container, so
one node can run a pod on crun with the engine's own settings next to a pod in
an unprivileged Proxmox container on a chosen storage and bridge.

It comes before 1.0 because 1.0 freezes the configuration it changes.

| Item | Why | Issue |
|---|---|---|
| ADR-005: isolation profiles | What a profile holds — the backend, and that backend's parameters; how an engine names one — the handler a `RuntimeClass` names, or an annotation the engine copies into the bundle (containerd's `pod_annotations`, CRI-O's `allowed_annotations`); and what becomes of `runtime.routing`. Proposed in [ADR-005](docs/architecture/ADR-005-Isolation-Profiles.md): the handler's program name, `nexcage@<profile>` | [#314] |
| The configuration file fails closed | A misspelt runtime in a routing rule routes to LXC without a word, and a section of the wrong type panics. A profile's parameters must not be misspelt into weaker isolation | [#371] |
| A container's backend comes from the container | Every command derives the backend from routing again, so a changed rule sends `delete` to the other backend. With profiles, a person's command and an engine's would disagree | [#372] |
| Profiles on the crun backend | The backend engines already drive, so the first place a profile can be proved end to end. Its shape follows the ADR | [#315] |
| The Proxmox LXC backend driven by an engine | For a profile to be able to choose it. `pct create` starts no process, which is why `--console-socket` and `--pid-file` are refused there today, and a bundle's rootfs is not a template. The largest item on this page | [#316] |

## 1.0 — what the number promises

1.0 is a compatibility promise, not a feature count. Proposed criteria:

1. **Interfaces change only after a warning.** Command names, flags, exit
   codes, `list` columns, the `state` document and config keys change only
   after a release that warns about it — as 0.13.0 did for
   `crun_name_patterns` and for a routing rule naming `runc`. [#317]
2. **Conformance on record.** The runtime-spec validation suite and `critest`
   run in CI since 0.16.0. Their results ship with each release's notes, and
   every test that fails is named with the reason.
3. **Every Proxmox VE major the README names runs the E2E suite.**
4. **Releases that can be verified.** Artifacts signed, and their provenance
   attested by the build (GitHub artifact attestations or Sigstore). Today
   `release.yml` writes `provenance.json` with a heredoc, which proves nothing
   about the binary. An APT repository, so that `apt upgrade` brings a fix to
   a node. [#318], [#319]
5. **A threat model for what ships.** ADR-003 describes a 2024 design —
   "Proxmox LXCRI", PCI-DSS, zero trust — the way ADR-001 did before its
   revision. A root binary on a Proxmox host, handed bundles it did not write,
   needs its own: what it trusts, what it refuses, what a bundle can reach.
   With it, scans that block: all three jobs in `security.yml` are
   `continue-on-error`. And OpenSSF Scorecards running again. [#320],
   [#321]
6. **A support policy**: which minor release receives fixes after 1.0, and
   for how long. [#322]

## Later, when asked

- **`exec`, `kill` and `pause` on a container on another node.** No Proxmox
  API reaches into a container's processes; the cluster's own root SSH between
  nodes does. That is a root binary opening root sessions on other hosts, so
  it needs an ADR, and a user who needs it. [#323]
- **`events`.** No engine has sent it: podman, `ctr`, containerd's CRI,
  CRI-O, critest and a kubelet all ran without it. If one does, the trace will
  say.
- **Backup, restore and migration through pct** — `vzdump`, `pct restore`,
  `pct migrate` — by name on any node, the way snapshots went. [#324]

## Open question

**Where users talk.** Discussions are enabled and hold one announcement;
`ADOPTERS.md` waits for a first adopter. A roadmap ordered by "when someone
asks" needs a place to be asked.

## Not planned

| | Why |
|---|---|
| A runc backend, or a fallback between backends | [ADR-001](docs/architecture/ADR-001-Container-Runtime-Selection.md): libcrun answers the same interface, and a container is one thing on one backend |
| Virtual machines through `qm` | The stub backend went in 0.14.0. It can come back with a test behind it and someone who needs it |
| Proxmox VE 8 | Earlier releases ran on it, but no test ever did, and Proxmox ended its own support for 8.x in August 2026. nexcage does not refuse an 8.x host; it no longer promises anything there |
| A daemon or a remote API | nexcage is an OCI runtime. A kubelet runs on each node and calls the binary there, as it calls runc |
| An image service for Kubernetes | containerd and CRI-O implement `ImageService` and hand the runtime an unpacked bundle |
| A health or metrics endpoint | A process that exits after every command has nothing to probe; metrics belong to the engine |
| `pct suspend` for `pause` | It checkpoints through CRIU and takes the container down. The freezer is what the runtime-spec means (0.12.0) |
| ZFS through libzfs | Proxmox owns the storage. Snapshots go through pct ([#299]), which supersedes [#116], [#117], [#118] and [#163] |
| FreeBSD jails ([#108]) | nexcage is a runtime for Proxmox VE, which is Linux |
| arm64 releases | Proxmox VE ships for amd64, and on an arm64 host there is no Proxmox to make nexcage worth choosing over crun. Revisit if that changes |

[#108]: https://github.com/CageForge/nexcage/issues/108
[#116]: https://github.com/CageForge/nexcage/issues/116
[#117]: https://github.com/CageForge/nexcage/issues/117
[#118]: https://github.com/CageForge/nexcage/issues/118
[#163]: https://github.com/CageForge/nexcage/issues/163
[#299]: https://github.com/CageForge/nexcage/issues/299
[#305]: https://github.com/CageForge/nexcage/issues/305
[#314]: https://github.com/CageForge/nexcage/issues/314
[#315]: https://github.com/CageForge/nexcage/issues/315
[#316]: https://github.com/CageForge/nexcage/issues/316
[#317]: https://github.com/CageForge/nexcage/issues/317
[#318]: https://github.com/CageForge/nexcage/issues/318
[#319]: https://github.com/CageForge/nexcage/issues/319
[#320]: https://github.com/CageForge/nexcage/issues/320
[#321]: https://github.com/CageForge/nexcage/issues/321
[#322]: https://github.com/CageForge/nexcage/issues/322
[#323]: https://github.com/CageForge/nexcage/issues/323
[#324]: https://github.com/CageForge/nexcage/issues/324
[#371]: https://github.com/CageForge/nexcage/issues/371
[#372]: https://github.com/CageForge/nexcage/issues/372
