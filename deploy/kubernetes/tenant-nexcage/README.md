# tenant-nexcage

Manifests for the Cozystack tenant nexcage is developed and tested in. The
cluster they were written against is `pskep`: five Talos nodes, Cozystack, with
kubemox connected to the Proxmox host `prox-home`.

[../../../docs/KUBERNETES_INTEGRATION.md](../../../docs/KUBERNETES_INTEGRATION.md)
explains what the runtime still needs before Kubernetes can schedule onto it,
and which stage each of these files belongs to.

| File | What it does |
|---|---|
| `tenant.yaml` | The `Tenant`, which creates the `tenant-nexcage` namespace and its role bindings |
| `job-build-test.yaml` | Builds nexcage from source in the cluster and runs the unit tests and smoke checks |
| `vm-e2e-node.yaml` | The Proxmox VE node the E2E suite runs on, cloned by kubemox from `nexcage-pve-tpl-v0-2` on prox-home |
| `pve-template/` | The four scripts that build that template from the Debian 13 cloud image |

## Apply

```bash
kubectl apply -f tenant.yaml
kubectl -n tenant-root get tenant nexcage          # wait for READY=True
kubectl apply -f job-build-test.yaml
kubectl -n tenant-nexcage logs -f job/nexcage-build-test
```

The job ends with `ALL_OK`. It keeps its pod for a day
(`ttlSecondsAfterFinished`), so read the logs before then. To run it again,
delete the job first: a completed `Job` cannot be restarted in place.

```bash
kubectl -n tenant-nexcage delete job nexcage-build-test
```

## What does not run here

`tests/sim/run.sh` needs a user namespace it can mount in. The Talos nodes
report `user.max_user_namespaces=0` inside pods, so `unshare -r` fails there
whatever the pod's security context says, and PodSecurity enforces `baseline`
on tenant namespaces, which rules out a privileged pod as well. The job prints
`SIM_CAPABLE=no` and carries on.

Making it run needs both:

- `user.max_user_namespaces` raised on the nodes through the Talos machine
  config (`machine.sysctls`);
- the namespace labelled `pod-security.kubernetes.io/enforce=privileged`, if
  the suite is run as a privileged pod instead of through a user namespace.

Until then the simulation suite runs on the self-hosted build agent, where it
passes — see `.github/workflows/buildagent.yml`.

Anything calling `pct` needs a Proxmox VE host and cannot run in a pod at all.
That is what `vm-e2e-node.yaml` is for:

```bash
kubectl apply -f vm-e2e-node.yaml
kubectl -n tenant-nexcage get vm nexcage-e2e-1 -w     # wait for state=running
```

kubemox clones the template on prox-home and starts the node. Then register the
Actions runner on it — the template carries the runner software but no
registration:

```bash
gh api -X POST repos/CageForge/nexcage/actions/runners/registration-token --jq .token \
  | ssh -J root@192.168.1.3 root@192.168.3.80 \
      'read -r RUNNER_TOKEN; export RUNNER_TOKEN; bash -s' \
  < ../../../scripts/register_e2e_runner.sh
```

It comes up with the labels `proxmox,pve9,nexcage-e2e`, and
`proxmox_e2e.yml` targets `[self-hosted, pve9]`.

Deleting the `VirtualMachine` destroys the node, so remove the runner from the
repository first (`./svc.sh stop && ./svc.sh uninstall` on the node, then
`config.sh remove`), or it lingers as an offline runner.
