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
// Alias so signatures read as Failure rather than failure.Failure.
//
const Failure = failure.Failure;

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
    fail: *Failure,
) failure.Error!Status {
    try remote.validateName(namespace, "namespace", fail);
    var changed = false;
    const skills_dir = try files.joinPath(allocator, &.{ store_dir, "skills" });
    const commands_dir = try files.joinPath(allocator, &.{ store_dir, "commands" });
    const has_skills = isDirectory(io, skills_dir, true);
    const has_commands = isDirectory(io, commands_dir, true);
    if (has_skills) {
        changed = try linkTree(io, allocator, store_dir, "skills", namespace, scope.cursor_skills, fail) or changed;
        if (has_commands) {
            changed = try linkTree(io, allocator, store_dir, "skills", namespace, scope.claude_skills, fail) or changed;
        } else {
            changed = try linkTree(io, allocator, store_dir, "skills", namespace, scope.claude_commands, fail) or changed;
        }
    }
    if (has_commands) {
        changed = try linkTree(io, allocator, store_dir, "commands", namespace, scope.cursor_commands, fail) or changed;
        changed = try linkTree(io, allocator, store_dir, "commands", namespace, scope.claude_commands, fail) or changed;
    }
    changed = try unlinkTree(io, allocator, store_dir, "commands", namespace, scope.cursor_skills, fail) or changed;
    changed = try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.cursor_commands, fail) or changed;
    return if (changed) .changed else .unchanged;
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
    fail: *Failure,
) failure.Error!void {
    try remote.validateName(namespace, "namespace", fail);
    _ = try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.cursor_skills, fail);
    _ = try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.claude_skills, fail);
    _ = try unlinkTree(io, allocator, store_dir, "commands", namespace, scope.cursor_skills, fail);
    _ = try unlinkTree(io, allocator, store_dir, "commands", namespace, scope.claude_commands, fail);
    _ = try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.claude_commands, fail);
    _ = try unlinkTree(io, allocator, store_dir, "commands", namespace, scope.cursor_commands, fail);
    _ = try unlinkTree(io, allocator, store_dir, "skills", namespace, scope.cursor_commands, fail);
}

//
// Turns a failed symlink create into a Failure.
//
// AccessDenied and PermissionDenied mention Developer Mode because that is what Windows needs
// (or an equivalent privilege) to create directory symlinks; the code never falls back to copying.
// Pub so tests can fake the syscall failure without a host that refuses directory symlinks.
//
pub fn mapSymlinkError(err: anyerror, path: []const u8, fail: *Failure) failure.Error {
    switch (err) {
        error.AccessDenied, error.PermissionDenied => return fail.set(
            "Cannot create symlink {s}: enable Developer Mode (or equivalent) to allow directory symlinks.",
            .{path},
        ),
        else => return fail.set("Cannot create symlink {s}: {s}.", .{ path, files.describeError(err) }),
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
    fail: *Failure,
) failure.Error!bool {
    const store_tree = try files.joinPath(allocator, &.{ store_dir, tree });
    if (!isDirectory(io, store_tree, true)) {
        return false;
    }
    const made_root = try ensureAgentRoot(io, agent_root, fail);
    const link_path = try files.joinPath(allocator, &.{ agent_root, namespace });
    const placed = try placeSymlink(io, store_tree, link_path, fail);
    return made_root or placed;
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
    fail: *Failure,
) failure.Error!bool {
    const store_tree = try files.joinPath(allocator, &.{ store_dir, tree });
    const link_path = try files.joinPath(allocator, &.{ agent_root, namespace });
    const st = std.Io.Dir.cwd().statFile(io, link_path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return fail.set("Cannot stat {s}: {s}.", .{ link_path, files.describeError(err) }),
    };
    if (st.kind != .sym_link) {
        return false;
    }
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = std.Io.Dir.cwd().readLink(io, link_path, &buffer) catch |err| {
        return fail.set("Cannot read symlink {s}: {s}.", .{ link_path, files.describeError(err) });
    };
    //
    // Windows CI: dest had `/`, readLink had `\`. Byte equality skipped the delete.
    //
    if (!files.samePath(buffer[0..n], store_tree)) {
        return false;
    }
    try removeSymlink(io, link_path, fail);
    return true;
}

//
// `.cursor` / `.claude` and the skills or commands directory under them, as real directories.
//
// Checked without following symlinks first so a folded parent (a symlink to the store) is refused
// rather than written through.
//
fn ensureAgentRoot(io: std.Io, agent_root: []const u8, fail: *Failure) failure.Error!bool {
    const made_parent = try ensureRealDirectory(io, files.dirName(agent_root), fail);
    const made_root = try ensureRealDirectory(io, agent_root, fail);
    return made_parent or made_root;
}

//
// Creates path as a real directory, or accepts one that already is. A symlink here is the stow
// tree-folding hazard and is an error.
//
// Pub because the scratch module creates `<scratch>/skills` and `<scratch>/commands` with it, so a
// symlink or a regular file at either path is refused in the same words as an agent root.
//
pub fn ensureRealDirectory(io: std.Io, path: []const u8, fail: *Failure) failure.Error!bool {
    const st = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => {
            files.makeDirPath(io, path) catch |create_err| {
                return fail.set("Cannot create directory {s}: {s}.", .{ path, files.describeError(create_err) });
            };
            return true;
        },
        else => return fail.set("Cannot stat {s}: {s}.", .{ path, files.describeError(err) }),
    };
    if (st.kind == .sym_link) {
        return fail.set("{s} is a symlink; expected a real directory.", .{path});
    }
    if (st.kind != .directory) {
        return fail.set("{s} exists and is not a directory.", .{path});
    }
    return false;
}

//
// Creates dest ← link_path, or leaves an existing symlink that already names dest.
//
fn placeSymlink(io: std.Io, dest: []const u8, link_path: []const u8, fail: *Failure) failure.Error!bool {
    const st = std.Io.Dir.cwd().statFile(io, link_path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => {
            std.Io.Dir.cwd().symLink(io, dest, link_path, .{ .is_directory = true }) catch |create_err| {
                return mapSymlinkError(create_err, link_path, fail);
            };
            return true;
        },
        else => return fail.set("Cannot stat {s}: {s}.", .{ link_path, files.describeError(err) }),
    };
    if (st.kind != .sym_link) {
        return fail.set("{s} exists and is not a symlink; will not overwrite.", .{link_path});
    }
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = std.Io.Dir.cwd().readLink(io, link_path, &buffer) catch |err| {
        return fail.set("Cannot read symlink {s}: {s}.", .{ link_path, files.describeError(err) });
    };
    //
    // Windows CI: dest had `/`, readLink had `\`. Byte equality made a correct link look foreign.
    //
    if (files.samePath(buffer[0..n], dest)) {
        return false;
    }
    try removeSymlink(io, link_path, fail);
    std.Io.Dir.cwd().symLink(io, dest, link_path, .{ .is_directory = true }) catch |create_err| {
        return mapSymlinkError(create_err, link_path, fail);
    };
    return true;
}

//
// Deletes a symlink at link_path. Directory symlinks on Windows look like directories to
// deleteFile, so IsDir falls through to deleteDir rather than leaving the link in place.
//
fn removeSymlink(io: std.Io, link_path: []const u8, fail: *Failure) failure.Error!void {
    std.Io.Dir.cwd().deleteFile(io, link_path) catch |err| switch (err) {
        error.IsDir => {
            std.Io.Dir.cwd().deleteDir(io, link_path) catch |dir_err| {
                return fail.set("Cannot remove symlink {s}: {s}.", .{ link_path, files.describeError(dir_err) });
            };
        },
        else => return fail.set("Cannot remove symlink {s}: {s}.", .{ link_path, files.describeError(err) }),
    };
}

//
// True when path is a directory, optionally following a symlink to one.
//
fn isDirectory(io: std.Io, path: []const u8, follow_symlinks: bool) bool {
    const st = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = follow_symlinks }) catch return false;
    return st.kind == .directory;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("link.test.zig");
}
