//
// The test input factories for `File`, the parsed `skl.yaml`, so Faultline calls the functions that
// write it with real packages.
//

const std = @import("std");

//
// The file that declares `File`.
//
const config = @import("config.zig");

//
// The `skl.yaml` that `skl add acme/skills --ns demo`, `skl add acme/tools --ns tools --branch dev`
// and `skl add acme/local --ns local --local ../local-skills` leave: one package of each kind.
//
pub fn threePackages(allocator: std.mem.Allocator) !config.File {
    const packages = try allocator.alloc(config.Package, 3);
    packages[0] = .{
        .repo = "acme/skills",
        .namespace = "demo",
    };
    packages[1] = .{
        .repo = "acme/tools",
        .namespace = "tools",
        .branch = "dev",
    };
    packages[2] = .{
        .repo = "acme/local",
        .namespace = "local",
        .local = "../local-skills",
    };
    return .{
        .packages = packages,
    };
}

//
// The `skl.yaml` that `skl init` writes: no packages.
//
pub fn noPackages() config.File {
    return .{
        .packages = &.{},
    };
}

//
// The `skl.yaml` `skl install` reads after `skl add` wrote one package of each kind and someone
// added a comment and quotes by hand.
//
pub fn everyKindOfRowText() []const u8 {
    return
        \\# The project's packages.
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: "acme/tools"
        \\    namespace: 'tools'
        \\    branch: dev
        \\  - repo: git@github.com:acme/local.git
        \\    namespace: local
        \\    local: ../local-skills
        \\    branch: ~
        \\
    ;
}

//
// An `skl.yaml` edited by hand into a list, which `skl install` refuses.
//
pub fn notAnObjectText() []const u8 {
    return
        \\- acme/skills
        \\
    ;
}

//
// An `skl.yaml` whose `packages` is a string, which `skl install` refuses.
//
pub fn packagesNotAListText() []const u8 {
    return
        \\packages: acme/skills
        \\
    ;
}

//
// An `skl.yaml` whose package is a bare string, which `skl install` refuses.
//
pub fn rowNotAnObjectText() []const u8 {
    return
        \\packages:
        \\  - acme/skills
        \\
    ;
}

//
// An `skl.yaml` whose package has no `repo`, which `skl install` refuses.
//
pub fn rowWithoutRepoText() []const u8 {
    return
        \\packages:
        \\  - namespace: demo
        \\
    ;
}

//
// An `skl.yaml` whose package has an empty `branch`, which `skl install` refuses.
//
pub fn rowWithEmptyBranchText() []const u8 {
    return
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: ""
        \\
    ;
}

//
// An `skl.yaml` whose package has a number for `branch`, which `skl install` refuses.
//
pub fn rowWithNumberBranchText() []const u8 {
    return
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: 2
        \\
    ;
}

//
// An `skl.yaml` whose package has both `branch` and `local`, which `skl install` refuses.
//
pub fn rowWithBranchAndLocalText() []const u8 {
    return
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    branch: dev
        \\    local: ../skills
        \\
    ;
}

//
// An `skl.yaml` whose package uses the scratch directory's namespace, which `skl install`
// refuses.
//
pub fn rowWithReservedNamespaceText() []const u8 {
    return
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: loc
        \\
    ;
}

//
// An `skl.yaml` with two packages under one namespace, which `skl install` refuses.
//
pub fn duplicateNamespaceText() []const u8 {
    return
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\  - repo: acme/tools
        \\    namespace: demo
        \\
    ;
}

//
// An `skl.yaml` with a field one space out of line, which `skl install` refuses.
//
pub fn badIndentText() []const u8 {
    return
        \\packages:
        \\  - repo: acme/skills
        \\   namespace: demo
        \\
    ;
}

//
// An `skl.yaml` whose package has no `namespace`, which `skl install` refuses.
//
pub fn rowWithoutNamespaceText() []const u8 {
    return
        \\packages:
        \\  - repo: acme/skills
        \\
    ;
}

//
// An `skl.yaml` whose package has an empty `local`, which `skl install` refuses.
//
pub fn rowWithEmptyLocalText() []const u8 {
    return
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    local: ""
        \\
    ;
}
