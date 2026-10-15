//
// The test input factories for `Value`, the parsed YAML every `skl` command reads from `skl.yaml`,
// so Faultline calls the functions that read and write it with real rows and documents.
//
// The full document comes first, because Faultline's first call to a function uses the first
// factory for each parameter.
//

const std = @import("std");

//
// The file that declares `Value`.
//
const value = @import("value.zig");

//
// The `skl.yaml` that `skl add acme/skills --ns demo` then `skl add acme/tools --ns tools --branch
// dev` leave: a document with two package rows.
//
pub fn documentWithTwoPackages(allocator: std.mem.Allocator) !value.Value {
    var packages = value.newArray(allocator);
    try packages.append(try row(allocator, &.{ "repo", "acme/skills", "namespace", "demo" }));
    try packages.append(try row(allocator, &.{ "repo", "acme/tools", "namespace", "tools", "branch", "dev" }));
    var root: value.Object = .empty;
    try root.put(allocator, "packages", .{
        .array = packages,
    });
    return .{
        .object = root,
    };
}

//
// The row `skl add acme/skills --ns demo` writes into `skl.yaml`.
//
pub fn packageRow(allocator: std.mem.Allocator) !value.Value {
    return row(allocator, &.{ "repo", "acme/skills", "namespace", "demo" });
}

//
// The row `skl add acme/skills --ns demo --branch dev` writes into `skl.yaml`.
//
pub fn packageRowOnBranch(allocator: std.mem.Allocator) !value.Value {
    return row(allocator, &.{ "repo", "acme/skills", "namespace", "demo", "branch", "dev" });
}

//
// The row `skl add acme/skills --ns demo --local ../skills` writes into `skl.yaml`.
//
pub fn packageRowWithLocalTree(allocator: std.mem.Allocator) !value.Value {
    return row(allocator, &.{ "repo", "acme/skills", "namespace", "demo", "local", "../skills" });
}

//
// A `skl.yaml` row edited by hand to have both `branch` and `local`, which `skl install` refuses.
//
pub fn packageRowWithBranchAndLocalTree(allocator: std.mem.Allocator) !value.Value {
    return row(allocator, &.{ "repo", "acme/skills", "namespace", "demo", "branch", "dev", "local", "../skills" });
}

//
// A `skl.yaml` row edited by hand to use the namespace reserved for the scratch directory, which
// `skl install` refuses.
//
pub fn packageRowWithReservedNamespace(allocator: std.mem.Allocator) !value.Value {
    return row(allocator, &.{ "repo", "acme/skills", "namespace", "loc" });
}

//
// A `skl.yaml` row edited by hand to leave out `repo`, which `skl install` refuses.
//
pub fn packageRowWithoutRepo(allocator: std.mem.Allocator) !value.Value {
    return row(allocator, &.{ "namespace", "demo" });
}

//
// A `skl.yaml` row edited by hand to give `repo` an empty string, which `skl install` refuses.
//
pub fn packageRowWithEmptyRepo(allocator: std.mem.Allocator) !value.Value {
    return row(allocator, &.{ "repo", "", "namespace", "demo" });
}

//
// A `skl.yaml` row edited by hand to give `branch` an empty string, which `skl install` refuses.
//
pub fn packageRowWithEmptyBranch(allocator: std.mem.Allocator) !value.Value {
    return row(allocator, &.{ "repo", "acme/skills", "namespace", "demo", "branch", "" });
}

//
// A `skl.yaml` row edited by hand to give `branch` as `~`, YAML's null, which `skl install` treats
// as no branch.
//
pub fn packageRowWithNullBranch(allocator: std.mem.Allocator) !value.Value {
    var object: value.Object = .empty;
    try object.put(allocator, "repo", value.str("acme/skills"));
    try object.put(allocator, "namespace", value.str("demo"));
    try object.put(allocator, "branch", .null);
    return .{
        .object = object,
    };
}

//
// A `skl.yaml` row edited by hand to give `branch` as a number, which `skl install` refuses.
//
pub fn packageRowWithNumberBranch(allocator: std.mem.Allocator) !value.Value {
    var object: value.Object = .empty;
    try object.put(allocator, "repo", value.str("acme/skills"));
    try object.put(allocator, "namespace", value.str("demo"));
    try object.put(allocator, "branch", value.int(2));
    return .{
        .object = object,
    };
}

//
// A `skl.yaml` package written by hand as a bare string, which `skl install` refuses.
//
pub fn packageAsString() value.Value {
    return value.str("acme/skills");
}

//
// A `skl.yaml` holding scalars of every kind a hand edit can put there: true, false, a whole
// number, a float, null and a string that needs quoting.
//
pub fn documentWithEveryScalar(allocator: std.mem.Allocator) !value.Value {
    var object: value.Object = .empty;
    try object.put(allocator, "yes", value.boolean(true));
    try object.put(allocator, "no", value.boolean(false));
    try object.put(allocator, "count", value.int(3));
    try object.put(allocator, "ratio", .{
        .float = 1.5,
    });
    try object.put(allocator, "nothing", .null);
    try object.put(allocator, "quoted", value.str("a: b # c"));
    try object.put(allocator, "empty", value.str(""));
    try object.put(allocator, "comment", value.str("a #b"));
    try object.put(allocator, "escapes", value.str("say \"hi\" \\ now\nthen\rtab\t"));
    try object.put(allocator, "big", .{
        .number_string = "123456789012345678901234567890",
    });
    var nested = value.newArray(allocator);
    try nested.append(value.str("one"));
    try nested.append(.{
        .array = value.newArray(allocator),
    });
    try object.put(allocator, "list", .{
        .array = nested,
    });
    try object.put(allocator, "map", .{
        .object = .empty,
    });
    return .{
        .object = object,
    };
}

//
// An object with each pair of strings in `fields` as a key and its value.
//
fn row(allocator: std.mem.Allocator, fields: []const []const u8) !value.Value {
    var object: value.Object = .empty;
    var index: usize = 0;
    while (index < fields.len) : (index += 2) {
        try object.put(allocator, fields[index], value.str(fields[index + 1]));
    }
    return .{
        .object = object,
    };
}
