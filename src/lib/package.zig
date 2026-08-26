//
// Skills and commands found in a cloned package tree.
//

const std = @import("std");

//
// How a rejected package tree is described to the caller.
//
const failure = @import("failure.zig");

//
// Bounded reads of SKILL.md, command markdown, and README.md.
//
const files = @import("files.zig");

//
// Description text: frontmatter `description` or the first body paragraph.
//
const frontmatter = @import("frontmatter.zig");

//
// Alias so signatures read as Failure rather than failure.Failure.
//
const Failure = failure.Failure;

//
// Whether an item is a skill (one-level SKILL.md) or a command (recursive *.md).
//
pub const Kind = enum {
    //
    // Immediate subdirectory of skills/ that contains SKILL.md.
    //
    skill,

    //
    // A *.md file under commands/, named by its path relative to that tree.
    //
    command,
};

//
// One skill or command found under a package root.
//
// `name` is what later `ns:name` uses: the skills subdirectory, or the commands path with `.md`
// stripped and `/` separators. `rel_path` is the file inside the package, for reading and linking.
//
pub const Item = struct {
    //
    // Skill versus command, so list and docs can label them without re-deriving from the path.
    //
    kind: Kind,

    //
    // Path relative to the package root, always with `/` (`skills/hello/SKILL.md`).
    //
    rel_path: []const u8,

    //
    // Logical name: skill directory, or command path without `.md` (`plan/create`).
    //
    name: []const u8,

    //
    // Frontmatter description, or the first paragraph of the file body.
    //
    description: []const u8,
};

//
// Skills and commands under pkg_root.
//
// A valid package has a top-level `skills/` directory, a top-level `commands/` directory, or both.
// Both missing is the only layout error. An empty tree is allowed and contributes no items of that
// kind. Nested `skills/a/b/SKILL.md` is ignored; every `commands/**/*.md` is a command.
//
pub fn scan(io: std.Io, allocator: std.mem.Allocator, pkg_root: []const u8, fail: *Failure) failure.Error![]Item {
    const skills_path = try files.joinPath(allocator, &.{ pkg_root, "skills" });
    const commands_path = try files.joinPath(allocator, &.{ pkg_root, "commands" });

    var skills_dir: ?std.Io.Dir = null;
    var commands_dir: ?std.Io.Dir = null;
    defer {
        if (skills_dir) |dir| {
            dir.close(io);
        }
        if (commands_dir) |dir| {
            dir.close(io);
        }
    }

    skills_dir = openTree(io, skills_path) catch |err| {
        return fail.set("cannot open {s}: {s}", .{ skills_path, files.describeError(err) });
    };
    commands_dir = openTree(io, commands_path) catch |err| {
        return fail.set("cannot open {s}: {s}", .{ commands_path, files.describeError(err) });
    };

    if (skills_dir == null and commands_dir == null) {
        return fail.set("package at {s} has no skills/ or commands/ directory", .{pkg_root});
    }

    var items: std.ArrayList(Item) = .empty;
    if (skills_dir) |dir| {
        try scanSkills(io, allocator, pkg_root, dir, &items, fail);
    }
    if (commands_dir) |dir| {
        try scanCommands(io, allocator, pkg_root, dir, &items, fail);
    }

    const slice = try items.toOwnedSlice(allocator);
    std.mem.sort(Item, slice, {}, itemLessThan);
    return slice;
}

//
// First paragraph (or frontmatter description) of README.md / readme.md, or null when neither file
// exists.
//
// Pub so list/docs and the tests can read the package blurb without scanning GitHub.
//
pub fn readmeDescription(io: std.Io, allocator: std.mem.Allocator, pkg_root: []const u8, fail: *Failure) failure.Error!?[]const u8 {
    const names = [_][]const u8{ "README.md", "readme.md" };
    for (names) |name| {
        const path = try files.joinPath(allocator, &.{ pkg_root, name });
        const text = files.readFile(io, allocator, path) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return fail.set("cannot read {s}: {s}", .{ path, files.describeError(err) }),
        };
        return try frontmatter.extract(allocator, text);
    }
    return null;
}

//
// Opens path as a directory for iteration. Null when it is missing or not a directory.
//
fn openTree(io: std.Io, path: []const u8) !?std.Io.Dir {
    return std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => null,
        else => err,
    };
}

//
// Immediate subdirectories of skills/ that contain SKILL.md. Nested SKILL.md files are not items.
//
fn scanSkills(
    io: std.Io,
    allocator: std.mem.Allocator,
    pkg_root: []const u8,
    dir: std.Io.Dir,
    items: *std.ArrayList(Item),
    fail: *Failure,
) failure.Error!void {
    var it = dir.iterate();
    while (it.next(io) catch |err| {
        return fail.set("cannot read {s}: {s}", .{ pkg_root, files.describeError(err) });
    }) |entry| {
        if (entry.kind != .directory) {
            continue;
        }
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) {
            continue;
        }
        const name = try allocator.dupe(u8, entry.name);
        const rel_path = try std.fmt.allocPrint(allocator, "skills/{s}/SKILL.md", .{name});
        const full_path = try files.joinPath(allocator, &.{ pkg_root, rel_path });
        if (!files.fileExists(io, full_path)) {
            continue;
        }
        const text = files.readFile(io, allocator, full_path) catch |err| {
            return fail.set("cannot read {s}: {s}", .{ full_path, files.describeError(err) });
        };
        try items.append(allocator, .{
            .kind = .skill,
            .rel_path = rel_path,
            .name = name,
            .description = try frontmatter.extract(allocator, text),
        });
    }
}

//
// Every *.md file under commands/, recursively. `name` uses `/` even on Windows.
//
fn scanCommands(
    io: std.Io,
    allocator: std.mem.Allocator,
    pkg_root: []const u8,
    dir: std.Io.Dir,
    items: *std.ArrayList(Item),
    fail: *Failure,
) failure.Error!void {
    var walker = try dir.walk(allocator);
    defer {
        while (walker.next(io) catch null) |_| {}
        walker.deinit();
    }

    while (walker.next(io) catch |err| {
        return fail.set("cannot read {s}: {s}", .{ pkg_root, files.describeError(err) });
    }) |entry| {
        if (entry.kind == .directory) {
            continue;
        }
        if (!std.mem.endsWith(u8, entry.basename, ".md")) {
            continue;
        }
        const posix = try posixPath(allocator, entry.path);
        const text = entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(files.MAX_FILE_BYTES)) catch |err| {
            return fail.set("cannot read {s}: {s}", .{ posix, files.describeError(err) });
        };
        try items.append(allocator, .{
            .kind = .command,
            .rel_path = try std.fmt.allocPrint(allocator, "commands/{s}", .{posix}),
            .name = stripMd(posix),
            .description = try frontmatter.extract(allocator, text),
        });
    }
}

//
// A copy of path with `\` turned into `/`, so command names are the same on every platform.
//
fn posixPath(allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]u8 {
    const copy = try allocator.dupe(u8, path);
    std.mem.replaceScalar(u8, copy, '\\', '/');
    return copy;
}

//
// path without a trailing `.md`. The slice aliases path; the caller keeps path alive.
//
fn stripMd(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".md")) {
        return path[0 .. path.len - 3];
    }
    return path;
}

//
// Skills first, then commands; each group by name, so scan output does not follow readdir order.
//
fn itemLessThan(_: void, a: Item, b: Item) bool {
    const ka = @intFromEnum(a.kind);
    const kb = @intFromEnum(b.kind);
    if (ka != kb) {
        return ka < kb;
    }
    return std.mem.lessThan(u8, a.name, b.name);
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("package.test.zig");
}
