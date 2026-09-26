# nexcage 0.11.1

A small release. Nothing new to use; `images`, `pull` and `rmi` shipped in
0.11.0 having met only the simulator's fakes, and they are checked against a
real Proxmox host now.

## The one thing to notice

`images --node` on a node the cluster does not have used to print a header and
exit 0:

```
$ nexcage images --node definitely-not-a-node
NODE  STORAGE  SHARED  SIZE  TEMPLATE
$ echo $?
0
```

That reads as "that node has no templates", which is a different statement and
sends someone looking in the wrong place. It is an error now, naming the nodes
the cluster does have:

```
$ nexcage images --node definitely-not-a-node
ERROR no node called 'definitely-not-a-node' in this cluster; it has: prox-home, titan
$ echo $?
1
```

## Why this release exists

Three of the failures while writing the simulator's fakes for those commands
were the fake and not the code: a shared storage modelled as separate files per
node, a pulled template that appeared in the wrong list, a version the fake
reported as 8.4.1. A storage listing is exactly the kind of thing a fake gets
subtly wrong, so the commands are now exercised where nothing is pretending:

```
[E2E] images lists what this node has, and agrees with pvesm
NODE          STORAGE  SHARED  SIZE  TEMPLATE
nexcage-e2e   local    no      123M  local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
[E2E] a node the cluster does not have is an error, not an empty list
[E2E] pull, and the volid it prints is the one the storage holds
[E2E] pulled local:vztmpl/alpine_3.20.tar
[E2E] rmi removes it from the storage, not just from the listing
local:vztmpl/alpine_3.20.tar removed from nexcage-e2e
[E2E] and removing it twice is an error, not a second success
[E2E] templates path passed
```

The step frees anything it pulled on the way out, failure included. `images`
runs on any Proxmox; `pull` and `rmi` need 9.1 or later, and the step says so
and stops rather than failing there.

## Also fixed

The E2E job uploaded only `e2e_lxc.log`. The registry step has been writing
`e2e_registry.log` since it was added and nothing ever collected it, so a
failure there left nothing to read afterwards. All of them are collected now.

## Upgrading from 0.11.0

Nothing to do. The only behaviour change is the one above, and it affects a
command that was answering wrongly.
