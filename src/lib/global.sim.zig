//
// Value factories used for every file: how git is started, the environment a run sees and the
// paths one run reads and writes. Several files take each of these, so they are here, where
// Faultline uses them for all of them. The layouts of the project that the scenarios write before
// they call the code are here too; the factories themselves build values only.
//

const std = @import("std");

//
// The result type a git runner returns, imported by its own path as the lib files import it.
//
const failure = @import("failure.zig");

//
// The git runner type, imported by its own path as the lib files import it.
//
const git = @import("git.zig");

//
// The scope type, imported by its own path as the lib files import it.
//
const paths = @import("paths.zig");

//
// The files a factory lays out in Faultline's simulated filesystem.
//
const files = @import("files.zig");

//
// How `skl add acme/skills --ns demo` runs git when git answers like a repository on `main` with
// nothing to pull: `rev-parse HEAD` prints a full commit SHA, `rev-parse --abbrev-ref HEAD` prints
// `main`, the upstream is `origin/main`, `show` prints an `skl.yaml` with one package, and the rest
// succeed silently.
//
// First, because Faultline's first call to a function uses the first factory for each parameter.
// `cmd/global.sim.zig` answers the same way for the commands: the two cannot share one function,
// because this file's `GitRunner` is the copy of `git.zig` imported by path and the commands use
// the copy in the `skilled` module.
//
pub fn answeringGit(allocator: std.mem.Allocator) !git.GitRunner {
    return answering(allocator, .up_to_date);
}

//
// How `skl update demo` runs git when the clone has a detached HEAD.
//
pub fn detachedGit(allocator: std.mem.Allocator) !git.GitRunner {
    return answering(allocator, .detached);
}

//
// How `skl update demo` runs git when the clone has uncommitted changes.
//
pub fn dirtyGit(allocator: std.mem.Allocator) !git.GitRunner {
    return answering(allocator, .dirty);
}

//
// How `skl update demo` runs git when the clone's branch has no upstream.
//
pub fn noUpstreamGit(allocator: std.mem.Allocator) !git.GitRunner {
    return answering(allocator, .no_upstream);
}

//
// How `skl update demo` runs git when `git fetch` fails.
//
pub fn fetchFailingGit(allocator: std.mem.Allocator) !git.GitRunner {
    return answering(allocator, .fetch_fails);
}

//
// How `skl update demo` runs git when the clone has diverged from its upstream and `git merge`
// says why.
//
pub fn divergedGit(allocator: std.mem.Allocator) !git.GitRunner {
    return answering(allocator, .diverged);
}

//
// How `skl update demo` runs git when the clone has diverged from its upstream and `git merge`
// prints nothing.
//
pub fn silentlyDivergedGit(allocator: std.mem.Allocator) !git.GitRunner {
    return answering(allocator, .diverged_silently);
}

//
// How `skl add acme/skills --ns demo` runs git when every git command fails with exit code 128.
//
pub fn failingGit(allocator: std.mem.Allocator) !git.GitRunner {
    return .{
        .function = .{
            .ctx = try allocator.create(u8),
            .runFn = &failGit,
        },
    };
}

//
// How `skl add acme/skills --ns demo` runs git when `git` is not on PATH.
//
pub fn missingGit(allocator: std.mem.Allocator) !git.GitRunner {
    return .{
        .function = .{
            .ctx = try allocator.create(u8),
            .runFn = &findNoGit,
        },
    };
}

//
// How every `skl` command that runs git starts it, such as `skl add acme/skills --ns demo`: by
// spawning `git`. Faultline simulates the process.
//
pub fn spawnsGit() git.GitRunner {
    return git.processRunner();
}

//
// The environment of `HOME=/home/skilled skl <command>`, which git is started with, allocated from
// the allocator Faultline passes in so it lasts as long as the call.
//
pub fn environment(allocator: std.mem.Allocator) !*const std.process.Environ.Map {
    const made = try allocator.create(std.process.Environ.Map);
    made.* = .init(allocator);
    try made.put("HOME", "/home/skilled");
    return made;
}

//
// The environment of `SKL_BROWSER=firefox skl docs demo`, which names the browser `skl docs` opens.
//
pub fn environmentWithBrowser(allocator: std.mem.Allocator) !*const std.process.Environ.Map {
    const made = try allocator.create(std.process.Environ.Map);
    made.* = .init(allocator);
    try made.put("HOME", "/home/skilled");
    try made.put("SKL_BROWSER", "firefox");
    return made;
}

//
// The environment of `skl` on Windows, where `USERPROFILE` names the home directory and `HOME` is
// not set.
//
pub fn environmentWithUserProfile(allocator: std.mem.Allocator) !*const std.process.Environ.Map {
    const made = try allocator.create(std.process.Environ.Map);
    made.* = .init(allocator);
    try made.put("USERPROFILE", "C:\\Users\\skilled");
    return made;
}

//
// The environment of `env -i skl list`, which has no home directory at all.
//
pub fn emptyEnvironment(allocator: std.mem.Allocator) !*const std.process.Environ.Map {
    const made = try allocator.create(std.process.Environ.Map);
    made.* = .init(allocator);
    return made;
}

//
// The state of the repository an answering git plays.
//
const Situation = enum {
    //
    // On `main`, clean, with nothing to pull.
    //
    up_to_date,

    //
    // HEAD is detached.
    //
    detached,

    //
    // The working tree has uncommitted changes.
    //
    dirty,

    //
    // The branch has no upstream.
    //
    no_upstream,

    //
    // `git fetch` exits 128.
    //
    fetch_fails,

    //
    // `git merge --ff-only` exits 128 and says why.
    //
    diverged,

    //
    // `git merge --ff-only` exits 128 and prints nothing.
    //
    diverged_silently,
};

//
// A git runner whose function plays `situation`, which it is handed back on every call.
//
fn answering(allocator: std.mem.Allocator, situation: Situation) !git.GitRunner {
    const state = try allocator.create(Situation);
    state.* = situation;
    return .{
        .function = .{
            .ctx = state,
            .runFn = &answerGit,
        },
    };
}

//
// What an answering git prints for `argv` in the situation `ctx` points at.
//
fn answerGit(
    ctx: *anyopaque,
    _: std.Io,
    _: std.mem.Allocator,
    _: *const std.process.Environ.Map,
    argv: []const []const u8,
    _: ?[]const u8,
) git.RunError!failure.Result(git.Result) {
    const situation: *const Situation = @ptrCast(@alignCast(ctx));
    const command = argv[1];
    const last = argv[argv.len - 1];
    if (std.mem.eql(u8, command, "show")) {
        return printed("packages:\n  - repo: acme/tools\n    namespace: tools\n");
    }
    if (std.mem.eql(u8, command, "rev-parse") and std.mem.eql(u8, last, "@{upstream}")) {
        if (situation.* == .no_upstream) {
            return refused("fatal: no upstream configured for branch 'main'\n");
        }
        return printed("origin/main\n");
    }
    if (std.mem.eql(u8, command, "rev-parse") and argv.len == 4) {
        if (situation.* == .detached) {
            return printed("HEAD\n");
        }
        return printed("main\n");
    }
    if (std.mem.eql(u8, command, "rev-parse")) {
        return printed("0123456789abcdef0123456789abcdef01234567\n");
    }
    if (std.mem.eql(u8, command, "status") and situation.* == .dirty) {
        return printed(" M README.md\n");
    }
    if (std.mem.eql(u8, command, "fetch") and situation.* == .fetch_fails) {
        return refused("fatal: unable to access the remote\n");
    }
    if (std.mem.eql(u8, command, "merge") and situation.* == .diverged) {
        return refused("fatal: Not possible to fast-forward, aborting.\n");
    }
    if (std.mem.eql(u8, command, "merge") and situation.* == .diverged_silently) {
        return refused("");
    }
    return printed("");
}

//
// A git command that exits 0 after printing `stdout`.
//
fn printed(stdout: []const u8) failure.Result(git.Result) {
    return .{
        .ok = .{
            .stdout = stdout,
            .stderr = "",
            .exit_code = 0,
        },
    };
}

//
// A git command that exits 128 after printing `stderr`.
//
fn refused(stderr: []const u8) failure.Result(git.Result) {
    return .{
        .ok = .{
            .stdout = "",
            .stderr = stderr,
            .exit_code = 128,
        },
    };
}

//
// What `failingGit` runs in place of `git`.
//
fn failGit(
    _: *anyopaque,
    _: std.Io,
    _: std.mem.Allocator,
    _: *const std.process.Environ.Map,
    _: []const []const u8,
    _: ?[]const u8,
) git.RunError!failure.Result(git.Result) {
    return refused("fatal: not a git repository\n");
}

//
// What `missingGit` runs in place of `git`.
//
fn findNoGit(
    _: *anyopaque,
    _: std.Io,
    _: std.mem.Allocator,
    _: *const std.process.Environ.Map,
    _: []const []const u8,
    _: ?[]const u8,
) git.RunError!failure.Result(git.Result) {
    return error.FileNotFound;
}

//
// The paths `skl install` uses in the project `/home/skilled/project`.
//
pub fn projectScope(allocator: std.mem.Allocator) !paths.Scope {
    return paths.scopeFromFlag(allocator, false, "/home/skilled", "/home/skilled/project", null);
}

//
// The paths `skl install -g` uses for the user `/home/skilled`.
//
pub fn globalScope(allocator: std.mem.Allocator) !paths.Scope {
    return paths.scopeFromFlag(allocator, true, "/home/skilled", "/home/skilled/project", null);
}

//
// Lays out the project as a first `skl install` leaves it for the second: the scratch directory
// made and linked under the `loc` namespace in every agent directory.
//
pub fn writeScratchAlreadyLinked(io: std.Io) !void {
    try linkScratch(io, "/home/skilled/project/.skilled/scratch/skills", "/home/skilled/project/.skilled/scratch/commands");
}

//
// Lays out the project as `skl install` finds it after the scratch directory moved: the `loc`
// links in every agent directory still name the old place.
//
pub fn writeStaleScratchLinks(io: std.Io) !void {
    try linkScratch(io, "/home/skilled/old/skills", "/home/skilled/old/commands");
}

//
// Lays out the project as `skl install` finds it when `.claude/skills` is a file someone made by
// hand, so links cannot go inside it.
//
pub fn writeAgentRootAsFile(io: std.Io) !void {
    try writeFile(io, "/home/skilled/project/.claude/skills", "not a directory\n");
}

//
// Lays out the project as `skl install` finds it when `.claude/commands` is a file someone made by
// hand, so links cannot go inside it.
//
pub fn writeClaudeCommandsAsFile(io: std.Io) !void {
    try writeFile(io, "/home/skilled/project/.claude/commands", "not a directory\n");
}

//
// Lays out the project as `skl install` finds it when `.cursor/skills` is a symlink someone made by
// hand, so `skl` will not put links inside it.
//
pub fn writeAgentRootAsSymlink(io: std.Io) !void {
    try files.makeDirPath(io, "/home/skilled/elsewhere");
    try files.makeDirPath(io, "/home/skilled/project/.cursor");
    try std.Io.Dir.cwd().symLink(io, "/home/skilled/elsewhere", "/home/skilled/project/.cursor/skills", .{
        .is_directory = true,
    });
}

//
// Lays out the project as `skl install` finds it when a file someone made by hand sits where the
// scratch directory's `loc` links go, so `skl` will not overwrite it.
//
pub fn writeFileWhereLinkGoes(io: std.Io) !void {
    try writeFile(io, "/home/skilled/project/.claude/skills/loc", "not a link\n");
    try writeFile(io, "/home/skilled/project/.cursor/skills/loc", "not a link\n");
}

//
// Makes the project's scratch directory and links `loc` in every agent directory, skills to
// `skills_target` and commands to `commands_target`.
//
fn linkScratch(io: std.Io, skills_target: []const u8, commands_target: []const u8) !void {
    try files.makeDirPath(io, "/home/skilled/project/.skilled/scratch/skills");
    try files.makeDirPath(io, "/home/skilled/project/.skilled/scratch/commands");
    try files.makeDirPath(io, skills_target);
    try files.makeDirPath(io, commands_target);
    try placeLink(io, skills_target, "/home/skilled/project/.cursor/skills/loc");
    try placeLink(io, skills_target, "/home/skilled/project/.claude/skills/loc");
    try placeLink(io, commands_target, "/home/skilled/project/.cursor/commands/loc");
    try placeLink(io, commands_target, "/home/skilled/project/.claude/commands/loc");
}

//
// A directory symlink at `link_path` naming `target`, creating the directories above it.
//
fn placeLink(io: std.Io, target: []const u8, link_path: []const u8) !void {
    try files.makeParentDir(io, link_path);
    try std.Io.Dir.cwd().symLink(io, target, link_path, .{
        .is_directory = true,
    });
}

//
// Writes one file in the simulated filesystem, creating the directories above it.
//
fn writeFile(io: std.Io, path: []const u8, contents: []const u8) !void {
    try files.makeParentDir(io, path);
    try files.writeFile(io, path, contents);
}
