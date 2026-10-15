//
// The test input factories for the process `main` is started with, one per `skl` command line, so
// Faultline calls `main` and through it every command's action.
//
// Each scenario lays out the project with one package and starts `main` in it with one of these.
// The command lines that get furthest come first, because Faultline's first call to a function
// uses the first factory for each parameter.
//

const std = @import("std");

//
// The project with one package, which the scenarios lay out in Faultline's simulated filesystem.
//
const global_sim = @import("cmd/global.sim.zig");

//
// The file whose `main` the scenarios start.
//
const main = @import("main.zig");

//
// What a scenario is given: the simulated world and the expectations it checks.
//
const sim = @import("sim");

//
// `skl add acme/skills --ns demo2`.
//
pub fn addProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "add", "acme/skills", "--ns", "demo2" });
}

//
// `skl list`.
//
pub fn listProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "list" });
}

//
// `skl install`.
//
pub fn installProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "install" });
}

//
// `skl remove demo`.
//
pub fn removeProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "remove", "demo" });
}

//
// `skl update`.
//
pub fn updateProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "update" });
}

//
// `skl docs demo`.
//
pub fn docsProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "docs", "demo" });
}

//
// `skl init`, in a project that already has an `skl.yaml`.
//
pub fn initProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "init" });
}

//
// `skl --version`.
//
pub fn versionProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "--version" });
}

//
// `skl --help`.
//
pub fn helpProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "--help" });
}

//
// `skl nope`, a command that does not exist, which is refused.
//
pub fn unknownCommandProcess(allocator: std.mem.Allocator, io: std.Io) !std.process.Init {
    return process(allocator, io, &.{ "skl", "nope" });
}

//
// The process `argv` is started with: the arena, the environment map and the arguments, all created
// in one allocation from the allocator Faultline passes in.
//
fn process(allocator: std.mem.Allocator, io: std.Io, comptime argv: []const [*:0]const u8) !std.process.Init {
    const parts = try allocator.create(struct {
        arena: std.heap.ArenaAllocator,
        environ: std.process.Environ.Map,
    });
    parts.arena = .init(allocator);
    parts.environ = .init(allocator);
    try parts.environ.put("HOME", "/home/skilled");
    return .{
        .minimal = .{
            .environ = .empty,
            .args = .{
                .vector = argv,
            },
        },
        .arena = &parts.arena,
        .gpa = allocator,
        .io = io,
        .environ_map = &parts.environ,
        .preopens = .empty,
    };
}

//
// `main` started with `addProcess` in `/home/skilled/project`, a project with one package.
//
pub fn addProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try addProcess(context.allocator, context.io));
}

//
// `main` started with `listProcess` in `/home/skilled/project`, a project with one package.
//
pub fn listProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try listProcess(context.allocator, context.io));
}

//
// `main` started with `installProcess` in `/home/skilled/project`, a project with one package.
//
pub fn installProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try installProcess(context.allocator, context.io));
}

//
// `main` started with `removeProcess` in `/home/skilled/project`, a project with one package.
//
pub fn removeProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try removeProcess(context.allocator, context.io));
}

//
// `main` started with `updateProcess` in `/home/skilled/project`, a project with one package.
//
pub fn updateProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try updateProcess(context.allocator, context.io));
}

//
// `main` started with `docsProcess` in `/home/skilled/project`, a project with one package.
//
pub fn docsProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try docsProcess(context.allocator, context.io));
}

//
// `main` started with `initProcess` in `/home/skilled/project`, a project with one package.
//
pub fn initProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try initProcess(context.allocator, context.io));
}

//
// `main` started with `versionProcess` in `/home/skilled/project`, a project with one package.
//
pub fn versionProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try versionProcess(context.allocator, context.io));
}

//
// `main` started with `helpProcess` in `/home/skilled/project`, a project with one package.
//
pub fn helpProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try helpProcess(context.allocator, context.io));
}

//
// `main` started with `unknownCommandProcess` in `/home/skilled/project`, a project with one package.
//
pub fn unknownCommandProcessScenario(context: *sim.ScenarioContext) anyerror!void {
    try global_sim.writeOnePackage(context.allocator, context.io);
    try std.process.setCurrentPath(context.io, "/home/skilled/project");
    _ = main.main(try unknownCommandProcess(context.allocator, context.io));
}
