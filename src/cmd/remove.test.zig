//
// Tests for remove.zig.
//

const std = @import("std");
const add = @import("add.zig");
const harness = @import("../lib/test/harness.zig");
const init = @import("init.zig");
const remove = @import("remove.zig");
const skilled = @import("skilled");
const testing = std.testing;

test "remove unlinks and drops the YAML entry, leaving the store clone" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try remove.run(&ctx, .{ .query = "acme/skills" }));

    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());

    const dest = try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".skilled", "store", "github.com", "acme", "skills", "skills/hello/SKILL.md",
    });
    try testing.expect(skilled.files.fileExists(scenario.io(), dest));

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(scenario.io(), link_path, .{ .follow_symlinks = false }));
}

test "remove matches by repo name, SSH URL, and namespace" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: git@github.example.com:acme/cmds.git
        \\    namespace: cmd
        \\
    );

    const by_name = scenario.context();
    try testing.expectEqual(@as(u8, 0), try remove.run(&by_name, .{ .query = "skills" }));
    var yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/skills") == null);
    try testing.expect(std.mem.indexOf(u8, yaml, "cmds") != null);

    const by_ssh = scenario.context();
    try testing.expectEqual(@as(u8, 0), try remove.run(&by_ssh, .{ .query = "git@github.example.com:acme/cmds.git" }));
    yaml = try scenario.readProjectYaml();
    try testing.expectEqualStrings("packages: []\n", yaml);
}

test "remove matches by namespace" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try remove.run(&ctx, .{ .query = "demo" }));
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
}

test "remove errors on an ambiguous match" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: acme/other
        \\    namespace: skills
        \\
    );

    const ctx = scenario.context();
    try testing.expectError(error.Failed, remove.run(&ctx, .{ .query = "skills" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "Ambiguous") != null);
    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/other") != null);
}

test "remove nosuch exits non-zero" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const ctx = scenario.context();
    try testing.expectError(error.Failed, remove.run(&ctx, .{ .query = "nosuch" }));
}

test "remove without config errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, remove.run(&ctx, .{ .query = "acme/skills" }));
    try testing.expectEqualStrings("No skl.yaml here; run skl init.", scenario.fail.text());
}

test "remove of a local package unlinks the namespace and drops YAML" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .local = local,
    }));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try remove.run(&ctx, .{ .query = "demo" }));
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(scenario.io(), link_path, .{ .follow_symlinks = false }));
}

test "remove of the scratch namespace is refused and the links survive" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, remove.run(&ctx, .{ .query = "loc" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "scratch directory") != null);

    for (try scratchLinks(scenario, scenario.cwd)) |path| {
        try expectScratchSymlink(scenario.io(), path);
    }
}

test "remove of a package leaves the scratch links alone" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try remove.run(&ctx, .{ .query = "demo" }));

    const demo_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(scenario.io(), demo_link, .{ .follow_symlinks = false }));
    for (try scratchLinks(scenario, scenario.cwd)) |path| {
        try expectScratchSymlink(scenario.io(), path);
    }
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
// Asserts path exists as a symlink.
//
fn expectScratchSymlink(io: std.Io, path: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
}
