//
// `skl init`: create skl.yaml in the active scope, empty or from `--from`.
//
// Plain init writes `packages: []` when the file is missing. `--from` fills a missing or empty
// file from a YAML file in git, then installs those packages. Neither form wipes a list the user
// already built.
//

const skilled = @import("skilled");

const context_mod = @import("context.zig");
const shared = @import("shared.zig");

//
// The command line library this definition is written against.
//
const commander = skilled.commander;

//
// Empty-file YAML shape this command writes, and the target `--from` fills.
//
const config = skilled.config;

//
// Bounded filesystem helpers, used to see whether the config path already exists.
//
const files = skilled.files;

//
// Spec parse, throwaway clone, and YAML load for `--from`.
//
const from = skilled.from;

//
// The run values this command was given.
//
const Context = context_mod.Context;

//
// The Commander command type, aliased so the builder chain stays short.
//
const Command = commander.Command;

//
// What this invocation of `init` asked for, unpacked from Commander.
//
pub const Args = struct {
    //
    // `-g` / `--global`: write the machine config instead of `./skl.yaml`.
    //
    global: bool = false,

    //
    // `--from <spec>`. When set, the file is created or filled from that YAML.
    //
    from: ?[]const u8 = null,
};

//
// Writes skl.yaml with `packages: []` when the file is missing.
//
// An existing file is left alone: empty or already listing packages. `--from` is the exception
// that may fill a missing or empty file; a non-empty list is still refused.
//
pub fn run(ctx: *const Context, args: Args) skilled.failure.Error!u8 {
    if (args.from) |spec| {
        return runFrom(ctx, args.global, spec);
    }
    const scope = try shared.scopeOf(ctx, args.global);
    if (!files.fileExists(ctx.io, scope.config_path)) {
        try config.writeFile(ctx.io, ctx.allocator, scope.config_path, .{ .packages = &.{} }, ctx.fail);
        try shared.line(ctx, "wrote {s}", .{scope.config_path});
        return 0;
    }
    const file = try config.readFile(ctx.io, ctx.allocator, scope.config_path, ctx.fail);
    if (file.packages.len == 0) {
        try shared.line(ctx, "{s} already exists", .{scope.config_path});
        return 0;
    }
    try shared.line(ctx, "{s} already lists packages; not overwritten", .{scope.config_path});
    return 0;
}

//
// Builds the `init` command.
//
pub fn buildCommand(ctx: *const Context) *Command {
    return Command.init(ctx.allocator, "init")
        .description("Create skl.yaml with packages: [].")
        .option("--from <spec>", "A YAML file inside a git repo; also install its packages.", null)
        .action(ctx, action);
}

//
// Fetches YAML, writes it when the config is missing or still `packages: []`, then installs.
//
fn runFrom(ctx: *const Context, global: bool, spec: []const u8) skilled.failure.Error!u8 {
    const scope = try shared.scopeOf(ctx, global);
    if (files.fileExists(ctx.io, scope.config_path)) {
        const existing = try config.readFile(ctx.io, ctx.allocator, scope.config_path, ctx.fail);
        if (existing.packages.len != 0) {
            return ctx.fail.set("{s} already lists packages; use skl add --from", .{scope.config_path});
        }
    }
    const fetched = try from.fetchConfig(ctx.io, ctx.allocator, ctx.environ, ctx.git, spec, ctx.fail);
    try config.writeFile(ctx.io, ctx.allocator, scope.config_path, fetched, ctx.fail);
    try shared.line(ctx, "wrote {s}", .{scope.config_path});
    return shared.installAll(ctx, scope, fetched);
}

//
// Unpacks Commander options and runs init.
//
fn action(invocation: *commander.Invocation) anyerror!void {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    invocation.exit_code = try run(ctx, .{
        .global = invocation.option("global") != null,
        .from = invocation.option("from"),
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("init.test.zig");
}
