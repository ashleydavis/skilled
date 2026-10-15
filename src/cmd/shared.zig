//
// Helpers several commands share: missing config, store paths, package matching, URLs, prompts.
//

const std = @import("std");
const builtin = @import("builtin");
const skilled = @import("skilled");

const context_mod = @import("context.zig");

//
// The run values commands already received from main.
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
// The scratch directory: its reserved namespace, and the call that creates and links it.
//
const scratch = skilled.scratch;

//
// Color and icons for painted stdout.
//
const term = skilled.term;

//
// How a refused command says why: the failure every function here returns in place of its value.
//
const failure = skilled.failure;

//
// The message used when the active scope has no skl.yaml.
//
pub const missing_config_message = "No skl.yaml here; run skl init.";

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
    // Whether this run created the clone, as opposed to finding it already in the store.
    //
    cloned: bool = false,

    //
    // Host, owner, repo, and clone URL after step-6 validation.
    //
    parsed: remote.Remote,

    //
    // `<store>/<host>/<owner>/<repo>@<branch>`.
    //
    dest: []const u8,

    //
    // The branch dest is a clone of: the row's `branch`, or `config.default_branch` when it has none.
    //
    // Held here so the clone and the directory name cannot disagree about which branch it is.
    //
    branch: []const u8,
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
    const st = std.Io.Dir.cwd().statFile(io, path, .{
        .follow_symlinks = true,
    }) catch return false;
    return st.kind == .directory;
}

//
// Reads skl.yaml, or the missing-config error if the file is not there.
//
pub fn requireConfig(ctx: *const Context, config_path: []const u8) std.mem.Allocator.Error!failure.Result(config.File) {
    if (!files.fileExists(ctx.io, config_path)) {
        return .{
            .failed = failure.because("{s}", .{missing_config_message}),
        };
    }
    return config.readFile(ctx.io, ctx.allocator, config_path);
}

//
// Parses a YAML repo spec and joins it, with its branch, onto the store root.
//
// A null branch is `config.default_branch`. The branch is validated here, before it becomes part
// of a directory name, so a YAML row cannot name a path outside the store.
//
pub fn resolveStore(ctx: *const Context, spec: []const u8, branch: ?[]const u8) std.mem.Allocator.Error!failure.Result(Resolved) {
    const parsed = switch (try remote.parse(ctx.allocator, spec)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const name = branch orelse config.default_branch;
    switch (remote.validateBranch(name)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    const dest = try paths.clonePath(ctx.allocator, try storeDir(ctx), parsed.host, parsed.owner, parsed.repo, name);
    return .{
        .ok = .{
            .parsed = parsed,
            .dest = dest,
            .branch = name,
            .cloned = false,
        },
    };
}

//
// Clones into the store when dest is missing. An existing dest is reused: every scope that names
// the same repo and branch shares it, and it is already on that branch because each branch has its
// own clone. Progress is drawn only for an actual clone.
//
pub fn ensureCloned(ctx: *const Context, spec: []const u8, branch: ?[]const u8, spinner: *progress.Progress) std.mem.Allocator.Error!failure.Result(Resolved) {
    var resolved = switch (try resolveStore(ctx, spec, branch)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (dirExists(ctx.io, resolved.dest)) {
        return .{
            .ok = resolved,
        };
    }
    spinner.cloning(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ resolved.parsed.owner, resolved.parsed.repo }));
    defer spinner.finish();
    switch (try git.clone(
        ctx.io,
        ctx.allocator,
        ctx.environ,
        ctx.git,
        resolved.parsed.clone_url,
        resolved.dest,
        resolved.branch,
    )) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    resolved.cloned = true;
    return .{
        .ok = resolved,
    };
}

//
// Directory whose skills/ and commands/ trees are linked: a `local:` path, else the store clone.
//
pub fn contentDir(ctx: *const Context, pkg: config.Package) std.mem.Allocator.Error!failure.Result([]const u8) {
    if (pkg.local) |local| {
        return .{
            .ok = try files.absolutePath(ctx.allocator, ctx.cwd, local),
        };
    }
    const resolved = switch (try resolveStore(ctx, pkg.repo, pkg.branch)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    return .{
        .ok = resolved.dest,
    };
}

//
// Absolute path of a local working tree that is a git repo and a valid package.
//
// Empty is refused. Relative paths are resolved against ctx.cwd. `.git` may be a directory or a
// gitfile (a regular file); a missing `.git` is not a repo.
//
pub fn resolveLocal(ctx: *const Context, path: []const u8) std.mem.Allocator.Error!failure.Result([]const u8) {
    if (path.len == 0) {
        return .{
            .failed = failure.because("The --local path is empty.", .{}),
        };
    }
    const abs = try files.absolutePath(ctx.allocator, ctx.cwd, path);
    if (!dirExists(ctx.io, abs)) {
        return .{
            .failed = failure.because("Local path {s} is not a directory.", .{abs}),
        };
    }
    const git_dir = try files.joinPath(ctx.allocator, &.{ abs, ".git" });
    const git_st = std.Io.Dir.cwd().statFile(ctx.io, git_dir, .{
        .follow_symlinks = true,
    }) catch {
        return .{
            .failed = failure.because("Local path {s} is not a git repository.", .{abs}),
        };
    };
    if (git_st.kind != .directory and git_st.kind != .file) {
        return .{
            .failed = failure.because("Local path {s} is not a git repository.", .{abs}),
        };
    }
    switch (try package.scan(ctx.io, ctx.allocator, abs)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .{
        .ok = abs,
    };
}

//
// Creates this scope's scratch directory and links it as the reserved namespace.
//
// The one place that happens, so `init`, `install`, and a no-flag `update` cannot drift on where
// the directory is or what it is called. The line is printed only when something was created or
// repaired, so a routine run says nothing about a directory that was already there.
//
pub fn syncScratch(ctx: *const Context, scope: paths.Scope) std.mem.Allocator.Error!failure.Result(void) {
    const status = switch (try scratch.sync(ctx.io, ctx.allocator, scope)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (status == .unchanged) {
        return .ok;
    }
    return line(ctx, "{s} Scratch directory at {s}.", .{ ctx.style.check(), try muted(ctx, scope.scratch_dir) });
}

//
// Clones missing packages and links each namespace in `file`.
//
// Same work as `skl install`. `init --from` calls this so the developer does not run a second
// command after the YAML is written. On package *k* of *N* failing, packages 1..k-1 stay cloned
// and linked; there is no rollback.
//
pub fn installAll(ctx: *const Context, scope: paths.Scope, file: config.File) std.mem.Allocator.Error!failure.Result(u8) {
    var spinner = newSpinner(ctx);
    defer spinner.finish();

    for (file.packages) |pkg| {
        switch (try installOne(ctx, scope, pkg, &spinner)) {
            .ok => {},
            .failed => |why| return .{
                .failed = failure.because("Install failed on {s}: {s}", .{ pkg.repo, why.message() }),
            },
        }
    }
    return .{
        .ok = 0,
    };
}

//
// Clone if missing, scan, then link. A failure from a helper is returned as-is; installAll names the
// package in front of it.
//
fn installOne(
    ctx: *const Context,
    scope: paths.Scope,
    pkg: config.Package,
    spinner: *progress.Progress,
) std.mem.Allocator.Error!failure.Result(void) {
    if (pkg.local) |local_path| {
        const dest = switch (try resolveLocal(ctx, local_path)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ pkg.namespace, pkg.repo }));
        const linked = switch (try link.linkPackage(ctx.io, ctx.allocator, dest, pkg.namespace, scope)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        spinner.finish();
        if (linked == .changed) {
            return line(ctx, "{s} Installed {s}.", .{ ctx.style.check(), try identifier(ctx, pkg.repo) });
        }
        return line(ctx, "  {s} is already installed.", .{try identifier(ctx, pkg.repo)});
    }
    const resolved = switch (try ensureCloned(ctx, pkg.repo, pkg.branch, spinner)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (try package.scan(ctx.io, ctx.allocator, resolved.dest)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ pkg.namespace, resolved.parsed.repo }));
    const linked = switch (try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, pkg.namespace, scope)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    spinner.finish();
    //
    // Every package accounts for itself, but only a package that needed work gets the mark: a tick
    // means something was cloned or relinked, a plain line means it was checked and left alone.
    //
    if (resolved.cloned or linked == .changed) {
        return line(ctx, "{s} Installed {s}.", .{ ctx.style.check(), try identifier(ctx, pkg.repo) });
    }
    return line(ctx, "  {s} is already installed.", .{try identifier(ctx, pkg.repo)});
}

//
// A progress line.
//
pub fn newSpinner(ctx: *const Context) progress.Progress {
    return progress.Progress.init(ctx.stderr, ctx.style, ctx.non_interactive, ctx.stderr_is_tty);
}

//
// Writes one line to stdout, or the failure that says output could not be written.
//
pub fn line(ctx: *const Context, comptime fmt: []const u8, args: anytype) failure.Result(void) {
    ctx.stdout.print(fmt ++ "\n", args) catch {
        return .{
            .failed = failure.because("Cannot write output.", .{}),
        };
    };
    return .ok;
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
pub fn promptLine(ctx: *const Context) std.mem.Allocator.Error!failure.Result([]const u8) {
    const raw = ctx.stdin.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return .{
            .failed = failure.because("Expected input.", .{}),
        },
        error.StreamTooLong => return .{
            .failed = failure.because("Input is too long.", .{}),
        },
        error.ReadFailed => return .{
            .failed = failure.because("Cannot read input.", .{}),
        },
    };
    return .{
        .ok = std.mem.trim(u8, raw, " \t\r"),
    };
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
// Packages that match query by the remove/update/docs rules, one per YAML row, in file order.
//
pub fn matchPackages(
    allocator: std.mem.Allocator,
    packages: []const config.Package,
    query: []const u8,
) std.mem.Allocator.Error![]Match {
    var matches: std.ArrayList(Match) = .empty;
    for (packages, 0..) |pkg, index| {
        if (!try entryMatches(allocator, pkg, query)) {
            continue;
        }
        try matches.append(allocator, .{
            .index = index,
            .pkg = pkg,
        });
    }
    return matches.toOwnedSlice(allocator);
}

//
// Exactly one match, or an error listing the matches / saying nothing matched.
//
// A query naming the scratch namespace is refused with its own wording.
//
pub fn requireOneMatch(
    allocator: std.mem.Allocator,
    packages: []const config.Package,
    query: []const u8,
) std.mem.Allocator.Error!failure.Result(Match) {
    //
    // The scratch namespace can never be a row (config.parse refuses it), so the generic no-match
    // wording would send a user looking for a package that cannot exist. Answered here rather than
    // in remove, update, and docs separately.
    //
    if (scratch.isReserved(query)) {
        return .{
            .failed = failure.because("{s} is the scratch directory, not a package.", .{query}),
        };
    }
    const matches = try matchPackages(allocator, packages, query);
    if (matches.len == 0) {
        return .{
            .failed = failure.because("No package matching '{s}'.", .{query}),
        };
    }
    if (matches.len > 1) {
        var listed: std.ArrayList(u8) = .empty;
        for (matches, 0..) |m, i| {
            if (i > 0) {
                try listed.appendSlice(allocator, ", ");
            }
            try listed.print(allocator, "{s} ({s})", .{ m.pkg.namespace, m.pkg.repo });
        }
        return .{
            .failed = failure.because(
                "Ambiguous match '{s}' ({s}); pass a unique owner/repo or the namespace.",
                .{ query, listed.items },
            ),
        };
    }
    return .{
        .ok = matches[0],
    };
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
// The process runner spawns argv with std.process.run, and FileNotFound is worded as a missing
// opener.
//
pub fn openUrl(ctx: *const Context, url: []const u8) std.mem.Allocator.Error!failure.Result(void) {
    const argv = try browserArgv(ctx.allocator, ctx.environ, url, builtin.os.tag);
    switch (ctx.browser) {
        .process => {},
        .function => |function| {
            return function.runFn(function.ctx, ctx.io, ctx.allocator, ctx.environ, argv);
        },
    }
    const spawned = std.process.run(ctx.allocator, ctx.io, .{
        .argv = argv,
        .environ_map = ctx.environ,
        .stdout_limit = .limited(files.MAX_FILE_BYTES),
        .stderr_limit = .limited(files.MAX_FILE_BYTES),
    }) catch |err| switch (err) {
        error.FileNotFound => return .{
            .failed = failure.because("Browser not found: {s}.", .{argv[0]}),
        },
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{
            .failed = failure.because("Browser failed to start: {s}.", .{@errorName(err)}),
        },
    };
    switch (spawned.term) {
        .exited => |code| {
            if (code != 0) {
                return .{
                    .failed = failure.because("Browser exited with code {d}.", .{code}),
                };
            }
        },
        else => return .{
            .failed = failure.because("Browser was killed before it finished.", .{}),
        },
    }
    return .ok;
}

//
// The first seven characters of a SHA, or the whole thing when it is already shorter.
//
// Shared by add and update so one command cannot start abbreviating differently from the other.
//
pub fn shortSha(sha: []const u8) []const u8 {
    if (sha.len <= 7) {
        return sha;
    }
    return sha[0..7];
}

//
// A namespace, painted the way every command paints one.
//
pub fn namespaceText(ctx: *const Context, text: []const u8) std.mem.Allocator.Error![]const u8 {
    return paint(ctx.allocator, ctx.style, term.namespace_color, text);
}

//
// An identifier — owner/repo, a URL, a branch — painted the way every command paints one.
//
pub fn identifier(ctx: *const Context, text: []const u8) std.mem.Allocator.Error![]const u8 {
    return paint(ctx.allocator, ctx.style, term.identifier_color, text);
}

//
// Anything secondary: a path, a SHA, a description.
//
pub fn muted(ctx: *const Context, text: []const u8) std.mem.Allocator.Error![]const u8 {
    return paint(ctx.allocator, ctx.style, term.muted_color, text);
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
) std.mem.Allocator.Error!bool {
    if (std.mem.eql(u8, pkg.repo, query) or std.mem.eql(u8, pkg.namespace, query)) {
        return true;
    }
    const parsed = switch (try remote.parse(allocator, pkg.repo)) {
        .ok => |got| got,
        .failed => return false,
    };
    if (std.mem.eql(u8, parsed.clone_url, query) or std.mem.eql(u8, parsed.repo, query)) {
        return true;
    }
    const shorthand = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ parsed.owner, parsed.repo });
    return std.mem.eql(u8, shorthand, query);
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
