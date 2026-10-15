//
// Reading and writing skl.yaml: a list of `{repo, namespace}` packages with optional branch/local.
//
// The scratch namespace is refused here rather than in the commands, so a hand-edited file and a
// fetched `--from` file are both caught before anything is linked.
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
// The namespace the scratch directory owns, which no package may take.
//
const scratch = @import("scratch.zig");

//
// The vendored parser and renderer for the skl.yaml subset.
//
const yaml = @import("yaml.zig");

//
// Alias so the YAML tree is named Value at the point of use.
//
const Value = value.Value;

//
// The branch a row without `branch:` is cloned from and updated on.
//
// Named rather than left to the remote's default so a row always says which branch it follows, and
// a row without `branch:` shares its store clone with a `branch: main` row.
//
pub const default_branch = "main";

//
// One package entry in skl.yaml: where to clone from, and the namespace it links under.
//
// A list of these, not a map keyed by name, is what lets the same repo appear twice under
// different namespaces. Uniqueness is on namespace, checked in parse, which also refuses the
// namespace the scratch directory owns.
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

    //
    // Named remote branch to clone. Null means `default_branch`.
    //
    // Mutually exclusive with `local` in a parsed document so install has one source.
    //
    branch: ?[]const u8 = null,

    //
    // Absolute path of a local working tree that agent links point at instead of the store.
    //
    // Null means the store clone. Written absolute so a later install from another cwd still finds it.
    //
    local: ?[]const u8 = null,
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
// Turns YAML text into a File, or the failure that says why the document is not a valid skl.yaml.
//
// Namespace uniqueness is per file: the second entry that repeats a namespace is the one that
// fails. Repo strings are kept as written; clone-spec parsing is a later step.
//
pub fn parse(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!failure.Result(File) {
    const parsed = switch (try yaml.parseOrFail(allocator, text, "skl.yaml")) {
        .ok => |read| read,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (!value.isPlainObject(parsed)) {
        return .{
            .failed = failure.because("The file skl.yaml must be a YAML object, got {s}.", .{
                try value.describe(allocator, parsed),
            }),
        };
    }

    const raw_packages = value.get(parsed, "packages");
    const packages_array = switch (raw_packages orelse Value.null) {
        .array => |array| array,
        else => return .{
            .failed = failure.because("The skl.yaml field \"packages\" must be an array, got {s}.", .{
                try value.describe(allocator, raw_packages),
            }),
        },
    };

    var seen: std.StringArrayHashMapUnmanaged(void) = .empty;
    var packages: std.ArrayList(Package) = .empty;
    for (packages_array.items) |raw_package| {
        const pkg = switch (try parsePackage(allocator, raw_package, &seen)) {
            .ok => |read| read,
            .failed => |why| return .{
                .failed = why,
            },
        };
        try packages.append(allocator, pkg);
    }

    return .{
        .ok = .{
            .packages = try packages.toOwnedSlice(allocator),
        },
    };
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
        if (pkg.branch) |branch| {
            try object.put(allocator, "branch", value.str(branch));
        }
        if (pkg.local) |local| {
            try object.put(allocator, "local", value.str(local));
        }
        try packages.append(.{
            .object = object,
        });
    }

    var root: value.Object = .empty;
    try root.put(allocator, "packages", .{
        .array = packages,
    });
    const body = try yaml.stringify(allocator, .{
        .object = root,
    });
    defer allocator.free(body);
    return std.mem.concat(allocator, u8, &.{ body, "\n" });
}

//
// Reads path, bounded by files.MAX_FILE_BYTES, and parses it as skl.yaml.
//
pub fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error!failure.Result(File) {
    const text = files.readFile(io, allocator, path) catch |err| {
        return .{
            .failed = failure.because("Cannot read {s}: {s}.", .{ path, files.describeError(err) }),
        };
    };
    return parse(allocator, text);
}

//
// Writes file as YAML at path, creating any missing parent directories.
//
pub fn writeFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8, file: File) std.mem.Allocator.Error!failure.Result(void) {
    const text = try stringify(allocator, file);
    defer allocator.free(text);
    files.makeParentDir(io, path) catch |err| {
        return .{
            .failed = failure.because("Cannot write {s}: {s}.", .{ path, files.describeError(err) }),
        };
    };
    files.writeFile(io, path, text) catch |err| {
        return .{
            .failed = failure.because("Cannot write {s}: {s}.", .{ path, files.describeError(err) }),
        };
    };
    return .ok;
}

//
// One list item: an object with non-empty `repo` and `namespace` strings.
//
fn parsePackage(
    allocator: std.mem.Allocator,
    raw_package: Value,
    seen: *std.StringArrayHashMapUnmanaged(void),
) std.mem.Allocator.Error!failure.Result(Package) {
    if (!value.isPlainObject(raw_package)) {
        return .{
            .failed = failure.because("A skl.yaml package must be an object, got {s}.", .{
                try value.describe(allocator, raw_package),
            }),
        };
    }

    const repo = switch (try readRequiredString(allocator, raw_package, "repo")) {
        .ok => |read| read,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const namespace = switch (try readRequiredString(allocator, raw_package, "namespace")) {
        .ok => |read| read,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const branch = switch (try readOptionalString(allocator, raw_package, "branch")) {
        .ok => |read| read,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const local = switch (try readOptionalString(allocator, raw_package, "local")) {
        .ok => |read| read,
        .failed => |why| return .{
            .failed = why,
        },
    };
    if (branch != null and local != null) {
        return .{
            .failed = failure.because("A skl.yaml package cannot have both \"branch\" and \"local\".", .{}),
        };
    }
    if (scratch.isReserved(namespace)) {
        return .{
            .failed = failure.because(
                "The skl.yaml namespace \"{s}\" is reserved for the scratch directory.",
                .{namespace},
            ),
        };
    }
    if (seen.contains(namespace)) {
        return .{
            .failed = failure.because("The skl.yaml file has a duplicate namespace \"{s}\".", .{namespace}),
        };
    }
    try seen.put(allocator, namespace, {});
    return .{
        .ok = .{
            .repo = repo,
            .namespace = namespace,
            .branch = branch,
            .local = local,
        },
    };
}

//
// A required string field on a package object. Absent, null, or a non-string is refused.
//
fn readRequiredString(allocator: std.mem.Allocator, object: Value, field: []const u8) std.mem.Allocator.Error!failure.Result([]const u8) {
    const raw = value.get(object, field);
    const text: []const u8 = switch (raw orelse Value.null) {
        .string => |string| string,
        else => "",
    };
    if (text.len == 0) {
        return .{
            .failed = failure.because("The skl.yaml package field \"{s}\" must be a non-empty string, got {s}.", .{
                field,
                try value.describe(allocator, raw),
            }),
        };
    }
    return .{
        .ok = text,
    };
}

//
// Optional string field: absent or YAML null is unset; empty or a non-string is refused.
//
fn readOptionalString(allocator: std.mem.Allocator, object: Value, field: []const u8) std.mem.Allocator.Error!failure.Result(?[]const u8) {
    const raw = value.get(object, field) orelse return .{
        .ok = null,
    };
    switch (raw) {
        .null => return .{
            .ok = null,
        },
        .string => |text| {
            if (text.len > 0) {
                return .{
                    .ok = text,
                };
            }
        },
        else => {},
    }
    return .{
        .failed = failure.because("The skl.yaml package field \"{s}\" must be a non-empty string, got {s}.", .{
            field,
            try value.describe(allocator, raw),
        }),
    };
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("config.test.zig");
}
