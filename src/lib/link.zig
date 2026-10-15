//
// Namespace symlinks from a store clone into Cursor and Claude skill and command directories.
//
// Cursor loads skills from `.cursor/skills` and slash commands from `.cursor/commands`.
// Claude keeps `skills/ns` and `commands/ns`, with a skills-only package remapped to
// `commands/ns` so those files show up as slash commands. Never a copy, never a
// write under skills-cursor. Agent parents `.cursor` / `.claude` are real directories so a
// later namespace cannot fold those trees into the store.
//

const std = @import("std");

//
// How a refused link or unlink is described to the caller.
//
const failure = @import("failure.zig");

//
// Directory creation, path joining, and error wording used when a symlink or parent dir fails.
//
const files = @import("files.zig");

//
// The four agent roots for the active scope. Linker reads these rather than joining home or cwd.
//
const paths = @import("paths.zig");

//
// Namespace validation, so `skills/ns` cannot contain `..` even if a later caller forgets step 6.
//
const remote = @import("remote.zig");

//
// Whether linking had anything to do, so a caller can stay quiet when it did not.
//
pub const Status = enum {
    //
    // Every link the package needs was already in place and pointing at it.
    //
    unchanged,

    //
    // A link or an agent directory was missing, pointed elsewhere, or was left over, and was
    // created, retargeted, or removed.
    //
    changed,
};

//
// Symlinks one package's skills/ and commands/ trees into every agent root in scope.
//
// Skills-only: Cursor `skills/ns` and Claude `commands/ns`, both → store/skills. Commands-only:
// Cursor `commands/ns` and Claude `commands/ns`, both → store/commands. Both trees: Cursor
// `skills/ns` → store/skills and `commands/ns` → store/commands; Claude gets both as-is.
// Existing links that already point at the store dest are left alone. A real file, or a symlink
// to somewhere else, is an error rather than `--adopt`. Leftover Cursor links from older
// layouts (commands under `skills/ns`, or skills under `commands/ns`) are removed when they
// point at this package.
//
pub fn linkPackage(
    io: std.Io,
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    namespace: []const u8,
    scope: paths.Scope,
) std.mem.Allocator.Error!failure.Result(Status) {
    switch (remote.validateName(namespace, "namespace")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    const skills_dir = try files.joinPath(allocator, &.{ store_dir, "skills" });
    const commands_dir = try files.joinPath(allocator, &.{ store_dir, "commands" });
    const has_skills = isDirectory(io, skills_dir, true);
    const has_commands = isDirectory(io, commands_dir, true);

    var changed = false;
    if (has_skills) {
        switch (try linkTree(io, allocator, store_dir, "skills", namespace, scope.cursor_skills)) {
            .ok => |made| changed = made or changed,
            .failed => |why| return .{
                .failed = why,
            },
        }
        if (has_commands) {
            switch (try linkTree(io, allocator, store_dir, "skills", namespace, scope.claude_skills)) {
                .ok => |made| changed = made or changed,
                .failed => |why| return .{
                    .failed = why,
                },
            }
        } else {
            switch (try linkTree(io, allocator, store_dir, "skills", namespace, scope.claude_commands)) {
                .ok => |made| changed = made or changed,
                .failed => |why| return .{
                    .failed = why,
                },
            }
        }
    }
    if (has_commands) {
        switch (try linkTree(io, allocator, store_dir, "commands", namespace, scope.cursor_commands)) {
            .ok => |made| changed = made or changed,
            .failed => |why| return .{
                .failed = why,
            },
        }
        switch (try linkTree(io, allocator, store_dir, "commands", namespace, scope.claude_commands)) {
            .ok => |made| changed = made or changed,
            .failed => |why| return .{
                .failed = why,
            },
        }
    }
    switch (try unlinkTree(io, allocator, store_dir, "commands", namespace, scope.cursor_skills)) {
        .ok => |made| changed = made or changed,
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.cursor_commands)) {
        .ok => |made| changed = made or changed,
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .{
        .ok = if (changed) .changed else .unchanged,
    };
}

//
// Removes skills/ns and commands/ns when they are symlinks to this package's store trees.
//
// Also removes Claude `commands/ns` when it points at store/skills, Cursor `skills/ns` when it
// points at store/commands, and leftover `.cursor/commands/ns` links that pointed at store/skills.
// Missing links are a no-op. A real file or a symlink that points elsewhere is left alone.
// The store clone is never deleted: another scope may still use it.
//
pub fn unlinkPackage(
    io: std.Io,
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    namespace: []const u8,
    scope: paths.Scope,
) std.mem.Allocator.Error!failure.Result(void) {
    switch (remote.validateName(namespace, "namespace")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.cursor_skills)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.claude_skills)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try unlinkTree(io, allocator, store_dir, "commands", namespace, scope.cursor_skills)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try unlinkTree(io, allocator, store_dir, "commands", namespace, scope.claude_commands)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.claude_commands)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try unlinkTree(io, allocator, store_dir, "commands", namespace, scope.cursor_commands)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    switch (try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.cursor_commands)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .ok;
}

//
// The failure for a symlink that could not be created.
//
// AccessDenied and PermissionDenied mention Developer Mode because that is what Windows needs
// (or an equivalent privilege) to create directory symlinks; the code never falls back to copying.
//
pub fn symlinkFailure(err: anyerror, path: []const u8) failure.Failure {
    switch (err) {
        error.AccessDenied, error.PermissionDenied => return failure.because(
            "Cannot create symlink {s}: enable Developer Mode (or equivalent) to allow directory symlinks.",
            .{path},
        ),
        else => return failure.because("Cannot create symlink {s}: {s}.", .{ path, files.describeError(err) }),
    }
}

//
// Links store_dir/<tree> to agent_root/<namespace> when that store tree is a directory.
//
fn linkTree(
    io: std.Io,
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    tree: []const u8,
    namespace: []const u8,
    agent_root: []const u8,
) std.mem.Allocator.Error!failure.Result(bool) {
    const store_tree = try files.joinPath(allocator, &.{ store_dir, tree });
    if (!isDirectory(io, store_tree, true)) {
        return .{
            .ok = false,
        };
    }
    const made_root = switch (ensureAgentRoot(io, agent_root)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const link_path = try files.joinPath(allocator, &.{ agent_root, namespace });
    const placed = switch (placeSymlink(io, store_tree, link_path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    return .{
        .ok = made_root or placed,
    };
}

//
// Deletes agent_root/<namespace> when it is a symlink whose target is store_dir/<tree>.
//
fn unlinkTree(
    io: std.Io,
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    tree: []const u8,
    namespace: []const u8,
    agent_root: []const u8,
) std.mem.Allocator.Error!failure.Result(bool) {
    const store_tree = try files.joinPath(allocator, &.{ store_dir, tree });
    const link_path = try files.joinPath(allocator, &.{ agent_root, namespace });
    const st = std.Io.Dir.cwd().statFile(io, link_path, .{
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return .{
            .ok = false,
        },
        else => return .{
            .failed = failure.because("Cannot stat {s}: {s}.", .{ link_path, files.describeError(err) }),
        },
    };
    if (st.kind != .sym_link) {
        return .{
            .ok = false,
        };
    }
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = std.Io.Dir.cwd().readLink(io, link_path, &buffer) catch |err| {
        return .{
            .failed = failure.because("Cannot read symlink {s}: {s}.", .{ link_path, files.describeError(err) }),
        };
    };
    //
    // Windows CI: dest had `/`, readLink had `\`. Byte equality skipped the delete.
    //
    if (!files.samePath(buffer[0..n], store_tree)) {
        return .{
            .ok = false,
        };
    }
    switch (removeSymlink(io, link_path)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .{
        .ok = true,
    };
}

//
// `.cursor` / `.claude` and the skills or commands directory under them, as real directories.
//
// Checked without following symlinks first so a folded parent (a symlink to the store) is refused
// rather than written through.
//
fn ensureAgentRoot(io: std.Io, agent_root: []const u8) failure.Result(bool) {
    const made_parent = switch (ensureRealDirectory(io, files.dirName(agent_root))) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const made_root = switch (ensureRealDirectory(io, agent_root)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    return .{
        .ok = made_parent or made_root,
    };
}

//
// Creates path as a real directory, or accepts one that already is. A symlink here is the stow
// tree-folding hazard and is an error.
//
// Pub because the scratch module creates `<scratch>/skills` and `<scratch>/commands` with it, so a
// symlink or a regular file at either path is refused in the same words as an agent root.
//
pub fn ensureRealDirectory(io: std.Io, path: []const u8) failure.Result(bool) {
    const st = std.Io.Dir.cwd().statFile(io, path, .{
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            files.makeDirPath(io, path) catch |create_err| {
                return .{
                    .failed = failure.because("Cannot create directory {s}: {s}.", .{ path, files.describeError(create_err) }),
                };
            };
            return .{
                .ok = true,
            };
        },
        else => return .{
            .failed = failure.because("Cannot stat {s}: {s}.", .{ path, files.describeError(err) }),
        },
    };
    if (st.kind == .sym_link) {
        return .{
            .failed = failure.because("{s} is a symlink; expected a real directory.", .{path}),
        };
    }
    if (st.kind != .directory) {
        return .{
            .failed = failure.because("{s} exists and is not a directory.", .{path}),
        };
    }
    return .{
        .ok = false,
    };
}

//
// Creates dest ← link_path, or leaves an existing symlink that already names dest.
//
fn placeSymlink(io: std.Io, dest: []const u8, link_path: []const u8) failure.Result(bool) {
    const st = std.Io.Dir.cwd().statFile(io, link_path, .{
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            std.Io.Dir.cwd().symLink(io, dest, link_path, .{
                .is_directory = true,
            }) catch |create_err| {
                return .{
                    .failed = symlinkFailure(create_err, link_path),
                };
            };
            return .{
                .ok = true,
            };
        },
        else => return .{
            .failed = failure.because("Cannot stat {s}: {s}.", .{ link_path, files.describeError(err) }),
        },
    };
    if (st.kind != .sym_link) {
        return .{
            .failed = failure.because("{s} exists and is not a symlink; will not overwrite.", .{link_path}),
        };
    }
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = std.Io.Dir.cwd().readLink(io, link_path, &buffer) catch |err| {
        return .{
            .failed = failure.because("Cannot read symlink {s}: {s}.", .{ link_path, files.describeError(err) }),
        };
    };
    //
    // Windows CI: dest had `/`, readLink had `\`. Byte equality made a correct link look foreign.
    //
    if (files.samePath(buffer[0..n], dest)) {
        return .{
            .ok = false,
        };
    }
    switch (removeSymlink(io, link_path)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    std.Io.Dir.cwd().symLink(io, dest, link_path, .{
        .is_directory = true,
    }) catch |create_err| {
        return .{
            .failed = symlinkFailure(create_err, link_path),
        };
    };
    return .{
        .ok = true,
    };
}

//
// Deletes a symlink at link_path. Directory symlinks on Windows look like directories to
// deleteFile, so IsDir falls through to deleteDir rather than leaving the link in place.
//
fn removeSymlink(io: std.Io, link_path: []const u8) failure.Result(void) {
    std.Io.Dir.cwd().deleteFile(io, link_path) catch |err| switch (err) {
        error.IsDir => {
            std.Io.Dir.cwd().deleteDir(io, link_path) catch |dir_err| {
                return .{
                    .failed = failure.because("Cannot remove symlink {s}: {s}.", .{ link_path, files.describeError(dir_err) }),
                };
            };
        },
        else => return .{
            .failed = failure.because("Cannot remove symlink {s}: {s}.", .{ link_path, files.describeError(err) }),
        },
    };
    return .ok;
}

//
// True when path is a directory, optionally following a symlink to one.
//
fn isDirectory(io: std.Io, path: []const u8, follow_symlinks: bool) bool {
    const st = std.Io.Dir.cwd().statFile(io, path, .{
        .follow_symlinks = follow_symlinks,
    }) catch return false;
    return st.kind == .directory;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("link.test.zig");
}
