//
// Tests for update.zig.
//

const std = @import("std");
const add = @import("add.zig");
const harness = @import("../lib/test/harness.zig");
const init = @import("init.zig");
const update = @import("update.zig");
const testing = std.testing;

test "update prints unchanged when HEAD does not move" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&ctx, .{}));
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "unchanged") != null);
}

test "update prints old SHA to new SHA when HEAD moves" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    scenario.git.next_head = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&ctx, .{ .query = "acme/skills" }));
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), scenario.git.head) != null);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), scenario.git.next_head) != null);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "unchanged") == null);
}

test "update errors on a dirty tree" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    scenario.git.dirty = true;
    const ctx = scenario.context();
    try testing.expectError(error.Failed, update.run(&ctx, .{ .query = "acme/skills" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "dirty") != null);
}

test "update without config errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, update.run(&ctx, .{}));
    try testing.expectEqualStrings("no skl.yaml; run skl init", scenario.fail.text());
}
