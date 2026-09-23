//
// Tests for init.zig.
//

const std = @import("std");
const init = @import("init.zig");
const harness = @import("../lib/test/harness.zig");
const skilled = @import("skilled");
const testing = std.testing;

test "init creates YAML when the project has none" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{}));

    const text = try scenario.readProjectYaml();
    try testing.expectEqualStrings("packages: []\n", text);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "Wrote") != null);
}

test "init leaves an existing empty YAML alone" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml("packages: []\n");
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{}));
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
}

test "init refuses to wipe a file that already lists packages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const original =
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    ;
    try scenario.writeProjectYaml(original);

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{}));

    const after = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, after, "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, after, "demo") != null);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "already lists packages") != null);
}

test "init -g writes the global config, not the project file" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{ .global = true }));

    try testing.expectError(error.FileNotFound, scenario.readProjectYaml());
    const global_path = try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".config", "skilled", "skl.yaml",
    });
    try testing.expectEqualStrings("packages: []\n", try skilled.files.readFile(scenario.io(), scenario.allocator(), global_path));
}

test "init --from creates a missing file from the fetched YAML" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    scenario.git.commands_repo = "cmds";
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: demo") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/cmds") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: cmd") != null);
    try expectFromInstalledPackages(scenario);
}

test "init --from fills packages: []" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    scenario.git.commands_repo = "cmds";
    try scenario.writeProjectYaml("packages: []\n");
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/cmds") != null);
    try expectFromInstalledPackages(scenario);
}

test "init --from errors when packages are already listed and leaves YAML unchanged" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const original =
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    ;
    try scenario.writeProjectYaml(original);

    const ctx = scenario.context();
    try testing.expectError(error.Failed, init.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "add --from") != null);
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);
    try testing.expect(std.mem.indexOf(u8, try scenario.readProjectYaml(), "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, try scenario.readProjectYaml(), "acme/cmds") == null);
}

test "init --from rejects a bad spec without cloning" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, init.run(&ctx, .{ .from = "acme/skl-config" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "owner/repo:path") != null);
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);
    try testing.expectError(error.FileNotFound, scenario.readProjectYaml());
}

test "init --from leaves YAML unchanged when the file at ref:path is missing" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml("packages: []\n");
    scenario.git.show_exit_code = 128;
    scenario.git.show_stderr = "fatal: path 'teams/missing.yaml' does not exist in 'HEAD'\n";

    const ctx = scenario.context();
    try testing.expectError(error.Failed, init.run(&ctx, .{ .from = "acme/skl-config:teams/missing.yaml" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "git show") != null);
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
}

test "missing-config is not an error for init" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{}));
    try testing.expect(scenario.fail.message == null);
}

//
// `--from` clones the config repo into a throwaway dir, then clones listed packages into the store
// and links them.
//
fn expectFromInstalledPackages(scenario: *harness.Scenario) !void {
    const dest = cloneDest(scenario) orelse return error.TestUnexpectedResult;
    try testing.expect(std.mem.indexOf(u8, dest, ".skilled") == null);
    try testing.expect(!pathExists(scenario, dest));
    try testing.expect(!pathExists(scenario, try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".skilled", "store", "github.com", "acme", "skl-config",
    })));
    try testing.expect(pathExists(scenario, try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".skilled", "store", "github.com", "acme", "skills",
    })));
    const skills_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    const commands_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "commands", "cmd" });
    try expectSymlink(scenario.io(), skills_link);
    try expectSymlink(scenario.io(), commands_link);
}

//
// Asserts path exists as a symlink.
//
fn expectSymlink(io: std.Io, path: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
}

//
// Dest of the first `git clone`, if clone ran.
//
fn cloneDest(scenario: *harness.Scenario) ?[]const u8 {
    for (scenario.git.calls.items) |call| {
        if (call.argv.len >= 2 and std.mem.eql(u8, call.argv[1], "clone")) {
            return call.argv[call.argv.len - 1];
        }
    }
    return null;
}

//
// True when a path exists as any kind of inode.
//
fn pathExists(scenario: *harness.Scenario, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(scenario.io(), path, .{}) catch return false;
    return true;
}

test "init creates the scratch trees and links them" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{}));

    const scratch_dir = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".skilled", "scratch" });
    try expectDirectory(scenario.io(), try skilled.files.joinPath(scenario.allocator(), &.{ scratch_dir, "skills" }));
    try expectDirectory(scenario.io(), try skilled.files.joinPath(scenario.allocator(), &.{ scratch_dir, "commands" }));
    for (try scratchLinks(scenario, scenario.cwd)) |path| {
        try expectScratchSymlink(scenario.io(), path);
    }
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "scratch") != null);
}

test "init restores a deleted scratch link" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const first = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&first, .{}));
    const links = try scratchLinks(scenario, scenario.cwd);
    try removeLink(scenario.io(), links[2]);

    const second = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&second, .{}));
    try expectScratchSymlink(scenario.io(), links[2]);
}

test "init -g links the scratch directory under home" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{ .global = true }));

    try expectDirectory(scenario.io(), try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".skilled", "scratch", "skills",
    }));
    for (try scratchLinks(scenario, scenario.home)) |path| {
        try expectScratchSymlink(scenario.io(), path);
    }
    const project_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "loc" });
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(scenario.io(), project_link, .{ .follow_symlinks = false }));
}

test "init --from links the scratch directory as well as the packages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    scenario.git.commands_repo = "cmds";
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));

    for (try scratchLinks(scenario, scenario.cwd)) |path| {
        try expectScratchSymlink(scenario.io(), path);
    }
    const demo_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    try expectScratchSymlink(scenario.io(), demo_link);
}

//
// Asserts path exists as a real directory.
//
fn expectDirectory(io: std.Io, path: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.directory, st.kind);
}

//
// The four scratch namespace links under one base directory.
//
fn scratchLinks(scenario: *harness.Scenario, base: []const u8) ![4][]const u8 {
    const allocator = scenario.allocator();
    const ns = skilled.scratch.namespace;
    return .{
        try skilled.files.joinPath(allocator, &.{ base, ".cursor", "skills", ns }),
        try skilled.files.joinPath(allocator, &.{ base, ".cursor", "commands", ns }),
        try skilled.files.joinPath(allocator, &.{ base, ".claude", "skills", ns }),
        try skilled.files.joinPath(allocator, &.{ base, ".claude", "commands", ns }),
    };
}

//
// Deletes a namespace symlink. A directory symlink answers IsDir on Windows, so deleteFile alone
// is not enough.
//
fn removeLink(io: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.IsDir => try std.Io.Dir.cwd().deleteDir(io, path),
        else => return err,
    };
}

//
// Asserts path exists as a symlink.
//
fn expectScratchSymlink(io: std.Io, path: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
}
