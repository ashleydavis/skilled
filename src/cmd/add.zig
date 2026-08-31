//
// `skl add`: clone or link a local tree, scan, append YAML, then link — or append YAML from `--from`.
//
// Clone and scan run before any YAML write. `--branch` clones that branch; `--local` links a
// working tree instead of cloning. `--from` fetches a YAML file in git and merges it; it does not
// clone skill packages or create links.
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
// YAML read/write after a successful scan or `--from` merge.
//
const config = skilled.config;

//
// Spec parse, throwaway clone, YAML load, and package-list merge for `--from`.
//
const from = skilled.from;

//
// Namespace symlinks into Cursor and Claude.
//
const link = skilled.link;

//
// Layout check that decides whether the clone is a valid package.
//
const package = skilled.package;

//
// Namespace validation, the same rule host/owner/repo already used.
//
const remote = skilled.remote;

//
// The run values this command was given.
//
const Context = context_mod.Context;

//
// The Commander command type, aliased so the builder chain stays short.
//
const Command = commander.Command;

//
// What this invocation of `add` asked for, unpacked from Commander.
//
pub const Args = struct {
    //
    // `-g` / `--global`: project vs machine YAML and agent roots.
    //
    global: bool = false,

    //
    // The `[repo]` positional. Null when the user passed `--from` instead.
    //
    repo: ?[]const u8 = null,

    //
    // `--ns <namespace>`. Null means prompt when interactive, error when not.
    //
    namespace: ?[]const u8 = null,

    //
    // `--from <spec>`. Mutually exclusive with `<repo>` and `--ns`.
    //
    from: ?[]const u8 = null,

    //
    // `--branch <name>`. Null means the remote's default branch. Mutually exclusive with `--local`.
    //
    branch: ?[]const u8 = null,

    //
    // `--local <path>`. Null means clone into the store. Mutually exclusive with `--branch`.
    //
    local: ?[]const u8 = null,
};

//
// Adds one package, or merges packages from `--from`.
//
// Non-interactive without `--ns` errors (no hang). Interactive without `--ns` prompts. A failed
// clone or scan leaves the YAML unchanged. A clone of an invalid package may leave a store dest.
// `--from` does not clone skill packages or link; the user runs `skl install`.
//
pub fn run(ctx: *const Context, args: Args) skilled.failure.Error!u8 {
    if (args.from) |spec| {
        if (args.repo != null) {
            return ctx.fail.set("add --from cannot be used with a repo", .{});
        }
        if (args.namespace != null) {
            return ctx.fail.set("--ns is not used with --from", .{});
        }
        if (args.branch != null) {
            return ctx.fail.set("--branch is not used with --from", .{});
        }
        if (args.local != null) {
            return ctx.fail.set("--local is not used with --from", .{});
        }
        return runFrom(ctx, args.global, spec);
    }
    if (args.branch != null and args.local != null) {
        return ctx.fail.set("--branch cannot be used with --local", .{});
    }
    const spec = args.repo orelse return ctx.fail.set("add requires a repo or --from", .{});

    const scope = try shared.scopeOf(ctx, args.global);
    const file = try shared.requireConfig(ctx, scope.config_path);

    const namespace = try resolveNamespace(ctx, args.namespace);
    try remote.validateName(namespace, "namespace", ctx.fail);
    if (shared.namespaceTaken(file.packages, namespace)) |taken| {
        return ctx.fail.set("namespace \"{s}\" is already used by {s}", .{ namespace, taken.repo });
    }

    var spinner = shared.newSpinner(ctx);
    defer spinner.finish();

    if (args.local) |local_path| {
        const dest = try shared.resolveLocal(ctx, local_path);
        const appended = try appendPackage(ctx.allocator, file, .{
            .repo = spec,
            .namespace = namespace,
            .local = dest,
        });
        try config.writeFile(ctx.io, ctx.allocator, scope.config_path, appended, ctx.fail);
        spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ namespace, spec }));
        try link.linkPackage(ctx.io, ctx.allocator, dest, namespace, scope, ctx.fail);
        spinner.finish();
        try shared.line(ctx, "{s} {s} -> {s}", .{ ctx.style.check(), spec, namespace });
        return 0;
    }

    const resolved = try shared.ensureCloned(ctx, spec, args.branch, &spinner);
    _ = try package.scan(ctx.io, ctx.allocator, resolved.dest, ctx.fail);

    const appended = try appendPackage(ctx.allocator, file, .{
        .repo = spec,
        .namespace = namespace,
        .branch = args.branch,
    });
    try config.writeFile(ctx.io, ctx.allocator, scope.config_path, appended, ctx.fail);

    spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ namespace, resolved.parsed.repo }));
    try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, namespace, scope, ctx.fail);
    spinner.finish();

    try shared.line(ctx, "{s} {s}/{s} -> {s}", .{
        ctx.style.check(),
        resolved.parsed.owner,
        resolved.parsed.repo,
        namespace,
    });
    return 0;
}

//
// Builds the `add` command. `[repo]` is optional so `--from` can occupy the line.
//
pub fn buildCommand(ctx: *const Context) *Command {
    return Command.init(ctx.allocator, "add")
        .description("Clone a package, append YAML, and link it.")
        .argument("[repo]", "The package to add.")
        .option("--ns <namespace>", "The namespace to install under.", null)
        .option("--from <spec>", "A YAML file inside a git repo.", null)
        .option("--branch <name>", "Clone this branch instead of the default.", null)
        .option("--local <path>", "Link a local working tree instead of cloning.", null)
        .action(ctx, action);
}

//
// `--ns` when given, a prompt when interactive, or an error that names `--ns`.
//
fn resolveNamespace(ctx: *const Context, namespace_opt: ?[]const u8) skilled.failure.Error![]const u8 {
    if (namespace_opt) |ns| {
        if (ns.len == 0) {
            return ctx.fail.set("--ns is required", .{});
        }
        return ns;
    }
    if (ctx.non_interactive) {
        return ctx.fail.set("--ns is required", .{});
    }
    shared.promptWrite(ctx, "Namespace: ", .{});
    const ns = try shared.promptLine(ctx);
    if (ns.len == 0) {
        return ctx.fail.set("--ns is required", .{});
    }
    return ns;
}

//
// Existing packages plus one new entry, allocated as a single slice.
//
fn appendPackage(
    allocator: std.mem.Allocator,
    file: config.File,
    pkg: config.Package,
) std.mem.Allocator.Error!config.File {
    const packages = try allocator.alloc(config.Package, file.packages.len + 1);
    for (file.packages, 0..) |existing, i| {
        packages[i] = existing;
    }
    packages[file.packages.len] = pkg;
    return .{ .packages = packages };
}

//
// Appends packages from a YAML file in git into an existing skl.yaml. Does not clone or link.
//
fn runFrom(ctx: *const Context, global: bool, spec: []const u8) skilled.failure.Error!u8 {
    const scope = try shared.scopeOf(ctx, global);
    const file = try shared.requireConfig(ctx, scope.config_path);
    const fetched = try from.fetchConfig(ctx.io, ctx.allocator, ctx.environ, ctx.git, spec, ctx.fail);
    const merged = try from.mergePackages(ctx.allocator, file.packages, fetched.packages, ctx.fail);
    try config.writeFile(ctx.io, ctx.allocator, scope.config_path, .{ .packages = merged }, ctx.fail);
    try shared.line(ctx, "updated {s}", .{scope.config_path});
    return 0;
}

//
// Unpacks Commander options and runs add.
//
fn action(invocation: *commander.Invocation) anyerror!void {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    invocation.exit_code = try run(ctx, .{
        .global = invocation.option("global") != null,
        .repo = if (invocation.args.len > 0) invocation.args[0] else null,
        .namespace = invocation.option("ns"),
        .from = invocation.option("from"),
        .branch = invocation.option("branch"),
        .local = invocation.option("local"),
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("add.test.zig");
}
