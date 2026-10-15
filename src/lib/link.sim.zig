//
// The value factories and scenarios for the functions in `link.zig`. The scenarios lay out a
// package in the store and agent directories, some already linked, then link or unlink it.
//

const std = @import("std");

//
// The files a factory lays out in Faultline's simulated filesystem.
//
const files = @import("files.zig");

//
// The file whose functions the scenarios call.
//
const link = @import("link.zig");

//
// The paths of the project and the layouts of its agent directories.
//
const global_sim = @import("global.sim.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// Where `writeLinkedStoreClone` lays out the clone.
//
const linked_store = "/home/skilled/store/acme/skills@main";

//
// Where `writeSkillsOnlyStoreClone` lays out the clone.
//
const skills_only_store = "/home/skilled/store/acme/hello@main";

//
// Lays out the store clone `skl update demo` relinks after `skl add acme/skills --ns demo`, whose
// `skills` tree is already linked as `demo` in `/home/skilled/agent`.
//
pub fn writeLinkedStoreClone(io: std.Io) !void {
    try files.makeDirPath(io, linked_store ++ "/skills/hello");
    try files.makeDirPath(io, linked_store ++ "/commands");
    try files.makeDirPath(io, "/home/skilled/agent");
    try std.Io.Dir.cwd().symLink(io, linked_store ++ "/skills", "/home/skilled/agent/demo", .{
        .is_directory = true,
    });
}

//
// Lays out the store clone `skl add acme/hello --ns demo` links when the package has skills and no
// commands.
//
pub fn writeSkillsOnlyStoreClone(io: std.Io) !void {
    try files.makeDirPath(io, skills_only_store ++ "/skills/hello");
}

//
// `skl remove demo` taking away the `demo` link the agent directory holds to the store clone's
// `skills` tree.
//
pub fn unlinkLinkedTreeScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeLinkedStoreClone(context.io);
    _ = try link.unlinkTree(context.io, context.allocator, linked_store, skillsTree(), demoNamespace(), agentDirectory());
}

//
// `skl add acme/hello --ns demo` for a package with only skills, in a project where
// `.claude/commands` is a file, which is refused.
//
pub fn linkSkillsOnlyIntoFileScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeSkillsOnlyStoreClone(context.io);
    try global_sim.writeClaudeCommandsAsFile(context.io);
    _ = try link.linkPackage(context.io, context.allocator, skills_only_store, demoNamespace(), try global_sim.projectScope(context.allocator));
}

//
// `skl add acme/skills --ns demo` linking a clone with both trees, in a project where
// `.claude/skills` is a file, which is refused.
//
pub fn linkIntoAgentRootFileScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeLinkedStoreClone(context.io);
    try global_sim.writeAgentRootAsFile(context.io);
    _ = try link.linkPackage(context.io, context.allocator, linked_store, demoNamespace(), try global_sim.projectScope(context.allocator));
}

//
// `skl add acme/skills --ns demo` linking a clone with both trees, in a project where
// `.cursor/skills` is a symlink, which is refused.
//
pub fn linkIntoAgentRootSymlinkScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeLinkedStoreClone(context.io);
    try global_sim.writeAgentRootAsSymlink(context.io);
    _ = try link.linkPackage(context.io, context.allocator, linked_store, demoNamespace(), try global_sim.projectScope(context.allocator));
}

//
// `skl add acme/skills --ns demo` linking a clone with both trees into a project, then
// `skl remove demo` unlinking it again.
//
pub fn linkThenUnlinkScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeLinkedStoreClone(context.io);
    const scope = try global_sim.projectScope(context.allocator);
    _ = try link.linkPackage(context.io, context.allocator, linked_store, demoNamespace(), scope);
    _ = try link.unlinkPackage(context.io, context.allocator, linked_store, demoNamespace(), scope);
}

//
// The tree `skl update demo` relinks: `skills`.
//
pub fn skillsTree() []const u8 {
    return "skills";
}

//
// The namespace in `skl add acme/skills --ns demo`.
//
pub fn demoNamespace() []const u8 {
    return "demo";
}

//
// The agent directory holding the `demo` link that `skl add acme/skills --ns demo` made.
//
pub fn agentDirectory() []const u8 {
    return "/home/skilled/agent";
}
