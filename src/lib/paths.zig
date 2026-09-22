//
// Home, config, store, scratch, and agent directories, resolved the same way on every platform.
//
// Nothing here touches the disk: home and XDG come from a map the caller already has, and the rest
// is joining those strings. Tests pass a fake map and fake cwd rather than the process environment.
// Cursor's managed `skills-cursor` directory is never a result of these functions.
//

const std = @import("std");

//
// Path joining, so store and config paths use the same separators as the rest of the tool.
//
const files = @import("files.zig");

//
// Returned when neither HOME nor USERPROFILE is set, so no store or config path can be resolved.
//
pub const Error = error{
    HomeNotFound,
};

//
// Config path and the four agent roots for one scope (global or project).
//
// `-g` picks this once; later clone and link steps read these fields rather than joining home or
// cwd again, so a run cannot write YAML in one place and links in another.
//
pub const Scope = struct {
    //
    // The `skl.yaml` for this scope: global config or `<cwd>/skl.yaml`.
    //
    config_path: []const u8,

    //
    // Where this scope's Cursor skills namespace symlinks live.
    //
    cursor_skills: []const u8,

    //
    // Where this scope's Cursor command namespace symlinks live.
    //
    cursor_commands: []const u8,

    //
    // Where this scope's Claude skills namespace symlinks live.
    //
    claude_skills: []const u8,

    //
    // Where this scope's Claude command namespace symlinks live.
    //
    claude_commands: []const u8,

    //
    // This scope's scratch directory, whose skills/ and commands/ trees are linked as `loc`.
    //
    // Resolved here with the agent roots so a run cannot create the trees under one base and link
    // them from another.
    //
    scratch_dir: []const u8,
};

//
// The user's home directory: `HOME`, else `USERPROFILE` (Windows).
//
// Empty values are treated as unset so a blank HOME does not win over a real USERPROFILE.
//
pub fn homeDir(env: *const std.process.Environ.Map) Error![]const u8 {
    if (nonEmpty(env.get("HOME"))) |value| {
        return value;
    }
    if (nonEmpty(env.get("USERPROFILE"))) |value| {
        return value;
    }
    return error.HomeNotFound;
}

//
// `XDG_CONFIG_HOME` when it is set to a non-empty value, otherwise null.
//
// Callers pass this into `globalConfigPath` rather than reading the map again, so a test can
// supply the override without constructing an environment.
//
pub fn xdgConfigHome(env: *const std.process.Environ.Map) ?[]const u8 {
    return nonEmpty(env.get("XDG_CONFIG_HOME"));
}

//
// The global YAML file: `$XDG_CONFIG_HOME/skilled/skl.yaml` when that env is set, else
// `<home>/.config/skilled/skl.yaml` on every platform, Windows included.
//
// A stow-managed `~/.config` tree only works if Windows uses the same layout as Unix.
//
pub fn globalConfigPath(
    allocator: std.mem.Allocator,
    home_dir: []const u8,
    xdg_config_home: ?[]const u8,
) std.mem.Allocator.Error![]const u8 {
    if (nonEmpty(xdg_config_home)) |xdg| {
        return files.joinPath(allocator, &.{ xdg, "skilled", "skl.yaml" });
    }
    return files.joinPath(allocator, &.{ home_dir, ".config", "skilled", "skl.yaml" });
}

//
// The project YAML file, always `<cwd>/skl.yaml`.
//
pub fn projectConfigPath(allocator: std.mem.Allocator, cwd: []const u8) std.mem.Allocator.Error![]const u8 {
    return files.joinPath(allocator, &.{ cwd, "skl.yaml" });
}

//
// Where cloned packages live, resolved against the user's home directory.
//
// Resolved from home only, not `XDG_DATA_HOME`, so a run cannot clone into one store and link
// from another. v1 keeps the store at `<home>/.skilled/store` on purpose.
//
pub fn storeDir(allocator: std.mem.Allocator, home_dir: []const u8) std.mem.Allocator.Error![]const u8 {
    return files.joinPath(allocator, &.{ home_dir, ".skilled", "store" });
}

//
// The directory of one clone: `<store>/<host>/<owner>/<repo>`.
//
// Host is a single directory name, including dotted names like `github.example.com`, so a
// later clone cannot split a host into nested directories.
//
pub fn clonePath(
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    host: []const u8,
    owner: []const u8,
    repo: []const u8,
) std.mem.Allocator.Error![]const u8 {
    return files.joinPath(allocator, &.{ store_dir, host, owner, repo });
}

//
// Config path and agent roots for `-g` (home) or the project (cwd).
//
// Global still honours `XDG_CONFIG_HOME` for the YAML path; agent roots and the scratch directory
// stay under home or cwd, never under `skills-cursor`.
//
pub fn scopeFromFlag(
    allocator: std.mem.Allocator,
    global: bool,
    home_dir: []const u8,
    cwd: []const u8,
    xdg_config_home: ?[]const u8,
) std.mem.Allocator.Error!Scope {
    if (global) {
        return scopeFromBase(
            allocator,
            try globalConfigPath(allocator, home_dir, xdg_config_home),
            home_dir,
        );
    }
    return scopeFromBase(allocator, try projectConfigPath(allocator, cwd), cwd);
}

//
// Fills a Scope from an already-chosen config path and the directory that owns the agent roots.
//
fn scopeFromBase(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    base: []const u8,
) std.mem.Allocator.Error!Scope {
    return .{
        .config_path = config_path,
        .cursor_skills = try files.joinPath(allocator, &.{ base, ".cursor", "skills" }),
        .cursor_commands = try files.joinPath(allocator, &.{ base, ".cursor", "commands" }),
        .claude_skills = try files.joinPath(allocator, &.{ base, ".claude", "skills" }),
        .claude_commands = try files.joinPath(allocator, &.{ base, ".claude", "commands" }),
        .scratch_dir = try files.joinPath(allocator, &.{ base, ".skilled", "scratch" }),
    };
}

//
// The slice when it is present and non-empty, otherwise null.
//
fn nonEmpty(value: ?[]const u8) ?[]const u8 {
    const slice = value orelse return null;
    if (slice.len == 0) {
        return null;
    }
    return slice;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("paths.test.zig");
}
