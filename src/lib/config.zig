//
// Reading and writing skl.yaml: a list of `{repo, namespace}` packages.
//

const std = @import("std");

//
// How a rejected document is described to the caller.
//
const failure = @import("failure.zig");

//
// Bounded filesystem reads and writes used by readFile and writeFile.
//
const files = @import("files.zig");

//
// The dynamic YAML value parse produces, and stringify builds back.
//
const value = @import("value.zig");

//
// The vendored parser and renderer for the skl.yaml subset.
//
const yaml = @import("yaml.zig");

//
// Alias so parse signatures read as Failure rather than failure.Failure.
//
const Failure = failure.Failure;

//
// Alias so the YAML tree is named Value at the point of use.
//
const Value = value.Value;

//
// One package entry in skl.yaml: where to clone from, and the namespace it links under.
//
// A list of these, not a map keyed by name, is what lets the same repo appear twice under
// different namespaces. Uniqueness is on namespace, checked in parse.
//
pub const Package = struct {
    //
    // The clone spec as written: `owner/repo` or an SSH URL.
    //
    repo: []const u8,

    //
    // The directory name under each agent skills/ and commands/ tree.
    //
    namespace: []const u8,
};

//
// The whole of skl.yaml. `packages: []` is a valid empty file, which is what `skl init` writes.
//
pub const File = struct {
    //
    // Packages in file order. Empty is allowed; two entries sharing a namespace are not.
    //
    packages: []Package,
};

//
// Turns YAML text into a File, or records why the document is not a valid skl.yaml.
//
// Namespace uniqueness is per file: the second entry that repeats a namespace is the one that
// fails. Repo strings are kept as written; clone-spec parsing is a later step.
//
pub fn parse(allocator: std.mem.Allocator, text: []const u8, fail: *Failure) failure.Error!File {
    const parsed = try yaml.parseOrFail(allocator, text, "skl.yaml", fail);
    if (!value.isPlainObject(parsed)) {
        return fail.set("skl.yaml must be a YAML object, got {s}", .{
            try value.describe(allocator, parsed),
        });
    }

    const raw_packages = value.get(parsed, "packages");
    const packages_array = switch (raw_packages orelse Value.null) {
        .array => |array| array,
        else => return fail.set("skl.yaml field \"packages\" must be an array, got {s}", .{
            try value.describe(allocator, raw_packages),
        }),
    };

    var seen: std.StringArrayHashMapUnmanaged(void) = .empty;
    var packages: std.ArrayList(Package) = .empty;
    for (packages_array.items) |raw_package| {
        try packages.append(allocator, try parsePackage(allocator, raw_package, &seen, fail));
    }

    return .{ .packages = try packages.toOwnedSlice(allocator) };
}

//
// Renders a File as YAML. Empty packages become `packages: []`.
//
// A trailing newline is included so the result is a complete text file.
//
pub fn stringify(allocator: std.mem.Allocator, file: File) std.mem.Allocator.Error![]const u8 {
    var packages = value.newArray(allocator);
    for (file.packages) |pkg| {
        var object: value.Object = .empty;
        try object.put(allocator, "repo", value.str(pkg.repo));
        try object.put(allocator, "namespace", value.str(pkg.namespace));
        try packages.append(.{ .object = object });
    }

    var root: value.Object = .empty;
    try root.put(allocator, "packages", .{ .array = packages });
    const body = try yaml.stringify(allocator, .{ .object = root });
    defer allocator.free(body);
    return std.mem.concat(allocator, u8, &.{ body, "\n" });
}

//
// Reads path, bounded by files.MAX_FILE_BYTES, and parses it as skl.yaml.
//
pub fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8, fail: *Failure) failure.Error!File {
    const text = files.readFile(io, allocator, path) catch |err| {
        return fail.set("cannot read {s}: {s}", .{ path, files.describeError(err) });
    };
    return parse(allocator, text, fail);
}

//
// Writes file as YAML at path, creating any missing parent directories.
//
pub fn writeFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8, file: File, fail: *Failure) failure.Error!void {
    const text = try stringify(allocator, file);
    defer allocator.free(text);
    files.makeParentDir(io, path) catch |err| {
        return fail.set("cannot write {s}: {s}", .{ path, files.describeError(err) });
    };
    files.writeFile(io, path, text) catch |err| {
        return fail.set("cannot write {s}: {s}", .{ path, files.describeError(err) });
    };
}

//
// One list item: an object with non-empty `repo` and `namespace` strings.
//
fn parsePackage(
    allocator: std.mem.Allocator,
    raw_package: Value,
    seen: *std.StringArrayHashMapUnmanaged(void),
    fail: *Failure,
) failure.Error!Package {
    if (!value.isPlainObject(raw_package)) {
        return fail.set("skl.yaml package must be an object, got {s}", .{
            try value.describe(allocator, raw_package),
        });
    }

    const repo = try readRequiredString(allocator, raw_package, "repo", fail);
    const namespace = try readRequiredString(allocator, raw_package, "namespace", fail);
    if (seen.contains(namespace)) {
        return fail.set("skl.yaml has a duplicate namespace \"{s}\"", .{namespace});
    }
    try seen.put(allocator, namespace, {});
    return .{ .repo = repo, .namespace = namespace };
}

//
// A required string field on a package object. Absent, null, or a non-string is an error.
//
fn readRequiredString(allocator: std.mem.Allocator, object: Value, field: []const u8, fail: *Failure) failure.Error![]const u8 {
    const raw = value.get(object, field);
    switch (raw orelse Value.null) {
        .string => |text| {
            if (text.len > 0) {
                return text;
            }
        },
        else => {},
    }
    return fail.set("skl.yaml package field \"{s}\" must be a non-empty string, got {s}", .{
        field, try value.describe(allocator, raw),
    });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("config.test.zig");
}
