# Sprint 4 — Memory leaks & Proxmox upload fixes

Date: 2025-09-24

## Scope
- Fix memory leaks and lifetime issues in managers and client code
- Stabilize multipart upload to Proxmox (template upload)
- Ensure build is green and remote testing passes compilation stage

## Changes
- proxmox/client.zig: add proper cleanup in `Client.deinit()` for `hosts`, `token`, `base_urls`
- proxmox/proxmox.zig: avoid double-free; rely on `Client.deinit()`; adjust `deinit`
- oci/image/manager.zig: free/destroy `LayerFS`, `MetadataCache`, `LayerManager`, `file_ops`, `self` in `deinit`
- oci/lxc.zig: destroy `self` in `deinit`
- main.zig: add consistent cleanup path for `proxmox_client`; fix `defer` placement to avoid syntax issues
- proxmox/client.zig: remove unsupported `request.timeout`; keep retry handling for `ConnectionResetByPeer`; correct multipart `Content-Type`
- proxmox/template/operations.zig: correct multipart form structure — send file under `content` with filename

## Results
- Local build: OK (`zig build` succeeds)
- Remote compile: OK (build succeeds), runtime still shows remaining GPA leak traces during large upload — further iteration planned

## Next Steps
- Finalize Proxmox template upload resilience (retries/backoff and stream write buffering)
- Validate LXC create path via Proxmox API end-to-end; ensure `rootfs_path` passed and containerd fallback logic is effective
- Track and close remaining GPA leaks reported during remote run

## Time Spent
- Implementation & testing: 1h 10m


