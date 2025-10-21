# Container Creation Flow Diagram

## Overview
This document contains a visual representation of the container creation process in Nexcage runtime using Mermaid diagrams.

## Main Flow Diagram

```mermaid
flowchart TD
    A[Start: create command] --> B[Parse CreateOpts]
    B --> C[Validate Bundle Path]
    C --> D[Read config.json]
    D --> E[Parse OCI Configuration]
    E --> F[Validate OCI Version 1.0.2]
    F --> G[Check Required Fields]
    
    G --> H{Image Available?}
    H -->|No| I[Pull Image]
    H -->|Yes| J[Validate Image]
    I --> J
    
    J --> K[Setup LayerFS for Container]
    K --> L[Mount Image Layers]
    L --> M[Create Container Filesystem]
    M --> N[Setup Container Metadata]
    
    N --> O{Choose Runtime Type}
    O -->|LXC| P[LXC Container Creation]
    O -->|CRun| Q[CRun Container Creation]
    O -->|VM| R[VM Container Creation]
    O -->|Runc| S[Runc Container Creation]
    
    P --> T[Check Container Exists]
    T --> U{Container Exists?}
    U -->|Yes| V[Return ContainerExists Error]
    U -->|No| W{Use Raw Image?}
    
    W -->|Yes| X[Create .raw File]
    W -->|No| Y[Create ZFS Dataset]
    X --> Z[Create ZFS Dataset]
    Z --> AA[Configure LXC with Raw]
    Y --> BB[Configure LXC Container]
    
    Q --> CC[Create CRun Container]
    R --> DD[Return NotImplemented]
    S --> EE[Return NotImplemented]
    
    AA --> FF[Execute Pre-start Hooks]
    BB --> FF
    CC --> FF
    
    FF --> GG[Start Container]
    GG --> HH[Create PID File]
    HH --> II[Container Created Successfully]
    
    V --> JJ[Error Handling]
    DD --> JJ
    EE --> JJ
    
    style A fill:#e1f5fe
    style II fill:#c8e6c9
    style JJ fill:#ffcdd2
```

## Detailed LXC Flow

```mermaid
flowchart TD
    A[LXC Container Creation] --> B[Check Container Exists]
    B --> C{Container Exists?}
    C -->|Yes| D[Return ContainerExists Error]
    C -->|No| E{Use Raw Image?}
    
    E -->|Yes| F[Create .raw File]
    E -->|No| G[Create ZFS Dataset]
    
    F --> H[Create ZFS Dataset]
    H --> I[Configure LXC with Raw File]
    
    G --> J[Configure LXC Container]
    
    I --> K[Execute Pre-start Hooks]
    J --> K
    
    K --> L[Start Container]
    L --> M[Container Created Successfully]
    
    D --> N[Error Handling]
    
    style A fill:#e3f2fd
    style M fill:#c8e6c9
    style N fill:#ffcdd2
```

## Image Validation Flow

```mermaid
flowchart TD
    A[Image Validation] --> B[Check Image Exists]
    B --> C{Image Found?}
    C -->|No| D[Return ImageNotFound Error]
    C -->|Yes| E[Validate Image Manifest]
    
    E --> F[Parse manifest.json]
    F --> G{Manifest Valid?}
    G -->|No| H[Return InvalidImage Error]
    G -->|Yes| I[Check Image Configuration]
    
    I --> J[Parse config.json]
    J --> K{Config Valid?}
    K -->|No| L[Return InvalidImage Error]
    K -->|Yes| M[Verify Layer Integrity]
    
    M --> N[Check Layer Files]
    N --> O{All Layers Valid?}
    O -->|No| P[Return InvalidImage Error]
    O -->|Yes| Q[Image Validation Complete]
    
    D --> R[Error Handling]
    H --> R
    L --> R
    P --> R
    
    style A fill:#fff3e0
    style Q fill:#c8e6c9
    style R fill:#ffcdd2
```

## LayerFS Setup Flow

```mermaid
flowchart TD
    A[LayerFS Setup] --> B[Create Container Mount Point]
    B --> C[Create mounts/{container_id} Directory]
    C --> D[Setup LayerFS Instance]
    
    D --> E[Mount Image Layers]
    E --> F[Read Layers Directory]
    F --> G[Iterate Through Layer Files]
    
    G --> H{More Layers?}
    H -->|Yes| I[Create Layer Object]
    H -->|No| K[LayerFS Setup Complete]
    
    I --> J[Add Layer to LayerFS]
    J --> G
    
    style A fill:#f3e5f5
    style K fill:#c8e6c9
```

## Filesystem Creation Flow

```mermaid
flowchart TD
    A[Filesystem Creation] --> B[Create Container Rootfs]
    B --> C[Create rootfs/{container_id} Directory]
    
    C --> D[Create Standard Directories]
    D --> E[Create dev/ Directory]
    E --> F[Create proc/ Directory]
    F --> G[Create sys/ Directory]
    G --> H[Create tmp/ Directory]
    H --> I[Create var/ Directory]
    I --> J[Create run/ Directory]
    
    J --> K[Filesystem Creation Complete]
    
    style A fill:#e8f5e8
    style K fill:#c8e6c9
```

## Error Handling Flow

```mermaid
flowchart TD
    A[Error Occurs] --> B{Error Type?}
    
    B -->|InvalidJson| C[Log JSON Parse Error]
    B -->|InvalidSpec| D[Log Specification Error]
    B -->|FileError| E[Log File System Error]
    B -->|OutOfMemory| F[Log Memory Error]
    B -->|ImageNotFound| G[Log Image Not Found]
    B -->|BundleNotFound| H[Log Bundle Error]
    B -->|ContainerExists| I[Log Container Exists]
    B -->|ZFSError| J[Log ZFS Error]
    B -->|LXCError| K[Log LXC Error]
    B -->|ProxmoxError| L[Log Proxmox Error]
    B -->|ConfigError| M[Log Configuration Error]
    B -->|InvalidConfig| N[Log Invalid Config]
    B -->|InvalidRootfs| O[Log Rootfs Error]
    B -->|RuntimeNotAvailable| P[Log Runtime Error]
    
    C --> Q[Cleanup Resources]
    D --> Q
    E --> Q
    F --> Q
    G --> Q
    H --> Q
    I --> Q
    J --> Q
    K --> Q
    L --> Q
    M --> Q
    N --> Q
    O --> Q
    P --> Q
    
    Q --> R[Return Error to Caller]
    
    style A fill:#ffebee
    style R fill:#ffcdd2
```

## Performance Optimization Points

```mermaid
flowchart TD
    A[Performance Optimizations] --> B[MetadataCache LRU]
    A --> C[LayerFS Batch Operations]
    A --> D[Object Pool Templates]
    A --> E[Memory Management]
    A --> F[Graph Traversal]
    
    B --> G[95% Faster LRU Operations]
    C --> H[40% Faster Batch Operations]
    D --> I[60% Faster Layer Creation]
    E --> J[15-25% Memory Reduction]
    F --> K[30% Faster Graph Operations]
    
    G --> L[Overall 20%+ Improvement]
    H --> L
    I --> L
    J --> L
    K --> L
    
    style A fill:#e8f5e8
    style L fill:#c8e6c9
```

## Hook Execution Flow

```mermaid
flowchart TD
    A[Hook Execution] --> B{Container Hooks Exist?}
    B -->|No| C[Skip Hook Execution]
    B -->|Yes| D{Pre-start Hooks Exist?}
    
    D -->|No| E[Skip Pre-start Hooks]
    D -->|Yes| F[Execute Pre-start Hooks]
    
    F --> G[Create Hook Context]
    G --> H[Set Container ID]
    H --> I[Set Bundle Path]
    I --> J[Set State to 'creating']
    
    J --> K[Execute Hook Scripts]
    K --> L{Hooks Successful?}
    L -->|No| M[Log Hook Failure]
    L -->|Yes| N[Pre-start Hooks Complete]
    
    C --> O[Continue Container Creation]
    E --> O
    M --> O
    N --> O
    
    style A fill:#fff8e1
    style N fill:#c8e6c9
    style M fill:#ffcdd2
```

## Summary

These diagrams provide a comprehensive visual representation of the container creation process in Proxmox LXCRI, showing:

1. **Main Flow**: The complete container creation process
2. **LXC Flow**: Specific LXC container creation steps
3. **Image Validation**: Image validation and integrity checks
4. **LayerFS Setup**: LayerFS configuration and layer mounting
5. **Filesystem Creation**: Container filesystem setup
6. **Error Handling**: Comprehensive error handling flow
7. **Performance Optimizations**: Key performance improvement points
8. **Hook Execution**: Container hook execution process

Each diagram shows the decision points, error handling, and success paths, making it easy to understand the complete container creation workflow.
