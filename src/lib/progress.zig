//
// The stderr spinner drawn while clone and link run.
//
// Writes a single line and clears it on finish. A no-op when non-interactive, stderr is not a TTY,
// or color is off. Never writes to stdout. The writer is passed in so a test can capture the bytes.
//

const std = @import("std");

//
// Color and TTY detection, used to decide whether this progress line should run at all.
//
const term = @import("term.zig");

//
// Frames of the spinner drawn at the start of the progress line.
//
// Braille rather than `|/-\\` because progress only runs when color (and so Unicode icons) is on.
//
const spinner_frames = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

//
// Clears the current line using the ANSI erase-line sequence, then returns the cursor to column 0.
//
// Used both before a new step and on finish, so a later stdout write does not sit beside leftover
// spinner text. Progress only runs when color is enabled, so ANSI is available.
//
const clear_line = "\r\x1b[2K";

//
// Room for a clone or link step: the verb, a repo or `ns/name`, and the ellipsis.
//
const text_cap = 256;

//
// A single-line spinner written to stderr while clone and link run.
//
// The writer is passed in rather than taken from the process, so a test can capture the bytes and
// the CLI can point it at stderr. Writes are swallowed: a broken pipe on the progress line must
// not fail the clone that is still running.
//
pub const Progress = struct {
    //
    // Where the line is written. Stderr in the CLI; a growing buffer in tests.
    //
    writer: *std.Io.Writer,

    //
    // False when the line must not be drawn: non-interactive, stderr is not a TTY, or style is off.
    //
    enabled: bool,

    //
    // Which spinner frame was last drawn, so `tick` can advance it without the caller tracking it.
    //
    frame: usize = 0,

    //
    // The current step text, owned here so `tick` can redraw it after `set` returns.
    //
    text_buf: [text_cap]u8 = undefined,

    //
    // How much of `text_buf` is the current step.
    //
    text_len: usize = 0,

    //
    // Builds a progress line that is a no-op unless color is on, the run is interactive, and
    // stderr is a TTY.
    //
    pub fn init(writer: *std.Io.Writer, style: term.Style, non_interactive: bool, stderr_is_tty: bool) Progress {
        return .{
            .writer = writer,
            .enabled = style.color and !non_interactive and stderr_is_tty,
        };
    }

    //
    // Draws `Cloning owner/repo…` and starts the spinner on that message.
    //
    pub fn cloning(self: *Progress, repo: []const u8) void {
        self.set("Cloning {s}…", .{repo});
    }

    //
    // Draws `Linking ns/name…` and starts the spinner on that message.
    //
    pub fn linking(self: *Progress, ns_name: []const u8) void {
        self.set("Linking {s}…", .{ns_name});
    }

    //
    // Advances the spinner without changing the step text.
    //
    pub fn tick(self: *Progress) void {
        if (!self.enabled) {
            return;
        }
        self.frame += 1;
        self.draw();
    }

    //
    // Erases the progress line so later stdout is not written beside it.
    //
    pub fn finish(self: *Progress) void {
        if (!self.enabled) {
            return;
        }
        self.write(clear_line);
        self.text_len = 0;
        self.frame = 0;
    }

    //
    // Replaces the step text and draws it.
    //
    fn set(self: *Progress, comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled) {
            return;
        }
        const text = std.fmt.bufPrint(&self.text_buf, fmt, args) catch {
            self.text_len = 0;
            self.draw();
            return;
        };
        self.text_len = text.len;
        self.draw();
    }

    //
    // Writes the current frame and step text, replacing whatever was on the line.
    //
    fn draw(self: *Progress) void {
        if (!self.enabled) {
            return;
        }
        const frame = spinner_frames[self.frame % spinner_frames.len];
        var buf: [text_cap + 32]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "{s}{s} {s}", .{ clear_line, frame, self.text_buf[0..self.text_len] }) catch return;
        self.write(line);
    }

    //
    // Writes bytes and flushes, ignoring a broken pipe so the work behind the spinner can finish.
    //
    fn write(self: *Progress, bytes: []const u8) void {
        self.writer.writeAll(bytes) catch return;
        self.writer.flush() catch return;
    }
};

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("progress.test.zig");
}
