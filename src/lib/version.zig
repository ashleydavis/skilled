//
// Which build this is.
//
// A release workflow rewrites this file from the git tag before compiling, so a working copy
// and a tagged binary report different values from the same source.
//

//
// The version string `skl --version` prints.
//
pub const version = "0.0.1";

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("version.test.zig");
}
