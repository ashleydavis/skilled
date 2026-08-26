//
// How the CLI, tests, and release binary are produced.
//
// Three things come out of this file:
//
//   zig build            builds the CLI into zig-out/bin/skl
//   zig build test       runs every unit test in the project
//   zig build release    copies the optimised binary to bin/<arch>/<os>/skl
//
// The library is a module of its own rather than a pile of relative imports, because two
// different roots need it: the CLI at src/main.zig and (later) any extra binaries. A module
// is how those roots share one copy of the code.
//

const std = @import("std");

//
// Registers the compile, test, run, and release steps.
//
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // Every piece of logic lives here, behind src/lib/lib.zig, which re-exports the modules by
    // name. Nothing in it knows about the command line or about the process, which is what makes
    // it all reachable from a unit test.
    //
    const lib_mod = b.addModule("skilled", .{
        .root_source_file = b.path("src/lib/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    //
    // The CLI itself: argument parsing and the wiring from the real process into the library.
    //
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("skilled", lib_mod);

    const exe = b.addExecutable(.{
        .name = "skl",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    //
    // `zig build run -- <args>` drives the freshly built CLI.
    //
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the CLI.");
    run_step.dependOn(&run_cmd.step);

    //
    // Unit tests. There are two test binaries because there are two modules: the library and the
    // CLI layer above it. Both are wired to the one `zig build test` step, so a single command
    // runs everything.
    //
    const lib_tests = b.addTest(.{ .root_module = lib_mod });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run every unit test.");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    //
    // The release build: an optimised binary at the path the smoke tests look for.
    //
    // `scripts/smoke-tests.sh --binary` runs bin/<arch>/<os>/skl. Building to it here is what
    // lets that script find the binary without extra install flags.
    //
    const release_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    release_mod.addImport("skilled", b.addModule("skilled-release", .{
        .root_source_file = b.path("src/lib/lib.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    }));

    const release_exe = b.addExecutable(.{
        .name = "skl",
        .root_module = release_mod,
    });

    //
    // Copied into the source tree rather than installed under the usual prefix, so `zig build
    // release` on its own puts the binary where the smoke tests look for it. Installing it would
    // land it under zig-out and need `--prefix "$PWD"` on every invocation.
    //
    const install_release = b.addUpdateSourceFiles();
    install_release.addCopyFileToSource(release_exe.getEmittedBin(), releasePathFor(b, target.result));

    const release_step = b.step("release", "Build the optimised binary the smoke tests drive.");
    release_step.dependOn(&install_release.step);
}

//
// Where the release binary goes, relative to the repository root.
//
// `scripts/smoke-tests.sh --binary` hard-codes this layout.
//
fn releasePathFor(b: *std.Build, target: std.Target) []const u8 {
    const architecture = switch (target.cpu.arch) {
        .x86_64 => "x64",
        .aarch64 => "arm64",
        else => @tagName(target.cpu.arch),
    };

    const operating_system = switch (target.os.tag) {
        .linux => "linux",
        .macos => "mac",
        .windows => "win",
        else => @tagName(target.os.tag),
    };

    const name = if (target.os.tag == .windows) "skl.exe" else "skl";
    return b.fmt("bin/{s}/{s}/{s}", .{ architecture, operating_system, name });
}
