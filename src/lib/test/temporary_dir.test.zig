//
// The throwaway directory a unit test makes when it needs real files.
//
// Test-only, so it lives in a `.test.zig` file and never in the code the tests exercise. It calls
// the standard library directly rather than `files.zig`, so both test binaries can import it by
// path without `files.zig` belonging to two modules.
//

const std = @import("std");

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
    // The largest file `read` returns, the same ceiling `files.readFile` uses.
    //
    const max_file_bytes = 16 * 1024 * 1024;

    //
    // Makes a fresh empty directory under the system temporary directory.
    //
    pub fn create(io: std.Io) !TemporaryDir {
        var random_bytes: [12]u8 = undefined;
        io.random(&random_bytes);
        const suffix = std.fmt.bytesToHex(random_bytes, .lower);

        const raw = try std.fmt.allocPrint(path_allocator, "/tmp/skilled-test-{s}", .{suffix});
        errdefer path_allocator.free(raw);
        try std.Io.Dir.cwd().createDirPath(io, raw);

        //
        // Windows cannot follow a symlink whose target is `/tmp/...` or `\tmp\...`: those have no
        // drive letter, and CI failed with OBJECT_PATH_NOT_FOUND reading a file through the
        // namespace link. realPath turns this into e.g. `D:\tmp\...` so dest is a followable path.
        //
        var dir = try std.Io.Dir.cwd().openDir(io, raw, .{});
        defer dir.close(io);
        var real_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const n = try dir.realPath(io, &real_buf);
        const path = try path_allocator.dupe(u8, real_buf[0..n]);
        path_allocator.free(raw);

        return .{
            .path = path,
            .io = io,
        };
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
        return std.Io.Dir.path.join(allocator, &.{ self.path, sub_path });
    }

    //
    // Writes a file inside the directory, creating any directories it needs.
    //
    pub fn write(self: *const TemporaryDir, sub_path: []const u8, contents: []const u8) !void {
        var buffer: [512]u8 = undefined;
        const full_path = try std.fmt.bufPrint(&buffer, "{s}/{s}", .{ self.path, sub_path });
        try std.Io.Dir.cwd().createDirPath(self.io, std.Io.Dir.path.dirname(full_path) orelse ".");
        try std.Io.Dir.cwd().writeFile(self.io, .{
            .sub_path = full_path,
            .data = contents,
        });
    }

    //
    // Reads a file from inside the directory.
    //
    pub fn read(self: *const TemporaryDir, allocator: std.mem.Allocator, sub_path: []const u8) ![]u8 {
        var buffer: [512]u8 = undefined;
        const full_path = try std.fmt.bufPrint(&buffer, "{s}/{s}", .{ self.path, sub_path });
        return std.Io.Dir.cwd().readFileAlloc(self.io, full_path, allocator, .limited(max_file_bytes));
    }

    //
    // True when something inside the directory exists.
    //
    pub fn has(self: *const TemporaryDir, sub_path: []const u8) bool {
        var buffer: [512]u8 = undefined;
        const full_path = std.fmt.bufPrint(&buffer, "{s}/{s}", .{ self.path, sub_path }) catch return false;
        const file = std.Io.Dir.cwd().openFile(self.io, full_path, .{}) catch return false;
        file.close(self.io);
        return true;
    }
};
