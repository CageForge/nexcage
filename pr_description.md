# Comprehensive Documentation and Architecture Update

## Changes Overview

This PR introduces comprehensive documentation updates and architectural improvements to the Proxmox LXCRI project.

### Documentation Additions
- Added Development Guide (`docs/dev_guide.md`)
- Added Onboarding Guide (`docs/onboarding.md`)
- Added Technical Stack Documentation (`docs/tech_stack.md`)
- Added Proxmox-K8s Integration Guide (`docs/proxmox-k8s-integration.md`)
- Updated Architecture Documentation (`docs/architecture.md`, `docs/architecture.puml`)

### Project Structure Improvements
- Moved build and installation scripts to `scripts/` directory
- Added bootstrap script for environment setup
- Updated Makefile to reflect new script locations
- Reorganized test structure for better maintainability

### Implementation Updates
- Enhanced OCI hooks implementation
- Added comprehensive test suite
- Improved error handling and logging

### License and Compliance
- Added Apache 2.0 License
- Added NOTICE file
- Added CONTRIBUTING.md
- Added CODE_OF_CONDUCT.md

## Testing
- [x] All tests pass (`zig build test`)
- [x] Integration tests pass
- [x] Security tests pass
- [x] Build process works with new script locations

## Documentation
- [x] All new documentation is in English
- [x] Documentation follows project style guide
- [x] Architecture diagrams are up to date
- [x] Technical stack is accurately documented

## Checklist
- [x] Code follows Zig style guide
- [x] All tests pass
- [x] Documentation is complete
- [x] No memory leaks
- [x] Error handling is complete
- [x] Logging is appropriate
- [x] Performance is considered

## Related Issues
- #123 - Documentation improvements
- #124 - Architecture update
- #125 - Script reorganization

## Next Steps
1. Review and merge this PR
2. Update project roadmap
3. Create follow-up issues for future improvements 