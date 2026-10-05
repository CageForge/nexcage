# Roadmap

Where nexcage goes after 0.13.0, and what it deliberately will not do.
Reviewed against `main` at `a57feb48` on 2026-10-05.

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
  `resume`, `update`, on any node of the cluster — and snapshots, merged
  after 0.13.0.
- **An OCI runtime that container engines drive**: podman, `ctr`,
  containerd's CRI, CRI-O and a kubelet run containers on the crun backend,
  and a pod with `runtimeClassName: nexcage` runs on a node.

Everything a kubelet's containerd asks a runtime is answered. What is left is
less about missing verbs than about proof, depth on the Proxmox side, and what
makes a 1.0 a promise rather than a number.

## Next: 0.14.0 — ship what is merged, and make the project say true things

Snapshots, `scripts/dev.sh`, the perf suites and `ociVersion` 1.3.0 have been
on `main` since 2026-10-02 (*Unreleased* in the changelog). They should not
wait for anything else in this section, which is small, overdue, and mostly
not code.

| Item | Why now | Issue |
|---|---|---|
| Release snapshots: `snapshot`, `snapshots`, `rollback`, `delsnapshot` | Merged in [#300] and exercised by the E2E suite on a real host | [#299] |
| Remove the Proxmox VM backend | 267 lines, compiled out by default, built by no workflow, and its operations log a warning: the state the runc backend was in when 0.13.0 removed it. `qm` can come back with a test behind it | no issue yet |
| Fix `CODEOWNERS` and `MAINTAINERS.md` | GitHub reports every owner in `CODEOWNERS` as unknown: `@CageForge` is the organization, which cannot own code except through a team, and `@moriarti` is a different account from the maintainer's, `@themoriarti`. The file has never requested a review | no issue yet |
| Protect `main` | It has no branch protection. Require `CI` and `crun backend build` to pass before a merge | no issue yet |
| Make the review rule the one practised | `GOVERNANCE.md` and `MAINTAINERS.md` ask for two LGTMs on non-trivial changes, with one active maintainer to give them | no issue yet |
| Answer [#301] | An outside documentation contribution, open since 2026-10-04 | [#301] |
| Close what is settled | [#117] and [#118] are superseded by snapshots through pct, as the changelog already says. [#119]'s caching shipped in 0.13.0 as reuse of an image already on the storage. [#108] asks for FreeBSD jails, which have no backend and no Proxmox (see *Not planned*). [#131] is a 2025 plan: what still applies becomes its own issue. Five sprint milestones were due in 2025 | — |
| Docs that disagree with the code | `CLI_REFERENCE.md` says a bundle must sit under `/var/lib/nexcage/bundles/` or `/tmp/nexcage-bundles/`, which 0.10.0 stopped requiring. Rows 6 and 8 of the gap table in `KUBERNETES_INTEGRATION.md` read as open, though logs and sandboxes are the engine's, as row 7 already says of CNI; row 5 is *Not planned* below. The changelog's *Support Policy* is about v0.3.x | no issue yet |

## 0.15.0 — the Proxmox command line, deeper

The Proxmox face is where nexcage is more than crun under another name, and it
is the face with the fewest options.

| Item | Why | Issue |
|---|---|---|
| `create` takes what `pct create` is usually given | The storage, root filesystem size and bridge come from the config file, and the network is always DHCP. Memory, cores, a static address and gateway, a VLAN tag, mount points, `onboot` and tags need a `pct set` afterwards, outside nexcage. `update` already turns limits into pct's terms; `create` should accept the same | no issue yet |
| Private registries | `oci-registry-pull` takes no credentials, so `pull` and `create` cannot reach a private registry. Ask Proxmox for a credentials parameter first; a registry client inside a binary that runs as root is the fallback, and wants an ADR before code | no issue yet |

## 0.16.0 — the OCI runtime, measured by the suites that define it

Every engine-facing defect in 0.10.0 was found by running an engine, and none
was on the list of what was thought to be missing. The conformance suites ask
everything, not only what one engine happened to ask.

| Item | Why | Issue |
|---|---|---|
| The runtime-spec validation suite ([opencontainers/runtime-tools]) against the crun backend, in CI | The specification's own tests. Results recorded, known failures named | no issue yet |
| `critest` ([cri-tools]) against containerd with nexcage as the runtime handler | What Kubernetes checks of a CRI runtime. `tests/cri/pod_on_nexcage.sh` is one pod | no issue yet |
| The k3s pod test from a workflow | `tests/k8s/pod_on_node.sh` runs on `nexcage-e2e-1` by hand today | no issue yet |
| An install for a Kubernetes node on Proxmox VE | The routing config, containerd and CRI-O drop-ins and a `RuntimeClass` shipped with the `-crun` package and in `deploy/`, rather than assembled from `KUBERNETES_INTEGRATION.md`. [#301] starts on the config | no issue yet |
| `events` | Only once an engine sends it. The trace will say | — |

## 0.17.0 — isolation profiles

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
| ADR-005: isolation profiles | What a profile holds — the backend, and that backend's parameters; how an engine names one — the handler a `RuntimeClass` names, or an annotation the engine copies into the bundle (containerd's `pod_annotations`, CRI-O's `allowed_annotations`); and what becomes of `runtime.routing` | no issue yet |
| Profiles on the crun backend | The backend engines already drive, so the first place a profile can be proved end to end. Its shape follows the ADR | no issue yet |
| The Proxmox LXC backend driven by an engine | For a profile to be able to choose it. `pct create` starts no process, which is why `--console-socket` and `--pid-file` are refused there today, and a bundle's rootfs is not a template. The largest item on this page | no issue yet |

## 1.0 — what the number promises

1.0 is a compatibility promise, not a feature count. Proposed criteria:

1. **Interfaces change only after a warning.** Command names, flags, exit
   codes, `list` columns, the `state` document and config keys change only
   after a release that warns about it — as 0.13.0 did for
   `crun_name_patterns` and for a routing rule naming `runc`.
2. **Conformance on record.** The runtime-spec validation suite and `critest`
   run in CI, and their results ship with each release's notes.
3. **Every Proxmox VE major the README names runs the E2E suite.**
4. **Releases that can be verified.** Artifacts signed, and their provenance
   attested by the build (GitHub artifact attestations or Sigstore). Today
   `release.yml` writes `provenance.json` with a heredoc, which proves nothing
   about the binary. An APT repository, so that `apt upgrade` brings a fix to
   a node.
5. **A threat model for what ships.** ADR-003 describes a 2024 design —
   "Proxmox LXCRI", PCI-DSS, zero trust — the way ADR-001 did before its
   revision. A root binary on a Proxmox host, handed bundles it did not write,
   needs its own: what it trusts, what it refuses, what a bundle can reach.
   With it, scans that block: all three jobs in `security.yml` are
   `continue-on-error`. And OpenSSF Scorecards running again.
6. **A support policy**: which minor release receives fixes after 1.0, and
   for how long.

## Later, when asked

- **`exec`, `kill` and `pause` on a container on another node.** No Proxmox
  API reaches into a container's processes; the cluster's own root SSH between
  nodes does. That is a root binary opening root sessions on other hosts, so
  it needs an ADR, and a user who needs it.
- **Backup, restore and migration through pct** — `vzdump`, `pct restore`,
  `pct migrate` — by name on any node, the way snapshots went.

## Open question

**Where users talk.** Discussions are enabled and hold one announcement;
`ADOPTERS.md` waits for a first adopter. A roadmap ordered by "when someone
asks" needs a place to be asked.

## Not planned

| | Why |
|---|---|
| A runc backend, or a fallback between backends | [ADR-001](docs/architecture/ADR-001-Container-Runtime-Selection.md): libcrun answers the same interface, and a container is one thing on one backend |
| Virtual machines through `qm` | The stub backend goes in 0.14.0. It can come back with a test behind it and someone who needs it |
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
[#119]: https://github.com/CageForge/nexcage/issues/119
[#131]: https://github.com/CageForge/nexcage/issues/131
[#163]: https://github.com/CageForge/nexcage/issues/163
[#299]: https://github.com/CageForge/nexcage/issues/299
[#300]: https://github.com/CageForge/nexcage/pull/300
[#301]: https://github.com/CageForge/nexcage/pull/301
[opencontainers/runtime-tools]: https://github.com/opencontainers/runtime-tools
[cri-tools]: https://github.com/kubernetes-sigs/cri-tools
