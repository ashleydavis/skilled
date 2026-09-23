//
// Whether this run should use color, icons, and interactive prompts.
//
// Color and prompts are decided from argv, the environment, and whether the matching stream is a
// TTY, so a test can pass fake args and a map rather than owning a real terminal. The CLI computes
// these once and hands the result down; nothing here looks at the process on its own.
//

const std = @import("std");

//
// The success mark, used when icons are on.
//
pub const check_icon = "✓";

//
// The failure mark, used when icons are on.
//
pub const cross_icon = "✗";

//
// The next-step mark, used when icons are on.
//
pub const arrow_icon = "→";

//
// The package mark, used when icons are on.
//
pub const package_icon = "📦";

//
// The palette, kept here so every command paints the same kind of thing the same way.
//
// `namespace` is what a user types in an agent, `identifier` is where files came from, `muted` is
// anything a reader can skip: a path, a SHA, prose. Values are the SGR parameters `paint` takes,
// not whole escape sequences, so a caller that already has an allocator can reuse them.
//

//
// A namespace: the handle typed in Cursor or Claude.
//
pub const namespace_color = "1;33";

//
// An identifier: owner/repo, a URL, a branch.
//
pub const identifier_color = "1;36";

//
// Anything secondary: paths, SHAs, descriptions.
//
pub const muted_color = "2";

//
// A grouping label inside a listing.
//
pub const label_color = "35";

//
// Raw sequences for the marks above, which are printed without an allocator.
//
const green = "\x1b[32m";
const red = "\x1b[31m";
const dim = "\x1b[2m";
const reset = "\x1b[0m";

//
// Whether color and icons should be written.
//
// Icons follow color: they are on only when color is on. Two fields rather than one, so a caller
// can ask about either without knowing that v1 keeps them in lockstep.
//
pub const Style = struct {
    //
    // Whether ANSI color is written to stdout.
    //
    color: bool,

    //
    // Whether Unicode icons are used. Off whenever color is off.
    //
    icons: bool,

    //
    // The mark for a success: green when color is on, and its ASCII stand-in when it is off.
    //
    // The escape is baked into the returned string rather than wrapped by the caller, because a
    // mark is printed on nearly every line and an allocator on that path buys nothing.
    //
    pub fn check(self: Style) []const u8 {
        if (!self.color) {
            return if (self.icons) check_icon else "OK";
        }
        return if (self.icons) green ++ check_icon ++ reset else green ++ "OK" ++ reset;
    }

    //
    // The mark for a failure: red when color is on.
    //
    pub fn cross(self: Style) []const u8 {
        if (!self.color) {
            return if (self.icons) cross_icon else "X";
        }
        return if (self.icons) red ++ cross_icon ++ reset else red ++ "X" ++ reset;
    }

    //
    // The mark for a next step, dimmed so the things it sits between stay louder than it.
    //
    pub fn arrow(self: Style) []const u8 {
        if (!self.color) {
            return if (self.icons) arrow_icon else "->";
        }
        return if (self.icons) dim ++ arrow_icon ++ reset else dim ++ "->" ++ reset;
    }

    //
    // The mark for a package, or its ASCII stand-in when icons are off. Never coloured: the emoji
    // carries its own.
    //
    pub fn package(self: Style) []const u8 {
        return if (self.icons) package_icon else "#";
    }
};

//
// Turns color and icons off when any of: `--no-color`, `NO_COLOR` set to any value,
// `SKL_NO_COLOR=1`, or stdout is not a TTY.
//
pub fn detectStyle(args: []const []const u8, env: *const std.process.Environ.Map, stdout_is_tty: bool) Style {
    const color = stdout_is_tty and
        !argsContain(args, "--no-color") and
        env.get("NO_COLOR") == null and
        !std.mem.eql(u8, env.get("SKL_NO_COLOR") orelse "", "1");
    return .{ .color = color, .icons = color };
}

//
// True when prompts must not run: `--non-interactive` / `-n`, `SKL_NONINTERACTIVE=1`, or stdin is
// not a TTY.
//
pub fn nonInteractive(args: []const []const u8, env: *const std.process.Environ.Map, stdin_is_tty: bool) bool {
    return !stdin_is_tty or
        argsContain(args, "--non-interactive") or
        argsContain(args, "-n") or
        std.mem.eql(u8, env.get("SKL_NONINTERACTIVE") orelse "", "1");
}

//
// True when one of the argv tokens is exactly `needle`.
//
// Exact tokens only: clustered shorts are out of scope, and a value that happens to look like a
// flag is still a token the user typed.
//
fn argsContain(args: []const []const u8, needle: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, needle)) {
            return true;
        }
    }
    return false;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("term.test.zig");
}
