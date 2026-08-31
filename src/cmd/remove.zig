//
// `skl remove`: unlink a namespace and drop that YAML entry. The store clone stays.
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
// YAML rewrite after the entry is dropped.
//
const config = skilled.config;

//
// Removes skills/ns and commands/ns when they belong to this package.
//
const link = skilled.link;

//
// The run values this command was given.
//
const Context = context_mod.Context;

//
// The Commander command type, aliased so the builder chain stays short.
//
const Command = commander.Command;

//
// What this invocation of `remove` asked for, unpacked from Commander.
//
pub const Args = struct {
    //
    // `-g` / `--global`: project vs machine YAML and agent roots.
    //
    global: bool = false,

    //
    // Repo string, owner/repo, name, or namespace. Required.
    //
    query: []const u8,
};

//
// Unlinks the matched package and removes that one YAML row.
//
pub fn run(ctx: *const Context, args: Args) skilled.failure.Error!u8 {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = try shared.requireConfig(ctx, scope.config_path);
    const matched = try shared.requireOneMatch(ctx.allocator, file.packages, args.query, ctx.fail);

    const dest = shared.contentDir(ctx, matched.pkg) catch |err| switch (err) {
        error.Failed => null,
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (dest) |path| {
        try link.unlinkPackage(ctx.io, ctx.allocator, path, matched.pkg.namespace, scope, ctx.fail);
    }

    const remaining = try dropIndex(ctx.allocator, file.packages, matched.index);
    try config.writeFile(ctx.io, ctx.allocator, scope.config_path, .{ .packages = remaining }, ctx.fail);
    try shared.line(ctx, "{s} removed {s}", .{ ctx.style.check(), matched.pkg.repo });
    return 0;
}

//
// Builds the `remove` command.
//
pub fn buildCommand(ctx: *const Context) *Command {
    return Command.init(ctx.allocator, "remove")
        .description("Unlink a package and drop its YAML entry.")
        .argument("<query>", "Repo string, owner/repo, name, or namespace.")
        .action(ctx, action);
}

//
// Packages without the entry at index, in the original order.
//
fn dropIndex(allocator: std.mem.Allocator, packages: []const config.Package, index: usize) std.mem.Allocator.Error![]config.Package {
    const remaining = try allocator.alloc(config.Package, packages.len - 1);
    var out: usize = 0;
    for (packages, 0..) |pkg, i| {
        if (i == index) {
            continue;
        }
        remaining[out] = pkg;
        out += 1;
    }
    return remaining;
}

//
// Unpacks Commander options and runs remove.
//
fn action(invocation: *commander.Invocation) anyerror!void {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    if (invocation.args.len == 0) {
        return ctx.fail.set("remove requires a query", .{});
    }
    invocation.exit_code = try run(ctx, .{
        .global = invocation.option("global") != null,
        .query = invocation.args[0],
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("remove.test.zig");
}
