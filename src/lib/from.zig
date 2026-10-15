//
// `--from <spec>`: locate a YAML file in a git repo, fetch it, and merge package lists.
//
// The spec is a locator, not a skill package. Clone goes to a throwaway directory, one file is
// read with `git show`, and the clone is deleted. Nothing here scans, links, or writes the store.
//

const std = @import("std");

//
// YAML list of packages that a fetched file must parse as.
//
const config = @import("config.zig");

//
// How a refused spec or fetch is described to the caller.
//
const failure = @import("failure.zig");

//
// Parent-directory creation before clone, and path joins for the throwaway dest.
//
const files = @import("files.zig");

//
// Clone and `git show` used to read the file at a ref.
//
const git = @import("git.zig");

//
// Host/owner/repo validation and the SSH clone URL `--from` still uses.
//
const remote = @import("remote.zig");

//
// A YAML file inside a git repo, after the spec has been split and names validated.
//
// `remote.clone_url` is what `git clone` receives (always SSH). `ref` is `HEAD` when the spec did
// not name one. `path` is the file inside the repo, using `/` the way `git show` wants it.
//
pub const Spec = struct {
    //
    // Validated host, owner, repo, and SSH clone URL.
    //
    remote: remote.Remote,

    //
    // The git ref `git show` reads. Blob URLs supply this; everything else uses HEAD.
    //
    ref: []const u8,

    //
    // Path inside the repo, posix slashes, already validated per segment.
    //
    path: []const u8,
};

//
// Turns a `--from` spec into host/owner/repo/ref/path, or the failure that says why it is refused.
//
// First match wins: GitHub HTTPS UI URL, then SSH with a second colon for the path, then
// `owner/repo:path`. HTTPS is only a locator; the clone URL is still SSH. Names are validated
// before any clone.
//
pub fn parse(allocator: std.mem.Allocator, spec: []const u8) std.mem.Allocator.Error!failure.Result(Spec) {
    if (spec.len == 0) {
        return .{
            .failed = failure.because("--from spec is empty", .{}),
        };
    }
    if (startsWithIgnoreCase(spec, "http://")) {
        return .{
            .failed = failure.because("HTTP --from specs are not supported; use an https://github.com/... URL", .{}),
        };
    }
    if (startsWithIgnoreCase(spec, "https://")) {
        return parseHttps(allocator, spec);
    }
    if (std.mem.startsWith(u8, spec, "git@")) {
        return parseSsh(allocator, spec);
    }
    return parseShorthand(allocator, spec);
}

//
// Clones the spec's repo into a throwaway directory, reads `ref:path` with `git show`, deletes the
// clone, and parses the bytes as skl.yaml.
//
// The dest is under TMPDIR/TMP/TEMP (else `/tmp`), never the package store. The throwaway directory
// is removed even when clone, show, or YAML parse fails.
//
pub fn fetchConfig(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: git.GitRunner,
    spec_text: []const u8,
) std.mem.Allocator.Error!failure.Result(config.File) {
    const spec = switch (try parse(allocator, spec_text)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const text = switch (try fetchText(io, allocator, environ, runner, spec)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    return config.parse(allocator, text);
}

//
// Existing packages plus incoming ones that are not already present.
//
// Existing entries stay in order. Each incoming package whose namespace is free is appended. The
// same namespace and the same package (exact repo string, or the same host/owner/repo after
// parse) is skipped. The same namespace and a different repo is an error so the caller can leave
// YAML unchanged.
//
pub fn mergePackages(
    allocator: std.mem.Allocator,
    existing: []const config.Package,
    incoming: []const config.Package,
) std.mem.Allocator.Error!failure.Result([]config.Package) {
    var packages: std.ArrayList(config.Package) = .empty;
    try packages.appendSlice(allocator, existing);
    for (incoming) |pkg| {
        if (namespaceTaken(packages.items, pkg.namespace)) |taken| {
            if (samePackage(allocator, taken.repo, pkg.repo)) {
                continue;
            }
            return .{
                .failed = failure.because("namespace \"{s}\" is already used by {s}", .{ pkg.namespace, taken.repo }),
            };
        }
        try packages.append(allocator, pkg);
    }
    return .{
        .ok = try packages.toOwnedSlice(allocator),
    };
}

//
// `https://github.com/owner/repo/blob/<ref>/path` or `https://github.com/owner/repo/path`.
//
// Non-github.com hosts are refused in v1. Query strings and fragments are stripped so a copied
// blob URL still parses. The clone is `git@github.com:owner/repo.git`. A spec that does not start
// with `https://` is refused.
//
pub fn parseHttps(allocator: std.mem.Allocator, spec: []const u8) std.mem.Allocator.Error!failure.Result(Spec) {
    if (!startsWithIgnoreCase(spec, "https://")) {
        return .{
            .failed = failure.because("invalid --from URL '{s}'; expected https://github.com/owner/repo/path", .{spec}),
        };
    }
    const after_scheme = spec["https://".len..];
    const without_fragment = stripAfter(after_scheme, '#');
    const loc = stripAfter(without_fragment, '?');
    const slash = std.mem.indexOfScalar(u8, loc, '/') orelse {
        return .{
            .failed = failure.because("invalid --from URL '{s}'; expected https://github.com/owner/repo/path", .{spec}),
        };
    };
    const host = loc[0..slash];
    if (!std.ascii.eqlIgnoreCase(host, "github.com")) {
        return .{
            .failed = failure.because("HTTPS --from specs must use github.com; got '{s}'", .{host}),
        };
    }
    const rest = loc[slash + 1 ..];
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, rest, '/');
    while (it.next()) |part| {
        if (part.len == 0) {
            return .{
                .failed = failure.because("invalid --from URL '{s}'; expected https://github.com/owner/repo/path", .{spec}),
            };
        }
        try parts.append(allocator, part);
    }
    if (parts.items.len < 3) {
        return .{
            .failed = failure.because("invalid --from URL '{s}'; path is required", .{spec}),
        };
    }

    const owner = parts.items[0];
    const repo_part = parts.items[1];
    const is_blob = std.mem.eql(u8, parts.items[2], "blob");
    if (is_blob and parts.items.len < 5) {
        return .{
            .failed = failure.because("invalid --from URL '{s}'; path is required", .{spec}),
        };
    }
    const ref: []const u8 = if (is_blob) parts.items[3] else "HEAD";
    const path_parts: []const []const u8 = if (is_blob) parts.items[4..] else parts.items[2..];

    const path = switch (try joinGitPath(allocator, path_parts)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const shorthand = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ owner, repo_part });
    const parsed = switch (try remote.parse(allocator, shorthand)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    switch (remote.validateName(ref, "ref")) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return .{
        .ok = .{
            .remote = parsed,
            .ref = try allocator.dupe(u8, ref),
            .path = path,
        },
    };
}

//
// `git@host:owner/repo.git:path`. The first colon is host vs owner/repo; a second colon starts the
// file path. No second colon is an error because a path is required, and so is a spec that does
// not start with `git@`.
//
pub fn parseSsh(allocator: std.mem.Allocator, spec: []const u8) std.mem.Allocator.Error!failure.Result(Spec) {
    if (!std.mem.startsWith(u8, spec, "git@")) {
        return .{
            .failed = failure.because("Invalid --from spec '{s}'; expected git@host:owner/repo:path.", .{spec}),
        };
    }
    const rest = spec["git@".len..];
    const first = std.mem.indexOfScalar(u8, rest, ':') orelse {
        return .{
            .failed = failure.because("Invalid --from spec '{s}'; expected git@host:owner/repo:path.", .{spec}),
        };
    };
    const after_host = rest[first + 1 ..];
    const second = std.mem.indexOfScalar(u8, after_host, ':') orelse {
        return .{
            .failed = failure.because("Invalid --from spec '{s}'; a path is required after the repo.", .{spec}),
        };
    };
    const remote_spec = spec[0 .. "git@".len + first + 1 + second];
    const path = after_host[second + 1 ..];
    if (path.len == 0) {
        return .{
            .failed = failure.because("Invalid --from spec '{s}'; a path is required after the repo.", .{spec}),
        };
    }
    const parsed = switch (try remote.parse(allocator, remote_spec)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const path_owned = switch (try copyGitPath(allocator, path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    return .{
        .ok = .{
            .remote = parsed,
            .ref = try allocator.dupe(u8, "HEAD"),
            .path = path_owned,
        },
    };
}

//
// `owner/repo:path`. Split on the first colon. No colon, or an empty side, is an error.
//
fn parseShorthand(allocator: std.mem.Allocator, spec: []const u8) std.mem.Allocator.Error!failure.Result(Spec) {
    const colon = std.mem.indexOfScalar(u8, spec, ':') orelse {
        return .{
            .failed = failure.because("Invalid --from spec '{s}'; expected owner/repo:path.", .{spec}),
        };
    };
    const left = spec[0..colon];
    const path = spec[colon + 1 ..];
    if (left.len == 0 or path.len == 0) {
        return .{
            .failed = failure.because("Invalid --from spec '{s}'; expected owner/repo:path.", .{spec}),
        };
    }
    const parsed = switch (try remote.parse(allocator, left)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    const path_owned = switch (try copyGitPath(allocator, path)) {
        .ok => |got| got,
        .failed => |why| return .{
            .failed = why,
        },
    };
    return .{
        .ok = .{
            .remote = parsed,
            .ref = try allocator.dupe(u8, "HEAD"),
            .path = path_owned,
        },
    };
}

//
// Clone into a unique dest, `git show <ref>:<path>`, then delete the throwaway tree.
//
fn fetchText(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    runner: git.GitRunner,
    spec: Spec,
) std.mem.Allocator.Error!failure.Result([]const u8) {
    const dest = try uniqueDest(io, allocator, tempParent(environ), spec.remote.repo);
    const temp_root = files.dirName(dest);
    defer std.Io.Dir.cwd().deleteTree(io, temp_root) catch {};

    switch (try git.clone(io, allocator, environ, runner, spec.remote.clone_url, dest, null)) {
        .ok => {},
        .failed => |why| return .{
            .failed = why,
        },
    }
    return git.showFile(io, allocator, environ, runner, dest, spec.ref, spec.path);
}

//
// TMPDIR, else TMP, else TEMP, else `/tmp`.
//
fn tempParent(environ: *const std.process.Environ.Map) []const u8 {
    if (nonEmpty(environ.get("TMPDIR"))) |value| {
        return value;
    }
    if (nonEmpty(environ.get("TMP"))) |value| {
        return value;
    }
    if (nonEmpty(environ.get("TEMP"))) |value| {
        return value;
    }
    return "/tmp";
}

//
// `<parent>/skl-from-<random>/<repo>`. Parent is created by clone; dest itself must not exist yet.
//
fn uniqueDest(
    io: std.Io,
    allocator: std.mem.Allocator,
    parent: []const u8,
    repo: []const u8,
) std.mem.Allocator.Error![]const u8 {
    var random_bytes: [12]u8 = undefined;
    io.random(&random_bytes);
    const suffix = std.fmt.bytesToHex(random_bytes, .lower);
    const dir_name = try std.fmt.allocPrint(allocator, "skl-from-{s}", .{suffix});
    return files.joinPath(allocator, &.{ parent, dir_name, repo });
}

//
// Joins git-show path segments with `/` after validating each one.
//
fn joinGitPath(allocator: std.mem.Allocator, parts: []const []const u8) std.mem.Allocator.Error!failure.Result([]const u8) {
    for (parts) |part| {
        switch (remote.validateName(part, "path")) {
            .ok => {},
            .failed => |why| return .{
                .failed = why,
            },
        }
    }
    return .{
        .ok = try std.mem.join(allocator, "/", parts),
    };
}

//
// Validates each `/`-separated segment of a path that already uses git's slashes.
//
fn copyGitPath(allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error!failure.Result([]const u8) {
    if (path.len == 0) {
        return .{
            .failed = failure.because("Invalid --from spec: the path is empty.", .{}),
        };
    }
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (part.len == 0) {
            return .{
                .failed = failure.because("Invalid --from path '{s}'.", .{path}),
            };
        }
        try parts.append(allocator, part);
    }
    return joinGitPath(allocator, parts.items);
}

//
// True when both repo strings name the same package, including SSH vs owner/repo spelling.
//
fn samePackage(allocator: std.mem.Allocator, left: []const u8, right: []const u8) bool {
    if (std.mem.eql(u8, left, right)) {
        return true;
    }
    const parsed_left = switch (remote.parse(allocator, left) catch return false) {
        .ok => |got| got,
        .failed => return false,
    };
    const parsed_right = switch (remote.parse(allocator, right) catch return false) {
        .ok => |got| got,
        .failed => return false,
    };
    return std.mem.eql(u8, parsed_left.host, parsed_right.host) and
        std.mem.eql(u8, parsed_left.owner, parsed_right.owner) and
        std.mem.eql(u8, parsed_left.repo, parsed_right.repo);
}

//
// First existing entry that already uses this namespace, if any.
//
fn namespaceTaken(packages: []const config.Package, namespace: []const u8) ?config.Package {
    for (packages) |pkg| {
        if (std.mem.eql(u8, pkg.namespace, namespace)) {
            return pkg;
        }
    }
    return null;
}

//
// Bytes before the first needle, or the whole slice when it is absent.
//
fn stripAfter(text: []const u8, needle: u8) []const u8 {
    if (std.mem.indexOfScalar(u8, text, needle)) |index| {
        return text[0..index];
    }
    return text;
}

//
// Scheme prefixes are matched without regard to case so `HTTPS://` still parses as a blob URL.
//
fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) {
        return false;
    }
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

//
// The slice when it is present and non-empty, otherwise null.
//
fn nonEmpty(value: ?[]const u8) ?[]const u8 {
    const slice = value orelse return null;
    if (slice.len == 0) {
        return null;
    }
    return slice;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("from.test.zig");
}
