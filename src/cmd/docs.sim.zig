//
// The test input factories for `skl docs`'s options, so Faultline calls `docs.run` with each set.
//

const std = @import("std");

//
// The command whose options these are.
//
const docs = @import("docs.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// The run values and the project layouts every command's scenarios share.
//
const global_sim = @import("global.sim.zig");

//
// `skl docs demo`, which prints the package under `demo` and opens its page.
//
pub fn onePackage() docs.Args {
    return .{
        .query = "demo",
    };
}

//
// `skl docs`, which asks which package when interactive and is refused otherwise.
//
pub fn noPackage() docs.Args {
    return .{};
}

//
// `skl docs tools`, the package on a branch name git refuses.
//
pub fn packageOnBadBranch() docs.Args {
    return .{
        .query = "tools",
    };
}

//
// `skl docs other`, a package with no clone in the store yet.
//
pub fn packageNotCloned() docs.Args {
    return .{
        .query = "other",
    };
}

//
// `skl docs demo-dev`, the package on branch `dev` in the project with three packages.
//
pub fn packageOnBranch() docs.Args {
    return .{
        .query = "demo-dev",
    };
}

//
// `skl docs local`, the package linked from a working tree in the project with three packages.
//
pub fn packageFromLocalTree() docs.Args {
    return .{
        .query = "local",
    };
}

//
// `skl docs nope`, a package that is not in `skl.yaml`, which is refused.
//
pub fn missingPackage() docs.Args {
    return .{
        .query = "nope",
    };
}

//
// `skl docs -g demo`, the package under `demo` in the machine's `skl.yaml`.
//
pub fn global() docs.Args {
    return .{
        .global = true,
        .query = "demo",
    };
}

//
// `skl docs broken`, the package whose repo names no owner, which is refused.
//
pub fn packageWithBadRepo() docs.Args {
    return .{
        .query = "broken",
    };
}

//
// `skl docs` with the options of `onePackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn onePackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), onePackage());
}

//
// `skl docs` with the options of `noPackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn noPackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), noPackage());
}

//
// `skl docs` with the options of `packageOnBadBranch`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageOnBadBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageOnBadBranch());
}

//
// `skl docs` with the options of `packageNotCloned`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageNotClonedScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageNotCloned());
}

//
// `skl docs` with the options of `packageOnBranch`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageOnBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageOnBranch());
}

//
// `skl docs` with the options of `packageFromLocalTree`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageFromLocalTreeScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageFromLocalTree());
}

//
// `skl docs` with the options of `missingPackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn missingPackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), missingPackage());
}

//
// `skl docs` with the options of `global`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn globalScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), global());
}

//
// `skl docs` with the options of `packageWithBadRepo`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageWithBadRepoScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageWithBadRepo());
}

//
// `skl docs demo` typed at a terminal in a project with one package, where the browser refuses to
// open the page.
//
pub fn docsWithRefusingBrowserScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.interactiveRunWithRefusingBrowser(context.allocator, context.io), onePackage());
}

//
// `skl docs demo` typed at a terminal in a project with one package, where the page is opened by
// starting the system's opener.
//
pub fn docsOpeningWithProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.interactiveRunOpeningWithProcess(context.allocator, context.io), onePackage());
}

//
// `skl docs` typed at a terminal in a project with one package, with nothing typed at the menu,
// which is refused.
//
pub fn docsWithNothingTypedScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.interactiveRunWithNothingTyped(context.allocator, context.io), noPackage());
}

//
// `skl docs` typed at a terminal in a project with one package, with `1` typed at the menu.
//
pub fn docsChoosingFromMenuScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .typed = "1\n",
        .interactive = true,
        .stdout = context.writer,
    }), noPackage());
}

//
// `skl docs demo` in a project whose `skl.yaml` lists no packages, which is refused.
//
pub fn docsWithEmptyConfigScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEmptyConfig(context.io);
    _ = try docs.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), onePackage());
}
