# Quick Release Guide

**Fast reference for experienced maintainers**

## 🚀 Quick Commands

```bash
# 1. Set version
NEXT_VERSION="0.4.0"

# 2. Update code version
sed -i 's/version [0-9]\+\.[0-9]\+\.[0-9]\+/version '${NEXT_VERSION}'/' src/oci/help.zig

# 3. Update documentation
sed -i 's/Version-[0-9]\+\.[0-9]\+\.[0-9]\+/Version-'${NEXT_VERSION}'/' README.md
sed -i 's/nexcage_[0-9]\+\.[0-9]\+\.[0-9]\+-1/nexcage_'${NEXT_VERSION}'-1/g' README.md docs/INSTALLATION.md
sed -i '1s/([0-9]\+\.[0-9]\+\.[0-9]\+-1)/('${NEXT_VERSION}'-1)/' packaging/debian/changelog

# 4. Update CHANGELOG.md manually
# Move [Unreleased] → [${NEXT_VERSION}] - $(date +%Y-%m-%d)

# 5. Commit and tag
git add .
git commit -m "🔖 Release v${NEXT_VERSION}"
git push origin main

# 6. Create and push tag
git tag -a v${NEXT_VERSION} -m "Release v${NEXT_VERSION}"
git push origin v${NEXT_VERSION}

# 7. Monitor release
gh run watch
```

## ✅ Checklist

- [ ] Update `src/oci/help.zig` version
- [ ] Update README.md version badge and examples  
- [ ] Update docs/INSTALLATION.md examples
- [ ] Update packaging/debian/changelog
- [ ] Update docs/CHANGELOG.md with release date
- [ ] Commit changes
- [ ] Create and push tag
- [ ] Verify GitHub Actions completes
- [ ] Test DEB package installation

## 📦 Expected Artifacts

After successful release:
- `nexcage-linux-x86_64`
- `nexcage-linux-aarch64`  
- `nexcage_${VERSION}-1_amd64.deb`
- `nexcage_${VERSION}-1_arm64.deb`
- `checksums.txt`

**See [RELEASE_PROCESS.md](RELEASE_PROCESS.md) for detailed guide.**
