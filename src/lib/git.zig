//
// Git on PATH, spawned by argv array, for clone, show, fetch, and HEAD in the store.
//
// Never a shell: every invocation is `std.process.run` with an argv array and an explicit
// environment map.
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
// Branch names for `--branch` clone, so a dash-prefixed name cannot become a git flag.
//
const remote = @import("remote.zig");

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
    // Captured stderr, included in the failure's message when the exit code is non-zero.
    //
    stderr: []const u8,

    //
    // The process exit code. 0 is success; anything else is mapped by the caller.
    //
    exit_code: u8,
};

//
// Errors a GitRunner.runFn may return besides a Result or a failure.
//
// FileNotFound is "git is not on PATH", worded once by `invoke` for every operation.
//
pub const RunError = error{FileNotFound} || std.mem.Allocator.Error;

//
// One git spawn: argv plus optional cwd, returning stdout/stderr/exit.
//
// The process runner ignores ctx.
//
pub const RunFn = *const fn (
    ctx: *anyopaque,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    cwd: ?[]const u8,
) RunError!failure.Result(Result);

//
// How git is started. The CLI uses `.process`.
//
pub const GitRunner = union(enum) {
    //
    // Spawns the real `git` binary via std.process.run.
    //
    process,

    //
    // A callback that records argv and returns scripted output.
    //
    function: GitFunction,
};

//
// The function half of GitRunner: an opaque pointer and the function that uses it.
//
pub const GitFunction = struct {
    //
    // The state the function is handed on every call.
    //
    ctx: *anyopaque,

    //
    // One git invocation.
    //
    runFn: RunFn,
};

//
// The runner that spawns `git`. The CLI holds this.
//
pub fn processRunner() GitRunner {
    return .process;
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
) std.mem.Allocator.Error!failure.Result(void) {
    files.makeParentDir(io, dest) catch |err| {
        return .{
            .failed = failure.because("Cannot create {s}: {s}.", .{ dest, files.describeError(err) }),
        };
    };
    if (branch) |name| {
        switch (remote.validateBranch(name)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        const argv = [_][]const u8{ "git", "clone", "--branch", name, "--", url, dest };
        const result = switch (try invoke(runner, io, allocator, environ, &argv, null)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        switch (expectSuccess(result, "git clone")) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        return .ok;
    }
    const argv = [_][]const u8{ "git", "clone", "--", url, dest };
    const result = switch (try invoke(runner, io, allocator, environ, &argv, null)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (expectSuccess(result, "git clone")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .ok;
}

//
// `git show <ref>:<path>` in repo, returning stdout.
//
// Used by `init --from` and `add --from` to read a file at a ref. A missing ref or path is a
// non-zero exit from git, returned as a failure. The file bytes are not trimmed: trailing newlines
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
) std.mem.Allocator.Error!failure.Result([]const u8) {
    const spec = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, path });
    const argv = [_][]const u8{ "git", "show", spec };
    const result = switch (try invoke(runner, io, allocator, environ, &argv, repo)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (expectSuccess(result, "git show")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .{
        .ok = result.stdout,
    };
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
) std.mem.Allocator.Error!failure.Result(void) {
    switch (try refuseDetachedOrDirty(io, allocator, environ, runner, dest)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    const upstream_argv = [_][]const u8{ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" };
    const upstream = switch (try invoke(runner, io, allocator, environ, &upstream_argv, dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (upstream.exit_code != 0) {
        return .{
            .failed = failure.because("No upstream branch; cannot update.", .{}),
        };
    }

    const fetch_argv = [_][]const u8{ "git", "fetch" };
    const fetched = switch (try invoke(runner, io, allocator, environ, &fetch_argv, dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (expectSuccess(fetched, "git fetch")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    const merge_argv = [_][]const u8{ "git", "merge", "--ff-only", "@{upstream}" };
    const merged = switch (try invoke(runner, io, allocator, environ, &merge_argv, dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (merged.exit_code != 0) {
        const stderr = trim(merged.stderr);
        if (stderr.len == 0) {
            return .{
                .failed = failure.because("Cannot fast-forward: diverged from upstream.", .{}),
            };
        }
        return .{
            .failed = failure.because("Cannot fast-forward: diverged from upstream: {s}", .{stderr}),
        };
    }
    return .ok;
}

//
// Refuses a detached HEAD or a dirty working tree before fetchUpdate fetches.
//
fn refuseDetachedOrDirty(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: GitRunner,
    dest: []const u8,
) std.mem.Allocator.Error!failure.Result(void) {
    const head_argv = [_][]const u8{ "git", "rev-parse", "--abbrev-ref", "HEAD" };
    const head = switch (try invoke(runner, io, allocator, environ, &head_argv, dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (expectSuccess(head, "git rev-parse --abbrev-ref HEAD")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    if (std.mem.eql(u8, trim(head.stdout), "HEAD")) {
        return .{
            .failed = failure.because("Repository has a detached HEAD; cannot update.", .{}),
        };
    }

    const status_argv = [_][]const u8{ "git", "status", "--porcelain" };
    const status = switch (try invoke(runner, io, allocator, environ, &status_argv, dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (expectSuccess(status, "git status --porcelain")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    if (trim(status.stdout).len != 0) {
        return .{
            .failed = failure.because("Working tree is dirty; cannot update.", .{}),
        };
    }
    return .ok;
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
) std.mem.Allocator.Error!failure.Result([]const u8) {
    const argv = [_][]const u8{ "git", "rev-parse", "HEAD" };
    const result = switch (try invoke(runner, io, allocator, environ, &argv, dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (expectSuccess(result, "git rev-parse HEAD")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .{
        .ok = try allocator.dupe(u8, trim(result.stdout)),
    };
}

//
// Dispatches to the process runner or the test callback, mapping FileNotFound to a PATH error.
//
// An argv without a git command (fewer than two entries) is refused before any runner sees it.
//
// The child sees a copy of environ with GIT_DIR and GIT_WORK_TREE removed so dest/cwd is the
// repo git uses. The caller's map is left alone.
//
pub fn invoke(
    runner: GitRunner,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    cwd: ?[]const u8,
) std.mem.Allocator.Error!failure.Result(Result) {
    if (argv.len < 2) {
        return .{
            .failed = failure.because("No git command to run.", .{}),
        };
    }
    var child_env = try childEnviron(allocator, environ);
    defer child_env.deinit();
    const result = switch (runner) {
        .process => runProcess(io, allocator, &child_env, argv, cwd),
        .function => |function| function.runFn(function.ctx, io, allocator, &child_env, argv, cwd),
    };
    return result catch |err| switch (err) {
        error.FileNotFound => return .{
            .failed = failure.because("Git is not on PATH; install git to clone and update packages.", .{}),
        },
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
) RunError!failure.Result(Result) {
    const spawned = std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = if (cwd) |path| .{
            .path = path,
        } else .inherit,
        .environ_map = environ,
        .stdout_limit = .limited(files.MAX_FILE_BYTES),
        .stderr_limit = .limited(files.MAX_FILE_BYTES),
    }) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{
            .failed = failure.because("Git failed to start: {s}.", .{@errorName(err)}),
        },
    };

    switch (spawned.term) {
        .exited => |code| return .{
            .ok = .{
                .stdout = spawned.stdout,
                .stderr = spawned.stderr,
                .exit_code = code,
            },
        },
        else => {
            allocator.free(spawned.stdout);
            allocator.free(spawned.stderr);
            return .{
                .failed = failure.because("Git was killed before it finished.", .{}),
            };
        },
    }
}

//
// Turns a non-zero exit into a failure whose message includes git's stderr when it said anything.
//
fn expectSuccess(result: Result, what: []const u8) failure.Result(void) {
    if (result.exit_code == 0) {
        return .ok;
    }
    const stderr = trim(result.stderr);
    if (stderr.len == 0) {
        return .{
            .failed = failure.because("Command {s} failed with exit code {d}.", .{ what, result.exit_code }),
        };
    }
    return .{
        .failed = failure.because("Command {s} failed with exit code {d}: {s}", .{ what, result.exit_code, stderr }),
    };
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
