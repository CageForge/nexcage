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
That is stage 2 in the integration document: a `VirtualMachine` declared
through kubemox, carrying the runner that `proxmox_e2e.yml` targets.
