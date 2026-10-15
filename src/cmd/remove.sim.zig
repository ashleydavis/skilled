//
// The test input factories for `skl remove`'s options, so Faultline calls `remove.run` with each
// set.
//

const std = @import("std");

//
// The command whose options these are.
//
const remove = @import("remove.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// The run values and the project layouts every command's scenarios share.
//
const global_sim = @import("global.sim.zig");

//
// `skl remove demo`, which removes the package under `demo`.
//
pub fn onePackage() remove.Args {
    return .{
        .query = "demo",
    };
}

//
// `skl remove acme/local`, the package whose repo is `git@github.com:acme/local.git`, named by its
// owner and repo.
//
pub fn packageByShorthand() remove.Args {
    return .{
        .query = "acme/local",
    };
}

//
// `skl remove loc`, the scratch directory's namespace, which is refused.
//
pub fn scratchDirectory() remove.Args {
    return .{
        .query = "loc",
    };
}

//
// `skl remove tools`, the package on a branch name git refuses.
//
pub fn packageOnBadBranch() remove.Args {
    return .{
        .query = "tools",
    };
}

//
// `skl remove acme/skills`, the same package named by its repo.
//
pub fn onePackageByRepo() remove.Args {
    return .{
        .query = "acme/skills",
    };
}

//
// `skl remove nope`, a package that is not in `skl.yaml`, which is refused.
//
pub fn missingPackage() remove.Args {
    return .{
        .query = "nope",
    };
}

//
// `skl remove -g demo`, the package under `demo` in the machine's `skl.yaml`.
//
pub fn global() remove.Args {
    return .{
        .global = true,
        .query = "demo",
    };
}

//
// `skl remove skills`, the package whose repo is `acme/skills`, named by its repo name alone.
//
pub fn packageByRepoName() remove.Args {
    return .{
        .query = "skills",
    };
}

//
// `skl remove` with the options of `onePackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn onePackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try remove.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), onePackage());
}

//
// `skl remove` with the options of `packageByShorthand`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageByShorthandScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try remove.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageByShorthand());
}

//
// `skl remove` with the options of `scratchDirectory`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn scratchDirectoryScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try remove.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), scratchDirectory());
}

//
// `skl remove` with the options of `packageOnBadBranch`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageOnBadBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try remove.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageOnBadBranch());
}

//
// `skl remove` with the options of `onePackageByRepo`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn onePackageByRepoScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try remove.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), onePackageByRepo());
}

//
// `skl remove` with the options of `missingPackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn missingPackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try remove.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), missingPackage());
}

//
// `skl remove` with the options of `global`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn globalScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try remove.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), global());
}

//
// `skl remove` with the options of `packageByRepoName`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageByRepoNameScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try remove.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageByRepoName());
}
