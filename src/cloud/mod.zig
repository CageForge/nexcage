// Cloud integration and deployment module
// This module provides multi-cloud support for deploying proxmox-lxcri
// to various cloud providers including AWS, Azure, GCP, and DigitalOcean

pub const provider = @import("provider.zig");
pub const aws = @import("aws.zig");
pub const azure = @import("azure.zig");
pub const gcp = @import("gcp.zig");
pub const digitalocean = @import("digitalocean.zig");
pub const deployment = @import("deployment.zig");
pub const monitoring = @import("monitoring.zig");

// Re-export main types for convenience
pub const CloudProvider = provider.CloudProvider;
pub const CloudCredentials = provider.CloudCredentials;
pub const DeploymentConfig = provider.DeploymentConfig;
pub const DeploymentResult = provider.DeploymentResult;

// Cloud provider types
pub const AWSProvider = aws.AWSProvider;
pub const AzureProvider = azure.AzureProvider;
pub const GCPProvider = gcp.GCPProvider;
pub const DigitalOceanProvider = digitalocean.DigitalOceanProvider;

// Deployment engine
pub const DeploymentEngine = deployment.DeploymentEngine;
pub const TerraformGenerator = deployment.TerraformGenerator;
pub const KubernetesDeployer = deployment.KubernetesDeployer;

// Cloud monitoring
pub const CloudMetricsCollector = monitoring.CloudMetricsCollector;
pub const CloudAlerting = monitoring.CloudAlerting;

// Export all cloud-related functionality
pub const cloud = struct {
    pub const Provider = CloudProvider;
    pub const Credentials = CloudCredentials;
    pub const Config = DeploymentConfig;
    pub const Result = DeploymentResult;
    
    pub const AWS = AWSProvider;
    pub const Azure = AzureProvider;
    pub const GCP = GCPProvider;
    pub const DigitalOcean = DigitalOceanProvider;
    
    pub const Deploy = DeploymentEngine;
    pub const Terraform = TerraformGenerator;
    pub const Kubernetes = KubernetesDeployer;
    
    pub const Monitor = CloudMetricsCollector;
    pub const Alert = CloudAlerting;
};
