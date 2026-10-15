//
// `skl list`: print each YAML package and its skills/commands as `ns:name`.
//
// A missing store clone still prints the YAML row; the item list is empty with a note that it is
// not installed. The scratch directory is printed after the packages, under its own namespace, so
// what the agents can see is one list rather than two commands.
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
// The scratch namespace, for the section printed after the packages.
//
const scratch = skilled.scratch;

//
// The run values this command was given.
//
const Context = context_mod.Context;

//
// The Commander command type, aliased so the builder chain stays short.
//
const Command = commander.Command;

//
// What this invocation of `list` asked for, unpacked from Commander.
//
pub const Args = struct {
    //
    // `-g` / `--global`: project vs machine YAML and agent roots.
    //
    global: bool = false,
};

//
// Prints every package in the active YAML.
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
        switch (shared.line(ctx, "There are no packages.", .{})) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        switch (try printScratch(ctx, scope)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        return .{
            .ok = 0,
        };
    }

    for (file.packages) |pkg| {
        switch (try printPackage(ctx, pkg)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }
    switch (try printScratch(ctx, scope)) {
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
// Builds the `list` command.
//
pub fn buildCommand(ctx: *const Context) std.mem.Allocator.Error!*Command {
    return (try Command.init(ctx.allocator, "list"))
        .description("Print each namespace with its skills and commands.")
        .action(ctx, action);
}

//
// One namespace block: the heading, the package blurb, then its items by kind.
//
fn printPackage(ctx: *const Context, pkg: skilled.config.Package) std.mem.Allocator.Error!failure.Result(void) {
    const source = if (pkg.local) |local_path|
        try std.fmt.allocPrint(ctx.allocator, "{s} (local {s})", .{ pkg.repo, local_path })
    else if (pkg.branch) |branch|
        try std.fmt.allocPrint(ctx.allocator, "{s} (branch {s})", .{ pkg.repo, branch })
    else
        pkg.repo;

    switch (try printHeading(ctx, pkg.namespace, source)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    const dest = switch (try shared.contentDir(ctx, pkg)) {
        .ok => |path| path,
        .failed => return printNote(ctx, "Not installed."),
    };
    if (!shared.dirExists(ctx.io, dest)) {
        return printNote(ctx, "Not installed.");
    }

    const readme = switch (try package.readmeDescription(ctx.io, ctx.allocator, dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (readme) |description| {
        switch (try printNote(ctx, description)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }

    const items = switch (try package.scan(ctx.io, ctx.allocator, dest)) {
        .ok => |got| got,
        .failed => return printNote(ctx, "Not installed."),
    };
    return printItems(ctx, items);
}

//
// The scratch directory as one more namespace block.
//
// Nothing is printed when the directory is not there: a scope where init and install have not run
// has no scratch directory to describe, and list is not the command that creates it. A scan that
// fails (a tree removed by hand) prints the heading only rather than failing the whole listing.
//
fn printScratch(ctx: *const Context, scope: skilled.paths.Scope) std.mem.Allocator.Error!failure.Result(void) {
    if (!shared.dirExists(ctx.io, scope.scratch_dir)) {
        return .ok;
    }

    switch (try printHeading(ctx, scratch.namespace, "scratch directory")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try printNote(ctx, scope.scratch_dir)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    const items = switch (try package.scan(ctx.io, ctx.allocator, scope.scratch_dir)) {
        .ok => |got| got,
        .failed => return .ok,
    };
    return printItems(ctx, items);
}

//
// `<namespace> — <source>`, the line that opens a block.
//
// The namespace is what the user types in an agent, so it is the one thing coloured; where the
// files came from is dimmed behind it.
//
fn printHeading(ctx: *const Context, namespace: []const u8, source: []const u8) std.mem.Allocator.Error!failure.Result(void) {
    const name = try shared.namespaceText(ctx, namespace);
    const from = try shared.muted(ctx, try std.fmt.allocPrint(ctx.allocator, "— {s}", .{source}));
    return shared.line(ctx, "{s} {s}", .{ name, from });
}

//
// A dim line under a heading: the package blurb, the scratch path, or why there is nothing to list.
//
fn printNote(ctx: *const Context, text: []const u8) std.mem.Allocator.Error!failure.Result(void) {
    const dim = try shared.muted(ctx, text);
    return shared.line(ctx, "   {s}", .{dim});
}

//
// The items of one block, under a `skills` or `commands` sub-heading.
//
// Names are printed without the namespace because the heading above already carries it. The name
// column is as wide as the longest name in this block, so descriptions line up within a block
// without a listing-wide pass over every package.
//
fn printItems(ctx: *const Context, items: []const package.Item) std.mem.Allocator.Error!failure.Result(void) {
    var width: usize = 0;
    for (items) |item| {
        if (item.name.len > width) {
            width = item.name.len;
        }
    }

    switch (try printKind(ctx, items, .skill, "skills", width)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return printKind(ctx, items, .command, "commands", width);
}

//
// One sub-heading and the items of that kind, or nothing when the package has none.
//
fn printKind(
    ctx: *const Context,
    items: []const package.Item,
    kind: package.Kind,
    label: []const u8,
    width: usize,
) std.mem.Allocator.Error!failure.Result(void) {
    var seen = false;
    for (items) |item| {
        if (item.kind != kind) {
            continue;
        }
        if (!seen) {
            const heading = try shared.paint(ctx.allocator, ctx.style, skilled.term.label_color, label);
            switch (shared.line(ctx, "   {s}", .{heading})) {
                .ok => {},
                .failed => |why| return .{
                    .failed = why,
                },
            }
            seen = true;
        }
        switch (try printItem(ctx, item, width)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }
    return .ok;
}

//
// `      <name><padding>  <description>`, with the description dimmed behind the name.
//
pub fn printItem(ctx: *const Context, item: package.Item, width: usize) std.mem.Allocator.Error!failure.Result(void) {
    if (item.description.len == 0) {
        return shared.line(ctx, "      {s}", .{item.name});
    }

    //
    // A name longer than `width` gets no padding rather than a negative amount.
    //
    const padding = try ctx.allocator.alloc(u8, width -| item.name.len);
    @memset(padding, ' ');
    const description = try shared.muted(ctx, item.description);
    return shared.line(ctx, "      {s}{s}   {s}", .{ item.name, padding, description });
}

//
// Unpacks Commander options and runs list.
//
fn action(invocation: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    return run(ctx, .{
        .global = invocation.option("global") != null,
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("list.test.zig");
}
