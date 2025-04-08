# Changelog

All notable changes to the Proxmox LXCRI project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Multi-host support with automatic failover
- Node caching to reduce API calls
- GitHub Actions workflow for CI/CD
- Release management process

### Changed
- Updated configuration to support multiple Proxmox hosts

### Fixed
- Fixed string formatting in logging statements

## [0.1.0] - YYYY-MM-DD

### Added
- Initial release
- Basic CRI implementation for Proxmox LXC
- Pod and container lifecycle management
- Configuration management
- Logging system
- Proxmox VE API integration 