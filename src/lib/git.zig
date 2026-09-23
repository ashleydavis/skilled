//
// Git on PATH, spawned by argv array, for clone, show, fetch, checkout, and HEAD in the store.
//
// Never a shell: every invocation is `std.process.run` with an argv array and an explicit
// environment map. Tests inject a GitRunner so clone and fetch never touch the network.
//

const std = @import("std");

//
// How a refused git operation is described to the caller.
//
const failure = @import("failure.zig");

//
// Parent-directory creation before clone, and the byte ceiling on captured stdout.
//
const files = @import("files.zig");

//
// Branch names for `--branch` clone/checkout, so a dash-prefixed name cannot become a git flag.
//
const remote = @import("remote.zig");

//
// Alias so signatures read as Failure rather than failure.Failure.
//
const Failure = failure.Failure;

//
// What a runner returns after one git argv, including a non-zero exit.
//
// Spawn failure (missing binary) is a Zig error, not this struct, so FileNotFound can be mapped
// once for every operation.
//
pub const Result = struct {
    //
    // Captured stdout. `showFile` and `headSha` return a slice of this.
    //
    stdout: []const u8,

    //
    // Captured stderr, included in the Failure when the exit code is non-zero.
    //
    stderr: []const u8,

    //
    // The process exit code. 0 is success; anything else is mapped by the caller.
    //
    exit_code: u8,
};

//
// Errors a GitRunner.runFn may return besides a Result.
//
// FileNotFound is "git is not on PATH". Failed already has a message in the Failure.
//
pub const RunError = error{FileNotFound} || failure.Error;

//
// One git spawn: argv plus optional cwd, returning stdout/stderr/exit.
//
// The process runner ignores ctx. Tests pass their fake as ctx so they can record argv.
//
pub const RunFn = *const fn (
    ctx: *anyopaque,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    cwd: ?[]const u8,
    fail: *Failure,
) RunError!Result;

//
// How git is started. The CLI uses `.process`; tests use `.custom` so nothing hits the network.
//
pub const GitRunner = union(enum) {
    //
    // Spawns the real `git` binary via std.process.run.
    //
    process,

    //
    // A callback that records argv and returns scripted output.
    //
    custom: Custom,
};

//
// The fake half of GitRunner: an opaque pointer and the function that uses it.
//
pub const Custom = struct {
    //
    // The fake's state, typically the scripted runner in git.test.zig.
    //
    ctx: *anyopaque,

    //
    // One git invocation. Returning FileNotFound is how tests cover a missing binary.
    //
    runFn: RunFn,
};

//
// The runner that spawns `git`. The CLI holds this; unit tests never use it.
//
pub fn processRunner() GitRunner {
    return .process;
}

//
// A test runner that records argv and returns scripted results.
//
pub fn customRunner(ctx: *anyopaque, runFn: RunFn) GitRunner {
    return .{ .custom = .{ .ctx = ctx, .runFn = runFn } };
}

//
// `git clone [--branch <branch>] -- <url> <dest>`, creating dest's parent directories first.
//
// `--` keeps a URL that starts with a dash from being parsed as a flag. Dest is the store path
// the caller already joined (`store/host/owner/repo`); this does not parse remotes. `branch` is
// the named remote branch, or null for the remote's default.
//
pub fn clone(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: GitRunner,
    url: []const u8,
    dest: []const u8,
    branch: ?[]const u8,
    fail: *Failure,
) failure.Error!void {
    files.makeParentDir(io, dest) catch |err| {
        return fail.set("Cannot create {s}: {s}.", .{ dest, files.describeError(err) });
    };
    if (branch) |name| {
        try remote.validateBranch(name, fail);
        const argv = [_][]const u8{ "git", "clone", "--branch", name, "--", url, dest };
        const result = try invoke(runner, io, allocator, environ, &argv, null, fail);
        try expectSuccess(result, "git clone", fail);
        return;
    }
    const argv = [_][]const u8{ "git", "clone", "--", url, dest };
    const result = try invoke(runner, io, allocator, environ, &argv, null, fail);
    try expectSuccess(result, "git clone", fail);
}

//
// `git show <ref>:<path>` in repo, returning stdout.
//
// Used by `init --from` and `add --from` to read a file at a ref. A missing ref or path is a
// non-zero exit from git, mapped to a Failure. The file bytes are not trimmed: trailing newlines
// belong to the file. There is no `--` before the spec: git would then treat `ref:path` as a
// pathspec instead of a revision, and the blob would never be read. Ref and path are already
// validated so they cannot start with a dash.
//
pub fn showFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: GitRunner,
    repo: []const u8,
    ref: []const u8,
    path: []const u8,
    fail: *Failure,
) failure.Error![]const u8 {
    const spec = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, path });
    const argv = [_][]const u8{ "git", "show", spec };
    const result = try invoke(runner, io, allocator, environ, &argv, repo, fail);
    try expectSuccess(result, "git show", fail);
    return result.stdout;
}

//
// Fast-forward the clone at dest to its upstream, or explain why that is refused.
//
// Order is the one that does not destroy work: refuse detached or dirty or missing upstream
// before fetch, then `git merge --ff-only @{upstream}` so a diverged branch is an error rather
// than a reset.
//
pub fn fetchUpdate(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: GitRunner,
    dest: []const u8,
    fail: *Failure,
) failure.Error!void {
    try refuseDetachedOrDirty(io, allocator, environ, runner, dest, fail);

    const upstream_argv = [_][]const u8{ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" };
    const upstream = try invoke(runner, io, allocator, environ, &upstream_argv, dest, fail);
    if (upstream.exit_code != 0) {
        return fail.set("No upstream branch; cannot update.", .{});
    }

    const fetch_argv = [_][]const u8{ "git", "fetch" };
    const fetched = try invoke(runner, io, allocator, environ, &fetch_argv, dest, fail);
    try expectSuccess(fetched, "git fetch", fail);

    const merge_argv = [_][]const u8{ "git", "merge", "--ff-only", "@{upstream}" };
    const merged = try invoke(runner, io, allocator, environ, &merge_argv, dest, fail);
    if (merged.exit_code != 0) {
        const stderr = trim(merged.stderr);
        if (stderr.len == 0) {
            return fail.set("Cannot fast-forward: diverged from upstream.", .{});
        }
        return fail.set("Cannot fast-forward: diverged from upstream: {s}", .{stderr});
    }
}

//
// Fetch, then check dest out onto `origin/<branch>` with tracking, so later fetchUpdate has upstream.
//
// Detached or dirty trees are refused with the same wording as fetchUpdate. A missing remote
// branch is git's non-zero exit, mapped to a Failure.
//
pub fn checkoutBranch(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: GitRunner,
    dest: []const u8,
    branch: []const u8,
    fail: *Failure,
) failure.Error!void {
    try remote.validateBranch(branch, fail);
    try refuseDetachedOrDirty(io, allocator, environ, runner, dest, fail);

    const fetch_argv = [_][]const u8{ "git", "fetch" };
    const fetched = try invoke(runner, io, allocator, environ, &fetch_argv, dest, fail);
    try expectSuccess(fetched, "git fetch", fail);

    const start_point = try std.fmt.allocPrint(allocator, "origin/{s}", .{branch});
    const checkout_argv = [_][]const u8{ "git", "checkout", "--track", "-B", branch, start_point };
    const checked = try invoke(runner, io, allocator, environ, &checkout_argv, dest, fail);
    try expectSuccess(checked, "git checkout", fail);
}

//
// Detached HEAD or a dirty working tree, worded the way fetchUpdate already used so callers share one phrase.
//
fn refuseDetachedOrDirty(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: GitRunner,
    dest: []const u8,
    fail: *Failure,
) failure.Error!void {
    const head_argv = [_][]const u8{ "git", "rev-parse", "--abbrev-ref", "HEAD" };
    const head = try invoke(runner, io, allocator, environ, &head_argv, dest, fail);
    try expectSuccess(head, "git rev-parse --abbrev-ref HEAD", fail);
    if (std.mem.eql(u8, trim(head.stdout), "HEAD")) {
        return fail.set("Repository has a detached HEAD; cannot update.", .{});
    }

    const status_argv = [_][]const u8{ "git", "status", "--porcelain" };
    const status = try invoke(runner, io, allocator, environ, &status_argv, dest, fail);
    try expectSuccess(status, "git status --porcelain", fail);
    if (trim(status.stdout).len != 0) {
        return fail.set("Working tree is dirty; cannot update.", .{});
    }
}

//
// `git rev-parse HEAD` in dest, with the trailing newline git prints stripped.
//
pub fn headSha(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: GitRunner,
    dest: []const u8,
    fail: *Failure,
) failure.Error![]const u8 {
    const argv = [_][]const u8{ "git", "rev-parse", "HEAD" };
    const result = try invoke(runner, io, allocator, environ, &argv, dest, fail);
    try expectSuccess(result, "git rev-parse HEAD", fail);
    return try allocator.dupe(u8, trim(result.stdout));
}

//
// Dispatches to the process runner or the test callback, mapping FileNotFound to a PATH error.
//
// The child sees a copy of environ with GIT_DIR and GIT_WORK_TREE removed so dest/cwd is the
// repo git uses. The caller's map is left alone.
//
fn invoke(
    runner: GitRunner,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    cwd: ?[]const u8,
    fail: *Failure,
) failure.Error!Result {
    var child_env = try childEnviron(allocator, environ);
    defer child_env.deinit();
    const result = switch (runner) {
        .process => runProcess(io, allocator, &child_env, argv, cwd, fail),
        .custom => |custom| custom.runFn(custom.ctx, io, allocator, &child_env, argv, cwd, fail),
    };
    return result catch |err| switch (err) {
        error.FileNotFound => return fail.set("Git is not on PATH; install git to clone and update packages.", .{}),
        error.Failed => return error.Failed,
        error.OutOfMemory => return error.OutOfMemory,
    };
}

//
// A copy of environ without GIT_DIR or GIT_WORK_TREE.
//
// Those two make git ignore dest/cwd and operate on whatever they name — including a GitHub
// Actions checkout. Everything else is kept: SSH_AUTH_SOCK, GIT_SSH, and GIT_CONFIG_* that
// checkout injects via GIT_CONFIG_COUNT / GIT_CONFIG_KEY_* / GIT_CONFIG_VALUE_*.
//
fn childEnviron(allocator: std.mem.Allocator, environ: *const std.process.Environ.Map) std.mem.Allocator.Error!std.process.Environ.Map {
    var child = try environ.clone(allocator);
    _ = child.swapRemove("GIT_DIR");
    _ = child.swapRemove("GIT_WORK_TREE");
    return child;
}

//
// Spawns argv with std.process.run. FileNotFound is left for invoke to word as a PATH error.
//
fn runProcess(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    cwd: ?[]const u8,
    fail: *Failure,
) RunError!Result {
    const spawned = std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = if (cwd) |path| .{ .path = path } else .inherit,
        .environ_map = environ,
        .stdout_limit = .limited(files.MAX_FILE_BYTES),
        .stderr_limit = .limited(files.MAX_FILE_BYTES),
    }) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.OutOfMemory => return error.OutOfMemory,
        else => return fail.set("Git failed to start: {s}.", .{@errorName(err)}),
    };

    switch (spawned.term) {
        .exited => |code| return .{
            .stdout = spawned.stdout,
            .stderr = spawned.stderr,
            .exit_code = code,
        },
        else => {
            allocator.free(spawned.stdout);
            allocator.free(spawned.stderr);
            return fail.set("Git was killed before it finished.", .{});
        },
    }
}

//
// Turns a non-zero exit into a Failure that includes git's stderr when it said anything.
//
fn expectSuccess(result: Result, what: []const u8, fail: *Failure) failure.Error!void {
    if (result.exit_code == 0) {
        return;
    }
    const stderr = trim(result.stderr);
    if (stderr.len == 0) {
        return fail.set("Command {s} failed with exit code {d}.", .{ what, result.exit_code });
    }
    return fail.set("Command {s} failed with exit code {d}: {s}", .{ what, result.exit_code, stderr });
}

//
// Strips the whitespace git leaves on stdout and stderr so "HEAD\n" matches "HEAD".
//
fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("git.test.zig");
}
