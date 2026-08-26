//
// Tests for list.zig.
//

const std = @import("std");
const add = @import("add.zig");
const harness = @import("../lib/test/harness.zig");
const init = @import("init.zig");
const list = @import("list.zig");
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
