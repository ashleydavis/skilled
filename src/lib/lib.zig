//
// The reusable half of the project, gathered under one name.
//
// What belongs here is anything not specific to one CLI invocation: filesystem helpers, the
// config format, git store, linker. What does not is the application itself, which is src/main.zig
// and src/cmd.
//
// Most of what is here takes everything it needs as arguments and touches no global state: no argv,
// no working directory, no stdout. That is what makes it reachable from a unit test.
//

//
// How the message that goes with a failure is carried, in place of an exception.
//
pub const failure = @import("failure.zig");

//
// The value used wherever the structure is not known at compile time.
//
pub const value = @import("value.zig");

//
// Reading and writing YAML.
//
pub const yaml = @import("yaml.zig");

//
// The filesystem operations everything else is built out of.
//
pub const files = @import("files.zig");

//
// The command line library: a port of the parts of `commander` this tool uses.
//
pub const commander = @import("commander.zig");

//
// Whether this run should use color, icons, and interactive prompts.
//
pub const term = @import("term.zig");

//
// The stderr spinner drawn while clone and link run.
//
pub const progress = @import("progress.zig");

//
// Home, config, store, and agent directories, resolved the same way on every platform.
//
pub const paths = @import("paths.zig");

//
// SSH clone specs turned into host/owner/repo, with the name rules a later namespace uses.
//
pub const remote = @import("remote.zig");

//
// skl.yaml: a list of `{repo, namespace}` packages, read and written as YAML.
//
pub const config = @import("config.zig");

//
// YAML frontmatter and first-paragraph descriptions from skill and command markdown.
//
pub const frontmatter = @import("frontmatter.zig");

//
// Skills and commands found in a cloned package tree.
//
pub const package = @import("package.zig");

//
// Clone, show, fetch, and HEAD in the git store, via argv-array spawns.
//
pub const git = @import("git.zig");

//
// `--from` spec parsing, throwaway clone + `git show`, and YAML package-list merge.
//
pub const from = @import("from.zig");

//
// Namespace symlinks from the store into Cursor and Claude skill and command directories.
//
pub const link = @import("link.zig");

//
// Which build this is.
//
pub const version = @import("version.zig");

test {
    //
    // Pulls in every module's own tests, so `zig build test` runs the lot rather than only the
    // handful reachable from whatever happened to be referenced.
    //
    @import("std").testing.refAllDecls(@This());
}
