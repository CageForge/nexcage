#!/bin/bash
set -e

VERSION=$(cat VERSION | tr -d '\n\r')
DEB_VERSION="${VERSION}-1"
PACKAGE_NAME="nexcage"
BUILD_DIR="../build-deb/${PACKAGE_NAME}-${VERSION}"
DIST_DIR="dist"

echo "Building ${PACKAGE_NAME}-${DEB_VERSION}.deb"

# Clean previous builds
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Copy source
cp -r . "${BUILD_DIR}/"
cd "${BUILD_DIR}"

# Copy debian directory
cp -r packaging/debian debian/

# Build binary
echo "Building binary..."
zig build -Doptimize=ReleaseFast

# Create package structure
DEB_ROOT="debian/${PACKAGE_NAME}"
mkdir -p "${DEB_ROOT}/DEBIAN"
mkdir -p "${DEB_ROOT}/usr/bin"
mkdir -p "${DEB_ROOT}/usr/share/doc/${PACKAGE_NAME}"
mkdir -p "${DEB_ROOT}/etc/${PACKAGE_NAME}"

# Copy binary
cp zig-out/bin/nexcage "${DEB_ROOT}/usr/bin/"

# Copy config files
[ -f packaging/config/config.json ] && \
  cp packaging/config/config.json "${DEB_ROOT}/etc/${PACKAGE_NAME}/config.json.example" || true
[ -f packaging/config/proxmox-lxcri.json ] && \
  cp packaging/config/proxmox-lxcri.json "${DEB_ROOT}/etc/${PACKAGE_NAME}/proxmox-lxcri.json.example" || true

# Copy man page
[ -f packaging/man/proxmox-lxcri.1 ] && \
  mkdir -p "${DEB_ROOT}/usr/share/man/man1" && \
  cp packaging/man/proxmox-lxcri.1 "${DEB_ROOT}/usr/share/man/man1/nexcage.1" || true

# Copy docs
cp README.md "${DEB_ROOT}/usr/share/doc/${PACKAGE_NAME}/"
[ -f docs/architecture.md ] && \
  cp docs/architecture.md "${DEB_ROOT}/usr/share/doc/${PACKAGE_NAME}/" || true

# Copy bash completion
[ -f packaging/completion/nexcage.bash ] && \
  mkdir -p "${DEB_ROOT}/usr/share/bash-completion/completions" && \
  cp packaging/completion/nexcage.bash "${DEB_ROOT}/usr/share/bash-completion/completions/nexcage" || true

# Create control file
cat > "${DEB_ROOT}/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${DEB_VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: CageForge Team <contact@cageforge.com>
Depends: libc6
Recommends: proxmox-ve (>= 7.0), zfsutils-linux (>= 2.1)
Suggests: containerd (>= 1.6), kubernetes-cni
Homepage: https://github.com/CageForge/nexcage
Description: OCI-compatible container runtime for Proxmox VE
 NexCage (formerly Proxmox-LXCri) is a high-performance OCI-compatible
 runtime implementation that transforms Proxmox VE into a container and
 VM orchestration worker.
 .
 Key features:
  * Full OCI Runtime Specification 1.0.2 compliance
  * Proxmox VE LXC backend integration
  * OCI bundle support with config.json parsing
  * Container lifecycle management (create, start, stop, delete, kill)
  * State management with OCI-compliant state.json
  * ZFS dataset support for container storage
  * Security hardening with input validation
  * Multiple runtime backends (proxmox-lxc, crun, runc, vm)
EOF

# Create postinst script
cat > "${DEB_ROOT}/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
set -e
# Update man database
if command -v mandb >/dev/null 2>&1; then
    mandb >/dev/null 2>&1 || true
fi
# Enable bash completion
if [ -f /usr/share/bash-completion/completions/nexcage ]; then
    source /usr/share/bash-completion/completions/nexcage || true
fi
exit 0
POSTINST
chmod +x "${DEB_ROOT}/DEBIAN/postinst"

# Build DEB package
cd debian
fakeroot dpkg-deb --build "${PACKAGE_NAME}"

# Move to dist (back to repo root)
REPO_ROOT="$(cd ../../.. && pwd)"
mkdir -p "${REPO_ROOT}/${DIST_DIR}"
mv "${PACKAGE_NAME}.deb" "${REPO_ROOT}/${DIST_DIR}/${PACKAGE_NAME}-${VERSION}-amd64.deb"

echo "✅ DEB package built: ${REPO_ROOT}/${DIST_DIR}/${PACKAGE_NAME}-${VERSION}-amd64.deb"
ls -lh "${REPO_ROOT}/${DIST_DIR}/${PACKAGE_NAME}-${VERSION}-amd64.deb"

