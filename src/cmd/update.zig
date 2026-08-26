//
// `skl update`: fast-forward store clones and repair missing links.
//
// Dirty, detached, diverged, or missing-upstream trees are an error for that package. There is no
// reset. Store-dir symlinks already show new files after a fast-forward; linkPackage still runs so
// a missing link is repaired.
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
// fetchUpdate and HEAD, via the injected runner.
//
const git = skilled.git;

//
// Idempotent repair of namespace links after a fast-forward.
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
// What this invocation of `update` asked for, unpacked from Commander.
//
pub const Args = struct {
    //
    // `-g` / `--global`: project vs machine YAML and agent roots.
    //
    global: bool = false,

    //
    // One package to update, or null to update every package in the active YAML.
    //
    query: ?[]const u8 = null,
};

//
// Updates one package or every package in the active YAML.
//
pub fn run(ctx: *const Context, args: Args) skilled.failure.Error!u8 {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = try shared.requireConfig(ctx, scope.config_path);

    if (args.query) |q| {
        const matched = try shared.requireOneMatch(ctx.allocator, file.packages, q, ctx.fail);
        try updateOne(ctx, scope, matched.pkg);
        return 0;
    }

    for (file.packages) |pkg| {
        var one_fail = skilled.failure.Failure.init(ctx.allocator);
        var one_ctx = ctx.*;
        one_ctx.fail = &one_fail;
        updateOne(&one_ctx, scope, pkg) catch {
            return ctx.fail.set("update failed on {s}: {s}", .{ pkg.repo, one_fail.text() });
        };
    }
    return 0;
}

//
// Builds the `update` command.
//
pub fn buildCommand(ctx: *const Context) *Command {
    return Command.init(ctx.allocator, "update")
        .description("Fast-forward store clones and repair links.")
        .argument("[repo]", "One package, or every package when omitted.")
        .action(ctx, action);
}

//
// fetchUpdate, print SHA change, then linkPackage.
//
fn updateOne(ctx: *const Context, scope: skilled.paths.Scope, pkg: skilled.config.Package) skilled.failure.Error!void {
    const resolved = try shared.resolveStore(ctx, pkg.repo);
    if (!shared.dirExists(ctx.io, resolved.dest)) {
        return ctx.fail.set("{s} is not installed; run skl install", .{pkg.repo});
    }

    const old_sha = try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest, ctx.fail);
    try git.fetchUpdate(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest, ctx.fail);
    const new_sha = try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest, ctx.fail);

    try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, pkg.namespace, scope, ctx.fail);

    if (std.mem.eql(u8, old_sha, new_sha)) {
        try shared.line(ctx, "{s}  unchanged", .{resolved.parsed.repo});
    } else {
        try shared.line(ctx, "{s}  {s} {s} {s}", .{
            resolved.parsed.repo,
            old_sha,
            ctx.style.arrow(),
            new_sha,
        });
    }
}

//
// Unpacks Commander options and runs update.
//
fn action(invocation: *commander.Invocation) anyerror!void {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    invocation.exit_code = try run(ctx, .{
        .global = invocation.option("global") != null,
        .query = if (invocation.args.len > 0) invocation.args[0] else null,
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("update.test.zig");
}
