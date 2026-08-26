//
// Tests for version.zig.
//

const std = @import("std");
const version = @import("version.zig");
const testing = std.testing;

test "the version is a non-empty string" {
    try testing.expect(version.version.len > 0);
}

test "the version equals 0.0.1" {
    try testing.expectEqualStrings("0.0.1", version.version);
}
