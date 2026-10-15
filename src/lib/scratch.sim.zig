//
// The scenarios for the functions in `scratch.zig`: each lays out the project's agent directories
// as a user can leave them, then creates and links the scratch directory.
//

//
// The file whose functions the scenarios call.
//
const scratch = @import("scratch.zig");

//
// The paths of the project and the layouts of its agent directories.
//
const global_sim = @import("global.sim.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// A second `skl install`, after the first made the scratch directory and linked it.
//
pub fn syncAlreadyLinkedScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeScratchAlreadyLinked(context.io);
    _ = try scratch.sync(context.io, context.allocator, try global_sim.projectScope(context.allocator));
}

//
// `skl install` after the scratch directory moved, so the `loc` links name the old place.
//
pub fn syncStaleLinksScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeStaleScratchLinks(context.io);
    _ = try scratch.sync(context.io, context.allocator, try global_sim.projectScope(context.allocator));
}

//
// `skl install` in a project where `.claude/skills` is a file, which is refused.
//
pub fn syncIntoAgentRootFileScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeAgentRootAsFile(context.io);
    _ = try scratch.sync(context.io, context.allocator, try global_sim.projectScope(context.allocator));
}

//
// `skl install` in a project where `.cursor/skills` is a symlink, which is refused.
//
pub fn syncIntoAgentRootSymlinkScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeAgentRootAsSymlink(context.io);
    _ = try scratch.sync(context.io, context.allocator, try global_sim.projectScope(context.allocator));
}

//
// `skl install` in a project where a file sits where a `loc` link goes, which is refused.
//
pub fn syncOverFileScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeFileWhereLinkGoes(context.io);
    _ = try scratch.sync(context.io, context.allocator, try global_sim.projectScope(context.allocator));
}
