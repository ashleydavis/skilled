//
// The test input factories for `skl add`'s options, so Faultline calls `add.run` with each set.
//
// The sets that get furthest come first, because Faultline's first call to a function uses the
// first factory for each parameter and pairs only the first few of them with each other.
//

const std = @import("std");
const skilled = @import("skilled");

//
// The command whose options these are.
//
const add = @import("add.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// The run values and the project layouts every command's scenarios share.
//
const global_sim = @import("global.sim.zig");

//
// `skl add acme/skills --ns demo2`, the package the store already holds, under a free namespace.
//
pub fn repoWithNamespace() add.Args {
    return .{
        .repo = "acme/skills",
        .namespace = "demo2",
    };
}

//
// `skl add acme/other` without `--ns`, which prompts when interactive and is refused otherwise.
//
pub fn repoWithoutNamespace() add.Args {
    return .{
        .repo = "acme/other",
    };
}

//
// `skl add acme/local --ns local --local ../local-skills`, which links a working tree in place.
//
pub fn repoFromLocalTree() add.Args {
    return .{
        .repo = "acme/local",
        .namespace = "local",
        .local = "../local-skills",
    };
}

//
// `skl add acme/skills --ns demo2 --branch dev`, a branch the store has no clone of, so it clones
// one.
//
pub fn repoOnBranch() add.Args {
    return .{
        .repo = "acme/skills",
        .namespace = "demo2",
        .branch = "dev",
    };
}

//
// `skl add --from acme/config:skl.yaml`, which fetches the named file and merges its packages.
//
pub fn fromOnly() add.Args {
    return .{
        .from = "acme/config:skl.yaml",
    };
}

//
// `skl add acme/skills --ns ""`, which is refused.
//
pub fn repoWithEmptyNamespace() add.Args {
    return .{
        .repo = "acme/skills",
        .namespace = "",
    };
}

//
// `skl add acme/skills --ns loc`, the namespace reserved for the scratch directory, which is
// refused.
//
pub fn repoWithReservedNamespace() add.Args {
    return .{
        .repo = "acme/skills",
        .namespace = skilled.scratch.namespace,
    };
}

//
// `skl add acme/skills --ns demo`, the namespace the project's one package already uses, which is
// refused.
//
pub fn repoWithTakenNamespace() add.Args {
    return .{
        .repo = "acme/skills",
        .namespace = "demo",
    };
}

//
// `skl add acme/other --branch dev --local ../skills`, which is refused.
//
pub fn branchWithLocal() add.Args {
    return .{
        .repo = "acme/other",
        .branch = "dev",
        .local = "../skills",
    };
}

//
// `skl add`, which is refused because it names no repo.
//
pub fn noOptions() add.Args {
    return .{};
}

//
// `skl add acme/other --from acme/skills`, which is refused before anything is fetched.
//
pub fn fromWithRepo() add.Args {
    return .{
        .from = "acme/skills",
        .repo = "acme/other",
    };
}

//
// `skl add --from acme/config:skl.yaml --ns demo2`, which is refused before anything is fetched.
//
pub fn fromWithNamespace() add.Args {
    return .{
        .from = "acme/config:skl.yaml",
        .namespace = "demo2",
    };
}

//
// `skl add --from acme/config:skl.yaml --branch dev`, which is refused before anything is fetched.
//
pub fn fromWithBranch() add.Args {
    return .{
        .from = "acme/config:skl.yaml",
        .branch = "dev",
    };
}

//
// `skl add --from acme/config:skl.yaml --local ../skills`, which is refused before anything is
// fetched.
//
pub fn fromWithLocal() add.Args {
    return .{
        .from = "acme/config:skl.yaml",
        .local = "../skills",
    };
}

//
// `skl add acme/skills --ns ..`, a namespace that could leave the agent's directory, which is
// refused.
//
pub fn repoWithInvalidNamespace() add.Args {
    return .{
        .repo = "acme/skills",
        .namespace = "..",
    };
}

//
// `skl add` with the options of `repoWithNamespace`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn repoWithNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoWithNamespace());
}

//
// `skl add` with the options of `repoWithoutNamespace`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn repoWithoutNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoWithoutNamespace());
}

//
// `skl add` with the options of `repoFromLocalTree`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn repoFromLocalTreeScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoFromLocalTree());
}

//
// `skl add` with the options of `repoOnBranch`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn repoOnBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoOnBranch());
}

//
// `skl add` with the options of `fromOnly`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn fromOnlyScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromOnly());
}

//
// `skl add` with the options of `repoWithEmptyNamespace`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn repoWithEmptyNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoWithEmptyNamespace());
}

//
// `skl add` with the options of `repoWithReservedNamespace`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn repoWithReservedNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoWithReservedNamespace());
}

//
// `skl add` with the options of `repoWithTakenNamespace`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn repoWithTakenNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoWithTakenNamespace());
}

//
// `skl add` with the options of `branchWithLocal`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn branchWithLocalScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), branchWithLocal());
}

//
// `skl add` with the options of `noOptions`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn noOptionsScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), noOptions());
}

//
// `skl add` with the options of `fromWithRepo`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn fromWithRepoScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromWithRepo());
}

//
// `skl add` with the options of `fromWithNamespace`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn fromWithNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromWithNamespace());
}

//
// `skl add` with the options of `fromWithBranch`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn fromWithBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromWithBranch());
}

//
// `skl add` with the options of `fromWithLocal`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn fromWithLocalScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromWithLocal());
}

//
// `skl add` with the options of `repoWithInvalidNamespace`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn repoWithInvalidNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoWithInvalidNamespace());
}

//
// `skl add acme/skills` typed at a terminal in a project with one package, with `demo2` typed at
// the namespace prompt.
//
pub fn addAskingForNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    _ = try add.run(try global_sim.interactiveRunTypingDemo2(context.allocator, context.io), repoWithoutNamespace());
}

//
// `skl add acme/skills` typed at a terminal in a project with one package, with nothing typed
// before stdin ends, which is refused.
//
pub fn addWithNothingTypedScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    _ = try add.run(try global_sim.interactiveRunWithNothingTyped(context.allocator, context.io), repoWithoutNamespace());
}

//
// `skl add acme/skills` typed at a terminal in a project with one package, with stdin that cannot
// be read, which is refused.
//
pub fn addWithUnreadableStdinScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    _ = try add.run(try global_sim.interactiveRunWithUnreadableStdin(context.allocator, context.io), repoWithoutNamespace());
}

//
// `skl add acme/skills` typed at a terminal in a project with one package, with a line too long to
// read pasted at the prompt, which is refused.
//
pub fn addWithEndlessLineScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    _ = try add.run(try global_sim.interactiveRunWithEndlessLine(context.allocator, context.io), repoWithoutNamespace());
}

//
// `skl add acme/local --ns local --local ../local-skills` in a project with one package, where the
// working tree has no commits yet, which is refused.
//
pub fn addLocalTreeWithoutCommitsScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try global_sim.writeLocalTree(context.io);
    _ = try add.run(try global_sim.runWithoutCommits(context.allocator, context.io), repoFromLocalTree());
}

//
// `skl add --from acme/config:skl.yaml` in a project that already gives `tools` to another repo,
// which is refused.
//
pub fn addFromTakenNamespaceScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeToolsNamespaceTaken(context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), fromOnly());
}

//
// `skl add acme/local --ns local --local ../local-skills` in a project with one package, which links
// the working tree in place.
//
pub fn addLocalTreeScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try global_sim.writeLocalTree(context.io);
    _ = try add.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), repoFromLocalTree());
}
