//
// Each test's own `Io` and throwaway directory, so no two tests share a disk.
//
// The library's tests and the CLI's tests both need these. A file imported by path from both would
// belong to two modules, which Zig refuses, so `build.zig` makes this file a module and both import
// it by name.
//

//
// Each test's own `Io`.
//
pub const TestIo = @import("test_io.test.zig").TestIo;

//
// Each test's own throwaway directory.
//
pub const TemporaryDir = @import("temporary_dir.test.zig").TemporaryDir;
