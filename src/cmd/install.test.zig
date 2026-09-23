//
// Tests for install.zig.
//

const std = @import("std");
const harness = @import("../lib/test/harness.zig");
const init = @import("init.zig");
const install = @import("install.zig");
const skilled = @import("skilled");
const testing = std.testing;

test "install links all packages in fixture YAML" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    scenario.git.commands_repo = "cmds";
    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: acme/cmds
        \\    namespace: cmd
        \\
    );

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&ctx, .{}));

    const skills_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    const commands_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "commands", "cmd" });
    try expectSymlink(scenario.io(), skills_link);
    try expectSymlink(scenario.io(), commands_link);
}

test "install is idempotent" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const first = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&first, .{}));
    scenario.clear();
    const second = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&second, .{}));
}

test "install missing config errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, install.run(&ctx, .{}));
    try testing.expectEqualStrings("No skl.yaml here; run skl init.", scenario.fail.text());
}

test "install partial failure keeps earlier packages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    scenario.git.empty_repo = "empty";
    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: acme/empty
        \\    namespace: empty
        \\
    );

    const ctx = scenario.context();
    try testing.expectError(error.Failed, install.run(&ctx, .{}));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "acme/empty") != null);

    const skills_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    try expectSymlink(scenario.io(), skills_link);

    const empty_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "empty" });
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(scenario.io(), empty_link, .{ .follow_symlinks = false }));
}

test "init then install of empty YAML succeeds" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&ctx, .{}));
}

test "install of a branch row clones with --branch" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: feature
        \\
    );

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&ctx, .{}));
    var found = false;
    for (scenario.git.calls.items) |call| {
        if (call.argv.len < 2 or !std.mem.eql(u8, call.argv[1], "clone")) {
            continue;
        }
        for (call.argv) |arg| {
            if (std.mem.eql(u8, arg, "--branch")) {
                found = true;
            }
        }
    }
    try testing.expect(found);
}

test "install of a local row links that path and does not clone" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const yaml = try std.fmt.allocPrint(scenario.allocator(),
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    local: {s}
        \\
    , .{local});
    try scenario.writeProjectYaml(yaml);

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&ctx, .{}));
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    try expectSymlink(scenario.io(), link_path);
}

test "install missing local path keeps earlier packages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: acme/cmds
        \\    namespace: gone
        \\    local: /no/such/local/pkg
        \\
    );

    const ctx = scenario.context();
    try testing.expectError(error.Failed, install.run(&ctx, .{}));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "acme/cmds") != null);

    const skills_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    try expectSymlink(scenario.io(), skills_link);
}

//
// Asserts path exists as a symlink.
//
fn expectSymlink(io: std.Io, path: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
}

test "install links the scratch directory when the YAML lists no packages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml("packages: []\n");

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&ctx, .{}));

    for (try scratchLinks(scenario, scenario.cwd)) |path| {
        try expectScratchSymlink(scenario.io(), path);
    }
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "scratch") != null);
}

test "install restores a deleted scratch link and still links the packages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const first = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&first, .{}));
    const links = try scratchLinks(scenario, scenario.cwd);
    try removeLink(scenario.io(), links[1]);

    const second = scenario.context();
    try testing.expectEqual(@as(u8, 0), try install.run(&second, .{}));

    try expectScratchSymlink(scenario.io(), links[1]);
    const demo_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    try expectScratchSymlink(scenario.io(), demo_link);
}

test "install fails before cloning when a real file holds a scratch link path" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );
    const blocked = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".claude", "commands", "loc" });
    try skilled.files.makeParentDir(scenario.io(), blocked);
    try skilled.files.writeFile(scenario.io(), blocked, "not a link\n");

    const ctx = scenario.context();
    try testing.expectError(error.Failed, install.run(&ctx, .{}));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "will not overwrite") != null);
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);
    try testing.expectEqualStrings("not a link\n", try skilled.files.readFile(scenario.io(), scenario.allocator(), blocked));
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
