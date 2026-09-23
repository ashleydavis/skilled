//
// The per-scope scratch directory, linked into Cursor and Claude as `loc`.
//
// A place to keep a skill or a slash command without making a git repository for it. The directory
// holds the same `skills/` and `commands/` trees a package has, so the linker and the scanner need
// no special case: it is linked exactly like a package that happens to have no remote and no YAML
// row. Creating and linking it is one call, `sync`, so every command that repairs the links does
// the same thing.
//

const std = @import("std");

//
// How a refused create or link is described to the caller.
//
const failure = @import("failure.zig");

//
// Path joining for the two trees under the scratch directory.
//
const files = @import("files.zig");

//
// The namespace symlinks themselves, and the real-directory check the trees are created with.
//
const link = @import("link.zig");

//
// The agent roots and the scratch path for the active scope.
//
const paths = @import("paths.zig");

//
// Alias so signatures read as Failure rather than failure.Failure.
//
const Failure = failure.Failure;

//
// The namespace the scratch trees are linked under, in both agents.
//
// Named once here because three other places depend on it: `config` refuses it as a package
// namespace, `add` refuses it on `--ns`, and the commands print it when a query names it. A second
// copy of the string is a second answer to "which namespace is reserved".
//
pub const namespace = "loc";

//
// True when a namespace is the reserved one.
//
// The reserved rule has one implementation so a YAML row and a `--ns` flag cannot disagree.
//
pub fn isReserved(candidate: []const u8) bool {
    return std.mem.eql(u8, candidate, namespace);
}

//
// Creates `<scratch>/skills` and `<scratch>/commands`, and the parents above them.
//
// Both trees are made even when the user only wants one, because a package with both trees is what
// gives Claude `skills/loc` and `commands/loc` directly rather than the skills-only remap. An empty
// tree is a valid package that contributes no items. Existing directories are left alone; a symlink
// or a regular file at either path is an error. True when a directory had to be created.
//
pub fn ensureTrees(
    io: std.Io,
    allocator: std.mem.Allocator,
    scratch_dir: []const u8,
    fail: *Failure,
) failure.Error!bool {
    const made_root = try link.ensureRealDirectory(io, scratch_dir, fail);
    const made_skills = try link.ensureRealDirectory(io, try files.joinPath(allocator, &.{ scratch_dir, "skills" }), fail);
    const made_commands = try link.ensureRealDirectory(io, try files.joinPath(allocator, &.{ scratch_dir, "commands" }), fail);
    return made_root or made_skills or made_commands;
}

//
// Whether a sync had anything to do, so a caller can stay quiet when it did not.
//
pub const Status = enum {
    //
    // Both trees and all four links were already in place; nothing was created.
    //
    unchanged,

    //
    // A tree or a link was missing or pointed elsewhere, and was created or repaired.
    //
    changed,
};

//
// Creates the trees for this scope and links them into Cursor and Claude as `loc`.
//
// Idempotent: `linkPackage` leaves a link that already points at the tree, replaces one that points
// elsewhere, and refuses a real file. That is what lets `install` and `update` repair a namespace a
// user deleted without any repair code of their own.
//
// The trees and the linker each say whether they had to do anything, so the caller can tell a
// repair from a no-op: a command that announced the scratch directory on every run would bury the
// result the user asked for.
//
pub fn sync(
    io: std.Io,
    allocator: std.mem.Allocator,
    scope: paths.Scope,
    fail: *Failure,
) failure.Error!Status {
    const made_trees = try ensureTrees(io, allocator, scope.scratch_dir, fail);
    const linked = try link.linkPackage(io, allocator, scope.scratch_dir, namespace, scope, fail);
    return if (made_trees or linked == .changed) .changed else .unchanged;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("scratch.test.zig");
}
