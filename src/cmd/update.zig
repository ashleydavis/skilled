//
// `skl update`: fast-forward store clones, switch branch/local, and repair missing links.
//
// Without `--branch` / `--local` it also creates and links the scratch directory, because that is
// the same repair.
//
// Dirty, detached, diverged, or missing-upstream trees are an error for a remote package. There
// is no reset. `--branch` / `--local` rewrite that YAML row and retarget namespace links.
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
// YAML rewrite when `--branch` or `--local` changes a row's source.
//
const config = skilled.config;

//
// fetchUpdate, checkout, and HEAD, via the injected runner.
//
const git = skilled.git;

//
// Idempotent repair of namespace links after a fast-forward or source switch.
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

    //
    // `--branch <name>`. Requires `query`. Mutually exclusive with `--local`.
    //
    branch: ?[]const u8 = null,

    //
    // `--local <path>`. Requires `query`. Mutually exclusive with `--branch`.
    //
    local: ?[]const u8 = null,
};

//
// Updates one package or every package in the active YAML.
//
pub fn run(ctx: *const Context, args: Args) skilled.failure.Error!u8 {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = try shared.requireConfig(ctx, scope.config_path);

    if (args.branch != null and args.local != null) {
        return ctx.fail.set("The --branch flag cannot be used with --local.", .{});
    }
    if (args.branch != null or args.local != null) {
        const q = args.query orelse {
            if (args.branch != null) {
                return ctx.fail.set("The update --branch flag requires a package query.", .{});
            }
            return ctx.fail.set("The update --local flag requires a package query.", .{});
        };
        const matched = try shared.requireOneMatch(ctx.allocator, file.packages, q, ctx.fail);
        if (args.local) |local_path| {
            try switchToLocal(ctx, scope, file, matched, local_path);
        } else {
            try switchToBranch(ctx, scope, file, matched, args.branch.?);
        }
        return 0;
    }

    //
    // Without the source flags this is the "repair missing links" command, so the scratch links are
    // repaired too. `--branch` and `--local` are about one named package and leave it alone.
    //
    try shared.syncScratch(ctx, scope);

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
            return ctx.fail.set("Update failed on {s}: {s}", .{ pkg.repo, one_fail.text() });
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
        .option("--branch <name>", "Check out this branch and relink the store.", null)
        .option("--local <path>", "Link a local working tree instead of the store.", null)
        .action(ctx, action);
}

//
// fetchUpdate, print SHA change, then linkPackage — or repair a `local:` row with no fetch.
//
fn updateOne(ctx: *const Context, scope: skilled.paths.Scope, pkg: skilled.config.Package) skilled.failure.Error!void {
    if (pkg.local) |local_path| {
        const dest = try shared.resolveLocal(ctx, local_path);
        _ = try link.linkPackage(ctx.io, ctx.allocator, dest, pkg.namespace, scope, ctx.fail);
        try shared.line(ctx, "{s} is linked to the local tree at {s}.", .{
        try shared.identifier(ctx, pkg.repo),
        try shared.muted(ctx, dest),
    });
        return;
    }

    const resolved = try shared.resolveStore(ctx, pkg.repo);
    if (!shared.dirExists(ctx.io, resolved.dest)) {
        return ctx.fail.set("Package {s} is not installed; run skl install.", .{pkg.repo});
    }

    const old_sha = try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest, ctx.fail);
    try git.fetchUpdate(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest, ctx.fail);
    const new_sha = try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest, ctx.fail);

    _ = try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, pkg.namespace, scope, ctx.fail);
    try printShaLine(ctx, pkg.repo, old_sha, new_sha);
}

//
// Clears `branch`, writes absolute `local`, and retargets agent links at that path.
//
fn switchToLocal(
    ctx: *const Context,
    scope: skilled.paths.Scope,
    file: config.File,
    matched: shared.Match,
    local_path: []const u8,
) skilled.failure.Error!void {
    const dest = try shared.resolveLocal(ctx, local_path);
    var pkg = matched.pkg;
    pkg.local = dest;
    pkg.branch = null;
    const rewritten = try replacePackage(ctx.allocator, file, matched.index, pkg);
    try config.writeFile(ctx.io, ctx.allocator, scope.config_path, rewritten, ctx.fail);
    _ = try link.linkPackage(ctx.io, ctx.allocator, dest, pkg.namespace, scope, ctx.fail);
    try shared.line(ctx, "{s} is linked to the local tree at {s}.", .{
        try shared.identifier(ctx, pkg.repo),
        try shared.muted(ctx, dest),
    });
}

//
// Clears `local`, writes `branch`, clones or checks out, and relinks at the store dest.
//
fn switchToBranch(
    ctx: *const Context,
    scope: skilled.paths.Scope,
    file: config.File,
    matched: shared.Match,
    branch: []const u8,
) skilled.failure.Error!void {
    const resolved_store = try shared.resolveStore(ctx, matched.pkg.repo);
    const dest_existed = shared.dirExists(ctx.io, resolved_store.dest);
    const old_sha: ?[]const u8 = if (dest_existed)
        try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved_store.dest, ctx.fail)
    else
        null;

    var spinner = shared.newSpinner(ctx);
    defer spinner.finish();
    const resolved = try shared.ensureCloned(ctx, matched.pkg.repo, branch, &spinner);
    _ = try skilled.package.scan(ctx.io, ctx.allocator, resolved.dest, ctx.fail);

    var pkg = matched.pkg;
    pkg.branch = branch;
    pkg.local = null;
    const rewritten = try replacePackage(ctx.allocator, file, matched.index, pkg);
    try config.writeFile(ctx.io, ctx.allocator, scope.config_path, rewritten, ctx.fail);
    _ = try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, pkg.namespace, scope, ctx.fail);

    const new_sha = try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest, ctx.fail);
    if (old_sha) |old| {
        try printShaLine(ctx, pkg.repo, old, new_sha);
    } else {
        try shared.line(ctx, "{s} is at {s}.", .{
            try shared.identifier(ctx, pkg.repo),
            try shared.muted(ctx, shared.shortSha(new_sha)),
        });
    }
}

//
// Copies file.packages and replaces the entry at index.
//
fn replacePackage(
    allocator: std.mem.Allocator,
    file: config.File,
    index: usize,
    pkg: config.Package,
) std.mem.Allocator.Error!config.File {
    const packages = try allocator.alloc(config.Package, file.packages.len);
    for (file.packages, 0..) |existing, i| {
        packages[i] = existing;
    }
    packages[index] = pkg;
    return .{ .packages = packages };
}

//
// Either the package is already current, or it moved from one commit to another.
//
// The subject is the full `owner/repo`, the same name the user typed into `add` and the same one
// in skl.yaml: a bare repo name reads as an ordinary word rather than as an identifier. SHAs are
// abbreviated because the point of the line is that HEAD moved, not which bytes it moved to.
//
fn printShaLine(
    ctx: *const Context,
    repo: []const u8,
    old_sha: []const u8,
    new_sha: []const u8,
) skilled.failure.Error!void {
    if (std.mem.eql(u8, old_sha, new_sha)) {
        try shared.line(ctx, "{s} is already up to date.", .{try shared.identifier(ctx, repo)});
        return;
    }
    try shared.line(ctx, "{s} updated {s} {s} {s}.", .{
        try shared.identifier(ctx, repo),
        try shared.muted(ctx, shared.shortSha(old_sha)),
        ctx.style.arrow(),
        try shared.muted(ctx, shared.shortSha(new_sha)),
    });
}

//
// Unpacks Commander options and runs update.
//
fn action(invocation: *commander.Invocation) anyerror!void {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    invocation.exit_code = try run(ctx, .{
        .global = invocation.option("global") != null,
        .query = if (invocation.args.len > 0) invocation.args[0] else null,
        .branch = invocation.option("branch"),
        .local = invocation.option("local"),
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("update.test.zig");
}
