//
// The test input factories for `skl init`'s options, so Faultline calls `init.run` with each set.
//

const std = @import("std");

//
// The command whose options these are.
//
const init = @import("init.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// The run values and the project layouts every command's scenarios share.
//
const global_sim = @import("global.sim.zig");

//
// `skl init`, which writes an empty `skl.yaml` or leaves an existing one alone.
//
pub fn noOptions() init.Args {
    return .{};
}

//
// `skl init --from acme/config:skl.yaml`, which starts `skl.yaml` from a file in git.
//
pub fn fromFile() init.Args {
    return .{
        .from = "acme/config:skl.yaml",
    };
}

//
// `skl init -g`, which writes the machine's `skl.yaml`.
//
pub fn global() init.Args {
    return .{
        .global = true,
    };
}

//
// `skl init` with the options of `noOptions`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn noOptionsScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try init.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), noOptions());
}

//
// `skl init` with the options of `fromFile`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn fromFileScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try init.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromFile());
}

//
// `skl init` with the options of `global`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn globalScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try init.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), global());
}

//
// `skl init` in a project with no `skl.yaml`, which writes one.
//
pub fn initInEmptyProjectScenario(context: *sim.ScenarioContext) anyerror!void {
    _ = try init.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), noOptions());
}

//
// `skl init` in a project whose `skl.yaml` lists no packages, which leaves it alone.
//
pub fn initWithEmptyConfigScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEmptyConfig(context.io);
    _ = try init.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), noOptions());
}

//
// `skl init --from acme/config:skl.yaml` in a project with no `skl.yaml`, which fills one and
// installs what it lists.
//
pub fn initFromFileInEmptyProjectScenario(context: *sim.ScenarioContext) anyerror!void {
    _ = try init.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromFile());
}

//
// `skl init --from acme/config:skl.yaml` in a project whose `skl.yaml` lists no packages, which
// fills it.
//
pub fn initFromFileWithEmptyConfigScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEmptyConfig(context.io);
    _ = try init.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromFile());
}
