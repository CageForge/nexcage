## 2025-11-03: deps/crun sync to 1.24

- Changes:
  - Synced vendored crun sources/headers in `deps/crun` to upstream `1.24` using `scripts/sync_crun_vendor.sh`.
  - Added workflow `.github/workflows/crun_vendor_sync.yml` for weekly checks and PR auto-creation.
  - Added `scripts/sync_crun_vendor.sh` (supports `--latest/--version`, markers in `deps/crun/.upstream_tag`).
- Build: success (`zig build`).
- Time spent: ~0.3h.


