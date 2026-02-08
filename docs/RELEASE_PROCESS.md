# Nexcage Release Process Guide

This document outlines the complete step-by-step process for creating and publishing releases of Nexcage with automated DEB package generation.

## 📋 Prerequisites

### Required Access
- **GitHub Repository**: Write access to `cageforge/nexcage`
- **Git Configuration**: Properly configured local Git environment
- **GPG Key**: For signing releases (recommended)

### Required Tools
```bash
# Install required tools
sudo apt update
sudo apt install -y git gh zig

# Verify installations
git --version
gh --version
zig version

# Authenticate with GitHub CLI
gh auth login
```

### Development Environment
```bash
# Clone repository
git clone https://github.com/cageforge/nexcage.git
cd nexcage

# Ensure clean working directory
git status
git pull origin main
```

## 🚀 Release Process Steps

### Step 1: Pre-Release Preparation

#### 1.1 Version Planning
```bash
# Determine next version based on changes
# - Major (X.0.0): Breaking changes
# - Minor (X.Y.0): New features, backward compatible
# - Patch (X.Y.Z): Bug fixes, backward compatible

# Example: Current v0.3.0 → Next v0.3.1 (patch) or v0.4.0 (minor)
NEXT_VERSION="0.4.0"
echo "Planning release: v${NEXT_VERSION}"
```

#### 1.2 Code Freeze and Testing
```bash
# Ensure all code is committed
git add .
git commit -m "Final changes for v${NEXT_VERSION}"

# Run comprehensive tests
zig build test

# Build and test locally
zig build -Doptimize=ReleaseFast
./zig-out/bin/nexcage version
./zig-out/bin/nexcage --help
```

#### 1.3 Documentation Review
```bash
# Check all documentation is up to date
git status docs/

# Verify examples work with current code
# Update any outdated documentation
```

### Step 2: Version Updates

#### 2.1 Update Version in Code
```bash
# Update binary version in help system
sed -i 's/version [0-9]\+\.[0-9]\+\.[0-9]\+/version '${NEXT_VERSION}'/' src/oci/help.zig

# Verify the change
grep "version.*${NEXT_VERSION}" src/oci/help.zig
```

#### 2.2 Update Documentation Versions
```bash
# Update README.md version badge
sed -i 's/Version-[0-9]\+\.[0-9]\+\.[0-9]\+/Version-'${NEXT_VERSION}'/' README.md
sed -i 's/tag\/v[0-9]\+\.[0-9]\+\.[0-9]\+/tag\/v'${NEXT_VERSION}'/' README.md

# Update installation examples
sed -i 's/nexcage_[0-9]\+\.[0-9]\+\.[0-9]\+-1/nexcage_'${NEXT_VERSION}'-1/' README.md
sed -i 's/nexcage_[0-9]\+\.[0-9]\+\.[0-9]\+-1/nexcage_'${NEXT_VERSION}'-1/' docs/INSTALLATION.md

# Update package changelog
sed -i '1s/([0-9]\+\.[0-9]\+\.[0-9]\+-1)/('${NEXT_VERSION}'-1)/' packaging/debian/changelog
```

#### 2.3 Update CHANGELOG.md
```bash
# Edit CHANGELOG.md to move features from [Unreleased] to new version
# Add new [Unreleased] section for future changes

# Example structure:
cat >> CHANGELOG_UPDATE.md << EOF
## [Unreleased]

### Planned
- Future enhancements and improvements

## [${NEXT_VERSION}] - $(date +%Y-%m-%d)

### Added
- [List new features]

### Changed  
- [List changes]

### Fixed
- [List bug fixes]

EOF

# Manually merge this into docs/CHANGELOG.md
echo "Update docs/CHANGELOG.md with version ${NEXT_VERSION}"
echo "Remember to set the correct date: $(date +%Y-%m-%d)"
```

### Step 3: Pre-Release Validation

#### 3.1 Build and Test
```bash
# Clean build
rm -rf zig-out/ zig-cache/
zig build -Doptimize=ReleaseFast

# Validate version
./zig-out/bin/nexcage version | grep ${NEXT_VERSION}

# Test key functionality
./zig-out/bin/nexcage help
./zig-out/bin/nexcage help checkpoint
./zig-out/bin/nexcage help restore
```

#### 3.2 Package Validation
```bash
# Test DEB package structure
find packaging/debian -name "*.control" -o -name "*.rules" -o -name "*.changelog" | xargs ls -la

# Validate changelog format
head -n 10 packaging/debian/changelog

# Check for any linting issues
if command -v lintian >/dev/null 2>&1; then
    echo "Lintian available for package validation"
else
    echo "Consider installing lintian: sudo apt install lintian"
fi
```

### Step 4: Commit Release Changes

#### 4.1 Create Release Commit
```bash
# Stage all changes
git add .

# Create release commit
git commit -m "🔖 Release v${NEXT_VERSION}

📈 VERSION UPDATE:
- Updated binary version to ${NEXT_VERSION}
- Updated documentation and examples
- Updated package changelog
- Updated README.md version references

🎯 RELEASE READY:
- All tests passing
- Documentation updated
- Package configuration validated
- Ready for tag creation

Status: RELEASE v${NEXT_VERSION} PREPARED ✅"

# Push changes
git push origin main
```

#### 4.2 Verify CI Status
```bash
# Check GitHub Actions status
gh run list --limit 5

# Wait for CI to pass before proceeding
echo "Ensure all CI checks pass before creating tag"
```

### Step 5: Create Release Tag

#### 5.1 Create Annotated Tag
```bash
# Create comprehensive tag message
git tag -a v${NEXT_VERSION} -m "🚀 Release v${NEXT_VERSION}

🌟 MAJOR FEATURES:
$(grep -A 10 "## \[${NEXT_VERSION}\]" docs/CHANGELOG.md | tail -n +3 | head -n -1)

🎯 RELEASE HIGHLIGHTS:
- Production-ready functionality
- Comprehensive testing validated
- Professional DEB packaging
- Multi-architecture support

📦 INSTALLATION:
DEB Package (Ubuntu/Debian):
  wget https://github.com/cageforge/nexcage/releases/download/v${NEXT_VERSION}/nexcage_${NEXT_VERSION}-1_amd64.deb
  sudo dpkg -i nexcage_${NEXT_VERSION}-1_amd64.deb

Binary Installation:
  wget https://github.com/cageforge/nexcage/releases/download/v${NEXT_VERSION}/nexcage-linux-x86_64
  chmod +x nexcage-linux-x86_64
  sudo mv nexcage-linux-x86_64 /usr/local/bin/nexcage

📚 DOCUMENTATION:
- Installation Guide: docs/INSTALLATION.md
- ZFS Guide: docs/zfs-checkpoint-guide.md
- Architecture: docs/architecture.md

This release delivers production-ready container runtime functionality."

# Verify tag was created
git tag -v v${NEXT_VERSION} 2>/dev/null || git tag -n v${NEXT_VERSION}
```

#### 5.2 Push Tag to Trigger Release
```bash
# Push tag to GitHub (this triggers automated release workflow)
git push origin v${NEXT_VERSION}

echo "✅ Tag v${NEXT_VERSION} pushed to GitHub"
echo "🔄 GitHub Actions will now:"
echo "   1. Build binaries for x86_64 and ARM64"
echo "   2. Create DEB packages for both architectures"  
echo "   3. Run package validation tests"
echo "   4. Create GitHub release with all artifacts"
echo "   5. Generate comprehensive release notes"
```

### Step 6: Monitor Release Build

#### 6.1 Watch GitHub Actions
```bash
# Monitor the release workflow
gh run watch

# Alternative: Check via web
echo "Monitor release progress at:"
echo "https://github.com/cageforge/nexcage/actions"
```

#### 6.2 Verify Artifacts Generation
```bash
# Check if release workflow completes successfully
gh run list --workflow=release.yml --limit 1

# Once complete, verify release was created
gh release view v${NEXT_VERSION}

# List release assets
gh release view v${NEXT_VERSION} --json assets --jq '.assets[].name'
```

### Step 7: Post-Release Validation

#### 7.1 Test Release Assets
```bash
# Download and test DEB package
mkdir -p /tmp/release-test
cd /tmp/release-test

# Download DEB package
gh release download v${NEXT_VERSION} --pattern "*.deb"

# Test DEB package (in container to avoid system changes)
docker run --rm -v $(pwd):/test ubuntu:22.04 bash -c "
    apt update && apt install -y /test/*.deb
    nexcage version
    nexcage help
"

# Download and test binary
gh release download v${NEXT_VERSION} --pattern "*linux-x86_64"
chmod +x nexcage-linux-x86_64
./nexcage-linux-x86_64 version

# Cleanup
cd - && rm -rf /tmp/release-test
```

#### 7.2 Verify Package Installation
```bash
# Test installation instructions from release notes
echo "Test the installation commands from the release:"
echo "https://github.com/cageforge/nexcage/releases/tag/v${NEXT_VERSION}"

# Verify checksums if available
gh release view v${NEXT_VERSION} --json assets --jq '.assets[] | select(.name | contains("sha256")) | .name'
```

### Step 8: Post-Release Tasks

#### 8.1 Update Development Environment
```bash
# Switch back to main development
git checkout main
git pull origin main

# Verify local environment matches released state
git log --oneline -5
git tag --sort=-version:refname | head -5
```

#### 8.2 Announce Release
```bash
# Create announcement template
cat > RELEASE_ANNOUNCEMENT.md << EOF
# 🚀 Nexcage v${NEXT_VERSION} Released!

We're excited to announce the release of Nexcage v${NEXT_VERSION}!

## 🌟 Key Features
- [Highlight major features from CHANGELOG]

## 📦 Installation
\`\`\`bash
# DEB Package (Ubuntu/Debian)
wget https://github.com/cageforge/nexcage/releases/download/v${NEXT_VERSION}/nexcage_${NEXT_VERSION}-1_amd64.deb
sudo dpkg -i nexcage_${NEXT_VERSION}-1_amd64.deb

# Binary Installation
wget https://github.com/cageforge/nexcage/releases/download/v${NEXT_VERSION}/nexcage-linux-x86_64
chmod +x nexcage-linux-x86_64
sudo mv nexcage-linux-x86_64 /usr/local/bin/nexcage
\`\`\`

## 📚 Documentation
- [Installation Guide](docs/INSTALLATION.md)
- [ZFS Checkpoint Guide](docs/zfs-checkpoint-guide.md)
- [Release Notes](https://github.com/cageforge/nexcage/releases/tag/v${NEXT_VERSION})

Thank you to all contributors who made this release possible!
EOF

echo "Use RELEASE_ANNOUNCEMENT.md for social media, forums, etc."
```

#### 8.3 Prepare for Next Development Cycle
```bash
# Create next development version in [Unreleased] section
echo "Consider updating docs/CHANGELOG.md [Unreleased] section with:"
echo "- Planned features for next release"
echo "- Known issues to address"
echo "- Community requests"

# Update roadmap if needed
echo "Update Roadmap/ROADMAP.md with:"
echo "- Completed features from this release"
echo "- Next sprint/version planning"
echo "- Updated progress metrics"
```

## 🔧 Troubleshooting

### Common Issues

#### Release Workflow Fails
```bash
# Check workflow logs
gh run view --log

# Common fixes:
# 1. Check Zig version in workflow matches project requirements
# 2. Verify all files are committed and pushed
# 3. Check for syntax errors in packaging files
# 4. Ensure tag follows semantic versioning
```

#### DEB Package Build Fails
```bash
# Test package build locally with Docker
docker run --rm -v $(pwd):/src -w /src ubuntu:22.04 bash -c "
    apt update && apt install -y debhelper devscripts build-essential fakeroot
    # Add Zig installation steps
    # Run package build commands
"
```

#### Version Inconsistencies
```bash
# Check all version references
grep -r "0\.3\.0" . --exclude-dir=.git --exclude-dir=zig-out --exclude-dir=zig-cache
grep -r "v0\.3\.0" . --exclude-dir=.git --exclude-dir=zig-out --exclude-dir=zig-cache

# Update any missed references
# Ensure consistency across all files
```

### Recovery Procedures

#### Delete and Recreate Tag
```bash
# If tag needs to be recreated (only before public release)
git tag -d v${NEXT_VERSION}
git push origin :refs/tags/v${NEXT_VERSION}

# Fix issues and recreate tag
git tag -a v${NEXT_VERSION} -m "Updated tag message"
git push origin v${NEXT_VERSION}
```

#### Fix Release After Publishing
```bash
# For critical fixes after release
PATCH_VERSION="${NEXT_VERSION%.*}.$((${NEXT_VERSION##*.}+1))"
echo "Create patch release: v${PATCH_VERSION}"

# Follow same process with patch changes
```

## 📋 Release Checklist

Copy this checklist for each release:

```
Release v${NEXT_VERSION} Checklist:

Pre-Release:
□ Code freeze and final testing
□ Update version in src/oci/help.zig
□ Update version references in documentation
□ Update packaging/debian/changelog
□ Update docs/CHANGELOG.md with release date
□ Commit all changes with proper message

Release:
□ Verify CI passes on main branch
□ Create annotated git tag with comprehensive message
□ Push tag to trigger automated release workflow
□ Monitor GitHub Actions for successful completion

Post-Release:
□ Verify GitHub release created with all artifacts
□ Test DEB package installation
□ Test binary download and execution
□ Verify release notes are accurate and complete
□ Announce release through appropriate channels
□ Update development environment for next cycle

Artifacts Verified:
□ nexcage-linux-x86_64 binary
□ nexcage-linux-aarch64 binary  
□ nexcage_${NEXT_VERSION}-1_amd64.deb package
□ nexcage_${NEXT_VERSION}-1_arm64.deb package
□ checksums.txt with SHA256 hashes
□ Comprehensive release notes with installation instructions
```

## 🎯 Best Practices

### Version Strategy
- **Major**: Breaking changes, API changes
- **Minor**: New features, backward compatible
- **Patch**: Bug fixes, security updates

### Tag Messages
- Use comprehensive, detailed tag messages
- Include feature highlights and installation instructions
- Reference documentation and breaking changes

### Release Notes
- Automated generation includes installation instructions
- Highlight major features and improvements
- Include migration guide for breaking changes

### Communication
- Announce releases through multiple channels
- Provide clear upgrade instructions
- Document any required configuration changes

---

**🎉 Happy Releasing!**

This process ensures consistent, professional releases with automated DEB package generation and comprehensive documentation.
