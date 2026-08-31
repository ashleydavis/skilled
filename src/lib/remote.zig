//
// SSH-only clone specs turned into host, owner, and repo.
//
// HTTPS, `github:` shorthands, and filesystem paths are refused here so a later clone or symlink
// never runs on a string that can leave the store or an agent root. Git still performs SSH
// authentication; nothing here looks at `~/.ssh` or private keys.
//

const std = @import("std");

//
// How a rejected spec or name is described to the caller.
//
const failure = @import("failure.zig");

//
// One accepted remote, after shorthand expansion and name checks.
//
// `clone_url` is what `git clone` receives. `repo` is the package name: the git repo name with a
// trailing `.git` stripped. Strings are allocated from the caller's allocator so the spec does not
// have to outlive this value.
//
pub const Remote = struct {
    //
    // The URL passed to `git clone`. Constructed for `owner/repo`; the input string for SSH.
    //
    clone_url: []const u8,

    //
    // Store directory name for the host, including dots (`github.example.com` stays one segment).
    //
    host: []const u8,

    //
    // The GitHub (or other host) owner segment.
    //
    owner: []const u8,

    //
    // The package name: repo last segment without a trailing `.git`.
    //
    repo: []const u8,
};

//
// Parses `owner/repo` or `git@host:owner/repo` into a Remote, or records why the spec is refused.
//
// `owner/repo` becomes `git@github.com:owner/repo.git`. An SSH spec is kept as-is for cloning.
// Invalid names fail before any URL is built.
//
pub fn parse(allocator: std.mem.Allocator, spec: []const u8, fail: *failure.Failure) failure.Error!Remote {
    if (spec.len == 0) {
        return fail.set("remote is empty; expected owner/repo or git@host:owner/repo", .{});
    }
    if (startsWithIgnoreCase(spec, "https://") or startsWithIgnoreCase(spec, "http://")) {
        return fail.set("HTTPS remotes are not supported; use owner/repo or git@host:owner/repo", .{});
    }
    if (startsWithIgnoreCase(spec, "github:")) {
        return fail.set("`github:` remotes are not supported; use owner/repo or git@host:owner/repo", .{});
    }
    if (isFilesystemPath(spec)) {
        return fail.set("filesystem paths are not supported; use owner/repo or git@host:owner/repo", .{});
    }
    if (std.mem.startsWith(u8, spec, "git@")) {
        return parseSsh(allocator, spec, fail);
    }
    return parseShorthand(allocator, spec, fail);
}

//
// The shared rule for host labels, owner, repo, and (in later steps) namespace.
//
// Pub so tests and later link/`--ns` code share one check: a rejected name never becomes a
// directory under `skills/` or the store.
//
pub fn validateName(name: []const u8, what: []const u8, fail: *failure.Failure) failure.Error!void {
    if (name.len == 0) {
        return fail.set("invalid {s}: empty", .{what});
    }
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
        return fail.set("invalid {s} '{s}': '.' and '..' are not allowed", .{ what, name });
    }
    for (name) |c| {
        if (!isNameChar(c)) {
            return fail.set("invalid {s} '{s}': must match [A-Za-z0-9._-]+", .{ what, name });
        }
    }
}

//
// `--branch` names: same per-segment rule as validateName, with `/` allowed between segments.
//
// Pub so clone, checkout, and `--branch` share one check: a dash-prefixed name cannot become a git
// flag, and `feature/foo` is accepted.
//
pub fn validateBranch(name: []const u8, fail: *failure.Failure) failure.Error!void {
    if (name.len == 0) {
        return fail.set("invalid branch: empty", .{});
    }
    if (std.ascii.eqlIgnoreCase(name, "HEAD")) {
        return fail.set("invalid branch '{s}'", .{name});
    }
    if (name[0] == '-') {
        return fail.set("invalid branch '{s}': must not start with '-'", .{name});
    }
    for (name) |c| {
        if (c == '\\' or c == ':' or c == '<' or c == '>' or c == '"' or c == '|' or c == '?' or c == '*') {
            return fail.set("invalid branch '{s}'", .{name});
        }
    }
    if (name[0] == '/' or name[name.len - 1] == '/') {
        return fail.set("invalid branch '{s}'", .{name});
    }
    var segments = std.mem.splitScalar(u8, name, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0) {
            return fail.set("invalid branch '{s}'", .{name});
        }
        try validateName(segment, "branch", fail);
    }
}fn parseSsh(allocator: std.mem.Allocator, spec: []const u8, fail: *failure.Failure) failure.Error!Remote {
    const rest = spec["git@".len..];
    const colon = std.mem.indexOfScalar(u8, rest, ':') orelse {
        return fail.set("invalid SSH remote '{s}'; expected git@host:owner/repo", .{spec});
    };
    const host = rest[0..colon];
    const path = rest[colon + 1 ..];
    const slash = std.mem.indexOfScalar(u8, path, '/') orelse {
        return fail.set("invalid SSH remote '{s}'; expected git@host:owner/repo", .{spec});
    };
    if (std.mem.indexOfScalar(u8, path[slash + 1 ..], '/') != null) {
        return fail.set("invalid SSH remote '{s}'; expected git@host:owner/repo", .{spec});
    }
    const owner = path[0..slash];
    const repo = stripGitSuffix(path[slash + 1 ..]);
    try validateHost(host, fail);
    try validateName(owner, "owner", fail);
    try validateName(repo, "repo", fail);
    return try ownedRemote(allocator, spec, host, owner, repo);
}

//
// `owner/repo` or `owner/repo.git` → clone URL `git@github.com:owner/repo.git`.
//
fn parseShorthand(allocator: std.mem.Allocator, spec: []const u8, fail: *failure.Failure) failure.Error!Remote {
    const slash = std.mem.indexOfScalar(u8, spec, '/') orelse {
        return fail.set("invalid remote '{s}'; expected owner/repo or git@host:owner/repo", .{spec});
    };
    if (std.mem.indexOfScalar(u8, spec[slash + 1 ..], '/') != null) {
        return fail.set("invalid remote '{s}'; expected owner/repo or git@host:owner/repo", .{spec});
    }
    const owner = spec[0..slash];
    const repo = stripGitSuffix(spec[slash + 1 ..]);
    try validateName(owner, "owner", fail);
    try validateName(repo, "repo", fail);
    const clone_url = try std.fmt.allocPrint(allocator, "git@github.com:{s}/{s}.git", .{ owner, repo });
    errdefer allocator.free(clone_url);
    return try ownedParts(allocator, clone_url, "github.com", owner, repo);
}

//
// Each host label is checked with the same rule as owner/repo; dots only separate labels.
//
fn validateHost(host: []const u8, fail: *failure.Failure) failure.Error!void {
    if (host.len == 0) {
        return fail.set("invalid host: empty", .{});
    }
    var labels = std.mem.splitScalar(u8, host, '.');
    while (labels.next()) |label| {
        if (label.len == 0) {
            return fail.set("invalid host '{s}': empty label", .{host});
        }
        try validateName(label, "host", fail);
    }
}

//
// Copies every Remote field so the result does not borrow the spec. `clone_url` is already owned.
//
fn ownedParts(
    allocator: std.mem.Allocator,
    clone_url: []const u8,
    host: []const u8,
    owner: []const u8,
    repo: []const u8,
) failure.Error!Remote {
    const host_owned = try allocator.dupe(u8, host);
    errdefer allocator.free(host_owned);
    const owner_owned = try allocator.dupe(u8, owner);
    errdefer allocator.free(owner_owned);
    const repo_owned = try allocator.dupe(u8, repo);
    return .{
        .clone_url = clone_url,
        .host = host_owned,
        .owner = owner_owned,
        .repo = repo_owned,
    };
}

//
// SSH form: duplicate the input as the clone URL, then the parsed segments.
//
fn ownedRemote(
    allocator: std.mem.Allocator,
    spec: []const u8,
    host: []const u8,
    owner: []const u8,
    repo: []const u8,
) failure.Error!Remote {
    const clone_url = try allocator.dupe(u8, spec);
    errdefer allocator.free(clone_url);
    return try ownedParts(allocator, clone_url, host, owner, repo);
}

//
// Git's clone URL may end in `.git`; the package name never does.
//
fn stripGitSuffix(name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, name, ".git")) {
        return name[0 .. name.len - ".git".len];
    }
    return name;
}

//
// Absolute, drive-letter, relative, `file:`, and `~` paths, so they never parse as owner/repo.
//
fn isFilesystemPath(spec: []const u8) bool {
    if (spec[0] == '/' or spec[0] == '\\' or spec[0] == '~') {
        return true;
    }
    if (std.mem.eql(u8, spec, ".") or std.mem.eql(u8, spec, "..")) {
        return true;
    }
    if (std.mem.startsWith(u8, spec, "./") or std.mem.startsWith(u8, spec, "../")) {
        return true;
    }
    if (std.mem.indexOfScalar(u8, spec, '\\') != null) {
        return true;
    }
    if (startsWithIgnoreCase(spec, "file:")) {
        return true;
    }
    if (spec.len >= 3 and spec[1] == ':' and (spec[2] == '/' or spec[2] == '\\') and std.ascii.isAlphabetic(spec[0])) {
        return true;
    }
    return false;
}

//
// Scheme prefixes are matched without regard to case so `HTTPS://` is still refused.
//
fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) {
        return false;
    }
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

//
// One character of `[A-Za-z0-9._-]+`, which already excludes `/`, `\`, `:`, and Windows-illegal
// `<>"|?*`.
//
fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-';
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("remote.test.zig");
}
