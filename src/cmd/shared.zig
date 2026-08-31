//
// Helpers several commands share: missing config, store paths, package matching, URLs, prompts.
//

const std = @import("std");
const builtin = @import("builtin");
const skilled = @import("skilled");

const context_mod = @import("context.zig");

//
// The run values commands already received from main or a test.
//
const Context = context_mod.Context;

//
// How a URL is opened; `openUrl` dispatches on this.
//
const BrowserRunner = context_mod.BrowserRunner;

//
// Config file shape, so matching and requireConfig can talk about packages without re-parsing.
//
const config = skilled.config;

//
// Bounded filesystem helpers, including path joins.
//
const files = skilled.files;

//
// Clone when the store dest is missing.
//
const git = skilled.git;

//
// Namespace symlinks into Cursor and Claude, used when `--from` finishes by installing.
//
const link = skilled.link;

//
// Layout check after clone, so an empty package fails this entry rather than linking nothing.
//
const package = skilled.package;

//
// Store and scope paths resolved from home/cwd.
//
const paths = skilled.paths;

//
// The stderr spinner drawn around clone and link.
//
const progress = skilled.progress;

//
// SSH clone specs turned into host/owner/repo.
//
const remote = skilled.remote;

//
// Color and icons for painted stdout.
//
const term = skilled.term;

//
// How a refused command is described.
//
const Failure = skilled.failure.Failure;

//
// The message used when the active scope has no skl.yaml. Exact so smoke tests can match it.
//
pub const missing_config_message = "no skl.yaml; run skl init";

//
// A package plus its index in the YAML list, so remove can drop that one entry.
//
pub const Match = struct {
    //
    // Position in `packages`, used to splice the entry out on remove.
    //
    index: usize,

    //
    // The matching YAML row.
    //
    pkg: config.Package,
};

//
// Parsed remote plus the store directory it clones into.
//
pub const Resolved = struct {
    //
    // Host, owner, repo, and clone URL after step-6 validation.
    //
    parsed: remote.Remote,

    //
    // `<store>/<host>/<owner>/<repo>`.
    //
    dest: []const u8,
};

//
// Config path and agent roots for `-g` or the project, using this run's home and cwd.
//
pub fn scopeOf(ctx: *const Context, global: bool) std.mem.Allocator.Error!paths.Scope {
    return paths.scopeFromFlag(ctx.allocator, global, ctx.home, ctx.cwd, paths.xdgConfigHome(ctx.environ));
}

//
// The store root for this run, always under home, never XDG_DATA_HOME.
//
pub fn storeDir(ctx: *const Context) std.mem.Allocator.Error![]const u8 {
    return paths.storeDir(ctx.allocator, ctx.home);
}

//
// True when path is a directory, following a symlink to one.
//
pub fn dirExists(io: std.Io, path: []const u8) bool {
    const st = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = true }) catch return false;
    return st.kind == .directory;
}

//
// Reads skl.yaml, or the missing-config error if the file is not there.
//
pub fn requireConfig(ctx: *const Context, config_path: []const u8) skilled.failure.Error!config.File {
    if (!files.fileExists(ctx.io, config_path)) {
        return ctx.fail.set("{s}", .{missing_config_message});
    }
    return config.readFile(ctx.io, ctx.allocator, config_path, ctx.fail);
}

//
// Parses a YAML repo spec and joins it onto the store root.
//
pub fn resolveStore(ctx: *const Context, spec: []const u8) skilled.failure.Error!Resolved {
    const parsed = try remote.parse(ctx.allocator, spec, ctx.fail);
    const dest = try paths.clonePath(ctx.allocator, try storeDir(ctx), parsed.host, parsed.owner, parsed.repo);
    return .{ .parsed = parsed, .dest = dest };
}

//
// Clones into the store when dest is missing. An existing dest is reused (global and project share
// the store). When `branch` is set and dest already exists, the clone is checked out onto that
// branch. Progress is drawn only for an actual clone.
//
pub fn ensureCloned(ctx: *const Context, spec: []const u8, branch: ?[]const u8, spinner: *progress.Progress) skilled.failure.Error!Resolved {
    const resolved = try resolveStore(ctx, spec);
    if (dirExists(ctx.io, resolved.dest)) {
        if (branch) |name| {
            try git.checkoutBranch(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest, name, ctx.fail);
        }
        return resolved;
    }
    spinner.cloning(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ resolved.parsed.owner, resolved.parsed.repo }));
    git.clone(
        ctx.io,
        ctx.allocator,
        ctx.environ,
        ctx.git,
        resolved.parsed.clone_url,
        resolved.dest,
        branch,
        ctx.fail,
    ) catch |err| {
        spinner.finish();
        return err;
    };
    spinner.finish();
    return resolved;
}

//
// Directory whose skills/ and commands/ trees are linked: a `local:` path, else the store clone.
//
pub fn contentDir(ctx: *const Context, pkg: config.Package) skilled.failure.Error![]const u8 {
    if (pkg.local) |local| {
        return files.absolutePath(ctx.allocator, ctx.cwd, local);
    }
    const resolved = try resolveStore(ctx, pkg.repo);
    return resolved.dest;
}

//
// Absolute path of a local working tree that is a git repo and a valid package.
//
// Empty is refused. Relative paths are resolved against ctx.cwd. `.git` may be a directory or a
// gitfile (a regular file); a missing `.git` is not a repo.
//
pub fn resolveLocal(ctx: *const Context, path: []const u8) skilled.failure.Error![]const u8 {
    if (path.len == 0) {
        return ctx.fail.set("--local path is empty", .{});
    }
    const abs = try files.absolutePath(ctx.allocator, ctx.cwd, path);
    if (!dirExists(ctx.io, abs)) {
        return ctx.fail.set("local path {s} is not a directory", .{abs});
    }
    const git_dir = try files.joinPath(ctx.allocator, &.{ abs, ".git" });
    const git_st = std.Io.Dir.cwd().statFile(ctx.io, git_dir, .{ .follow_symlinks = true }) catch {
        return ctx.fail.set("local path {s} is not a git repository", .{abs});
    };
    if (git_st.kind != .directory and git_st.kind != .file) {
        return ctx.fail.set("local path {s} is not a git repository", .{abs});
    }
    _ = try package.scan(ctx.io, ctx.allocator, abs, ctx.fail);
    return abs;
}

//
// Clones missing packages and links each namespace in `file`.
//
// Same work as `skl install`. `init --from` calls this so the developer does not run a second
// command after the YAML is written. On package *k* of *N* failing, packages 1..k-1 stay cloned
// and linked; there is no rollback.
//
pub fn installAll(ctx: *const Context, scope: paths.Scope, file: config.File) skilled.failure.Error!u8 {
    var spinner = newSpinner(ctx);
    defer spinner.finish();

    for (file.packages) |pkg| {
        var one_fail = Failure.init(ctx.allocator);
        var one_ctx = ctx.*;
        one_ctx.fail = &one_fail;
        installOne(&one_ctx, scope, pkg, &spinner) catch {
            return ctx.fail.set("install failed on {s}: {s}", .{ pkg.repo, one_fail.text() });
        };
    }
    return 0;
}

//
// Clone if missing, scan, then link. A Failure from a helper is left as-is; installAll wraps it.
//
fn installOne(
    ctx: *const Context,
    scope: paths.Scope,
    pkg: config.Package,
    spinner: *progress.Progress,
) skilled.failure.Error!void {
    if (pkg.local) |local_path| {
        const dest = try resolveLocal(ctx, local_path);
        spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ pkg.namespace, pkg.repo }));
        try link.linkPackage(ctx.io, ctx.allocator, dest, pkg.namespace, scope, ctx.fail);
        spinner.finish();
        try line(ctx, "{s} {s}", .{ ctx.style.check(), pkg.repo });
        return;
    }
    const resolved = try ensureCloned(ctx, pkg.repo, pkg.branch, spinner);
    _ = try package.scan(ctx.io, ctx.allocator, resolved.dest, ctx.fail);
    spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ pkg.namespace, resolved.parsed.repo }));
    try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, pkg.namespace, scope, ctx.fail);
    spinner.finish();
    try line(ctx, "{s} {s}", .{ ctx.style.check(), pkg.repo });
}

//
// A progress line that is a no-op in tests unless they opt into a TTY-looking stderr.
//
pub fn newSpinner(ctx: *const Context) progress.Progress {
    return progress.Progress.init(ctx.stderr, ctx.style, ctx.non_interactive, ctx.stderr_is_tty);
}

//
// Writes one line to stdout, or records that output could not be written.
//
pub fn line(ctx: *const Context, comptime fmt: []const u8, args: anytype) skilled.failure.Error!void {
    ctx.stdout.print(fmt ++ "\n", args) catch return ctx.fail.set("cannot write output", .{});
}

//
// Writes one line to stderr (prompts). Failures here are ignored: a broken stderr must not hang a prompt.
//
pub fn promptWrite(ctx: *const Context, comptime fmt: []const u8, args: anytype) void {
    ctx.stderr.print(fmt, args) catch {};
    ctx.stderr.flush() catch {};
}

//
// Reads one line from stdin, trimming a trailing `\r` from a Windows CRLF.
//
pub fn promptLine(ctx: *const Context) skilled.failure.Error![]const u8 {
    const raw = ctx.stdin.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return ctx.fail.set("expected input", .{}),
        error.StreamTooLong => return ctx.fail.set("input is too long", .{}),
        error.ReadFailed => return ctx.fail.set("cannot read input", .{}),
    };
    return std.mem.trim(u8, raw, " \t\r");
}

//
// Namespace already used by a (possibly different) repo in this file.
//
pub fn namespaceTaken(packages: []const config.Package, namespace: []const u8) ?config.Package {
    for (packages) |pkg| {
        if (std.mem.eql(u8, pkg.namespace, namespace)) {
            return pkg;
        }
    }
    return null;
}

//
// Packages that match query by the remove/update/docs rules, unique by YAML index.
//
pub fn matchPackages(
    allocator: std.mem.Allocator,
    packages: []const config.Package,
    query: []const u8,
    fail: *Failure,
) skilled.failure.Error![]Match {
    var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
    var matches: std.ArrayList(Match) = .empty;
    for (packages, 0..) |pkg, index| {
        if (!try entryMatches(allocator, pkg, query, fail)) {
            continue;
        }
        if (seen.contains(index)) {
            continue;
        }
        try seen.put(allocator, index, {});
        try matches.append(allocator, .{ .index = index, .pkg = pkg });
    }
    return matches.toOwnedSlice(allocator);
}

//
// Exactly one match, or an error listing the matches / saying nothing matched.
//
pub fn requireOneMatch(
    allocator: std.mem.Allocator,
    packages: []const config.Package,
    query: []const u8,
    fail: *Failure,
) skilled.failure.Error!Match {
    const matches = try matchPackages(allocator, packages, query, fail);
    if (matches.len == 0) {
        return fail.set("no package matching '{s}'", .{query});
    }
    if (matches.len > 1) {
        var listed: std.ArrayList(u8) = .empty;
        for (matches, 0..) |m, i| {
            if (i > 0) {
                try listed.appendSlice(allocator, ", ");
            }
            try listed.print(allocator, "{s} ({s})", .{ m.pkg.namespace, m.pkg.repo });
        }
        return fail.set(
            "ambiguous match '{s}' ({s}); pass a unique owner/repo or the namespace",
            .{ query, listed.items },
        );
    }
    return matches[0];
}

//
// HTTPS URL of the git repo, built only from a validated Remote.
//
pub fn httpsRepoUrl(allocator: std.mem.Allocator, parsed: remote.Remote) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "https://{s}/{s}/{s}", .{ parsed.host, parsed.owner, parsed.repo });
}

//
// GitHub Pages guess, printed as text, never fetched.
//
pub fn pagesGuessUrl(allocator: std.mem.Allocator, parsed: remote.Remote) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "https://{s}.github.io/{s}/", .{ parsed.owner, parsed.repo });
}

//
// Argv that opens url: SKL_BROWSER when set, otherwise the platform opener.
//
// Pub so tests can assert the Windows `start` empty-title form without spawning.
//
pub fn browserArgv(
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    url: []const u8,
    os_tag: std.Target.Os.Tag,
) std.mem.Allocator.Error![]const []const u8 {
    if (nonEmpty(environ.get("SKL_BROWSER"))) |browser| {
        const argv = try allocator.alloc([]const u8, 2);
        argv[0] = browser;
        argv[1] = url;
        return argv;
    }
    switch (os_tag) {
        .windows => {
            const argv = try allocator.alloc([]const u8, 5);
            argv[0] = "cmd.exe";
            argv[1] = "/C";
            argv[2] = "start";
            argv[3] = "";
            argv[4] = url;
            return argv;
        },
        .macos => {
            const argv = try allocator.alloc([]const u8, 2);
            argv[0] = "open";
            argv[1] = url;
            return argv;
        },
        else => {
            const argv = try allocator.alloc([]const u8, 2);
            argv[0] = "xdg-open";
            argv[1] = url;
            return argv;
        },
    }
}

//
// Opens url with the context's browser runner. Never a shell.
//
pub fn openUrl(ctx: *const Context, url: []const u8) skilled.failure.Error!void {
    const argv = try browserArgv(ctx.allocator, ctx.environ, url, builtin.os.tag);
    switch (ctx.browser) {
        .process => try spawnBrowser(ctx, argv),
        .custom => |custom| try custom.runFn(custom.ctx, ctx.io, ctx.allocator, ctx.environ, argv, ctx.fail),
    }
}

//
// Wraps text in ANSI when color is on. Returns text unchanged otherwise, so callers can print either.
//
pub fn paint(allocator: std.mem.Allocator, style: term.Style, code: []const u8, text: []const u8) std.mem.Allocator.Error![]const u8 {
    if (!style.color) {
        return text;
    }
    return std.fmt.allocPrint(allocator, "\x1b[{s}m{s}\x1b[0m", .{ code, text });
}

//
// True when query matches this YAML entry by any of the five remove rules.
//
fn entryMatches(
    allocator: std.mem.Allocator,
    pkg: config.Package,
    query: []const u8,
    fail: *Failure,
) skilled.failure.Error!bool {
    if (std.mem.eql(u8, pkg.repo, query) or std.mem.eql(u8, pkg.namespace, query)) {
        return true;
    }
    _ = fail;
    var parse_fail = Failure.init(allocator);
    const parsed = remote.parse(allocator, pkg.repo, &parse_fail) catch return false;
    if (std.mem.eql(u8, parsed.clone_url, query) or std.mem.eql(u8, parsed.repo, query)) {
        return true;
    }
    const shorthand = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ parsed.owner, parsed.repo });
    return std.mem.eql(u8, shorthand, query);
}

//
// Spawns argv with std.process.run. FileNotFound is worded as a missing opener.
//
fn spawnBrowser(ctx: *const Context, argv: []const []const u8) skilled.failure.Error!void {
    const spawned = std.process.run(ctx.allocator, ctx.io, .{
        .argv = argv,
        .environ_map = ctx.environ,
        .stdout_limit = .limited(files.MAX_FILE_BYTES),
        .stderr_limit = .limited(files.MAX_FILE_BYTES),
    }) catch |err| switch (err) {
        error.FileNotFound => return ctx.fail.set("browser not found: {s}", .{argv[0]}),
        error.OutOfMemory => return error.OutOfMemory,
        else => return ctx.fail.set("browser failed to start: {s}", .{@errorName(err)}),
    };
    switch (spawned.term) {
        .exited => |code| {
            if (code != 0) {
                return ctx.fail.set("browser exited with code {d}", .{code});
            }
        },
        else => return ctx.fail.set("browser was killed before it finished", .{}),
    }
}

//
// The slice when it is present and non-empty, otherwise null.
//
fn nonEmpty(value: ?[]const u8) ?[]const u8 {
    const slice = value orelse return null;
    if (slice.len == 0) {
        return null;
    }
    return slice;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("shared.test.zig");
}
