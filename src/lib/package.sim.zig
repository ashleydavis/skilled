//
// The scenarios for the functions in `package.zig`: each lays out a package directory and scans it,
// so Faultline exercises the scan with every failure it can inject there.
//

const std = @import("std");

//
// The files the layouts write in Faultline's simulated filesystem.
//
const files = @import("files.zig");

//
// The file whose functions the scenarios call.
//
const package = @import("package.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// Where `writeFullPackage` lays the package out, which its scenario then reads.
//
const full_package_root = "/home/skilled/packages/full";

//
// Where `writeSkillsOnlyPackage` lays the package out, which its scenario then reads.
//
const skills_only_package_root = "/home/skilled/packages/skills-only";

//
// Where `writeCommandsOnlyPackage` lays the package out, which its scenario then reads.
//
const commands_only_package_root = "/home/skilled/packages/commands-only";

//
// Where `writeEmptyPackage` lays the package out, which its scenario then reads.
//
const empty_package_root = "/home/skilled/packages/empty";

//
// Where `writePackageWithSkillsAsFile` lays the package out, which its scenario then reads.
//
const package_with_skills_as_file_root = "/home/skilled/packages/odd";

//
// Lays out the clone `skl add acme/skills --ns demo` scans: two skills, one of them a directory with no
// `SKILL.md`, commands nested in a folder beside a file that is not markdown, and a README whose
// frontmatter has a description.
//
pub fn writeFullPackage(io: std.Io) !void {
    const root = full_package_root;
    try writeFile(io, root ++ "/skills/hello/SKILL.md", "---\ndescription: Says hello.\n---\n# Hello\n");
    try writeFile(io, root ++ "/skills/bye/SKILL.md", "# Bye\n\nSays bye.\n");
    try files.makeDirPath(io, root ++ "/skills/empty");
    try writeFile(io, root ++ "/skills/notes.txt", "Not a skill.\n");
    try writeFile(io, root ++ "/commands/plan/create.md", "# Create\n\nMakes a plan.\n");
    try writeFile(io, root ++ "/commands/plan.md", "# Plan\n\nPlans.\n");
    try writeFile(io, root ++ "/commands/notes.txt", "Not a command.\n");
    try writeFile(io, root ++ "/README.md", "---\ndescription: Skills for acme.\n---\n# Skills\n");
}

//
// Lays out the clone `skl add acme/skills --ns demo` scans when the package has only skills and its readme
// is `readme.md`.
//
pub fn writeSkillsOnlyPackage(io: std.Io) !void {
    const root = skills_only_package_root;
    try writeFile(io, root ++ "/skills/hello/SKILL.md", "# Hello\n\nSays hello.\n");
    try writeFile(io, root ++ "/readme.md", "# Skills\n\nSkills for acme.\n");
}

//
// Lays out the clone `skl add acme/commands --ns demo` scans when the package has only commands and no
// readme.
//
pub fn writeCommandsOnlyPackage(io: std.Io) !void {
    const root = commands_only_package_root;
    try writeFile(io, root ++ "/commands/plan.md", "# Plan\n\nPlans.\n");
}

//
// Lays out the clone `skl add acme/empty --ns demo` scans when the repository has neither `skills/` nor
// `commands/`, which is refused.
//
pub fn writeEmptyPackage(io: std.Io) !void {
    const root = empty_package_root;
    try writeFile(io, root ++ "/README.md", "# Empty\n");
}

//
// Lays out the clone `skl add acme/odd --ns demo` scans when `skills` is a file, not a directory, which is
// refused.
//
pub fn writePackageWithSkillsAsFile(io: std.Io) !void {
    const root = package_with_skills_as_file_root;
    try writeFile(io, root ++ "/skills", "Not a directory.\n");
}

//
// Writes one file in the simulated filesystem, creating the directories above it.
//
fn writeFile(io: std.Io, path: []const u8, contents: []const u8) !void {
    try files.makeParentDir(io, path);
    try files.writeFile(io, path, contents);
}

//
// Scans the package `writeFullPackage` lays out and reads its readme, as `skl add` does after a clone.
//
pub fn scanFullScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeFullPackage(context.io);
    _ = try package.scan(context.io, context.allocator, full_package_root);
    _ = try package.readmeDescription(context.io, context.allocator, full_package_root);
}

//
// Scans the package `writeSkillsOnlyPackage` lays out and reads its readme, as `skl add` does after a clone.
//
pub fn scanSkillsOnlyScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeSkillsOnlyPackage(context.io);
    _ = try package.scan(context.io, context.allocator, skills_only_package_root);
    _ = try package.readmeDescription(context.io, context.allocator, skills_only_package_root);
}

//
// Scans the package `writeCommandsOnlyPackage` lays out and reads its readme, as `skl add` does after a clone.
//
pub fn scanCommandsOnlyScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeCommandsOnlyPackage(context.io);
    _ = try package.scan(context.io, context.allocator, commands_only_package_root);
    _ = try package.readmeDescription(context.io, context.allocator, commands_only_package_root);
}

//
// Scans the package `writeEmptyPackage` lays out and reads its readme, as `skl add` does after a clone.
//
pub fn scanEmptyScenario(context: *sim.ScenarioContext) anyerror!void {
    try writeEmptyPackage(context.io);
    _ = try package.scan(context.io, context.allocator, empty_package_root);
    _ = try package.readmeDescription(context.io, context.allocator, empty_package_root);
}

//
// Scans the package `writePackageWithSkillsAsFile` lays out and reads its readme, as `skl add` does after a clone.
//
pub fn scanSkillsAsFileScenario(context: *sim.ScenarioContext) anyerror!void {
    try writePackageWithSkillsAsFile(context.io);
    _ = try package.scan(context.io, context.allocator, package_with_skills_as_file_root);
    _ = try package.readmeDescription(context.io, context.allocator, package_with_skills_as_file_root);
}
