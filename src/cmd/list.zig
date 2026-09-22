//
// `skl list`: print each YAML package and its skills/commands as `ns:name`.
//
// A missing store clone still prints the YAML row; the item list is empty with a note that it is
// not installed. The scratch directory is printed after the packages, under its own namespace, so
// what the agents can see is one list rather than two commands.
//

const std = @import("std");
const skilled = @import("skilled");

const context_mod = @import("context.zig");
const shared = @import("shared.zig");

//
// The command line library this definition is written against.
//
const commander = skilled.commander;

//
// Package description and skill/command items, when the clone exists.
//
const package = skilled.package;

//
// The scratch namespace, for the section printed after the packages.
//
const scratch = skilled.scratch;

//
// The run values this command was given.
//
const Context = context_mod.Context;

//
// The Commander command type, aliased so the builder chain stays short.
//
const Command = commander.Command;

//
// What this invocation of `list` asked for, unpacked from Commander.
//
pub const Args = struct {
    //
    // `-g` / `--global`: project vs machine YAML and agent roots.
    //
    global: bool = false,
};

//
// Prints every package in the active YAML.
//
pub fn run(ctx: *const Context, args: Args) skilled.failure.Error!u8 {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = try shared.requireConfig(ctx, scope.config_path);

    if (file.packages.len == 0) {
        try shared.line(ctx, "no packages", .{});
        try printScratch(ctx, scope);
        return 0;
    }

    for (file.packages) |pkg| {
        try printPackage(ctx, pkg);
    }
    try printScratch(ctx, scope);
    return 0;
}

//
// Builds the `list` command.
//
pub fn buildCommand(ctx: *const Context) *Command {
    return Command.init(ctx.allocator, "list")
        .description("Print packages and each skill/command as ns:name.")
        .action(ctx, action);
}

//
// One YAML row, plus items when the package directory is present.
//
fn printPackage(ctx: *const Context, pkg: skilled.config.Package) skilled.failure.Error!void {
    var parse_fail = skilled.failure.Failure.init(ctx.allocator);
    const parsed = skilled.remote.parse(ctx.allocator, pkg.repo, &parse_fail) catch null;
    const name = if (parsed) |remote| remote.repo else pkg.repo;

    const title = try shared.paint(ctx.allocator, ctx.style, "1;36", name);
    if (pkg.local) |local_path| {
        try shared.line(ctx, "{s} {s}  {s}  {s}  {s}", .{ ctx.style.package(), title, pkg.namespace, pkg.repo, local_path });
    } else if (pkg.branch) |branch| {
        try shared.line(ctx, "{s} {s}  {s}  {s}  {s}", .{ ctx.style.package(), title, pkg.namespace, pkg.repo, branch });
    } else {
        try shared.line(ctx, "{s} {s}  {s}  {s}", .{ ctx.style.package(), title, pkg.namespace, pkg.repo });
    }

    const dest = shared.contentDir(ctx, pkg) catch |err| switch (err) {
        error.Failed => {
            try shared.line(ctx, "  not installed", .{});
            return;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (!shared.dirExists(ctx.io, dest)) {
        try shared.line(ctx, "  not installed", .{});
        return;
    }

    if (try package.readmeDescription(ctx.io, ctx.allocator, dest, ctx.fail)) |description| {
        const dim = try shared.paint(ctx.allocator, ctx.style, "2", description);
        try shared.line(ctx, "  {s}", .{dim});
    }

    var scan_fail = skilled.failure.Failure.init(ctx.allocator);
    const items = package.scan(ctx.io, ctx.allocator, dest, &scan_fail) catch {
        try shared.line(ctx, "  not installed", .{});
        return;
    };
    try printItems(ctx, pkg.namespace, items);
}

//
// The scratch directory and its items, printed in the same shape as a package.
//
// Nothing is printed when the directory is not there: a scope where init and install have not run
// has no scratch directory to describe, and list is not the command that creates it. A scan that
// fails (a tree removed by hand) prints the heading only rather than failing the whole listing.
//
fn printScratch(ctx: *const Context, scope: skilled.paths.Scope) skilled.failure.Error!void {
    if (!shared.dirExists(ctx.io, scope.scratch_dir)) {
        return;
    }

    const title = try shared.paint(ctx.allocator, ctx.style, "1;36", "scratch");
    try shared.line(ctx, "{s} {s}  {s}  {s}", .{
        ctx.style.package(),
        title,
        scratch.namespace,
        scope.scratch_dir,
    });

    var scan_fail = skilled.failure.Failure.init(ctx.allocator);
    const items = package.scan(ctx.io, ctx.allocator, scope.scratch_dir, &scan_fail) catch return;
    try printItems(ctx, scratch.namespace, items);
}

//
// The `ns:name` lines under a package or the scratch directory.
//
// Shared so a scratch item and a package item cannot drift into two layouts.
//
fn printItems(ctx: *const Context, namespace: []const u8, items: []const package.Item) skilled.failure.Error!void {
    for (items) |item| {
        const id = try std.fmt.allocPrint(ctx.allocator, "{s}:{s}", .{ namespace, item.name });
        if (item.description.len == 0) {
            try shared.line(ctx, "  {s}", .{id});
        } else {
            try shared.line(ctx, "  {s}  {s}", .{ id, item.description });
        }
    }
}

//
// Unpacks Commander options and runs list.
//
fn action(invocation: *commander.Invocation) anyerror!void {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    invocation.exit_code = try run(ctx, .{
        .global = invocation.option("global") != null,
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("list.test.zig");
}
