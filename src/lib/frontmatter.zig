//
// Description text from markdown: YAML frontmatter `description`, or the first body paragraph.
//

const std = @import("std");

//
// The dynamic YAML tree the inner mapping is parsed into.
//
const value = @import("value.zig");

//
// The vendored parser. Multi-line scalars are unsupported here, which is why a `|` or `>`
// description falls back to the body instead of being misread.
//
const yaml = @import("yaml.zig");

//
// Description text from a markdown file: YAML frontmatter `description` when it is a single-line
// string, otherwise the first paragraph of the body.
//
// Vendored yaml.zig does not parse markdown, so the fence is stripped here before the inner
// mapping is handed to it. Allocations come from the caller (an arena in the CLI and in tests).
//
pub fn extract(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    const parts = split(text);
    if (parts.yaml) |inner| {
        if (try descriptionFromYaml(allocator, inner)) |desc| {
            return desc;
        }
    }
    return allocator.dupe(u8, firstParagraph(parts.body));
}

//
// The inner YAML (if a well-formed fence was found) and the markdown after it.
//
// Missing, unclosed, or non-starting fences leave yaml null and body as the whole file, which is
// what makes "no frontmatter" and "broken fence" both fall back to the first paragraph.
//
const Parts = struct {
    //
    // Bytes between the opening and closing `---` lines, or null when there is no complete fence.
    //
    yaml: ?[]const u8,

    //
    // Markdown after the closing fence, or the whole file when the fence is absent.
    //
    body: []const u8,
};

//
// Splits a markdown file on a leading `---` fence.
//
// Opening is `---\n` or `---\r\n`. Closing is a later line that is exactly `---` (`\n---\n` or
// `\n---\r\n`, or `---` at EOF). Anything else is treated as ordinary markdown.
//
fn split(text: []const u8) Parts {
    const after_open = blk: {
        if (std.mem.startsWith(u8, text, "---\n")) {
            break :blk text[4..];
        }
        if (std.mem.startsWith(u8, text, "---\r\n")) {
            break :blk text[5..];
        }
        return .{ .yaml = null, .body = text };
    };

    const closing_at = findClosingFence(after_open) orelse {
        return .{ .yaml = null, .body = text };
    };
    return .{
        .yaml = after_open[0..closing_at],
        .body = after_open[closing_at + fenceLineLen(after_open, closing_at) ..],
    };
}

//
// Index in after_open where a closing `---` line begins, or null if none is found.
//
fn findClosingFence(after_open: []const u8) ?usize {
    if (isFenceLineAt(after_open, 0)) {
        return 0;
    }
    var i: usize = 0;
    while (i < after_open.len) {
        if (after_open[i] == '\n' and isFenceLineAt(after_open, i + 1)) {
            return i + 1;
        }
        i += 1;
    }
    return null;
}

//
// True when text[i..] is a line whose only content is `---`.
//
fn isFenceLineAt(text: []const u8, i: usize) bool {
    if (i + 3 > text.len) {
        return false;
    }
    if (!std.mem.eql(u8, text[i .. i + 3], "---")) {
        return false;
    }
    if (i + 3 == text.len) {
        return true;
    }
    if (text[i + 3] == '\n') {
        return true;
    }
    if (text[i + 3] == '\r' and i + 4 < text.len and text[i + 4] == '\n') {
        return true;
    }
    return false;
}

//
// How many bytes the `---` line at i occupies, including its trailing newline when present.
//
fn fenceLineLen(text: []const u8, i: usize) usize {
    if (i + 3 == text.len) {
        return 3;
    }
    if (text[i + 3] == '\n') {
        return 4;
    }
    return 5;
}

//
// The frontmatter `description` when it is a non-empty plain or quoted string; otherwise null.
//
// YAML that fails to parse, a non-object document, a missing key, a multi-line scalar, or a
// non-string value all return null so the caller can use the body instead.
//
fn descriptionFromYaml(allocator: std.mem.Allocator, inner: []const u8) std.mem.Allocator.Error!?[]const u8 {
    var err: ?yaml.SyntaxError = null;
    const parsed = yaml.parse(allocator, inner, &err) catch |caught| switch (caught) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Syntax => return null,
    };
    if (!value.isPlainObject(parsed)) {
        return null;
    }
    const raw = value.get(parsed, "description") orelse return null;
    switch (raw) {
        .string => |text| {
            if (text.len == 0) {
                return null;
            }
            return try allocator.dupe(u8, text);
        },
        else => return null,
    }
}

//
// Text up to the first blank line, after leading blank lines are skipped.
//
// A blank line is one with no content, whether the file uses `\n` or `\r\n`. No blank line means
// the whole remaining text is the paragraph.
//
fn firstParagraph(text: []const u8) []const u8 {
    const start = skipLeadingNewlines(text);
    if (start >= text.len) {
        return "";
    }
    const rest = text[start..];
    var line_start: usize = 0;
    var i: usize = 0;
    while (i < rest.len) {
        if (rest[i] == '\n') {
            var line = rest[line_start..i];
            if (line.len > 0 and line[line.len - 1] == '\r') {
                line = line[0 .. line.len - 1];
            }
            if (line.len == 0) {
                return std.mem.trimEnd(u8, rest[0..line_start], " \t\r\n");
            }
            line_start = i + 1;
        }
        i += 1;
    }
    return std.mem.trimEnd(u8, rest, " \t\r\n");
}

//
// Index of the first non-whitespace byte, which is where the first paragraph starts.
//
fn skipLeadingNewlines(text: []const u8) usize {
    var i: usize = 0;
    while (i < text.len and (text[i] == '\n' or text[i] == '\r' or text[i] == ' ' or text[i] == '\t')) {
        i += 1;
    }
    return i;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("frontmatter.test.zig");
}
