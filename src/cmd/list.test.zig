//
// Tests for list.zig.
//

const std = @import("std");
const add = @import("add.zig");
const harness = @import("../lib/test/harness.zig");
const init = @import("init.zig");
const list = @import("list.zig");
const skilled = @import("skilled");
const testing = std.testing;

test "list formats package and items as ns:name including nested commands" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    scenario.git.commands_repo = "cmds";
    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_skills = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_skills, .{ .repo = "acme/skills", .namespace = "demo" }));
    const add_cmds = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_cmds, .{ .repo = "acme/cmds", .namespace = "cmd" }));

    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try list.run(&ctx, .{}));

    const out = scenario.printed();
    try testing.expect(std.mem.indexOf(u8, out, "skills") != null);
    try testing.expect(std.mem.indexOf(u8, out, "demo") != null);
    try testing.expect(std.mem.indexOf(u8, out, "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, out, "demo:hello") != null);
    try testing.expect(std.mem.indexOf(u8, out, "cmd:plan/create") != null);
}

test "list missing config errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, list.run(&ctx, .{}));
    try testing.expectEqualStrings("no skl.yaml; run skl init", scenario.fail.text());
}

test "list missing store clone still prints the YAML row" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try list.run(&ctx, .{}));
    const out = scenario.printed();
    try testing.expect(std.mem.indexOf(u8, out, "acme/skills") != null);
    try testing.expect(std.mem.indexOf(u8, out, "demo") != null);
    try testing.expect(std.mem.indexOf(u8, out, "not installed") != null);
    try testing.expect(std.mem.indexOf(u8, out, "demo:hello") == null);
}

test "list of a local row shows items from that tree" {
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
    try testing.expectEqual(@as(u8, 0), try list.run(&ctx, .{}));
    const out = scenario.printed();
    try testing.expect(std.mem.indexOf(u8, out, local) != null);
    try testing.expect(std.mem.indexOf(u8, out, "demo:hello") != null);
    try testing.expect(std.mem.indexOf(u8, out, "not installed") == null);
}

test "list of a branch row lists items from the store" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .branch = "feature",
    }));

    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try list.run(&ctx, .{}));
    const out = scenario.printed();
    try testing.expect(std.mem.indexOf(u8, out, "feature") != null);
    try testing.expect(std.mem.indexOf(u8, out, "demo:hello") != null);
}

test "list prints a scratch skill and command as loc items" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    try writeScratchItems(scenario);

    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try list.run(&ctx, .{}));

    const out = scenario.printed();
    try testing.expect(std.mem.indexOf(u8, out, "scratch") != null);
    try testing.expect(std.mem.indexOf(u8, out, "loc:hello") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Scratch hello") != null);
    try testing.expect(std.mem.indexOf(u8, out, "loc:plan/create") != null);
}

test "list prints the scratch section when the YAML lists no packages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    try writeScratchItems(scenario);

    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try list.run(&ctx, .{}));

    const out = scenario.printed();
    try testing.expect(std.mem.indexOf(u8, out, "no packages") != null);
    try testing.expect(std.mem.indexOf(u8, out, "loc:hello") != null);
}

test "list prints no scratch section when the directory is absent" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml("packages: []\n");

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try list.run(&ctx, .{}));

    const out = scenario.printed();
    try testing.expect(std.mem.indexOf(u8, out, "no packages") != null);
    try testing.expect(std.mem.indexOf(u8, out, "loc") == null);
    try testing.expect(std.mem.indexOf(u8, out, "scratch") == null);
}

test "list keeps package items when a scratch section follows" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));
    try writeScratchItems(scenario);

    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try list.run(&ctx, .{}));

    const out = scenario.printed();
    const demo_at = std.mem.indexOf(u8, out, "demo:hello");
    const loc_at = std.mem.indexOf(u8, out, "loc:hello");
    try testing.expect(demo_at != null);
    try testing.expect(loc_at != null);
    try testing.expect(demo_at.? < loc_at.?);
}

//
// A skill and a command written into this scenario's project scratch directory.
//
fn writeScratchItems(scenario: *harness.Scenario) !void {
    const allocator = scenario.allocator();
    const scratch_dir = try skilled.files.joinPath(allocator, &.{ scenario.cwd, ".skilled", "scratch" });

    const skill = try skilled.files.joinPath(allocator, &.{ scratch_dir, "skills", "hello", "SKILL.md" });
    try skilled.files.makeParentDir(scenario.io(), skill);
    try skilled.files.writeFile(scenario.io(), skill,
        \\---
        \\description: Scratch hello
        \\---
        \\
        \\# Hello
        \\
    );

    const command = try skilled.files.joinPath(allocator, &.{ scratch_dir, "commands", "plan", "create.md" });
    try skilled.files.makeParentDir(scenario.io(), command);
    try skilled.files.writeFile(scenario.io(), command,
        \\---
        \\description: Create a plan
        \\---
        \\
        \\Write a plan.
        \\
    );
}
