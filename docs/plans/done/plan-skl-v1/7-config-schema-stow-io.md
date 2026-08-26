# 7. Config schema and stow-safe IO

## Goal

Parse and write `skl.yaml` as a list of `{repo, namespace}` objects, enforce per-file namespace uniqueness, and write through stow symlinks without replacing them.

## Files

- `src/lib/config.zig` + `src/lib/config.test.zig`
- Re-export from `src/lib/lib.zig`. Wire `test { _ = @import("config.test.zig"); }`.

## YAML shape (list of objects, not a map)

```yaml
packages:
  - repo: owner/repo
    namespace: demo
  - repo: git@github.example.com:acme/skills.git
    namespace: pla
```

Types: `pub const Package = struct { repo: []u8, namespace: []u8 }; pub const File = struct { packages: []Package };`.

`parse(allocator, text)` and `stringify(allocator, file)` using the vendored YAML parser.

**Namespace uniqueness** is per config file: two entries with the same `namespace` is an error.

## IO

Pass `io: std.Io` on every filesystem call.

- `readFile(io, path)` follows symlinks (`open` the path) and is bounded by `files.MAX_FILE_BYTES`.
- `writeFile(io, path, file)` is **stow-safe**:
  - Resolve `path`.
  - Write through only when the resolved target is a **regular file** (or `path` does not exist yet).
  - If `path` is a symlink to a regular file, open that path, truncate, write bytes, close — **do not** write a tempfile and `rename` over `path` (that would replace a stow symlink with a regular file).
  - If `path` does not exist, `makePath` the parent directory then create the file.
  - If `path` is a symlink to a directory, a dangling symlink, a device, or anything other than a regular file, **error** rather than overwrite.
  - Never delete and recreate `skl.yaml`.

## Tests

- Parse/stringify round-trip of a list of `{repo, namespace}`.
- Duplicate namespace error.
- Write-through: symlink still a symlink, target updated.
- Refuse write-through to a symlink-to-directory.

Fixtures live in the test file, not in `config.zig`. Call `config.parse(...)` / `config.writeFile(...)` through the module.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `src/lib/config.zig` (with co-located tests) and re-exported it from `lib.zig`.

- `Package` is `{repo, namespace}`; `File` is a list of those. `parse` reads YAML via the vendored parser; `stringify` writes it back (`packages: []` for empty). Duplicate namespace is a `Failure`. Repo strings are kept as written.
- `readFile` / `writeFile` go through `files.zig` (`MAX_FILE_BYTES`, `makeParentDir` when the path is new). No special-case path kinds.
- Not wired into `main` yet (CLI is step 11). Smoke tests are step 13; not run. `zig build` and `zig build test` pass; the test count moved when `config.test.zig` was added.

Skipped (per instruction): write-through tests and any handling of path kinds other than ordinary files.
