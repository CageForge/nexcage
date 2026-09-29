#!/usr/bin/env python3
"""Check a `nexcage --runtime crun features` document against this build.

    nexcage --runtime crun features > features.json
    python3 tests/crun/features_check.py features.json

containerd's CRI asks for this once at startup. The values must be libcrun's
own, read from this build -- a features document written by hand would be a
set of promises to a kubelet about someone else's compile-time configuration,
free to drift from it silently.

Run by crun_build.yml and by `scripts/dev.sh crun`.
"""
import json
import sys

d = json.load(open(sys.argv[1]))
assert d["ociVersionMin"].startswith("1."), d["ociVersionMin"]
assert "createRuntime" in d["hooks"], d["hooks"]
assert "mount" in d["linux"]["namespaces"], d["linux"]["namespaces"]
assert "bind" in d["mountOptions"], d["mountOptions"][:10]
assert d["linux"]["cgroup"]["v2"] is True, d["linux"]["cgroup"]
assert d["annotations"]["run.oci.crun.version"], d["annotations"]
assert d["annotations"]["io.cageforge.nexcage.backend"] == "crun"
print("spec", d["ociVersionMin"], "to", d["ociVersionMax"],
      "on crun", d["annotations"]["run.oci.crun.version"])
