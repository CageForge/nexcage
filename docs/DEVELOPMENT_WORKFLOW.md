# Development Workflow

This document outlines the development workflow for the Nexcage runtime project.

## 1. Task Selection and Refinement

### Selecting a Task
- Tasks are tracked as GitHub issues

### Task Refinement Process
If a task is not fully described, write its acceptance criteria, dependencies
and technical details into the issue before starting implementation.

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

## 6. Release

See [CI/CD — Releasing](CI_CD_SETUP.md#releasing): update `VERSION`,
`CHANGELOG.md` and `docs/releases/NOTES_v<version>.md`, then push a
`v<version>` tag. `release.yml` tests, builds and publishes the release.

## Build Notes: crun backend (optional)

The default build is Proxmox LXC only. The crun backend is enabled with
`-Denable-backend-crun=true` and compiles vendored libcrun from `deps/crun`,
which needs the submodules and two generated header sets. Only vendored
libcrun is supported; there is no CLI fallback.

The Dockerfile is the reference for those steps and works from a clean clone:

```bash
docker build --build-arg BUILD_FLAGS=-Denable-backend-crun=true -t nexcage:crun .
```

Locally:

```bash
git submodule update --init --recursive
bash scripts/gen_crun_headers_local.sh          # config.h, git-version.h
(cd deps/crun/libocispec && \
  python3 src/ocispec/generate.py --gen-ref --root=. --out=src/ocispec runtime-spec/schema && \
  python3 src/ocispec/generate.py --gen-ref --root=. --out=src/ocispec image-spec/schema)
zig build -Denable-backend-crun=true
```

`make crun-docker` runs the Docker build. In CI, `.github/workflows/crun_build.yml`
builds it on pushes to `main` and on pull requests that touch the build,
the Dockerfile or the crun backend.

## Version Numbering
- Major version (X): Breaking changes
- Minor version (Y): New features
- Patch version (Z): Bug fixes

Example: v1.2.3
- 1: Major version
- 2: Minor version
- 3: Patch version

## Tools and Scripts
- `make help` lists the build, test, packaging and documentation targets
- [scripts/README.md](../scripts/README.md) describes the scripts
- Workflows can be tried locally with `act` (section 3)
