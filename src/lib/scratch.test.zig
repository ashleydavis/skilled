//
// Tests for scratch.zig.
//

const std = @import("std");
const failure = @import("failure.zig");
const files = @import("files.zig");
const paths = @import("paths.zig");
const scratch = @import("scratch.zig");
const testing = std.testing;

//
// A project scope and a global scope rooted in one TemporaryDir, so tests stay isolated.
//
const Fixture = struct {
    //
    // Thrown away when the test ends. Every path below lives inside it.
    //
    temporary: files.TemporaryDir,

    //
    // Project scope: agent roots and scratch under `<temporary>/project`.
    //
    project: paths.Scope,

    //
    // Global scope: agent roots and scratch under `<temporary>/home`.
    //
    global: paths.Scope,
};

//
// Builds the two scopes over empty project and home directories.
//
fn makeFixture(io: std.Io, allocator: std.mem.Allocator) !Fixture {
    var temporary = try files.TemporaryDir.create(io);
    errdefer temporary.destroy();

    const home = try temporary.join(allocator, "home");
    const project_cwd = try temporary.join(allocator, "project");
    try files.makeDirPath(io, home);
    try files.makeDirPath(io, project_cwd);

    return .{
        .temporary = temporary,
        .project = try paths.scopeFromFlag(allocator, false, home, project_cwd, null),
        .global = try paths.scopeFromFlag(allocator, true, home, project_cwd, null),
    };
}

//
// Asserts path is a symlink whose stored target is dest, compared the way the linker compares so
// a Windows `\` does not fail a correct link.
//
fn expectSymlink(io: std.Io, path: []const u8, dest: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try std.Io.Dir.cwd().readLink(io, path, &buffer);
    try testing.expect(files.samePath(buffer[0..n], dest));
}

//
// True when nothing exists at path, following no symlink.
//
fn missing(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch return true;
    return false;
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
// The four namespace link paths of one scope, in a fixed order.
//
fn linkPaths(allocator: std.mem.Allocator, scope: paths.Scope) ![4][]const u8 {
    return .{
        try files.joinPath(allocator, &.{ scope.cursor_skills, scratch.namespace }),
        try files.joinPath(allocator, &.{ scope.cursor_commands, scratch.namespace }),
        try files.joinPath(allocator, &.{ scope.claude_skills, scratch.namespace }),
        try files.joinPath(allocator, &.{ scope.claude_commands, scratch.namespace }),
    };
}

test "scratch namespace is loc" {
    try testing.expectEqualStrings("loc", scratch.namespace);
}

test "scratch isReserved matches only the exact namespace" {
    try testing.expect(scratch.isReserved("loc"));
    try testing.expect(!scratch.isReserved("local"));
    try testing.expect(!scratch.isReserved("loc2"));
    try testing.expect(!scratch.isReserved("scratch"));
    try testing.expect(!scratch.isReserved(""));
}

test "scratch ensureTrees creates both trees and the parents above them" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    try scratch.ensureTrees(io, allocator, fixture.project.scratch_dir, &fail);

    const skills = try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "skills" });
    const commands = try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "commands" });
    try testing.expectEqual(std.Io.File.Kind.directory, (try std.Io.Dir.cwd().statFile(io, skills, .{})).kind);
    try testing.expectEqual(std.Io.File.Kind.directory, (try std.Io.Dir.cwd().statFile(io, commands, .{})).kind);
}

test "scratch ensureTrees twice leaves the trees and their files alone" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    try scratch.ensureTrees(io, allocator, fixture.project.scratch_dir, &fail);
    const skill_path = try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "skills", "hello", "SKILL.md" });
    try files.makeParentDir(io, skill_path);
    try files.writeFile(io, skill_path, "Hello.\n");

    try scratch.ensureTrees(io, allocator, fixture.project.scratch_dir, &fail);
    try testing.expect(files.fileExists(io, skill_path));
}

test "scratch ensureTrees refuses a regular file where a tree belongs" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    const skills = try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "skills" });
    try files.makeDirPath(io, fixture.project.scratch_dir);
    try files.writeFile(io, skills, "not a directory\n");

    try testing.expectError(error.Failed, scratch.ensureTrees(io, allocator, fixture.project.scratch_dir, &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "skills") != null);
}

test "scratch sync links both trees into the project agent roots" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    try scratch.sync(io, allocator, fixture.project, &fail);

    const skills = try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "skills" });
    const commands = try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "commands" });
    const links = try linkPaths(allocator, fixture.project);
    try expectSymlink(io, links[0], skills);
    try expectSymlink(io, links[1], commands);
    try expectSymlink(io, links[2], skills);
    try expectSymlink(io, links[3], commands);
}

test "scratch sync of a global scope leaves the project roots alone" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    try scratch.sync(io, allocator, fixture.global, &fail);

    const global_links = try linkPaths(allocator, fixture.global);
    const project_links = try linkPaths(allocator, fixture.project);
    try expectSymlink(io, global_links[0], try files.joinPath(allocator, &.{ fixture.global.scratch_dir, "skills" }));
    for (project_links) |path| {
        try testing.expect(missing(io, path));
    }
}

test "scratch sync twice is idempotent" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    try scratch.sync(io, allocator, fixture.project, &fail);
    try scratch.sync(io, allocator, fixture.project, &fail);

    const links = try linkPaths(allocator, fixture.project);
    try expectSymlink(io, links[3], try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "commands" }));
}

test "scratch sync restores a deleted namespace link" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    try scratch.sync(io, allocator, fixture.project, &fail);
    const links = try linkPaths(allocator, fixture.project);
    try removeLink(io, links[2]);
    try testing.expect(missing(io, links[2]));

    try scratch.sync(io, allocator, fixture.project, &fail);

    const skills = try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "skills" });
    try expectSymlink(io, links[2], skills);
    try expectSymlink(io, links[0], skills);
}

test "scratch sync refuses a real file at a namespace link path" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    const links = try linkPaths(allocator, fixture.project);
    try files.makeDirPath(io, fixture.project.claude_skills);
    try files.writeFile(io, links[2], "not a link\n");

    try testing.expectError(error.Failed, scratch.sync(io, allocator, fixture.project, &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "will not overwrite") != null);
}

test "scratch sync makes a scratch skill readable through the agent link" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator);
    defer fixture.temporary.destroy();
    var fail = failure.Failure.init(allocator);

    try scratch.sync(io, allocator, fixture.project, &fail);
    const written = try files.joinPath(allocator, &.{ fixture.project.scratch_dir, "skills", "hello", "SKILL.md" });
    try files.makeParentDir(io, written);
    try files.writeFile(io, written, "Scratch hello.\n");

    const through_link = try files.joinPath(allocator, &.{ fixture.project.cursor_skills, scratch.namespace, "hello", "SKILL.md" });
    try testing.expectEqualStrings("Scratch hello.\n", try files.readFile(io, allocator, through_link));
}
