//
// The test input factories for the functions in `progress.zig`, so Faultline can call them with a
// step too long for the progress line.
//

//
// The repo in `skl add acme/aaa… --ns demo` with a repo name of 300 letters, too long for the
// progress line to show whole.
//
pub fn repoTooLongToShow() []const u8 {
    return "acme/" ++ "a" ** 300;
}
