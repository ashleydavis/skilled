//
// Tests for failure.zig.
//

const std = @import("std");
const failure = @import("failure.zig");
const testing = std.testing;

test "because formats the message into the failure" {
    const made = failure.because("bad thing: {s}", .{"here"});

    try testing.expectEqualStrings("bad thing: here", made.message());
}

test "because cuts a message too long to hold and ends it in three dots" {
    const long = "x" ** (failure.message_capacity + 10);

    const made = failure.because("{s}", .{long});

    try testing.expectEqual(@as(usize, failure.message_capacity), made.message().len);
    try testing.expect(std.mem.endsWith(u8, made.message(), "..."));
}

test "a Result holds either its value or the failure" {
    const ok: failure.Result(u8) = .{
        .ok = 7,
    };
    const refused: failure.Result(u8) = .{
        .failed = failure.because("no", .{}),
    };

    try testing.expectEqual(@as(u8, 7), ok.ok);
    try testing.expectEqualStrings("no", refused.failed.message());
}
