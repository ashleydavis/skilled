//
// Tests for update.zig.
//

const std = @import("std");
const add = @import("add.zig");
const harness = @import("../lib/test/harness.zig");
const init = @import("init.zig");
const update = @import("update.zig");
const skilled = @import("skilled");
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

test "update --branch without query errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, update.run(&ctx, .{ .branch = "main" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "package") != null);
}

test "update --local without query errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, update.run(&ctx, .{ .local = "/tmp/skills" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "package") != null);
}

test "update --branch and --local together errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, update.run(&ctx, .{
        .query = "demo",
        .branch = "main",
        .local = "/tmp/skills",
    }));
}

test "update --branch main writes branch in YAML" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&ctx, .{ .query = "demo", .branch = "main" }));
    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "branch: main") != null);
}

test "update --local writes local, clears branch, and retargets links" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&ctx, .{ .query = "demo", .local = local }));
    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "local:") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, local) != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "branch:") == null);

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try std.Io.Dir.cwd().readLink(scenario.io(), link_path, &buffer);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "local-skills") != null);
}

test "update --branch after --local clears local and links the store" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));
    const to_local = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&to_local, .{ .query = "demo", .local = local }));

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&ctx, .{ .query = "demo", .branch = "main" }));
    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "branch: main") != null);
    try testing.expect(std.mem.indexOf(u8, yaml, "local:") == null);

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, ".cursor", "skills", "demo" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try std.Io.Dir.cwd().readLink(scenario.io(), link_path, &buffer);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "github.com") != null);
}

test "no-flag update of a local row does not fetch" {
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

    scenario.git.calls.clearRetainingCapacity();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&ctx, .{ .query = "demo" }));
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "local") != null);
    for (scenario.git.calls.items) |call| {
        try testing.expect(!(call.argv.len >= 2 and std.mem.eql(u8, call.argv[1], "fetch")));
    }
}

test "update with no flags restores a deleted scratch link" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const links = try scratchLinks(scenario, scenario.cwd);
    try removeLink(scenario.io(), links[0]);

    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&ctx, .{}));

    try expectScratchSymlink(scenario.io(), links[0]);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "scratch") != null);
}

test "update --branch and --local leave the scratch links to install" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    const links = try scratchLinks(scenario, scenario.cwd);
    try removeLink(scenario.io(), links[3]);

    const local_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&local_ctx, .{ .query = "demo", .local = local }));
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(scenario.io(), links[3], .{ .follow_symlinks = false }));

    const branch_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try update.run(&branch_ctx, .{ .query = "demo", .branch = "main" }));
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(scenario.io(), links[3], .{ .follow_symlinks = false }));
}

test "update of the scratch namespace names the scratch directory and does not fetch" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    scenario.git.calls.clearRetainingCapacity();
    const ctx = scenario.context();
    try testing.expectError(error.Failed, update.run(&ctx, .{ .query = "loc" }));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "scratch directory") != null);
    for (scenario.git.calls.items) |call| {
        try testing.expect(!(call.argv.len >= 2 and std.mem.eql(u8, call.argv[1], "fetch")));
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
