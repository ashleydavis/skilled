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
    const commands_link = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "cmd" });
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
    try testing.expectEqualStrings("no skl.yaml; run skl init", scenario.fail.text());
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

//
// Asserts path exists as a symlink.
//
fn expectSymlink(io: std.Io, path: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
}
