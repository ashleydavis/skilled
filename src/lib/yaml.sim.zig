//
// The test input factories for the functions in `yaml.zig`, so Faultline can call them with real
// failures and parsed YAML.
//

const std = @import("std");

//
// A `skl.yaml` written by hand with flow sequences and mappings on one line, as `skl install`
// reads it.
//
pub fn flowCollectionsText() []const u8 {
    return
        \\packages: [{repo: acme/skills, namespace: demo}, {repo: "acme/tools", namespace: tools}]
        \\names: [one, two, [three]]
        \\empty: []
        \\nothing: {}
        \\
    ;
}

//
// A `skl.yaml` written by hand with every kind of scalar, as `skl install` reads it.
//
pub fn scalarsText() []const u8 {
    return
        \\yes: true
        \\no: false
        \\count: 3
        \\negative: -4
        \\ratio: 1.5
        \\nothing: null
        \\tilde: ~
        \\empty:
        \\double: "a\tb\n\r\0\\ \/ \"c"
        \\single: 'it''s'
        \\plain: some words # a comment
        \\hash: a#b
        \\
    ;
}

//
// A `skl.yaml` written by hand with nested blocks and mappings on a dash line, as `skl install`
// reads it.
//
pub fn nestedBlocksText() []const u8 {
    return
        \\# top comment
        \\
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    extra:
        \\      - one
        \\      -
        \\        deep: yes
        \\  -
        \\    repo: acme/tools
        \\    namespace: tools
        \\settings:
        \\  colour: off
        \\
    ;
}

//
// A `skl.yaml` with a quote that is never closed, which `skl install` refuses.
//
pub fn unterminatedQuoteText() []const u8 {
    return
        \\packages: "acme
        \\
    ;
}

//
// A `skl.yaml` with a line indented under a scalar, which `skl install` refuses.
//
pub fn danglingIndentText() []const u8 {
    return
        \\packages: []
        \\    stray: 1
        \\
    ;
}

//
// A `skl.yaml` using an anchor, which `skl install` refuses.
//
pub fn anchorText() []const u8 {
    return
        \\base: &base
        \\  namespace: demo
        \\
    ;
}

//
// A `skl.yaml` holding two documents, which `skl install` refuses.
//
pub fn secondDocumentText() []const u8 {
    return
        \\packages: []
        \\---
        \\packages: []
        \\
    ;
}

//
// A `skl.yaml` indented with a tab, which `skl install` refuses.
//
pub fn tabIndentText() []const u8 {
    return "packages:\n\t- repo: acme/skills\n";
}

//
// A `skl.yaml` with a key and no colon, which `skl install` refuses.
//
pub fn missingColonText() []const u8 {
    return
        \\packages
        \\
    ;
}

//
// A `skl.yaml` with an escape YAML does not have, which `skl install` refuses.
//
pub fn badEscapeText() []const u8 {
    return
        \\name: "a\qb"
        \\
    ;
}

//
// A `skl.yaml` written by hand with quoted keys and numbers in every form, as `skl install` reads
// it.
//
pub fn numbersAndKeysText() []const u8 {
    return
        \\"quoted key": 1
        \\'single key': 2
        \\"a: b": 3
        \\exponent: 1e5
        \\signed: -1.5E-3
        \\bare: .5
        \\noexponent: 1e
        \\nosign: 1e+
        \\letters: 1e5x
        \\version: 1.2.3
        \\
    ;
}

//
// A `skl.yaml` with a flow sequence missing its commas, which `skl install` refuses.
//
pub fn flowErrorsText() []const u8 {
    return
        \\names: [one two]
        \\
    ;
}

//
// A `skl.yaml` with a flow mapping missing its colon, which `skl install` refuses.
//
pub fn flowMappingErrorText() []const u8 {
    return
        \\names: {one two}
        \\
    ;
}

//
// A `skl.yaml` with text after a flow sequence, which `skl install` refuses.
//
pub fn flowTrailingTextText() []const u8 {
    return
        \\names: [one] two
        \\
    ;
}

//
// A `skl.yaml` with a flow sequence that is never closed, which `skl install` refuses.
//
pub fn flowUnclosedText() []const u8 {
    return
        \\names: [one, {two: 2}
        \\
    ;
}

//
// A `skl.yaml` whose second line belongs to no block above it, which `skl install` refuses.
//
pub fn strayLineText() []const u8 {
    return
        \\- one
        \\key: 1
        \\
    ;
}

//
// A `skl.yaml` with a flow sequence as a key, which `skl install` refuses.
//
pub fn flowKeyText() []const u8 {
    return
        \\[one]: 1
        \\
    ;
}

//
// The parser whose output the factories below return.
//
const yaml = @import("yaml.zig");

//
// The value type the parser returns.
//
const value = @import("value.zig");

//
// What `skl install` holds after reading the hand-written `skl.yaml` of `nestedBlocksText`, as
// `skl add` then writes it back.
//
pub fn parsedNestedBlocks(allocator: std.mem.Allocator) !value.Value {
    return switch (try yaml.parse(allocator, nestedBlocksText())) {
        .ok => |parsed| parsed,
        .invalid => error.Syntax,
    };
}

//
// What `skl install` holds after reading the hand-written `skl.yaml` of `flowCollectionsText`, as
// `skl add` then writes it back.
//
pub fn parsedFlowCollections(allocator: std.mem.Allocator) !value.Value {
    return switch (try yaml.parse(allocator, flowCollectionsText())) {
        .ok => |parsed| parsed,
        .invalid => error.Syntax,
    };
}

//
// What `skl install` holds after reading the hand-written `skl.yaml` of `scalarsText`, as `skl add`
// then writes it back.
//
pub fn parsedScalars(allocator: std.mem.Allocator) !value.Value {
    return switch (try yaml.parse(allocator, scalarsText())) {
        .ok => |parsed| parsed,
        .invalid => error.Syntax,
    };
}

//
// An `skl.yaml` that `skl add` writes when a package's fields hold text that has to be quoted: a
// comment mark, quotes, a backslash, line ends, a tab and a number too long for an integer.
//
pub fn documentWithTextThatNeedsQuoting(allocator: std.mem.Allocator) !value.Value {
    var object: value.Object = .empty;
    try object.put(allocator, "comment", value.str("a #b"));
    try object.put(allocator, "colon", value.str("a: b"));
    try object.put(allocator, "escapes", value.str("say \"hi\" \\ now\nthen\rtab\t"));
    try object.put(allocator, "dash", value.str("- item"));
    try object.put(allocator, "big", .{
        .number_string = "123456789012345678901234567890",
    });
    return .{
        .object = object,
    };
}

//
// A `skl.yaml` with a quoted item in a flow sequence followed by another without a comma, which
// `skl install` refuses.
//
pub fn flowQuotedMissingCommaText() []const u8 {
    return
        \\names: ["one" two]
        \\
    ;
}

//
// A `skl.yaml` with a quoted value in a flow mapping followed by another key without a comma,
// which `skl install` refuses.
//
pub fn flowMappingQuotedMissingCommaText() []const u8 {
    return
        \\names: {one: "1" two: 2}
        \\
    ;
}
