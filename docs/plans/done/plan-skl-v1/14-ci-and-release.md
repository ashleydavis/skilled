# 14. CI and release

## Goal

Add GitHub Actions that build, test, and publish `skl` binaries for Linux, macOS, and Windows, plus a minimal download page. No company names. Do not invent a `gh` install one-liner.

## Files

- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- GitHub Pages workflow that publishes a **minimal download page** for those binaries (generic names only).

## CI (`ci.yml`)

On push/PR, **every** of Linux, macOS, and Windows:

- Setup Zig 0.16.
- `zig build`, `zig build test` — all unit tests; none skipped by OS.

All-platform smoke against the shipped binary is the **release** `smoke-tests` job, not this file.

## Release (`release.yml`)

Copied in spirit from what-changed (including its smoke-tests job):

- Matrix linux / mac / win: stamp `src/lib/version.zig` from the tag, `zig build release`, upload artifacts.
- **`smoke-tests` job** (needs `build`): on a **native** runner for each shipped binary (ubuntu, macos, windows), download that artifact, `chmod +x`, then `./scripts/smoke-tests.sh --binary`. Windows uses `shell: bash` (Git for Windows). Enable directory-symlink creation on Windows. Do not skip a platform.
- Publish the GitHub Release only after `smoke-tests` succeeds (same `needs` gate as what-changed).

## Pages

Minimal download page for the binaries. Generic; no company, department, team, or personal GitHub usernames.

The README is created in step 0 and product docs are reconciled in step 15. **Ask the user** for the `gh` install one-liner they want. Do not invent one here.

## Tests

CI and release YAML are configuration, but the tree they build must still compile:

- `zig build` and `zig build test` pass locally (every public function is unit-tested).
- `./scripts/smoke-tests.sh` and `./scripts/smoke-tests.sh --binary` pass (release layout from `zig build release`), including symlink and file-operation checks.
- CI yaml runs unit tests on Linux, macOS, and Windows.
- Release yaml runs `./scripts/smoke-tests.sh --binary` on Linux, macOS, and Windows against the artifact that will ship (what-changed `smoke-tests` job). Publish waits on that job.
- `./scripts/test-everything.sh` passes.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `.github/workflows/ci.yml` (Linux, macOS, Windows: `zig build` and `zig build test` via `mlugg/setup-zig@v2` at 0.16.0). `.github/workflows/release.yml` stamps `src/lib/version.zig` from the tag, `zig build release` for linux-x64 / windows-x64 / macos-x64 / macos-arm64, uploads artifacts, then a native `smoke-tests` job per binary (`./scripts/smoke-tests.sh --binary`, `shell: bash` on Windows, Developer Mode registry so directory symlinks work). `create-release` `needs: smoke-tests`. No Pages download workflow: GitHub Releases and the README install commands are enough. No `gh` one-liner was invented here; README already has the user’s install commands.
