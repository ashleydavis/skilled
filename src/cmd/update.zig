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
// How a refused command says why: the failure returned in place of the exit code.
//
const failure = skilled.failure;

//
// YAML rewrite when `--branch` or `--local` changes a row's source.
//
const config = skilled.config;

//
// fetchUpdate and HEAD, via the injected runner.
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
pub fn run(ctx: *const Context, args: Args) std.mem.Allocator.Error!failure.Result(u8) {
    const scope = try shared.scopeOf(ctx, args.global);
    const file = switch (try shared.requireConfig(ctx, scope.config_path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };

    if (args.branch != null and args.local != null) {
        return .{
            .failed = failure.because("The --branch flag cannot be used with --local.", .{}),
        };
    }
    if (args.branch != null or args.local != null) {
        const q = args.query orelse {
            if (args.branch != null) {
                return .{
                    .failed = failure.because("The update --branch flag requires a package query.", .{}),
                };
            }
            return .{
                .failed = failure.because("The update --local flag requires a package query.", .{}),
            };
        };
        const matched = switch (try shared.requireOneMatch(ctx.allocator, file.packages, q)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        if (args.local) |local_path| {
            switch (try switchToLocal(ctx, scope, file, matched, local_path)) {
                .ok => {},
                .failed => |why| return .{
                    .failed = why,
                },
            }
        } else {
            switch (try switchToBranch(ctx, scope, file, matched, args.branch.?)) {
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
    // Without the source flags this is the "repair missing links" command, so the scratch links are
    // repaired too. `--branch` and `--local` are about one named package and leave it alone.
    //
    switch (try shared.syncScratch(ctx, scope)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    if (args.query) |q| {
        const matched = switch (try shared.requireOneMatch(ctx.allocator, file.packages, q)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        switch (try updateOne(ctx, scope, matched.pkg)) {
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
        switch (try updateOne(ctx, scope, pkg)) {
            .ok => {},
            .failed => |why| return .{
                .failed = failure.because("Update failed on {s}: {s}", .{ pkg.repo, why.message() }),
            },
        }
    }
    return .{
        .ok = 0,
    };
}

//
// Builds the `update` command.
//
pub fn buildCommand(ctx: *const Context) std.mem.Allocator.Error!*Command {
    const command = (try Command.init(ctx.allocator, "update"))
        .description("Fast-forward store clones and repair links.")
        .argument("[repo]", "One package, or every package when omitted.")
        .action(ctx, action);
    try command.option("--branch <name>", "Check out this branch and relink the store.", null);
    try command.option("--local <path>", "Link a local working tree instead of the store.", null);
    return command;
}

//
// fetchUpdate, print SHA change, then linkPackage — or repair a `local:` row with no fetch.
//
fn updateOne(ctx: *const Context, scope: skilled.paths.Scope, pkg: skilled.config.Package) std.mem.Allocator.Error!failure.Result(void) {
    if (pkg.local) |local_path| {
        const dest = switch (try shared.resolveLocal(ctx, local_path)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        switch (try link.linkPackage(ctx.io, ctx.allocator, dest, pkg.namespace, scope)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        return shared.line(ctx, "{s} is linked to the local tree at {s}.", .{
            try shared.identifier(ctx, pkg.repo),
            try shared.muted(ctx, dest),
        });
    }

    const resolved = switch (try shared.resolveStore(ctx, pkg.repo, pkg.branch)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (!shared.dirExists(ctx.io, resolved.dest)) {
        return .{
            .failed = failure.because("Package {s} is not installed; run skl install.", .{pkg.repo}),
        };
    }

    const old_sha = switch (try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (try git.fetchUpdate(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    const new_sha = switch (try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };

    switch (try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, pkg.namespace, scope)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return printShaLine(ctx, pkg.repo, old_sha, new_sha);
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
) std.mem.Allocator.Error!failure.Result(void) {
    const dest = switch (try shared.resolveLocal(ctx, local_path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    var pkg = matched.pkg;
    pkg.local = dest;
    pkg.branch = null;
    const rewritten = replacePackage(ctx.allocator, file, matched.index, pkg) catch |err| switch (err) {
        error.IndexNotFound => return .{
            .failed = failure.because("The package to update is no longer in {s}.", .{scope.config_path}),
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    switch (try config.writeFile(ctx.io, ctx.allocator, scope.config_path, rewritten)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try link.linkPackage(ctx.io, ctx.allocator, dest, pkg.namespace, scope)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return shared.line(ctx, "{s} is linked to the local tree at {s}.", .{
        try shared.identifier(ctx, pkg.repo),
        try shared.muted(ctx, dest),
    });
}

//
// Clears `local`, writes `branch`, clones that branch's store dest if missing, and relinks at it.
//
// The links to the row's previous source are removed first. That source is another directory (the
// local tree or another branch's clone), so linkPackage alone would leave a link the new branch's
// layout does not use.
//
fn switchToBranch(
    ctx: *const Context,
    scope: skilled.paths.Scope,
    file: config.File,
    matched: shared.Match,
    branch: []const u8,
) std.mem.Allocator.Error!failure.Result(void) {
    const old_dest = switch (try shared.contentDir(ctx, matched.pkg)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const old_sha: ?[]const u8 = if (shared.dirExists(ctx.io, old_dest))
        switch (try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, old_dest)) {
            .ok => |sha| sha,
            .failed => |why| return .{
                .failed = why,
            },
        }
    else
        null;

    var spinner = shared.newSpinner(ctx);
    defer spinner.finish();
    const resolved = switch (try shared.ensureCloned(ctx, matched.pkg.repo, branch, &spinner)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (try skilled.package.scan(ctx.io, ctx.allocator, resolved.dest)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    var pkg = matched.pkg;
    pkg.branch = branch;
    pkg.local = null;
    const rewritten = replacePackage(ctx.allocator, file, matched.index, pkg) catch |err| switch (err) {
        error.IndexNotFound => return .{
            .failed = failure.because("The package to update is no longer in {s}.", .{scope.config_path}),
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    switch (try config.writeFile(ctx.io, ctx.allocator, scope.config_path, rewritten)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try link.unlinkPackage(ctx.io, ctx.allocator, old_dest, pkg.namespace, scope)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try link.linkPackage(ctx.io, ctx.allocator, resolved.dest, pkg.namespace, scope)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }

    const new_sha = switch (try git.headSha(ctx.io, ctx.allocator, ctx.environ, ctx.git, resolved.dest)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (old_sha) |old| {
        return printShaLine(ctx, pkg.repo, old, new_sha);
    }
    return shared.line(ctx, "{s} is at {s}.", .{
        try shared.identifier(ctx, pkg.repo),
        try shared.muted(ctx, shared.shortSha(new_sha)),
    });
}

//
// Copies file.packages and replaces the entry at index. An index past the end names no entry and is
// refused with `error.IndexNotFound`, before anything is allocated.
//
pub fn replacePackage(
    allocator: std.mem.Allocator,
    file: config.File,
    index: usize,
    pkg: config.Package,
) (error{IndexNotFound} || std.mem.Allocator.Error)!config.File {
    if (index >= file.packages.len) {
        return error.IndexNotFound;
    }
    const packages = try allocator.alloc(config.Package, file.packages.len);
    for (file.packages, 0..) |existing, i| {
        packages[i] = existing;
    }
    packages[index] = pkg;
    return .{
        .packages = packages,
    };
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
) std.mem.Allocator.Error!failure.Result(void) {
    if (std.mem.eql(u8, old_sha, new_sha)) {
        return shared.line(ctx, "{s} is already up to date.", .{try shared.identifier(ctx, repo)});
    }
    return shared.line(ctx, "{s} updated {s} {s} {s}.", .{
        try shared.identifier(ctx, repo),
        try shared.muted(ctx, shared.shortSha(old_sha)),
        ctx.style.arrow(),
        try shared.muted(ctx, shared.shortSha(new_sha)),
    });
}

//
// Unpacks Commander options and runs update.
//
fn action(invocation: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    return run(ctx, .{
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
