//
// Tests for git.zig.
//

const std = @import("std");
const failure = @import("failure.zig");
const files = @import("files.zig");
const git = @import("git.zig");
const testing = std.testing;

//
// One scripted reply the fake runner returns, in enqueue order.
//
const Reply = struct {
    //
    // Bytes treated as git stdout for that invocation.
    //
    stdout: []const u8 = "",

    //
    // Bytes treated as git stderr, used when the exit code is non-zero.
    //
    stderr: []const u8 = "",

    //
    // Process exit code. 0 is success.
    //
    exit_code: u8 = 0,
};

//
// One recorded git argv, so tests can assert `--` and dest without spawning.
//
const Call = struct {
    //
    // Copied argv, owned by the test arena.
    //
    argv: []const []const u8,

    //
    // Copied cwd, or null when the spawn inherited the process directory (clone).
    //
    cwd: ?[]const u8,

    //
    // GIT_DIR as the child saw it. Must stay null: that variable retargets the repo.
    //
    git_dir: ?[]const u8,

    //
    // GIT_WORK_TREE as the child saw it. Must stay null for the same reason as GIT_DIR.
    //
    git_work_tree: ?[]const u8,

    //
    // SSH_AUTH_SOCK as the child saw it. Kept so an agent in CI still reaches git.
    //
    ssh_auth_sock: ?[]const u8,

    //
    // GIT_CONFIG_COUNT as the child saw it. Kept so Actions checkout config still applies.
    //
    git_config_count: ?[]const u8,
};

//
// A GitRunner that records argv and returns enqueued replies. Never starts git.
//
const Scripted = struct {
    //
    // Where captured argv and reply copies are allocated. The test's arena.
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
    // When true, the next invoke returns FileNotFound, which git.zig maps to a PATH error.
    //
    missing: bool = false,

    //
    // Queues a reply for the next git invocation.
    //
    fn enqueue(self: *Scripted, reply: Reply) !void {
        try self.replies.append(self.allocator, reply);
    }

    //
    // The GitRunner clone, showFile, fetchUpdate, and headSha take.
    //
    fn runner(self: *Scripted) git.GitRunner {
        return git.customRunner(@ptrCast(self), run);
    }
};

//
// Records argv, then returns FileNotFound or the next reply.
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
    const self: *Scripted = @ptrCast(@alignCast(ctx));
    try self.calls.append(self.allocator, .{
        .argv = try copyArgv(self.allocator, argv),
        .cwd = if (cwd) |path| try self.allocator.dupe(u8, path) else null,
        .git_dir = try copyOpt(self.allocator, environ.get("GIT_DIR")),
        .git_work_tree = try copyOpt(self.allocator, environ.get("GIT_WORK_TREE")),
        .ssh_auth_sock = try copyOpt(self.allocator, environ.get("SSH_AUTH_SOCK")),
        .git_config_count = try copyOpt(self.allocator, environ.get("GIT_CONFIG_COUNT")),
    });
    if (self.missing) {
        return error.FileNotFound;
    }
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
// Duplicates an optional env value so it still exists after the child map is freed.
//
fn copyOpt(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    const slice = value orelse return null;
    return try allocator.dupe(u8, slice);
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
// An empty environment map for tests that do not care which variables git sees.
//
fn emptyEnviron(allocator: std.mem.Allocator) std.process.Environ.Map {
    return std.process.Environ.Map.init(allocator);
}

test "clone argv uses -- and the store host/owner/repo dest" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{});

    const dest = try files.joinPath(allocator, &.{ temporary.path, "store", "github.com", "acme", "skills" });
    var fail = failure.Failure.init(allocator);
    try git.clone(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "git@github.com:acme/skills.git",
        dest,
        null,
        &fail,
    );

    try testing.expectEqual(@as(usize, 1), scripted.calls.items.len);
    try expectArgv(scripted.calls.items[0], &.{
        "git",
        "clone",
        "--",
        "git@github.com:acme/skills.git",
        dest,
    });
    try testing.expect(scripted.calls.items[0].cwd == null);
    //
    // Windows CI failed asserting dest ends with `store/github.com/acme/skills`: joinPath uses `\`.
    //
    try testing.expect(std.mem.endsWith(u8, dest, try files.joinPath(allocator, &.{ "store", "github.com", "acme", "skills" })));
}

test "clone argv includes --branch when a branch is given" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{});

    const dest = try files.joinPath(allocator, &.{ temporary.path, "store", "github.com", "acme", "skills" });
    var fail = failure.Failure.init(allocator);
    try git.clone(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "git@github.com:acme/skills.git",
        dest,
        "feature",
        &fail,
    );

    try testing.expectEqual(@as(usize, 1), scripted.calls.items.len);
    try expectArgv(scripted.calls.items[0], &.{
        "git",
        "clone",
        "--branch",
        "feature",
        "--",
        "git@github.com:acme/skills.git",
        dest,
    });
}

test "showFile argv is git show ref:path" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "packages: []\n" });

    var fail = failure.Failure.init(allocator);
    const text = try git.showFile(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/acme/skl-config",
        "main",
        "teams/platform.yaml",
        &fail,
    );

    try testing.expectEqualStrings("packages: []\n", text);
    try testing.expectEqual(@as(usize, 1), scripted.calls.items.len);
    try expectArgv(scripted.calls.items[0], &.{ "git", "show", "main:teams/platform.yaml" });
    try testing.expectEqualStrings("/tmp/acme/skl-config", scripted.calls.items[0].cwd.?);
}

test "fetchUpdate refuses a detached HEAD" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "HEAD\n" });

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, git.fetchUpdate(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/store/github.com/acme/skills",
        &fail,
    ));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "detached") != null);
    try testing.expectEqual(@as(usize, 1), scripted.calls.items.len);
}

test "fetchUpdate refuses a dirty working tree" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "main\n" });
    try scripted.enqueue(.{ .stdout = " M README.md\n" });

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, git.fetchUpdate(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/store/github.com/acme/skills",
        &fail,
    ));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "dirty") != null);
    try testing.expectEqual(@as(usize, 2), scripted.calls.items.len);
}

test "fetchUpdate refuses a missing upstream" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "main\n" });
    try scripted.enqueue(.{});
    try scripted.enqueue(.{ .exit_code = 128, .stderr = "no upstream\n" });

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, git.fetchUpdate(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/store/github.com/acme/skills",
        &fail,
    ));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "upstream") != null);
    try testing.expectEqual(@as(usize, 3), scripted.calls.items.len);
}

test "fetchUpdate runs git fetch then merge --ff-only @{upstream}" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "main\n" });
    try scripted.enqueue(.{});
    try scripted.enqueue(.{ .stdout = "origin/main\n" });
    try scripted.enqueue(.{});
    try scripted.enqueue(.{});

    const dest = "/tmp/store/github.com/acme/skills";
    var fail = failure.Failure.init(allocator);
    try git.fetchUpdate(io, allocator, &environ, scripted.runner(), dest, &fail);

    try testing.expectEqual(@as(usize, 5), scripted.calls.items.len);
    try expectArgv(scripted.calls.items[0], &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" });
    try expectArgv(scripted.calls.items[1], &.{ "git", "status", "--porcelain" });
    try expectArgv(scripted.calls.items[2], &.{ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" });
    try expectArgv(scripted.calls.items[3], &.{ "git", "fetch" });
    try expectArgv(scripted.calls.items[4], &.{ "git", "merge", "--ff-only", "@{upstream}" });
    for (scripted.calls.items) |call| {
        try testing.expectEqualStrings(dest, call.cwd.?);
    }
}

test "checkoutBranch argv is fetch then checkout --track -B origin/branch" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "main\n" });
    try scripted.enqueue(.{});
    try scripted.enqueue(.{});
    try scripted.enqueue(.{});

    const dest = "/tmp/store/github.com/acme/skills";
    var fail = failure.Failure.init(allocator);
    try git.checkoutBranch(io, allocator, &environ, scripted.runner(), dest, "feature", &fail);

    try testing.expectEqual(@as(usize, 4), scripted.calls.items.len);
    try expectArgv(scripted.calls.items[0], &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" });
    try expectArgv(scripted.calls.items[1], &.{ "git", "status", "--porcelain" });
    try expectArgv(scripted.calls.items[2], &.{ "git", "fetch" });
    try expectArgv(scripted.calls.items[3], &.{ "git", "checkout", "--track", "-B", "feature", "origin/feature" });
    for (scripted.calls.items) |call| {
        try testing.expectEqualStrings(dest, call.cwd.?);
    }
}

test "checkoutBranch refuses a detached HEAD" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "HEAD\n" });

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, git.checkoutBranch(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/store/github.com/acme/skills",
        "feature",
        &fail,
    ));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "detached") != null);
}

test "checkoutBranch refuses a dirty working tree" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "main\n" });
    try scripted.enqueue(.{ .stdout = " M README.md\n" });

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, git.checkoutBranch(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/store/github.com/acme/skills",
        "feature",
        &fail,
    ));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "dirty") != null);
}

test "headSha argv is git rev-parse HEAD" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "abc123def\n" });

    var fail = failure.Failure.init(allocator);
    const sha = try git.headSha(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/store/github.com/acme/skills",
        &fail,
    );

    try testing.expectEqualStrings("abc123def", sha);
    try testing.expectEqual(@as(usize, 1), scripted.calls.items.len);
    try expectArgv(scripted.calls.items[0], &.{ "git", "rev-parse", "HEAD" });
}

test "git not on PATH maps to a readable error" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    var scripted = Scripted{ .allocator = allocator, .missing = true };

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, git.headSha(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/store/github.com/acme/skills",
        &fail,
    ));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "PATH") != null);
}

test "spawn drops GIT_DIR and GIT_WORK_TREE and keeps SSH and GIT_CONFIG" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var environ = emptyEnviron(allocator);
    try environ.put("GIT_DIR", "/wrong/repo/.git");
    try environ.put("GIT_WORK_TREE", "/wrong/repo");
    try environ.put("SSH_AUTH_SOCK", "/tmp/ssh-agent.sock");
    try environ.put("GIT_CONFIG_COUNT", "1");

    var scripted = Scripted{ .allocator = allocator };
    try scripted.enqueue(.{ .stdout = "abc123\n" });

    var fail = failure.Failure.init(allocator);
    _ = try git.headSha(
        io,
        allocator,
        &environ,
        scripted.runner(),
        "/tmp/store/github.com/acme/skills",
        &fail,
    );

    try testing.expectEqual(@as(usize, 1), scripted.calls.items.len);
    try testing.expect(scripted.calls.items[0].git_dir == null);
    try testing.expect(scripted.calls.items[0].git_work_tree == null);
    try testing.expectEqualStrings("/tmp/ssh-agent.sock", scripted.calls.items[0].ssh_auth_sock.?);
    try testing.expectEqualStrings("1", scripted.calls.items[0].git_config_count.?);
    try testing.expectEqualStrings("/wrong/repo/.git", environ.get("GIT_DIR").?);
    try testing.expectEqualStrings("/wrong/repo", environ.get("GIT_WORK_TREE").?);
}
