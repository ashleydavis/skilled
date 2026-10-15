//
// The test input factories for `skl install`'s options, so Faultline calls `install.run` with each
// set.
//

const std = @import("std");

//
// The command whose options these are.
//
const install = @import("install.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// The run values and the project layouts every command's scenarios share.
//
const global_sim = @import("global.sim.zig");

//
// `skl install`, which installs the project's packages.
//
pub fn project() install.Args {
    return .{};
}

//
// `skl install -g`, which installs the machine's packages.
//
pub fn global() install.Args {
    return .{
        .global = true,
    };
}

//
// `skl install` with the options of `project`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn projectScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try install.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), project());
}

//
// `skl install` with the options of `global`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn globalScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try install.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), global());
}

//
// `skl install` in a project with one package whose clone is not in the store, which clones it.
//
pub fn installCloningScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeToolsNamespaceTaken(context.io);
    _ = try install.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), project());
}
