//
// Tests for remote.zig.
//

const std = @import("std");
const failure = @import("failure.zig");
const files = @import("files.zig");
const paths = @import("paths.zig");
const remote = @import("remote.zig");
const testing = std.testing;

//
// A POSIX-looking home used when joining a parsed remote onto a store path.
//
const fake_home = "/home/fake";

test "parse expands owner/repo to github.com SSH and strips .git from the package name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const got = try remote.parse(allocator, "acme/skills.git", &fail);
    try testing.expectEqualStrings("git@github.com:acme/skills.git", got.clone_url);
    try testing.expectEqualStrings("github.com", got.host);
    try testing.expectEqualStrings("acme", got.owner);
    try testing.expectEqualStrings("skills", got.repo);
}

test "parse keeps an SSH URL as-is and strips .git from the package name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const spec = "git@github.com:acme/skills.git";
    const got = try remote.parse(allocator, spec, &fail);
    try testing.expectEqualStrings(spec, got.clone_url);
    try testing.expectEqualStrings("github.com", got.host);
    try testing.expectEqualStrings("acme", got.owner);
    try testing.expectEqualStrings("skills", got.repo);
}

test "parse keeps an SSH URL that has no .git suffix" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const spec = "git@github.com:acme/skills";
    const got = try remote.parse(allocator, spec, &fail);
    try testing.expectEqualStrings(spec, got.clone_url);
    try testing.expectEqualStrings("skills", got.repo);
}

test "parse rejects HTTPS" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, remote.parse(allocator, "https://github.com/acme/skills", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "HTTPS") != null);
}

test "parse rejects a github: scheme" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, remote.parse(allocator, "github:acme/skills", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "github:") != null);
}

test "parse rejects a filesystem path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const specs = [_][]const u8{ "/tmp/some-path", "./skills", "../skills", "file:///tmp/skills" };
    for (specs) |spec| {
        var fail = failure.Failure.init(allocator);
        try testing.expectError(error.Failed, remote.parse(allocator, spec, &fail));
        try testing.expect(std.mem.indexOf(u8, fail.text(), "filesystem") != null);
    }
}

test "parse rejects .. in owner, repo, and host" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const specs = [_][]const u8{
        "acme/..",
        "../skills",
        "git@github.com:../skills",
        "git@github.com:acme/..",
        "git@github..com:acme/skills.git",
    };
    for (specs) |spec| {
        var fail = failure.Failure.init(allocator);
        try testing.expectError(error.Failed, remote.parse(allocator, spec, &fail));
    }
}

test "parse rejects a colon in owner or repo" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var owner_fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, remote.parse(allocator, "acme:org/skills", &owner_fail));
    try testing.expect(std.mem.indexOf(u8, owner_fail.text(), "owner") != null);

    var repo_fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, remote.parse(allocator, "acme/ski:lls", &repo_fail));
    try testing.expect(std.mem.indexOf(u8, repo_fail.text(), "repo") != null);
}

test "parse rejects empty owner, repo, host, and spec" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const specs = [_][]const u8{ "", "acme/", "/skills", "git@github.com:/skills", "git@:acme/skills" };
    for (specs) |spec| {
        var fail = failure.Failure.init(allocator);
        try testing.expectError(error.Failed, remote.parse(allocator, spec, &fail));
    }
}

test "validateName rejects slash, colon, empty, dot, and Windows-illegal characters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bad = [_][]const u8{ "", ".", "..", "foo/bar", "foo\\bar", "foo:bar", "foo<bar", "foo>bar", "foo|bar", "foo\"bar", "foo?bar", "foo*bar" };
    for (bad) |name| {
        var fail = failure.Failure.init(allocator);
        try testing.expectError(error.Failed, remote.validateName(name, "namespace", &fail));
    }
}

test "validateName accepts a namespace that later steps will use under skills/" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var fail = failure.Failure.init(arena.allocator());

    try remote.validateName("demo", "namespace", &fail);
    try remote.validateName("cmd.v2", "namespace", &fail);
}

test "parse maps an enterprise SSH URL onto store/host/owner/repo" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const got = try remote.parse(allocator, "git@github.example.com:acme/skills.git", &fail);
    try testing.expectEqualStrings("git@github.example.com:acme/skills.git", got.clone_url);
    try testing.expectEqualStrings("github.example.com", got.host);
    try testing.expectEqualStrings("acme", got.owner);
    try testing.expectEqualStrings("skills", got.repo);

    const store_dir = try paths.storeDir(allocator, fake_home);
    const clone_path = try paths.clonePath(allocator, store_dir, got.host, got.owner, got.repo);
    const expected = try files.joinPath(allocator, &.{ store_dir, "github.example.com", "acme", "skills" });
    try testing.expectEqualStrings(expected, clone_path);
}
