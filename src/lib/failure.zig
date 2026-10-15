//
// How a failure and the message that goes with it are returned.
//
// Zig errors are bare enum values and cannot carry a string, so a function that can refuse returns
// a `Result`: either its value or a `Failure` holding the message. The message travels back with
// the failure, through every caller, to the top of the CLI, which prints it. Nothing is written
// anywhere on the way.
//
// Running out of memory is not a refusal: it stays the Zig error `error.OutOfMemory`, so a function
// that allocates returns `std.mem.Allocator.Error!Result(T)`.
//

const std = @import("std");

//
// How many bytes a message can hold. Far more than any message here, which is a sentence naming a
// path or a package. A longer one is cut short and ends in `...`.
//
pub const message_capacity = 1024;

//
// Why something was refused, as the sentence a person reads. Held inside the value, so making one
// allocates nothing and cannot fail.
//
pub const Failure = struct {
    //
    // The message's bytes, of which the first `len` are written.
    //
    buffer: [message_capacity]u8 = undefined,

    //
    // How many bytes of `buffer` the message is.
    //
    len: usize = 0,

    //
    // The message.
    //
    pub fn message(self: *const Failure) []const u8 {
        return self.buffer[0..self.len];
    }
};

//
// A Failure whose message is `fmt` formatted with `args`.
//
pub fn because(comptime fmt: []const u8, args: anytype) Failure {
    var made: Failure = .{};
    var writer = std.Io.Writer.fixed(&made.buffer);
    writer.print(fmt, args) catch {
        //
        // The message did not fit: what did fit is kept and ends in `...`, so a reader can tell
        // it was cut.
        //
        writer.end = made.buffer.len - "...".len;
        writer.writeAll("...") catch unreachable;
    };
    made.len = writer.end;
    return made;
}

//
// What a function that can refuse returns: its value, or the failure that says why not.
//
pub fn Result(comptime T: type) type {
    return union(enum) {
        //
        // The value, when nothing was refused.
        //
        ok: T,

        //
        // Why it was refused.
        //
        failed: Failure,
    };
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change
    // to the code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("failure.test.zig");
}
