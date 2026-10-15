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
// How a refused command says why: the failure returned in place of the exit code.
//
const failure = skilled.failure;

//
// YAML read/write after a successful scan or `--from` merge.
//
const config = skilled.config;

//
// Spec parse, throwaway clone, YAML load, and package-list merge for `--from`.
//
const from = skilled.from;

//
// HEAD of the fresh clone, reported on the success line.
//
const git = skilled.git;

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
// The reserved namespace check, so a package cannot take the scratch directory's links.
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
pub fn run(ctx: *const Context, args: Args) std.mem.Allocator.Error!failure.Result(u8) {
    if (args.from) |spec| {
        if (args.repo != null) {
            return .{
                .failed = failure.because("Cannot use add --from together with a repo.", .{}),
            };
        }
        if (args.namespace != null) {
            return .{
                .failed = failure.because("The --ns flag is not used with --from.", .{}),
            };
        }
        if (args.branch != null) {
            return .{
                .failed = failure.because("The --branch flag is not used with --from.", .{}),
            };
        }
        if (args.local != null) {
            return .{
                .failed = failure.because("The --local flag is not used with --from.", .{}),
            };
        }
        return runFrom(ctx, args.global, spec);
    }
    if (args.branch != null and args.local != null) {
        return .{
            .failed = failure.because("The --branch flag cannot be used with --local.", .{}),
        };
    }
    const spec = args.repo orelse return .{
        .failed = failure.because("The add command requires a repo or --from.", .{}),
    };

    const scope = try shared.scopeOf(ctx, args.global);
    const file = switch (try shared.requireConfig(ctx, scope.config_path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };

    const namespace = switch (try resolveNamespace(ctx, args.namespace)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (remote.validateName(namespace, "namespace")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    //
    // Before the clone and before the YAML write, so a refused namespace leaves nothing behind.
    // The interactive prompt returns into this same variable, so it is checked too.
    //
    if (scratch.isReserved(namespace)) {
        return .{
            .failed = failure.because("Namespace \"{s}\" is reserved for the scratch directory.", .{namespace}),
        };
    }
    if (shared.namespaceTaken(file.packages, namespace)) |taken| {
        return .{
            .failed = failure.because("Namespace \"{s}\" is already used by {s}.", .{ namespace, taken.repo }),
        };
    }

    var spinner = shared.newSpinner(ctx);
    defer spinner.finish();

    if (args.local) |local_path| {
        const dest = switch (try shared.resolveLocal(ctx, local_path)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        const appended = try appendPackage(ctx.allocator, file, .{
            .repo = spec,
            .namespace = namespace,
            .local = dest,
        });
        switch (try config.writeFile(ctx.io, ctx.allocator, scope.config_path, appended)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ namespace, spec }));
        switch (try link.linkPackage(ctx.io, ctx.allocator, dest, namespace, scope)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        spinner.finish();
        const local_sha = switch (try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, dest)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        switch (shared.line(ctx, "{s} Added {s} as {s} at {s}.", .{
            ctx.style.check(),
            try shared.identifier(ctx, spec),
            try shared.namespaceText(ctx, namespace),
            try shared.muted(ctx, shared.shortSha(local_sha)),
        })) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        return .{
            .ok = 0,
        };
    }

    const resolved = switch (try shared.ensureCloned(ctx, spec, args.branch, &spinner)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (try package.scan(ctx.io, ctx.allocator, resolved.dest)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    const appended = try appendPackage(ctx.allocator, file, .{
        .repo = spec,
        .namespace = namespace,
        .branch = args.branch,
    });
    switch (try config.writeFile(ctx.io, ctx.allocator, scope.config_path, appended)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    spinner.linking(try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ namespace, resolved.parsed.repo }));
    switch (try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, namespace, scope)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    spinner.finish();

    const added = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{
        resolved.parsed.owner,
        resolved.parsed.repo,
    });
    //
    // The commit the namespace is pinned to right now, so the line says which revision was linked
    // rather than only that something was. Every package is a git repository — the scratch
    // directory is the one tree that is not, and it is never added — so a clone that cannot report
    // HEAD is a real failure, not a line printed without its SHA.
    //
    const sha = switch (try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (shared.line(ctx, "{s} Added {s} as {s} at {s}.", .{
        ctx.style.check(),
        try shared.identifier(ctx, added),
        try shared.namespaceText(ctx, namespace),
        try shared.muted(ctx, shared.shortSha(sha)),
    })) {
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
// Builds the `add` command. `[repo]` is optional so `--from` can occupy the line.
//
pub fn buildCommand(ctx: *const Context) std.mem.Allocator.Error!*Command {
    const command = (try Command.init(ctx.allocator, "add"))
        .description("Clone a package, append YAML, and link it.")
        .argument("[repo]", "The package to add.")
        .action(ctx, action);
    try command.option("--ns <namespace>", "The namespace to install under.", null);
    try command.option("--from <spec>", "A YAML file inside a git repo.", null);
    try command.option("--branch <name>", "Clone this branch instead of the default.", null);
    try command.option("--local <path>", "Link a local working tree instead of cloning.", null);
    return command;
}

//
// `--ns` when given, a prompt when interactive, or an error that names `--ns`.
//
fn resolveNamespace(ctx: *const Context, namespace_opt: ?[]const u8) std.mem.Allocator.Error!failure.Result([]const u8) {
    if (namespace_opt) |ns| {
        if (ns.len == 0) {
            return .{
                .failed = failure.because("The --ns flag is required.", .{}),
            };
        }
        return .{
            .ok = ns,
        };
    }
    if (ctx.non_interactive) {
        return .{
            .failed = failure.because("The --ns flag is required.", .{}),
        };
    }
    shared.promptWrite(ctx, "Namespace: ", .{});
    const ns = switch (try shared.promptLine(ctx)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (ns.len == 0) {
        return .{
            .failed = failure.because("The --ns flag is required.", .{}),
        };
    }
    return .{
        .ok = ns,
    };
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
    return .{
        .packages = packages,
    };
}

//
// Appends packages from a YAML file in git into an existing skl.yaml. Does not clone or link.
//
fn runFrom(ctx: *const Context, global: bool, spec: []const u8) std.mem.Allocator.Error!failure.Result(u8) {
    const scope = try shared.scopeOf(ctx, global);
    const file = switch (try shared.requireConfig(ctx, scope.config_path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const fetched = switch (try from.fetchConfig(ctx.io, ctx.allocator, ctx.environ, ctx.git, spec)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const merged = switch (try from.mergePackages(ctx.allocator, file.packages, fetched.packages)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (try config.writeFile(ctx.io, ctx.allocator, scope.config_path, .{
        .packages = merged,
    })) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (shared.line(ctx, "Updated {s}.", .{try shared.muted(ctx, scope.config_path)})) {
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
// Unpacks Commander options and runs add.
//
fn action(invocation: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    return run(ctx, .{
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
