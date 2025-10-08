# Scripts Directory

This directory contains automation scripts for managing project dependencies and build processes.

## Available Scripts

### 1. `update_crun.sh` - CRUN Dependency Update Script

Automatically checks for new crun versions and updates `build.zig.zon`.

**Usage:**
```bash
./scripts/update_crun.sh [OPTIONS]
```

**Options:**
- `--force` - Force update even if compatibility issues are detected
- `--check-only` - Only check for new versions, don't update
- `--verbose` - Enable verbose output
- `-h, --help` - Show help message

**Examples:**
```bash
# Check and update if compatible
./scripts/update_crun.sh

# Only check for new versions
./scripts/update_crun.sh --check-only

# Force update (may break build)
./scripts/update_crun.sh --force
```

### 2. `update_dependencies.sh` - Universal Dependency Update Script

Automatically checks and updates all dependencies in `build.zig.zon`.

**Usage:**
```bash
./scripts/update_dependencies.sh [OPTIONS]
```

**Options:**
- `--force` - Force update even if compatibility issues are detected
- `--check-only` - Only check for new versions, don't update
- `--verbose` - Enable verbose output
- `--dependency NAME` - Update only specific dependency (e.g., crun, zig-json)
- `-h, --help` - Show help message

**Examples:**
```bash
# Check and update all dependencies
./scripts/update_dependencies.sh

# Update only crun dependency
./scripts/update_dependencies.sh --dependency crun

# Only check for new versions
./scripts/update_dependencies.sh --check-only
```

**Available Dependencies:**
- `crun` - Container runtime
- `zig-json` - JSON parsing library

### 3. `check_dependencies.sh` - Dependency Status Check Script

Shows current versions and checks for updates without making changes.

**Usage:**
```bash
./scripts/check_dependencies.sh [OPTIONS]
```

**Options:**
- `--verbose` - Enable verbose output
- `--dependency NAME` - Check only specific dependency
- `-h, --help` - Show help message

**Examples:**
```bash
# Check all dependencies
./scripts/check_dependencies.sh

# Check only crun dependency
./scripts/check_dependencies.sh --dependency crun

# Verbose output
./scripts/check_dependencies.sh --verbose
```

## Features

### 🔒 **Safety Features**
- **Automatic Backup**: Creates `build.zig.zon.backup` before updates
- **Compatibility Checking**: Tests Zig compatibility for crun updates
- **Build Testing**: Verifies build success after updates
- **Rollback**: Automatically restores backup if build fails

### 🚀 **Automation Features**
- **Version Detection**: Automatically detects latest versions from GitHub
- **Hash Calculation**: Calculates SHA256 hashes for new versions
- **File Updates**: Automatically updates `build.zig.zon` with new versions
- **Status Reporting**: Comprehensive status and progress reporting

### 🎨 **User Experience**
- **Colorized Output**: Easy-to-read colored status messages
- **Progress Indicators**: Clear progress and status information
- **Help System**: Comprehensive help and usage examples
- **Error Handling**: Detailed error messages and recovery suggestions

## Workflow

### Typical Update Process

1. **Check Current Status**
   ```bash
   ./scripts/check_dependencies.sh
   ```

2. **Update Dependencies**
   ```bash
   # Update all dependencies
   ./scripts/update_dependencies.sh
   
   # Or update specific dependency
   ./scripts/update_dependencies.sh --dependency crun
   ```

3. **Verify Update**
   ```bash
   ./scripts/check_dependencies.sh
   ```

### CRUN-Specific Workflow

1. **Check CRUN Status**
   ```bash
   ./scripts/update_crun.sh --check-only
   ```

2. **Update CRUN**
   ```bash
   ./scripts/update_crun.sh
   ```

3. **Force Update (if needed)**
   ```bash
   ./scripts/update_crun.sh --force
   ```

## Configuration

### Dependency Sources

The scripts automatically detect dependencies from the following sources:

- **crun**: GitHub Releases API
- **zig-json**: GitHub Commits API

### File Locations

- **Build File**: `build.zig.zon` (project root)
- **Backup File**: `build.zig.zon.backup` (created automatically)
- **Temp Directory**: `/tmp/deps_update` (cleaned automatically)

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x scripts/*.sh
   ```

2. **Build File Not Found**
   - Ensure you're running from project root
   - Check if `build.zig.zon` exists

3. **Zig Not Found**
   - Ensure Zig is installed and in PATH
   - Use full path to Zig binary if needed

4. **Network Issues**
   - Check internet connectivity
   - Verify GitHub API access

### Recovery

If an update fails and breaks the build:

1. **Automatic Rollback**: Scripts automatically restore from backup
2. **Manual Rollback**: 
   ```bash
   cp build.zig.zon.backup build.zig.zon
   ```

## Best Practices

1. **Always Check First**: Use `--check-only` to see what updates are available
2. **Test After Updates**: Verify the build works after dependency updates
3. **Keep Backups**: Don't delete `.backup` files until you're sure everything works
4. **Monitor Compatibility**: Be aware of Zig compatibility issues with newer crun versions

## Contributing

When adding new dependencies:

1. Add dependency configuration to the `DEPENDENCIES` array
2. Implement version detection logic
3. Add update logic for the new dependency
4. Test thoroughly before committing

## License

These scripts are part of the nexcage project and follow the same license terms.
