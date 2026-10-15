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
// How a refused command says why: the failure returned in place of the exit code.
//
const failure = skilled.failure;

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
pub fn run(ctx: *const Context, args: Args) std.mem.Allocator.Error!failure.Result(u8) {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = switch (try shared.requireConfig(ctx, scope.config_path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const matched = switch (try shared.requireOneMatch(ctx.allocator, file.packages, args.query)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    return removeMatched(ctx, scope, file, matched);
}

//
// Unlinks `matched` and writes `file` back without its row. A match whose index is past the end
// of `file` names no row and is refused.
//
fn removeMatched(
    ctx: *const Context,
    scope: skilled.paths.Scope,
    file: config.File,
    matched: shared.Match,
) std.mem.Allocator.Error!failure.Result(u8) {
    //
    // A row whose directory cannot be worked out has no links of ours to remove, so its row is
    // still dropped.
    //
    const dest: ?[]const u8 = switch (try shared.contentDir(ctx, matched.pkg)) {
        .ok => |path| path,
        .failed => null,
    };
    if (dest) |path| {
        switch (try link.unlinkPackage(ctx.io, ctx.allocator, path, matched.pkg.namespace, scope)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }

    const remaining = dropIndex(ctx.allocator, file.packages, matched.index) catch |err| switch (err) {
        error.IndexNotFound => return .{
            .failed = failure.because("The package to remove is no longer in {s}.", .{scope.config_path}),
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    switch (try config.writeFile(ctx.io, ctx.allocator, scope.config_path, .{
        .packages = remaining,
    })) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (shared.line(ctx, "{s} Removed {s}.", .{ ctx.style.check(), try shared.identifier(ctx, matched.pkg.repo) })) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .{
        .ok = 0,
    };
}

//
// Builds the `remove` command.
//
pub fn buildCommand(ctx: *const Context) std.mem.Allocator.Error!*Command {
    return (try Command.init(ctx.allocator, "remove"))
        .description("Unlink a package and drop its YAML entry.")
        .argument("<query>", "Repo string, owner/repo, name, or namespace.")
        .action(ctx, action);
}

//
// Packages without the entry at index, in the original order. An index past the end names no entry
// and is refused with `error.IndexNotFound`, before anything is allocated.
//
pub fn dropIndex(allocator: std.mem.Allocator, packages: []const config.Package, index: usize) (error{IndexNotFound} || std.mem.Allocator.Error)![]config.Package {
    if (index >= packages.len) {
        return error.IndexNotFound;
    }
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
fn action(invocation: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    if (invocation.args.len == 0) {
        return .{
            .failed = failure.because("The remove command requires a query.", .{}),
        };
    }
    return run(ctx, .{
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
