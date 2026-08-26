//
// Tests for link.zig.
//

const std = @import("std");
const failure = @import("failure.zig");
const files = @import("files.zig");
const link = @import("link.zig");
const paths = @import("paths.zig");
const testing = std.testing;

//
// A store clone plus project and global scopes, all under one TemporaryDir so tests stay isolated.
//
const Fixture = struct {
    //
    // Thrown away when the test ends. Every path below lives inside it.
    //
    temporary: files.TemporaryDir,

    //
    // Absolute path of the fake package clone (skills/ and/or commands/ under this).
    //
    store_dir: []const u8,

    //
    // Project scope: agent roots under `<temporary>/project`.
    //
    project: paths.Scope,

    //
    // Global scope: agent roots under `<temporary>/home`.
    //
    global: paths.Scope,
};

//
// Builds a fixture with optional skills and commands trees already in the store.
//
fn makeFixture(
    io: std.Io,
    allocator: std.mem.Allocator,
    with_skills: bool,
    with_commands: bool,
) !Fixture {
    var temporary = try files.TemporaryDir.create(io);
    errdefer temporary.destroy();

    const home = try temporary.join(allocator, "home");
    const project_cwd = try temporary.join(allocator, "project");
    try files.makeDirPath(io, home);
    try files.makeDirPath(io, project_cwd);

    const store_dir = try temporary.join(allocator, "store");
    try files.makeDirPath(io, store_dir);
    if (with_skills) {
        try temporary.write("store/skills/hello/SKILL.md", "Hello skill.\n");
    }
    if (with_commands) {
        try temporary.write("store/commands/plan/create.md", "Create a plan.\n");
    }

    return .{
        .temporary = temporary,
        .store_dir = store_dir,
        .project = try paths.scopeFromFlag(allocator, false, home, project_cwd, null),
        .global = try paths.scopeFromFlag(allocator, true, home, project_cwd, null),
    };
}

//
// Asserts path is a symlink whose stored target is dest.
//
fn expectSymlink(io: std.Io, path: []const u8, dest: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.sym_link, st.kind);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try std.Io.Dir.cwd().readLink(io, path, &buffer);
    try testing.expectEqualStrings(dest, buffer[0..n]);
}

//
// Asserts path is a real directory, not a symlink.
//
fn expectRealDir(io: std.Io, path: []const u8) !void {
    const st = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    try testing.expectEqual(std.Io.File.Kind.directory, st.kind);
}

//
// Asserts path does not exist (no file, dir, or symlink).
//
fn expectMissing(io: std.Io, path: []const u8) !void {
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }));
}

//
// Joins agent_root / namespace for assertions.
//
fn nsPath(allocator: std.mem.Allocator, agent_root: []const u8, namespace: []const u8) ![]const u8 {
    return files.joinPath(allocator, &.{ agent_root, namespace });
}

test "linkPackage creates skills and commands namespace links for Cursor and Claude" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, true);
    defer fixture.temporary.destroy();

    var fail = failure.Failure.init(allocator);
    try link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail);

    const skills_dest = try files.joinPath(allocator, &.{ fixture.store_dir, "skills" });
    const commands_dest = try files.joinPath(allocator, &.{ fixture.store_dir, "commands" });
    try expectSymlink(io, try nsPath(allocator, fixture.project.cursor_skills, "demo"), skills_dest);
    try expectSymlink(io, try nsPath(allocator, fixture.project.claude_skills, "demo"), skills_dest);
    try expectSymlink(io, try nsPath(allocator, fixture.project.cursor_commands, "demo"), commands_dest);
    try expectSymlink(io, try nsPath(allocator, fixture.project.claude_commands, "demo"), commands_dest);

    try expectRealDir(io, files.dirName(fixture.project.cursor_skills));
    try expectRealDir(io, files.dirName(fixture.project.claude_skills));
    try expectRealDir(io, fixture.project.cursor_skills);
    try expectRealDir(io, fixture.project.claude_commands);

    const through = try files.joinPath(allocator, &.{ fixture.project.cursor_skills, "demo", "hello", "SKILL.md" });
    try testing.expectEqualStrings("Hello skill.\n", try files.readFile(io, allocator, through));

    const nested = try files.joinPath(allocator, &.{ fixture.project.cursor_commands, "demo", "plan", "create.md" });
    try testing.expectEqualStrings("Create a plan.\n", try files.readFile(io, allocator, nested));

    try expectMissing(io, try files.joinPath(allocator, &.{ files.dirName(fixture.project.cursor_skills), "skills-cursor" }));
    try expectMissing(io, try nsPath(allocator, fixture.global.cursor_skills, "demo"));
}

test "linkPackage is idempotent when the symlink already points at the store" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, true);
    defer fixture.temporary.destroy();

    var fail = failure.Failure.init(allocator);
    try link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail);
    try link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail);

    const skills_dest = try files.joinPath(allocator, &.{ fixture.store_dir, "skills" });
    try expectSymlink(io, try nsPath(allocator, fixture.project.cursor_skills, "demo"), skills_dest);
}

test "unlinkPackage removes namespace links and leaves the store clone" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, true);
    defer fixture.temporary.destroy();

    var fail = failure.Failure.init(allocator);
    try link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail);
    try link.unlinkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail);

    try expectMissing(io, try nsPath(allocator, fixture.project.cursor_skills, "demo"));
    try expectMissing(io, try nsPath(allocator, fixture.project.claude_skills, "demo"));
    try expectMissing(io, try nsPath(allocator, fixture.project.cursor_commands, "demo"));
    try expectMissing(io, try nsPath(allocator, fixture.project.claude_commands, "demo"));

    try testing.expect(fixture.temporary.has("store/skills/hello/SKILL.md"));
    try testing.expect(fixture.temporary.has("store/commands/plan/create.md"));
}

test "unlinkPackage is a no-op when the links are already gone" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, false);
    defer fixture.temporary.destroy();

    var fail = failure.Failure.init(allocator);
    try link.unlinkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail);
}

test "linkPackage refuses to clobber a real file" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, false);
    defer fixture.temporary.destroy();

    try files.makeDirPath(io, fixture.project.cursor_skills);
    const blocking = try nsPath(allocator, fixture.project.cursor_skills, "demo");
    try files.writeFile(io, blocking, "not a link\n");

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "will not overwrite") != null);
    try testing.expectEqualStrings("not a link\n", try files.readFile(io, allocator, blocking));
}

test "linkPackage refuses a symlink that points elsewhere" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, false);
    defer fixture.temporary.destroy();

    const other = try fixture.temporary.join(allocator, "other-skills");
    try files.makeDirPath(io, other);
    try files.makeDirPath(io, fixture.project.cursor_skills);
    const blocking = try nsPath(allocator, fixture.project.cursor_skills, "demo");
    try std.Io.Dir.cwd().symLink(io, other, blocking, .{ .is_directory = true });

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "already points") != null);
    try expectSymlink(io, blocking, other);
}

test "unlinkPackage leaves a real file at the namespace path" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, false);
    defer fixture.temporary.destroy();

    try files.makeDirPath(io, fixture.project.cursor_skills);
    const blocking = try nsPath(allocator, fixture.project.cursor_skills, "demo");
    try files.writeFile(io, blocking, "keep me\n");

    var fail = failure.Failure.init(allocator);
    try link.unlinkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail);
    try testing.expectEqualStrings("keep me\n", try files.readFile(io, allocator, blocking));
}

test "linkPackage project vs global roots" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, false);
    defer fixture.temporary.destroy();

    var project_fail = failure.Failure.init(allocator);
    try link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &project_fail);
    try expectMissing(io, try nsPath(allocator, fixture.global.cursor_skills, "demo"));

    var global_fail = failure.Failure.init(allocator);
    try link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.global, &global_fail);

    const skills_dest = try files.joinPath(allocator, &.{ fixture.store_dir, "skills" });
    try expectSymlink(io, try nsPath(allocator, fixture.project.cursor_skills, "demo"), skills_dest);
    try expectSymlink(io, try nsPath(allocator, fixture.global.cursor_skills, "demo"), skills_dest);
    try expectSymlink(io, try nsPath(allocator, fixture.global.claude_skills, "demo"), skills_dest);
}

test "linkPackage skills-only does not create commands namespace links" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, false);
    defer fixture.temporary.destroy();

    var fail = failure.Failure.init(allocator);
    try link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail);

    try expectSymlink(io, try nsPath(allocator, fixture.project.cursor_skills, "demo"), try files.joinPath(allocator, &.{ fixture.store_dir, "skills" }));
    try expectMissing(io, fixture.project.cursor_commands);
    try expectMissing(io, try nsPath(allocator, fixture.project.cursor_commands, "demo"));
}

test "linkPackage commands-only does not create skills namespace links" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, false, true);
    defer fixture.temporary.destroy();

    var fail = failure.Failure.init(allocator);
    try link.linkPackage(io, allocator, fixture.store_dir, "cmd", fixture.project, &fail);

    try expectSymlink(io, try nsPath(allocator, fixture.project.cursor_commands, "cmd"), try files.joinPath(allocator, &.{ fixture.store_dir, "commands" }));
    try expectMissing(io, fixture.project.cursor_skills);
    try expectMissing(io, try nsPath(allocator, fixture.project.cursor_skills, "cmd"));
}

test "linkPackage refuses a folded .cursor symlink" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, false);
    defer fixture.temporary.destroy();

    const folded = try fixture.temporary.join(allocator, "folded");
    try files.makeDirPath(io, folded);
    try std.Io.Dir.cwd().symLink(io, folded, files.dirName(fixture.project.cursor_skills), .{ .is_directory = true });

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, link.linkPackage(io, allocator, fixture.store_dir, "demo", fixture.project, &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "symlink") != null);
}

test "linkPackage refuses an invalid namespace" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try makeFixture(io, allocator, true, false);
    defer fixture.temporary.destroy();

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, link.linkPackage(io, allocator, fixture.store_dir, "..", fixture.project, &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "namespace") != null);
}

test "mapSymlinkError AccessDenied mentions Developer Mode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectEqual(failure.Error.Failed, link.mapSymlinkError(error.AccessDenied, "skills/demo", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "Developer Mode") != null);
    try testing.expect(std.mem.indexOf(u8, fail.text(), "skills/demo") != null);
}

test "mapSymlinkError PermissionDenied mentions Developer Mode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectEqual(failure.Error.Failed, link.mapSymlinkError(error.PermissionDenied, "ns", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "Developer Mode") != null);
}

test "mapSymlinkError other failures do not mention Developer Mode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectEqual(failure.Error.Failed, link.mapSymlinkError(error.NoSpaceLeft, "ns", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "Developer Mode") == null);
    try testing.expect(std.mem.indexOf(u8, fail.text(), "no space") != null);
}
