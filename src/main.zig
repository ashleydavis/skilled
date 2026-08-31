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
// How a refused command is described.
//
const Failure = skilled.failure.Failure;

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
pub fn buildProgram(ctx: *const Context) *commander.Command {
    const program = commander.program(ctx.allocator)
        .name("skl")
        .description("Install AI agent skill packages from git.")
        .version(skilled.version.version, "-V, --version", "output the version number")
        .option("-g, --global", "Use the global config and global agent roots.", null)
        .option("--no-color", "Disable color and icons.", null)
        .option("-n, --non-interactive", "Do not prompt.", null)
        .addHelpText("after", HELP_EXAMPLES);

    program.addCommand(init_cmd.buildCommand(ctx));
    program.addCommand(install_cmd.buildCommand(ctx));
    program.addCommand(add_cmd.buildCommand(ctx));
    program.addCommand(remove_cmd.buildCommand(ctx));
    program.addCommand(update_cmd.buildCommand(ctx));
    program.addCommand(list_cmd.buildCommand(ctx));
    program.addCommand(docs_cmd.buildCommand(ctx));
    return program;
}

//
// The entry point. It holds the wiring from the real process into the command functions.
//
pub fn main(init: std.process.Init) u8 {
    const allocator = init.arena.allocator();

    var stdout_file = std.Io.File.stdout().writer(init.io, &.{});
    var stderr_file = std.Io.File.stderr().writer(init.io, &.{});
    var fail = Failure.init(allocator);

    const exit_code = run(init, allocator, &stdout_file.interface, &stderr_file.interface, &fail) catch |err| blk: {
        if (err == error.OutOfMemory and fail.message == null) {
            _ = fail.set("skl ran out of memory.", .{}) catch {};
        }
        break :blk reportFailure(&fail, &stderr_file.interface);
    };

    stdout_file.interface.flush() catch {};
    return exit_code;
}

//
// Prints a failure and gives the exit code to use.
//
// Public so the tests in main.test.zig can reach it with a buffer writer.
//
pub fn reportFailure(fail: *Failure, writer: *std.Io.Writer) u8 {
    writer.print("{s}\n", .{fail.text()}) catch {};
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
    fail: *Failure,
) skilled.failure.Error!u8 {
    const argv = init.minimal.args.toSlice(allocator) catch |err| {
        return fail.set("Failed to read the command line: {s}", .{@errorName(err)});
    };
    const arguments = if (argv.len > 1) argv[1..] else &[_][:0]const u8{};

    var widened: std.ArrayList([]const u8) = .empty;
    for (arguments) |argument| {
        try widened.append(allocator, argument);
    }

    const cwd = std.process.currentPathAlloc(init.io, allocator) catch |err| {
        return fail.set("Failed to read the working directory: {s}", .{skilled.files.describeError(err)});
    };

    const home = paths.homeDir(init.environ_map) catch {
        return fail.set("HOME is not set", .{});
    };

    const stdout_is_tty = std.Io.File.stdout().isTty(init.io) catch false;
    const stdin_is_tty = std.Io.File.stdin().isTty(init.io) catch false;
    const stderr_is_tty = std.Io.File.stderr().isTty(init.io) catch false;

    var stdin_buf: [4096]u8 = undefined;
    var stdin_file = std.Io.File.stdin().reader(init.io, &stdin_buf);

    const ctx = try allocator.create(Context);
    ctx.* = .{
        .allocator = allocator,
        .io = init.io,
        .environ = init.environ_map,
        .cwd = cwd,
        .home = home,
        .style = term.detectStyle(widened.items, init.environ_map, stdout_is_tty),
        .non_interactive = term.nonInteractive(widened.items, init.environ_map, stdin_is_tty),
        .stderr_is_tty = stderr_is_tty,
        .git = git.processRunner(),
        .browser = .process,
        .stdin = &stdin_file.interface,
        .stdout = stdout,
        .stderr = stderr,
        .fail = fail,
    };

    const program = buildProgram(ctx);

    var runner = commander.Program{ .out = stdout };
    commander.parse(&runner, program, widened.items) catch |err| switch (err) {
        error.Displayed => return 0,
        error.Refused => {
            if (runner.message) |message| {
                _ = fail.set("{s}", .{message}) catch {};
            }
            return error.Failed;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };

    return runner.exit_code;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("main.test.zig");
}
