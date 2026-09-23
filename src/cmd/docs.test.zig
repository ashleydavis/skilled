//
// Tests for docs.zig.
//

const std = @import("std");
const add = @import("add.zig");
const docs = @import("docs.zig");
const harness = @import("../lib/test/harness.zig");
const init = @import("init.zig");
const shared = @import("shared.zig");
const testing = std.testing;

test "docs opens the Pages URL when interactive" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{ .repo = "acme/skills", .namespace = "demo" }));

    scenario.clear();
    const ctx = scenario.contextInteractive(false);
    try testing.expectEqual(@as(u8, 0), try docs.run(&ctx, .{ .query = "acme/skills" }));

    try testing.expectEqual(@as(usize, 1), scenario.browser.opens);
    try testing.expect(scenario.browser.argv.len >= 2);
    try testing.expectEqualStrings("https://acme.github.io/skills/", scenario.browser.argv[scenario.browser.argv.len - 1]);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "github.io") != null);
}

test "docs SKL_BROWSER argv uses that path" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.environ.put("SKL_BROWSER", "/tmp/skl-browser-stub");
    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const ctx = scenario.contextInteractive(false);
    try testing.expectEqual(@as(u8, 0), try docs.run(&ctx, .{ .query = "acme/skills" }));

    try testing.expectEqual(@as(usize, 2), scenario.browser.argv.len);
    try testing.expectEqualStrings("/tmp/skl-browser-stub", scenario.browser.argv[0]);
    try testing.expectEqualStrings("https://acme.github.io/skills/", scenario.browser.argv[1]);
}

test "docs menu is skipped when non-interactive without a name" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const ctx = scenario.context();
    try testing.expectError(error.Failed, docs.run(&ctx, .{}));
    try testing.expect(std.mem.indexOf(u8, scenario.fail.text(), "non-interactive") != null);
    try testing.expectEqual(@as(usize, 0), scenario.browser.opens);
}

test "docs missing clone still opens Pages when interactive" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );

    const ctx = scenario.contextInteractive(false);
    try testing.expectEqual(@as(u8, 0), try docs.run(&ctx, .{ .query = "acme/skills" }));
    try testing.expectEqual(@as(usize, 1), scenario.browser.opens);
    try testing.expectEqualStrings("https://acme.github.io/skills/", scenario.browser.argv[scenario.browser.argv.len - 1]);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "demo:hello") == null);
}

test "docs interactive menu selects by number then opens Pages" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );
    scenario.stdin_bytes = "1\n";
    const ctx = scenario.contextInteractive(false);
    try testing.expectEqual(@as(u8, 0), try docs.run(&ctx, .{}));
    try testing.expectEqual(@as(usize, 1), scenario.browser.opens);
    try testing.expectEqualStrings("https://acme.github.io/skills/", scenario.browser.argv[scenario.browser.argv.len - 1]);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "acme/skills") != null);
}

test "docs non-interactive does not open a browser" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    try scenario.writeProjectYaml(
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\
    );
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try docs.run(&ctx, .{ .query = "acme/skills" }));
    try testing.expectEqual(@as(usize, 0), scenario.browser.opens);
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "github.io") != null);
}

test "browserArgv uses SKL_BROWSER, xdg-open, open, and Windows start" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var with_browser = std.process.Environ.Map.init(allocator);
    try with_browser.put("SKL_BROWSER", "/bin/skl-browser");
    const from_env = try shared.browserArgv(allocator, &with_browser, "https://github.com/acme/skills", .linux);
    try testing.expectEqualStrings("/bin/skl-browser", from_env[0]);
    try testing.expectEqualStrings("https://github.com/acme/skills", from_env[1]);

    var empty = std.process.Environ.Map.init(allocator);
    const linux = try shared.browserArgv(allocator, &empty, "https://example.com/x", .linux);
    try testing.expectEqualStrings("xdg-open", linux[0]);

    const mac = try shared.browserArgv(allocator, &empty, "https://example.com/x", .macos);
    try testing.expectEqualStrings("open", mac[0]);

    const win = try shared.browserArgv(allocator, &empty, "https://example.com/x", .windows);
    try testing.expectEqual(@as(usize, 5), win.len);
    try testing.expectEqualStrings("cmd.exe", win[0]);
    try testing.expectEqualStrings("/C", win[1]);
    try testing.expectEqualStrings("start", win[2]);
    try testing.expectEqualStrings("", win[3]);
    try testing.expectEqualStrings("https://example.com/x", win[4]);
}

test "docs without config errors" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const ctx = scenario.context();
    try testing.expectError(error.Failed, docs.run(&ctx, .{ .query = "acme/skills" }));
    try testing.expectEqualStrings("No skl.yaml here; run skl init.", scenario.fail.text());
}

test "docs of a local row prints local and items from that tree" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const local = try scenario.writeLocalPackage("local-skills", "Local hello");
    const yaml = try std.fmt.allocPrint(scenario.allocator(),
        \\packages:
        \\  - repo: acme/skills
        \\    namespace: demo
        \\    local: {s}
        \\
    , .{local});
    try scenario.writeProjectYaml(yaml);

    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try docs.run(&ctx, .{ .query = "demo" }));
    const out = scenario.printed();
    try testing.expect(std.mem.indexOf(u8, out, "Local:") != null);
    try testing.expect(std.mem.indexOf(u8, out, local) != null);
    try testing.expect(std.mem.indexOf(u8, out, "demo:hello") != null);
}

test "docs of a branch row prints branch" {
    var scenario = try harness.Scenario.create();
    defer scenario.destroy();

    const init_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try init.run(&init_ctx, .{}));
    const add_ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try add.run(&add_ctx, .{
        .repo = "acme/skills",
        .namespace = "demo",
        .branch = "feature",
    }));

    scenario.clear();
    const ctx = scenario.context();
    try testing.expectEqual(@as(u8, 0), try docs.run(&ctx, .{ .query = "demo" }));
    try testing.expect(std.mem.indexOf(u8, scenario.printed(), "Branch: feature") != null);
}
