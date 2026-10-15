//
// The test input factories for `skl list`'s options, so Faultline calls `list.run` with each set.
//

const std = @import("std");

//
// The command whose options these are.
//
const list = @import("list.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// The run values and the project layouts every command's scenarios share.
//
const global_sim = @import("global.sim.zig");

//
// `skl list`, which lists the project's packages.
//
pub fn project() list.Args {
    return .{};
}

//
// `skl list -g`, which lists the machine's packages.
//
pub fn global() list.Args {
    return .{
        .global = true,
    };
}

//
// `skl list` with the options of `project`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn projectScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try list.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), project());
}

//
// `skl list` with the options of `global`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn globalScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try list.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), global());
}

//
// `skl list` after `skl init`, in a project whose `skl.yaml` lists no packages and whose scratch
// directory is linked.
//
pub fn listScratchOnlyScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeScratchOnly(context.allocator, context.io);
    _ = try list.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), project());
}
