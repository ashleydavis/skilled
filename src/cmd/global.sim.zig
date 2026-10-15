//
// Value factories for the run values every command takes, and the layouts of the project that the
// command scenarios write before they run a command. Every command's functions take a `Context`,
// so the factories are here, where Faultline uses them for every file. The factories build values
// only; writing files is left to the scenarios.
//

const std = @import("std");
const skilled = @import("skilled");

//
// The file that declares `Context`, imported by its own path so the factory returns the type
// Faultline asks for.
//
const context_mod = @import("context.zig");

//
// Where every factory's user lives in Faultline's simulated filesystem.
//
const home = "/home/skilled";

//
// The project directory every factory's command runs in.
//
const project = "/home/skilled/project";

//
// `skl <command>` run in `/home/skilled/project`, with its output going to the writer Faultline
// supplies, so every line a command prints is a place Faultline can make the write fail. The
// project's files are whatever the scenario that calls the command lays out first; a function
// Faultline calls with this context directly finds none.
//
// First, because Faultline's first call to a function uses the first factory for each parameter.
//
pub fn projectRun(allocator: std.mem.Allocator, io: std.Io, stdout: *std.Io.Writer) !*const context_mod.Context {
    return build(allocator, io, .{
        .stdout = stdout,
    });
}

//
// `skl <command>` typed at a terminal in `/home/skilled/project`, with `demo2` typed at the first
// prompt.
//
pub fn interactiveRunTypingDemo2(allocator: std.mem.Allocator, io: std.Io) !*const context_mod.Context {
    return build(allocator, io, .{
        .typed = "demo2\n",
        .interactive = true,
    });
}

//
// `skl <command>` typed at a terminal in `/home/skilled/project`, with `1` typed at the first
// prompt. Its output goes to the writer Faultline supplies, so a menu line is a place Faultline can
// make the write fail.
//
pub fn interactiveRunAnsweringOne(allocator: std.mem.Allocator, io: std.Io, stdout: *std.Io.Writer) !*const context_mod.Context {
    return build(allocator, io, .{
        .typed = "1\n",
        .interactive = true,
        .stdout = stdout,
    });
}

//
// `skl <command>` typed at a terminal in `/home/skilled/project`, with nothing typed before stdin
// ends.
//
pub fn interactiveRunWithNothingTyped(allocator: std.mem.Allocator, io: std.Io) !*const context_mod.Context {
    return build(allocator, io, .{
        .interactive = true,
    });
}

//
// `skl <command>` typed at a terminal in `/home/skilled/project`, with stdin that cannot be read.
//
pub fn interactiveRunWithUnreadableStdin(allocator: std.mem.Allocator, io: std.Io) !*const context_mod.Context {
    return build(allocator, io, .{
        .interactive = true,
        .stdin = .unreadable,
    });
}

//
// `skl <command>` typed at a terminal in `/home/skilled/project`, with a line pasted at the prompt
// that is too long to read.
//
pub fn interactiveRunWithEndlessLine(allocator: std.mem.Allocator, io: std.Io) !*const context_mod.Context {
    return build(allocator, io, .{
        .interactive = true,
        .stdin = .endless,
    });
}

//
// `skl <command>` typed at a terminal in `/home/skilled/project`, where the browser refuses to open
// the page.
//
pub fn interactiveRunWithRefusingBrowser(allocator: std.mem.Allocator, io: std.Io) !*const context_mod.Context {
    return build(allocator, io, .{
        .interactive = true,
        .browser = .refuses,
    });
}

//
// `skl <command>` typed at a terminal in `/home/skilled/project`, where the page is opened by
// starting the system's opener.
//
pub fn interactiveRunOpeningWithProcess(allocator: std.mem.Allocator, io: std.Io) !*const context_mod.Context {
    return build(allocator, io, .{
        .interactive = true,
        .browser = .process,
    });
}

//
// `skl <command>` run in `/home/skilled/project`, where every git repository has no commits yet.
//
pub fn runWithoutCommits(allocator: std.mem.Allocator, io: std.Io) !*const context_mod.Context {
    return build(allocator, io, .{
        .git_without_commits = true,
    });
}

//
// `skl <command>` with no arguments and no options, run in `/home/skilled/project`. It is what a
// command's action receives from Commander's parse, with the command's context in it.
//
pub fn invocationInProject(allocator: std.mem.Allocator, io: std.Io) !*skilled.commander.Invocation {
    const made = try allocator.create(skilled.commander.Invocation);
    made.* = .{
        .context = try build(allocator, io, .{}),
        .args = &.{},
        .values = .empty,
    };
    return made;
}

//
// Lays out a project after `skl install` whose `skl.yaml` has one row of every kind: `acme/skills`
// under `demo`, the same repo on branch `dev` under `demo-dev`, `acme/local` by its SSH address
// linked from the working tree `../local-skills`, `acme/other` under `other` with no clone in the
// store yet, `acme/tools` under `tools` on a branch name git refuses, and `acme` under `broken`,
// which names no repo. The store holds both clones of `acme/skills`, and the scratch directory,
// `demo` and `local` are already linked.
//
pub fn writeEveryKindOfPackage(allocator: std.mem.Allocator, io: std.Io) !void {
    try writeFile(io, project ++ "/skl.yaml",
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: acme/skills
        \\    namespace: demo-dev
        \\    branch: dev
        \\  - repo: git@github.com:acme/local.git
        \\    namespace: local
        \\    local: ../local-skills
        \\  - repo: acme/other
        \\    namespace: other
        \\  - repo: acme/tools
        \\    namespace: tools
        \\    branch: -bad
        \\  - repo: acme
        \\    namespace: broken
        \\
    );
    const main_clone = home ++ "/.skilled/store/github.com/acme/skills@main";
    const local_tree = home ++ "/local-skills";
    try writePackage(allocator, io, main_clone);
    try writePackage(allocator, io, home ++ "/.skilled/store/github.com/acme/skills@dev");
    try writePackage(allocator, io, local_tree);

    const scope = try skilled.paths.scopeFromFlag(allocator, false, home, project, null);
    switch (try skilled.scratch.sync(io, allocator, scope)) {
        .ok => {},
        .failed => return error.ScratchNotLinked,
    }
    switch (try skilled.link.linkPackage(io, allocator, main_clone, "demo", scope)) {
        .ok => {},
        .failed => return error.PackageNotLinked,
    }
    switch (try skilled.link.linkPackage(io, allocator, local_tree, "local", scope)) {
        .ok => {},
        .failed => return error.PackageNotLinked,
    }
}

//
// Everything one context points at, so it can all be one allocation.
//
const Parts = struct {
    //
    // What the command prints to stdout.
    //
    stdout: std.Io.Writer.Allocating,

    //
    // What the command prints to stderr.
    //
    stderr: std.Io.Writer.Allocating,

    //
    // The environment, holding only `HOME`.
    //
    environ: std.process.Environ.Map,

    //
    // What the command reads from stdin.
    //
    stdin: std.Io.Reader,

    //
    // The room stdin reads into when it is a stream rather than fixed text, small so a line longer
    // than it is too long.
    //
    stdin_buffer: [8]u8,

    //
    // True when git answers `rev-parse HEAD` as in a repository with no commits.
    //
    git_without_commits: bool,

    //
    // True when the browser refuses to open the page.
    //
    browser_refuses: bool,

    //
    // The context itself, pointing at the fields above.
    //
    context: context_mod.Context,
};

//
// How a factory's context differs from one run non-interactively with nothing on stdin.
//
const Options = struct {
    //
    // What the user types on stdin.
    //
    typed: []const u8 = "",

    //
    // True to run as if at a terminal: prompts are shown and stderr is a TTY.
    //
    interactive: bool = false,

    //
    // What stdin does instead of giving `typed`: nothing different, fail to be read, or give one
    // line that never ends.
    //
    stdin: Stdin = .typed,

    //
    // Where the command's output goes in place of a buffer that always takes it. Faultline passes
    // a writer that fails where it injects a failure.
    //
    stdout: ?*std.Io.Writer = null,

    //
    // True when git answers `rev-parse HEAD` as in a repository with no commits.
    //
    git_without_commits: bool = false,

    //
    // How the page is opened: by a browser that opens it, one that refuses, or by starting the
    // opener as a process, which Faultline simulates.
    //
    browser: Browser = .opens,
};

//
// What stdin does in a factory's context.
//
const Stdin = enum {
    //
    // Gives the text in `Options.typed`.
    //
    typed,

    //
    // Fails to be read.
    //
    unreadable,

    //
    // Gives one line that never ends.
    //
    endless,
};

//
// How the page is opened in a factory's context.
//
const Browser = enum {
    //
    // A browser that opens it.
    //
    opens,

    //
    // A browser that refuses.
    //
    refuses,

    //
    // The opener started as a process.
    //
    process,
};

//
// `skl <command>` run in the project as `options` says, in whatever the caller has laid out with
// the `write` functions here. Each command's sim file builds its contexts with this.
//
pub fn build(allocator: std.mem.Allocator, io: std.Io, options: Options) !*const context_mod.Context {
    const parts = try allocator.create(Parts);
    parts.stdout = .init(allocator);
    parts.stderr = .init(allocator);
    parts.environ = .init(allocator);
    try parts.environ.put("HOME", home);
    parts.stdin = switch (options.stdin) {
        .typed => .fixed(options.typed),
        .unreadable => .failing,
        .endless => .{
            .vtable = &.{
                .stream = streamEndlessLine,
            },
            .buffer = &parts.stdin_buffer,
            .seek = 0,
            .end = 0,
        },
    };
    parts.git_without_commits = options.git_without_commits;
    parts.browser_refuses = options.browser == .refuses;
    const stdout = options.stdout orelse &parts.stdout.writer;
    parts.context = .init(allocator, io, &parts.environ, project, home, &parts.stdin, stdout, &parts.stderr.writer);
    parts.context.non_interactive = !options.interactive;
    parts.context.stderr_is_tty = options.interactive;
    parts.context.git = .{
        .function = .{
            .ctx = parts,
            .runFn = &answerGit,
        },
    };
    parts.context.browser = switch (options.browser) {
        .opens, .refuses => .{
            .function = .{
                .ctx = parts,
                .runFn = &openPage,
            },
        },
        .process => .process,
    };
    return &parts.context;
}

//
// What an endless stdin gives: the same letter, again and again, with no end of line.
//
fn streamEndlessLine(_: *std.Io.Reader, writer: *std.Io.Writer, _: std.Io.Limit) std.Io.Reader.StreamError!usize {
    try writer.writeByte('a');
    return 1;
}

//
// Lays out the project's `skl.yaml` listing `acme/skills` under `demo`, and that package's clone in
// the store: one skill, one command and a README with a description.
//
pub fn writeOnePackage(allocator: std.mem.Allocator, io: std.Io) !void {
    try writeFile(io, project ++ "/skl.yaml",
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );
    try writePackage(allocator, io, home ++ "/.skilled/store/github.com/acme/skills@main");
}

//
// A package at `dest`: a git working tree with one skill, one command and a README with a
// description.
//
fn writePackage(allocator: std.mem.Allocator, io: std.Io, dest: []const u8) !void {
    try writeFile(io, try skilled.files.joinPath(allocator, &.{ dest, ".git", "HEAD" }), "ref: refs/heads/main\n");
    try writeFile(io, try skilled.files.joinPath(allocator, &.{ dest, "skills", "hello", "SKILL.md" }),
        \\---
        \\description: Says hello.
        \\---
        \\
        \\# Hello
        \\
    );
    try writeFile(io, try skilled.files.joinPath(allocator, &.{ dest, "commands", "plan.md" }), "# Plan\n\nMakes a plan.\n");
    try writeFile(io, try skilled.files.joinPath(allocator, &.{ dest, "README.md" }), "# Skills\n\nSkills for acme.\n");
}

//
// What git answers in every factory's context, in place of starting the `git` program, which
// Faultline simulates without output. Each command gets the output a real repository on `main` with
// nothing to pull would give: `clone` writes a package at its destination, `rev-parse HEAD` prints
// a full commit SHA (a different one in a clone of `dev`), `rev-parse --abbrev-ref HEAD` prints
// `main`, the upstream is `origin/main`, `show` prints an `skl.yaml` with one package, and the rest
// succeed silently. In a context whose git has no commits, `rev-parse HEAD` fails the way git does
// in a repository with no commits.
//
fn answerGit(
    ctx: *anyopaque,
    io: std.Io,
    allocator: std.mem.Allocator,
    _: *const std.process.Environ.Map,
    argv: []const []const u8,
    cwd: ?[]const u8,
) skilled.git.RunError!skilled.failure.Result(skilled.git.Result) {
    const parts: *const Parts = @ptrCast(@alignCast(ctx));
    const command = argv[1];
    var stdout: []const u8 = "";
    if (parts.git_without_commits and std.mem.eql(u8, command, "rev-parse") and argv.len == 3) {
        return .{
            .ok = .{
                .stdout = "",
                .stderr = "fatal: ambiguous argument 'HEAD': unknown revision or path not in the working tree.\n",
                .exit_code = 128,
            },
        };
    }
    if (std.mem.eql(u8, command, "clone")) {
        writePackage(allocator, io, argv[argv.len - 1]) catch {
            return .{
                .failed = skilled.failure.because("The clone could not be written.", .{}),
            };
        };
    } else if (std.mem.eql(u8, command, "show")) {
        stdout = "packages:\n  - repo: acme/tools\n    namespace: tools\n";
    } else if (std.mem.eql(u8, command, "rev-parse") and std.mem.eql(u8, argv[argv.len - 1], "@{upstream}")) {
        stdout = "origin/main\n";
    } else if (std.mem.eql(u8, command, "rev-parse") and argv.len == 4) {
        stdout = "main\n";
    } else if (std.mem.eql(u8, command, "rev-parse") and std.mem.endsWith(u8, cwd orelse "", "@dev")) {
        stdout = "fedcba9876543210fedcba9876543210fedcba98\n";
    } else if (std.mem.eql(u8, command, "rev-parse")) {
        stdout = "0123456789abcdef0123456789abcdef01234567\n";
    }
    return .{
        .ok = .{
            .stdout = stdout,
            .stderr = "",
            .exit_code = 0,
        },
    };
}

//
// What the browser does in a factory's context, in place of starting the opener: it opens the page,
// or refuses in a context whose browser refuses.
//
fn openPage(
    ctx: *anyopaque,
    _: std.Io,
    _: std.mem.Allocator,
    _: *const std.process.Environ.Map,
    _: []const []const u8,
) std.mem.Allocator.Error!skilled.failure.Result(void) {
    const parts: *const Parts = @ptrCast(@alignCast(ctx));
    if (parts.browser_refuses) {
        return .{
            .failed = skilled.failure.because("Browser exited with code 1.", .{}),
        };
    }
    return .ok;
}

//
// Lays out the working tree `../local-skills` beside the project: a git repository that is a
// package with one skill.
//
pub fn writeLocalTree(io: std.Io) !void {
    try writeFile(io, home ++ "/local-skills/.git/HEAD", "ref: refs/heads/main\n");
    try writeFile(io, home ++ "/local-skills/skills/hello/SKILL.md", "# Hello\n\nSays hello.\n");
}

//
// Lays out a project whose `skl.yaml` gives the namespace `tools` to `acme/other-tools`, another
// repo than the one `skl add --from` fetches under that namespace.
//
pub fn writeToolsNamespaceTaken(io: std.Io) !void {
    try writeFile(io, project ++ "/skl.yaml",
        \\packages:
        \\  - repo: acme/other-tools
        \\    namespace: tools
        \\
    );
}

//
// Lays out a project after `skl init`: an `skl.yaml` that lists no packages and the scratch
// directory, created and linked.
//
pub fn writeScratchOnly(allocator: std.mem.Allocator, io: std.Io) !void {
    try writeEmptyConfig(io);
    const scope = try skilled.paths.scopeFromFlag(allocator, false, home, project, null);
    switch (try skilled.scratch.sync(io, allocator, scope)) {
        .ok => {},
        .failed => return error.ScratchNotLinked,
    }
}

//
// Lays out a project whose `skl.yaml` lists no packages.
//
pub fn writeEmptyConfig(io: std.Io) !void {
    try writeFile(io, project ++ "/skl.yaml", "packages: []\n");
}

//
// Writes one file in the simulated filesystem, creating the directories above it.
//
fn writeFile(io: std.Io, path: []const u8, contents: []const u8) !void {
    try skilled.files.makeParentDir(io, path);
    try skilled.files.writeFile(io, path, contents);
}
