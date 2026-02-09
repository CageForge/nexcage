# System Context and Architecture Diagrams

This document provides high-level architectural diagrams showing NexCage's position in the container ecosystem.

## System Context

```mermaid
graph TB
    subgraph "External Services"
        OCI_REG[OCI Container Registry<br/>Docker Hub, ghcr.io, etc.]
        K8S_API[Kubernetes API Server]
        MONITORING[Monitoring Systems<br/>Prometheus, Grafana]
    end

    subgraph "NexCage Runtime Environment"
        CLI[NexCage CLI]
        CORE[NexCage Core]
        
        subgraph "Backend Layer"
            LXC_BE[Proxmox LXC Backend]
            CRUN_BE[crun Backend]
            RUNC_BE[runc Backend]
        end
        
        CLI --> CORE
        CORE --> LXC_BE
        CORE --> CRUN_BE
        CORE --> RUNC_BE
    end
    
    subgraph "Proxmox VE Host"
        PVE_API[Proxmox VE API]
        LXC_RT[LXC Runtime]
        PCT[pct CLI Tool]
        ZFS[ZFS Storage]
        VMBR[Network Bridge]
        
        LXC_BE --> PCT
        PCT --> PVE_API
        PVE_API --> LXC_RT
        LXC_RT --> ZFS
        LXC_RT --> VMBR
    end
    
    subgraph "OCI Runtimes"
        CRUN[crun]
        RUNC[runc]
        
        CRUN_BE --> CRUN
        RUNC_BE --> RUNC
    end
    
    OCI_REG -.->|Pull Images| CORE
    K8S_API -.->|CRI Requests| CLI
    CORE -.->|Metrics| MONITORING
    
    style CLI fill:#4CAF50
    style CORE fill:#2196F3
    style PVE_API fill:#FF9800
    style ZFS fill:#9C27B0
```

## Component Interactions

```mermaid
sequenceDiagram
    participant User
    participant CLI as NexCage CLI
    participant Core as NexCage Core
    participant Router as Backend Router
    participant LXC as LXC Backend
    participant PVE as Proxmox VE
    participant Storage as ZFS Storage

    User->>CLI: nexcage create --name web01 --image /bundle
    CLI->>Core: Parse command & load config
    Core->>Router: Route to appropriate backend
    Router->>LXC: Select LXC backend
    
    LXC->>Storage: Create ZFS dataset
    Storage-->>LXC: Dataset created
    
    LXC->>PVE: pct create with config
    PVE-->>LXC: Container created (VMID: 100)
    
    LXC->>Core: Return container info
    Core->>CLI: Success response
    CLI-->>User: Container web01 created
```

## Deployment Architecture

### Standalone Proxmox Deployment

```mermaid
graph TB
    subgraph "Proxmox VE Host"
        NEXCAGE[NexCage Runtime]
        
        subgraph "Containers"
            CT1[Container 1<br/>LXC]
            CT2[Container 2<br/>LXC]
            CT3[Container 3<br/>crun]
        end
        
        subgraph "Storage"
            ZFS_POOL[ZFS Pool: tank<br/>Dataset: containers]
            TEMPLATES[Template Storage<br/>local:vztmpl]
        end
        
        subgraph "Network"
            VMBR0[vmbr0 Bridge]
            VLAN[VLAN 100]
        end
        
        NEXCAGE --> CT1
        NEXCAGE --> CT2
        NEXCAGE --> CT3
        
        CT1 --> ZFS_POOL
        CT2 --> ZFS_POOL
        CT3 --> ZFS_POOL
        
        CT1 --> VMBR0
        CT2 --> VMBR0
        CT3 --> VLAN
        VLAN --> VMBR0
    end
    
    style NEXCAGE fill:#4CAF50
    style ZFS_POOL fill:#9C27B0
```

### Kubernetes Integration Deployment

```mermaid
graph TB
    subgraph "Kubernetes Cluster"
        KUBELET[Kubelet]
        CONTAINERD[containerd]
        
        subgraph "Pods"
            POD1[Pod 1]
            POD2[Pod 2]
            POD3[Pod 3]
        end
        
        KUBELET --> CONTAINERD
        CONTAINERD --> POD1
        CONTAINERD --> POD2
        CONTAINERD --> POD3
    end
    
    subgraph "NexCage Layer"
        CRI[CRI Plugin]
        NEXCAGE[NexCage Runtime]
        
        CONTAINERD --> CRI
        CRI --> NEXCAGE
    end
    
    subgraph "Proxmox VE Backend"
        LXC1[LXC Container 1]
        LXC2[LXC Container 2]
        LXC3[LXC Container 3]
        
        NEXCAGE --> LXC1
        NEXCAGE --> LXC2
        NEXCAGE --> LXC3
    end
    
    subgraph "Infrastructure"
        ZFS[ZFS Storage]
        NETWORK[Network Bridge]
        
        LXC1 --> ZFS
        LXC2 --> ZFS
        LXC3 --> ZFS
        
        LXC1 --> NETWORK
        LXC2 --> NETWORK
        LXC3 --> NETWORK
    end
    
    style KUBELET fill:#326CE5
    style NEXCAGE fill:#4CAF50
    style ZFS fill:#9C27B0
```

### High-Availability Cluster

```mermaid
graph TB
    subgraph "Load Balancer"
        LB[HAProxy / Nginx]
    end
    
    subgraph "Proxmox Cluster"
        subgraph "Node 1"
            NC1[NexCage]
            CT1[Containers]
            ZFS1[ZFS Storage]
            NC1 --> CT1
            CT1 --> ZFS1
        end
        
        subgraph "Node 2"
            NC2[NexCage]
            CT2[Containers]
            ZFS2[ZFS Storage]
            NC2 --> CT2
            CT2 --> ZFS2
        end
        
        subgraph "Node 3"
            NC3[NexCage]
            CT3[Containers]
            ZFS3[ZFS Storage]
            NC3 --> CT3
            CT3 --> ZFS3
        end
        
        CLUSTER[Proxmox Cluster<br/>Corosync + pve-cluster]
        
        NC1 --> CLUSTER
        NC2 --> CLUSTER
        NC3 --> CLUSTER
    end
    
    subgraph "Shared Services"
        CEPH[Ceph Storage<br/>(optional)]
        MONITORING[Monitoring<br/>Prometheus]
    end
    
    LB --> NC1
    LB --> NC2
    LB --> NC3
    
    CLUSTER -.-> CEPH
    
    NC1 -.-> MONITORING
    NC2 -.-> MONITORING
    NC3 -.-> MONITORING
    
    style LB fill:#FF5722
    style CLUSTER fill:#FF9800
    style MONITORING fill:#00BCD4
```

## Data Flow Architecture

### Container Creation Flow

```mermaid
flowchart LR
    A[User Command] --> B{Parse CLI}
    B --> C[Load Config]
    C --> D[Validate Bundle]
    D --> E{Select Backend}
    
    E -->|LXC| F1[LXC Backend]
    E -->|crun| F2[crun Backend]
    E -->|runc| F3[runc Backend]
    
    F1 --> G1[Create ZFS Dataset]
    G1 --> H1[Generate LXC Config]
    H1 --> I1[pct create]
    I1 --> J[Save State]
    
    F2 --> G2[Setup OCI Bundle]
    G2 --> H2[crun create]
    H2 --> J
    
    F3 --> G3[Setup OCI Bundle]
    G3 --> H3[runc create]
    H3 --> J
    
    J --> K[Return Success]
    
    style A fill:#4CAF50
    style E fill:#FF9800
    style J fill:#2196F3
```

### State Management Flow

```mermaid
flowchart TB
    A[Container Operation] --> B{Operation Type}
    
    B -->|create| C1[Create State]
    B -->|start| C2[Update to Running]
    B -->|stop| C3[Update to Stopped]
    B -->|delete| C4[Remove State]
    
    C1 --> D[State Storage]
    C2 --> D
    C3 --> D
    C4 --> D
    
    D --> E[/run/nexcage/containers/]
    E --> F[container-id/state.json]
    
    G[State Query] --> F
    F --> H[Return OCI State JSON]
    
    style A fill:#4CAF50
    style D fill:#2196F3
    style H fill:#9C27B0
```

## Network Architecture

```mermaid
graph TB
    subgraph "External Network"
        INTERNET[Internet]
        GATEWAY[Gateway]
    end
    
    subgraph "Proxmox VE Host"
        VMBR0[vmbr0<br/>Main Bridge]
        VMBR1[vmbr1<br/>Internal Bridge]
        
        subgraph "Container Network Namespaces"
            CT1_NET[Container 1<br/>10.0.0.101]
            CT2_NET[Container 2<br/>10.0.0.102]
            CT3_NET[Container 3<br/>192.168.1.10]
        end
        
        VMBR0 --> CT1_NET
        VMBR0 --> CT2_NET
        VMBR1 --> CT3_NET
    end
    
    INTERNET --> GATEWAY
    GATEWAY --> VMBR0
    
    style VMBR0 fill:#2196F3
    style VMBR1 fill:#4CAF50
    style GATEWAY fill:#FF9800
```

## Security Architecture Layers

```mermaid
graph TB
    subgraph "Security Layers"
        L1[Image Scanning & Verification]
        L2[Container Isolation<br/>Namespaces, cgroups]
        L3[Runtime Security<br/>AppArmor, SELinux, Seccomp]
        L4[Network Segmentation<br/>Firewall, VLANs]
        L5[Host Hardening<br/>Kernel parameters]
        L6[Infrastructure Security<br/>Proxmox security]
        
        L1 --> L2
        L2 --> L3
        L3 --> L4
        L4 --> L5
        L5 --> L6
    end
    
    subgraph "Security Features"
        F1[Signature Verification]
        F2[Capability Dropping]
        F3[Read-only Rootfs]
        F4[No New Privileges]
        F5[Resource Limits]
        
        F1 -.-> L1
        F2 -.-> L3
        F3 -.-> L3
        F4 -.-> L3
        F5 -.-> L2
    end
    
    style L1 fill:#4CAF50
    style L3 fill:#FF9800
    style L6 fill:#9C27B0
```

## Backend Selection Logic

```mermaid
flowchart TD
    A[Container Create Request] --> B{Explicit Runtime?}
    
    B -->|Yes| C[Use Specified Runtime]
    B -->|No| D{Check Config Rules}
    
    D --> E{On Proxmox VE?}
    E -->|Yes| F[Select LXC Backend]
    E -->|No| G{crun Available?}
    
    G -->|Yes| H[Select crun Backend]
    G -->|No| I{runc Available?}
    
    I -->|Yes| J[Select runc Backend]
    I -->|No| K[Error: No Runtime]
    
    C --> L[Execute with Backend]
    F --> L
    H --> L
    J --> L
    
    style A fill:#4CAF50
    style E fill:#FF9800
    style L fill:#2196F3
    style K fill:#F44336
```

## Related Documentation

- [Architecture Overview](architecture/OVERVIEW.md) - Detailed architecture
- [Plugin System](architecture/PLUGIN_SYSTEM_ARCHITECTURE.md) - Plugin architecture
- [Security](architecture/ADR-003-Security-Architecture.md) - Security details
- [Deployment](architecture/DEPLOYMENT.md) - Deployment strategies
