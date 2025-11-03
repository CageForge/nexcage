# Development Workflow

This document outlines the development workflow for the Nexcage runtime project.

## 1. Task Selection and Refinement

### Selecting a Task
- Tasks are selected from the `Roadmap` directory
- Each task is organized by sprint and has a detailed description
- Tasks are tracked in the main `Roadmap/README.md` file

### Task Refinement Process
If a task is not fully described or needs additional details:
1. Review the task file in the corresponding sprint directory
2. In interactive mode:
   - Discuss and clarify requirements
   - Define acceptance criteria
   - Identify dependencies
   - Document technical details
   - Update the task file with new information
3. Only proceed to implementation when the task is fully defined

## 2. Implementation

### Branch Creation
1. Create a new branch from `main`:
   ```bash
   git checkout -b feature/[task-name]
   ```
   or
   ```bash
   git checkout -b fix/[issue-name]
   ```

2. Branch naming convention:
   - Features: `feature/[task-name]`
   - Bug fixes: `fix/[issue-name]`
   - Documentation: `docs/[topic]`

### Development Process
1. Implement the task following the project's coding standards
2. Write tests for new functionality
3. Update documentation as needed
4. Ensure all tests pass
5. Run the local GitHub workflow tests if applicable

## 3. Local Workflow Testing

### Prerequisites
1. Install Docker
2. Install GitHub CLI (`gh`)
3. Install act (`curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash`)

### Testing Workflows Locally
1. List available workflows:
   ```bash
   act -l
   ```

2. Run a specific workflow:
   ```bash
   act -W .github/workflows/[workflow-name].yml
   ```

3. Run a specific job in a workflow:
   ```bash
   act -j [job-name] -W .github/workflows/[workflow-name].yml
   ```

4. Run with specific event:
   ```bash
   act push -W .github/workflows/[workflow-name].yml
   ```

### Common Issues and Solutions
1. Docker permissions:
   ```bash
   sudo usermod -aG docker $USER
   ```

2. GitHub token:
   ```bash
   gh auth login
   ```

3. Workflow secrets:
   Create a `.secrets` file with required secrets:
   ```bash
   GITHUB_TOKEN=your_token_here
   ```

4. Run with secrets:
   ```bash
   act --secret-file .secrets
   ```

## 4. Code Review and Merge

### Before Creating a Pull Request
1. Ensure all tests pass
2. Run workflow tests locally
3. Update documentation
4. Squash commits if necessary

### Pull Request Process
1. Create a pull request from your branch to `main`
2. Add a descriptive title and detailed description
3. Link related issues or tasks
4. Request reviews from team members
5. Address review comments
6. Merge when approved

## 5. Post-Merge Tasks
1. Delete the feature branch
2. Update local repository:
   ```bash
   git checkout main
   git pull
   ```
3. Start working on the next task

## 6. Sprint Completion and Release

### Backlog Formation
At the end of each sprint:
1. Review all completed tasks
2. Document any remaining work
3. Update the Roadmap with:
   - Completed tasks
   - New tasks identified
   - Adjusted priorities

### Release Process
1. Create a release branch from `main`:
   ```bash
   git checkout -b release/vX.Y.Z
   ```

2. Update version numbers and documentation

3. Create a release tag:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

4. Create a GitHub release with:
   - Release notes
   - Changelog
   - Binary artifacts
   - Documentation updates

## Build Notes: libcrun ABI Linking

Linking `libcrun` and `libsystemd` is optional and disabled by default.

```bash
# Link in non-Debug builds only
zig build -Dlink-libcrun=true

# Allow linking in Debug (if needed)
zig build -Dlink-libcrun=true -Dlink-libcrun-in-debug=true
```

If these libraries are not present on the system, omit these flags (the runtime will use the CLI fallback driver).

## Experimental: Vendored libcrun build

You can attempt to compile vendored `libcrun`/`libocispec` directly from `deps/crun`:

```bash
zig build -Duse-vendored-libcrun=true
```

Notes:
- Requires generated `config.h` and proper feature defines from crun's build system (autotools/meson). This repo does not generate them yet.
- Expected to fail out-of-the-box; intended for contributors experimenting with fully static integration.
- Prefer system `libcrun` via `-Dlink-libcrun=true` for production builds.

## Version Numbering
- Major version (X): Breaking changes
- Minor version (Y): New features
- Patch version (Z): Bug fixes

Example: v1.2.3
- 1: Major version
- 2: Minor version
- 3: Patch version

## Tools and Scripts
- Development environment setup: `scripts/setup-dev-env.sh`
- GitHub workflow testing: `tests/test_workflow.zig`
- Connection testing: `tests/test_connection.zig` 