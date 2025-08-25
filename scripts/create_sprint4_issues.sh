#!/bin/bash

# Create Sprint 4 GitHub Issues Script
# This script creates GitHub issues for Sprint 4 using GitHub CLI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Creating Sprint 4 GitHub Issues...${NC}"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) is not installed.${NC}"
    echo -e "${YELLOW}📋 Please install GitHub CLI or create issues manually using the descriptions in:${NC}"
    echo -e "${YELLOW}   Roadmap/sprint4/github-issues.md${NC}"
    echo ""
    echo -e "${YELLOW}🔧 To install GitHub CLI:${NC}"
    echo -e "${YELLOW}   sudo apt install gh${NC}"
    echo -e "${YELLOW}   gh auth login${NC}"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}❌ Not authenticated with GitHub. Please run:${NC}"
    echo -e "${YELLOW}   gh auth login${NC}"
    exit 1
fi

# Get repository info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo -e "${GREEN}✅ Repository: ${REPO}${NC}"

# Issue #56: Fix CreateContainer Implementation
echo -e "${BLUE}📝 Creating Issue #56: Fix CreateContainer Implementation...${NC}"

gh issue create \
    --title "Fix CreateContainer Implementation - CRI Integration & Runtime Selection" \
    --body "## 🚀 Issue Overview
**Priority**: Critical  
**Effort**: 16 hours  
**Dependencies**: Sprint 3 completion

## 🎯 Objectives
- Fix CreateContainer command according to technical requirements
- Implement proper CRI integration
- Add runtime selection logic (crun vs Proxmox LXC)
- Fix OCI bundle generation

## 🔧 Technical Requirements

### CRI Integration
- **CreateContainerRequest**: Handle CRI request properly
- **PodSandbox Validation**: Validate existing sandbox
- **ContainerConfig**: Parse and validate container configuration
- **SandboxConfig**: Parse and validate sandbox configuration

### Runtime Selection
- **Algorithm Logic**: Implement runtime selection algorithm
- **crun Support**: Standard container runtime support
- **Proxmox LXC**: Special case LXC container support
- **Image Pattern Matching**: Match image names to runtime type

### OCI Bundle Generation
- **Directory Structure**: Proper bundle directory layout
- **rootfs Preparation**: Container filesystem setup
- **config.json**: OCI Runtime Spec generation
- **Mount Configuration**: Volume and secret mounts

## 🏗️ Implementation Plan

### Phase 1: Current Implementation Analysis (4 hours)
- Code review of \`src/oci/create.zig\`
- Technical requirements analysis
- Gap analysis and planning

### Phase 2: CRI Integration Implementation (6 hours)
- CRI request handling implementation
- PodSandbox validation
- Configuration validation

### Phase 3: Runtime Selection Logic (6 hours)
- Runtime selection algorithm
- Runtime-specific implementation
- Integration testing

## 📊 Success Criteria
- [ ] CreateContainer command working correctly
- [ ] CRI integration properly implemented
- [ ] Runtime selection logic working
- [ ] OCI bundle generation correct

## 📅 Timeline
**Start Date**: August 25, 2025  
**Target Completion**: August 27, 2025" \
    --label "sprint4,critical,bug,enhancement,cri,runtime" \
    --assignee "@me"

echo -e "${GREEN}✅ Issue #56 created successfully!${NC}"

# Issue #57: CRI Integration & Runtime Selection
echo -e "${BLUE}📝 Creating Issue #57: CRI Integration & Runtime Selection...${NC}"

gh issue create \
    --title "CRI Integration & Runtime Selection - CreateContainerRequest Handling" \
    --body "## 🚀 Issue Overview
**Priority**: Critical  
**Effort**: 16 hours  
**Dependencies**: Issue #56

## 🎯 Objectives
- Implement CRI CreateContainerRequest handling
- Add PodSandbox validation
- Implement ContainerConfig and SandboxConfig validation
- Add runtime selection algorithm

## 🔧 Technical Requirements

### CRI Request Handling
\`\`\`zig
// CRI CreateContainerRequest structure
pub const CreateContainerRequest = struct {
    pod_sandbox_id: []const u8,
    config: ContainerConfig,
    sandbox_config: SandboxConfig,
    
    pub fn validate(self: *const Self) !void {
        // Validate request parameters
    }
};
\`\`\`

### PodSandbox Validation
\`\`\`zig
// PodSandbox validation
pub fn validatePodSandbox(pod_sandbox_id: []const u8) !PodSandbox {
    // Check if PodSandbox exists
    // Validate PodSandbox state
    // Return PodSandbox information
}
\`\`\`

### Configuration Validation
\`\`\`zig
// Container configuration validation
pub fn validateContainerConfig(config: ContainerConfig) !void {
    // Validate image specification
    // Validate command and arguments
    // Validate environment variables
    // Validate resource limits
    // Validate security context
}
\`\`\`

## 🏗️ Implementation Plan

### Phase 1: CRI Request Handling (6 hours)
- CreateContainerRequest structure implementation
- Request validation logic
- Error handling

### Phase 2: PodSandbox Validation (5 hours)
- PodSandbox existence check
- State validation
- Network and namespace validation

### Phase 3: Configuration Validation (5 hours)
- ContainerConfig validation
- SandboxConfig validation
- Security context validation

## 📊 Success Criteria
- [ ] CRI request handling working
- [ ] PodSandbox validation implemented
- [ ] Configuration validation working
- [ ] Runtime selection algorithm working

## 📅 Timeline
**Start Date**: August 26, 2025  
**Target Completion**: August 28, 2025" \
    --label "sprint4,critical,enhancement,cri,runtime,integration" \
    --assignee "@me"

echo -e "${GREEN}✅ Issue #57 created successfully!${NC}"

# Issue #58: OCI Bundle Generation & Configuration
echo -e "${BLUE}📝 Creating Issue #58: OCI Bundle Generation & Configuration...${NC}"

gh issue create \
    --title "OCI Bundle Generation & Configuration - Bundle Structure & config.json" \
    --body "## 🚀 Issue Overview
**Priority**: Critical  
**Effort**: 16 hours  
**Dependencies**: Issue #57

## 🎯 Objectives
- Fix OCI bundle directory structure
- Generate proper config.json
- Implement rootfs preparation
- Add proper mount configuration

## 🔧 Technical Requirements

### OCI Bundle Structure
\`\`\`
/var/lib/<runtime>/<sandbox_id>/<container_id>/
├── rootfs/           # Container filesystem
├── config.json       # OCI Runtime Spec
└── mounts/           # Mount points
\`\`\`

### config.json Generation
\`\`\`zig
// OCI Runtime Spec generation
pub fn generateConfigJson(config: ContainerConfig) ![]u8 {
    // Generate OCI Runtime Spec
    // Include process configuration
    // Include mount configuration
    // Include namespace configuration
    // Include security context
}
\`\`\`

### rootfs Preparation
\`\`\`zig
// Container filesystem setup
pub fn prepareRootfs(bundle_path: []const u8, image_path: []const u8) !void {
    // Extract image layers
    // Setup overlay filesystem
    // Configure mount points
    // Set permissions
}
\`\`\`

## 🏗️ Implementation Plan

### Phase 1: Bundle Directory Structure (4 hours)
- Bundle directory creation
- Directory layout implementation
- Permission setup

### Phase 2: config.json Generation (6 hours)
- OCI Runtime Spec structure
- Process configuration
- Mount configuration
- Security context

### Phase 3: rootfs Preparation (6 hours)
- Image layer extraction
- Overlay filesystem setup
- Mount point configuration

## 📊 Success Criteria
- [ ] OCI bundle structure correct
- [ ] config.json generation working
- [ ] rootfs preparation implemented
- [ ] Mount configuration correct

## 📅 Timeline
**Start Date**: August 28, 2025  
**Target Completion**: August 30, 2025" \
    --label "sprint4,critical,enhancement,oci,bundle,configuration" \
    --assignee "@me"

echo -e "${GREEN}✅ Issue #58 created successfully!${NC}"

echo ""
echo -e "${GREEN}🎉 All Sprint 4 issues created successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Sprint 4 Summary:${NC}"
echo -e "${BLUE}   - Issue #56: Fix CreateContainer Implementation (16 hours)${NC}"
echo -e "${BLUE}   - Issue #57: CRI Integration & Runtime Selection (16 hours)${NC}"
echo -e "${BLUE}   - Issue #58: OCI Bundle Generation & Configuration (16 hours)${NC}"
echo -e "${BLUE}   - Total Effort: 48 hours${NC}"
echo -e "${BLUE}   - Timeline: August 25-30, 2025${NC}"
echo ""
echo -e "${GREEN}🚀 Sprint 4 is ready to start!${NC}"
