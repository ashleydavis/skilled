//
// The values every CLI command takes from the process, so tests can inject the rest.
//
// Commands never read argv, cwd, HOME, or the environment on their own. main fills this in from
// the real process; unit tests fill it in from a TemporaryDir and a fake git runner.
//

const std = @import("std");
const skilled = @import("skilled");

//
// Clone, fetch, and HEAD go through this runner so a test never hits the network.
//
const git = skilled.git;

//
// Color and icons for list/docs output, and the switch that turns progress off.
//
const term = skilled.term;

//
// How a refused command is described to the user.
//
const Failure = skilled.failure.Failure;

//
// One spawn of a browser: argv plus the environment that spawn sees.
//
// The process runner ignores ctx. Tests pass their fake as ctx so they can record argv.
//
pub const BrowserRunFn = *const fn (
    ctx: *anyopaque,
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    argv: []const []const u8,
    fail: *Failure,
) skilled.failure.Error!void;

//
// How a URL is opened. The CLI uses `.process`; docs tests use `.custom` so nothing launches.
//
pub const BrowserRunner = union(enum) {
    //
    // Spawns SKL_BROWSER or the platform opener via std.process.run.
    //
    process,

    //
    // A callback that records argv and returns a scripted success or failure.
    //
    custom: CustomBrowser,
};

//
// The fake half of BrowserRunner: an opaque pointer and the function that uses it.
//
pub const CustomBrowser = struct {
    //
    // The fake's state, typically the recorder in src/lib/test/harness.zig.
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
// command and a `-g` command without being rebuilt. Git and the browser are runners so tests
// inject fakes; the CLI passes `.process`.
//
pub const Context = struct {
    //
    // Arena for the whole run in the CLI; a test arena in unit tests.
    //
    allocator: std.mem.Allocator,

    //
    // How every filesystem call this run makes is performed.
    //
    io: std.Io,

    //
    // The environment git and the browser inherit. Tests pass a private map, never the process.
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
    // Stdin, for `--ns` and docs prompts. A real file in the CLI; a fixed buffer in tests.
    //
    stdin: *std.Io.Reader,

    //
    // Where command output goes.
    //
    stdout: *std.Io.Writer,

    //
    // Where progress, prompts, and failure text go. Tests capture this separately from stdout.
    //
    stderr: *std.Io.Writer,

    //
    // Filled in when a command refuses. The CLI prints it; tests read `fail.text()`.
    //
    fail: *Failure,
};
