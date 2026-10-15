//
// The test input factories for the functions in `remote.zig`, so Faultline can call them with a
// real failure.
//

const std = @import("std");

//
// The repo in `skl add acme/skills --ns demo`.
//
pub fn shorthandSpec() []const u8 {
    return "acme/skills";
}

//
// The repo in `skl add acme/skills.git --ns demo`.
//
pub fn shorthandWithGitSuffixSpec() []const u8 {
    return "acme/skills.git";
}

//
// The repo in `skl add git@github.com:acme/skills.git --ns demo`.
//
pub fn sshSpec() []const u8 {
    return "git@github.com:acme/skills.git";
}

//
// The repo in `skl add git@git.example.com:acme/skills --ns demo`.
//
pub fn sshOtherHostSpec() []const u8 {
    return "git@git.example.com:acme/skills";
}

//
// The repo in `skl add git@:acme/skills --ns demo`, which is refused.
//
pub fn sshWithoutHostSpec() []const u8 {
    return "git@:acme/skills";
}

//
// The repo in `skl add git@-bad.com:acme/skills --ns demo`, which is refused.
//
pub fn sshBadHostSpec() []const u8 {
    return "git@-bad.com:acme/skills";
}

//
// The repo in `skl add git@github.com --ns demo`, which is refused.
//
pub fn sshWithoutPathSpec() []const u8 {
    return "git@github.com";
}

//
// The repo in `skl add https://github.com/acme/skills --ns demo`, which is refused.
//
pub fn httpsSpec() []const u8 {
    return "https://github.com/acme/skills";
}

//
// The repo in `skl add ../skills --ns demo`, a path, which is refused.
//
pub fn relativePathSpec() []const u8 {
    return "../skills";
}

//
// The repo in `skl add /home/skilled/skills --ns demo`, a path, which is refused.
//
pub fn absolutePathSpec() []const u8 {
    return "/home/skilled/skills";
}

//
// The repo in `skl add C:\\\\skills --ns demo`, a Windows path, which is refused.
//
pub fn windowsPathSpec() []const u8 {
    return "C:\\skills";
}

//
// The repo in `skl add acme/skills/extra --ns demo`, which is refused.
//
pub fn tooManySlashesSpec() []const u8 {
    return "acme/skills/extra";
}

//
// The repo in `skl add "acme/sk ills" --ns demo`, which is refused.
//
pub fn badCharacterSpec() []const u8 {
    return "acme/sk ills";
}

//
// The repo in `skl add github:acme/skills --ns demo`, which is refused.
//
pub fn githubPrefixSpec() []const u8 {
    return "github:acme/skills";
}

//
// The repo in `skl add file:///home/skilled/skills --ns demo`, a file URL, which is refused.
//
pub fn fileUrlSpec() []const u8 {
    return "file:///home/skilled/skills";
}

//
// The repo in `skl add C:/skills --ns demo`, a Windows path written with a forward slash, which is
// refused.
//
pub fn windowsForwardSlashPathSpec() []const u8 {
    return "C:/skills";
}

//
// The branch in `skl add acme/skills --ns demo --branch HEAD`, which is refused.
//
pub fn headBranch() []const u8 {
    return "HEAD";
}

//
// The branch in `skl add acme/skills --ns demo --branch feature/`, which is refused.
//
pub fn branchEndingInSlash() []const u8 {
    return "feature/";
}

//
// The repo in `skl add git@github.com:skills --ns demo`, which has no owner and is refused.
//
pub fn sshWithoutOwnerSpec() []const u8 {
    return "git@github.com:skills";
}

//
// The repo in `skl add "git@github.com:ac me/skills" --ns demo`, whose owner is refused.
//
pub fn sshBadOwnerSpec() []const u8 {
    return "git@github.com:ac me/skills";
}

//
// The branch in `skl add acme/skills --ns demo --branch feature//dev`, which has an empty part and
// is refused.
//
pub fn branchWithEmptyPart() []const u8 {
    return "feature//dev";
}

//
// The repo in `skl add acme/xxx…/extra --ns demo` with a repo name of 1100 letters, which is
// refused with a message too long to hold whole, so it is cut short.
//
pub fn tooLongToQuoteSpec() []const u8 {
    return "acme/" ++ "x" ** 1100 ++ "/extra";
}
