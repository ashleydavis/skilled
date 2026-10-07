//
// Tests for shared.zig.
//

const std = @import("std");
const harness = @import("../lib/test/harness.zig");
const shared = @import("shared.zig");
const skilled = @import("skilled");
const testing = std.testing;

test "contentDir with local returns that path" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const ctx = scenario.context();
    const dest = try shared.contentDir(&ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .local = local,
    });
    try testing.expectEqualStrings(local, dest);
}

test "contentDir without local or branch returns the default branch store dest" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    const dest = try shared.contentDir(&ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
    });
    const expected = try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".skilled", "store", "github.com", "acme", "skills@main",
    });
    try testing.expectEqualStrings(expected, dest);
}

test "contentDir with a branch returns that branch's store dest" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    const dest = try shared.contentDir(&ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .branch = "dev",
    });
    const expected = try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.home, ".skilled", "store", "github.com", "acme", "skills@dev",
    });
    try testing.expectEqualStrings(expected, dest);
}

test "resolveLocal errors on a missing path" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    const missing = try skilled.files.joinPath(scenario.allocator(), &.{ scenario.cwd, "gone" });
    try testing.expectError(error.Failed, shared.resolveLocal(&ctx, missing));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "directory") != null);
}

test "resolveLocal errors on a directory without .git" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const dest = try scenario.temporary.join(scenario.allocator(), "not-git");
    try skilled.files.makeDirPath(scenario.io(), dest);
    const skill = try skilled.files.joinPath(scenario.allocator(), &.{ dest, "skills", "hello", "SKILL.md" });
    try skilled.files.makeParentDir(scenario.io(), skill);
    try skilled.files.writeFile(scenario.io(), skill, "# Hello\n");

    const ctx = scenario.context();
    try testing.expectError(error.Failed, shared.resolveLocal(&ctx, dest));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "git") != null);
}

test "resolveLocal errors on a git dir that fails package.scan" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const dest = try scenario.temporary.join(scenario.allocator(), "empty-git");
    try skilled.files.makeDirPath(scenario.io(), dest);
    try skilled.files.makeDirPath(scenario.io(), try skilled.files.joinPath(scenario.allocator(), &.{ dest, ".git" }));

    const ctx = scenario.context();
    try testing.expectError(error.Failed, shared.resolveLocal(&ctx, dest));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "skills/") != null);
}

test "ensureCloned missing dest without branch clones the default branch" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    var spinner = shared.newSpinner(&ctx);
    defer spinner.finish();
    const resolved = try shared.ensureCloned(&ctx, "acme/skills", null, &spinner);

    try testing.expect(cloneHasBranch(&scenario.git, skilled.config.default_branch));
    try testing.expectEqualStrings(skilled.config.default_branch, resolved.branch);
}

test "ensureCloned missing dest with branch includes --branch" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    var spinner = shared.newSpinner(&ctx);
    defer spinner.finish();
    _ = try shared.ensureCloned(&ctx, "acme/skills", "feature", &spinner);

    try testing.expect(cloneHasBranch(&scenario.git, "feature"));
}

test "ensureCloned with a branch clones its own dest and leaves the default clone alone" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    var first = shared.newSpinner(&ctx);
    defer first.finish();
    const default_clone = try shared.ensureCloned(&ctx, "acme/skills", null, &first);
    const clones_after_first = countArgv(&scenario.git, "clone");

    const again = scenario.context();
    var second = shared.newSpinner(&again);
    defer second.finish();
    const branch_clone = try shared.ensureCloned(&again, "acme/skills", "feature", &second);

    try testing.expect(!std.mem.eql(u8, default_clone.dest, branch_clone.dest));
    try testing.expectEqual(clones_after_first + 1, countArgv(&scenario.git, "clone"));
    try testing.expectEqual(@as(usize, 0), countArgv(&scenario.git, "checkout"));
}

test "ensureCloned existing branch dest does not clone again" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    var first = shared.newSpinner(&ctx);
    defer first.finish();
    _ = try shared.ensureCloned(&ctx, "acme/skills", "feature", &first);
    const clones_after_first = countArgv(&scenario.git, "clone");

    const again = scenario.context();
    var second = shared.newSpinner(&again);
    defer second.finish();
    const resolved = try shared.ensureCloned(&again, "acme/skills", "feature", &second);

    try testing.expectEqual(clones_after_first, countArgv(&scenario.git, "clone"));
    try testing.expect(!resolved.cloned);
}

test "ensureCloned refuses a branch that is not a valid name" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    var spinner = shared.newSpinner(&ctx);
    defer spinner.finish();
    try testing.expectError(error.Failed, shared.ensureCloned(&ctx, "acme/skills", "../escape", &spinner));
    try testing.expect(!cloneRan(&scenario.git));
}

//
// True when a recorded clone argv contains `--branch` and that name.
//
fn cloneHasBranch(git: *const harness.FakeGit, branch: []const u8) bool {
    for (git.calls.items) |call| {
        if (call.argv.len < 2 or !std.mem.eql(u8, call.argv[1], "clone")) {
            continue;
        }
        var i: usize = 0;
        while (i + 1 < call.argv.len) : (i += 1) {
            if (std.mem.eql(u8, call.argv[i], "--branch") and std.mem.eql(u8, call.argv[i + 1], branch)) {
                return true;
            }
        }
    }
    return false;
}

//
// True when clone ran at least once.
//
fn cloneRan(git: *const harness.FakeGit) bool {
    return countArgv(git, "clone") > 0;
}

//
// How many recorded argv have this git subcommand.
//
fn countArgv(git: *const harness.FakeGit, subcommand: []const u8) usize {
    var n: usize = 0;
    for (git.calls.items) |call| {
        if (call.argv.len >= 2 and std.mem.eql(u8, call.argv[1], subcommand)) {
            n += 1;
        }
    }
    return n;
}

test "requireOneMatch refuses the scratch namespace even when packages exist" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const packages = [_]skilled.config.Package{
        .{ .repo = "acme/skills", .namespace = "demo" },
    };
    const ctx = scenario.context();
    try testing.expectError(error.Failed, shared.requireOneMatch(
        scenario.allocator(),
        &packages,
        skilled.scratch.namespace,
        ctx.fail,
    ));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "scratch directory") != null);
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "no package matching") == null);
}

test "syncScratch creates the links and prints the scratch path" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    const scope = try shared.scopeOf(&ctx, false);
    try shared.syncScratch(&ctx, scope);

    const link_path = try skilled.files.joinPath(scenario.allocator(), &.{
        scenario.cwd, ".claude", "skills", skilled.scratch.namespace,
    });
    const st = try std.Io.Dir.cwd().statFile(scenario.io(), link_path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), scope.scratch_dir) != null);
}
