//
// Tests for paths.zig.
//

const std = @import("std");
const files = @import("files.zig");
const paths = @import("paths.zig");
const testing = std.testing;

//
// A POSIX-looking home used as the fake Unix HOME in every join test.
//
const fake_home = "/home/fake";

//
// A POSIX-looking home used as the fake Windows USERPROFILE when HOME is absent.
//
const fake_userprofile = "/Users/win";

//
// A project working directory used as the fake cwd.
//
const fake_cwd = "/tmp/proj";

test "homeDir uses HOME when it is set" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    try env.put("HOME", fake_home);
    try env.put("USERPROFILE", fake_userprofile);

    try testing.expectEqualStrings(fake_home, try paths.homeDir(&env));
}

test "homeDir uses USERPROFILE when HOME is absent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = std.process.Environ.Map.init(allocator);
    try env.put("USERPROFILE", fake_userprofile);

    const home = try paths.homeDir(&env);
    try testing.expectEqualStrings(fake_userprofile, home);
    try testing.expectEqualStrings(
        try files.joinPath(allocator, &.{ fake_userprofile, ".skilled", "store" }),
        try paths.storeDir(allocator, home),
    );
    try testing.expectEqualStrings(
        try files.joinPath(allocator, &.{ fake_userprofile, ".config", "skilled", "skl.yaml" }),
        try paths.globalConfigPath(allocator, home, null),
    );
}

test "homeDir uses USERPROFILE when HOME is empty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    try env.put("HOME", "");
    try env.put("USERPROFILE", fake_userprofile);

    try testing.expectEqualStrings(fake_userprofile, try paths.homeDir(&env));
}

test "homeDir errors when neither HOME nor USERPROFILE is set" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());

    try testing.expectError(error.HomeNotFound, paths.homeDir(&env));
}

test "globalConfigPath joins home/.config/skilled/skl.yaml without XDG_CONFIG_HOME" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const expected = try files.joinPath(allocator, &.{ fake_home, ".config", "skilled", "skl.yaml" });
    try testing.expectEqualStrings(expected, try paths.globalConfigPath(allocator, fake_home, null));
}

test "globalConfigPath uses XDG_CONFIG_HOME when it is set" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = std.process.Environ.Map.init(allocator);
    try env.put("XDG_CONFIG_HOME", "/xdg/config");

    const xdg = paths.xdgConfigHome(&env);
    const expected = try files.joinPath(allocator, &.{ "/xdg/config", "skilled", "skl.yaml" });
    try testing.expectEqualStrings(expected, try paths.globalConfigPath(allocator, fake_home, xdg));
}

test "globalConfigPath ignores an empty XDG_CONFIG_HOME" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = std.process.Environ.Map.init(allocator);
    try env.put("XDG_CONFIG_HOME", "");

    const expected = try files.joinPath(allocator, &.{ fake_home, ".config", "skilled", "skl.yaml" });
    try testing.expectEqualStrings(expected, try paths.globalConfigPath(allocator, fake_home, paths.xdgConfigHome(&env)));
}

test "projectConfigPath is cwd/skl.yaml" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const expected = try files.joinPath(allocator, &.{ fake_cwd, "skl.yaml" });
    try testing.expectEqualStrings(expected, try paths.projectConfigPath(allocator, fake_cwd));
}

test "storeDir is home/.skilled/store and ignores XDG_DATA_HOME" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = std.process.Environ.Map.init(allocator);
    try env.put("HOME", fake_home);
    try env.put("XDG_DATA_HOME", "/xdg/data");

    const home = try paths.homeDir(&env);
    const store_dir = try paths.storeDir(allocator, home);
    const expected = try files.joinPath(allocator, &.{ fake_home, ".skilled", "store" });
    try testing.expectEqualStrings(expected, store_dir);
    try testing.expect(std.mem.indexOf(u8, store_dir, "xdg") == null);
}

test "clonePath joins store/host/owner/repo for github.com" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const store_dir = try paths.storeDir(allocator, fake_home);
    const got = try paths.clonePath(allocator, store_dir, "github.com", "acme", "skills");
    const expected = try files.joinPath(allocator, &.{ store_dir, "github.com", "acme", "skills" });
    try testing.expectEqualStrings(expected, got);
}

test "clonePath keeps a dotted host as one directory name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const store_dir = try paths.storeDir(allocator, fake_home);
    const got = try paths.clonePath(allocator, store_dir, "github.example.com", "acme", "skills");
    const expected = try files.joinPath(allocator, &.{ store_dir, "github.example.com", "acme", "skills" });
    try testing.expectEqualStrings(expected, got);
}

test "scopeFromFlag project uses cwd for config and agent roots" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scope = try paths.scopeFromFlag(allocator, false, fake_home, fake_cwd, null);
    try testing.expectEqualStrings(try paths.projectConfigPath(allocator, fake_cwd), scope.config_path);
    try testing.expectEqualStrings(try files.joinPath(allocator, &.{ fake_cwd, ".cursor", "skills" }), scope.cursor_skills);
    try testing.expectEqualStrings(try files.joinPath(allocator, &.{ fake_cwd, ".cursor", "commands" }), scope.cursor_commands);
    try testing.expectEqualStrings(try files.joinPath(allocator, &.{ fake_cwd, ".claude", "skills" }), scope.claude_skills);
    try testing.expectEqualStrings(try files.joinPath(allocator, &.{ fake_cwd, ".claude", "commands" }), scope.claude_commands);
}

test "scopeFromFlag global uses home for agent roots and XDG for config" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const xdg: ?[]const u8 = "/xdg/config";
    const scope = try paths.scopeFromFlag(allocator, true, fake_home, fake_cwd, xdg);
    try testing.expectEqualStrings(try paths.globalConfigPath(allocator, fake_home, xdg), scope.config_path);
    try testing.expectEqualStrings(try files.joinPath(allocator, &.{ fake_home, ".cursor", "skills" }), scope.cursor_skills);
    try testing.expectEqualStrings(try files.joinPath(allocator, &.{ fake_home, ".cursor", "commands" }), scope.cursor_commands);
    try testing.expectEqualStrings(try files.joinPath(allocator, &.{ fake_home, ".claude", "skills" }), scope.claude_skills);
    try testing.expectEqualStrings(try files.joinPath(allocator, &.{ fake_home, ".claude", "commands" }), scope.claude_commands);
}

test "scopeFromFlag never resolves Cursor skills-cursor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try paths.scopeFromFlag(allocator, false, fake_home, fake_cwd, null);
    const global = try paths.scopeFromFlag(allocator, true, fake_home, fake_cwd, null);
    try testing.expect(std.mem.indexOf(u8, project.cursor_skills, "skills-cursor") == null);
    try testing.expect(std.mem.indexOf(u8, global.cursor_skills, "skills-cursor") == null);
    try testing.expect(std.mem.endsWith(u8, project.cursor_skills, "skills"));
    try testing.expect(std.mem.endsWith(u8, global.cursor_skills, "skills"));
}
