# Proxmox LXCRI Documentation Standards

## 1. General Rules

### 1.1 Documentation Language
- All documentation must be in English
- Use technical English
- Avoid slang and informal expressions

### 1.2 Format
- Use Markdown
- Follow [CommonMark](https://commonmark.org/) specification
- Use UTF-8 encoding

### 1.3 Document Structure
- First level heading (#) - document title
- Short description (2-3 sentences)
- Table of contents (for long documents)
- Main content
- References and appendices

## 2. Archival Policy
- Outdated documentation and materials are moved to `archive/`
- Deprecated code is moved to `archive/legacy/`
- New documents should reference current paths; avoid linking to `archive/` unless historical context is required

## 3. Component Versions

### 3.1 Core Components
- Zig: 0.13.0+
- Proxmox VE: 7.4+
- containerd: 1.7+
- ZFS: 2.1+
- Linux Kernel: 5.15+

### 3.2 Version Format
- Use semantic versioning (MAJOR.MINOR.PATCH)
- Use "+" for minimum versions (e.g., 1.7+)
- Use full version for exact versions (e.g., 0.13.0)

## 4. Formatting

### 4.1 Headings
```markdown
# Level 1
## Level 2
### Level 3
```

### 4.2 Code Blocks
```markdown
```zig
// Zig code
```

```bash
# Shell commands
```

```toml
# Configuration
```
```

### 4.3 Lists
- Use "-" for unordered lists
- Use "1." for ordered lists
- Use 2 spaces for nested lists

### 4.4 Tables
```markdown
| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |
```

## 5. Project Structure

### 5.1 Main Directories
- `docs/` - documentation
- `src/` - source code
- `tests/` - tests
- `scripts/` - scripts
- `Roadmap/` - roadmap
- `archive/` - archived content and `archive/legacy/` for deprecated code

### 5.2 Document Types
- `ARCHITECTURE.md` - architecture documentation
- `API.md` - API documentation
- `DEVELOPMENT.md` - developer instructions
- `DEPLOYMENT.md` - deployment instructions
- `TROUBLESHOOTING.md` - troubleshooting guide

## 6. Documentation Updates

### 6.1 Process
1. Create branch for changes
2. Update documentation
3. Check compliance with standards
4. Review changes
5. Merge to main branch

### 6.2 Responsibility
- Each developer is responsible for updating documentation with code
- Technical writer is responsible for overall documentation quality
- Maintainer is responsible for enforcing standards

## 7. Quality Control

### 7.1 Criteria
- Compliance with standards
- Information accuracy
- Completeness
- Clarity
- Error-free

### 7.2 Tools
- Markdown linters
- Spell checkers
- Link checkers
- Format checkers 