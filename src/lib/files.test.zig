//
// Tests for files.zig.
//

const std = @import("std");
const files = @import("files.zig");
const testing = std.testing;

//
// Windows CI failed when dest used `/` and readLink used `\`. SamePath is the comparison that fix uses.
//
test "samePath is true for identical bytes and false when they differ" {
    try testing.expect(files.samePath("/tmp/a/b", "/tmp/a/b"));
    try testing.expect(!files.samePath("/tmp/a/b", "/tmp/a/c"));
    try testing.expect(!files.samePath("/tmp/a", "/tmp/ab"));
}

//
// Windows CI failed when dest used `/` and readLink used `\`. This is the comparison that fix uses.
//
test "samePath treats slash and backslash as the same separator only on Windows" {
    try testing.expectEqual(std.fs.path.sep == '\\', files.samePath("/tmp/foo/bar", "\\tmp\\foo\\bar"));
}

test "describeError words the common failures the way a person expects" {
    try testing.expectEqualStrings("no such file or directory", files.describeError(error.FileNotFound));
    try testing.expectEqualStrings("permission denied", files.describeError(error.AccessDenied));
    try testing.expectEqualStrings("illegal operation on a directory", files.describeError(error.IsDir));
    try testing.expectEqualStrings("Unexpected", files.describeError(error.Unexpected));
}

test "each TestIo is its own implementation" {
    //
    // The point of a test making its own: two of them are two separate implementations, so nothing
    // one test does to its `Io` can be seen by another.
    //
    var first = files.TestIo.init();
    defer first.deinit();
    var second = files.TestIo.init();
    defer second.deinit();

    try testing.expect(first.io().userdata != second.io().userdata);
}

test "readFile and writeFile round trip a file" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    const path = try temporary.join(allocator, "nested/file.txt");
    try files.makeParentDir(io, path);
    try files.writeFile(io, path, "contents");
    try testing.expectEqualStrings("contents", try files.readFile(io, allocator, path));
}

test "fileExists answers for a file that is there and one that is not" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("here.txt", "x");
    try testing.expect(files.fileExists(io, try temporary.join(allocator, "here.txt")));
    try testing.expect(!files.fileExists(io, try temporary.join(allocator, "gone.txt")));
}

test "readFile reports a missing file rather than returning nothing" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try testing.expectError(error.FileNotFound, files.readFile(io, allocator, try temporary.join(allocator, "gone.txt")));
}

test "makeDirPath creates every directory in the path" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    const deep = try temporary.join(allocator, "a/b/c");
    try files.makeDirPath(io, deep);
    try files.makeDirPath(io, deep); // Doing it twice is not an error.

    try files.writeFile(io, try temporary.join(allocator, "a/b/c/file.txt"), "x");
    try testing.expect(temporary.has("a/b/c/file.txt"));
}

test "TemporaryDir gives each caller its own directory" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var first = try files.TemporaryDir.create(io);
    defer first.destroy();
    var second = try files.TemporaryDir.create(io);
    defer second.destroy();

    try testing.expect(!std.mem.eql(u8, first.path, second.path));

    try first.write("only-here.txt", "x");
    try testing.expect(first.has("only-here.txt"));
    try testing.expect(!second.has("only-here.txt"));
}

test "TemporaryDir from two threads get distinct directories" {
    //
    // Zig runs tests on multiple threads; this makes that overlap explicit so a regression to a
    // shared path fails here rather than as a flake in some other file.
    //
    const Slot = struct {
        //
        // Copied path bytes. The TemporaryDir frees its path on destroy, so the thread keeps a copy.
        //
        buf: [256]u8 = undefined,

        //
        // How many bytes of buf are the path.
        //
        len: usize = 0,

        //
        // True when the thread created a dir, wrote a marker, and copied the path.
        //
        wrote: bool = false,
    };

    const Worker = struct {
        fn run(slot: *Slot) void {
            var test_io = files.TestIo.init();
            defer test_io.deinit();
            var dir = files.TemporaryDir.create(test_io.io()) catch return;
            defer dir.destroy();
            dir.write("marker.txt", "x") catch return;
            if (!dir.has("marker.txt")) {
                return;
            }
            const n = @min(slot.buf.len, dir.path.len);
            @memcpy(slot.buf[0..n], dir.path[0..n]);
            slot.len = n;
            slot.wrote = true;
        }
    };

    var first = Slot{};
    var second = Slot{};
    const first_thread = try std.Thread.spawn(.{}, Worker.run, .{&first});
    const second_thread = try std.Thread.spawn(.{}, Worker.run, .{&second});
    first_thread.join();
    second_thread.join();

    try testing.expect(first.wrote);
    try testing.expect(second.wrote);
    try testing.expect(!std.mem.eql(u8, first.buf[0..first.len], second.buf[0..second.len]));
}
