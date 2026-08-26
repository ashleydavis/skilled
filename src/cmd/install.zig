//
// `skl install` / `skl i`: clone missing packages and link every namespace in the active YAML.
//
// Idempotent. On package *k* of *N* failing, packages 1..k-1 stay cloned and linked; there is no
// rollback. The next install continues the rest.
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
// Namespace symlinks into Cursor and Claude.
//
const link = skilled.link;

//
// Layout check after clone, so an empty package fails this entry rather than linking nothing.
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
// What this invocation of `install` asked for, unpacked from Commander.
//
pub const Args = struct {
    //
    // `-g` / `--global`: project vs machine YAML and agent roots.
    //
    global: bool = false,
};

//
// Clones missing packages and links each namespace in the active config.
//
pub fn run(ctx: *const Context, args: Args) skilled.failure.Error!u8 {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = try shared.requireConfig(ctx, scope.config_path);

    var spinner = shared.newSpinner(ctx);
    defer spinner.finish();

    for (file.packages) |pkg| {
        var one_fail = skilled.failure.Failure.init(ctx.allocator);
        var one_ctx = ctx.*;
        one_ctx.fail = &one_fail;
        installOne(&one_ctx, scope, pkg, &spinner) catch {
            return ctx.fail.set("install failed on {s}: {s}", .{ pkg.repo, one_fail.text() });
        };
    }
    return 0;
}

//
// Builds the `install` command, aliased as `i`.
//
pub fn buildCommand(ctx: *const Context) *Command {
    return Command.init(ctx.allocator, "install")
        .description("Clone and link every package in skl.yaml.")
        .alias("i")
        .action(ctx, action);
}

//
// Clone if missing, scan, then link. A Failure from a helper is left as-is; run wraps it.
//
fn installOne(
    ctx: *const Context,
    scope: skilled.paths.Scope,
    pkg: skilled.config.Package,
    spinner: *skilled.progress.Progress,
) skilled.failure.Error!void {
    const resolved = try shared.ensureCloned(ctx, pkg.repo, spinner);
    _ = try package.scan(ctx.io, ctx.allocator, resolved.dest, ctx.fail);
    spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ pkg.namespace, resolved.parsed.repo }));
    try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, pkg.namespace, scope, ctx.fail);
    spinner.finish();
    try shared.line(ctx, "{s} {s}", .{ ctx.style.check(), pkg.repo });
}

//
// Unpacks Commander options and runs install.
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
    _ = @import("install.test.zig");
}
