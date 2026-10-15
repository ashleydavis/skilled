//
// The values every CLI command takes from the process.
//
// Commands never read argv, cwd, HOME, or the environment on their own. main fills this in from
// the real process.
//

const std = @import("std");
const skilled = @import("skilled");

//
// Clone, fetch, and HEAD go through this runner.
//
const git = skilled.git;

//
// Color and icons for list/docs output, and the switch that turns progress off.
//
const term = skilled.term;

//
// One spawn of a browser: argv plus the environment that spawn sees, returning the failure that
// says why the URL could not be opened.
//
// The process runner ignores ctx.
//
pub const BrowserRunFn = *const fn (
    ctx: *anyopaque,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
) std.mem.Allocator.Error!skilled.failure.Result(void);

//
// How a URL is opened. The CLI uses `.process`.
//
pub const BrowserRunner = union(enum) {
    //
    // Spawns SKL_BROWSER or the platform opener via std.process.run.
    //
    process,

    //
    // A callback that records argv and returns a scripted success or failure.
    //
    function: BrowserFunction,
};

//
// The function half of BrowserRunner: an opaque pointer and the function that uses it.
//
pub const BrowserFunction = struct {
    //
    // The state the function is handed on every call.
    //
    ctx: *anyopaque,

    //
    // One browser invocation.
    //
    runFn: BrowserRunFn,
};

//
// Everything a command needs from outside itself.
//
// `global` is not here: it is a flag on the invocation, so the same context can run a project
// command and a `-g` command without being rebuilt. Git and the browser are runners; the CLI
// passes `.process`.
//
pub const Context = struct {
    //
    // Arena for the whole run in the CLI.
    //
    allocator: std.mem.Allocator,

    //
    // How every filesystem call this run makes is performed.
    //
    io: std.Io,

    //
    // The environment git and the browser inherit.
    //
    environ: *const std.process.Environ.Map,

    //
    // Directory the tool was invoked from. Project YAML and project agent roots hang off this.
    //
    cwd: []const u8,

    //
    // Resolved HOME (or USERPROFILE). Store, global config, and global agent roots hang off this.
    //
    home: []const u8,

    //
    // Whether color and icons should be written to stdout.
    //
    style: term.Style,

    //
    // True when prompts must not run.
    //
    non_interactive: bool,

    //
    // Whether stderr is a TTY. Progress is a no-op when this is false.
    //
    stderr_is_tty: bool,

    //
    // How git is started.
    //
    git: git.GitRunner,

    //
    // How the Pages URL is opened by interactive `docs`.
    //
    browser: BrowserRunner,

    //
    // Stdin, for `--ns` and docs prompts. A real file in the CLI.
    //
    stdin: *std.Io.Reader,

    //
    // Where command output goes.
    //
    stdout: *std.Io.Writer,

    //
    // Where progress, prompts, and failure text go.
    //
    stderr: *std.Io.Writer,

    //
    // A context from the values every caller has to supply.
    //
    // The rest start as a run nobody is watching: plain output, no prompts, stderr not a TTY, and
    // git and the browser started as real processes. A caller that differs sets those fields after.
    //
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: *const std.process.Environ.Map,
        cwd: []const u8,
        home: []const u8,
        stdin: *std.Io.Reader,
        stdout: *std.Io.Writer,
        stderr: *std.Io.Writer,
    ) Context {
        return .{
            .allocator = allocator,
            .io = io,
            .environ = environ,
            .cwd = cwd,
            .home = home,
            .style = .{
                .color = false,
                .icons = false,
            },
            .non_interactive = true,
            .stderr_is_tty = false,
            .git = git.processRunner(),
            .browser = .process,
            .stdin = stdin,
            .stdout = stdout,
            .stderr = stderr,
        };
    }
};

test {
    _ = @import("context.test.zig");
}
