Keep this file in sync with CLAUDE.md.

# Instructions for skilled (`skl`)

## Rules

- **This repository must not contain company, department, team, or other sensitive details.** No real org names, hostnames, repo names, Slack channels, or internal process. Examples use generic names (`acme`, `owner/repo`). Config that belongs to a real org lives in that org’s own repos, not here.
- **Document what this repo does.** Do not document absences, non-features, or things the project does not do. README, comments, and help text state actual behavior.
- **Do not put snapshot values in docs.** Test counts, file sizes, and other numbers that change with the next commit go stale. Docs describe durable behavior, not a figure that will be wrong tomorrow.
- You (Claude) wrote this entire repo and are responsible for everything in it. Never use these excuses:
  - "It's pre existing code"
  - "I didn't write it"
  - "It happened before this session"

## Tools

This project uses [mise](https://mise.jdx.dev/) to provide Zig and any other tools. Versions are pinned in `mise.toml`. After `mise install`, invoke them by name (`zig build`, `zig build test`).

## Git in test scripts

Fixture git in `scripts/smoke-tests.sh` may `init` / `add` / `commit` / `config` only inside `mktemp` dirs with `GIT_DIR` and `GIT_WORK_TREE` set to those dirs. After each, abort if `git rev-parse --show-toplevel` is not that throwaway path. Never run those commands against this checkout. `skl` itself is invoked with `GIT_DIR` and `GIT_WORK_TREE` unset. Each scenario gets its own throwaway `HOME`, project directory, and copy of the fixture remotes (`mktemp`), so scenarios can run concurrently and two `./scripts/smoke-tests.sh` invocations can overlap.

## Comments

Every `.zig` file starts with a fenced `//` comment that states the file's single responsibility, before any import or declaration. One job per file; the comment names that job.

```zig
//
// SSH clone specs turned into host, owner, and repo.
//
```

Every top-level declaration in a `.zig` file gets a comment above it, `pub` or not: functions, `const`, `var`, and every struct, enum, union and error set. Every struct field gets one too.

Say what it is for and why it is needed. Do not restate the type.

The style is `//` lines fenced by a blank `//` above and below, immediately before the declaration. Not `///`, and not a trailing comment on the same line.

```zig
//
// Where cloned packages live, resolved against the user's home directory.
//
// Resolved once here so a run cannot clone into one store and link from another.
//
store_dir: []const u8,
```

## Style

If-statement bodies are never on the same line as `if`. Put the body in braces on the following lines.

```zig
if (slice.len == 0) {
    return null;
}
```

Not `if (slice.len == 0) return null;`. An `if` used as a value (`return if (icons) mark else "OK"`) is an expression, not a statement body, and may stay on one line.

## Tests

Tests never live in the file they test. `src/lib/config.zig` is tested by `src/lib/config.test.zig`, beside it. Not idiomatic Zig, and deliberate: with tests inline, a diff of a code file does not say whether the code changed or only its tests did.

Nothing imports a `.test.zig` file, so the code file has to name it at the bottom, and that block is the only test wiring a code file holds:

```zig
test {
    _ = @import("config.test.zig");
}
```

Leave it out and the tests silently never run, while `zig build test` still passes. Check the test count moved when you add a test file. Each of these blocks counts as one test of its own.

Call through the module, `config.parse(...)` rather than a bare `parse(...)`.

Tests only reach `pub` declarations. Where a test needs something private, make it `pub` and say in its comment that the tests are why. Never copy the value into the test file: a copy keeps passing after the original changes.

Fixtures live in the test file that owns them and other test files import it. Never put a fixture in a code file.

Unit tests and smoke tests must be safe to run in parallel with themselves: Zig runs unit tests on multiple threads in one binary, two `zig build test` processes can overlap, and two smoke scripts can overlap. A test that only passes when it runs alone is a bug.

- Each unit test owns its memory, its `TestIo`, and (when it touches disk) a `TemporaryDir`. Never a fixed path such as `/tmp/skl-test`.
- Never `chdir`. Paths handed to the code under test are absolute (from `TemporaryDir` or a fake join).
- Never mutate the process environment. Pass a private `Environ.Map`.
- Never write into this checkout.
- Smoke tests: each scenario's `HOME`, project directory, and fixture remotes come from `mktemp`, and each scenario performs its own setup. A scenario that needs state another scenario left behind is a bug: the driver runs them in lanes that pull from a shared queue (`--jobs`, four by default) and any one of them runs alone with `--only`.

## Done means

`zig build`, `zig build test`, and `./scripts/smoke-tests.sh --binary` all pass.
