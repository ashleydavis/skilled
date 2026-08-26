//
// Tests for package.zig.
//

const std = @import("std");
const failure = @import("failure.zig");
const files = @import("files.zig");
const package = @import("package.zig");
const testing = std.testing;

//
// Finds an item by kind and name so tests do not depend on scan order beyond the sort.
//
fn findItem(items: []const package.Item, kind: package.Kind, name: []const u8) ?package.Item {
    for (items) |item| {
        if (item.kind == kind and std.mem.eql(u8, item.name, name)) {
            return item;
        }
    }
    return null;
}

test "scan reads a skills-only package" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("skills/hello/SKILL.md",
        \\---
        \\description: Says hello
        \\---
        \\
        \\# Hello
        \\
    );
    try temporary.write("README.md", "A pack of demo skills.\n");

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqual(@as(usize, 1), items.len);
    try testing.expectEqual(package.Kind.skill, items[0].kind);
    try testing.expectEqualStrings("hello", items[0].name);
    try testing.expectEqualStrings("skills/hello/SKILL.md", items[0].rel_path);
    try testing.expectEqualStrings("Says hello", items[0].description);

    var readme_fail = failure.Failure.init(allocator);
    const readme = try package.readmeDescription(io, allocator, temporary.path, &readme_fail);
    try testing.expectEqualStrings("A pack of demo skills.", readme.?);
}

test "scan reads a commands-only package" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("commands/plan/create.md",
        \\---
        \\description: Create a plan
        \\---
        \\
        \\Write a plan.
        \\
    );

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqual(@as(usize, 1), items.len);
    try testing.expectEqual(package.Kind.command, items[0].kind);
    try testing.expectEqualStrings("plan/create", items[0].name);
    try testing.expectEqualStrings("commands/plan/create.md", items[0].rel_path);
    try testing.expectEqualStrings("Create a plan", items[0].description);
}

test "scan reads a package with both trees" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("skills/hello/SKILL.md", "Hello skill.\n");
    try temporary.write("commands/ping.md", "Ping command.\n");

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqual(@as(usize, 2), items.len);
    const skill = findItem(items, .skill, "hello").?;
    try testing.expectEqualStrings("Hello skill.", skill.description);
    const command = findItem(items, .command, "ping").?;
    try testing.expectEqualStrings("Ping command.", command.description);
}

test "scan errors when both trees are missing" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("README.md", "Not a package.\n");

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, package.scan(io, allocator, temporary.path, &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "skills/") != null);
    try testing.expect(std.mem.indexOf(u8, fail.text(), "commands/") != null);
}

test "scan accepts an empty skills directory with no skill items" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try files.makeDirPath(io, try temporary.join(allocator, "skills"));

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqual(@as(usize, 0), items.len);
}

test "scan names a nested command plan/create" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("commands/plan/create.md", "Nested.\n");
    try temporary.write("commands/top.md", "Top level.\n");

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqual(@as(usize, 2), items.len);
    try testing.expect(findItem(items, .command, "plan/create") != null);
    try testing.expect(findItem(items, .command, "top") != null);
    try testing.expect(findItem(items, .command, "create") == null);
}

test "scan ignores a nested SKILL.md" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("skills/hello/SKILL.md", "Top skill.\n");
    try temporary.write("skills/hello/nested/SKILL.md", "Must be ignored.\n");

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqual(@as(usize, 1), items.len);
    try testing.expectEqualStrings("hello", items[0].name);
    try testing.expectEqualStrings("Top skill.", items[0].description);
}

test "scan succeeds when README is missing" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("skills/hello/SKILL.md", "Hello.\n");

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqual(@as(usize, 1), items.len);

    var readme_fail = failure.Failure.init(allocator);
    try testing.expectEqual(@as(?[]const u8, null), try package.readmeDescription(io, allocator, temporary.path, &readme_fail));
}

test "scan uses a single-line frontmatter description on a skill" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("skills/hello/SKILL.md",
        \\---
        \\description: From frontmatter
        \\---
        \\
        \\From body.
        \\
    );

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqualStrings("From frontmatter", items[0].description);
}

test "scan falls back to the body when frontmatter is missing" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("skills/hello/SKILL.md",
        \\First paragraph of the body.
        \\
        \\Second paragraph.
        \\
    );

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqualStrings("First paragraph of the body.", items[0].description);
}

test "scan falls back to the body when frontmatter uses a multi-line scalar" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("skills/hello/SKILL.md",
        \\---
        \\description: |
        \\  line one
        \\  line two
        \\---
        \\
        \\Body paragraph.
        \\
    );

    var fail = failure.Failure.init(allocator);
    const items = try package.scan(io, allocator, temporary.path, &fail);
    try testing.expectEqualStrings("Body paragraph.", items[0].description);
}

test "readmeDescription reads readme.md when README.md is absent" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    try temporary.write("skills/hello/SKILL.md", "Hello.\n");
    try temporary.write("readme.md", "Lowercase readme.\n");

    var fail = failure.Failure.init(allocator);
    const readme = try package.readmeDescription(io, allocator, temporary.path, &fail);
    try testing.expectEqualStrings("Lowercase readme.", readme.?);
}
