//
// The test input factories for `skl update`'s options, so Faultline calls `update.run` with each
// set.
//
// The sets that get furthest come first, because Faultline's first call to a function uses the
// first factory for each parameter and pairs only the first few of them with each other.
//

const std = @import("std");
const skilled = @import("skilled");

//
// The command whose options these are.
//
const update = @import("update.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// The run values and the project layouts every command's scenarios share.
//
const global_sim = @import("global.sim.zig");

//
// The file that declares `Match`, the row of `skl.yaml` a query picked.
//
const shared = @import("shared.zig");

//
// `skl update`, which updates every package.
//
pub fn everyPackage() update.Args {
    return .{};
}

//
// `skl update other --branch dev`, a package with no clone in the store yet, moved to `dev`.
//
pub fn packageNotClonedToBranch() update.Args {
    return .{
        .query = "other",
        .branch = "dev",
    };
}

//
// `skl update demo`, which updates the one package under `demo`.
//
pub fn onePackage() update.Args {
    return .{
        .query = "demo",
    };
}

//
// `skl update demo --branch dev`, which moves the package to another branch.
//
pub fn onePackageToBranch() update.Args {
    return .{
        .query = "demo",
        .branch = "dev",
    };
}

//
// `skl update demo --local ../local-skills`, which links the package to a working tree.
//
pub fn onePackageToLocalTree() update.Args {
    return .{
        .query = "demo",
        .local = "../local-skills",
    };
}

//
// The working tree in `skl update demo --local /home/skilled/local-skills`.
//
pub fn localTreePath() []const u8 {
    return "/home/skilled/local-skills";
}

//
// The branch in `skl update demo --branch dev`.
//
pub fn devBranch() []const u8 {
    return "dev";
}

//
// `skl update demo --branch dev` where `demo` was taken out of `skl.yaml` by hand after the match
// was made, so the row it names is past the end of the file.
//
pub fn matchPastTheEnd() shared.Match {
    return .{
        .index = 9,
        .pkg = .{
            .repo = "acme/skills",
            .namespace = "demo",
        },
    };
}

//
// `skl update broken --branch dev`, the row whose repo names no owner, so where its files are cannot
// be worked out.
//
pub fn matchWithBadRepo() shared.Match {
    return .{
        .index = 0,
        .pkg = .{
            .repo = "acme",
            .namespace = "broken",
        },
    };
}

//
// `skl update other --branch dev`, matched to the first row of `skl.yaml`: `acme/other`, whose
// clone is not in the store yet.
//
pub fn otherMatch() shared.Match {
    return .{
        .index = 0,
        .pkg = .{
            .repo = "acme/other",
            .namespace = "other",
        },
    };
}

//
// The `skl.yaml` `skl update other --branch dev` reads: one row, `acme/other` under `other`.
//
pub fn fileWithOther(allocator: std.mem.Allocator) !skilled.config.File {
    const packages = try allocator.alloc(skilled.config.Package, 1);
    packages[0] = .{
        .repo = "acme/other",
        .namespace = "other",
    };
    return .{
        .packages = packages,
    };
}

//
// The paths `skl update` uses in the project `/home/skilled/project`.
//
pub fn projectScope(allocator: std.mem.Allocator) !skilled.paths.Scope {
    return skilled.paths.scopeFromFlag(allocator, false, "/home/skilled", "/home/skilled/project", null);
}

//
// `skl update other --branch dev`, the package whose clone is not in the store yet.
//
pub fn otherPackageToBranch() update.Args {
    return .{
        .query = "other",
        .branch = "dev",
    };
}

//
// `skl update nope --branch dev`, a package that is not in `skl.yaml`, which is refused.
//
pub fn missingPackageToBranch() update.Args {
    return .{
        .query = "nope",
        .branch = "dev",
    };
}

//
// `skl update nope`, a package that is not in `skl.yaml`, which is refused.
//
pub fn missingPackage() update.Args {
    return .{
        .query = "nope",
    };
}

//
// `skl update --branch dev`, which is refused because it names no package.
//
pub fn branchWithoutPackage() update.Args {
    return .{
        .branch = "dev",
    };
}

//
// `skl update --local ../local-skills`, which is refused because it names no package.
//
pub fn localTreeWithoutPackage() update.Args {
    return .{
        .local = "../local-skills",
    };
}

//
// `skl update demo --branch dev --local ../local-skills`, which is refused.
//
pub fn branchWithLocalTree() update.Args {
    return .{
        .query = "demo",
        .branch = "dev",
        .local = "../local-skills",
    };
}

//
// `skl update -g`, which updates every package in the machine's `skl.yaml`.
//
pub fn global() update.Args {
    return .{
        .global = true,
    };
}

//
// `skl update` with the options of `everyPackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn everyPackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), everyPackage());
}

//
// `skl update` with the options of `packageNotClonedToBranch`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn packageNotClonedToBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), packageNotClonedToBranch());
}

//
// `skl update` with the options of `onePackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn onePackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), onePackage());
}

//
// `skl update` with the options of `onePackageToBranch`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn onePackageToBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), onePackageToBranch());
}

//
// `skl update` with the options of `onePackageToLocalTree`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn onePackageToLocalTreeScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), onePackageToLocalTree());
}

//
// `skl update` with the options of `otherPackageToBranch`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn otherPackageToBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), otherPackageToBranch());
}

//
// `skl update` with the options of `missingPackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn missingPackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), missingPackage());
}

//
// `skl update` with the options of `branchWithoutPackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn branchWithoutPackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), branchWithoutPackage());
}

//
// `skl update` with the options of `localTreeWithoutPackage`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn localTreeWithoutPackageScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), localTreeWithoutPackage());
}

//
// `skl update` with the options of `branchWithLocalTree`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn branchWithLocalTreeScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), branchWithLocalTree());
}

//
// `skl update` with the options of `global`, run in a project after `skl install` whose `skl.yaml` has one
// package row of every kind.
//
pub fn globalScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), global());
}

//
// `skl update other --branch dev` in a project after `skl install` with one package row of every
// kind, where the new clone has no commits yet, which is refused.
//
pub fn updateToBranchWithoutCommitsScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.runWithoutCommits(context.allocator, context.io), otherPackageToBranch());
}

//
// `skl update demo --branch dev` in a project after `skl install` with one package row of every
// kind, where the clone it leaves has no commits yet, which is refused.
//
pub fn updateFromCloneWithoutCommitsScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.runWithoutCommits(context.allocator, context.io), onePackageToBranch());
}

//
// `skl update demo --local ../local-skills` where `demo` was taken out of `skl.yaml` by hand after
// the match was made, which is refused.
//
pub fn updateToLocalTreePastTheEndScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try global_sim.writeLocalTree(context.io);
    const ctx = try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    });
    _ = try update.switchToLocal(ctx, try projectScope(context.allocator), try fileWithOther(context.allocator), matchPastTheEnd(), localTreePath());
}

//
// `skl update demo --branch dev` where `demo` was taken out of `skl.yaml` by hand after the match
// was made, which is refused.
//
pub fn updateToBranchPastTheEndScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    const ctx = try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    });
    _ = try update.switchToBranch(ctx, try projectScope(context.allocator), try fileWithOther(context.allocator), matchPastTheEnd(), devBranch());
}

//
// `skl update other --local ../local-skills`, matched to the first row of a `skl.yaml` that lists
// only `acme/other`.
//
pub fn updateOtherToLocalTreeScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeLocalTree(context.io);
    const ctx = try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    });
    _ = try update.switchToLocal(ctx, try projectScope(context.allocator), try fileWithOther(context.allocator), otherMatch(), localTreePath());
}

//
// `skl update nope --branch dev` in a project after `skl install` whose `skl.yaml` has one package
// row of every kind, which is refused.
//
pub fn missingPackageToBranchScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeEveryKindOfPackage(context.allocator, context.io);
    _ = try update.run(try global_sim.build(context.allocator, context.io, .{
        .stdout = context.writer,
    }), missingPackageToBranch());
}
