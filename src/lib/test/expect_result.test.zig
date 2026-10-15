//
// Checks on a returned `failure.Result`, so a test reads the value or the refusal it expects.
//
// The library's tests and the CLI's tests both need these. A file imported by path from both would
// belong to two modules, which Zig refuses, so `build.zig` makes this file a module and both import
// it by name. It takes any Result, so it imports nothing from the library.
//

const std = @import("std");

//
// The value a Result holds. A refusal fails the test and prints its message, so the test output
// says why it was refused.
//
pub fn ok(result: anytype) error{TestUnexpectedResult}!@FieldType(@TypeOf(result), "ok") {
    switch (result) {
        .ok => |value| {
            return value;
        },
        .failed => |why| {
            std.debug.print("Expected a value, but it was refused: {s}\n", .{why.message()});
            return error.TestUnexpectedResult;
        },
    }
}

//
// The failure a Result holds. A value fails the test, because the call should have been refused.
//
pub fn failed(result: anytype) error{TestUnexpectedResult}!@FieldType(@TypeOf(result), "failed") {
    switch (result) {
        .ok => {
            std.debug.print("Expected a refusal, but a value was returned.\n", .{});
            return error.TestUnexpectedResult;
        },
        .failed => |why| {
            return why;
        },
    }
}
