//
// The test input factories for the text of the markdown files `skl` reads descriptions from.
//

//
// The `SKILL.md` `skl list` reads for a skill whose frontmatter has a description.
//
pub fn skillWithDescriptionText() []const u8 {
    return
        \\---
        \\name: hello
        \\description: Says hello.
        \\---
        \\
        \\# Hello
        \\
        \\The body.
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose description is quoted.
//
pub fn skillWithQuotedDescriptionText() []const u8 {
    return
        \\---
        \\description: "Says: hello."
        \\---
        \\Body.
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose description is empty, so the body is used.
//
pub fn skillWithEmptyDescriptionText() []const u8 {
    return
        \\---
        \\description:
        \\---
        \\
        \\
        \\First paragraph
        \\still first.
        \\
        \\Second.
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose frontmatter is never closed.
//
pub fn skillWithoutClosingFenceText() []const u8 {
    return
        \\---
        \\description: Says hello.
        \\
        \\# Hello
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill saved with Windows line ends.
//
pub fn skillWithWindowsLineEndsText() []const u8 {
    return
        \\---
        \\description: Says hello.
        \\---
        \\
        \\# Hello
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill with no frontmatter, so its first paragraph is
// used.
//
pub fn skillWithoutFrontmatterText() []const u8 {
    return
        \\
        \\
        \\# Hello
        \\
        \\Says hello.
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose frontmatter is not valid YAML.
//
pub fn skillWithBadFrontmatterText() []const u8 {
    return
        \\---
        \\description: "unclosed
        \\---
        \\Body.
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose `---` line is not at the top.
//
pub fn skillWithFenceLaterText() []const u8 {
    return
        \\Intro.
        \\---
        \\description: no
        \\---
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose file ends on its closing `---` with no line
// end.
//
pub fn skillEndingAtFenceText() []const u8 {
    return "---\ndescription: Says hello.\n---";
}

//
// The `SKILL.md` `skl list` reads for a skill whose first line is `----`, which is not a fence.
//
pub fn skillWithLongDashLineText() []const u8 {
    return
        \\----
        \\description: no
        \\---
        \\
        \\Body.
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose frontmatter is a list, not a mapping.
//
pub fn skillWithListFrontmatterText() []const u8 {
    return
        \\---
        \\- one
        \\---
        \\
        \\Body.
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose description is a number.
//
pub fn skillWithNumberDescriptionText() []const u8 {
    return
        \\---
        \\description: 3
        \\---
        \\
        \\Body.
        \\
    ;
}

//
// The `SKILL.md` `skl list` reads for a skill whose closing `---` has a Windows line end.
//
pub fn skillWithWindowsClosingFenceText() []const u8 {
    return "---\r\ndescription: Says hello.\r\n---\r\nBody.\r\n";
}

//
// The `SKILL.md` `skl list` reads for a skill whose description is an empty quoted string, so the
// body is used.
//
pub fn skillWithEmptyQuotedDescriptionText() []const u8 {
    return
        \\---
        \\description: ""
        \\---
        \\
        \\Body.
        \\
    ;
}
