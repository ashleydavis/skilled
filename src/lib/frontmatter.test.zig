//
// Tests for frontmatter.zig.
//

const std = @import("std");
const frontmatter = @import("frontmatter.zig");
const testing = std.testing;

test "extract reads a single-line frontmatter description" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("A useful skill", try frontmatter.extract(arena.allocator(),
        \\---
        \\description: A useful skill
        \\---
        \\
        \\# Title
        \\
        \\Body that must not win.
        \\
    ));
}

test "extract reads a quoted single-line frontmatter description" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("A: useful skill", try frontmatter.extract(arena.allocator(),
        \\---
        \\description: "A: useful skill"
        \\---
        \\
        \\Body.
        \\
    ));
}

test "extract falls back to the first body paragraph when frontmatter is missing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("This is the first paragraph.", try frontmatter.extract(arena.allocator(),
        \\This is the first paragraph.
        \\
        \\This is the second.
        \\
    ));
}

test "extract falls back to the body when description is absent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("Body paragraph.", try frontmatter.extract(arena.allocator(),
        \\---
        \\name: hello
        \\---
        \\
        \\Body paragraph.
        \\
        \\Later.
        \\
    ));
}

test "extract falls back to the body when the YAML fence is unclosed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("---\ndescription: never closed", try frontmatter.extract(arena.allocator(),
        \\---
        \\description: never closed
        \\
        \\Body.
        \\
    ));
}

test "extract falls back to the body when description is a multi-line scalar" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("Body paragraph.", try frontmatter.extract(arena.allocator(),
        \\---
        \\description: |
        \\  line one
        \\  line two
        \\---
        \\
        \\Body paragraph.
        \\
    ));
}

test "extract falls back to the body when description is not a string" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("Body paragraph.", try frontmatter.extract(arena.allocator(),
        \\---
        \\description: 42
        \\---
        \\
        \\Body paragraph.
        \\
    ));
}

test "extract treats a file of only a paragraph as that paragraph" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("Just one line.", try frontmatter.extract(arena.allocator(), "Just one line.\n"));
}

test "extract returns empty when the file is empty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqualStrings("", try frontmatter.extract(arena.allocator(), ""));
}
