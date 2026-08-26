//
// Tests for from.zig.
//

const std = @import("std");
const config = @import("config.zig");
const failure = @import("failure.zig");
const files = @import("files.zig");
const from = @import("from.zig");
const git = @import("git.zig");
const testing = std.testing;

//
// YAML the fake `git show` returns unless a test overrides it.
//
const platform_yaml =
    \\packages:
    \\  - repo: acme/skills
    \\    namespace: demo
    \\  - repo: acme/cmds
    \\    namespace: cmd
    \\
;

//
// One recorded git argv, so fetch tests can assert clone dest and `git show`.
//
const Call = struct {
    //
    // Copied argv, owned by the test arena.
    //
    argv: []const []const u8,

    //
    // Copied cwd, or null when clone inherits the process directory.
    //
    cwd: ?[]const u8,
};

//
// One scripted reply, consumed in invoke order.
//
const Reply = struct {
    //
    // Bytes treated as git stdout.
    //
    stdout: []const u8 = "",

    //
    // Bytes treated as git stderr when the exit code is non-zero.
    //
    stderr: []const u8 = "",

    //
    // Process exit code. 0 is success.
    //
    exit_code: u8 = 0,
};

//
// A GitRunner that records argv and returns enqueued replies. Never starts git.
//
const Scripted = struct {
    //
    // Where captured argv is allocated.
    //
    allocator: std.mem.Allocator,

    //
    // Replies consumed in order, one per invoke.
    //
    replies: std.ArrayList(Reply) = .empty,

    //
    // Every argv the code under test built.
    //
    calls: std.ArrayList(Call) = .empty,

    //
    // Queues a reply for the next git invocation.
    //
    fn enqueue(self: *Scripted, reply: Reply) !void {
        try self.replies.append(self.allocator, reply);
    }

    //
    // The GitRunner fetchConfig takes.
    //
    fn runner(self: *Scripted) git.GitRunner {
        return git.customRunner(@ptrCast(self), run);
    }
};

test "parse shorthand owner/repo:path defaults ref to HEAD" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const got = try from.parse(allocator, "acme/skl-config:teams/platform.yaml", &fail);
    try testing.expectEqualStrings("git@github.com:acme/skl-config.git", got.remote.clone_url);
    try testing.expectEqualStrings("github.com", got.remote.host);
    try testing.expectEqualStrings("acme", got.remote.owner);
    try testing.expectEqualStrings("skl-config", got.remote.repo);
    try testing.expectEqualStrings("HEAD", got.ref);
    try testing.expectEqualStrings("teams/platform.yaml", got.path);
}

test "parse SSH with two colons keeps the SSH clone URL and strips .git from the repo name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const got = try from.parse(
        allocator,
        "git@github.com:acme/skl-config.git:teams/platform.yaml",
        &fail,
    );
    try testing.expectEqualStrings("git@github.com:acme/skl-config.git", got.remote.clone_url);
    try testing.expectEqualStrings("github.com", got.remote.host);
    try testing.expectEqualStrings("skl-config", got.remote.repo);
    try testing.expectEqualStrings("HEAD", got.ref);
    try testing.expectEqualStrings("teams/platform.yaml", got.path);
}

test "parse blob URL with ref still clones over SSH" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const got = try from.parse(
        allocator,
        "https://github.com/acme/skl-config/blob/main/teams/platform.yaml",
        &fail,
    );
    try testing.expectEqualStrings("git@github.com:acme/skl-config.git", got.remote.clone_url);
    try testing.expectEqualStrings("github.com", got.remote.host);
    try testing.expectEqualStrings("acme", got.remote.owner);
    try testing.expectEqualStrings("skl-config", got.remote.repo);
    try testing.expectEqualStrings("main", got.ref);
    try testing.expectEqualStrings("teams/platform.yaml", got.path);
}

test "parse HTTPS without blob defaults ref to HEAD" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const got = try from.parse(
        allocator,
        "https://github.com/acme/skl-config/teams/platform.yaml",
        &fail,
    );
    try testing.expectEqualStrings("HEAD", got.ref);
    try testing.expectEqualStrings("teams/platform.yaml", got.path);
    try testing.expectEqualStrings("git@github.com:acme/skl-config.git", got.remote.clone_url);
}

test "parse rejects a spec with no colon" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, from.parse(allocator, "acme/skl-config", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "owner/repo:path") != null);
}

test "parse rejects SSH with no file path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, from.parse(allocator, "git@github.com:acme/skl-config.git", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "path") != null);
}

test "parse rejects a non-github.com HTTPS host" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(
        error.Failed,
        from.parse(allocator, "https://github.example.com/acme/skl-config/blob/main/teams/platform.yaml", &fail),
    );
    try testing.expect(std.mem.indexOf(u8, fail.text(), "github.com") != null);
}

test "parse rejects an empty spec" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, from.parse(allocator, "", &fail));
}

test "parse rejects .. in a path segment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, from.parse(allocator, "acme/skl-config:../skl.yaml", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "path") != null);
}

test "fetchConfig clones over SSH, shows ref:path, and deletes the temp clone" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();
    const tmp = try temporary.join(allocator, "tmp");
    try files.makeDirPath(io, tmp);

    var environ = std.process.Environ.Map.init(allocator);
    try environ.put("TMPDIR", tmp);

    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{});
    try scripted.enqueue(.{ .stdout = platform_yaml });

    var fail = failure.Failure.init(allocator);
    const file = try from.fetchConfig(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "https://github.com/acme/skl-config/blob/main/teams/platform.yaml",
        &fail,
    );

    try testing.expectEqual(@as(usize, 2), file.packages.len);
    try testing.expectEqualStrings("acme/skills", file.packages[0].repo);
    try testing.expectEqualStrings("demo", file.packages[0].namespace);

    try testing.expectEqual(@as(usize, 2), scripted.calls.items.len);
    try expectArgvPrefix(scripted.calls.items[0], &.{ "git", "clone", "--", "git@github.com:acme/skl-config.git" });
    try expectArgv(scripted.calls.items[1], &.{ "git", "show", "main:teams/platform.yaml" });

    const dest = scripted.calls.items[0].argv[scripted.calls.items[0].argv.len - 1];
    try testing.expect(std.mem.indexOf(u8, dest, ".skilled") == null);
    try testing.expect(std.mem.startsWith(u8, dest, tmp));
    try testing.expectEqualStrings(dest, scripted.calls.items[1].cwd.?);
    try testing.expect(!pathExists(io, dest));
    try testing.expect(!pathExists(io, files.dirName(dest)));
}

test "fetchConfig maps a missing file at ref:path to a failure and still deletes the temp clone" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();
    const tmp = try temporary.join(allocator, "tmp");
    try files.makeDirPath(io, tmp);

    var environ = std.process.Environ.Map.init(allocator);
    try environ.put("TMPDIR", tmp);

    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{});
    try scripted.enqueue(.{
        .exit_code = 128,
        .stderr = "fatal: path 'teams/missing.yaml' does not exist in 'HEAD'\n",
    });

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, from.fetchConfig(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "acme/skl-config:teams/missing.yaml",
        &fail,
    ));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "git show") != null);
    try testing.expectEqual(@as(usize, 2), scripted.calls.items.len);
    try expectArgv(scripted.calls.items[1], &.{ "git", "show", "HEAD:teams/missing.yaml" });
    const dest = scripted.calls.items[0].argv[scripted.calls.items[0].argv.len - 1];
    try testing.expect(!pathExists(io, dest));
    try testing.expect(!pathExists(io, files.dirName(dest)));
}

test "mergePackages keeps existing extras and appends new namespaces" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const existing = [_]config.Package{.{ .repo = "acme/both", .namespace = "keep" }};
    const incoming = [_]config.Package{
        .{ .repo = "acme/skills", .namespace = "demo" },
        .{ .repo = "acme/cmds", .namespace = "cmd" },
    };
    const merged = try from.mergePackages(allocator, &existing, &incoming, &fail);
    try testing.expectEqual(@as(usize, 3), merged.len);
    try testing.expectEqualStrings("keep", merged[0].namespace);
    try testing.expectEqualStrings("demo", merged[1].namespace);
    try testing.expectEqualStrings("cmd", merged[2].namespace);
}

test "mergePackages skips the same namespace and same package including SSH vs shorthand" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const existing = [_]config.Package{.{
        .repo = "git@github.com:acme/skills.git",
        .namespace = "demo",
    }};
    const incoming = [_]config.Package{.{ .repo = "acme/skills", .namespace = "demo" }};
    const merged = try from.mergePackages(allocator, &existing, &incoming, &fail);
    try testing.expectEqual(@as(usize, 1), merged.len);
    try testing.expectEqualStrings("git@github.com:acme/skills.git", merged[0].repo);
}

test "mergePackages errors when a namespace is taken by a different repo" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const existing = [_]config.Package{.{ .repo = "acme/skills", .namespace = "demo" }};
    const incoming = [_]config.Package{.{ .repo = "acme/both", .namespace = "demo" }};
    try testing.expectError(error.Failed, from.mergePackages(allocator, &existing, &incoming, &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "already used") != null);
}

//
// Records argv, then returns the next reply.
//
fn run(
    ctx: *anyopaque,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    cwd: ?[]const u8,
    fail: *failure.Failure,
) git.RunError!git.Result {
    _ = io;
    _ = environ;
    const self: *Scripted = @ptrCast(@alignCast(ctx));
    try self.calls.append(self.allocator, .{
        .argv = try copyArgv(self.allocator, argv),
        .cwd = if (cwd) |path| try self.allocator.dupe(u8, path) else null,
    });
    if (self.calls.items.len > self.replies.items.len) {
        return fail.set("scripted git has no reply left for {s}", .{argv[1]});
    }
    const reply = self.replies.items[self.calls.items.len - 1];
    return .{
        .stdout = try allocator.dupe(u8, reply.stdout),
        .stderr = try allocator.dupe(u8, reply.stderr),
        .exit_code = reply.exit_code,
    };
}

//
// Copies argv so later asserts still see it after the stack array in git.zig is gone.
//
fn copyArgv(allocator: std.mem.Allocator, argv: []const []const u8) ![]const []const u8 {
    const copy = try allocator.alloc([]const u8, argv.len);
    for (argv, 0..) |arg, i| {
        copy[i] = try allocator.dupe(u8, arg);
    }
    return copy;
}

//
// Asserts a recorded argv matches the expected strings in order.
//
fn expectArgv(call: Call, expected: []const []const u8) !void {
    try testing.expectEqual(expected.len, call.argv.len);
    for (expected, call.argv) |want, got| {
        try testing.expectEqualStrings(want, got);
    }
}

//
// Asserts the first expected.len argv entries match, leaving dest (the last clone arg) unchecked.
//
fn expectArgvPrefix(call: Call, expected: []const []const u8) !void {
    try testing.expect(call.argv.len >= expected.len);
    for (expected, call.argv[0..expected.len]) |want, got| {
        try testing.expectEqualStrings(want, got);
    }
}

//
// True when a path exists as any kind of inode.
//
fn pathExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}
