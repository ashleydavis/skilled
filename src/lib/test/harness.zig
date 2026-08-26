//
// Throwaway dirs, fake git, and captured output that command tests share.
//
// Test-only: not a command, not re-exported from lib.zig. Each test owns one Scenario. Nothing
// here is a well-known path, and the environment map is private, so two tests (or two
// `zig build test` processes) cannot see each other's files.
//

const std = @import("std");
const skilled = @import("skilled");

const context_mod = @import("../../cmd/context.zig");

//
// The run values commands take, filled in from this scenario rather than the process.
//
const Context = context_mod.Context;

//
// Config writes in tests go through the real stow-safe path.
//
const config = skilled.config;

//
// TemporaryDir and TestIo, so each scenario has its own disk and Io.
//
const files = skilled.files;

//
// The runner interface FakeGit implements.
//
const git = skilled.git;

//
// How a refused command is described; the scenario holds one Failure for the command under test.
//
const Failure = skilled.failure.Failure;

//
// One recorded git argv, so tests can assert clone happened or did not.
//
pub const GitCall = struct {
    //
    // Copied argv, owned by the scenario arena.
    //
    argv: []const []const u8,

    //
    // Copied cwd, or null when the spawn inherited the process directory (clone).
    //
    cwd: ?[]const u8,
};

//
// What a successful clone writes into dest.
//
pub const CloneLayout = enum {
    //
    // skills/hello/SKILL.md and README.md.
    //
    skills,

    //
    // commands/plan/create.md only.
    //
    commands,

    //
    // Both trees.
    //
    both,

    //
    // Dest exists as a directory with neither tree, so scan fails.
    //
    empty,
};

//
// A GitRunner that materializes packages on clone and scripts fetchUpdate/HEAD.
//
pub const FakeGit = struct {
    //
    // Where captured argv and file writes are allocated.
    //
    allocator: std.mem.Allocator,

    //
    // Used to write package files into dest on clone.
    //
    io: std.Io,

    //
    // Every argv the code under test built.
    //
    calls: std.ArrayList(GitCall) = .empty,

    //
    // Layout written on clone. Tests change this per package via clone_layout_for.
    //
    default_layout: CloneLayout = .skills,

    //
    // When dest's last segment equals this, clone writes an empty tree instead.
    //
    empty_repo: ?[]const u8 = null,

    //
    // When dest's last segment equals this, clone writes a commands tree.
    //
    commands_repo: ?[]const u8 = null,

    //
    // When dest's last segment equals this, clone writes both trees.
    //
    both_repo: ?[]const u8 = null,

    //
    // When dest's last segment equals this, clone returns a failure and does not create dest.
    //
    fail_repo: ?[]const u8 = null,

    //
    // When true, the next invoke returns FileNotFound.
    //
    missing: bool = false,

    //
    // fetchUpdate: rev-parse --abbrev-ref HEAD returns HEAD.
    //
    detached: bool = false,

    //
    // fetchUpdate: git status --porcelain is non-empty.
    //
    dirty: bool = false,

    //
    // fetchUpdate: @{upstream} fails.
    //
    no_upstream: bool = false,

    //
    // fetchUpdate: merge --ff-only fails.
    //
    diverged: bool = false,

    //
    // SHA returned by rev-parse HEAD before a successful fetch.
    //
    head: []const u8 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",

    //
    // SHA returned by rev-parse HEAD after a successful fetch.
    //
    next_head: []const u8 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",

    //
    // Set when git fetch runs, so a later HEAD reflects next_head.
    //
    fetched: bool = false,

    //
    // YAML `git show` returns for `--from`. Tests override this when they need a different file.
    //
    show_text: []const u8 =
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: acme/cmds
        \\    namespace: cmd
        \\
    ,

    //
    // Exit code `git show` returns. Non-zero is a missing ref or path.
    //
    show_exit_code: u8 = 0,

    //
    // Stderr `git show` returns when it fails.
    //
    show_stderr: []const u8 = "",

    //
    // The GitRunner clone/fetch/headSha take.
    //
    pub fn runner(self: *FakeGit) git.GitRunner {
        return git.customRunner(@ptrCast(self), runGit);
    }
};

//
// A BrowserRunner that records argv and does not spawn.
//
pub const FakeBrowser = struct {
    //
    // Where captured argv is allocated.
    //
    allocator: std.mem.Allocator,

    //
    // Argv of the last open, or empty when nothing opened.
    //
    argv: []const []const u8 = &.{},

    //
    // How many times open ran.
    //
    opens: usize = 0,

    //
    // The BrowserRunner docs takes.
    //
    pub fn runner(self: *FakeBrowser) context_mod.BrowserRunner {
        return .{ .custom = .{ .ctx = @ptrCast(self), .runFn = runBrowser } };
    }
};

//
// One test's project, HOME, fake git, and captured streams.
//
pub const Scenario = struct {
    //
    // Memory for paths, YAML, and captured bytes. Torn down with the scenario.
    //
    arena: std.heap.ArenaAllocator,

    //
    // The Io this scenario's filesystem calls go through.
    //
    test_io: files.TestIo,

    //
    // Thrown away when the test ends. Home, cwd, and store live inside it.
    //
    temporary: files.TemporaryDir,

    //
    // Private environment. HOME is set to this scenario's home directory.
    //
    environ: std.process.Environ.Map,

    //
    // Captured stdout.
    //
    stdout: std.Io.Writer.Allocating,

    //
    // Captured stderr (progress and prompts).
    //
    stderr: std.Io.Writer.Allocating,

    //
    // Bytes the next context() presents as stdin. Rebuilt into a Reader each time.
    //
    stdin_bytes: []const u8 = "",

    //
    // The Reader context() points at. Replaced each context() so seek starts at 0.
    //
    stdin_reader: std.Io.Reader = undefined,

    //
    // Failure the command under test writes into.
    //
    fail: Failure,

    //
    // Fake git for this scenario.
    //
    git: FakeGit,

    //
    // Fake browser for this scenario.
    //
    browser: FakeBrowser,

    //
    // `<temporary>/home`.
    //
    home: []const u8,

    //
    // `<temporary>/project`.
    //
    cwd: []const u8,

    //
    // Empty project and home under a fresh TemporaryDir.
    //
    pub fn create() !*Scenario {
        const scenario = try std.testing.allocator.create(Scenario);
        scenario.* = .{
            .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
            .test_io = .init(),
            .temporary = undefined,
            .environ = undefined,
            .stdout = undefined,
            .stderr = undefined,
            .fail = undefined,
            .git = undefined,
            .browser = undefined,
            .home = undefined,
            .cwd = undefined,
        };
        scenario.temporary = try files.TemporaryDir.create(scenario.test_io.io());
        const alloc = scenario.arena.allocator();
        scenario.environ = std.process.Environ.Map.init(alloc);
        scenario.home = try scenario.temporary.join(alloc, "home");
        scenario.cwd = try scenario.temporary.join(alloc, "project");
        try files.makeDirPath(scenario.test_io.io(), scenario.home);
        try files.makeDirPath(scenario.test_io.io(), scenario.cwd);
        try scenario.environ.put("HOME", scenario.home);
        const tmp = try scenario.temporary.join(alloc, "tmp");
        try files.makeDirPath(scenario.test_io.io(), tmp);
        try scenario.environ.put("TMPDIR", tmp);
        try scenario.environ.put("TMP", tmp);
        try scenario.environ.put("TEMP", tmp);
        scenario.stdout = std.Io.Writer.Allocating.init(alloc);
        scenario.stderr = std.Io.Writer.Allocating.init(alloc);
        scenario.fail = Failure.init(alloc);
        scenario.git = .{
            .allocator = alloc,
            .io = scenario.test_io.io(),
        };
        scenario.browser = .{ .allocator = alloc };
        return scenario;
    }

    //
    // Removes the project and everything allocated for it.
    //
    pub fn destroy(self: *Scenario) void {
        self.temporary.destroy();
        self.test_io.deinit();
        self.arena.deinit();
        std.testing.allocator.destroy(self);
    }

    //
    // Where this scenario's memory comes from.
    //
    pub fn allocator(self: *Scenario) std.mem.Allocator {
        return self.arena.allocator();
    }

    //
    // The Io everything this scenario does goes through.
    //
    pub fn io(self: *Scenario) std.Io {
        return self.test_io.io();
    }

    //
    // Writes a file relative to the throwaway root.
    //
    pub fn write(self: *Scenario, sub_path: []const u8, contents: []const u8) !void {
        try self.temporary.write(sub_path, contents);
    }

    //
    // Project skl.yaml, created with a stow-safe write.
    //
    pub fn writeProjectYaml(self: *Scenario, text: []const u8) !void {
        const path = try files.joinPath(self.allocator(), &.{ self.cwd, "skl.yaml" });
        const file = try config.parse(self.allocator(), text, &self.fail);
        try config.writeFile(self.io(), self.allocator(), path, file, &self.fail);
    }

    //
    // Global skl.yaml under this scenario's HOME.
    //
    pub fn writeGlobalYaml(self: *Scenario, text: []const u8) !void {
        const path = try files.joinPath(self.allocator(), &.{ self.home, ".config", "skilled", "skl.yaml" });
        const file = try config.parse(self.allocator(), text, &self.fail);
        try config.writeFile(self.io(), self.allocator(), path, file, &self.fail);
    }

    //
    // The context a command is driven with. Rebuilds stdin so each call rereads stdin_bytes.
    //
    pub fn context(self: *Scenario) Context {
        return self.contextInteractive(true);
    }

    //
    // Like context(), with non_interactive chosen by the test (false to exercise prompts).
    //
    pub fn contextInteractive(self: *Scenario, non_interactive: bool) Context {
        self.stdin_reader = std.Io.Reader.fixed(self.stdin_bytes);
        self.fail = Failure.init(self.allocator());
        return .{
            .allocator = self.allocator(),
            .io = self.io(),
            .environ = &self.environ,
            .cwd = self.cwd,
            .home = self.home,
            .style = .{ .color = false, .icons = false },
            .non_interactive = non_interactive,
            .stderr_is_tty = false,
            .git = self.git.runner(),
            .browser = self.browser.runner(),
            .stdin = &self.stdin_reader,
            .stdout = &self.stdout.writer,
            .stderr = &self.stderr.writer,
            .fail = &self.fail,
        };
    }

    //
    // What has been printed to stdout so far.
    //
    pub fn printed(self: *Scenario) []const u8 {
        return self.stdout.written();
    }

    //
    // What has been printed to stderr so far.
    //
    pub fn printedErr(self: *Scenario) []const u8 {
        return self.stderr.written();
    }

    //
    // Forgets captured stdout and stderr so one test can check several commands.
    //
    pub fn clear(self: *Scenario) void {
        self.stdout.clearRetainingCapacity();
        self.stderr.clearRetainingCapacity();
    }

    //
    // Project YAML path.
    //
    pub fn projectYaml(self: *Scenario) ![]const u8 {
        return files.joinPath(self.allocator(), &.{ self.cwd, "skl.yaml" });
    }

    //
    // Bytes of the project YAML, or error.FileNotFound.
    //
    pub fn readProjectYaml(self: *Scenario) ![]u8 {
        return files.readFile(self.io(), self.allocator(), try self.projectYaml());
    }
};

//
// Records argv, then clones a fixture, scripts fetch/HEAD, or returns FileNotFound.
//
fn runGit(
    ctx: *anyopaque,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    cwd: ?[]const u8,
    fail: *Failure,
) git.RunError!git.Result {
    _ = environ;
    const self: *FakeGit = @ptrCast(@alignCast(ctx));
    try self.calls.append(self.allocator, .{
        .argv = try copyArgv(self.allocator, argv),
        .cwd = if (cwd) |path| try self.allocator.dupe(u8, path) else null,
    });
    if (self.missing) {
        return error.FileNotFound;
    }
    if (argv.len < 2) {
        return fail.set("scripted git: argv too short", .{});
    }
    if (std.mem.eql(u8, argv[1], "clone")) {
        return cloneReply(self, io, allocator, argv, fail);
    }
    if (std.mem.eql(u8, argv[1], "rev-parse")) {
        return revParseReply(self, allocator, argv, fail);
    }
    if (std.mem.eql(u8, argv[1], "status")) {
        return statusReply(self, allocator);
    }
    if (std.mem.eql(u8, argv[1], "fetch")) {
        self.fetched = true;
        return ok(allocator);
    }
    if (std.mem.eql(u8, argv[1], "merge")) {
        if (self.diverged) {
            return .{
                .stdout = try allocator.dupe(u8, ""),
                .stderr = try allocator.dupe(u8, "fatal: Not possible to fast-forward"),
                .exit_code = 1,
            };
        }
        return ok(allocator);
    }
    if (std.mem.eql(u8, argv[1], "show")) {
        return showReply(self, allocator);
    }
    return fail.set("scripted git: unexpected {s}", .{argv[1]});
}

//
// YAML bytes for `--from`, or a non-zero exit when the scripted file is missing.
//
fn showReply(self: *FakeGit, allocator: std.mem.Allocator) git.RunError!git.Result {
    return .{
        .stdout = try allocator.dupe(u8, self.show_text),
        .stderr = try allocator.dupe(u8, self.show_stderr),
        .exit_code = self.show_exit_code,
    };
}

//
// Creates dest according to layout, or fails without creating it.
//
fn cloneReply(
    self: *FakeGit,
    io: std.Io,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    fail: *Failure,
) git.RunError!git.Result {
    if (argv.len < 5) {
        return fail.set("scripted git clone: missing dest", .{});
    }
    const dest = argv[argv.len - 1];
    const repo = lastSegment(dest);
    if (nameIs(self.fail_repo, repo)) {
        return fail.set("scripted git clone failed for {s}", .{repo});
    }
    const layout = layoutFor(self, repo);
    materialize(io, allocator, dest, layout) catch |err| {
        return fail.set("scripted git clone could not write {s}: {s}", .{ dest, @errorName(err) });
    };
    return ok(allocator);
}

//
// HEAD, branch name, or upstream, depending on argv.
//
fn revParseReply(
    self: *FakeGit,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    fail: *Failure,
) git.RunError!git.Result {
    if (argvHas(argv, "HEAD") and !argvHas(argv, "--abbrev-ref")) {
        const sha = if (self.fetched) self.next_head else self.head;
        return .{
            .stdout = try allocator.dupe(u8, sha),
            .stderr = try allocator.dupe(u8, ""),
            .exit_code = 0,
        };
    }
    if (argvHas(argv, "--abbrev-ref") and argvHas(argv, "HEAD")) {
        const name: []const u8 = if (self.detached) "HEAD" else "main";
        return .{
            .stdout = try allocator.dupe(u8, name),
            .stderr = try allocator.dupe(u8, ""),
            .exit_code = 0,
        };
    }
    if (argvHas(argv, "@{upstream}")) {
        if (self.no_upstream) {
            return .{
                .stdout = try allocator.dupe(u8, ""),
                .stderr = try allocator.dupe(u8, "fatal: no upstream"),
                .exit_code = 1,
            };
        }
        return .{
            .stdout = try allocator.dupe(u8, "origin/main"),
            .stderr = try allocator.dupe(u8, ""),
            .exit_code = 0,
        };
    }
    return fail.set("scripted git rev-parse: unexpected argv", .{});
}

//
// Porcelain status: dirty when the flag is set.
//
fn statusReply(self: *FakeGit, allocator: std.mem.Allocator) git.RunError!git.Result {
    const text: []const u8 = if (self.dirty) " M README.md\n" else "";
    return .{
        .stdout = try allocator.dupe(u8, text),
        .stderr = try allocator.dupe(u8, ""),
        .exit_code = 0,
    };
}

//
// Layout for this dest's repo name.
//
fn layoutFor(self: *const FakeGit, repo: []const u8) CloneLayout {
    if (nameIs(self.empty_repo, repo)) {
        return .empty;
    }
    if (nameIs(self.commands_repo, repo)) {
        return .commands;
    }
    if (nameIs(self.both_repo, repo)) {
        return .both;
    }
    return self.default_layout;
}

//
// Writes the fixture files for a layout into dest.
//
fn materialize(io: std.Io, allocator: std.mem.Allocator, dest: []const u8, layout: CloneLayout) !void {
    files.makeDirPath(io, dest) catch {};
    switch (layout) {
        .empty => {},
        .skills => {
            try writePkgFile(io, allocator, dest, "README.md", "A pack of demo skills.\n");
            try writePkgFile(io, allocator, dest, "skills/hello/SKILL.md",
                \\---
                \\description: Says hello
                \\---
                \\
                \\# Hello
                \\
            );
        },
        .commands => {
            try writePkgFile(io, allocator, dest, "README.md", "A pack of demo commands.\n");
            try writePkgFile(io, allocator, dest, "commands/plan/create.md",
                \\---
                \\description: Create a plan
                \\---
                \\
                \\Write a plan.
                \\
            );
        },
        .both => {
            try writePkgFile(io, allocator, dest, "README.md", "Skills and commands together.\n");
            try writePkgFile(io, allocator, dest, "skills/hello/SKILL.md",
                \\---
                \\description: Says hello
                \\---
                \\
            );
            try writePkgFile(io, allocator, dest, "commands/plan/create.md",
                \\---
                \\description: Create a plan
                \\---
                \\
            );
        },
    }
}

//
// Writes one file under dest, creating parent directories.
//
fn writePkgFile(io: std.Io, allocator: std.mem.Allocator, dest: []const u8, rel: []const u8, contents: []const u8) !void {
    const path = try files.joinPath(allocator, &.{ dest, rel });
    try files.makeParentDir(io, path);
    try files.writeFile(io, path, contents);
}

//
// Records argv so docs tests can assert the repo URL, not a Pages URL.
//
fn runBrowser(
    ctx: *anyopaque,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    fail: *Failure,
) skilled.failure.Error!void {
    _ = io;
    _ = allocator;
    _ = environ;
    _ = fail;
    const self: *FakeBrowser = @ptrCast(@alignCast(ctx));
    self.argv = try copyArgv(self.allocator, argv);
    self.opens += 1;
}

//
// Empty successful git result.
//
fn ok(allocator: std.mem.Allocator) git.RunError!git.Result {
    return .{
        .stdout = try allocator.dupe(u8, ""),
        .stderr = try allocator.dupe(u8, ""),
        .exit_code = 0,
    };
}

//
// Copies argv so later asserts still see it after the stack array is gone.
//
fn copyArgv(allocator: std.mem.Allocator, argv: []const []const u8) ![]const []const u8 {
    const copy = try allocator.alloc([]const u8, argv.len);
    for (argv, 0..) |arg, i| {
        copy[i] = try allocator.dupe(u8, arg);
    }
    return copy;
}

//
// Last path segment of dest, which is the repo directory name.
//
fn lastSegment(path: []const u8) []const u8 {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            return path[i + 1 ..];
        }
    }
    return path;
}

//
// True when needle is set and equals name.
//
fn nameIs(needle: ?[]const u8, name: []const u8) bool {
    const want = needle orelse return false;
    return std.mem.eql(u8, want, name);
}

//
// True when one of argv is exactly token.
//
fn argvHas(argv: []const []const u8, token: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, token)) {
            return true;
        }
    }
    return false;
}
