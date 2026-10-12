# Development

## Tools

`skl` is written in Zig. The Zig version is pinned in `mise.toml`, so install [mise](https://mise.jdx.dev/) and run:

```sh
mise install
```

You also need `git` installed.

## Building

```sh
zig build
```

This puts a debug build at `zig-out/bin/skl`.

`zig build release` builds the optimised binary (with Zig's safety checks kept on) and copies it to `bin/<arch>/<os>/skl` (`skl.exe` on Windows). That is the binary the release workflow ships.

## Code layout

- `src/main.zig` is the process itself: it takes the command line and returns the exit code.
- `src/cmd/` has one file per command (`add.zig`, `install.zig`, `update.zig` and so on), plus `shared.zig` for what several commands use.
- `src/lib/` has the logic that knows nothing about the command line: remotes, git, config, the store paths, linking, the YAML parser.
- `scripts/` has the smoke tests and the script that runs every test.

The coding rules (comment style, one job per file, how tests are wired) are in `CLAUDE.md`.

## Testing

Run everything (build, unit tests, smoke tests) with:

```sh
./scripts/test-everything.sh
```

It asks [what-changed](https://github.com/ashleydavis/what-changed) which targets (`compile`, `test`, `smoke`, listed in `what-changed.yaml`) have changed files since each last passed, runs only those, and records each target's baseline as it passes. Baselines live in `.what-changed/`, which is gitignored.

```sh
./scripts/test-everything.sh --plan    # print what would run, run nothing
./scripts/test-everything.sh --force   # run every target
```

### Unit tests

```sh
zig build test
```

Each code file has its tests in a file beside it: `src/lib/config.zig` is tested by `src/lib/config.test.zig`. The code file names its test file in a `test { ... }` block at the bottom; a test file that is not named there does not run.

### Smoke tests

```sh
./scripts/smoke-tests.sh
```

These run the real `skl` binary against real git repositories. Each scenario makes its own throwaway home directory, project directory and copies of the test repositories, so nothing touches your own setup or the network: clones of `git@github.com:...` are redirected to the local test repositories.

By default they run `zig-out/bin/skl`, so run `zig build` first. To test the release binary instead:

```sh
zig build release
./scripts/smoke-tests.sh --binary
```

Scenarios run in parallel lanes. `--jobs N` sets how many, and `--only <pattern>` runs every scenario whose name or title contains the pattern. Use a scenario's name (`sc31`) to run just that one:

```sh
./scripts/smoke-tests.sh --jobs 8
./scripts/smoke-tests.sh --only sc31
```

## CI

Every push runs `zig build` and `zig build test` on Linux, macOS and Windows (`.github/workflows/ci.yml`). The smoke tests run in the release workflow, against each shipped binary on its own OS.

## Releasing

See [Making a release](RELEASING.md).
