# oci-spec-zig

Zig implementation of the Open Container Initiative specifications inspired by [`oci-spec-rs`](https://github.com/youki-dev/oci-spec-rs).

## Goals

- Provide strongly typed bindings for OCI Runtime, Image, and Distribution specifications.
- Offer code generation from upstream JSON schema files.
- Publish as a reusable Zig package that downstream projects can consume via `dependency("oci-spec-zig", .{})`.

## Layout

- `src/` — public Zig modules (`runtime`, `image`, `distribution`).
- `schemas/` — upstream JSON schema inputs.
- `tools/` — code generation utilities.
- `build.zig` — package entry that exports the `oci_spec` module.

## Usage

```zig
const std = @import("std");
const oci_spec = @import("oci_spec");

pub fn main() !void {
    std.debug.print("Runtime spec version: {s}\n", .{oci_spec.runtime.version});
}
```

Downstream projects can add the dependency in their `build.zig`:

```zig
const oci_spec_dep = b.dependency("oci-spec-zig", .{});
exe.root_module.addImport("oci_spec", oci_spec_dep.module("oci_spec"));
```

## Roadmap

1. Implement schema parser and generator (`zig build generate`).
2. Add comprehensive type coverage for Runtime spec v1.3.0.
3. Extend support for image and distribution specs.
4. Publish versioned releases once the API stabilises.

