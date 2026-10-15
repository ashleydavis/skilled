//
// The filesystem operations the rest of the tool is built out of.
//
// Zig 0.16 made every filesystem call take an `Io`: the interface that decides how blocking work is
// actually performed. Every function here that touches a disk takes one and passes it on, so there
// is no hidden answer to "which implementation is this using". The CLI creates exactly one, in
// main, from what the runtime handed the process, and it reaches everything else by being passed.
//

const std = @import("std");

//
// Path handling. Separate from the I/O above because none of it touches a disk: it is string
// manipulation, and it is the same in every Zig version.
//
const path_util = std.Io.Dir.path;

//
// The largest file that will be read in one go.
//
// Config YAML and skill/command markdown are small; a ceiling is needed because reading an
// unbounded amount into memory on the word of a filename is how a corrupted path takes a process
// down.
//
pub const MAX_FILE_BYTES = 16 * 1024 * 1024;

//
// Reads a whole file into memory.
//
pub fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(MAX_FILE_BYTES));
}

//
// True when a file can be opened for reading.
//
// Opening rather than stat-ing matches what later callers do: a path that exists but cannot be
// read is skipped rather than chosen and then refused.
//
pub fn fileExists(io: std.Io, path: []const u8) bool {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

//
// Describes a filesystem error in the words a person expects to see.
//
pub fn describeError(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "no such file or directory",
        error.AccessDenied, error.PermissionDenied => "permission denied",
        error.IsDir => "illegal operation on a directory",
        error.NotDir => "not a directory",
        error.NameTooLong => "file name too long",
        error.SymLinkLoop => "too many symbolic links encountered",
        error.FileTooBig, error.StreamTooLong => "file too large",
        error.NoSpaceLeft => "no space left on device",
        error.SystemResources, error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded => "too many open files",
        error.OutOfMemory => "out of memory",
        else => @errorName(err),
    };
}

//
// The directory a path is in, or "." when it names something in the working directory.
//
pub fn dirName(path: []const u8) []const u8 {
    return path_util.dirname(path) orelse ".";
}

//
// Joins path segments.
//
pub fn joinPath(allocator: std.mem.Allocator, segments: []const []const u8) std.mem.Allocator.Error![]const u8 {
    return path_util.join(allocator, segments);
}

//
// Absolute path for a local working tree, resolved against cwd when `path` is relative.
//
// Already-absolute paths are copied so the caller can store them in YAML. Relative paths are
// joined onto cwd; this does not chdir.
//
pub fn absolutePath(allocator: std.mem.Allocator, cwd: []const u8, path: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.fs.path.isAbsolute(path)) {
        return allocator.dupe(u8, path);
    }
    return joinPath(allocator, &.{ cwd, path });
}

//
// True when two paths name the same location on this host.
//
// Windows CI failed because readLink returns `\tmp\...` while dest was `/tmp/...\store\skills`.
// Byte equality treated a correct namespace link as pointing elsewhere, so install/update errored
// and unlink skipped the delete.
//
pub fn samePath(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }
    for (a, b) |left, right| {
        if (left == right) {
            continue;
        }
        if (path_util.isSep(left) and path_util.isSep(right)) {
            continue;
        }
        return false;
    }
    return true;
}

//
// Creates a directory and every directory above it, doing nothing when it is already there.
//
pub fn makeDirPath(io: std.Io, path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, path);
}

//
// Creates the directory a file is going to be written into.
//
pub fn makeParentDir(io: std.Io, path: []const u8) !void {
    try makeDirPath(io, dirName(path));
}

//
// Writes a whole file, replacing whatever was there.
//
pub fn writeFile(io: std.Io, path: []const u8, contents: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = contents,
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("files.test.zig");
}
