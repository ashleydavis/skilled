//
// The filesystem operations the rest of the tool is built out of.
//
// Zig 0.16 made every filesystem call take an `Io`: the interface that decides how blocking work is
// actually performed. Every function here that touches a disk takes one and passes it on, so there
// is no hidden answer to "which implementation is this using". The CLI creates exactly one, in
// main, from what the runtime handed the process, and it reaches everything else by being passed.
//
// A test creates its own with `TestIo`, which is what lets two tests run against different `Io`
// instances without either being able to affect the other.
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
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = contents });
}

//
// A throwaway directory, for tests that need real files.
//
// Every test that touches disk gets its own, so tests never see each other's files. Zig runs unit
// tests on multiple threads in one binary, and two test processes can overlap; a counter or a
// fixed `/tmp/skl-test` path would collide. The name carries random bytes so two callers, even in
// the same process, cannot share a directory.
//
pub const TemporaryDir = struct {
    //
    // Where the directory is, as an absolute path.
    //
    // Allocated rather than held in a buffer inside this struct. A slice pointing into the struct's
    // own storage would dangle the moment the struct was copied, which is exactly what happens when
    // `create` returns one.
    //
    path: []const u8,

    //
    // The `Io` the directory was made with, used for everything done to it afterwards.
    //
    // Held rather than passed to each method because a directory only ever makes sense against the
    // implementation that created it.
    //
    io: std.Io,

    //
    // Where the path is allocated from. The page allocator rather than a caller's, so a test needs
    // no allocator to make a directory, and nothing here can be mistaken for a leak in the code
    // under test.
    //
    const path_allocator = std.heap.page_allocator;

    //
    // Makes a fresh empty directory under the system temporary directory.
    //
    pub fn create(io: std.Io) !TemporaryDir {
        var random_bytes: [12]u8 = undefined;
        io.random(&random_bytes);
        const suffix = std.fmt.bytesToHex(random_bytes, .lower);

        const path = try std.fmt.allocPrint(path_allocator, "/tmp/skilled-test-{s}", .{suffix});
        errdefer path_allocator.free(path);

        try makeDirPath(io, path);
        return .{ .path = path, .io = io };
    }

    //
    // Removes the directory and everything in it.
    //
    pub fn destroy(self: *TemporaryDir) void {
        std.Io.Dir.cwd().deleteTree(self.io, self.path) catch {};
        path_allocator.free(self.path);
        self.path = &.{};
    }

    //
    // The absolute path of something inside the directory.
    //
    pub fn join(self: *const TemporaryDir, allocator: std.mem.Allocator, sub_path: []const u8) ![]const u8 {
        return joinPath(allocator, &.{ self.path, sub_path });
    }

    //
    // Writes a file inside the directory, creating any directories it needs.
    //
    pub fn write(self: *const TemporaryDir, sub_path: []const u8, contents: []const u8) !void {
        var buffer: [512]u8 = undefined;
        const full_path = try std.fmt.bufPrint(&buffer, "{s}/{s}", .{ self.path, sub_path });
        try makeParentDir(self.io, full_path);
        try writeFile(self.io, full_path, contents);
    }

    //
    // Reads a file from inside the directory.
    //
    pub fn read(self: *const TemporaryDir, allocator: std.mem.Allocator, sub_path: []const u8) ![]u8 {
        var buffer: [512]u8 = undefined;
        const full_path = try std.fmt.bufPrint(&buffer, "{s}/{s}", .{ self.path, sub_path });
        return readFile(self.io, allocator, full_path);
    }

    //
    // True when something inside the directory exists.
    //
    pub fn has(self: *const TemporaryDir, sub_path: []const u8) bool {
        var buffer: [512]u8 = undefined;
        const full_path = std.fmt.bufPrint(&buffer, "{s}/{s}", .{ self.path, sub_path }) catch return false;
        return fileExists(self.io, full_path);
    }
};

//
// An `Io` for one test, torn down with it.
//
// Every test that touches a disk makes its own rather than sharing one, so nothing a test does to
// its `Io` can reach another test. Held by the caller, because the `Io` handed out points back at
// the `Threaded` inside it and a copy would leave that pointer aimed at the wrong place.
//
pub const TestIo = struct {
    //
    // The threaded implementation the `Io` interface points at.
    //
    // Must live in this struct, not on the stack of `init`, so the pointer inside the `Io` stays
    // valid for as long as the test holds the `TestIo`.
    //
    threaded: std.Io.Threaded,

    //
    // The page allocator rather than the testing allocator: this belongs to the test itself, not to
    // the code under test, so it must not show up in that code's leak checking.
    //
    pub fn init() TestIo {
        return .{ .threaded = .init(std.heap.page_allocator, .{}) };
    }

    //
    // The `Io` to pass into filesystem calls under test.
    //
    pub fn io(self: *TestIo) std.Io {
        return self.threaded.io();
    }

    //
    // Tears down the threaded implementation.
    //
    pub fn deinit(self: *TestIo) void {
        self.threaded.deinit();
    }
};

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("files.test.zig");
}
