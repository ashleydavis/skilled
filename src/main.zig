//
// The CLI process: argv in, exit code out.
//

const std = @import("std");

//
// Library modules: Commander, git, paths, term, failure, version.
//
const skilled = @import("skilled");

//
// `skl add`: clone, scan, append YAML, link.
//
const add_cmd = @import("cmd/add.zig");

//
// Allocator, io, paths, runners, and streams every command reads.
//
const context_mod = @import("cmd/context.zig");

//
// `skl docs`: print details and open GitHub Pages when interactive.
//
const docs_cmd = @import("cmd/docs.zig");

//
// `skl init`: create an empty skl.yaml.
//
const init_cmd = @import("cmd/init.zig");

//
// `skl install` / `skl i`: clone missing packages and link them.
//
const install_cmd = @import("cmd/install.zig");

//
// `skl list`: print packages and `ns:name` items.
//
const list_cmd = @import("cmd/list.zig");

//
// `skl remove`: unlink and drop a YAML entry.
//
const remove_cmd = @import("cmd/remove.zig");

//
// `skl update`: fast-forward store clones and repair links.
//
const update_cmd = @import("cmd/update.zig");

//
// The command line library: program tree, help, and parse.
//
const commander = skilled.commander;

//
// Clone runner the real process uses.
//
const git = skilled.git;

//
// HOME, XDG, and the rest of path resolution.
//
const paths = skilled.paths;

//
// Color and interactive detection from argv, env, and TTY.
//
const term = skilled.term;

//
// How a refused command says why: the failure `run` returns in place of an exit code.
//
const failure = skilled.failure;

//
// Values every subcommand reads, filled in from the real process here.
//
const Context = context_mod.Context;

//
// Extra text under the program's own help.
//
const HELP_EXAMPLES =
    \\
    \\Examples:
    \\  skl init
    \\  skl add owner/repo --ns demo
    \\  skl add owner/repo --ns demo --branch feature
    \\  skl update demo --local /path/to/checkout
    \\  skl update demo --branch main
    \\  skl install
    \\  skl list
    \\
;

//
// Builds the whole command line: the program, its options, and every subcommand.
//
pub fn buildProgram(ctx: *const Context) std.mem.Allocator.Error!*commander.Command {
    const program = (try commander.program(ctx.allocator))
        .style(ctx.style)
        .name("skl")
        .description("Install AI agent skill packages from git.")
        .version(skilled.version.version, "-V, --version", "output the version number")
        .addHelpText("after", HELP_EXAMPLES);
    try program.option("-g, --global", "Use the global config and global agent roots.", null);
    try program.option("--no-color", "Disable color and icons.", null);
    try program.option("-n, --non-interactive", "Do not prompt.", null);

    try program.addCommand(try init_cmd.buildCommand(ctx));
    try program.addCommand(try install_cmd.buildCommand(ctx));
    try program.addCommand(try add_cmd.buildCommand(ctx));
    try program.addCommand(try remove_cmd.buildCommand(ctx));
    try program.addCommand(try update_cmd.buildCommand(ctx));
    try program.addCommand(try list_cmd.buildCommand(ctx));
    try program.addCommand(try docs_cmd.buildCommand(ctx));
    return program;
}

//
// What `skl` exits with when it runs out of memory: 137, the code a shell and Kubernetes report
// for a process the system ended for using too much memory (128 plus signal 9), so a script or a
// CI job reads it as running out of memory.
//
pub const out_of_memory_exit_code: u8 = 137;

//
// The exit code for a run that failed with `err`, after its failure was reported with `reported`:
// `out_of_memory_exit_code` when it ran out of memory, and `reported` otherwise.
//
pub fn exitCodeOf(err: anyerror, reported: u8) u8 {
    if (err == error.OutOfMemory) {
        return out_of_memory_exit_code;
    }
    return reported;
}

//
// The entry point. It holds the wiring from the real process into the command functions.
//
pub fn main(init: std.process.Init) u8 {
    const allocator = init.arena.allocator();

    var stdout_file = std.Io.File.stdout().writer(init.io, &.{});
    var stderr_file = std.Io.File.stderr().writer(init.io, &.{});

    const stderr_is_tty = std.Io.File.stderr().isTty(init.io) catch false;
    const stderr_style = term.detectStyle(&.{}, init.environ_map, stderr_is_tty);

    const exit_code: u8 = blk: {
        const result = run(init, allocator, &stdout_file.interface, &stderr_file.interface) catch |err| {
            const why = failure.because("skl ran out of memory and stopped.", .{});
            break :blk exitCodeOf(err, reportFailure(&why, &stderr_file.interface, stderr_style));
        };
        switch (result) {
            .ok => |code| break :blk code,
            .failed => |why| break :blk reportFailure(&why, &stderr_file.interface, stderr_style),
        }
    };

    stdout_file.interface.flush() catch {};
    return exit_code;
}

//
// Prints a failure and gives the exit code to use.
//
// Red when the stream takes color, so a refusal is distinguishable from ordinary output at a
// glance; plain text when `--no-color`, `NO_COLOR`, or a redirected stream turns color off.
//
pub fn reportFailure(why: *const failure.Failure, writer: *std.Io.Writer, style: term.Style) u8 {
    if (style.color) {
        writer.print("\x1b[31m{s}\x1b[0m\n", .{why.message()}) catch {};
    } else {
        writer.print("{s}\n", .{why.message()}) catch {};
    }
    return 1;
}

//
// Builds the command line from the process and runs whatever it asked for.
//
fn run(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) std.mem.Allocator.Error!failure.Result(u8) {
    const argv = init.minimal.args.toSlice(allocator) catch |err| {
        return .{
            .failed = failure.because("Failed to read the command line: {s}.", .{@errorName(err)}),
        };
    };
    const arguments = if (argv.len > 1) argv[1..] else &[_][:0]const u8{};

    var widened: std.ArrayList([]const u8) = .empty;
    for (arguments) |argument| {
        try widened.append(allocator, argument);
    }

    const cwd = std.process.currentPathAlloc(init.io, allocator) catch |err| {
        return .{
            .failed = failure.because("Failed to read the working directory: {s}.", .{skilled.files.describeError(err)}),
        };
    };

    const home = paths.homeDir(init.environ_map) catch {
        return .{
            .failed = failure.because("HOME is not set.", .{}),
        };
    };

    const stdout_is_tty = std.Io.File.stdout().isTty(init.io) catch false;
    const stdin_is_tty = std.Io.File.stdin().isTty(init.io) catch false;
    const stderr_is_tty = std.Io.File.stderr().isTty(init.io) catch false;

    var stdin_buf: [4096]u8 = undefined;
    var stdin_file = std.Io.File.stdin().reader(init.io, &stdin_buf);

    const ctx = try allocator.create(Context);
    ctx.* = .init(allocator, init.io, init.environ_map, cwd, home, &stdin_file.interface, stdout, stderr);
    ctx.style = term.detectStyle(widened.items, init.environ_map, stdout_is_tty);
    ctx.non_interactive = term.nonInteractive(widened.items, init.environ_map, stdin_is_tty);
    ctx.stderr_is_tty = stderr_is_tty;

    const program = try buildProgram(ctx);

    return switch (try commander.parse(stdout, program, widened.items)) {
        .displayed => .{
            .ok = 0,
        },
        .ran => |code| .{
            .ok = code,
        },
        .refused => |why| .{
            .failed = why,
        },
    };
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("main.test.zig");
}
