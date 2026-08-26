//
// The value used wherever the structure is not known at compile time.
//
// Parsed YAML lands here: `skl.yaml`, skill frontmatter, and anything stringify writes back. Using
// `std.json.Value` means the YAML parser and renderer share one type, so a config and a rendered
// document are the same structure and every check downstream is written once.
//
// Objects preserve insertion order (`std.json.ObjectMap` is an array hash map). That is not a
// detail: it is what makes the rendered output depend on the document rather than on a hash seed,
// so two runs over the same input print the same bytes.
//

const std = @import("std");

//
// A value of any type: null, bool, number, string, array or object.
//
pub const Value = std.json.Value;

//
// An object: an insertion-ordered map of string keys to values.
//
pub const Object = std.json.ObjectMap;

//
// An array of values.
//
pub const Array = std.json.Array;

//
// Makes an empty array.
//
pub fn newArray(allocator: std.mem.Allocator) Array {
    return Array.init(allocator);
}

//
// Wraps a string as a value, so building an object reads as a list of fields rather than as a list
// of union initialisers.
//
pub fn str(text: []const u8) Value {
    return .{ .string = text };
}

//
// Wraps a boolean as a value.
//
pub fn boolean(value: bool) Value {
    return .{ .bool = value };
}

//
// Wraps a whole number as a value.
//
pub fn int(value: i64) Value {
    return .{ .integer = value };
}

//
// Reads a field off a value.
//
// Anything that is not an object has no fields, so it answers null rather than failing. That is
// what lets the config checks read a field and then complain about its value, instead of having to
// prove the whole document is an object at every step.
//
pub fn get(value: Value, key: []const u8) ?Value {
    return switch (value) {
        .object => |object| object.get(key),
        else => null,
    };
}

//
// True for a plain object, which is what both halves of the baseline have to be.
//
// An array is a different tag, so it is excluded without having to be named.
//
pub fn isPlainObject(value: Value) bool {
    return value == .object;
}

//
// Renders a value for dropping into an error message: compact, with no whitespace at all.
//
// A missing field renders as "undefined" rather than "null", so a config that leaves a field out
// entirely reads as `got undefined`, which is a different complaint from one that set it to null.
//
pub fn describe(allocator: std.mem.Allocator, value: ?Value) std.mem.Allocator.Error![]const u8 {
    const present = value orelse return allocator.dupe(u8, "undefined");

    var rendered = std.Io.Writer.Allocating.init(allocator);
    errdefer rendered.deinit();

    std.json.Stringify.value(present, .{}, &rendered.writer) catch return error.OutOfMemory;
    return rendered.toOwnedSlice();
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("value.test.zig");
}
