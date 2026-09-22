//
// Tests for add.zig.
//

const std = @import("std");
const add = @import("add.zig");
const harness = @import("../lib/test/harness.zig");
const init = @import("init.zig");
const skilled = @import("skilled");
const testing = std.testing;

test "add requires --ns when non-interactive" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .repo = "acme/skills" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "--ns") != null);
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
}

test "add prompts for --ns when interactive" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    scenario.stdin_bytes = "demo\n";
    const ctx = scenario.contextInteractive(false);
    try testing.expectEqual(@as(u8, 0), try add.run(&ctx, .{ .repo = "acme/skills" }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: demo") != null);
}

test "add rejects a duplicate namespace" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .repo = "acme/both", .namespace = "demo" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "already used") != null);
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);
}

test "add rejects an invalid namespace" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .repo = "acme/skills", .namespace = ".." }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "namespace") != null);
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
}

test "add clone-then-YAML: failed scan leaves YAML unchanged" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    scenario.git.empty_repo = "empty";
    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .repo = "acme/empty", .namespace = "empty" }));

    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "skills/") != null);
}

test "add clones, appends YAML, and links" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: demo") != null);

    const dest = try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".skilled", "store", "github.com", "acme", "skills",
    });
    try testing.expect(skilled.files.fileExists(scenario.io(), try skilled.files.joinPath(scenario.allocator(), &.{ dest, "skills/hello/SKILL.md" })));

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    const st = try std.Io.Dir.cwd().statFile(scenario.io(), link_path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
}

test "add --from after init appends packages and does not clone skill packages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: demo") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/cmds") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: cmd") != null);

    try testing.expect(!pathExists(scenario, try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".skilled", "store", "github.com", "acme", "skills",
    })));
    try testing.expect(!pathExists(scenario, try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.cwd, ".cursor", "skills", "demo",
    })));
    const dest = cloneDest(scenario) orelse return error.TestUnexpectedResult;
    try testing.expect(std.mem.indexOf(u8, dest, ".skilled") == null);
    try testing.expect(!pathExists(scenario, dest));
}

test "add --from keeps an existing extra package" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/both
        \\    namespace: keep
        \\
    );

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: keep") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/both") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: demo") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: cmd") != null);
}

test "add --from skips the same namespace and same package" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: demo") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "namespace: cmd") != null);
    try testing.expectEqual(@as(usize, 1), countNeedle(yaml, "namespace: demo"));
}

test "add --from errors when a namespace is taken by a different repo" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/both
        \\    namespace: demo
        \\
    );
    const before = try scenario.readProjectYaml();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "already used") != null);
    try testing.expectEqualStrings(before, try scenario.readProjectYaml());
}

test "add --from errors when skl.yaml is missing" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .from = "acme/skl-config:teams/platform.yaml" }));
    try testing.expectEqualStrings("no skl.yaml; run skl init", scenario.fail.text());
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);
}

test "add --from with a repo argument errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{
        .repo = "acme/skills",
        .from = "acme/skl-config:teams/platform.yaml",
    }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "repo") != null);
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
}

test "add --from with --ns errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{
        .namespace = "demo",
        .from = "acme/skl-config:teams/platform.yaml",
    }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "--ns") != null);
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);
}

test "add without config errors with the missing-config message" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .repo = "acme/skills", .namespace = "demo" }));
    try testing.expectEqualStrings("no skl.yaml; run skl init", scenario.fail.text());
}

test "add --branch writes branch in YAML and clone argv includes --branch" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .branch = "feature",
    }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "branch: feature") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "local:") == null);
    try testing.expect(cloneArgvHas(scenario, "--branch"));
}

test "add --local writes absolute local, does not clone, and links that path" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .local = local,
    }));

    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, local) != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "local:") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "branch:") == null);
    try testing.expectEqual(@as(usize, 0), countGit(scenario, "clone"));

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try std.Io.Dir.cwd().readLink(scenario.io(), link_path, &buffer);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "local-skills") != null);
}

test "add --branch and --local together errors and leaves YAML unchanged" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .branch = "feature",
        .local = "/tmp/skills",
    }));
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
}

test "add --from with --branch errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{
        .from = "acme/skl-config:teams/platform.yaml",
        .branch = "feature",
    }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "--branch") != null);
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);
}

test "add --local without --ns when non-interactive errors --ns" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .repo = "acme/skills", .local = local }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "--ns") != null);
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
}

test "add --local of a missing path leaves YAML unchanged" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .local = "/no/such/path",
    }));
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
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

//
// How many times needle occurs in haystack. Used to assert a namespace was not duplicated.
//
fn countNeedle(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var rest = haystack;
    while (std.mem.indexOf(u8, rest, needle)) |index| {
        count += 1;
        rest = rest[index + needle.len ..];
    }
    return count;
}

//
// True when any recorded git argv contains token.
//
fn cloneArgvHas(scenario: *harness.Scenario, token: []const u8) bool {
    for (scenario.git.calls.items) |call| {
        if (call.argv.len < 2 or !std.mem.eql(u8, call.argv[1], "clone")) {
            continue;
        }
        for (call.argv) |arg| {
            if (std.mem.eql(u8, arg, token)) {
                return true;
            }
        }
    }
    return false;
}

//
// How many recorded argv have this git subcommand.
//
fn countGit(scenario: *harness.Scenario, subcommand: []const u8) usize {
    var n: usize = 0;
    for (scenario.git.calls.items) |call| {
        if (call.argv.len >= 2 and std.mem.eql(u8, call.argv[1], subcommand)) {
            n += 1;
        }
    }
    return n;
}

test "add --ns loc is refused and changes nothing" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    scenario.git.calls.clearRetainingCapacity();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, add.run(&ctx, .{ .repo = "acme/skills", .namespace = "loc" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "reserved") != null);
    try testing.expectEqualStrings("packages: []\n", try scenario.readProjectYaml());
    try testing.expectEqual(@as(usize, 0), scenario.git.calls.items.len);

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.cwd, ".cursor", "skills", skilled.scratch.namespace,
    });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try std.Io.Dir.cwd().readLink(scenario.io(), link_path, &buffer);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "scratch") != null);
}
