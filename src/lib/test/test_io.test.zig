//
// The `Io` each unit test makes for itself, so two tests never share one.
//
// Test-only, so it lives in a `.test.zig` file and never in the code the tests exercise.
//

const std = @import("std");

//
// An `Io` for one test, torn down with it.
//
// Every test that touches a disk makes its own rather than sharing one, so nothing a test does to
// its `Io` can reach another test. Held by the caller, because the `Io` handed out points back at
// the `Threaded` inside it and a copy would leave that pointer aimed at the wrong place.
//
pub const TestIo = struct {
    //
    // The threaded implementation the `Io` interface points at.
    //
    // Must live in this struct, not on the stack of `init`, so the pointer inside the `Io` stays
    // valid for as long as the test holds the `TestIo`.
    //
    threaded: std.Io.Threaded,

    //
    // The page allocator rather than the testing allocator: this belongs to the test itself, not to
    // the code under test, so it must not show up in that code's leak checking.
    //
    pub fn init() TestIo {
        return .{
            .threaded = .init(std.heap.page_allocator, .{}),
        };
    }

    //
    // The `Io` to pass into filesystem calls under test.
    //
    pub fn io(self: *TestIo) std.Io {
        return self.threaded.io();
    }

    //
    // Tears down the threaded implementation.
    //
    pub fn deinit(self: *TestIo) void {
        self.threaded.deinit();
    }
};
