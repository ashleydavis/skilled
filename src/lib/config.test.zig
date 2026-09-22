//
// Tests for config.zig.
//

const std = @import("std");
const config = @import("config.zig");
const failure = @import("failure.zig");
const files = @import("files.zig");
const testing = std.testing;

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
    var fail = failure.Failure.init(allocator);

    const file = try config.parse(allocator, sample_yaml, &fail);
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
    var fail = failure.Failure.init(allocator);

    const file = try config.parse(allocator, "packages: []\n", &fail);
    try testing.expectEqual(@as(usize, 0), file.packages.len);
}

test "stringify then parse round-trips a list of packages" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const original = try config.parse(allocator, sample_yaml, &fail);
    const rendered = try config.stringify(allocator, original);
    try testing.expectEqualStrings(sample_yaml, rendered);

    var fail_again = failure.Failure.init(allocator);
    const round_tripped = try config.parse(allocator, rendered, &fail_again);
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

    const rendered = try config.stringify(allocator, .{ .packages = &.{} });
    try testing.expectEqualStrings("packages: []\n", rendered);
}

test "parse refuses a duplicate namespace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, config.parse(allocator,
        \\packages:
        \\  - repo: acme/one
        \\    namespace: demo
        \\  - repo: acme/two
        \\    namespace: demo
        \\
    , &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "duplicate namespace") != null);
    try testing.expect(std.mem.indexOf(u8, fail.text(), "demo") != null);
}

test "parse refuses the scratch namespace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: loc
        \\
    , &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "reserved") != null);
    try testing.expect(std.mem.indexOf(u8, fail.text(), "loc") != null);
}

test "parse accepts namespaces that only look like the scratch one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const file = try config.parse(allocator,
        \\packages:
        \\  - repo: acme/one
        \\    namespace: local
        \\  - repo: acme/two
        \\    namespace: loc-notes
        \\  - repo: acme/three
        \\    namespace: scratch
        \\
    , &fail);
    try testing.expectEqual(@as(usize, 3), file.packages.len);
    try testing.expectEqualStrings("local", file.packages[0].namespace);
    try testing.expectEqualStrings("loc-notes", file.packages[1].namespace);
    try testing.expectEqualStrings("scratch", file.packages[2].namespace);
}

test "parse refuses a missing packages field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, config.parse(allocator, "other: 1\n", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "packages") != null);
}

test "parse refuses a package that is not an object" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, config.parse(allocator, "packages:\n  - owner/repo\n", &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "object") != null);
}

test "parse refuses a missing repo or namespace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fail_repo = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, config.parse(allocator,
        \\packages:
        \\  - namespace: demo
        \\
    , &fail_repo));
    try testing.expect(std.mem.indexOf(u8, fail_repo.text(), "repo") != null);

    var fail_ns = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\
    , &fail_ns));
    try testing.expect(std.mem.indexOf(u8, fail_ns.text(), "namespace") != null);
}

test "writeFile then readFile round-trips a config, creating parent directories" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    const path = try temporary.join(allocator, "nested/skl.yaml");
    var parse_fail = failure.Failure.init(allocator);
    const original = try config.parse(allocator, sample_yaml, &parse_fail);

    var write_fail = failure.Failure.init(allocator);
    try config.writeFile(io, allocator, path, original, &write_fail);

    var read_fail = failure.Failure.init(allocator);
    const loaded = try config.readFile(io, allocator, path, &read_fail);
    try testing.expectEqual(@as(usize, 2), loaded.packages.len);
    try testing.expectEqualStrings("owner/repo", loaded.packages[0].repo);
    try testing.expectEqualStrings("demo", loaded.packages[0].namespace);
    try testing.expectEqualStrings("pla", loaded.packages[1].namespace);
}

test "readFile reports a missing file" {
    var test_io = files.TestIo.init();
    defer test_io.deinit();
    const io = test_io.io();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temporary = try files.TemporaryDir.create(io);
    defer temporary.destroy();

    var fail = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, config.readFile(io, allocator, try temporary.join(allocator, "gone.yaml"), &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "no such file") != null);
}

test "parse reads branch and omits local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const file = try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: feature
        \\
    , &fail);
    try testing.expectEqual(@as(usize, 1), file.packages.len);
    try testing.expectEqualStrings("feature", file.packages[0].branch.?);
    try testing.expect(file.packages[0].local == null);
}

test "parse reads local and omits branch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const file = try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    local: /home/me/src/skills
        \\
    , &fail);
    try testing.expectEqual(@as(usize, 1), file.packages.len);
    try testing.expect(file.packages[0].branch == null);
    try testing.expectEqualStrings("/home/me/src/skills", file.packages[0].local.?);
}

test "stringify then parse round-trips branch and local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fail = failure.Failure.init(allocator);

    const original = try config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: feature
        \\  - repo: acme/cmds
        \\    namespace: work
        \\    local: /tmp/cmds
        \\
    , &fail);
    const rendered = try config.stringify(allocator, original);
    var fail_again = failure.Failure.init(allocator);
    const round_tripped = try config.parse(allocator, rendered, &fail_again);
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
    var fail = failure.Failure.init(allocator);

    try testing.expectError(error.Failed, config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: feature
        \\    local: /tmp/skills
        \\
    , &fail));
    try testing.expect(std.mem.indexOf(u8, fail.text(), "branch") != null);
    try testing.expect(std.mem.indexOf(u8, fail.text(), "local") != null);
}

test "parse refuses empty branch or local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fail_branch = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: ""
        \\
    , &fail_branch));
    try testing.expect(std.mem.indexOf(u8, fail_branch.text(), "branch") != null);

    var fail_local = failure.Failure.init(allocator);
    try testing.expectError(error.Failed, config.parse(allocator,
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    local: ""
        \\
    , &fail_local));
    try testing.expect(std.mem.indexOf(u8, fail_local.text(), "local") != null);
}
