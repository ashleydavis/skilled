//
// `skl list`: print each YAML package and its skills/commands as `ns:name`.
//
// A missing store clone still prints the YAML row; the item list is empty with a note that it is
// not installed.
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
        return 0;
    }

    for (file.packages) |pkg| {
        try printPackage(ctx, pkg);
    }
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
// One YAML row, plus items when the store clone is present.
//
fn printPackage(ctx: *const Context, pkg: skilled.config.Package) skilled.failure.Error!void {
    var parse_fail = skilled.failure.Failure.init(ctx.allocator);
    const parsed = skilled.remote.parse(ctx.allocator, pkg.repo, &parse_fail) catch null;
    const name = if (parsed) |remote| remote.repo else pkg.repo;

    const title = try shared.paint(ctx.allocator, ctx.style, "1;36", name);
    try shared.line(ctx, "{s} {s}  {s}  {s}", .{ ctx.style.package(), title, pkg.namespace, pkg.repo });

    const resolved = shared.resolveStore(ctx, pkg.repo) catch |err| switch (err) {
        error.Failed => {
            try shared.line(ctx, "  not installed", .{});
            return;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (!shared.dirExists(ctx.io, resolved.dest)) {
        try shared.line(ctx, "  not installed", .{});
        return;
    }

    if (try package.readmeDescription(ctx.io, ctx.allocator, resolved.dest, ctx.fail)) |description| {
        const dim = try shared.paint(ctx.allocator, ctx.style, "2", description);
        try shared.line(ctx, "  {s}", .{dim});
    }

    var scan_fail = skilled.failure.Failure.init(ctx.allocator);
    const items = package.scan(ctx.io, ctx.allocator, resolved.dest, &scan_fail) catch {
        try shared.line(ctx, "  not installed", .{});
        return;
    };
    for (items) |item| {
        const id = try std.fmt.allocPrint(ctx.allocator, "{s}:{s}", .{ pkg.namespace, item.name });
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
