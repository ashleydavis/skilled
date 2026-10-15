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
// How a refused command says why: the failure returned in place of the exit code.
//
const failure = skilled.failure;

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
pub fn run(ctx: *const Context, args: Args) std.mem.Allocator.Error!failure.Result(u8) {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = switch (try shared.requireConfig(ctx, scope.config_path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (file.packages.len == 0) {
        return .{
            .failed = failure.because("There are no packages in skl.yaml.", .{}),
        };
    }

    const pkg = switch (try selectPackage(ctx, file.packages, args.query)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const parsed = switch (try skilled.remote.parse(ctx.allocator, pkg.repo)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const pages = try shared.pagesGuessUrl(ctx.allocator, parsed);

    switch (try printDetails(ctx, pkg, parsed, pages)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    if (!ctx.non_interactive) {
        switch (try shared.openUrl(ctx, pages)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }
    return .{
        .ok = 0,
    };
}

//
// Builds the `docs` command.
//
pub fn buildCommand(ctx: *const Context) std.mem.Allocator.Error!*Command {
    return (try Command.init(ctx.allocator, "docs"))
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
) std.mem.Allocator.Error!failure.Result(skilled.config.Package) {
    if (query) |q| {
        const matched = switch (try shared.requireOneMatch(ctx.allocator, packages, q)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        return .{
            .ok = matched.pkg,
        };
    }
    if (ctx.non_interactive) {
        return .{
            .failed = failure.because("The docs command requires a package name when non-interactive.", .{}),
        };
    }
    for (packages, 0..) |pkg, i| {
        switch (shared.line(ctx, "{d}. {s}  {s}", .{ i + 1, pkg.namespace, pkg.repo })) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }
    shared.promptWrite(ctx, "Select a package: ", .{});
    const answer = switch (try shared.promptLine(ctx)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const n = std.fmt.parseInt(usize, answer, 10) catch {
        return .{
            .failed = failure.because("Expected a package number.", .{}),
        };
    };
    if (n == 0 or n > packages.len) {
        return .{
            .failed = failure.because("Expected a package number.", .{}),
        };
    }
    return .{
        .ok = packages[n - 1],
    };
}

//
// YAML fields, scan items when the clone exists, and the Pages guess as text only.
//
fn printDetails(
    ctx: *const Context,
    pkg: skilled.config.Package,
    parsed: skilled.remote.Remote,
    pages: []const u8,
) std.mem.Allocator.Error!failure.Result(void) {
    switch (shared.line(ctx, "{s} {s}", .{ ctx.style.package(), parsed.repo })) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (shared.line(ctx, "Namespace: {s}", .{try shared.namespaceText(ctx, pkg.namespace)})) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (shared.line(ctx, "Repo: {s}", .{try shared.identifier(ctx, pkg.repo)})) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    if (pkg.branch) |branch| {
        switch (shared.line(ctx, "Branch: {s}", .{try shared.identifier(ctx, branch)})) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }
    if (pkg.local) |local_path| {
        switch (shared.line(ctx, "Local: {s}", .{try shared.muted(ctx, local_path)})) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }

    //
    // A package whose directory cannot be worked out, or whose tree cannot be scanned, still gets
    // its YAML fields and the Pages guess printed, so those failures are not returned.
    //
    const dest: ?[]const u8 = switch (try shared.contentDir(ctx, pkg)) {
        .ok => |path| path,
        .failed => null,
    };
    if (dest) |path| {
        if (shared.dirExists(ctx.io, path)) {
            const readme = switch (try package.readmeDescription(ctx.io, ctx.allocator, path)) {
                .ok => |got| got,
                .failed => |why| return .{
                    .failed = why,
                },
            };
            if (readme) |description| {
                switch (shared.line(ctx, "{s}", .{try shared.muted(ctx, description)})) {
                    .ok => {},
                    .failed => |why| return .{
                        .failed = why,
                    },
                }
            }
            switch (try package.scan(ctx.io, ctx.allocator, path)) {
                .ok => |items| {
                    for (items) |item| {
                        switch (shared.line(ctx, "  {s}:{s}  {s}", .{ pkg.namespace, item.name, item.description })) {
                            .ok => {},
                            .failed => |why| return .{
                                .failed = why,
                            },
                        }
                    }
                },
                .failed => {},
            }
        }
    }

    return shared.line(ctx, "GitHub Pages: {s}", .{try shared.identifier(ctx, pages)});
}

//
// Unpacks Commander options and runs docs.
//
fn action(invocation: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    return run(ctx, .{
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
