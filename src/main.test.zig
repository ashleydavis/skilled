//
// Tests for main.zig.
//

const std = @import("std");
const commander = skilled.commander;
const harness = @import("lib/test/harness.zig");
const main = @import("main.zig");
const skilled = @import("skilled");
const testing = std.testing;

const Failure = skilled.failure.Failure;

test "reportFailure prints the message and exits non-zero" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var fail = Failure.init(arena.allocator());
    _ = fail.set("no skl.yaml; run skl init", .{}) catch {};

    var captured = std.Io.Writer.Allocating.init(arena.allocator());
    try testing.expectEqual(@as(u8, 1), main.reportFailure(&fail, &captured.writer));
    try testing.expectEqualStrings("no skl.yaml; run skl init\n", captured.written());
}

test "reportFailure says something even when nothing was recorded" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var fail = Failure.init(arena.allocator());
    var captured = std.Io.Writer.Allocating.init(arena.allocator());
    try testing.expectEqual(@as(u8, 1), main.reportFailure(&fail, &captured.writer));
    try testing.expect(captured.written().len > 1);
}

test "buildProgram declares every command" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const context = scenario.context();
    const program = main.buildProgram(&context);

    for ([_][]const u8{ "init", "install", "add", "remove", "update", "list", "docs" }) |name| {
        try testing.expect(program.findSubcommand(name) != null);
    }
    try testing.expect(program.findSubcommand("install").?.matches("i"));
}

test "the program help names every command" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const context = scenario.context();
    const help = try commander.renderHelp(scenario.allocator(), main.buildProgram(&context));

    try testing.expect(std.mem.startsWith(u8, help, "Usage: skl"));
    for ([_][]const u8{ "init", "install", "add", "remove", "update", "list", "docs" }) |name| {
        try testing.expect(std.mem.indexOf(u8, help, name) != null);
    }
}

test "bare parse of no args prints help and is Displayed" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const context = scenario.context();
    var captured = std.Io.Writer.Allocating.init(scenario.allocator());
    var runner = commander.Program{ .out = &captured.writer };
    try testing.expectError(error.Displayed, commander.parse(&runner, main.buildProgram(&context), &.{}));
    try testing.expect(std.mem.indexOf(u8, captured.written(), "Usage: skl") != null);
}

test "init --from through Commander writes YAML and does not clone into the store" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const context = scenario.context();
    var captured = std.Io.Writer.Allocating.init(scenario.allocator());
    var runner = commander.Program{ .out = &captured.writer };
    try commander.parse(
        &runner,
        main.buildProgram(&context),
        &.{ "init", "--from", "acme/skl-config:teams/platform.yaml" },
    );
    const yaml = try scenario.readProjectYaml();
    try testing.expect(std.mem.indexOf(u8, yaml, "acme/skills") != null);
    try testing.expect(scenario.git.calls.items.len >= 2);
    const dest = scenario.git.calls.items[0].argv[scenario.git.calls.items[0].argv.len - 1];
    try testing.expect(std.mem.indexOf(u8, dest, ".skilled") == null);
}
