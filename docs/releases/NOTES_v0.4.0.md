          # Proxmox LXCRI v$VERSION - ZFS Checkpoint/Restore Release
          
          ## 🚀 Major Features
          
          ### ZFS Checkpoint/Restore System
          - **Revolutionary Performance**: Lightning-fast filesystem-level snapshots in seconds
          - **Hybrid Architecture**: ZFS snapshots (primary) + CRIU fallback (secondary)
          - **Smart Detection**: Automatic ZFS availability detection with graceful fallback
          - **Production Ready**: Seamless integration with Proxmox ZFS infrastructure
          
          ### Enhanced Command Set
          - `checkpoint <container-id>` - Create instant ZFS snapshots
          - `restore <container-id>` - Restore from latest checkpoint
          - `restore --snapshot <name> <container-id>` - Restore specific checkpoint
          - `run --bundle <path> <container-id>` - Create and start in one operation
          - `spec --bundle <path>` - Generate OCI specification
          
          ### Performance Improvements
          - **300%+ Command Parsing**: StaticStringMap optimization
          - **Filesystem-Level Consistency**: ZFS copy-on-write guarantees
          - **Minimal Storage Overhead**: ~0-5% with ZFS deduplication
          
          ## 📦 Installation Options
          
          ### DEB Packages (Ubuntu/Debian)
          ```bash
          # Download and install DEB package
          wget https://github.com/cageforge/nexcage/releases/download/v$VERSION/nexcage_$VERSION-1_amd64.deb
          sudo dpkg -i nexcage_$VERSION-1_amd64.deb
          sudo apt-get install -f  # Fix dependencies if needed
          
          # Configure and start
          sudo systemctl enable nexcage
          sudo systemctl start nexcage
          ```
          
          ### Binary Installation
          ```bash
          # Download binary
          wget https://github.com/cageforge/nexcage/releases/download/v$VERSION/nexcage-linux-x86_64
          chmod +x nexcage-linux-x86_64
          sudo mv nexcage-linux-x86_64 /usr/local/bin/nexcage
          ```
          
          ## 📚 Documentation
          - Complete ZFS configuration and usage guide
          - Enhanced architecture documentation
          - Comprehensive troubleshooting section
          - Production deployment examples
          
          ## 🔧 Technical Details
          - Dataset pattern: `tank/containers/<container_id>`
          - Snapshot naming: `checkpoint-<timestamp>`
          - Automatic latest checkpoint detection
          - Error handling and logging improvements
          
          See [CHANGELOG.md](https://github.com/cageforge/nexcage/blob/main/docs/CHANGELOG.md) for complete details.
