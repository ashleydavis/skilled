//
// `skl docs`: print package details and open the GitHub Pages guess in a browser.
//
// No HTTP: there is no Pages probe, no HEAD/GET, no HTTP client. The Pages URL is a guess printed
// as text and opened when the run is interactive. Non-interactive docs only prints.
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
// What this invocation of `docs` asked for, unpacked from Commander.
//
pub const Args = struct {
    //
    // `-g` / `--global`: project vs machine YAML and agent roots.
    //
    global: bool = false,

    //
    // The `[package]` positional, or null to show a menu (interactive) / error (not).
    //
    query: ?[]const u8 = null,
};

//
// Prints one package (chosen by name, menu, or the only entry) and opens Pages when interactive.
//
pub fn run(ctx: *const Context, args: Args) skilled.failure.Error!u8 {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = try shared.requireConfig(ctx, scope.config_path);
    if (file.packages.len == 0) {
        return ctx.fail.set("no packages in skl.yaml", .{});
    }

    const pkg = try selectPackage(ctx, file.packages, args.query);
    var parse_fail = skilled.failure.Failure.init(ctx.allocator);
    const parsed = skilled.remote.parse(ctx.allocator, pkg.repo, &parse_fail) catch {
        return ctx.fail.set("{s}", .{parse_fail.text()});
    };
    const pages = try shared.pagesGuessUrl(ctx.allocator, parsed);

    try printDetails(ctx, pkg, parsed, pages);

    if (!ctx.non_interactive) {
        try shared.openUrl(ctx, pages);
    }
    return 0;
}

//
// Builds the `docs` command.
//
pub fn buildCommand(ctx: *const Context) *Command {
    return Command.init(ctx.allocator, "docs")
        .description("Print package details and open GitHub Pages.")
        .argument("[package]", "The package to show.")
        .action(ctx, action);
}

//
// The YAML package to show: an explicit query, a menu when interactive, or an error.
//
fn selectPackage(
    ctx: *const Context,
    packages: []const skilled.config.Package,
    query: ?[]const u8,
) skilled.failure.Error!skilled.config.Package {
    if (query) |q| {
        const matched = try shared.requireOneMatch(ctx.allocator, packages, q, ctx.fail);
        return matched.pkg;
    }
    if (ctx.non_interactive) {
        return ctx.fail.set("docs requires a package name when non-interactive", .{});
    }
    for (packages, 0..) |pkg, i| {
        try shared.line(ctx, "{d}. {s}  {s}", .{ i + 1, pkg.namespace, pkg.repo });
    }
    shared.promptWrite(ctx, "Select a package: ", .{});
    const answer = try shared.promptLine(ctx);
    const n = std.fmt.parseInt(usize, answer, 10) catch {
        return ctx.fail.set("expected a package number", .{});
    };
    if (n == 0 or n > packages.len) {
        return ctx.fail.set("expected a package number", .{});
    }
    return packages[n - 1];
}

//
// YAML fields, scan items when the clone exists, and the Pages guess as text only.
//
fn printDetails(
    ctx: *const Context,
    pkg: skilled.config.Package,
    parsed: skilled.remote.Remote,
    pages: []const u8,
) skilled.failure.Error!void {
    try shared.line(ctx, "{s} {s}", .{ ctx.style.package(), parsed.repo });
    try shared.line(ctx, "namespace: {s}", .{pkg.namespace});
    try shared.line(ctx, "repo: {s}", .{pkg.repo});
    if (pkg.branch) |branch| {
        try shared.line(ctx, "branch: {s}", .{branch});
    }
    if (pkg.local) |local_path| {
        try shared.line(ctx, "local: {s}", .{local_path});
    }

    const dest = shared.contentDir(ctx, pkg) catch |err| switch (err) {
        error.Failed => null,
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (dest) |path| {
        if (shared.dirExists(ctx.io, path)) {
            if (try package.readmeDescription(ctx.io, ctx.allocator, path, ctx.fail)) |description| {
                try shared.line(ctx, "{s}", .{description});
            }
            var scan_fail = skilled.failure.Failure.init(ctx.allocator);
            if (package.scan(ctx.io, ctx.allocator, path, &scan_fail)) |items| {
                for (items) |item| {
                    try shared.line(ctx, "  {s}:{s}  {s}", .{ pkg.namespace, item.name, item.description });
                }
            } else |_| {}
        }
    }

    try shared.line(ctx, "GitHub Pages: {s}", .{pages});
}

//
// Unpacks Commander options and runs docs.
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
    _ = @import("docs.test.zig");
}
