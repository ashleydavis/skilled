//
// `skl install` / `skl i`: clone missing packages and link every namespace in the active YAML.
//
// Idempotent. On package *k* of *N* failing, packages 1..k-1 stay cloned and linked; there is no
// rollback. The next install continues the rest. The scratch directory is created and linked
// first, so this is also the command that repairs it.
//

const skilled = @import("skilled");

const context_mod = @import("context.zig");
const shared = @import("shared.zig");

//
// The command line library this definition is written against.
//
const commander = skilled.commander;

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
    //
    // Before the packages, so a refused scratch link stops the run rather than leaving half the
    // namespaces linked, and so a config with no packages still gets its scratch directory.
    //
    try shared.syncScratch(ctx, scope);
    return shared.installAll(ctx, scope, file);
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
