# Modules and Dependencies

`build.zig` wires these Zig modules. An arrow points from a module to a module
it imports.

```mermaid
flowchart TB
  main["src/main.zig<br/>arguments, errors, exit codes"]
  cli["cli<br/>src/cli: commands, router"]
  core["core<br/>src/core: types, config, logging, validation"]
  backends["backends<br/>src/backends"]
  utils["utils<br/>src/utils: fs, net, lxc_converter"]
  cfg["config_integration<br/>src/core/enhanced_config.zig"]
  oci["oci_spec<br/>deps/oci-spec-zig: OCI types, bundle parser"]

  main --> cli
  main --> core
  main --> backends
  main --> utils
  cli --> core
  cli --> backends
  cli --> utils
  cli --> cfg
  cfg --> core
  backends --> core
  backends --> utils
  backends --> oci
  utils --> core
  utils --> oci
```

| Module | Root | Contents |
|---|---|---|
| `core` | `src/core/mod.zig` | Shared types and errors, config loading, logging, input validation, version |
| `cli` | `src/cli/mod.zig` | One file per command; `registry.zig` maps names to commands, `router.zig` picks the backend |
| `backends` | `src/backends/mod.zig` | One directory per backend, each compiled in or out by a build option; see [BACKENDS.md](BACKENDS.md) |
| `utils` | `src/utils/mod.zig` | Filesystem and network helpers, OCI-to-LXC conversion |
| `config_integration` | `src/core/enhanced_config.zig` | Configuration helpers imported by the CLI |
| `oci_spec` | `deps/oci-spec-zig/src/lib.zig` | Vendored copy of oci-specs-zig |
