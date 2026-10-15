//
// Tests for commander.zig.
//

const std = @import("std");
const commander = @import("commander.zig");
const failure = @import("failure.zig");
const testing = std.testing;

//
// What the test actions record, so a test can see what reached them.
//
const Recorder = struct {
    ran: bool = false,
    args: []const []const u8 = &.{},
    config: ?[]const u8 = null,
    output: ?[]const u8 = null,
    fail: bool = false,
};

//
// A test action: records what it was given, the way a real one reads its options.
//
fn recordAction(invocation: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    const recorder: *Recorder = @constCast(@ptrCast(@alignCast(invocation.context)));
    recorder.ran = true;
    recorder.args = invocation.args;
    recorder.config = invocation.option("config");
    recorder.output = invocation.option("output");
    if (recorder.fail) {
        return .{
            .failed = failure.because("The action failed.", .{}),
        };
    }
    return .{
        .ok = 0,
    };
}

//
// Builds a program shaped like the tool's own, for the tests below.
//
fn buildTestProgram(allocator: std.mem.Allocator, recorder: *Recorder) !*commander.Command {
    const root = (try commander.Command.init(allocator, "tool"))
        .description("Reports which files have changed.")
        .helpOption("--help", "Print this text.")
        .version("dev", "-v, --version", "Print the version.")
        .enablePositionalOptions();

    const summary = (try commander.Command.init(allocator, "summary"))
        .description("Show the changed files grouped under the targets they fall under.")
        .action(recorder, recordAction);
    try summary.option("--config <path>", "The config file to read.", null);
    try summary.option("--output <format>", "How to render the result: text, json or yaml.", "text");
    try root.addCommand(summary);

    const baseline = (try commander.Command.init(allocator, "baseline"))
        .description("Manage the recorded baseline.");
    const capture = (try baseline.command("capture"))
        .description("Record what the named targets watch as their baseline.")
        .argument("[target names...]", "The targets to capture.")
        .action(recorder, recordAction);
    try capture.alias("update");
    try capture.alias("set");
    try capture.option("--config <path>", "The config file to read.", null);
    try root.addCommand(baseline);

    const targets = (try commander.Command.init(allocator, "targets"))
        .description("Print the affected target names.")
        .action(recorder, recordAction)
        .enablePositionalOptions();
    try targets.option("--output <format>", "How to render the result.", "text");
    const list = (try targets.command("list"))
        .description("Print every target that can run on this platform.")
        .action(recorder, recordAction);
    try list.option("--output <format>", "How to render the result.", "text");
    try root.addCommand(targets);

    return root;
}

//
// Runs a command line against that program and hands back what happened.
//
fn runLine(allocator: std.mem.Allocator, recorder: *Recorder, argv: []const []const u8, captured: *std.Io.Writer.Allocating) !commander.Outcome {
    const root = try buildTestProgram(allocator, recorder);
    return commander.parse(&captured.writer, root, argv);
}

test "Option.name strips the dashes and the placeholder" {
    try testing.expectEqualStrings("config", (commander.Option{
        .flags = "--config <path>",
        .description = "",
        .default_value = null,
    }).name());
    try testing.expectEqualStrings("output", (commander.Option{
        .flags = "--output <format>",
        .description = "",
        .default_value = null,
    }).name());
    try testing.expectEqualStrings("force", (commander.Option{
        .flags = "--force",
        .description = "",
        .default_value = null,
    }).name());
    try testing.expectEqualStrings("global", (commander.Option{
        .flags = "-g, --global",
        .description = "",
        .default_value = null,
    }).name());
    try testing.expectEqualStrings("no-color", (commander.Option{
        .flags = "--no-color",
        .description = "",
        .default_value = null,
    }).name());
}

test "Option.takesValue is true only when the flags name a placeholder" {
    try testing.expect((commander.Option{
        .flags = "--ns <namespace>",
        .description = "",
        .default_value = null,
    }).takesValue());
    try testing.expect((commander.Option{
        .flags = "--from <spec>",
        .description = "",
        .default_value = null,
    }).takesValue());
    try testing.expect(!(commander.Option{
        .flags = "-g, --global",
        .description = "",
        .default_value = null,
    }).takesValue());
    try testing.expect(!(commander.Option{
        .flags = "--open",
        .description = "",
        .default_value = null,
    }).takesValue());
    try testing.expect(!(commander.Option{
        .flags = "--no-color",
        .description = "",
        .default_value = null,
    }).takesValue());
}

test "isOption tells an option from a value" {
    try testing.expect(commander.isOption("--config"));
    try testing.expect(commander.isOption("-v"));
    try testing.expect(!commander.isOption("-"));
    try testing.expect(!commander.isOption("summary"));
    try testing.expect(!commander.isOption(""));
}

test "isVariadic reads the ellipsis in an argument spec" {
    try testing.expect(commander.isVariadic("[target names...]"));
    try testing.expect(!commander.isVariadic("[name]"));
    try testing.expect(!commander.isVariadic("<name>"));
}

test "namedBy matches any spelling in a flag list" {
    try testing.expect(commander.namedBy("-v, --version", "-v"));
    try testing.expect(commander.namedBy("-v, --version", "--version"));
    try testing.expect(commander.namedBy("--help", "--help"));
    try testing.expect(!commander.namedBy("--help", "-h"));
}

test "matches accepts a command's name and every alias" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const command = try commander.Command.init(arena.allocator(), "capture");
    try command.alias("update");
    try command.alias("set");

    try testing.expect(command.matches("capture"));
    try testing.expect(command.matches("update"));
    try testing.expect(command.matches("set"));
    try testing.expect(!command.matches("reset"));
}

test "findOption finds an option by any of its spellings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const command = try commander.Command.init(arena.allocator(), "summary");
    try command.option("--config <path>", "The config file.", null);
    try command.option("-g, --global", "Use the global config.", null);

    try testing.expect(command.findOption("--config") != null);
    try testing.expect(command.findOption("-g") != null);
    try testing.expect(command.findOption("--global") != null);
    try testing.expect(command.findOption("--nope") == null);
}

test "command adds a subcommand and returns the child to chain onto" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const parent = try commander.Command.init(arena.allocator(), "baseline");
    const child = try parent.command("capture");

    try testing.expectEqual(@as(usize, 1), parent.subcommands.items.len);
    try testing.expectEqualStrings("capture", child.command_name);
    try testing.expect(parent.findSubcommand("capture") != null);
}

test "an action runs and reads the options it was given" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runLine(allocator, &recorder, &.{ "summary", "--config", "custom.yaml" }, &captured);

    try testing.expect(recorder.ran);
    try testing.expectEqualStrings("custom.yaml", recorder.config.?);
    try testing.expectEqual(@as(u8, 0), outcome.ran);
}

test "an option with a default arrives even when the command line is silent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runLine(allocator, &recorder, &.{"summary"}, &captured);

    try testing.expectEqualStrings("text", recorder.output.?);
    try testing.expect(recorder.config == null);
}

test "an option reaches the subcommand it follows, not the parent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //
    // The regression the whole positional-options rule exists for. Without it "--output" after
    // "list" resolves to the parent's copy, where the subcommand never sees it, and the request for
    // json quietly returns text.
    //
    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runLine(allocator, &recorder, &.{ "targets", "list", "--output", "json" }, &captured);

    try testing.expect(recorder.ran);
    try testing.expectEqualStrings("json", recorder.output.?);
}

test "a subcommand alias reaches the same action" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for ([_][]const u8{ "capture", "update", "set" }) |word| {
        var recorder = Recorder{};
        var captured = std.Io.Writer.Allocating.init(allocator);
        _ = try runLine(allocator, &recorder, &.{ "baseline", word, "unit" }, &captured);

        try testing.expect(recorder.ran);
        try testing.expectEqualStrings("unit", recorder.args[0]);
    }
}

test "a variadic argument collects every name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runLine(allocator, &recorder, &.{ "baseline", "capture", "unit", "documentation" }, &captured);

    try testing.expectEqual(@as(usize, 2), recorder.args.len);
    try testing.expectEqualStrings("documentation", recorder.args[1]);
}

test "arguments and options can be given together" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runLine(allocator, &recorder, &.{ "baseline", "capture", "unit", "--config", "c.yaml" }, &captured);

    try testing.expectEqualStrings("unit", recorder.args[0]);
    try testing.expectEqualStrings("c.yaml", recorder.config.?);
}

test "-- lets an argument that starts with a dash through" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runLine(allocator, &recorder, &.{ "baseline", "capture", "--", "--odd-name" }, &captured);

    try testing.expectEqualStrings("--odd-name", recorder.args[0]);
}

test "an unknown option is refused in commander's words" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runLine(allocator, &recorder, &.{"--nosuchoption"}, &captured);

    try testing.expectEqualStrings("Unknown option '--nosuchoption'.", outcome.refused.message());
    try testing.expect(!recorder.ran);
}

test "an option with no value is refused, quoting the flags" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runLine(allocator, &recorder, &.{ "summary", "--config" }, &captured);

    try testing.expectEqualStrings("Option '--config <path>' is missing its argument.", outcome.refused.message());
}

test "an unknown command is refused and named" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runLine(allocator, &recorder, &.{"badcommand"}, &captured);

    try testing.expectEqualStrings("Unknown command 'badcommand'.", outcome.refused.message());
}

test "an argument a command does not take is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runLine(allocator, &recorder, &.{ "summary", "extra" }, &captured);

    try testing.expect(std.mem.startsWith(u8, outcome.refused.message(), "Too many arguments"));
}

test "an option a subcommand does not declare is refused rather than ignored" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runLine(allocator, &recorder, &.{ "baseline", "capture", "--output", "json" }, &captured);

    try testing.expectEqualStrings("Unknown option '--output'.", outcome.refused.message());
}

test "--help prints the help and does not run anything" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runLine(allocator, &recorder, &.{"--help"}, &captured);

    try testing.expect(std.mem.startsWith(u8, captured.written(), "Usage: tool"));
    try testing.expect(!recorder.ran);
}

test "--help after a command explains that command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runLine(allocator, &recorder, &.{ "summary", "--help" }, &captured);

    try testing.expect(std.mem.startsWith(u8, captured.written(), "Usage: summary"));
    try testing.expect(!recorder.ran);
}

test "the program's help option can be respelled, and the default one then stops working" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //
    // The program declares "--help" only, so "-h" is not a flag it knows.
    //
    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runLine(allocator, &recorder, &.{"-h"}, &captured);

    try testing.expectEqualStrings("Unknown option '-h'.", outcome.refused.message());
}

test "--version and -v print the version" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for ([_][]const u8{ "--version", "-v" }) |flag| {
        var recorder = Recorder{};
        var captured = std.Io.Writer.Allocating.init(allocator);
        _ = try runLine(allocator, &recorder, &.{flag}, &captured);

        try testing.expectEqualStrings("dev\n", captured.written());
        try testing.expect(!recorder.ran);
    }
}

test "a command with subcommands and no action of its own prints its help" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runLine(allocator, &recorder, &.{"baseline"}, &captured);

    try testing.expect(std.mem.startsWith(u8, captured.written(), "Usage: baseline"));
    try testing.expect(!recorder.ran);
}

test "an action that fails makes the parse a refusal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{
        .fail = true,
    };
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runLine(allocator, &recorder, &.{"summary"}, &captured);

    try testing.expect(recorder.ran);
    try testing.expectEqualStrings("The action failed.", outcome.refused.message());
}

test "renderHelp lays the program out in commander's shape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = Recorder{};
    const root = try buildTestProgram(allocator, &recorder);
    const help = try commander.renderHelp(allocator, root);

    try testing.expect(std.mem.startsWith(u8, help, "Usage: tool [options] [command]\n"));
    try testing.expect(std.mem.indexOf(u8, help, "\nOptions:\n") != null);
    try testing.expect(std.mem.indexOf(u8, help, "  -v, --version      Print the version.") != null);
    try testing.expect(std.mem.indexOf(u8, help, "  --help             Print this text.") != null);
    try testing.expect(std.mem.indexOf(u8, help, "\nCommands:\n") != null);
    try testing.expect(std.mem.indexOf(u8, help, "  summary [options]") != null);
    try testing.expect(std.mem.indexOf(u8, help, "  help [command]     Display help for command.") != null);
}

test "renderHelp names a subcommand's aliases and what it accepts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const baseline = try commander.Command.init(allocator, "baseline");
    const capture = (try baseline.command("capture"))
        .description("Record the baseline.")
        .argument("[target names...]", "The targets.");
    try capture.alias("update");
    try capture.alias("set");
    try capture.option("--config <path>", "The config file.", null);

    const help = try commander.renderHelp(allocator, baseline);
    try testing.expect(std.mem.indexOf(u8, help, "capture|update|set [options] [target names...]") != null);
}

test "renderHelp shows an option's default the way commander does" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //
    // A short description, so the default is not pushed onto the next line by the wrapping. That
    // the long form wraps is checked separately; this is about the default being shown at all.
    //
    const command = try commander.Command.init(allocator, "summary");
    try command.option("--output <format>", "How to render.", "text");

    const help = try commander.renderHelp(allocator, command);
    try testing.expect(std.mem.indexOf(u8, help, "How to render. (default: \"text\")") != null);
}

test "renderHelp puts the extra text after everything else" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const command = try commander.Command.init(allocator, "capture");
    _ = command.description("Record the baseline.").addHelpText("after", "\nCapture one target only after it has passed.");

    const help = try commander.renderHelp(allocator, command);
    try testing.expect(std.mem.endsWith(u8, help, "Capture one target only after it has passed.\n"));
}

test "renderHelp wraps a long description rather than running past the width" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const command = try commander.Command.init(allocator, "targets");
    _ = command.description("Print the names of the targets affected by the current changes, one per line. Targets that cannot run on this platform are never named.");

    const help = try commander.renderHelp(allocator, command);
    var lines = std.mem.splitScalar(u8, help, '\n');
    while (lines.next()) |line| {
        try testing.expect(line.len <= commander.HELP_TOTAL_WIDTH);
    }
}

test "a usage line only claims what the command actually takes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bare = try commander.Command.init(allocator, "bare");
    try testing.expect(std.mem.startsWith(u8, try commander.renderHelp(allocator, bare), "Usage: bare\n"));

    const with_options = try commander.Command.init(allocator, "opts");
    try with_options.option("--config <path>", "The config file.", null);
    try testing.expect(std.mem.startsWith(u8, try commander.renderHelp(allocator, with_options), "Usage: opts [options]\n"));
}

//
// What the skl-shaped test actions record, so a test can see root flags and command-specific options.
//
const SklRecorder = struct {
    ran: bool = false,
    args: []const []const u8 = &.{},
    global: ?[]const u8 = null,
    ns: ?[]const u8 = null,
    from: ?[]const u8 = null,
    open: ?[]const u8 = null,
    no_color: ?[]const u8 = null,
    non_interactive: ?[]const u8 = null,
};

//
// A test action for the skl-shaped program.
//
fn recordSklAction(invocation: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    const recorder: *SklRecorder = @constCast(@ptrCast(@alignCast(invocation.context)));
    recorder.ran = true;
    recorder.args = invocation.args;
    recorder.global = invocation.option("global");
    recorder.ns = invocation.option("ns");
    recorder.from = invocation.option("from");
    recorder.open = invocation.option("open");
    recorder.no_color = invocation.option("no-color");
    recorder.non_interactive = invocation.option("non-interactive");
    return .{
        .ok = 0,
    };
}

//
// Builds a program shaped like skl: root booleans, add --ns, init/add --from.
//
fn buildSklProgram(allocator: std.mem.Allocator, recorder: *SklRecorder) !*commander.Command {
    const root = (try commander.Command.init(allocator, "skl"))
        .description("Install AI agent skill packages from git.")
        .version("0.0.1", "-V, --version", "Output the version number.");
    try root.option("-g, --global", "Use the global config.", null);
    try root.option("--no-color", "Disable color and icons.", null);
    try root.option("-n, --non-interactive", "Do not prompt.", null);

    const add = (try commander.Command.init(allocator, "add"))
        .description("Add a package.")
        .argument("[repo]", "The package to add.")
        .action(recorder, recordSklAction);
    try add.option("--ns <namespace>", "The namespace to install under.", null);
    try add.option("--from <spec>", "A YAML file inside a git repo.", null);
    try root.addCommand(add);

    const init_cmd = (try commander.Command.init(allocator, "init"))
        .description("Create a config file.")
        .action(recorder, recordSklAction);
    try init_cmd.option("--from <spec>", "A YAML file inside a git repo.", null);
    try root.addCommand(init_cmd);

    const docs = (try commander.Command.init(allocator, "docs"))
        .description("Show package documentation.")
        .argument("[package]", "The package to open.")
        .action(recorder, recordSklAction);
    try root.addCommand(docs);

    return root;
}

//
// Runs a command line against the skl-shaped program.
//
fn runSklLine(allocator: std.mem.Allocator, recorder: *SklRecorder, argv: []const []const u8, captured: *std.Io.Writer.Allocating) !commander.Outcome {
    const root = try buildSklProgram(allocator, recorder);
    return commander.parse(&captured.writer, root, argv);
}

test "a boolean flag stores true when present and is null when absent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var present = SklRecorder{};
    var captured_present = std.Io.Writer.Allocating.init(allocator);
    _ = try runSklLine(allocator, &present, &.{ "add", "--global", "--ns", "demo", "acme/skills" }, &captured_present);
    try testing.expect(present.ran);
    try testing.expectEqualStrings("true", present.global.?);
    try testing.expect(present.no_color == null);

    var absent = SklRecorder{};
    var captured_absent = std.Io.Writer.Allocating.init(allocator);
    _ = try runSklLine(allocator, &absent, &.{ "add", "--ns", "demo", "acme/skills" }, &captured_absent);
    try testing.expect(absent.ran);
    try testing.expect(absent.global == null);
}

test "-g combined with --ns on add sets both" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = SklRecorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runSklLine(allocator, &recorder, &.{ "add", "-g", "--ns", "demo", "acme/skills" }, &captured);

    try testing.expect(recorder.ran);
    try testing.expectEqualStrings("true", recorder.global.?);
    try testing.expectEqualStrings("demo", recorder.ns.?);
    try testing.expectEqualStrings("acme/skills", recorder.args[0]);
}

test "prefix -g add and suffix add -g both set global" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var prefix = SklRecorder{};
    var captured_prefix = std.Io.Writer.Allocating.init(allocator);
    _ = try runSklLine(allocator, &prefix, &.{ "-g", "add", "--ns", "demo", "acme/skills" }, &captured_prefix);
    try testing.expect(prefix.ran);
    try testing.expectEqualStrings("true", prefix.global.?);

    var suffix = SklRecorder{};
    var captured_suffix = std.Io.Writer.Allocating.init(allocator);
    _ = try runSklLine(allocator, &suffix, &.{ "add", "-g", "--ns", "demo", "acme/skills" }, &captured_suffix);
    try testing.expect(suffix.ran);
    try testing.expectEqualStrings("true", suffix.global.?);
}

test "an unknown option on the skl-shaped program is still refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = SklRecorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runSklLine(allocator, &recorder, &.{ "add", "--nosuch" }, &captured);

    try testing.expectEqualStrings("Unknown option '--nosuch'.", outcome.refused.message());
    try testing.expect(!recorder.ran);
}

test "--open is unknown on docs and add" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var docs_recorder = SklRecorder{};
    var docs_captured = std.Io.Writer.Allocating.init(allocator);
    const docs_outcome = try runSklLine(allocator, &docs_recorder, &.{ "docs", "--open", "acme/skills" }, &docs_captured);
    try testing.expectEqualStrings("Unknown option '--open'.", docs_outcome.refused.message());
    try testing.expect(!docs_recorder.ran);

    var add_recorder = SklRecorder{};
    var add_captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runSklLine(allocator, &add_recorder, &.{ "add", "--open" }, &add_captured);
    try testing.expectEqualStrings("Unknown option '--open'.", outcome.refused.message());
    try testing.expect(!add_recorder.ran);
}

test "--ns still requires a value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = SklRecorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    const outcome = try runSklLine(allocator, &recorder, &.{ "add", "--ns" }, &captured);

    try testing.expectEqualStrings("Option '--ns <namespace>' is missing its argument.", outcome.refused.message());
    try testing.expect(!recorder.ran);
}

test "--help, -h, and the help command all display help" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for ([_][]const []const u8{ &.{"--help"}, &.{"-h"}, &.{"help"} }) |argv| {
        var recorder = SklRecorder{};
        var captured = std.Io.Writer.Allocating.init(allocator);
        const outcome = try runSklLine(allocator, &recorder, argv, &captured);

        try testing.expect(std.mem.startsWith(u8, captured.written(), "Usage: skl"));
        try testing.expect(outcome == .displayed);
        try testing.expect(!recorder.ran);
    }

    var add_help = SklRecorder{};
    var add_captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runSklLine(allocator, &add_help, &.{ "help", "add" }, &add_captured);
    try testing.expect(std.mem.startsWith(u8, add_captured.written(), "Usage: add"));
    try testing.expect(!add_help.ran);
}

test "the version command prints the same as --version and -V" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for ([_][]const []const u8{ &.{"--version"}, &.{"-V"}, &.{"version"} }) |argv| {
        var recorder = SklRecorder{};
        var captured = std.Io.Writer.Allocating.init(allocator);
        _ = try runSklLine(allocator, &recorder, argv, &captured);

        try testing.expectEqualStrings("0.0.1\n", captured.written());
        try testing.expect(!recorder.ran);
    }
}

test "-n and --no-color are booleans on the root and reach add" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var recorder = SklRecorder{};
    var captured = std.Io.Writer.Allocating.init(allocator);
    _ = try runSklLine(allocator, &recorder, &.{ "-n", "--no-color", "add", "--ns", "demo", "acme/skills" }, &captured);

    try testing.expect(recorder.ran);
    try testing.expectEqualStrings("true", recorder.non_interactive.?);
    try testing.expectEqualStrings("true", recorder.no_color.?);
}

//
// A program with an option, an alias and a subcommand, built from `allocator`: something to fail
// each allocation of in turn.
//
fn buildSmallProgram(allocator: std.mem.Allocator) std.mem.Allocator.Error!*commander.Command {
    const program = (try commander.program(allocator)).name("skl");
    try program.option("-g, --global", "Use the global config.", null);
    const install = try commander.Command.init(allocator, "install");
    try install.alias("i");
    try install.option("--quiet", "", null);
    try program.addCommand(install);
    return program;
}

test "building a command line returns error.OutOfMemory at every allocation that fails, and never panics" {
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var failing = testing.FailingAllocator.init(arena.allocator(), .{
            .fail_index = fail_index,
        });

        const built = buildSmallProgram(failing.allocator());

        if (!failing.has_induced_failure) {
            _ = try built;
            break;
        }
        try testing.expectError(error.OutOfMemory, built);
    }
    try testing.expect(fail_index > 0);
}

test "writeWrapped puts every word on a line of its own when the indent leaves no room" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);

    try commander.writeWrapped(&out, testing.allocator, "one two", commander.HELP_TOTAL_WIDTH + 1);

    try testing.expect(std.mem.startsWith(u8, out.items, "one\n"));
    try testing.expect(std.mem.endsWith(u8, out.items, "two\n"));
}

test "writeWrapped reports running out of memory, not a crash, for an indent too large to hold" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);

    try testing.expectError(error.OutOfMemory, commander.writeWrapped(&out, testing.allocator, "one two", std.math.maxInt(usize)));
}
