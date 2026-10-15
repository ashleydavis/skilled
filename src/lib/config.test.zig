//
// Tests for config.zig.
//

const std = @import("std");
const config = @import("config.zig");
const failure = @import("failure.zig");
const files = @import("files.zig");
const TemporaryDir = @import("test_disk").TemporaryDir;
const TestIo = @import("test_disk").TestIo;
const testing = std.testing;
const expect_result = @import("expect_result");

//
// Two packages used as the round-trip fixture: shorthand plus an SSH URL, distinct namespaces.
//
const sample_yaml =
    \\packages:
    \\  - repo: owner/repo
    \\    namespace: demo
    \\  - repo: git@github.example.com:acme/skills.git
    \\    namespace: pla
    \\
;

test "parse reads a list of repo and namespace objects" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try expect_result.ok(try config.parse(allocator, sample_yaml));
    try testing.expectEqual(@as(usize, 2), file.packages.len);
    try testing.expectEqualStrings("owner/repo", file.packages[0].repo);
    try testing.expectEqualStrings("demo", file.packages[0].namespace);
    try testing.expect(file.packages[0].branch == null);
    try testing.expect(file.packages[0].local == null);
    try testing.expectEqualStrings("git@github.example.com:acme/skills.git", file.packages[1].repo);
    try testing.expectEqualStrings("pla", file.packages[1].namespace);
}

test "parse accepts an empty packages list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try expect_result.ok(try config.parse(allocator, "packages: []\n"));
    try testing.expectEqual(@as(usize, 0), file.packages.len);
}

test "stringify then parse round-trips a list of packages" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const original = try expect_result.ok(try config.parse(allocator, sample_yaml));
    const rendered = try config.stringify(allocator, original);
    try testing.expectEqualStrings(sample_yaml, rendered);

    const round_tripped = try expect_result.ok(try config.parse(allocator, rendered));
    try testing.expectEqual(@as(usize, 2), round_tripped.packages.len);
    try testing.expectEqualStrings(original.packages[0].repo, round_tripped.packages[0].repo);
    try testing.expectEqualStrings(original.packages[0].namespace, round_tripped.packages[0].namespace);
    try testing.expectEqualStrings(original.packages[1].repo, round_tripped.packages[1].repo);
    try testing.expectEqualStrings(original.packages[1].namespace, round_tripped.packages[1].namespace);
}

test "stringify renders an empty packages list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const rendered = try config.stringify(allocator, .{
        .packages = &.{},
    });
    try testing.expectEqualStrings("packages: []\n", rendered);
}

test "parse refuses a duplicate namespace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const why = try expect_result.failed(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/one
        \\    namespace: demo
        \\  - repo: acme/two
        \\    namespace: demo
        \\
    ));
    try testing.expect(std.mem.indexOf(u8, why.message(), "duplicate namespace") != null);
    try testing.expect(std.mem.indexOf(u8, why.message(), "demo") != null);
}

test "parse refuses the scratch namespace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const why = try expect_result.failed(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: loc
        \\
    ));
    try testing.expect(std.mem.indexOf(u8, why.message(), "reserved") != null);
    try testing.expect(std.mem.indexOf(u8, why.message(), "loc") != null);
}

test "parse accepts namespaces that only look like the scratch one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try expect_result.ok(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/one
        \\    namespace: local
        \\  - repo: acme/two
        \\    namespace: loc-notes
        \\  - repo: acme/three
        \\    namespace: scratch
        \\
    ));
    try testing.expectEqual(@as(usize, 3), file.packages.len);
    try testing.expectEqualStrings("local", file.packages[0].namespace);
    try testing.expectEqualStrings("loc-notes", file.packages[1].namespace);
    try testing.expectEqualStrings("scratch", file.packages[2].namespace);
}

test "parse refuses a missing packages field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const why = try expect_result.failed(try config.parse(allocator, "other: 1\n"));
    try testing.expect(std.mem.indexOf(u8, why.message(), "packages") != null);
}

test "parse refuses a package that is not an object" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const why = try expect_result.failed(try config.parse(allocator, "packages:\n  - owner/repo\n"));
    try testing.expect(std.mem.indexOf(u8, why.message(), "object") != null);
}

test "parse refuses a missing repo or namespace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const why = try expect_result.failed(try config.parse(allocator,
        \\packages:
        \\  - namespace: demo
        \\
    ));
    try testing.expect(std.mem.indexOf(u8, why.message(), "repo") != null);

    const why_2 = try expect_result.failed(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\
    ));
    try testing.expect(std.mem.indexOf(u8, why_2.message(), "namespace") != null);
}

test "writeFile then readFile round-trips a config, creating parent directories" {
    var test_io = TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try TemporaryDir.create(io);
    defer temporary.destroy();

    const path = try temporary.join(allocator, "nested/skl.yaml");
    const original = try expect_result.ok(try config.parse(allocator, sample_yaml));

    try expect_result.ok(try config.writeFile(io, allocator, path, original));

    const loaded = try expect_result.ok(try config.readFile(io, allocator, path));
    try testing.expectEqual(@as(usize, 2), loaded.packages.len);
    try testing.expectEqualStrings("owner/repo", loaded.packages[0].repo);
    try testing.expectEqualStrings("demo", loaded.packages[0].namespace);
    try testing.expectEqualStrings("pla", loaded.packages[1].namespace);
}

test "readFile reports a missing file" {
    var test_io = TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try TemporaryDir.create(io);
    defer temporary.destroy();

    const why = try expect_result.failed(try config.readFile(io, allocator, try temporary.join(allocator, "gone.yaml")));
    try testing.expect(std.mem.indexOf(u8, why.message(), "no such file") != null);
}

test "parse reads branch and omits local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try expect_result.ok(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: feature
        \\
    ));
    try testing.expectEqual(@as(usize, 1), file.packages.len);
    try testing.expectEqualStrings("feature", file.packages[0].branch.?);
    try testing.expect(file.packages[0].local == null);
}

test "parse reads local and omits branch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try expect_result.ok(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    local: /home/me/src/skills
        \\
    ));
    try testing.expectEqual(@as(usize, 1), file.packages.len);
    try testing.expect(file.packages[0].branch == null);
    try testing.expectEqualStrings("/home/me/src/skills", file.packages[0].local.?);
}

test "stringify then parse round-trips branch and local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const original = try expect_result.ok(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: feature
        \\  - repo: acme/cmds
        \\    namespace: work
        \\    local: /tmp/cmds
        \\
    ));
    const rendered = try config.stringify(allocator, original);
    const round_tripped = try expect_result.ok(try config.parse(allocator, rendered));
    try testing.expectEqual(@as(usize, 2), round_tripped.packages.len);
    try testing.expectEqualStrings("feature", round_tripped.packages[0].branch.?);
    try testing.expect(round_tripped.packages[0].local == null);
    try testing.expect(round_tripped.packages[1].branch == null);
    try testing.expectEqualStrings("/tmp/cmds", round_tripped.packages[1].local.?);
}

test "parse refuses both branch and local on one row" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const why = try expect_result.failed(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: feature
        \\    local: /tmp/skills
        \\
    ));
    try testing.expect(std.mem.indexOf(u8, why.message(), "branch") != null);
    try testing.expect(std.mem.indexOf(u8, why.message(), "local") != null);
}

test "parse refuses empty branch or local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const why = try expect_result.failed(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: ""
        \\
    ));
    try testing.expect(std.mem.indexOf(u8, why.message(), "branch") != null);

    const why_2 = try expect_result.failed(try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    local: ""
        \\
    ));
    try testing.expect(std.mem.indexOf(u8, why_2.message(), "local") != null);
}
