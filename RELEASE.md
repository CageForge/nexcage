# Release Management Guide

This document outlines the process for creating and managing releases for the Proxmox LXCRI project.

## Versioning

We follow [Semantic Versioning](https://semver.org/) for our releases:

- **MAJOR** version (X.0.0) - Incompatible API changes
- **MINOR** version (0.X.0) - Add functionality in a backward-compatible manner
- **PATCH** version (0.0.X) - Backward-compatible bug fixes

## Release Process

### 1. Prepare for Release

Before creating a new release:

1. Ensure all tests pass locally:
   ```bash
   zig test .
   ```

2. Update the version in the README.md and any other relevant files.

3. Create a new branch for the release:
   ```bash
   git checkout -b release/vX.Y.Z
   ```

4. Make any necessary version updates and commit them:
   ```bash
   git add .
   git commit -m "Prepare for vX.Y.Z release"
   ```

5. Push the branch to GitHub:
   ```bash
   git push origin release/vX.Y.Z
   ```

6. Create a pull request from `release/vX.Y.Z` to `main`.

### 2. Create a Release

Once the pull request is merged to `main`:

1. Go to the [GitHub Releases page](https://github.com/yourusername/proxmox-lxcri/releases).

2. Click "Draft a new release".

3. Select the tag version (e.g., `v1.0.0`).

4. Fill in the release title and description:
   - Title: `vX.Y.Z`
   - Description: Include a summary of changes, new features, and bug fixes.

5. Click "Publish release".

The GitHub Actions workflow will automatically:
- Build the AMD64 binary
- Create a tarball
- Attach it to the release

### 3. Post-Release

After the release is published:

1. Update the development branch with any necessary changes.

2. Announce the release in relevant channels (e.g., mailing lists, forums).

## Release Checklist

- [ ] All tests pass
- [ ] Version numbers updated
- [ ] CHANGELOG.md updated
- [ ] Release notes prepared
- [ ] Release branch created and PR merged
- [ ] GitHub release created and published
- [ ] Release announced

## Rollback Procedure

If a critical issue is discovered after release:

1. Create a new patch release with the fix.

2. If necessary, mark the problematic release as "pre-release" on GitHub.

3. Communicate the issue and solution to users.

## Contact

For questions about the release process, please contact the maintainers. 