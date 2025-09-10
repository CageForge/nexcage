# ADR-003: Security Architecture and Defense-in-Depth Strategy

## Status
**ACCEPTED** - 2024-12-01

## Context

As a container runtime handling potentially untrusted workloads, Proxmox LXCRI requires comprehensive security measures to protect the host system, other containers, and sensitive data. The security model must address:

- Container escape prevention
- Resource exhaustion attacks
- Privilege escalation
- Network-based attacks
- Supply chain security
- Compliance requirements (PCI-DSS, HIPAA, SOX)
- Zero-trust networking
- Audit and monitoring requirements

### Threat Model

**Assets to Protect:**
- Host operating system and kernel
- Other containers and their data
- Proxmox VE infrastructure
- Network resources and services
- Configuration and secrets
- Runtime metadata and logs

**Attack Vectors:**
- Malicious container images
- Compromised container applications
- Network-based attacks
- Insider threats
- Supply chain compromises
- Configuration errors
- Runtime vulnerabilities

**Threat Actors:**
- External attackers
- Malicious insiders
- Compromised applications
- Nation-state actors
- Automated attacks/botnets

## Decision

**We implement a comprehensive defense-in-depth security architecture with multiple layers of protection, zero-trust principles, and continuous monitoring.**

### Security Architecture Layers

```
┌─────────────────────────────────────────┐
│         Application Security            │ ← Image scanning, code analysis
├─────────────────────────────────────────┤
│         Container Security              │ ← Isolation, capabilities, seccomp
├─────────────────────────────────────────┤
│         Runtime Security                │ ← LXCRI hardening, monitoring
├─────────────────────────────────────────┤
│         Network Security                │ ← Firewalls, segmentation, TLS
├─────────────────────────────────────────┤
│         Host Security                   │ ← Host hardening, kernel protection
├─────────────────────────────────────────┤
│         Infrastructure Security         │ ← Proxmox security, hardware
└─────────────────────────────────────────┘
```

### Core Security Principles

1. **Least Privilege**: Minimal necessary permissions at all levels
2. **Defense in Depth**: Multiple independent security layers
3. **Zero Trust**: Verify everything, trust nothing
4. **Fail Secure**: Secure defaults and safe failure modes
5. **Continuous Monitoring**: Real-time threat detection
6. **Compliance by Design**: Built-in regulatory compliance

## Implementation Strategy

### 1. Container Isolation and Hardening

```zig
pub const SecurityProfile = struct {
    // Container isolation
    use_user_namespaces: bool = true,
    use_pid_namespaces: bool = true,
    use_network_namespaces: bool = true,
    use_mount_namespaces: bool = true,
    use_ipc_namespaces: bool = true,
    use_uts_namespaces: bool = true,
    use_cgroup_namespaces: bool = true,
    
    // Security features
    no_new_privileges: bool = true,
    read_only_root_filesystem: bool = false,
    drop_all_capabilities: bool = true,
    allowed_capabilities: []const Capability = &[_]Capability{},
    
    // Syscall filtering
    seccomp_profile: SeccompProfile = .default_secure,
    
    // MAC (Mandatory Access Control)
    apparmor_profile: ?[]const u8 = "default-secure",
    selinux_context: ?[]const u8 = null,
    
    // Resource limits
    memory_limit: ?u64 = null,
    cpu_limit: ?f64 = null,
    pids_limit: ?u32 = 1024,
    files_limit: ?u32 = 65536,
    
    // Network security
    network_policy: NetworkPolicy = .isolated,
    allowed_ports: []const u16 = &[_]u16{},
    
    pub const NetworkPolicy = enum {
        isolated,      // No network access
        internal_only, // Internal network only
        restricted,    // Limited external access
        standard,      // Standard network access
    };
};

pub const SeccompProfile = enum {
    disabled,
    default_secure,
    strict,
    custom,
    
    pub fn getSyscallFilter(self: SeccompProfile) []const SyscallRule {
        return switch (self) {
            .disabled => &[_]SyscallRule{},
            .default_secure => &default_secure_syscalls,
            .strict => &strict_syscalls,
            .custom => loadCustomProfile(),
        };
    }
};
```

### 2. Runtime Security Monitoring

```zig
pub const SecurityMonitor = struct {
    anomaly_detector: AnomalyDetector,
    threat_detector: ThreatDetector,
    compliance_monitor: ComplianceMonitor,
    audit_logger: AuditLogger,
    
    pub fn init(allocator: Allocator, config: SecurityConfig) !SecurityMonitor {
        return SecurityMonitor{
            .anomaly_detector = try AnomalyDetector.init(allocator, config.anomaly_config),
            .threat_detector = try ThreatDetector.init(allocator, config.threat_config),
            .compliance_monitor = try ComplianceMonitor.init(allocator, config.compliance_config),
            .audit_logger = try AuditLogger.init(allocator, config.audit_config),
        };
    }
    
    pub fn monitorContainer(self: *SecurityMonitor, container: *Container) !void {
        // Continuous monitoring
        try self.anomaly_detector.analyzeContainer(container);
        try self.threat_detector.scanContainer(container);
        try self.compliance_monitor.checkContainer(container);
        
        // Log security events
        try self.audit_logger.logContainerActivity(container);
    }
};

pub const AnomalyDetector = struct {
    baseline_metrics: ContainerMetrics,
    threshold_config: ThresholdConfig,
    
    pub fn analyzeContainer(self: *AnomalyDetector, container: *Container) !void {
        const current_metrics = try container.getMetrics();
        
        // Detect resource usage anomalies
        if (current_metrics.cpu_usage > self.baseline_metrics.cpu_usage * 3.0) {
            try self.raiseSecurityAlert(.high, "Abnormal CPU usage detected", container.id);
        }
        
        // Detect network anomalies
        if (current_metrics.network_connections > self.threshold_config.max_connections) {
            try self.raiseSecurityAlert(.medium, "Excessive network connections", container.id);
        }
        
        // Detect filesystem anomalies
        if (current_metrics.file_operations > self.threshold_config.max_file_ops) {
            try self.raiseSecurityAlert(.medium, "Excessive file operations", container.id);
        }
    }
    
    fn raiseSecurityAlert(self: *AnomalyDetector, severity: AlertSeverity, message: []const u8, container_id: []const u8) !void {
        const alert = SecurityAlert{
            .severity = severity,
            .message = message,
            .container_id = container_id,
            .timestamp = std.time.nanoTimestamp(),
            .detector = "anomaly_detector",
        };
        
        try self.sendAlert(alert);
    }
};
```

### 3. Image and Supply Chain Security

```zig
pub const ImageScanner = struct {
    vulnerability_db: VulnerabilityDatabase,
    signature_verifier: SignatureVerifier,
    policy_engine: PolicyEngine,
    
    pub fn scanImage(self: *ImageScanner, image_ref: []const u8) !ScanResult {
        var scan_result = ScanResult.init();
        
        // Download and verify image
        const image = try self.downloadImage(image_ref);
        defer image.deinit();
        
        // Verify digital signatures
        const signature_valid = try self.signature_verifier.verify(image);
        if (!signature_valid) {
            scan_result.addCriticalFinding("Image signature verification failed");
            return scan_result;
        }
        
        // Scan for vulnerabilities
        const vulnerabilities = try self.vulnerability_db.scan(image);
        for (vulnerabilities) |vuln| {
            scan_result.addVulnerability(vuln);
        }
        
        // Check against security policies
        const policy_violations = try self.policy_engine.check(image);
        for (policy_violations) |violation| {
            scan_result.addPolicyViolation(violation);
        }
        
        return scan_result;
    }
};

pub const ScanResult = struct {
    critical_findings: std.ArrayList(Finding),
    high_findings: std.ArrayList(Finding),
    medium_findings: std.ArrayList(Finding),
    low_findings: std.ArrayList(Finding),
    info_findings: std.ArrayList(Finding),
    
    pub fn isSecure(self: *const ScanResult) bool {
        return self.critical_findings.items.len == 0 and
               self.high_findings.items.len == 0;
    }
    
    pub fn getRiskScore(self: *const ScanResult) f32 {
        var score: f32 = 0.0;
        score += @as(f32, @floatFromInt(self.critical_findings.items.len)) * 10.0;
        score += @as(f32, @floatFromInt(self.high_findings.items.len)) * 7.0;
        score += @as(f32, @floatFromInt(self.medium_findings.items.len)) * 4.0;
        score += @as(f32, @floatFromInt(self.low_findings.items.len)) * 1.0;
        return score;
    }
};
```

### 4. Network Security and Microsegmentation

```zig
pub const NetworkSecurityManager = struct {
    firewall_manager: FirewallManager,
    network_policies: std.ArrayList(NetworkPolicy),
    traffic_analyzer: TrafficAnalyzer,
    
    pub const NetworkPolicy = struct {
        name: []const u8,
        selector: ContainerSelector,
        ingress_rules: []const IngressRule,
        egress_rules: []const EgressRule,
        default_deny: bool = true,
    };
    
    pub const IngressRule = struct {
        from: []const NetworkSelector,
        ports: []const PortSpec,
        protocols: []const Protocol,
    };
    
    pub const EgressRule = struct {
        to: []const NetworkSelector,
        ports: []const PortSpec,
        protocols: []const Protocol,
    };
    
    pub fn applyNetworkPolicy(self: *NetworkSecurityManager, container: *Container, policy: NetworkPolicy) !void {
        // Configure container network namespace
        try self.configureNetworkNamespace(container, policy);
        
        // Set up firewall rules
        try self.firewall_manager.applyRules(container, policy);
        
        // Enable traffic monitoring
        try self.traffic_analyzer.monitorContainer(container);
    }
    
    pub fn detectNetworkThreats(self: *NetworkSecurityManager, container: *Container) ![]const ThreatDetection {
        const traffic_analysis = try self.traffic_analyzer.analyze(container);
        var threats = std.ArrayList(ThreatDetection).init(self.allocator);
        
        // Detect port scanning
        if (traffic_analysis.unique_destination_ports > 100) {
            try threats.append(ThreatDetection{
                .type = .port_scanning,
                .severity = .high,
                .description = "Potential port scanning activity detected",
            });
        }
        
        // Detect data exfiltration
        if (traffic_analysis.outbound_bytes > 100 * 1024 * 1024) { // 100MB
            try threats.append(ThreatDetection{
                .type = .data_exfiltration,
                .severity = .medium,
                .description = "Large outbound data transfer detected",
            });
        }
        
        // Detect C&C communication
        if (traffic_analysis.suspicious_domains.len > 0) {
            try threats.append(ThreatDetection{
                .type = .command_control,
                .severity = .critical,
                .description = "Communication with suspicious domains detected",
            });
        }
        
        return threats.toOwnedSlice();
    }
};
```

### 5. Compliance and Audit Framework

```zig
pub const ComplianceFramework = struct {
    standards: std.ArrayList(ComplianceStandard),
    audit_logger: AuditLogger,
    report_generator: ReportGenerator,
    
    pub const ComplianceStandard = enum {
        pci_dss,
        hipaa,
        sox,
        gdpr,
        iso27001,
        cis_docker,
        nist_800_190,
    };
    
    pub fn checkCompliance(self: *ComplianceFramework, container: *Container, standard: ComplianceStandard) !ComplianceResult {
        const checks = self.getComplianceChecks(standard);
        var result = ComplianceResult.init(standard);
        
        for (checks) |check| {
            const check_result = try check.execute(container);
            result.addCheckResult(check_result);
        }
        
        // Generate audit trail
        try self.audit_logger.logComplianceCheck(container, standard, result);
        
        return result;
    }
    
    pub fn generateComplianceReport(self: *ComplianceFramework, standard: ComplianceStandard, containers: []const Container) !ComplianceReport {
        var report = ComplianceReport.init(standard);
        
        for (containers) |container| {
            const compliance_result = try self.checkCompliance(container, standard);
            report.addContainerResult(container.id, compliance_result);
        }
        
        // Calculate overall compliance score
        report.calculateOverallScore();
        
        // Generate remediation recommendations
        try report.generateRemediation();
        
        return report;
    }
};

pub const AuditLogger = struct {
    log_file: std.fs.File,
    encryption_key: [32]u8,
    integrity_hasher: std.crypto.hash.Blake3,
    
    pub fn logSecurityEvent(self: *AuditLogger, event: SecurityEvent) !void {
        const audit_entry = AuditEntry{
            .timestamp = std.time.nanoTimestamp(),
            .event_type = event.type,
            .severity = event.severity,
            .source = event.source,
            .target = event.target,
            .description = event.description,
            .metadata = event.metadata,
        };
        
        // Serialize and encrypt audit entry
        const serialized = try std.json.stringifyAlloc(self.allocator, audit_entry, .{});
        defer self.allocator.free(serialized);
        
        const encrypted = try self.encrypt(serialized);
        defer self.allocator.free(encrypted);
        
        // Write to tamper-evident log
        try self.writeWithIntegrity(encrypted);
    }
    
    fn writeWithIntegrity(self: *AuditLogger, data: []const u8) !void {
        // Calculate integrity hash
        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(data);
        const hash = hasher.final();
        
        // Write data + hash
        try self.log_file.writeAll(data);
        try self.log_file.writeAll(&hash);
        try self.log_file.sync();
    }
};
```

## Security Configuration Templates

### High-Security Profile
```json
{
  "security_profile": "high",
  "container_isolation": {
    "user_namespaces": true,
    "all_namespaces": true,
    "no_new_privileges": true,
    "read_only_root": true,
    "drop_all_capabilities": true,
    "seccomp_profile": "strict"
  },
  "resource_limits": {
    "memory_limit": "512MB",
    "cpu_limit": 1.0,
    "pids_limit": 512,
    "files_limit": 32768
  },
  "network_security": {
    "policy": "isolated",
    "allowed_ports": [],
    "default_deny": true
  },
  "monitoring": {
    "anomaly_detection": true,
    "threat_detection": true,
    "compliance_monitoring": true,
    "audit_logging": true
  }
}
```

### Compliance Profile (PCI-DSS)
```json
{
  "security_profile": "pci_dss",
  "container_isolation": {
    "user_namespaces": true,
    "all_namespaces": true,
    "no_new_privileges": true,
    "seccomp_profile": "default_secure"
  },
  "encryption": {
    "data_at_rest": true,
    "data_in_transit": true,
    "audit_logs": true
  },
  "access_control": {
    "rbac_enabled": true,
    "mfa_required": true,
    "session_timeout": 900
  },
  "monitoring": {
    "file_integrity_monitoring": true,
    "access_logging": true,
    "vulnerability_scanning": true,
    "compliance_reporting": true
  }
}
```

## Consequences

### Positive
- **Comprehensive Protection**: Multiple layers of security reduce attack surface
- **Compliance Ready**: Built-in support for major regulatory frameworks
- **Threat Detection**: Real-time monitoring and alerting capabilities
- **Audit Trail**: Complete audit logging for forensics and compliance
- **Flexibility**: Configurable security profiles for different use cases

### Negative
- **Performance Impact**: Security features add computational overhead
- **Complexity**: Multiple security layers increase system complexity
- **Configuration Burden**: Proper security requires careful configuration
- **Learning Curve**: Team needs security expertise and training

### Risk Mitigation
- **Performance Testing**: Regular benchmarking of security overhead
- **Automated Configuration**: Templates and defaults for common scenarios
- **Documentation**: Comprehensive security guides and best practices
- **Training**: Security awareness and technical training programs

## Monitoring and Metrics

### Security Metrics
- Container escape attempts
- Privilege escalation attempts
- Abnormal resource usage patterns
- Network policy violations
- Compliance score trends
- Vulnerability detection rates
- Incident response times

### Performance Impact Metrics
- Security overhead per container
- Monitoring CPU/memory usage
- Network latency impact
- Container startup time impact

## Review Schedule

This ADR will be reviewed:
- **Next review**: 2025-03-01 (3 months - security requires frequent review)
- **Trigger events**:
  - Security incidents or breaches
  - New vulnerability disclosures
  - Regulatory requirement changes
  - Major threat landscape shifts
  - Performance impact exceeding thresholds

## References

- [NIST SP 800-190: Container Security Guide](https://csrc.nist.gov/publications/detail/sp/800-190/final)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [OWASP Container Security Top 10](https://owasp.org/www-project-container-security/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [PCI DSS Requirements](https://www.pcisecuritystandards.org/document_library)
- [Linux Security Modules](https://www.kernel.org/doc/html/latest/admin-guide/LSM/index.html)

---
**Author**: Proxmox LXCRI Security Team  
**Reviewers**: Security Committee, Compliance Team, Architecture Committee  
**Last Updated**: 2024-12-01
