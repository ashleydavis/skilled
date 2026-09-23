//
// Tests for term.zig.
//

const std = @import("std");
const term = @import("term.zig");
const testing = std.testing;

test "detectStyle enables color and icons on a TTY with nothing disabling them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());

    const style = term.detectStyle(&.{}, &env, true);
    try testing.expect(style.color);
    try testing.expect(style.icons);
    //
    // With color on the marks carry their own escape, so the icon is present and wrapped rather
    // than returned bare.
    //
    try testing.expect(std.mem.indexOf(u8, style.check(), term.check_icon) != null);
    try testing.expect(std.mem.startsWith(u8, style.check(), "\x1b[32m"));
    try testing.expect(std.mem.indexOf(u8, style.cross(), term.cross_icon) != null);
    try testing.expect(std.mem.startsWith(u8, style.cross(), "\x1b[31m"));
    try testing.expect(std.mem.indexOf(u8, style.arrow(), term.arrow_icon) != null);
    try testing.expectEqualStrings(term.package_icon, style.package());
}

test "detectStyle turns color and icons off for --no-color" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());

    const style = term.detectStyle(&.{ "list", "--no-color" }, &env, true);
    try testing.expect(!style.color);
    try testing.expect(!style.icons);
    try testing.expectEqualStrings("OK", style.check());
    try testing.expectEqualStrings("X", style.cross());
    try testing.expectEqualStrings("->", style.arrow());
    try testing.expectEqualStrings("#", style.package());
}

test "detectStyle turns color off when NO_COLOR is set to any value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    try env.put("NO_COLOR", "");

    try testing.expect(!term.detectStyle(&.{}, &env, true).color);

    try env.put("NO_COLOR", "0");
    try testing.expect(!term.detectStyle(&.{}, &env, true).color);
}

test "detectStyle turns color off when SKL_NO_COLOR is 1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    try env.put("SKL_NO_COLOR", "1");

    try testing.expect(!term.detectStyle(&.{}, &env, true).color);
}

test "detectStyle leaves color on when SKL_NO_COLOR is not 1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    try env.put("SKL_NO_COLOR", "0");

    try testing.expect(term.detectStyle(&.{}, &env, true).color);
}

test "detectStyle turns color off when stdout is not a TTY" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());

    const style = term.detectStyle(&.{}, &env, false);
    try testing.expect(!style.color);
    try testing.expect(!style.icons);
}

test "nonInteractive is false on a TTY with nothing forcing it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());

    try testing.expect(!term.nonInteractive(&.{}, &env, true));
}

test "nonInteractive is true for --non-interactive and -n" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());

    try testing.expect(term.nonInteractive(&.{"--non-interactive"}, &env, true));
    try testing.expect(term.nonInteractive(&.{ "add", "-n" }, &env, true));
}

test "nonInteractive is true when SKL_NONINTERACTIVE is 1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    try env.put("SKL_NONINTERACTIVE", "1");

    try testing.expect(term.nonInteractive(&.{}, &env, true));
}

test "nonInteractive is false when SKL_NONINTERACTIVE is not 1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    try env.put("SKL_NONINTERACTIVE", "0");

    try testing.expect(!term.nonInteractive(&.{}, &env, true));
}

test "nonInteractive is true when stdin is not a TTY" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());

    try testing.expect(term.nonInteractive(&.{}, &env, false));
}

test "marks carry no escape when color is off" {
    const style = term.Style{ .color = false, .icons = false };
    try testing.expectEqualStrings("OK", style.check());
    try testing.expectEqualStrings("X", style.cross());
    try testing.expectEqualStrings("->", style.arrow());
    try testing.expectEqualStrings("#", style.package());
}
