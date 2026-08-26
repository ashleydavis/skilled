//
// Tests for progress.zig.
//

const std = @import("std");
const term = @import("term.zig");
const progress = @import("progress.zig");
const testing = std.testing;

//
// A style with color on, so an enabled progress line can be built without going through detectStyle.
//
const style_on = term.Style{ .color = true, .icons = true };

//
// A style with color off. Progress must be a no-op against this even on a TTY.
//
const style_off = term.Style{ .color = false, .icons = false };

test "Progress is a no-op when style is disabled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var captured = std.Io.Writer.Allocating.init(arena.allocator());
    var spinner = progress.Progress.init(&captured.writer, style_off, false, true);
    try testing.expect(!spinner.enabled);

    spinner.cloning("acme/skills");
    spinner.linking("demo/skills");
    spinner.tick();
    spinner.finish();
    try testing.expectEqualStrings("", captured.written());
}

test "Progress is a no-op when non-interactive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var captured = std.Io.Writer.Allocating.init(arena.allocator());
    var spinner = progress.Progress.init(&captured.writer, style_on, true, true);
    try testing.expect(!spinner.enabled);

    spinner.cloning("acme/skills");
    spinner.finish();
    try testing.expectEqualStrings("", captured.written());
}

test "Progress is a no-op when stderr is not a TTY" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var captured = std.Io.Writer.Allocating.init(arena.allocator());
    var spinner = progress.Progress.init(&captured.writer, style_on, false, false);
    try testing.expect(!spinner.enabled);

    spinner.cloning("acme/skills");
    spinner.finish();
    try testing.expectEqualStrings("", captured.written());
}

test "Progress writes clone and link steps to the buffer when enabled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var captured = std.Io.Writer.Allocating.init(arena.allocator());
    var spinner = progress.Progress.init(&captured.writer, style_on, false, true);
    try testing.expect(spinner.enabled);

    spinner.cloning("acme/skills");
    try testing.expect(std.mem.indexOf(u8, captured.written(), "Cloning acme/skills…") != null);
    try testing.expect(std.mem.indexOf(u8, captured.written(), "\x1b[2K") != null);

    spinner.linking("demo/skills");
    try testing.expect(std.mem.indexOf(u8, captured.written(), "Linking demo/skills…") != null);

    spinner.tick();
    spinner.finish();
    try testing.expect(std.mem.endsWith(u8, captured.written(), "\r\x1b[2K"));
}
