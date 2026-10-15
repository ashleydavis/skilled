//
// The test input factories for Commander's own types, so Faultline can call the functions that take them.
//

const std = @import("std");

//
// The file that declares the types these factories return.
//
const commander = @import("commander.zig");

//
// The help style type, imported by its own path as `commander.zig` imports it.
//
const term = @import("term.zig");

//
// How an action says why it refused, imported by its own path as `commander.zig` imports it.
//
const failure = @import("failure.zig");

//
// `skl add --ns demo` as the action receives it after a parse: one option given.
//
pub fn invocation(allocator: std.mem.Allocator) !*const commander.Invocation {
    const made = try allocator.create(commander.Invocation);
    made.* = .{
        .context = made,
        .args = &.{},
        .values = .empty,
    };
    try made.values.put(allocator, "ns", "demo");
    return made;
}

//
// The context every `skl` command's action is registered with. Commander only hands it back, so
// any pointer does.
//
pub fn actionContext(allocator: std.mem.Allocator) !*const anyopaque {
    return try allocator.create(u8);
}

//
// An action for a `skl` command, such as `skl list`, that does nothing and succeeds, for
// registering on a command.
//
pub fn doNothingAction() commander.ActionFn {
    return &doNothing;
}

//
// What `doNothingAction` registers.
//
fn doNothing(_: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    return .{
        .ok = 0,
    };
}

//
// An action for a `skl` command, such as `skl add` when the repo cannot be cloned, that fails.
//
pub fn failingAction() commander.ActionFn {
    return &fail;
}

//
// What `failingAction` registers.
//
fn fail(_: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    return .{
        .failed = failure.because("Cannot clone acme/skills.", .{}),
    };
}

//
// What a `skl` command's action returns when it runs out of memory.
//
fn runOutOfMemory(_: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    return error.OutOfMemory;
}

//
// The command tree `skl` parses its command line against, laid out as `main.buildProgram` lays it
// out, with actions that do nothing.
//
pub fn sklProgram(allocator: std.mem.Allocator) !*commander.Command {
    return buildSkl(allocator, .{
        .color = false,
        .icons = false,
    });
}

//
// `skl`'s command tree as `skl --help` paints it at a terminal that takes color.
//
pub fn sklProgramInColor(allocator: std.mem.Allocator) !*commander.Command {
    return buildSkl(allocator, .{
        .color = true,
        .icons = true,
    });
}

//
// A command tree with no version and no help text, as a program built without `.version` has, so
// `version` is read as an unknown command.
//
pub fn programWithoutVersion(allocator: std.mem.Allocator) !*commander.Command {
    const context = try allocator.create(u8);
    const program = (try commander.program(allocator)).name("skl");
    try program.addCommand((try commander.Command.init(allocator, "list")).action(context, &doNothing));
    return program;
}

//
// Where `skl` writes help and the version: an in-memory buffer, created with the allocator Faultline
// passes in.
//
pub fn sklOutput(allocator: std.mem.Allocator) !*std.Io.Writer {
    const out = try allocator.create(std.Io.Writer.Allocating);
    out.* = .init(allocator);
    return &out.writer;
}

//
// `skl add acme/skills --ns demo`.
//
pub fn addArguments() []const []const u8 {
    return &.{ "add", "acme/skills", "--ns", "demo" };
}

//
// `skl --help`.
//
pub fn helpArguments() []const []const u8 {
    return &.{"--help"};
}

//
// `skl add acme/skills --ns=demo --branch dev`.
//
pub fn addWithJoinedValueArguments() []const []const u8 {
    return &.{ "add", "acme/skills", "--ns=demo", "--branch", "dev" };
}

//
// `skl add acme/skills --ns`, which is refused because `--ns` has no value.
//
pub fn missingValueArguments() []const []const u8 {
    return &.{ "add", "acme/skills", "--ns" };
}

//
// `skl -gn list`, two short options run together before the command.
//
pub fn joinedShortOptionsArguments() []const []const u8 {
    return &.{ "-gn", "list" };
}

//
// `skl list -g --no-color`, the program's own options after the command.
//
pub fn optionsAfterCommandArguments() []const []const u8 {
    return &.{ "list", "-g", "--no-color" };
}

//
// `skl i`, `install` by its alias.
//
pub fn aliasArguments() []const []const u8 {
    return &.{"i"};
}

//
// `skl remove -- -odd`, a query that starts with a dash after `--`.
//
pub fn doubleDashArguments() []const []const u8 {
    return &.{ "remove", "--", "-odd" };
}

//
// `skl remove`, which is refused because `<query>` is missing.
//
pub fn missingArgumentArguments() []const []const u8 {
    return &.{"remove"};
}

//
// `skl remove demo extra`, which is refused because there is one argument too many.
//
pub fn extraArgumentArguments() []const []const u8 {
    return &.{ "remove", "demo", "extra" };
}

//
// `skl list --bogus`, which is refused because `--bogus` is not an option.
//
pub fn unknownOptionArguments() []const []const u8 {
    return &.{ "list", "--bogus" };
}

//
// `skl nope`, which is refused because there is no such command.
//
pub fn unknownCommandArguments() []const []const u8 {
    return &.{"nope"};
}

//
// `skl add -h`.
//
pub fn commandHelpArguments() []const []const u8 {
    return &.{ "add", "-h" };
}

//
// `skl --version`.
//
pub fn versionArguments() []const []const u8 {
    return &.{"--version"};
}

//
// `skl add -V`, the version flag after a command.
//
pub fn versionAfterCommandArguments() []const []const u8 {
    return &.{ "add", "-V" };
}

//
// `skl help add`, the help of one command asked for by name.
//
pub fn helpCommandArguments() []const []const u8 {
    return &.{ "help", "add" };
}

//
// `skl help nope`, which is refused because there is no such command.
//
pub fn helpUnknownCommandArguments() []const []const u8 {
    return &.{ "help", "nope" };
}

//
// `skl help`, the program's help asked for by name.
//
pub fn helpWordArguments() []const []const u8 {
    return &.{"help"};
}

//
// `skl version`, the version asked for by name.
//
pub fn versionWordArguments() []const []const u8 {
    return &.{"version"};
}

//
// `skl store version`, the version asked for by name inside a group of commands.
//
pub fn groupVersionWordArguments() []const []const u8 {
    return &.{ "store", "version" };
}

//
// `skl`, with no arguments, which prints the help.
//
pub fn noArguments() []const []const u8 {
    return &.{};
}

//
// `skl`'s command tree painted with `help_style`.
//
fn buildSkl(allocator: std.mem.Allocator, help_style: term.Style) !*commander.Command {
    const context = try allocator.create(u8);
    const program = (try commander.program(allocator))
        .style(help_style)
        .name("skl")
        .description("Install AI agent skill packages from git.")
        .version("1.0.0", "-V, --version", "output the version number")
        .addHelpText("after", "\nExamples:\n  skl init\n");
    try program.option("-g, --global", "Use the global config and global agent roots.", null);
    try program.option("--no-color", "Disable color and icons.", null);
    try program.option("-n, --non-interactive", "Do not prompt.", null);
    try program.option("--quiet", "", null);

    const add = (try commander.Command.init(allocator, "add"))
        .description("Clone a package, append YAML, and link it. This description is long enough that the help has to wrap it onto a second line.")
        .argument("[repo]", "The package to add.")
        .action(context, &doNothing);
    try add.option("--ns <namespace>", "The namespace to install under.", null);
    try add.option("--branch <name>", "Clone this branch instead of the default.", "main");
    try program.addCommand(add);

    const install = (try commander.Command.init(allocator, "install"))
        .description("Clone and link every package in skl.yaml.")
        .action(context, &doNothing);
    try install.alias("i");
    try program.addCommand(install);

    try program.addCommand((try commander.Command.init(allocator, "remove"))
        .description("Unlink a package and drop its YAML entry.")
        .argument("<query>", "Repo string, owner/repo, name, or namespace.")
        .action(context, &fail));

    const store = (try commander.Command.init(allocator, "store"))
        .description("Look after the store.");
    try store.addCommand((try commander.Command.init(allocator, "show")).action(context, &doNothing));
    try program.addCommand(store);

    try program.addCommand((try commander.Command.init(allocator, "list"))
        .description("Print each namespace with its skills and commands.")
        .argument("[names...]", "The namespaces to print.")
        .action(context, &runOutOfMemory));
    return program;
}
