//
// The test input factories for the functions in `from.zig`, so Faultline can call them with real
// failures, environments and git.
//

const std = @import("std");

//
// The spec in `skl add --from acme/config:skl.yaml`.
//
pub fn shorthandFromSpec() []const u8 {
    return "acme/config:skl.yaml";
}

//
// The spec in `skl add --from acme/config:teams/skl.yaml`.
//
pub fn shorthandNestedFromSpec() []const u8 {
    return "acme/config:teams/skl.yaml";
}

//
// The spec in `skl add --from acme/config`, which is refused.
//
pub fn shorthandWithoutPathFromSpec() []const u8 {
    return "acme/config";
}

//
// The spec in `skl add --from acme/config:../skl.yaml`, which is refused.
//
pub fn shorthandEscapingPathFromSpec() []const u8 {
    return "acme/config:../skl.yaml";
}

//
// The spec in `skl add --from https://github.com/acme/config/blob/main/skl.yaml`.
//
pub fn blobUrlFromSpec() []const u8 {
    return "https://github.com/acme/config/blob/main/skl.yaml";
}

//
// The spec in `skl add --from https://github.com/acme/config/skl.yaml?raw=1#top`.
//
pub fn plainUrlFromSpec() []const u8 {
    return "https://github.com/acme/config/skl.yaml?raw=1#top";
}

//
// The spec in `skl add --from https://github.com/acme/config/blob/main`, which is refused.
//
pub fn blobUrlWithoutPathFromSpec() []const u8 {
    return "https://github.com/acme/config/blob/main";
}

//
// The spec in `skl add --from https://gitlab.com/acme/config/skl.yaml`, which is refused.
//
pub fn otherHostUrlFromSpec() []const u8 {
    return "https://gitlab.com/acme/config/skl.yaml";
}

//
// The spec in `skl add --from https://github.com/acme//skl.yaml`, which is refused.
//
pub fn emptySegmentUrlFromSpec() []const u8 {
    return "https://github.com/acme//skl.yaml";
}

//
// The spec in `skl add --from http://github.com/acme/config/skl.yaml`, which is refused.
//
pub fn httpUrlFromSpec() []const u8 {
    return "http://github.com/acme/config/skl.yaml";
}

//
// The spec in `skl add --from git@github.com:acme/config.git:skl.yaml`.
//
pub fn sshFromSpec() []const u8 {
    return "git@github.com:acme/config.git:skl.yaml";
}

//
// The spec in `skl add --from git@github.com:acme/config.git`, which is refused.
//
pub fn sshWithoutPathFromSpec() []const u8 {
    return "git@github.com:acme/config.git";
}

//
// The spec in `skl add --from acme/config:`, which is refused.
//
pub fn shorthandEmptyPathFromSpec() []const u8 {
    return "acme/config:";
}

//
// The spec in `skl add --from :skl.yaml`, which is refused.
//
pub fn shorthandEmptyRepoFromSpec() []const u8 {
    return ":skl.yaml";
}

//
// The spec in `skl add --from acme/config:teams//skl.yaml`, which is refused.
//
pub fn shorthandDoubleSlashFromSpec() []const u8 {
    return "acme/config:teams//skl.yaml";
}

//
// The spec in `skl add --from git@github.com:acme/config.git:`, which is refused.
//
pub fn sshEmptyPathFromSpec() []const u8 {
    return "git@github.com:acme/config.git:";
}

//
// The environment of `TMPDIR=/home/skilled/tmp skl add --from acme/config:skl.yaml`, which clones
// into that directory.
//
pub fn environmentWithTmpdir(allocator: std.mem.Allocator) !*const std.process.Environ.Map {
    return environmentWith(allocator, "TMPDIR");
}

//
// The environment of `TMP=/home/skilled/tmp skl add --from acme/config:skl.yaml`, as Windows sets
// it.
//
pub fn environmentWithTmp(allocator: std.mem.Allocator) !*const std.process.Environ.Map {
    return environmentWith(allocator, "TMP");
}

//
// The environment of `TEMP=/home/skilled/tmp skl add --from acme/config:skl.yaml`, as Windows sets
// it.
//
pub fn environmentWithTemp(allocator: std.mem.Allocator) !*const std.process.Environ.Map {
    return environmentWith(allocator, "TEMP");
}

//
// An environment with `HOME` and `name` set to `/home/skilled/tmp`.
//
fn environmentWith(allocator: std.mem.Allocator, name: []const u8) !*const std.process.Environ.Map {
    const made = try allocator.create(std.process.Environ.Map);
    made.* = .init(allocator);
    try made.put("HOME", "/home/skilled");
    try made.put(name, "/home/skilled/tmp");
    return made;
}

//
// The spec in `skl init --from https://github.com/acme/config`, which names no file and is refused.
//
pub fn repoUrlWithoutPathFromSpec() []const u8 {
    return "https://github.com/acme/config";
}

//
// The spec in `skl init --from "https://github.com/acme/config/te am/skl.yaml"`, whose path is
// refused.
//
pub fn badPathUrlFromSpec() []const u8 {
    return "https://github.com/acme/config/te am/skl.yaml";
}

//
// The spec in `skl init --from "https://github.com/ac me/config/skl.yaml"`, whose owner is refused.
//
pub fn badOwnerUrlFromSpec() []const u8 {
    return "https://github.com/ac me/config/skl.yaml";
}

//
// The spec in `skl init --from https://github.com/acme/config/blob/../skl.yaml`, whose ref is
// refused.
//
pub fn badRefUrlFromSpec() []const u8 {
    return "https://github.com/acme/config/blob/../skl.yaml";
}

//
// The spec in `skl init --from "git@github.com:ac me/config.git:skl.yaml"`, whose owner is refused.
//
pub fn sshBadOwnerFromSpec() []const u8 {
    return "git@github.com:ac me/config.git:skl.yaml";
}

//
// The spec in `skl init --from git@github.com:acme/config.git:teams//skl.yaml`, whose path has an
// empty part and is refused.
//
pub fn sshEmptyPathPartFromSpec() []const u8 {
    return "git@github.com:acme/config.git:teams//skl.yaml";
}
