//
// `skl init`: create skl.yaml in the active scope, empty or from `--from`.
//
// Plain init writes `packages: []` when the file is missing. `--from` fills a missing or empty
// file from a YAML file in git, then installs those packages. Neither form wipes a list the user
// already built. Every form creates and links this scope's scratch directory, so a second init
// repairs a namespace link the user deleted.
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
pub fn run(ctx: *const Context, args: Args) std.mem.Allocator.Error!failure.Result(u8) {
    if (args.from) |spec| {
        return runFrom(ctx, args.global, spec);
    }
    const scope = try shared.scopeOf(ctx, args.global);
    if (!files.fileExists(ctx.io, scope.config_path)) {
        switch (try config.writeFile(ctx.io, ctx.allocator, scope.config_path, .{
            .packages = &.{},
        })) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        switch (shared.line(ctx, "Wrote {s}.", .{try shared.muted(ctx, scope.config_path)})) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        switch (try shared.syncScratch(ctx, scope)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        return .{
            .ok = 0,
        };
    }
    const file = switch (try config.readFile(ctx.io, ctx.allocator, scope.config_path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (file.packages.len == 0) {
        switch (shared.line(ctx, "Config already exists at {s}.", .{try shared.muted(ctx, scope.config_path)})) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        switch (try shared.syncScratch(ctx, scope)) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
        return .{
            .ok = 0,
        };
    }
    switch (shared.line(ctx, "Config at {s} already lists packages; it was not overwritten.", .{try shared.muted(ctx, scope.config_path)})) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try shared.syncScratch(ctx, scope)) {
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
// Builds the `init` command.
//
pub fn buildCommand(ctx: *const Context) std.mem.Allocator.Error!*Command {
    const command = (try Command.init(ctx.allocator, "init"))
        .description("Create skl.yaml with packages: [].")
        .action(ctx, action);
    try command.option("--from <spec>", "A YAML file inside a git repo; also install its packages.", null);
    return command;
}

//
// Fetches YAML, writes it when the config is missing or still `packages: []`, then installs.
//
fn runFrom(ctx: *const Context, global: bool, spec: []const u8) std.mem.Allocator.Error!failure.Result(u8) {
    const scope = try shared.scopeOf(ctx, global);
    if (files.fileExists(ctx.io, scope.config_path)) {
        const existing = switch (try config.readFile(ctx.io, ctx.allocator, scope.config_path)) {
            .ok => |got| got,
            .failed => |why| return .{
                .failed = why,
            },
        };
        if (existing.packages.len != 0) {
            return .{
                .failed = failure.because("Config at {s} already lists packages; use skl add --from.", .{scope.config_path}),
            };
        }
    }
    const fetched = switch (try from.fetchConfig(ctx.io, ctx.allocator, ctx.environ, ctx.git, spec)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (try config.writeFile(ctx.io, ctx.allocator, scope.config_path, fetched)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (shared.line(ctx, "Wrote {s}.", .{try shared.muted(ctx, scope.config_path)})) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try shared.syncScratch(ctx, scope)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return shared.installAll(ctx, scope, fetched);
}

//
// Unpacks Commander options and runs init.
//
fn action(invocation: *const commander.Invocation) std.mem.Allocator.Error!failure.Result(u8) {
    const ctx: *const Context = @ptrCast(@alignCast(invocation.context));
    return run(ctx, .{
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
