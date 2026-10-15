//
// Tests for context.zig.
//

const std = @import("std");
const skilled = @import("skilled");
const context = @import("context.zig");
const TestIo = @import("test_disk").TestIo;
const testing = std.testing;

test "init keeps every value it is given" {
    var test_io: TestIo = .init();
    defer test_io.deinit();
    var environ = std.process.Environ.Map.init(testing.allocator);
    defer environ.deinit();
    var stdin: std.Io.Reader = .fixed("");
    var stdout: std.Io.Writer.Allocating = .init(testing.allocator);
    defer stdout.deinit();
    var stderr: std.Io.Writer.Allocating = .init(testing.allocator);
    defer stderr.deinit();

    const ctx: context.Context = .init(testing.allocator, test_io.io(), &environ, "/project", "/home", &stdin, &stdout.writer, &stderr.writer);

    try testing.expectEqual(&environ, ctx.environ);
    try testing.expectEqualStrings("/project", ctx.cwd);
    try testing.expectEqualStrings("/home", ctx.home);
    try testing.expectEqual(&stdin, ctx.stdin);
    try testing.expectEqual(&stdout.writer, ctx.stdout);
    try testing.expectEqual(&stderr.writer, ctx.stderr);
}

test "init starts a run nobody is watching, with real git and browser processes" {
    var test_io: TestIo = .init();
    defer test_io.deinit();
    var environ = std.process.Environ.Map.init(testing.allocator);
    defer environ.deinit();
    var stdin: std.Io.Reader = .fixed("");
    var stdout: std.Io.Writer.Allocating = .init(testing.allocator);
    defer stdout.deinit();
    var stderr: std.Io.Writer.Allocating = .init(testing.allocator);
    defer stderr.deinit();

    const ctx: context.Context = .init(testing.allocator, test_io.io(), &environ, "/project", "/home", &stdin, &stdout.writer, &stderr.writer);

    try testing.expect(!ctx.style.color);
    try testing.expect(!ctx.style.icons);
    try testing.expect(ctx.non_interactive);
    try testing.expect(!ctx.stderr_is_tty);
    try testing.expect(ctx.git == .process);
    try testing.expect(ctx.browser == .process);
}
