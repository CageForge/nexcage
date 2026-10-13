const std = @import("std");

// Zig analyses only what something refers to, so a declaration nothing calls
// is never compiled, and can stop compiling without anyone seeing it. That is
// how a whole module built against an older standard library, a validator
// returning an error that does not exist and an error mapper with a duplicate
// switch prong all sat in a tree whose builds and tests passed. This refers
// to every public declaration of the three modules, so each one has to
// compile, whether anything calls it yet or not. The crun backend's are
// among them when it is built (-Denable-backend-crun=true).
test "every public declaration of core, backends and cli compiles" {
    std.testing.refAllDeclsRecursive(@import("core"));
    std.testing.refAllDeclsRecursive(@import("backends"));
    std.testing.refAllDeclsRecursive(@import("cli"));
}
